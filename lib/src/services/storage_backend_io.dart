import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'storage_backend_contract.dart';

class SqliteStorageBackend implements StorageBackend {
  SqliteStorageBackend._(this._db);

  final Database _db;

  static Future<SqliteStorageBackend> open({
    String? databasePathOverride,
    bool useInMemoryDatabase = false,
  }) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final databasePath = useInMemoryDatabase
        ? inMemoryDatabasePath
        : databasePathOverride ?? await _defaultDatabasePath();

    if (!useInMemoryDatabase) {
      await Directory(p.dirname(databasePath)).create(recursive: true);
    }

    final db = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE saves (
              slot INTEGER PRIMARY KEY,
              metadata_json TEXT NOT NULL,
              state_json TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE packages (
              filename TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              size INTEGER NOT NULL,
              has_cover INTEGER NOT NULL,
              modified_at INTEGER NOT NULL,
              indexed_at INTEGER NOT NULL
            )
          ''');
        },
        onOpen: (db) async {
          await db.execute('PRAGMA journal_mode=WAL;');
          await db.execute('PRAGMA synchronous=NORMAL;');
        },
      ),
    );

    return SqliteStorageBackend._(db);
  }

  static Future<String> _defaultDatabasePath() async {
    final databasesPath = await getDatabasesPath();
    return p.join(databasesPath, 'whatif_local.db');
  }

  @override
  Future<Map<String, String>> readSettings() async {
    final rows = await _db.query('settings');
    return {
      for (final row in rows)
        row['key']!.toString(): row['value']?.toString() ?? '',
    };
  }

  @override
  Future<void> writeSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
      return;
    }

    await _db.insert('settings', <String, Object?>{
      'key': key,
      'value': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<PersistedSaveRecord>> listSaves() async {
    final rows = await _db.query('saves', orderBy: 'updated_at DESC');
    return rows
        .map(
          (row) => PersistedSaveRecord(
            slot: (row['slot'] as num?)?.toInt() ?? 0,
            metadataJson: row['metadata_json']?.toString() ?? '{}',
            stateJson: row['state_json']?.toString() ?? '{}',
            updatedAtMs: (row['updated_at'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<PersistedSaveRecord?> getSave(int slot) async {
    final rows = await _db.query(
      'saves',
      where: 'slot = ?',
      whereArgs: [slot],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    return PersistedSaveRecord(
      slot: (row['slot'] as num?)?.toInt() ?? slot,
      metadataJson: row['metadata_json']?.toString() ?? '{}',
      stateJson: row['state_json']?.toString() ?? '{}',
      updatedAtMs: (row['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> upsertSave(PersistedSaveRecord record) async {
    await _db.insert('saves', <String, Object?>{
      'slot': record.slot,
      'metadata_json': record.metadataJson,
      'state_json': record.stateJson,
      'updated_at': record.updatedAtMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<PersistedPackageRecord>> listPackages() async {
    final rows = await _db.query('packages', orderBy: 'title COLLATE NOCASE');
    return rows
        .map(
          (row) => PersistedPackageRecord(
            filename: row['filename']?.toString() ?? '',
            title: row['title']?.toString() ?? '',
            size: (row['size'] as num?)?.toInt() ?? 0,
            hasCover: ((row['has_cover'] as num?)?.toInt() ?? 0) == 1,
            modifiedAtMs: (row['modified_at'] as num?)?.toInt() ?? 0,
            indexedAtMs: (row['indexed_at'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<PersistedPackageRecord?> getPackage(String filename) async {
    final rows = await _db.query(
      'packages',
      where: 'filename = ?',
      whereArgs: [filename],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    return PersistedPackageRecord(
      filename: row['filename']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      size: (row['size'] as num?)?.toInt() ?? 0,
      hasCover: ((row['has_cover'] as num?)?.toInt() ?? 0) == 1,
      modifiedAtMs: (row['modified_at'] as num?)?.toInt() ?? 0,
      indexedAtMs: (row['indexed_at'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> upsertPackage(PersistedPackageRecord record) async {
    await _db.insert('packages', <String, Object?>{
      'filename': record.filename,
      'title': record.title,
      'size': record.size,
      'has_cover': record.hasCover ? 1 : 0,
      'modified_at': record.modifiedAtMs,
      'indexed_at': record.indexedAtMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deletePackagesNotIn(Set<String> filenames) async {
    if (filenames.isEmpty) {
      await _db.delete('packages');
      return;
    }

    final placeholders = List<String>.filled(filenames.length, '?').join(', ');
    await _db.delete(
      'packages',
      where: 'filename NOT IN ($placeholders)',
      whereArgs: filenames.toList(growable: false),
    );
  }

  @override
  Future<void> close() async {
    await _db.close();
  }
}

Future<StorageBackend> openStorageBackend({
  SharedPreferences? legacyPrefs,
  String? databasePathOverride,
  bool useInMemoryDatabase = false,
}) {
  return SqliteStorageBackend.open(
    databasePathOverride: databasePathOverride,
    useInMemoryDatabase: useInMemoryDatabase,
  );
}
