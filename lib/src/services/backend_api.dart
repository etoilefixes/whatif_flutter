import 'backend_api_contract.dart';
import 'backend_api_stub.dart'
    if (dart.library.io) 'backend_api_io.dart'
    as impl;
import 'config_store.dart';

export 'backend_api_contract.dart';

Future<BackendApi> createBackendApi({required ConfigStore store}) {
  return impl.createBackendApi(store: store);
}
