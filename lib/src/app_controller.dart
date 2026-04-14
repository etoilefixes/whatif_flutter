import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'services/backend_api.dart';
import 'services/backend_runtime.dart';
import 'services/config_store.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.api,
    BackendRuntime? runtime,
  }) : runtime = runtime ?? const NoopBackendRuntime();

  final ConfigStore store;
  final BackendApi api;
  final BackendRuntime runtime;

  bool initializing = true;
  bool backendReachable = false;
  bool _didInitialize = false;

  AppReadyState readyState = AppReadyState.loading;
  AppPage page = AppPage.start;

  String locale = 'zh-CN';
  Map<String, String> apiKeys = {};
  LlmConfigMap? llmConfig;
  String? currentPkgName;
  String? currentPkgFilename;
  GameResumeState? resumeState;
  String? runtimeError;
  VoiceConfig voiceConfig = VoiceConfig.defaults();

  bool get hasApiKey => apiKeys.values.any((value) => value.trim().isNotEmpty);
  bool get backendUrlManaged =>
      runtime.managesBackend || !api.supportsBaseUrlOverride;
  String get backendModeLabel =>
      runtime.managesBackend ? runtime.modeLabel : api.modeLabel;
  bool get supportsLocalWorldPkgBuild => api.supportsLocalWorldPkgBuild;

  bool get canStart =>
      backendReachable &&
      readyState == AppReadyState.ready &&
      currentPkgName != null &&
      currentPkgName!.isNotEmpty;

  Future<void> initialize() async {
    if (_didInitialize) {
      return;
    }
    _didInitialize = true;

    locale = store.getLocale();
    apiKeys = store.getApiKeys();
    llmConfig = store.getLlmConfig();
    voiceConfig = store.getVoiceConfig(locale);

    final lastPkg = store.getLastPkg();
    currentPkgName = lastPkg?.name;
    currentPkgFilename = lastPkg?.filename;

    await _configureBackendEndpoint();
    await _refreshBackendState(lastPkg: lastPkg);
    initializing = false;
    notifyListeners();
  }

  Future<void> retryConnection() async {
    initializing = true;
    notifyListeners();
    await _configureBackendEndpoint(restartRuntime: runtime.managesBackend);
    await _refreshBackendState(lastPkg: store.getLastPkg());
    initializing = false;
    notifyListeners();
  }

  Future<void> _configureBackendEndpoint({bool restartRuntime = false}) async {
    runtimeError = null;

    if (!runtime.managesBackend) {
      api.baseUrl = store.getBackendUrl();
      return;
    }

    try {
      final managedUrl = restartRuntime
          ? await runtime.restart()
          : await runtime.start();
      if (managedUrl != null && managedUrl.isNotEmpty) {
        api.baseUrl = managedUrl;
        return;
      }
    } catch (error) {
      runtimeError = error.toString();
    }

    api.baseUrl = store.getBackendUrl();
  }

  Future<void> _refreshBackendState({LastPkg? lastPkg}) async {
    backendReachable = false;
    readyState = AppReadyState.loading;

    for (var attempt = 0; attempt < 10; attempt += 1) {
      if (await api.checkHealth()) {
        backendReachable = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    if (!backendReachable) {
      readyState = hasApiKey
          ? AppReadyState.offline
          : AppReadyState.needsConfig;
      return;
    }

    if (hasApiKey) {
      try {
        await api.updateApiKeys(apiKeys);
      } catch (_) {}
    }

    if (llmConfig != null) {
      try {
        await api.updateLlmConfig(llmConfig!);
      } catch (_) {}
    }

    if (lastPkg != null && lastPkg.filename.isNotEmpty) {
      try {
        final packages = await api.getWorldPkgs();
        final existing = packages.packages.where(
          (pkg) => pkg.filename == lastPkg.filename,
        );
        if (existing.isNotEmpty) {
          if (packages.current != lastPkg.name) {
            await api.loadWorldPkg(lastPkg.filename);
          }
          currentPkgName = lastPkg.name;
          currentPkgFilename = lastPkg.filename;
        }
      } catch (_) {}
    }

    readyState = hasApiKey ? AppReadyState.ready : AppReadyState.needsConfig;
  }

  void openStart() {
    page = AppPage.start;
    notifyListeners();
  }

  void openLibrary() {
    page = AppPage.library;
    notifyListeners();
  }

  void openSettings() {
    page = AppPage.settings;
    notifyListeners();
  }

  void openGameplay({GameResumeState? resume}) {
    resumeState = resume;
    page = AppPage.gameplay;
    notifyListeners();
  }

  Future<void> setLocale(String value) async {
    locale = value;
    await store.setLocale(value);
    notifyListeners();
  }

  Future<void> saveVoiceConfig(VoiceConfig value) async {
    voiceConfig = value;
    await store.setVoiceConfig(value);
    notifyListeners();
  }

  Future<void> updateBackendUrl(String value) async {
    if (!api.supportsBaseUrlOverride) {
      return;
    }
    api.baseUrl = value;
    await store.setBackendUrl(api.baseUrl);
    notifyListeners();
  }

  Future<void> saveApiKeys(Map<String, String> next) async {
    apiKeys = next;
    await store.setApiKeys(next);

    if (backendReachable) {
      try {
        await api.updateApiKeys(next);
      } catch (_) {}
    }

    readyState = hasApiKey
        ? (backendReachable ? AppReadyState.ready : AppReadyState.offline)
        : AppReadyState.needsConfig;
    notifyListeners();
  }

  Future<void> ensureLlmConfigLoaded() async {
    if (llmConfig != null || !backendReachable) {
      return;
    }

    try {
      llmConfig = await api.getLlmConfig();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> saveLlmConfig(LlmConfigMap next) async {
    llmConfig = next;
    await store.setLlmConfig(next);

    if (backendReachable) {
      await api.updateLlmConfig(next);
    }

    notifyListeners();
  }

  Future<List<WorldPkgInfo>> fetchWorldPackages() async {
    final response = await api.getWorldPkgs();
    if (response.current != null && response.current!.isNotEmpty) {
      currentPkgName = response.current;
      final selected = response.packages
          .where((pkg) => pkg.name == response.current)
          .toList();
      if (selected.isNotEmpty) {
        currentPkgFilename = selected.first.filename;
      }
      notifyListeners();
    }
    return response.packages;
  }

  Future<void> importWorldPackage(String filePath) async {
    await api.importWorldPkg(filePath);
  }

  Future<void> buildWorldPackageFromText(String filePath) async {
    await api.buildWorldPkgFromText(filePath);
  }

  Future<void> selectWorldPackage(WorldPkgInfo pkg) async {
    await api.loadWorldPkg(pkg.filename);
    currentPkgName = pkg.name;
    currentPkgFilename = pkg.filename;
    await store.setLastPkg(LastPkg(filename: pkg.filename, name: pkg.name));
    readyState = hasApiKey ? AppReadyState.ready : AppReadyState.needsConfig;
    page = AppPage.start;
    notifyListeners();
  }

  Future<List<SaveInfo>> fetchSaves() async {
    return api.getSaves();
  }

  Future<String> saveGame(int slot, String description) async {
    return api.saveGame(slot, description);
  }

  Future<void> loadSave(SaveInfo save) async {
    final packages = await api.getWorldPkgs();
    if (packages.current != save.worldpkgTitle) {
      final match = packages.packages
          .where((pkg) => pkg.name == save.worldpkgTitle)
          .toList();
      if (match.isEmpty) {
        throw const ApiException(
          'The package required by this save is missing.',
        );
      }
      await selectWorldPackage(match.first);
    }

    final loaded = await api.loadGame(save.slot);
    final state = await api.getGameState();

    final eventId = loaded.eventId ?? state.event?.id;
    resumeState = GameResumeState(
      text: loaded.text,
      phase: loaded.phase,
      eventId: eventId,
      turn: loaded.turn,
      awaitingNextEvent: state.awaitingNextEvent,
      gameEnded: state.gameEnded,
      eventHasImage: state.event?.hasImage ?? false,
    );
    page = AppPage.gameplay;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(runtime.stop());
    api.dispose();
    super.dispose();
  }
}
