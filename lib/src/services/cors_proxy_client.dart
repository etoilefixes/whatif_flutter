import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider_api_utils.dart';

class CorsProxyClient {
  CorsProxyClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _publicCorsProxy = 'https://corsproxy.io/?';

  Future<Object?> fetchModels({
    required String provider,
    required String apiKey,
    String? customApiUrl,
    String? corsProxyUrl,
  }) async {
    final modelsUrl = buildProviderModelsUrl(
      provider: provider,
      customApiUrl: customApiUrl,
    );
    final uri = _buildProxyUrl(modelsUrl, corsProxyUrl);

    final response = await _client
        .get(
          Uri.parse(uri),
          headers: buildProviderHeaders(provider: provider, apiKey: apiKey),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Authentication failed. Please verify the API key.');
    } else if (response.statusCode == 404) {
      throw Exception('Endpoint not found: $modelsUrl');
    } else {
      throw Exception(
        'HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}',
      );
    }
  }

  String _buildProxyUrl(String targetUrl, String? customProxy) {
    final proxyUrl = customProxy?.trim().isNotEmpty == true
        ? customProxy!.trim()
        : _publicCorsProxy;

    if (proxyUrl == _publicCorsProxy) {
      return '$proxyUrl${Uri.encodeComponent(targetUrl)}';
    }

    return '$proxyUrl${Uri.encodeComponent(targetUrl)}';
  }

  void dispose() {
    _client.close();
  }
}
