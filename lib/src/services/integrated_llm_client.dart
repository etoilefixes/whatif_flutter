import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'backend_api_contract.dart';
import 'provider_api_utils.dart';

class IntegratedLlmClient {
  IntegratedLlmClient({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const Map<String, String> _defaultBaseUrls = <String, String>{
    'openai': 'https://api.openai.com/v1',
    'dashscope': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'anthropic': 'https://api.anthropic.com/v1',
    'gemini': 'https://generativelanguage.googleapis.com/v1beta/openai',
    'volcengine': 'https://ark.cn-beijing.volces.com/api/v3',
  };

  static const Map<String, String> _defaultTestModels = <String, String>{
    'openai': 'gpt-4o-mini',
    'dashscope': 'qwen3.5-flash',
    'anthropic': 'claude-sonnet-4-20250514',
    'gemini': 'gemini-2.0-flash',
    'volcengine': 'doubao-1-5-pro-32k-250115',
  };

  bool supportsProvider(String provider, {String? apiBase}) {
    return (apiBase != null && apiBase.trim().isNotEmpty) ||
        _defaultBaseUrls.containsKey(provider.toLowerCase());
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
      model:
          model ?? _defaultTestModels[provider.toLowerCase()] ?? 'gpt-4o-mini',
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
    final apiBase = provider.apiUrl?.trim().isNotEmpty == true
        ? provider.apiUrl!.trim()
        : _defaultBaseUrls[provider.name.toLowerCase()];
    final model = provider.models.isNotEmpty
        ? provider.models.first
        : _defaultTestModels[provider.name.toLowerCase()] ?? 'gpt-4o-mini';
    await testProvider(
      provider.name,
      provider.apiKey,
      apiBase: apiBase,
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

    final uri = Uri.parse('$endpointBase/chat/completions');
    final body = <String, dynamic>{
      'model': _stripProviderPrefix(model),
      'messages': messages,
      'temperature': temperature,
      ...extraParams,
    };

    final response = await _client.post(
      uri,
      headers: buildProviderHeaders(provider: provider, apiKey: apiKey),
      body: jsonEncode(body),
    );

    final responseText = response.body;
    final decoded = responseText.isEmpty ? null : jsonDecode(responseText);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_errorMessage(response.statusCode, decoded));
    }

    if (decoded is! Map<String, dynamic>) {
      throw const ApiException(
        'The model provider returned an empty response.',
      );
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

  String _stripProviderPrefix(String model) {
    final slash = model.indexOf('/');
    return slash >= 0 ? model.substring(slash + 1) : model;
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

  String _errorMessage(int statusCode, Object? body) {
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

    return 'HTTP $statusCode';
  }

  void dispose() {
    _client.close();
  }
}
