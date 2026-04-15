import 'dart:io';

import 'api_client.dart';
import 'backend_api_contract.dart';
import 'config_store.dart';
import 'local_backend_api.dart';

Future<BackendApi> createBackendApi({required ConfigStore store}) async {
  final mode = Platform.environment['WHATIF_BACKEND_MODE']
      ?.trim()
      .toLowerCase();

  // 默认使用集成模式，除非显式设置为其他模式
  if (mode == null || mode == 'integrated' || mode == 'local') {
    return LocalBackendApi.create(store: store);
  }

  return ApiClient(baseUrl: store.getBackendUrl());
}
