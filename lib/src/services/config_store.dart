import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class ConfigStore {
  ConfigStore(this._prefs);

  static const defaultBackendUrl = 'http://127.0.0.1:8000';

  static const _apiKeysKey = 'api_keys';
  static const _llmConfigKey = 'llm_config';
  static const _localeKey = 'locale';
  static const _lastPkgKey = 'last_pkg';
  static const _backendUrlKey = 'backend_url';
  static const _voiceConfigKey = 'voice_config';

  final SharedPreferences _prefs;

  Map<String, String> getApiKeys() {
    final raw = _prefs.getString(_apiKeysKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return {};
    }

    return decoded.map((key, value) => MapEntry(key, value?.toString() ?? ''));
  }

  Future<void> setApiKeys(Map<String, String> keys) async {
    await _prefs.setString(_apiKeysKey, jsonEncode(keys));
  }

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

  String getLocale() {
    return _prefs.getString(_localeKey) ?? 'zh-CN';
  }

  Future<void> setLocale(String locale) async {
    await _prefs.setString(_localeKey, locale);
  }

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

  String getBackendUrl() {
    return _prefs.getString(_backendUrlKey) ?? defaultBackendUrl;
  }

  Future<void> setBackendUrl(String url) async {
    await _prefs.setString(_backendUrlKey, url);
  }

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
