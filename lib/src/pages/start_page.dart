import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';

class StartPage extends StatelessWidget {
  const StartPage({super.key, required this.controller, required this.strings});

  final AppController controller;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final status = _StatusMeta.fromReadyState(controller.readyState, strings);
    final currentPkg = controller.currentPkgName;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Text(
                strings.text('app.name'),
                textAlign: TextAlign.center,
                style: GoogleFonts.cinzel(
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.text('start.subtitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFC0CCE4),
                ),
              ),
              const SizedBox(height: 28),
              _GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: status.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: status.color.withValues(alpha: 0.5),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          status.label,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: status.color,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      currentPkg == null || currentPkg.isEmpty
                          ? strings.text('start.noPkg')
                          : strings.text('start.currentPkg', {
                              'name': currentPkg,
                            }),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (controller.readyState == AppReadyState.offline) ...[
                      const SizedBox(height: 10),
                      Text(
                        strings.text('start.backendOffline'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFE7B07F),
                        ),
                      ),
                    ],
                    if (controller.runtimeError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        controller.runtimeError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFE8A9A0),
                        ),
                      ),
                    ],
                    if (controller.readyState == AppReadyState.needsConfig) ...[
                      const SizedBox(height: 10),
                      Text(
                        strings.text('start.needsApiKey'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFF1CC7A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _ActionButton(
                icon: Icons.menu_book_rounded,
                label: strings.text('start.selectPackage'),
                onPressed: controller.openLibrary,
              ),
              const SizedBox(height: 14),
              _ActionButton(
                icon: Icons.auto_stories_rounded,
                label: strings.text('start.startGame'),
                enabled: controller.canStart,
                onPressed: () => controller.openGameplay(),
              ),
              const SizedBox(height: 14),
              _ActionButton(
                icon: Icons.folder_open_rounded,
                label: strings.text('start.loadSave'),
                enabled: controller.backendReachable,
                onPressed: () => _openLoadSaveDialog(context),
              ),
              const SizedBox(height: 14),
              _ActionButton(
                icon: Icons.tune_rounded,
                label: strings.text('start.settings'),
                onPressed: controller.openSettings,
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: controller.retryConnection,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(strings.text('app.retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLoadSaveDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _LoadSaveDialog(controller: controller, strings: strings),
    );
  }
}

class _LoadSaveDialog extends StatefulWidget {
  const _LoadSaveDialog({required this.controller, required this.strings});

  final AppController controller;
  final AppStrings strings;

  @override
  State<_LoadSaveDialog> createState() => _LoadSaveDialogState();
}

class _LoadSaveDialogState extends State<_LoadSaveDialog> {
  bool _loading = true;
  bool _processing = false;
  String? _error;
  List<SaveInfo> _saves = const <SaveInfo>[];
  int? _selectedSlot;

  SaveInfo? get _selectedSave {
    for (final save in _saves) {
      if (save.slot == _selectedSlot) {
        return save;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final saves = await widget.controller.fetchSaves();
      if (!mounted) {
        return;
      }

      saves.sort((left, right) => right.saveTime.compareTo(left.saveTime));

      setState(() {
        _saves = saves;
        _selectedSlot = saves.isEmpty ? null : saves.first.slot;
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

  Future<void> _loadSelected() async {
    final save = _selectedSave;
    if (save == null || _loading || _processing) {
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      await widget.controller.loadSave(save);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
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
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: const Color(0xFF0F1626),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0x22D6922F)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.strings.text('saves.loadEyebrow'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: const Color(0xFFD6922F),
                                letterSpacing: 1.2,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.strings.text('saves.loadTitle'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.strings.text('saves.loadSubtitle'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFFA7B5CC)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _processing
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0x33C96B54),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(_error!),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(child: _buildBody(context)),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _processing
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(widget.strings.text('common.cancel')),
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: _loading || _processing ? null : _load,
                    child: Text(widget.strings.text('common.retry')),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _selectedSave == null || _processing
                        ? null
                        : _loadSelected,
                    icon: _processing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.archive_rounded),
                    label: Text(widget.strings.text('saves.loadNow')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
            Text(widget.strings.text('saves.loading')),
          ],
        ),
      );
    }

    if (_saves.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.strings.text('saves.emptyTitle'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              widget.strings.text('saves.emptyBody'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFA7B5CC)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _saves.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final save = _saves[index];
        final selected = save.slot == _selectedSlot;
        final needsSwitch =
            widget.controller.currentPkgName != null &&
            widget.controller.currentPkgName != save.worldpkgTitle;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _processing
              ? null
              : () {
                  setState(() {
                    _selectedSlot = save.slot;
                  });
                },
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0x88D6922F)
                    : const Color(0x223A4A68),
              ),
              color: selected
                  ? const Color(0xFF16233A)
                  : const Color(0xFF111B2E),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF1C2A43),
                  ),
                  child: Text(
                    save.slot == 0
                        ? widget.strings.text('saves.autoSaveBadge')
                        : widget.strings.text('saves.slotLabel', {
                            'slot': save.slot.toString(),
                          }),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        save.description.isEmpty
                            ? save.worldpkgTitle
                            : save.description,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        save.worldpkgTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFA7B5CC),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Text(
                            '${widget.strings.text('saves.phase')}: ${_phaseLabel(widget.strings, save.currentPhase)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF94A2BD)),
                          ),
                          Text(
                            widget.strings.text('saves.turnInfo', {
                              'turn': save.totalTurns.toString(),
                            }),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF94A2BD)),
                          ),
                          Text(
                            _formatSaveTime(context, save.saveTime),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF94A2BD)),
                          ),
                        ],
                      ),
                      if (needsSwitch) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.strings.text('saves.packageSwitch', {
                            'name': save.worldpkgTitle,
                          }),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFFD6B26C)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFFD6922F),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF15213A),
          disabledBackgroundColor: const Color(0xFF101725),
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0xFF60708D),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x223A4A68)),
          ),
        ),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xCC101A2B), Color(0xCC0C1322)],
        ),
        border: Border.all(color: const Color(0x223A4A68)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 30,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatusMeta {
  const _StatusMeta({required this.label, required this.color});

  final String label;
  final Color color;

  factory _StatusMeta.fromReadyState(AppReadyState state, AppStrings strings) {
    switch (state) {
      case AppReadyState.ready:
        return _StatusMeta(
          label: strings.text('start.ready'),
          color: const Color(0xFF63D89F),
        );
      case AppReadyState.offline:
        return _StatusMeta(
          label: strings.text('start.offline'),
          color: const Color(0xFFE29A68),
        );
      case AppReadyState.needsConfig:
        return _StatusMeta(
          label: strings.text('start.needsConfig'),
          color: const Color(0xFFF0C874),
        );
      case AppReadyState.loading:
        return const _StatusMeta(label: 'Loading', color: Color(0xFF9AB7FF));
    }
  }
}

String _phaseLabel(AppStrings strings, String? phase) {
  switch (phase) {
    case 'setup':
      return strings.text('saves.phaseSetup');
    case 'confrontation':
      return strings.text('saves.phaseConfrontation');
    case 'resolution':
      return strings.text('saves.phaseResolution');
    default:
      return strings.text('saves.phaseUnknown');
  }
}

String _formatSaveTime(BuildContext context, String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }

  final localizations = MaterialLocalizations.of(context);
  final local = parsed.toLocal();
  final day = localizations.formatMediumDate(local);
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: true,
  );
  return '$day $time';
}
