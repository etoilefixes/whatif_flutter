import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'backend_api_contract.dart';

class ApiClient implements BackendApi {
  ApiClient({String baseUrl = 'http://127.0.0.1:8000', http.Client? client})
    : _baseUrl = _normalizeBaseUrl(baseUrl),
      _client = client ?? http.Client();

  final http.Client _client;
  String _baseUrl;

  @override
  String get baseUrl => _baseUrl;

  @override
  set baseUrl(String value) {
    _baseUrl = _normalizeBaseUrl(value);
  }

  @override
  bool get supportsBaseUrlOverride => true;

  @override
  bool get supportsProviderTesting => true;

  @override
  bool get supportsLocalWorldPkgBuild => false;

  @override
  String get modeLabel => 'http';

  String getWorldPkgCoverUrl(String filename) {
    return '$_baseUrl/api/config/worldpkg/cover/$filename';
  }

  String getEventImageUrl(String eventId) {
    return '$_baseUrl/api/game/event-image/$eventId';
  }

  @override
  Future<bool> checkHealth() async {
    try {
      final response = await _client.get(_uri('/api/health'));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> updateApiKeys(Map<String, String> keys) async {
    await _request('/api/config/api-keys', method: 'PUT', body: {'keys': keys});
  }

  @override
  Future<void> testApiKey(String provider, String key) async {
    await _request(
      '/api/config/test-key',
      method: 'POST',
      body: {'provider': provider, 'key': key},
    );
  }

  @override
  Future<LlmConfigMap> getLlmConfig() async {
    final json = await _request('/api/config/llm');
    return LlmConfigMap.fromJson(json);
  }

  @override
  Future<void> updateLlmConfig(LlmConfigMap config) async {
    await _request('/api/config/llm', method: 'PUT', body: config.toJson());
  }

  @override
  Future<WorldPkgListResponse> getWorldPkgs() async {
    final json = await _request('/api/config/worldpkgs');
    return WorldPkgListResponse.fromJson(json);
  }

  @override
  Future<void> loadWorldPkg(String filename) async {
    await _request(
      '/api/config/worldpkg/load',
      method: 'POST',
      body: {'filename': filename},
    );
  }

  @override
  Future<void> importWorldPkg(String filePath) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/config/worldpkg/import'),
    )..files.add(await http.MultipartFile.fromPath('file', filePath));

    final response = await request.send();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(await _streamErrorMessage(response));
    }
  }

  @override
  Future<void> buildWorldPkgFromText(String filePath) async {
    throw const ApiException(
      'This backend mode does not support local text extraction.',
    );
  }

  @override
  Future<List<SaveInfo>> getSaves() async {
    final json = await _request('/api/game/saves');
    final saves = json['saves'] as List<dynamic>? ?? const [];
    return saves
        .whereType<Map<String, dynamic>>()
        .map(SaveInfo.fromJson)
        .toList();
  }

  @override
  Future<LoadGameResponse> loadGame(int slot) async {
    final json = await _request(
      '/api/game/load',
      method: 'POST',
      body: {'slot': slot},
    );
    return LoadGameResponse.fromJson(json);
  }

  @override
  Future<String> saveGame(int slot, String description) async {
    final json = await _request(
      '/api/game/save',
      method: 'POST',
      body: {'slot': slot, 'description': description},
    );
    return json['message'] as String? ?? 'Saved';
  }

  @override
  Future<GameState> getGameState() async {
    final json = await _request('/api/game/state');
    return GameState.fromJson(json);
  }

  @override
  Future<List<VoiceInfo>> getVoices({String? locale}) async {
    final json = await _request(
      '/api/voice/voices',
      queryParameters: locale == null || locale.isEmpty
          ? null
          : {'locale': locale},
    );
    final voices = json['voices'] as List<dynamic>? ?? const [];
    return voices
        .whereType<Map<String, dynamic>>()
        .map(VoiceInfo.fromJson)
        .toList();
  }

  @override
  Future<String> segmentVoiceText(String text) async {
    final json = await _request(
      '/api/voice/segment',
      method: 'POST',
      body: {'text': text},
    );
    return json['segmented'] as String? ?? text;
  }

  @override
  Stream<SseEvent> startGameStream({
    String? lang,
    bool tts = false,
    String? voice,
  }) {
    return _readSse(
      '/api/game/start',
      queryParameters: _gameQuery(lang: lang, tts: tts, voice: voice),
    );
  }

  @override
  Stream<SseEvent> continueGameStream({
    String? lang,
    bool tts = false,
    String? voice,
  }) {
    return _readSse(
      '/api/game/continue',
      queryParameters: _gameQuery(lang: lang, tts: tts, voice: voice),
    );
  }

  @override
  Stream<SseEvent> submitActionStream(
    String action, {
    String? lang,
    bool tts = false,
    String? voice,
  }) {
    return _readSse(
      '/api/game/action',
      body: {'action': action},
      queryParameters: _gameQuery(lang: lang, tts: tts, voice: voice),
    );
  }

  @override
  Future<Uint8List?> getWorldPkgCover(String filename) async {
    return _binaryRequest('/api/config/worldpkg/cover/$filename');
  }

  @override
  Future<Uint8List?> getEventImage(String eventId) async {
    return _binaryRequest('/api/game/event-image/$eventId');
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final request = http.Request(
      method,
      _uri(path, queryParameters: queryParameters),
    );
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final response = await _client.send(request);
    final responseBody = await response.stream.bytesToString();
    final jsonBody = responseBody.isEmpty ? null : jsonDecode(responseBody);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_errorMessage(response.statusCode, jsonBody));
    }

    if (jsonBody is Map<String, dynamic>) {
      return jsonBody;
    }

    return {};
  }

  Future<Uint8List?> _binaryRequest(String path) async {
    final response = await _client.get(_uri(path));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 404) {
        return null;
      }
      throw ApiException('HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Stream<SseEvent> _readSse(
    String path, {
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
  }) async* {
    final request = http.Request(
      'POST',
      _uri(path, queryParameters: queryParameters),
    )..headers['Content-Type'] = 'application/json';

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(await _streamErrorMessage(response));
    }

    String? eventType;
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.startsWith('event: ')) {
        eventType = line.substring(7).trim();
        continue;
      }

      if (!line.startsWith('data: ') || eventType == null) {
        continue;
      }

      final payload = line.substring(6);
      final decoded = payload.isEmpty ? null : jsonDecode(payload);

      switch (eventType) {
        case 'chunk':
          final text =
              (decoded as Map<String, dynamic>)['text'] as String? ?? '';
          yield SseEvent.chunk(text);
          break;
        case 'audio':
          final json = decoded as Map<String, dynamic>;
          yield SseEvent.audio(
            json['audio'] as String? ?? '',
            (json['index'] as num?)?.toInt() ?? 0,
          );
          break;
        case 'state':
          yield SseEvent.state(
            GameStateData.fromJson(decoded as Map<String, dynamic>),
          );
          break;
        case 'error':
          final message =
              (decoded as Map<String, dynamic>)['message'] as String? ??
              'Unknown error';
          yield SseEvent.error(message);
          break;
        case 'done':
          yield const SseEvent.done();
          break;
      }

      eventType = null;
    }
  }

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    final base = Uri.parse(_baseUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final mergedPath = '${base.path}$normalizedPath';
    return base.replace(
      path: mergedPath,
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
  }

  Map<String, String> _gameQuery({
    String? lang,
    bool tts = false,
    String? voice,
  }) {
    final query = <String, String>{};

    if (tts) {
      query['tts'] = 'true';
      if (voice != null && voice.isNotEmpty) {
        query['voice'] = voice;
      }
    }

    if (lang != null && lang.isNotEmpty) {
      query['lang'] = lang;
    }

    return query;
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'http://127.0.0.1:8000';
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  String _errorMessage(int statusCode, Object? body) {
    if (body is Map<String, dynamic>) {
      final detail = body['detail']?.toString();
      if (detail != null && detail.isNotEmpty) {
        return detail;
      }
      final message = body['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
    return 'HTTP $statusCode';
  }

  Future<String> _streamErrorMessage(http.StreamedResponse response) async {
    final body = await response.stream.bytesToString();
    if (body.isEmpty) {
      return 'HTTP ${response.statusCode}';
    }

    try {
      final decoded = jsonDecode(body);
      return _errorMessage(response.statusCode, decoded);
    } catch (_) {
      return body;
    }
  }

  @override
  void dispose() {
    _client.close();
  }
}
