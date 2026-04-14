import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'backend_runtime_contract.dart';

BackendRuntime createBackendRuntime() {
  if (Platform.isWindows) {
    return DesktopBackendRuntime();
  }
  return const NoopBackendRuntime();
}

class DesktopBackendRuntime implements BackendRuntime {
  DesktopBackendRuntime();

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  String? _activeBaseUrl;
  String? _lastError;
  String _modeLabel = 'desktop-sidecar';

  @override
  bool get managesBackend => true;

  @override
  String? get activeBaseUrl => _activeBaseUrl;

  @override
  String? get lastError => _lastError;

  @override
  String get modeLabel => _modeLabel;

  @override
  Future<String?> start() async {
    if (_process != null && _activeBaseUrl != null) {
      return _activeBaseUrl;
    }

    await stop();
    _lastError = null;

    final spec = _resolveLaunchSpec();
    if (spec == null) {
      _lastError =
          'Unable to locate a bundled sidecar or a local backend runtime.';
      throw StateError(_lastError!);
    }

    final process = await Process.start(
      spec.executable,
      spec.arguments,
      workingDirectory: spec.workingDirectory,
      environment: spec.environment,
      runInShell: false,
    );
    _process = process;
    _modeLabel = spec.label;

    final stderrBuffer = StringBuffer();
    final portCompleter = Completer<int>();

    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final match = RegExp(r'__PORT__:(\d+)').firstMatch(line);
          if (match != null && !portCompleter.isCompleted) {
            portCompleter.complete(int.parse(match.group(1)!));
          }
        });

    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderrBuffer.writeln(line);
        });

    process.exitCode.then((code) {
      if (identical(_process, process)) {
        if (_activeBaseUrl != null && code != 0) {
          _lastError = 'Desktop backend exited unexpectedly with code $code.';
        }
        _process = null;
        _activeBaseUrl = null;
      }
    });

    try {
      final port = await Future.any<int>([
        portCompleter.future,
        process.exitCode.then<int>((code) {
          final stderr = stderrBuffer.toString().trim();
          throw StateError(
            stderr.isEmpty
                ? 'Desktop backend exited with code $code.'
                : 'Desktop backend exited with code $code.\n$stderr',
          );
        }),
        Future<int>.delayed(const Duration(seconds: 30), () {
          throw TimeoutException('Desktop backend startup timed out.');
        }),
      ]);

      final baseUrl = 'http://127.0.0.1:$port';
      await _waitForHealth(baseUrl);
      _activeBaseUrl = baseUrl;
      _lastError = null;
      return baseUrl;
    } catch (error) {
      _lastError = error.toString();
      await stop();
      rethrow;
    }
  }

  @override
  Future<String?> restart() async {
    await stop();
    return start();
  }

  @override
  Future<void> stop() async {
    final process = _process;
    _process = null;
    _activeBaseUrl = null;

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    if (process == null) {
      return;
    }

    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', <String>[
          '/F',
          '/T',
          '/PID',
          process.pid.toString(),
        ]);
      } else {
        process.kill(ProcessSignal.sigterm);
      }
    } catch (_) {
      process.kill();
    }
  }

  Future<void> _waitForHealth(String baseUrl) async {
    final client = HttpClient();
    try {
      for (var attempt = 0; attempt < 30; attempt += 1) {
        try {
          final request = await client.getUrl(Uri.parse('$baseUrl/api/health'));
          final response = await request.close();
          if (response.statusCode >= 200 && response.statusCode < 300) {
            return;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      client.close(force: true);
    }

    throw TimeoutException('Desktop backend health check timed out.');
  }

  _LaunchSpec? _resolveLaunchSpec() {
    final bundledExe = _resolveBundledExecutable();
    if (bundledExe != null) {
      return _LaunchSpec(
        executable: bundledExe.path,
        arguments: const <String>[],
        workingDirectory: bundledExe.parent.path,
        environment: const <String, String>{},
        label: 'bundled-sidecar',
      );
    }

    final repoRoot = _findRepoRoot();
    if (repoRoot == null) {
      return null;
    }

    final python = _findPython(repoRoot);
    if (python == null) {
      return null;
    }

    final serverScript = File(
      '${repoRoot.path}${Platform.pathSeparator}backend${Platform.pathSeparator}server.py',
    );
    if (!serverScript.existsSync()) {
      return null;
    }

    return _LaunchSpec(
      executable: python.path,
      arguments: <String>[serverScript.path],
      workingDirectory: '${repoRoot.path}${Platform.pathSeparator}backend',
      environment: <String, String>{
        ...Platform.environment,
        'PYTHONUNBUFFERED': '1',
      },
      label: 'python-sidecar',
    );
  }

  File? _resolveBundledExecutable() {
    final executableDir = File(Platform.resolvedExecutable).parent;
    final candidates = <File>[
      File(
        '${executableDir.path}${Platform.pathSeparator}data${Platform.pathSeparator}sidecar${Platform.pathSeparator}whatif-server${Platform.pathSeparator}whatif-server.exe',
      ),
    ];

    final repoRoot = _findRepoRoot();
    if (repoRoot != null) {
      candidates.add(
        File(
          '${repoRoot.path}${Platform.pathSeparator}backend${Platform.pathSeparator}dist${Platform.pathSeparator}whatif-server${Platform.pathSeparator}whatif-server.exe',
        ),
      );
    }

    for (final file in candidates) {
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  Directory? _findRepoRoot() {
    final roots = <Directory>{
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    };

    for (final start in roots) {
      Directory? cursor = start;
      for (var depth = 0; depth < 8 && cursor != null; depth += 1) {
        final marker = File(
          '${cursor.path}${Platform.pathSeparator}backend${Platform.pathSeparator}server.py',
        );
        if (marker.existsSync()) {
          return cursor;
        }
        final parent = cursor.parent;
        if (parent.path == cursor.path) {
          break;
        }
        cursor = parent;
      }
    }
    return null;
  }

  File? _findPython(Directory repoRoot) {
    final candidates = <File>[
      File(
        '${repoRoot.path}${Platform.pathSeparator}.venv${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe',
      ),
    ];

    for (final file in candidates) {
      if (file.existsSync()) {
        return file;
      }
    }

    final which = _which('python.exe') ?? _which('python');
    if (which != null) {
      return File(which);
    }

    return null;
  }

  String? _which(String command) {
    final path = Platform.environment['PATH'];
    if (path == null || path.isEmpty) {
      return null;
    }

    for (final rawSegment in path.split(';')) {
      final segment = rawSegment.trim();
      if (segment.isEmpty) {
        continue;
      }
      final candidate = File('$segment${Platform.pathSeparator}$command');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return null;
  }
}

class _LaunchSpec {
  const _LaunchSpec({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.label,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final String label;
}
