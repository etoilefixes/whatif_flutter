import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'backend_api_contract.dart';
import 'provider_api_utils.dart';

class IntegratedLlmClient {
  IntegratedLlmClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  bool supportsProvider(String provider, {String? apiBase}) {
    return (apiBase != null && apiBase.trim().isNotEmpty) ||
        ModelProvider.usesManagedApiUrl(provider);
  }

  Future<void> testProvider(
    String provider,
    String apiKey, {
    String? apiBase,
    String? model,
  }) async {
    if (!supportsProvider(provider, apiBase: apiBase)) {
      throw ApiException(
        'Integrated backend does not support provider "$provider" yet.',
      );
    }

    await completeChat(
      provider: provider,
      apiKey: apiKey,
      model: model ?? _defaultTestModel(provider),
      temperature: 0,
      apiBase: apiBase,
      messages: const <Map<String, String>>[
        <String, String>{
          'role': 'system',
          'content': 'Reply with OK and nothing else.',
        },
        <String, String>{'role': 'user', 'content': 'ping'},
      ],
    );
  }

  Future<void> testModelProvider(ModelProvider provider) async {
    final model = provider.models.isNotEmpty
        ? provider.models.first
        : _defaultTestModel(provider.name);
    await testProvider(
      provider.name,
      provider.apiKey,
      apiBase: provider.apiUrl,
      model: model,
    );
  }

  Future<String> completeChat({
    required String provider,
    required String apiKey,
    required String model,
    required double temperature,
    required List<Map<String, String>> messages,
    String? apiBase,
    Map<String, dynamic> extraParams = const <String, dynamic>{},
  }) async {
    final endpointBases = resolveProviderApiBaseCandidates(
      provider: provider,
      customApiUrl: apiBase,
    );
    if (endpointBases.isEmpty) {
      throw ApiException(
        'Integrated backend does not support provider "$provider" yet.',
      );
    }

    ApiException? lastError;
    final providerKey = ModelProvider.canonicalProviderName(provider);
    for (var index = 0; index < endpointBases.length; index += 1) {
      final endpointBase = endpointBases[index];
      final usesAnthropicMessagesApi = _usesAnthropicMessagesApi(
        provider,
        endpointBase,
      );
      final uri = Uri.parse(
        usesAnthropicMessagesApi
            ? '$endpointBase/messages'
            : '$endpointBase/chat/completions',
      );
      final body = _buildRequestBody(
        provider: provider,
        model: model,
        temperature: temperature,
        messages: messages,
        extraParams: extraParams,
        usesAnthropicMessagesApi: usesAnthropicMessagesApi,
      );

      final response = await _client.post(
        uri,
        headers: buildProviderHeaders(provider: provider, apiKey: apiKey),
        body: jsonEncode(body),
      );

      final responseText = response.body;
      final decoded = _tryDecodeResponseBody(responseText);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (providerKey == 'nvidia' &&
            _shouldRecoverNvidiaRequest(
              response.statusCode,
              decoded,
              responseText,
            )) {
          final recovered = await _recoverNvidiaRequest(
            endpointBase: endpointBase,
            apiKey: apiKey,
            requestedModel: model,
            temperature: temperature,
            messages: messages,
            extraParams: extraParams,
          );
          if (recovered != null) {
            return recovered.content;
          }
        }

        lastError = ApiException(
          _errorMessage(
            response.statusCode,
            decoded,
            rawBody: responseText,
            requestUrl: uri.toString(),
          ),
        );
        if (_shouldRetryWithFallback(response.statusCode, responseText) &&
            index < endpointBases.length - 1) {
          continue;
        }
        throw lastError;
      }

      if (decoded is! Map<String, dynamic>) {
        throw const ApiException(
          'The model provider returned an empty response.',
        );
      }

      if (usesAnthropicMessagesApi) {
        return _messageContent(<String, dynamic>{
          'content': decoded['content'],
        });
      }

      final choices = decoded['choices'];
      if (choices is! List<dynamic> || choices.isEmpty) {
        throw const ApiException('The model provider returned no choices.');
      }

      final firstChoice = choices.first;
      if (firstChoice is! Map<String, dynamic>) {
        throw const ApiException(
          'The model provider returned an invalid choice.',
        );
      }

      final message = firstChoice['message'];
      if (message is! Map<String, dynamic>) {
        throw const ApiException(
          'The model provider returned an invalid message.',
        );
      }

      return _messageContent(message);
    }

    throw lastError ??
        const ApiException('The model provider request did not complete.');
  }

  Map<String, dynamic> _buildRequestBody({
    required String provider,
    required String model,
    required double temperature,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> extraParams,
    required bool usesAnthropicMessagesApi,
  }) {
    if (!usesAnthropicMessagesApi) {
      return <String, dynamic>{
        'model': _normalizeModelId(provider, model),
        'messages': messages,
        'temperature': temperature,
        ...extraParams,
      };
    }

    final extra = Map<String, dynamic>.from(extraParams);
    final maxTokensValue = extra.remove('max_tokens');
    final maxTokens = switch (maxTokensValue) {
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };

    final body = <String, dynamic>{
      'model': _normalizeModelId(provider, model),
      'messages': _anthropicMessages(messages),
      'temperature': temperature,
      'max_tokens': maxTokens ?? 256,
      ...extra,
    };

    final systemPrompt = _anthropicSystemPrompt(messages);
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system'] = systemPrompt;
    }
    return body;
  }

  String _normalizeModelId(String provider, String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final providerKey = ModelProvider.canonicalProviderName(provider);
    final slash = trimmed.indexOf('/');
    if (slash <= 0) {
      return trimmed;
    }

    final prefix = trimmed.substring(0, slash).toLowerCase();
    if (prefix == providerKey) {
      final remainder = trimmed.substring(slash + 1);
      if ((providerKey == 'nvidia' || providerKey == 'siliconflow') &&
          !remainder.contains('/')) {
        return trimmed;
      }
      return remainder;
    }

    return trimmed;
  }

  Future<_RecoveredChatResult?> _recoverNvidiaRequest({
    required String endpointBase,
    required String apiKey,
    required String requestedModel,
    required double temperature,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> extraParams,
  }) async {
    final modelsUri = Uri.parse('$endpointBase/models');
    final modelsResponse = await _client.get(
      modelsUri,
      headers: buildProviderHeaders(provider: 'nvidia', apiKey: apiKey),
    );
    final modelsBody = modelsResponse.body;
    final decodedModels = _tryDecodeResponseBody(modelsBody);

    if (modelsResponse.statusCode < 200 || modelsResponse.statusCode >= 300) {
      throw ApiException(
        'NVIDIA API returned HTTP ${modelsResponse.statusCode} when probing '
        '$modelsUri. Please make sure you are using an API Catalog key from '
        'build.nvidia.com, not an NGC or other NVIDIA key.',
      );
    }

    final availableModels = parseModelIdsFromResponse(decodedModels);
    if (availableModels.isEmpty) {
      throw ApiException(
        'NVIDIA API returned no models from $modelsUri. Please confirm your '
        'Build NVIDIA account has access to at least one chat model.',
      );
    }

    final normalizedRequested = _normalizeModelId('nvidia', requestedModel);
    final retryModel = availableModels.firstWhere(
      (candidate) => candidate.trim() != normalizedRequested,
      orElse: () => availableModels.first,
    );

    if (retryModel == normalizedRequested) {
      throw ApiException(
        'NVIDIA API still rejected the resolved model "$retryModel". '
        'If this is a third-party model like meta/*, open it once on '
        'build.nvidia.com and complete any required acknowledgement.',
      );
    }

    final retryUri = Uri.parse('$endpointBase/chat/completions');
    final retryBody = _buildRequestBody(
      provider: 'nvidia',
      model: retryModel,
      temperature: temperature,
      messages: messages,
      extraParams: extraParams,
      usesAnthropicMessagesApi: false,
    );
    final retryResponse = await _client.post(
      retryUri,
      headers: buildProviderHeaders(provider: 'nvidia', apiKey: apiKey),
      body: jsonEncode(retryBody),
    );
    final retryResponseText = retryResponse.body;
    final retryDecoded = _tryDecodeResponseBody(retryResponseText);
    if (retryResponse.statusCode < 200 || retryResponse.statusCode >= 300) {
      throw ApiException(
        _errorMessage(
          retryResponse.statusCode,
          retryDecoded,
          rawBody: retryResponseText,
          requestUrl: retryUri.toString(),
        ),
      );
    }

    if (retryDecoded is! Map<String, dynamic>) {
      throw const ApiException(
        'The model provider returned an empty response.',
      );
    }

    final choices = retryDecoded['choices'];
    if (choices is! List<dynamic> || choices.isEmpty) {
      throw const ApiException('The model provider returned no choices.');
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw const ApiException(
        'The model provider returned an invalid choice.',
      );
    }

    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw const ApiException(
        'The model provider returned an invalid message.',
      );
    }

    return _RecoveredChatResult(content: _messageContent(message));
  }

  bool _shouldRetryWithFallback(int statusCode, String rawBody) {
    if (statusCode != 404) {
      return false;
    }
    final normalized = rawBody.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized.contains('page not found') ||
        normalized.contains('404');
  }

  bool _shouldRecoverNvidiaRequest(
    int statusCode,
    Object? decodedBody,
    String rawBody,
  ) {
    if (statusCode == 404) {
      return true;
    }

    final normalizedRaw = rawBody.trim().toLowerCase();
    if (normalizedRaw.contains('not found for account') ||
        normalizedRaw.contains('function')) {
      return true;
    }

    if (decodedBody is! Map<String, dynamic>) {
      return false;
    }

    final detail =
        decodedBody['detail']?.toString().toLowerCase() ??
        decodedBody['message']?.toString().toLowerCase() ??
        '';
    return detail.contains('not found for account') ||
        detail.contains('function');
  }

  bool _usesAnthropicMessagesApi(String provider, String endpointBase) {
    if (provider.toLowerCase() != 'anthropic') {
      return false;
    }
    final uri = Uri.parse(endpointBase);
    return uri.host.toLowerCase() == 'api.anthropic.com';
  }

  String? _anthropicSystemPrompt(List<Map<String, String>> messages) {
    final systemMessages = messages
        .where((message) => (message['role'] ?? '').trim() == 'system')
        .map((message) => (message['content'] ?? '').trim())
        .where((content) => content.isNotEmpty)
        .toList();
    if (systemMessages.isEmpty) {
      return null;
    }
    return systemMessages.join('\n\n');
  }

  List<Map<String, String>> _anthropicMessages(
    List<Map<String, String>> messages,
  ) {
    final converted = <Map<String, String>>[];
    for (final message in messages) {
      final role = (message['role'] ?? 'user').trim();
      final content = (message['content'] ?? '').trim();
      if (content.isEmpty || role == 'system') {
        continue;
      }
      converted.add(<String, String>{
        'role': role == 'assistant' ? 'assistant' : 'user',
        'content': content,
      });
    }

    if (converted.isEmpty) {
      converted.add(const <String, String>{'role': 'user', 'content': 'ping'});
    }
    return converted;
  }

  String _messageContent(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is String) {
      return content.trim();
    }
    if (content is List<dynamic>) {
      final text = content
          .whereType<Map<String, dynamic>>()
          .map((item) => item['text']?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .join('\n');
      return text.trim();
    }
    throw const ApiException('The model provider returned empty content.');
  }

  Object? _tryDecodeResponseBody(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(rawBody);
    } catch (_) {
      return null;
    }
  }

  String _errorMessage(
    int statusCode,
    Object? body, {
    String? rawBody,
    String? requestUrl,
  }) {
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return requestUrl == null ? message : '$message [$requestUrl]';
        }
      }

      final message = body['message']?.toString() ?? body['detail']?.toString();
      if (message != null && message.isNotEmpty) {
        return requestUrl == null ? message : '$message [$requestUrl]';
      }
    }

    final plainText = rawBody?.trim() ?? '';
    if (plainText.isNotEmpty) {
      final compact = plainText.replaceAll(RegExp(r'\s+'), ' ');
      final end = compact.length > 200 ? 200 : compact.length;
      final urlText = requestUrl == null ? '' : ' [$requestUrl]';
      return 'HTTP $statusCode$urlText: ${compact.substring(0, end)}';
    }

    return requestUrl == null
        ? 'HTTP $statusCode'
        : 'HTTP $statusCode [$requestUrl]';
  }

  String _defaultTestModel(String provider) {
    final suggestedModels = ModelProvider.suggestedModelsFor(provider);
    if (suggestedModels.isNotEmpty) {
      return suggestedModels.first;
    }
    return 'gpt-4o-mini';
  }

  void dispose() {
    _client.close();
  }
}

class _RecoveredChatResult {
  const _RecoveredChatResult({required this.content});

  final String content;
}
