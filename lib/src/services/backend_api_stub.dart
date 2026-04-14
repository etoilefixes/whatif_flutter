import 'api_client.dart';
import 'backend_api_contract.dart';
import 'config_store.dart';

Future<BackendApi> createBackendApi({required ConfigStore store}) async {
  return ApiClient(baseUrl: store.getBackendUrl());
}
