import 'dart:io';

import 'api_client.dart';
import 'backend_api_contract.dart';
import 'config_store.dart';
import 'local_backend_api.dart';

Future<BackendApi> createBackendApi({required ConfigStore store}) async {
  final mode = Platform.environment['WHATIF_BACKEND_MODE']
      ?.trim()
      .toLowerCase();

  if (mode == 'integrated' || mode == 'local') {
    return LocalBackendApi.create(store: store);
  }

  return ApiClient(baseUrl: store.getBackendUrl());
}
