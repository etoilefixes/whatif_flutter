abstract class BackendRuntime {
  const BackendRuntime();

  bool get managesBackend;
  String? get activeBaseUrl;
  String? get lastError;
  String get modeLabel;

  Future<String?> start();
  Future<String?> restart();
  Future<void> stop();
}

class NoopBackendRuntime implements BackendRuntime {
  const NoopBackendRuntime();

  @override
  bool get managesBackend => false;

  @override
  String? get activeBaseUrl => null;

  @override
  String? get lastError => null;

  @override
  String get modeLabel => 'external';

  @override
  Future<String?> restart() => Future<String?>.value(null);

  @override
  Future<String?> start() => Future<String?>.value(null);

  @override
  Future<void> stop() => Future<void>.value();
}
