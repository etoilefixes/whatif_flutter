import 'backend_runtime_contract.dart';
import 'backend_runtime_stub.dart'
    if (dart.library.io) 'backend_runtime_io.dart'
    as impl;

export 'backend_runtime_contract.dart';

BackendRuntime createBackendRuntime() => impl.createBackendRuntime();
