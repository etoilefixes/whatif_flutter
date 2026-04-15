import '../models.dart';

class PersistedSaveRecord {
  const PersistedSaveRecord({
    required this.slot,
    required this.metadataJson,
    required this.stateJson,
    required this.updatedAtMs,
  });

  final int slot;
  final String metadataJson;
  final String stateJson;
  final int updatedAtMs;
}

class PersistedPackageRecord {
  const PersistedPackageRecord({
    required this.filename,
    required this.title,
    required this.size,
    required this.hasCover,
    required this.modifiedAtMs,
    required this.indexedAtMs,
  });

  final String filename;
  final String title;
  final int size;
  final bool hasCover;
  final int modifiedAtMs;
  final int indexedAtMs;

  WorldPkgInfo toWorldPkgInfo() {
    return WorldPkgInfo(
      name: title,
      filename: filename,
      size: size,
      hasCover: hasCover,
    );
  }
}

abstract class StorageBackend {
  Future<Map<String, String>> readSettings();
  Future<void> writeSetting(String key, String? value);
  Future<List<PersistedSaveRecord>> listSaves();
  Future<PersistedSaveRecord?> getSave(int slot);
  Future<void> upsertSave(PersistedSaveRecord record);
  Future<List<PersistedPackageRecord>> listPackages();
  Future<PersistedPackageRecord?> getPackage(String filename);
  Future<void> upsertPackage(PersistedPackageRecord record);
  Future<void> deletePackagesNotIn(Set<String> filenames);
  Future<void> close();
}
