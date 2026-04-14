import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalBackendPaths {
  const LocalBackendPaths({
    required this.rootDir,
    required this.outputDir,
    required this.savesDir,
    required this.llmConfigFile,
  });

  final Directory rootDir;
  final Directory outputDir;
  final Directory savesDir;
  final File? llmConfigFile;

  static Future<LocalBackendPaths> resolve() async {
    final repoRoot = _findRepoRoot();
    if (repoRoot != null) {
      return LocalBackendPaths(
        rootDir: repoRoot,
        outputDir: Directory(p.join(repoRoot.path, 'output')),
        savesDir: Directory(p.join(repoRoot.path, 'saves')),
        llmConfigFile: File(
          p.join(repoRoot.path, 'backend', 'llm_config.yaml'),
        ),
      );
    }

    final appSupport = await getApplicationSupportDirectory();
    final rootDir = Directory(p.join(appSupport.path, 'whatif_local_backend'));
    return LocalBackendPaths(
      rootDir: rootDir,
      outputDir: Directory(p.join(rootDir.path, 'output')),
      savesDir: Directory(p.join(rootDir.path, 'saves')),
      llmConfigFile: null,
    );
  }

  Future<void> ensureReady() async {
    await outputDir.create(recursive: true);
    await savesDir.create(recursive: true);
  }

  static Directory? _findRepoRoot() {
    final candidates = <Directory>{
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    };

    for (final start in candidates) {
      Directory? cursor = start;
      for (var depth = 0; depth < 8 && cursor != null; depth += 1) {
        final configFile = File(
          p.join(cursor.path, 'backend', 'llm_config.yaml'),
        );
        if (configFile.existsSync()) {
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
}
