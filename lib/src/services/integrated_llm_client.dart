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
    final endpointBase = resolveProviderApiBase(
      provider: provider,
      customApiUrl: apiBase,
    );
    if (endpointBase == null) {
      throw ApiException(
        'Integrated backend does not support provider "$provider" yet.',
      );
    }

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
      throw ApiException(
        _errorMessage(response.statusCode, decoded, rawBody: responseText),
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(
        'The model provider returned an empty response.',
      );
    }

    if (usesAnthropicMessagesApi) {
      return _messageContent(<String, dynamic>{'content': decoded['content']});
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

  Map<String, dynamic> _buildRequestBody({
    required String model,
    required double temperature,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> extraParams,
    required bool usesAnthropicMessagesApi,
  }) {
    if (!usesAnthropicMessagesApi) {
      return <String, dynamic>{
        'model': _stripProviderPrefix(model),
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
      'model': _stripProviderPrefix(model),
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

  String _stripProviderPrefix(String model) {
    final slash = model.indexOf('/');
    return slash >= 0 ? model.substring(slash + 1) : model;
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

  String _errorMessage(int statusCode, Object? body, {String? rawBody}) {
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }

      final message = body['message']?.toString() ?? body['detail']?.toString();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }

    final plainText = rawBody?.trim() ?? '';
    if (plainText.isNotEmpty) {
      final compact = plainText.replaceAll(RegExp(r'\s+'), ' ');
      final end = compact.length > 200 ? 200 : compact.length;
      return 'HTTP $statusCode: ${compact.substring(0, end)}';
    }

    return 'HTTP $statusCode';
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
