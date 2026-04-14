import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class ConfigStore {
  ConfigStore(this._prefs);

  static const defaultBackendUrl = 'http://127.0.0.1:8000';

  static const _modelProvidersKey = 'model_providers';
  static const _legacyApiKeysKey = 'api_keys';
  static const _llmConfigKey = 'llm_config';
  static const _localeKey = 'locale';
  static const _lastPkgKey = 'last_pkg';
  static const _backendUrlKey = 'backend_url';
  static const _voiceConfigKey = 'voice_config';

  final SharedPreferences _prefs;

  // ── Model Providers ──────────────────────────────────────────────

  List<ModelProvider> getModelProviders() {
    final raw = _prefs.getString(_modelProvidersKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        final providers = decoded
            .whereType<Map<String, dynamic>>()
            .map(ModelProvider.fromJson)
            .toList();
        if (providers.isNotEmpty) {
          return providers;
        }
      }
    }

    // Migration: convert legacy api_keys format
    return _migrateFromApiKeys();
  }

  Future<void> setModelProviders(List<ModelProvider> providers) async {
    await _prefs.setString(
      _modelProvidersKey,
      jsonEncode(providers.map((p) => p.toJson()).toList()),
    );
  }

  /// Lookup API key and URL by provider name.
  /// Used by local backend services to resolve credentials per slot.
  ({String apiKey, String? apiUrl})? getProviderCredentials(String providerName) {
    final providers = getModelProviders();
    for (final p in providers) {
      if (p.name == providerName && p.hasKey) {
        return (apiKey: p.apiKey, apiUrl: p.apiUrl);
      }
    }
    return null;
  }

  List<ModelProvider> _migrateFromApiKeys() {
    final raw = _prefs.getString(_legacyApiKeysKey);
    if (raw == null || raw.isEmpty) {
      return const <ModelProvider>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <ModelProvider>[];
    }

    final providers = <ModelProvider>[];
    for (final entry in decoded.entries) {
      final apiKey = entry.value?.toString() ?? '';
      if (apiKey.trim().isEmpty) {
        continue;
      }
      providers.add(ModelProvider(
        name: entry.key,
        apiKey: apiKey,
        apiUrl: ModelProvider.defaultApiUrls[entry.key],
        models: ModelProvider.defaultModels[entry.key] ?? const <String>[],
      ));
    }
    return providers;
  }

  // ── LLM Config ───────────────────────────────────────────────────

  LlmConfigMap? getLlmConfig() {
    final raw = _prefs.getString(_llmConfigKey);
    final json = decodeJsonObject(raw);
    if (json == null) {
      return null;
    }
    return LlmConfigMap.fromJson(json);
  }

  Future<void> setLlmConfig(LlmConfigMap config) async {
    await _prefs.setString(_llmConfigKey, jsonEncode(config.toJson()));
  }

  // ── Locale ───────────────────────────────────────────────────────

  String getLocale() {
    return _prefs.getString(_localeKey) ?? 'zh-CN';
  }

  Future<void> setLocale(String locale) async {
    await _prefs.setString(_localeKey, locale);
  }

  // ── Voice Config ─────────────────────────────────────────────────

  VoiceConfig getVoiceConfig([String locale = 'zh-CN']) {
    final raw = _prefs.getString(_voiceConfigKey);
    final json = decodeJsonObject(raw);
    if (json == null) {
      return VoiceConfig.defaults(locale);
    }
    return VoiceConfig.fromJson(json);
  }

  Future<void> setVoiceConfig(VoiceConfig config) async {
    await _prefs.setString(_voiceConfigKey, jsonEncode(config.toJson()));
  }

  // ── Backend URL ──────────────────────────────────────────────────

  String getBackendUrl() {
    return _prefs.getString(_backendUrlKey) ?? defaultBackendUrl;
  }

  Future<void> setBackendUrl(String url) async {
    await _prefs.setString(_backendUrlKey, url);
  }

  // ── Last Package ─────────────────────────────────────────────────

  LastPkg? getLastPkg() {
    final raw = _prefs.getString(_lastPkgKey);
    final json = decodeJsonObject(raw);
    if (json == null) {
      return null;
    }
    return LastPkg.fromJson(json);
  }

  Future<void> setLastPkg(LastPkg pkg) async {
    await _prefs.setString(_lastPkgKey, jsonEncode(pkg.toJson()));
  }
}
