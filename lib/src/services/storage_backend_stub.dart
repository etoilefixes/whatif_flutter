import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'storage_backend_contract.dart';

class SharedPrefsStorageBackend implements StorageBackend {
  SharedPrefsStorageBackend(this._prefs);

  static const _settingsKey = 'sqlite_stub_settings';
  static const _savesKey = 'sqlite_stub_saves';
  static const _packagesKey = 'sqlite_stub_packages';

  final SharedPreferences _prefs;

  Map<String, dynamic> _readJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<void> _writeJson(String key, Map<String, dynamic> value) async {
    await _prefs.setString(key, jsonEncode(value));
  }

  @override
  Future<Map<String, String>> readSettings() async {
    return _readJson(_settingsKey).map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    );
  }

  @override
  Future<void> writeSetting(String key, String? value) async {
    final settings = _readJson(_settingsKey);
    if (value == null) {
      settings.remove(key);
    } else {
      settings[key] = value;
    }
    await _writeJson(_settingsKey, settings);
  }

  @override
  Future<List<PersistedSaveRecord>> listSaves() async {
    final saves = _readJson(_savesKey);
    return saves.values
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => PersistedSaveRecord(
            slot: (row['slot'] as num?)?.toInt() ?? 0,
            metadataJson: row['metadata_json']?.toString() ?? '{}',
            stateJson: row['state_json']?.toString() ?? '{}',
            updatedAtMs: (row['updated_at'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList()
      ..sort((left, right) => right.updatedAtMs.compareTo(left.updatedAtMs));
  }

  @override
  Future<PersistedSaveRecord?> getSave(int slot) async {
    final saves = _readJson(_savesKey);
    final row = saves[slot.toString()];
    if (row is! Map<String, dynamic>) {
      return null;
    }

    return PersistedSaveRecord(
      slot: (row['slot'] as num?)?.toInt() ?? slot,
      metadataJson: row['metadata_json']?.toString() ?? '{}',
      stateJson: row['state_json']?.toString() ?? '{}',
      updatedAtMs: (row['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> upsertSave(PersistedSaveRecord record) async {
    final saves = _readJson(_savesKey);
    saves[record.slot.toString()] = <String, Object?>{
      'slot': record.slot,
      'metadata_json': record.metadataJson,
      'state_json': record.stateJson,
      'updated_at': record.updatedAtMs,
    };
    await _writeJson(_savesKey, saves);
  }

  @override
  Future<List<PersistedPackageRecord>> listPackages() async {
    final packages = _readJson(_packagesKey);
    return packages.values
        .whereType<Map<String, dynamic>>()
        .map(
          (row) => PersistedPackageRecord(
            filename: row['filename']?.toString() ?? '',
            title: row['title']?.toString() ?? '',
            size: (row['size'] as num?)?.toInt() ?? 0,
            hasCover: row['has_cover'] == true || row['has_cover'] == 1,
            modifiedAtMs: (row['modified_at'] as num?)?.toInt() ?? 0,
            indexedAtMs: (row['indexed_at'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList()
      ..sort((left, right) => left.title.compareTo(right.title));
  }

  @override
  Future<PersistedPackageRecord?> getPackage(String filename) async {
    final packages = _readJson(_packagesKey);
    final row = packages[filename];
    if (row is! Map<String, dynamic>) {
      return null;
    }

    return PersistedPackageRecord(
      filename: row['filename']?.toString() ?? filename,
      title: row['title']?.toString() ?? '',
      size: (row['size'] as num?)?.toInt() ?? 0,
      hasCover: row['has_cover'] == true || row['has_cover'] == 1,
      modifiedAtMs: (row['modified_at'] as num?)?.toInt() ?? 0,
      indexedAtMs: (row['indexed_at'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> upsertPackage(PersistedPackageRecord record) async {
    final packages = _readJson(_packagesKey);
    packages[record.filename] = <String, Object?>{
      'filename': record.filename,
      'title': record.title,
      'size': record.size,
      'has_cover': record.hasCover,
      'modified_at': record.modifiedAtMs,
      'indexed_at': record.indexedAtMs,
    };
    await _writeJson(_packagesKey, packages);
  }

  @override
  Future<void> deletePackagesNotIn(Set<String> filenames) async {
    final packages = _readJson(_packagesKey);
    packages.removeWhere((key, value) => !filenames.contains(key));
    await _writeJson(_packagesKey, packages);
  }

  @override
  Future<void> close() async {}
}

Future<StorageBackend> openStorageBackend({
  SharedPreferences? legacyPrefs,
  String? databasePathOverride,
  bool useInMemoryDatabase = false,
}) async {
  final prefs = legacyPrefs ?? await SharedPreferences.getInstance();
  return SharedPrefsStorageBackend(prefs);
}
