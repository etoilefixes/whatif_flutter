import 'dart:typed_data';

import '../models.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class BackendApi {
  String get baseUrl;
  set baseUrl(String value);

  bool get supportsBaseUrlOverride;
  bool get supportsProviderTesting;
  bool get supportsLocalWorldPkgBuild;
  String get modeLabel;

  Future<bool> checkHealth();

  Future<void> updateApiKeys(Map<String, String> keys);
  Future<void> testApiKey(String provider, String key);

  Future<LlmConfigMap> getLlmConfig();
  Future<void> updateLlmConfig(LlmConfigMap config);

  Future<WorldPkgListResponse> getWorldPkgs();
  Future<void> loadWorldPkg(String filename);
  Future<void> importWorldPkg(String filePath);
  Future<void> buildWorldPkgFromText(String filePath);
  Future<Uint8List?> getWorldPkgCover(String filename);

  Future<List<SaveInfo>> getSaves();
  Future<LoadGameResponse> loadGame(int slot);
  Future<String> saveGame(int slot, String description);
  Future<GameState> getGameState();
  Future<Uint8List?> getEventImage(String eventId);

  Future<List<VoiceInfo>> getVoices({String? locale});
  Future<String> segmentVoiceText(String text);

  Stream<SseEvent> startGameStream({
    String? lang,
    bool tts = false,
    String? voice,
  });

  Stream<SseEvent> continueGameStream({
    String? lang,
    bool tts = false,
    String? voice,
  });

  Stream<SseEvent> submitActionStream(
    String action, {
    String? lang,
    bool tts = false,
    String? voice,
  });

  void dispose();
}
