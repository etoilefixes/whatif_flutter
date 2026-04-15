import 'dart:typed_data';

import '../models.dart';
import 'backend_api_contract.dart';
import 'config_store.dart';

/// Web 平台的集成模式 API 实现
/// 
/// 由于 Web 平台无法访问本地文件系统，这是一个简化版本，
/// 主要用于演示 UI，不依赖 HTTP 后端。
class WebBackendApi implements BackendApi {
  WebBackendApi._({required this.store});

  final ConfigStore store;
  final List<ModelProvider> _providers = [];
  LlmConfigMap? _llmConfig;

  static Future<WebBackendApi> create({required ConfigStore store}) async {
    final api = WebBackendApi._(store: store);
    // 从 store 加载已保存的提供商
    final savedProviders = store.getModelProviders();
    api._providers.addAll(savedProviders);
    return api;
  }

  @override
  String get baseUrl => 'integrated-web';

  @override
  set baseUrl(String value) {
    // Web 集成模式忽略 baseUrl 设置
  }

  @override
  bool get supportsBaseUrlOverride => false;

  @override
  bool get supportsProviderTesting => false;

  @override
  bool get supportsLocalWorldPkgBuild => false;

  @override
  String get modeLabel => 'integrated-web';

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> updateModelProviders(List<ModelProvider> providers) async {
    _providers.clear();
    _providers.addAll(providers);
    await store.setModelProviders(providers);
  }

  @override
  Future<void> testModelProvider(ModelProvider provider) async {
    // Web 平台模拟测试成功
    // 实际 API 调用在 Web 平台受 CORS 限制，这里仅验证配置格式
    if (provider.apiKey.isEmpty) {
      throw Exception('API Key 不能为空');
    }
    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 500));
    // 返回成功（实际生产环境应该通过后端代理测试）
  }

  @override
  Future<LlmConfigMap> getLlmConfig() async {
    if (_llmConfig != null) return _llmConfig!;
    
    // 返回默认配置
    return LlmConfigMap(
      extractors: {
        'event_extractor': LlmSlotConfig(
          model: 'gpt-4o-mini',
          temperature: 0.3,
          thinkingBudget: 0,
        ),
        'lorebook_extractor': LlmSlotConfig(
          model: 'gpt-4o-mini',
          temperature: 0.3,
          thinkingBudget: 0,
        ),
      },
      agents: {
        'setup_orchestrator': LlmSlotConfig(
          model: 'gpt-4o',
          temperature: 0.7,
          thinkingBudget: 0,
        ),
        'confrontation_orchestrator': LlmSlotConfig(
          model: 'gpt-4o',
          temperature: 0.7,
          thinkingBudget: 0,
        ),
        'resolution_orchestrator': LlmSlotConfig(
          model: 'gpt-4o',
          temperature: 0.7,
          thinkingBudget: 0,
        ),
      },
    );
  }

  @override
  Future<void> updateLlmConfig(LlmConfigMap config) async {
    _llmConfig = config;
    await store.setLlmConfig(config);
  }

  @override
  Future<WorldPkgListResponse> getWorldPkgs() async {
    // Web 平台返回空列表
    return WorldPkgListResponse(packages: [], current: null);
  }

  @override
  Future<void> loadWorldPkg(String filename) async {
    // Web 平台不支持
  }

  @override
  Future<void> importWorldPkg(String filePath) async {
    throw UnsupportedError('Import is not supported on Web platform');
  }

  @override
  Future<void> buildWorldPkgFromText(String filePath) async {
    throw UnsupportedError('Build from text is not supported on Web platform');
  }

  @override
  Future<Uint8List?> getWorldPkgCover(String filename) async => null;

  @override
  Future<List<SaveInfo>> getSaves() async => [];

  @override
  Future<LoadGameResponse> loadGame(int slot) async {
    throw UnsupportedError('Load game is not supported on Web platform');
  }

  @override
  Future<String> saveGame(int slot, String description) async {
    throw UnsupportedError('Save game is not supported on Web platform');
  }

  @override
  Future<GameState> getGameState() async {
    return GameState(
      phase: null,
      event: null,
      turn: 0,
      playerName: null,
      awaitingNextEvent: false,
      gameEnded: false,
    );
  }

  @override
  Future<Uint8List?> getEventImage(String eventId) async => null;

  @override
  Future<List<VoiceInfo>> getVoices({String? locale}) async => [];

  @override
  Future<String> segmentVoiceText(String text) async => text;

  @override
  Stream<SseEvent> startGameStream({
    String? lang,
    bool tts = false,
    String? voice,
  }) async* {
    throw UnsupportedError('Game streaming is not supported on Web platform');
  }

  @override
  Stream<SseEvent> continueGameStream({
    String? lang,
    bool tts = false,
    String? voice,
  }) async* {
    throw UnsupportedError('Game streaming is not supported on Web platform');
  }

  @override
  Stream<SseEvent> submitActionStream(
    String action, {
    String? lang,
    bool tts = false,
    String? voice,
  }) async* {
    throw UnsupportedError('Game streaming is not supported on Web platform');
  }

  @override
  void dispose() {
    // 无需清理
  }
}
