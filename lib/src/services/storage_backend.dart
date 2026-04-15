import 'package:shared_preferences/shared_preferences.dart';

import 'storage_backend_contract.dart';
import 'storage_backend_stub.dart'
    if (dart.library.io) 'storage_backend_io.dart' as impl;

export 'storage_backend_contract.dart';

Future<StorageBackend> openStorageBackend({
  SharedPreferences? legacyPrefs,
  String? databasePathOverride,
  bool useInMemoryDatabase = false,
}) {
  return impl.openStorageBackend(
    legacyPrefs: legacyPrefs,
    databasePathOverride: databasePathOverride,
    useInMemoryDatabase: useInMemoryDatabase,
  );
}
