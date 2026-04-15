import 'backend_api_contract.dart';
import 'config_store.dart';
import 'web_backend_api.dart';

Future<BackendApi> createBackendApi({required ConfigStore store}) async {
  return WebBackendApi.create(store: store);
}
