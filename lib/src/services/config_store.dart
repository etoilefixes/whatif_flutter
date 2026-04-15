import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'storage_backend.dart';

typedef StoredSaveSnapshot = ({SaveInfo info, Map<String, dynamic> state});

class ConfigStore {
  ConfigStore._({
    required StorageBackend backend,
    required Map<String, String> settings,
  }) : _backend = backend,
       _settings = settings;

  static const defaultBackendUrl = 'http://127.0.0.1:8000';

  static const _modelProvidersKey = 'model_providers';
  static const _legacyApiKeysKey = 'api_keys';
  static const _llmConfigKey = 'llm_config';
  static const _localeKey = 'locale';
  static const _lastPkgKey = 'last_pkg';
  static const _backendUrlKey = 'backend_url';
  static const _voiceConfigKey = 'voice_config';

  final StorageBackend _backend;
  final Map<String, String> _settings;

  static Future<ConfigStore> open({
    SharedPreferences? legacyPrefs,
    String? databasePathOverride,
    bool useInMemoryDatabase = false,
  }) async {
    final backend = await openStorageBackend(
      legacyPrefs: legacyPrefs,
      databasePathOverride: databasePathOverride,
      useInMemoryDatabase: useInMemoryDatabase,
    );
    var settings = await backend.readSettings();
    if (settings.isEmpty && legacyPrefs != null) {
      settings = _migrateLegacySettings(legacyPrefs);
      for (final entry in settings.entries) {
        await backend.writeSetting(entry.key, entry.value);
      }
    }

    return ConfigStore._(backend: backend, settings: settings);
  }

  static ConfigStore inMemory({Map<String, String> settings = const {}}) {
    return ConfigStore._(
      backend: _MemoryStorageBackend(settings: settings),
      settings: Map<String, String>.from(settings),
    );
  }

  static Map<String, String> _migrateLegacySettings(SharedPreferences prefs) {
    final migrated = <String, String>{};

    void copyString(String key) {
      final value = prefs.getString(key);
      if (value != null && value.isNotEmpty) {
        migrated[key] = value;
      }
    }

    copyString(_llmConfigKey);
    copyString(_localeKey);
    copyString(_lastPkgKey);
    copyString(_backendUrlKey);
    copyString(_voiceConfigKey);

    final providersRaw = prefs.getString(_modelProvidersKey);
    if (providersRaw != null && providersRaw.isNotEmpty) {
      migrated[_modelProvidersKey] = providersRaw;
      return migrated;
    }

    final legacyKeysRaw = prefs.getString(_legacyApiKeysKey);
    if (legacyKeysRaw == null || legacyKeysRaw.isEmpty) {
      return migrated;
    }

    final decoded = decodeJsonObject(legacyKeysRaw);
    if (decoded == null) {
      return migrated;
    }

    final providers = <ModelProvider>[];
    for (final entry in decoded.entries) {
      final providerName = ModelProvider.canonicalProviderName(entry.key);
      final apiKey = entry.value?.toString() ?? '';
      if (apiKey.trim().isEmpty) {
        continue;
      }
      providers.add(
        ModelProvider(
          name: providerName,
          apiKey: apiKey,
          apiUrl: ModelProvider.fixedApiUrlFor(providerName),
          models: ModelProvider.suggestedModelsFor(providerName),
        ),
      );
    }

    if (providers.isNotEmpty) {
      migrated[_modelProvidersKey] = jsonEncode(
        providers.map((provider) => provider.toJson()).toList(),
      );
    }
    return migrated;
  }

  String? _rawValue(String key) {
    final value = _settings[key];
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> _setValue(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _settings.remove(key);
      await _backend.writeSetting(key, null);
      return;
    }

    _settings[key] = value;
    await _backend.writeSetting(key, value);
  }

  // ── Model Providers ──────────────────────────────────────────────

  List<ModelProvider> getModelProviders() {
    final raw = _rawValue(_modelProvidersKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final providers = decoded
              .whereType<Map>()
              .map(
                (entry) =>
                    entry.map((key, value) => MapEntry(key.toString(), value)),
              )
              .map(ModelProvider.fromJson)
              .where((provider) => provider.name.trim().isNotEmpty)
              .toList();
          if (providers.isNotEmpty) {
            return providers;
          }
        }
      } catch (_) {}
    }

    return const <ModelProvider>[];
  }

  Future<void> setModelProviders(List<ModelProvider> providers) async {
    await _setValue(
      _modelProvidersKey,
      jsonEncode(providers.map((provider) => provider.toJson()).toList()),
    );
  }

  ({String apiKey, String? apiUrl})? getProviderCredentials(
    String providerName,
  ) {
    final providers = getModelProviders();
    for (final provider in providers) {
      if (provider.name == providerName && provider.isUsable) {
        return (apiKey: provider.apiKey, apiUrl: provider.apiUrl);
      }
    }
    return null;
  }

  // ── LLM Config ──────────────────────────────────────────────────

  LlmConfigMap? getLlmConfig() {
    final json = decodeJsonObject(_rawValue(_llmConfigKey));
    if (json == null) {
      return null;
    }
    return LlmConfigMap.fromJson(json);
  }

  Future<void> setLlmConfig(LlmConfigMap config) async {
    await _setValue(_llmConfigKey, jsonEncode(config.toJson()));
  }

  // ── Locale ──────────────────────────────────────────────────────

  String getLocale() {
    return _rawValue(_localeKey) ?? 'zh-CN';
  }

  Future<void> setLocale(String locale) async {
    await _setValue(_localeKey, locale);
  }

  // ── Voice Config ────────────────────────────────────────────────

  VoiceConfig getVoiceConfig([String locale = 'zh-CN']) {
    final json = decodeJsonObject(_rawValue(_voiceConfigKey));
    if (json == null) {
      return VoiceConfig.defaults(locale);
    }
    return VoiceConfig.fromJson(json);
  }

  Future<void> setVoiceConfig(VoiceConfig config) async {
    await _setValue(_voiceConfigKey, jsonEncode(config.toJson()));
  }

  // ── Backend URL ─────────────────────────────────────────────────

  String getBackendUrl() {
    return _rawValue(_backendUrlKey) ?? defaultBackendUrl;
  }

  Future<void> setBackendUrl(String url) async {
    await _setValue(_backendUrlKey, url);
  }

  // ── Last Package ────────────────────────────────────────────────

  LastPkg? getLastPkg() {
    final json = decodeJsonObject(_rawValue(_lastPkgKey));
    if (json == null) {
      return null;
    }
    return LastPkg.fromJson(json);
  }

  Future<void> setLastPkg(LastPkg pkg) async {
    await _setValue(_lastPkgKey, jsonEncode(pkg.toJson()));
  }

  // ── Save Persistence ────────────────────────────────────────────

  Future<void> saveGameSnapshot({
    required SaveInfo info,
    required Map<String, dynamic> state,
  }) async {
    await _backend.upsertSave(
      PersistedSaveRecord(
        slot: info.slot,
        metadataJson: jsonEncode(<String, dynamic>{
          'slot': info.slot,
          'saveTime': info.saveTime,
          'playerName': info.playerName,
          'currentPhase': info.currentPhase,
          'currentEventId': info.currentEventId,
          'totalTurns': info.totalTurns,
          'description': info.description,
          'worldpkgTitle': info.worldpkgTitle,
        }),
        stateJson: jsonEncode(state),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<List<SaveInfo>> listSavedGames() async {
    final records = await _backend.listSaves();
    final saves = <SaveInfo>[];
    for (final record in records) {
      final decoded = decodeJsonObject(record.metadataJson);
      if (decoded == null) {
        continue;
      }
      saves.add(SaveInfo.fromJson(decoded));
    }
    saves.sort((left, right) => right.saveTime.compareTo(left.saveTime));
    return saves;
  }

  Future<StoredSaveSnapshot?> getSavedGame(int slot) async {
    final record = await _backend.getSave(slot);
    if (record == null) {
      return null;
    }

    final metadata = decodeJsonObject(record.metadataJson);
    final state = decodeJsonObject(record.stateJson);
    if (metadata == null || state == null) {
      return null;
    }

    return (info: SaveInfo.fromJson(metadata), state: state);
  }

  // ── World Package Index ─────────────────────────────────────────

  Future<List<PersistedPackageRecord>> listPackageRecords() {
    return _backend.listPackages();
  }

  Future<PersistedPackageRecord?> getPackageRecord(String filename) {
    return _backend.getPackage(filename);
  }

  Future<void> upsertPackageRecord(PersistedPackageRecord record) {
    return _backend.upsertPackage(record);
  }

  Future<void> prunePackageRecords(Set<String> filenames) {
    return _backend.deletePackagesNotIn(filenames);
  }

  Future<void> dispose() {
    return _backend.close();
  }
}

class _MemoryStorageBackend implements StorageBackend {
  _MemoryStorageBackend({
    Map<String, String> settings = const <String, String>{},
  }) : _settings = Map<String, String>.from(settings);

  final Map<String, String> _settings;
  final Map<int, PersistedSaveRecord> _saves = <int, PersistedSaveRecord>{};
  final Map<String, PersistedPackageRecord> _packages =
      <String, PersistedPackageRecord>{};

  @override
  Future<Map<String, String>> readSettings() async {
    return Map<String, String>.from(_settings);
  }

  @override
  Future<void> writeSetting(String key, String? value) async {
    if (value == null) {
      _settings.remove(key);
      return;
    }
    _settings[key] = value;
  }

  @override
  Future<List<PersistedSaveRecord>> listSaves() async {
    final values = _saves.values.toList()
      ..sort((left, right) => right.updatedAtMs.compareTo(left.updatedAtMs));
    return values;
  }

  @override
  Future<PersistedSaveRecord?> getSave(int slot) async {
    return _saves[slot];
  }

  @override
  Future<void> upsertSave(PersistedSaveRecord record) async {
    _saves[record.slot] = record;
  }

  @override
  Future<List<PersistedPackageRecord>> listPackages() async {
    final values = _packages.values.toList()
      ..sort((left, right) => left.title.compareTo(right.title));
    return values;
  }

  @override
  Future<PersistedPackageRecord?> getPackage(String filename) async {
    return _packages[filename];
  }

  @override
  Future<void> upsertPackage(PersistedPackageRecord record) async {
    _packages[record.filename] = record;
  }

  @override
  Future<void> deletePackagesNotIn(Set<String> filenames) async {
    _packages.removeWhere((filename, _) => !filenames.contains(filename));
  }

  @override
  Future<void> close() async {}
}
