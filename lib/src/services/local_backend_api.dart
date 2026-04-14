import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models.dart';
import 'backend_api_contract.dart';
import 'config_store.dart';
import 'integrated_llm_client.dart';
import 'local_backend_paths.dart';
import 'local_bridge_planner.dart';
import 'local_deviation_agent.dart';
import 'local_game_engine.dart';
import 'local_memory_compression.dart';
import 'local_narrative_generator.dart';
import 'local_scene_adaptation.dart';
import 'local_tts_speaker.dart';
import 'local_worldpkg.dart';
import 'local_worldpkg_builder.dart';
import 'local_worldpkg_extraction_enhancer.dart';

class LocalBackendApi implements BackendApi {
  LocalBackendApi._({
    required this.store,
    required this.paths,
    required LocalGameEngine engine,
    required this.llmClient,
    required this.narrativeGenerator,
    required this.worldPkgBuilder,
  }) : _engine = engine;

  final ConfigStore store;
  final LocalBackendPaths paths;
  final LocalGameEngine _engine;
  final IntegratedLlmClient llmClient;
  final LocalNarrativeGenerator narrativeGenerator;
  final LocalWorldPkgBuilder worldPkgBuilder;
  LocalTtsSpeaker? _ttsSpeaker;
  LocalTtsSpeaker get ttsSpeaker => _ttsSpeaker ??= LocalTtsSpeaker();

  final Map<String, LocalWorldPkg> _packages = <String, LocalWorldPkg>{};
  LlmConfigMap? _defaultLlmConfig;

  static Future<LocalBackendApi> create({
    required ConfigStore store,
    LocalBackendPaths? paths,
  }) async {
    final resolvedPaths = paths ?? await LocalBackendPaths.resolve();
    await resolvedPaths.ensureReady();
    final llmClient = IntegratedLlmClient();
    late final LocalBackendApi backend;
    final narrativeGenerator = LocalNarrativeGenerator(
      store: store,
      paths: resolvedPaths,
      llmClient: llmClient,
      loadConfig: () => backend.getLlmConfig(),
    );
    final deviationAgent = LocalDeviationAgent(
      store: store,
      llmClient: llmClient,
      loadConfig: () => backend.getLlmConfig(),
    );
    final memoryCompression = LocalMemoryCompressionManager(
      store: store,
      llmClient: llmClient,
      loadConfig: () => backend.getLlmConfig(),
    );
    final bridgePlanner = LocalBridgePlanner(
      store: store,
      llmClient: llmClient,
      loadConfig: () => backend.getLlmConfig(),
    );
    final sceneAdaptationPlanner = LocalSceneAdaptationPlanner(
      store: store,
      llmClient: llmClient,
      loadConfig: () => backend.getLlmConfig(),
    );
    final engine = LocalGameEngine(
      savesDir: resolvedPaths.savesDir,
      narrativeGenerator: narrativeGenerator,
      deviationAgent: deviationAgent,
      memoryCompression: memoryCompression,
      bridgePlanner: bridgePlanner,
      sceneAdaptationPlanner: sceneAdaptationPlanner,
    );
    final extractionEnhancer = LocalLlmWorldPkgExtractionEnhancer(
      store: store,
      llmClient: llmClient,
      loadConfig: () => backend.getLlmConfig(),
    );
    final worldPkgBuilder = LocalWorldPkgBuilder(
      outputDir: resolvedPaths.outputDir,
      extractionEnhancer: extractionEnhancer,
    );
    backend = LocalBackendApi._(
      store: store,
      paths: resolvedPaths,
      engine: engine,
      llmClient: llmClient,
      narrativeGenerator: narrativeGenerator,
      worldPkgBuilder: worldPkgBuilder,
    );
    return backend;
  }

  @override
  String get baseUrl => 'local://integrated';

  @override
  set baseUrl(String value) {}

  @override
  bool get supportsBaseUrlOverride => false;

  @override
  bool get supportsProviderTesting => true;

  @override
  bool get supportsLocalWorldPkgBuild => true;

  @override
  String get modeLabel => 'integrated-dart';

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> updateApiKeys(Map<String, String> keys) async {}

  @override
  Future<void> testApiKey(String provider, String key) async {
    await narrativeGenerator.testProvider(provider, key);
  }

  @override
  Future<LlmConfigMap> getLlmConfig() async {
    final fromStore = store.getLlmConfig();
    if (fromStore != null) {
      return fromStore;
    }

    if (_defaultLlmConfig != null) {
      return _defaultLlmConfig!;
    }

    final file = paths.llmConfigFile;
    if (file == null || !file.existsSync()) {
      throw const ApiException('Local model configuration is unavailable.');
    }

    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) {
      throw const ApiException('Unable to parse local llm_config.yaml.');
    }

    Map<String, LlmSlotConfig> parseSection(String key) {
      final section = yaml[key];
      if (section is! YamlMap) {
        return <String, LlmSlotConfig>{};
      }

      final parsed = <String, LlmSlotConfig>{};
      for (final entry in section.entries) {
        final name = entry.key?.toString() ?? '';
        final value = entry.value;
        if (name.isEmpty || value is! YamlMap) {
          continue;
        }
        parsed[name] = LlmSlotConfig(
          model: value['model']?.toString() ?? '',
          temperature: (value['temperature'] as num?)?.toDouble() ?? 0.2,
          thinkingBudget: (value['thinking_budget'] as num?)?.toInt() ?? 0,
          apiBase: value['api_base']?.toString(),
          extraParams: _yamlMapToJsonMap(value['extra_params']),
        );
      }
      return parsed;
    }

    _defaultLlmConfig = LlmConfigMap(
      extractors: parseSection('extractors'),
      agents: parseSection('agents'),
    );
    return _defaultLlmConfig!;
  }

  @override
  Future<void> updateLlmConfig(LlmConfigMap config) async {}

  @override
  Future<WorldPkgListResponse> getWorldPkgs() async {
    await _scanPackages();
    final packages = _packages.values.map((pkg) => pkg.toInfo()).toList()
      ..sort((left, right) => left.name.compareTo(right.name));

    return WorldPkgListResponse(
      packages: packages,
      current: _engine.currentWorldTitle,
    );
  }

  @override
  Future<void> loadWorldPkg(String filename) async {
    final pkg = await _ensurePackage(filename);
    _engine.setWorld(pkg);
  }

  @override
  Future<void> importWorldPkg(String filePath) async {
    final source = File(filePath);
    if (!source.existsSync() ||
        p.extension(source.path).toLowerCase() != '.wpkg') {
      throw const ApiException('Only .wpkg files can be imported.');
    }

    await paths.outputDir.create(recursive: true);
    final target = File(p.join(paths.outputDir.path, p.basename(source.path)));
    if (target.existsSync()) {
      throw const ApiException(
        'A world package with the same filename already exists.',
      );
    }

    await source.copy(target.path);
    _packages.remove(p.basename(target.path));
  }

  @override
  Future<void> buildWorldPkgFromText(String filePath) async {
    final builtFile = await worldPkgBuilder.buildFromTextFile(filePath);
    _packages.remove(p.basename(builtFile.path));
    await _scanPackages();
  }

  @override
  Future<Uint8List?> getWorldPkgCover(String filename) async {
    final pkg = await _ensurePackage(filename);
    return pkg.getCoverBytes();
  }

  @override
  Future<List<SaveInfo>> getSaves() {
    return _engine.listSaves();
  }

  @override
  Future<LoadGameResponse> loadGame(int slot) {
    return _engine.loadGame(slot);
  }

  @override
  Future<String> saveGame(int slot, String description) {
    return _engine.saveGame(slot, description);
  }

  @override
  Future<GameState> getGameState() async {
    return _engine.getGameState();
  }

  @override
  Future<Uint8List?> getEventImage(String eventId) async {
    return _engine.getEventImage(eventId);
  }

  @override
  Future<List<VoiceInfo>> getVoices({String? locale}) async {
    return ttsSpeaker.listVoices(locale: locale);
  }

  @override
  Future<String> segmentVoiceText(String text) async {
    return text
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s+([,.;!?，。！？；：])'), r'$1')
        .replaceAll(RegExp(r'([(\[{"“‘])\s+'), r'$1')
        .replaceAll(RegExp(r'\s+([)\]}"”’])'), r'$1')
        .replaceAll(' ,', ',')
        .replaceAll(' .', '.')
        .trim();
  }

  @override
  Stream<SseEvent> startGameStream({
    String? lang,
    bool tts = false,
    String? voice,
  }) async* {
    try {
      yield* _engine.startGame(lang: lang ?? store.getLocale());
    } catch (error) {
      yield SseEvent.error(error.toString());
      yield const SseEvent.done();
    }
  }

  @override
  Stream<SseEvent> continueGameStream({
    String? lang,
    bool tts = false,
    String? voice,
  }) async* {
    try {
      yield* _engine.continueGame(lang: lang ?? store.getLocale());
    } catch (error) {
      yield SseEvent.error(error.toString());
      yield const SseEvent.done();
    }
  }

  @override
  Stream<SseEvent> submitActionStream(
    String action, {
    String? lang,
    bool tts = false,
    String? voice,
  }) async* {
    try {
      yield* _engine.submitAction(action, lang: lang ?? store.getLocale());
    } catch (error) {
      yield SseEvent.error(error.toString());
      yield const SseEvent.done();
    }
  }

  Future<void> _scanPackages() async {
    await paths.outputDir.create(recursive: true);
    final nextPackages = <String, LocalWorldPkg>{};

    await for (final entity in paths.outputDir.list()) {
      if (entity is! File ||
          p.extension(entity.path).toLowerCase() != '.wpkg') {
        continue;
      }

      try {
        final pkg = LocalWorldPkg.load(entity);
        nextPackages[p.basename(entity.path)] = pkg;
      } catch (_) {}
    }

    _packages
      ..clear()
      ..addAll(nextPackages);
  }

  Future<LocalWorldPkg> _ensurePackage(String filename) async {
    if (_packages.containsKey(filename)) {
      return _packages[filename]!;
    }

    final file = File(p.join(paths.outputDir.path, filename));
    if (!file.existsSync()) {
      throw ApiException('World package "$filename" was not found.');
    }

    final pkg = LocalWorldPkg.load(file);
    _packages[filename] = pkg;
    return pkg;
  }

  @override
  void dispose() {
    _ttsSpeaker?.dispose();
    llmClient.dispose();
  }

  Map<String, dynamic> _yamlMapToJsonMap(Object? value) {
    if (value is! YamlMap) {
      return const <String, dynamic>{};
    }

    return value.map(
      (key, nestedValue) =>
          MapEntry(key.toString(), _yamlValueToJson(nestedValue)),
    );
  }

  Object? _yamlValueToJson(Object? value) {
    if (value is YamlMap) {
      return _yamlMapToJsonMap(value);
    }
    if (value is YamlList) {
      return value.map(_yamlValueToJson).toList();
    }
    return value;
  }
}
