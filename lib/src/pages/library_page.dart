import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    required this.strings,
  });

  final AppController controller;
  final AppStrings strings;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final ScrollController _gridController = ScrollController();
  final Map<String, Future<Uint8List?>> _coverFutures =
      <String, Future<Uint8List?>>{};

  bool _loading = true;
  bool _importing = false;
  bool _buildingFromText = false;
  String? _error;
  List<WorldPkgInfo> _packages = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final packages = await widget.controller.fetchWorldPackages();
      if (!mounted) {
        return;
      }
      final filenames = packages.map((pkg) => pkg.filename).toSet();
      _coverFutures.removeWhere((filename, _) => !filenames.contains(filename));
      setState(() {
        _packages = packages;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectPackage(WorldPkgInfo pkg) async {
    try {
      await widget.controller.selectWorldPackage(pkg);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _importPackage() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['wpkg'],
    );

    final path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }

    setState(() {
      _importing = true;
    });

    try {
      await widget.controller.importWorldPackage(path);
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
    }
  }

  Future<void> _buildPackageFromText() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md'],
    );

    final path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }

    setState(() {
      _buildingFromText = true;
    });

    try {
      await widget.controller.buildWorldPackageFromText(path);
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _buildingFromText = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: widget.controller.openStart,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.strings.text('library.title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Flexible(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    if (widget.controller.supportsLocalWorldPkgBuild)
                      FilledButton.tonalIcon(
                        onPressed: _importing || _buildingFromText
                            ? null
                            : _buildPackageFromText,
                        icon: _buildingFromText
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_stories_rounded),
                        label: Text(
                          _buildingFromText
                              ? _buildFromTextLabel(busy: true)
                              : _buildFromTextLabel(),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: _importing || _buildingFromText
                          ? null
                          : _importPackage,
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(
                        _importing
                            ? widget.strings.text('library.importing')
                            : widget.strings.text('library.import'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  @override
  void dispose() {
    _gridController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _coverFutureFor(WorldPkgInfo pkg) {
    return _coverFutures.putIfAbsent(
      pkg.filename,
      () => widget.controller.api.getWorldPkgCover(pkg.filename),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(widget.strings.text('library.loading')),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _refresh,
                child: Text(widget.strings.text('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (_packages.isEmpty) {
      return Center(child: Text(widget.strings.text('library.empty')));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? constraints.maxWidth >= 1500
                  ? 6
                  : 5
            : constraints.maxWidth >= 860
            ? 4
            : constraints.maxWidth >= 620
            ? 3
            : 2;
        final childAspectRatio = constraints.maxWidth >= 1300 ? 0.78 : 0.72;

        return Scrollbar(
          controller: _gridController,
          thumbVisibility: constraints.maxWidth >= 960,
          child: GridView.builder(
            key: const PageStorageKey<String>('library-grid'),
            controller: _gridController,
            cacheExtent: 1400,
            padding: const EdgeInsets.all(24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: _packages.length,
            itemBuilder: (context, index) {
              final pkg = _packages[index];
              return RepaintBoundary(
                child: _PackageCard(
                  key: ValueKey(pkg.filename),
                  pkg: pkg,
                  controller: widget.controller,
                  strings: widget.strings,
                  coverFuture: _coverFutureFor(pkg),
                  onSelect: () => _selectPackage(pkg),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _buildFromTextLabel({bool busy = false}) {
    final english = widget.strings.locale.startsWith('en');
    if (busy) {
      return english ? 'Building...' : '正在生成...';
    }
    return english ? 'Build From Text' : '从文本生成';
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    super.key,
    required this.pkg,
    required this.controller,
    required this.strings,
    required this.coverFuture,
    required this.onSelect,
  });

  final WorldPkgInfo pkg;
  final AppController controller;
  final AppStrings strings;
  final Future<Uint8List?> coverFuture;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final active = controller.currentPkgName == pkg.name;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: active ? const Color(0x88D6922F) : const Color(0x223A4A68),
        ),
        color: const Color(0xCC101A2B),
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  pkg.hasCover
                      ? _CoverArt(title: pkg.name, coverFuture: coverFuture)
                      : _FallbackCover(title: pkg.name),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: active ? 1 : 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFD6922F),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pkg.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '${(pkg.size / 1024).toStringAsFixed(0)} KB',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA6B4CB),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onSelect,
                    child: Text(strings.text('library.select')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.title, required this.coverFuture});

  final String title;
  final Future<Uint8List?> coverFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: coverFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _FallbackCover(title: title);
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stackTrace) =>
              _FallbackCover(title: title),
        );
      },
    );
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final seed = title.runes.fold<int>(0, (value, rune) => value + rune);
    final colors = <List<Color>>[
      const [Color(0xFF1B3A66), Color(0xFF0A6B74)],
      const [Color(0xFF51284F), Color(0xFF8B3D69)],
      const [Color(0xFF1A4D3A), Color(0xFF49895F)],
      const [Color(0xFF4A2A16), Color(0xFF875C28)],
      const [Color(0xFF25305F), Color(0xFF5A7FD3)],
    ][seed % 5];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          title.isEmpty ? '?' : title.substring(0, 1),
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.88),
          ),
        ),
      ),
    );
  }
}
