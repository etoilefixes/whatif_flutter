import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';
import 'provider_list_page.dart';

// 深色主题配色
class _DarkTheme {
  static const Color background = Color(0xFF0D1117);
  static const Color card = Color(0xFF161B22);
  static const Color border = Color(0xFF30363D);
  static const Color primary = Color(0xFFD6922F);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);
  static const Color selectedBg = Color(0xFF21262D);
  static const Color errorBg = Color(0x33DA3633);
  static const double radius = 8;
  static const double radiusLg = 12;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.strings,
  });

  final AppController controller;
  final AppStrings strings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _backendUrlController;
  final List<_ProviderEditor> _providerEditors = [];

  late VoiceConfig _voiceDraft;
  List<VoiceInfo> _voices = const <VoiceInfo>[];

  bool _savingProviders = false;
  bool _savingVoice = false;
  bool _loadingVoices = false;
  String? _testingProviderName;
  String? _voiceError;

  @override
  void initState() {
    super.initState();
    _backendUrlController = TextEditingController(
      text: widget.controller.api.baseUrl,
    );
    _voiceDraft = widget.controller.voiceConfig;

    for (final provider in widget.controller.modelProviders) {
      _providerEditors.add(_ProviderEditor.fromProvider(provider));
    }

    _loadVoices();
  }

  Future<void> _loadVoices() async {
    if (!widget.controller.backendReachable) {
      setState(() {
        _loadingVoices = false;
        _voices = const <VoiceInfo>[];
        _voiceError = widget.strings.text('settings.voiceUnavailable');
      });
      return;
    }

    setState(() {
      _loadingVoices = true;
      _voiceError = null;
    });

    try {
      final voices = await widget.controller.api.getVoices(
        locale: widget.controller.locale,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _voices = voices;
        if ((voices.isNotEmpty &&
                !voices.any((voice) => voice.name == _voiceDraft.voice)) ||
            _voiceDraft.voice.isEmpty) {
          _voiceDraft = _voiceDraft.copyWith(voice: voices.first.name);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingVoices = false;
        });
      }
    }
  }

  // ── Provider Actions ─────────────────────────────────────────────

  void _addProvider() {
    setState(() {
      _providerEditors.add(
        _ProviderEditor(name: '', apiKey: '', apiUrl: '', modelsText: ''),
      );
    });
  }

  void _removeProvider(int index) {
    setState(() {
      _providerEditors[index].dispose();
      _providerEditors.removeAt(index);
    });
  }

  Future<void> _saveProviders() async {
    setState(() {
      _savingProviders = true;
    });

    try {
      final providers = _providerEditors
          .map((e) {
            final models = e.modelsText
                .split('\n')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            return ModelProvider(
              name: e.nameController.text.trim(),
              apiKey: e.apiKeyController.text.trim(),
              apiUrl: e.apiUrlController.text.trim().isEmpty
                  ? null
                  : e.apiUrlController.text.trim(),
              models: models,
            );
          })
          .where((p) => p.name.isNotEmpty)
          .toList();

      if (!widget.controller.backendUrlManaged) {
        await widget.controller.updateBackendUrl(
          _backendUrlController.text.trim(),
        );
      }
      await widget.controller.retryConnection();
      _backendUrlController.text = widget.controller.api.baseUrl;
      await widget.controller.saveModelProviders(providers);
      await _loadVoices();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.strings.text('settings.connectionSaved'),
            style: const TextStyle(color: _DarkTheme.textPrimary),
          ),
          backgroundColor: _DarkTheme.card,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString(),
            style: const TextStyle(color: _DarkTheme.textPrimary),
          ),
          backgroundColor: _DarkTheme.card,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingProviders = false;
        });
      }
    }
  }

  Future<void> _testProvider(_ProviderEditor editor) async {
    final name = editor.nameController.text.trim();
    final apiKey = editor.apiKeyController.text.trim();
    if (apiKey.isEmpty || !widget.controller.api.supportsProviderTesting) {
      return;
    }

    final apiUrl = editor.apiUrlController.text.trim();
    final models = editor.modelsText
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final provider = ModelProvider(
      name: name,
      apiKey: apiKey,
      apiUrl: apiUrl.isEmpty ? null : apiUrl,
      models: models,
    );

    setState(() {
      _testingProviderName = name;
    });

    try {
      await widget.controller.api.testModelProvider(provider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.strings.text('settings.testSuccess'),
            style: const TextStyle(color: _DarkTheme.textPrimary),
          ),
          backgroundColor: _DarkTheme.card,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.strings.text('settings.testFailed'),
            style: const TextStyle(color: _DarkTheme.textPrimary),
          ),
          backgroundColor: _DarkTheme.card,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _testingProviderName = null;
        });
      }
    }
  }

  Future<void> _saveVoiceConfig() async {
    setState(() {
      _savingVoice = true;
    });

    try {
      await widget.controller.saveVoiceConfig(_voiceDraft);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.strings.text('settings.saved'),
            style: const TextStyle(color: _DarkTheme.textPrimary),
          ),
          backgroundColor: _DarkTheme.card,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString(),
            style: const TextStyle(color: _DarkTheme.textPrimary),
          ),
          backgroundColor: _DarkTheme.card,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingVoice = false;
        });
      }
    }
  }

  Future<void> _setLocale(String locale) async {
    await widget.controller.setLocale(locale);
    await _loadVoices();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    for (final editor in _providerEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Container(
        color: _DarkTheme.background,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: widget.controller.openStart,
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: _DarkTheme.card,
                      foregroundColor: _DarkTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.strings.text('settings.title'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _DarkTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TabBar(
                isScrollable: true,
                labelColor: _DarkTheme.primary,
                unselectedLabelColor: _DarkTheme.textSecondary,
                indicatorColor: _DarkTheme.primary,
                tabs: [
                  Tab(text: widget.strings.text('settings.tabProviders')),
                  Tab(text: widget.strings.text('settings.tabVoice')),
                  Tab(text: widget.strings.text('settings.tabLanguage')),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildProvidersTab(),
                  _buildVoiceTab(),
                  _buildLanguageTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Providers Tab ────────────────────────────────────────────────

  Future<void> _navigateToProviderList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProviderListPage(
          controller: widget.controller,
          strings: widget.strings,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildProvidersTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionCard(
          title: widget.strings.text('settings.backendUrl'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _backendUrlController,
                readOnly: widget.controller.backendUrlManaged,
                style: const TextStyle(color: _DarkTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: widget.controller.backendUrlManaged
                      ? 'Managed by the desktop runtime'
                      : widget.strings.text('settings.backendUrlHint'),
                  hintStyle: const TextStyle(color: _DarkTheme.textMuted),
                ),
              ),
              if (widget.controller.backendUrlManaged) ...[
                const SizedBox(height: 10),
                Text(
                  'The Flutter desktop app starts and owns the backend process automatically.',
                  style: TextStyle(
                    color: _DarkTheme.textSecondary.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mode: ${widget.controller.backendModeLabel}',
                  style: TextStyle(
                    color: _DarkTheme.textSecondary.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
              if (widget.controller.runtimeError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_DarkTheme.radius),
                    color: _DarkTheme.errorBg,
                    border: Border.all(color: const Color(0x55DA3633)),
                  ),
                  child: Text(
                    widget.controller.runtimeError!,
                    style: const TextStyle(color: _DarkTheme.textPrimary),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: widget.strings.text('settings.apiKeys'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.controller.modelProviders.length} ${widget.strings.text('provider.modelsCount')}',
                style: const TextStyle(
                  color: _DarkTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _navigateToProviderList,
                  icon: const Icon(Icons.manage_accounts_rounded),
                  label: Text(widget.strings.text('provider.listTitle')),
                  style: FilledButton.styleFrom(
                    backgroundColor: _DarkTheme.primary,
                    foregroundColor: _DarkTheme.background,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildDataManagementSection(),
        if (_providerEditors.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Legacy Configuration',
            style: TextStyle(
              color: _DarkTheme.textMuted.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _providerEditors.length; i++) ...[
            _buildProviderCard(i),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addProvider,
              icon: const Icon(Icons.add_rounded),
              label: Text(widget.strings.text('settings.addProvider')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _DarkTheme.textSecondary,
                side: const BorderSide(color: _DarkTheme.border),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _savingProviders ? null : _saveProviders,
              style: FilledButton.styleFrom(
                backgroundColor: _DarkTheme.primary,
                foregroundColor: _DarkTheme.background,
              ),
              child: _savingProviders
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _DarkTheme.background,
                      ),
                    )
                  : Text(widget.strings.text('settings.save')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProviderCard(int index) {
    final editor = _providerEditors[index];
    final isKnown = ModelProvider.knownProviders.contains(
      editor.nameController.text.trim().toLowerCase(),
    );
    final displayName = isKnown
        ? editor.nameController.text.trim()
        : widget.strings.text('settings.customProvider');

    return _SectionCard(
      title: displayName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            controller: editor.nameController,
            label: widget.strings.text('settings.providerName'),
            hint: widget.strings.text('settings.providerNameHint'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: editor.apiKeyController,
            label: widget.strings.text('settings.apiKey'),
            hint: 'sk-...',
            obscure: true,
          ),
          const SizedBox(height: 10),
          _buildTextField(
            controller: editor.apiUrlController,
            label: widget.strings.text('settings.apiUrl'),
            hint: widget.strings.text('settings.apiUrlHint'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: editor.modelsController,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(color: _DarkTheme.textPrimary),
            decoration: InputDecoration(
              labelText: widget.strings.text('settings.models'),
              labelStyle: const TextStyle(color: _DarkTheme.textSecondary),
              hintText: widget.strings.text('settings.modelsHint'),
              hintStyle: const TextStyle(color: _DarkTheme.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_DarkTheme.radius),
                borderSide: const BorderSide(color: _DarkTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_DarkTheme.radius),
                borderSide: const BorderSide(color: _DarkTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_DarkTheme.radius),
                borderSide: const BorderSide(color: _DarkTheme.primary),
              ),
              filled: true,
              fillColor: _DarkTheme.background,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonal(
                onPressed:
                    !widget.controller.api.supportsProviderTesting ||
                        _testingProviderName != null
                    ? null
                    : () => _testProvider(editor),
                style: FilledButton.styleFrom(
                  backgroundColor: _DarkTheme.selectedBg,
                  foregroundColor: _DarkTheme.textPrimary,
                ),
                child: _testingProviderName == editor.nameController.text.trim()
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _DarkTheme.textSecondary,
                        ),
                      )
                    : Text(widget.strings.text('settings.test')),
              ),
              const Spacer(),
              IconButton.outlined(
                onPressed: () => _removeProvider(index),
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: widget.strings.text('settings.removeProvider'),
                style: IconButton.styleFrom(
                  foregroundColor: _DarkTheme.textSecondary,
                  side: const BorderSide(color: _DarkTheme.border),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      style: const TextStyle(color: _DarkTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _DarkTheme.textSecondary),
        hintText: hint,
        hintStyle: const TextStyle(color: _DarkTheme.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_DarkTheme.radius),
          borderSide: const BorderSide(color: _DarkTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_DarkTheme.radius),
          borderSide: const BorderSide(color: _DarkTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_DarkTheme.radius),
          borderSide: const BorderSide(color: _DarkTheme.primary),
        ),
        filled: true,
        fillColor: _DarkTheme.background,
      ),
    );
  }

  // ── Voice Tab ────────────────────────────────────────────────────

  Widget _buildVoiceTab() {
    final items = _voices.toList()
      ..sort((left, right) => left.friendlyName.compareTo(right.friendlyName));
    final selectedVoice = items.isEmpty
        ? null
        : items.any((voice) => voice.name == _voiceDraft.voice)
        ? _voiceDraft.voice
        : items.first.name;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionCard(
          title: widget.strings.text('settings.voice'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _voiceDraft.enabled,
                onChanged: (value) {
                  setState(() {
                    _voiceDraft = _voiceDraft.copyWith(enabled: value);
                  });
                },
                title: Text(
                  widget.strings.text('settings.voiceEnable'),
                  style: const TextStyle(color: _DarkTheme.textPrimary),
                ),
                subtitle: Text(
                  widget.strings.text('settings.voiceHint'),
                  style: const TextStyle(color: _DarkTheme.textSecondary),
                ),
                activeColor: _DarkTheme.primary,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedVoice,
                      dropdownColor: _DarkTheme.card,
                      style: const TextStyle(color: _DarkTheme.textPrimary),
                      items: [
                        for (final voice in items)
                          DropdownMenuItem<String>(
                            value: voice.name,
                            child: Text(
                              voice.friendlyName.isEmpty
                                  ? voice.name
                                  : voice.friendlyName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _DarkTheme.textPrimary,
                              ),
                            ),
                          ),
                      ],
                      onChanged: items.isEmpty
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _voiceDraft = _voiceDraft.copyWith(
                                  voice: value,
                                );
                              });
                            },
                      decoration: InputDecoration(
                        labelText: widget.strings.text('settings.voiceLabel'),
                        labelStyle: const TextStyle(
                          color: _DarkTheme.textSecondary,
                        ),
                        hintText: _loadingVoices
                            ? widget.strings.text('settings.voiceLoading')
                            : widget.strings.text('settings.voiceUnavailable'),
                        hintStyle: const TextStyle(color: _DarkTheme.textMuted),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            _DarkTheme.radius,
                          ),
                          borderSide: const BorderSide(
                            color: _DarkTheme.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            _DarkTheme.radius,
                          ),
                          borderSide: const BorderSide(
                            color: _DarkTheme.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            _DarkTheme.radius,
                          ),
                          borderSide: const BorderSide(
                            color: _DarkTheme.primary,
                          ),
                        ),
                        filled: true,
                        fillColor: _DarkTheme.background,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: _loadingVoices ? null : _loadVoices,
                    style: FilledButton.styleFrom(
                      backgroundColor: _DarkTheme.selectedBg,
                      foregroundColor: _DarkTheme.textPrimary,
                    ),
                    child: _loadingVoices
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _DarkTheme.textSecondary,
                            ),
                          )
                        : Text(widget.strings.text('settings.voiceRefresh')),
                  ),
                ],
              ),
              if (_voiceError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_DarkTheme.radius),
                    color: _DarkTheme.errorBg,
                    border: Border.all(color: const Color(0x55DA3633)),
                  ),
                  child: Text(
                    _voiceError!,
                    style: const TextStyle(color: _DarkTheme.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _savingVoice ? null : _saveVoiceConfig,
                  style: FilledButton.styleFrom(
                    backgroundColor: _DarkTheme.primary,
                    foregroundColor: _DarkTheme.background,
                  ),
                  child: _savingVoice
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _DarkTheme.background,
                          ),
                        )
                      : Text(widget.strings.text('settings.save')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Data Management ───────────────────────────────────────────────

  Widget _buildDataManagementSection() {
    return _SectionCard(
      title: '数据管理',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '备份和恢复您的设置数据',
            style: TextStyle(color: _DarkTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportConfig,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('导出配置'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _DarkTheme.textSecondary,
                    side: const BorderSide(color: _DarkTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importConfig,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('导入配置'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _DarkTheme.textSecondary,
                    side: const BorderSide(color: _DarkTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _clearAllData,
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('清除所有数据'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF7B72),
              side: const BorderSide(color: const Color(0x55DA3633)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_DarkTheme.radius),
              color: _DarkTheme.background,
              border: Border.all(color: _DarkTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '存储状态',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _DarkTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildStorageInfoRow(
                  '模型商数量',
                  '${widget.controller.modelProviders.length}',
                ),
                _buildStorageInfoRow('语言设置', widget.controller.locale),
                _buildStorageInfoRow(
                  '语音状态',
                  widget.controller.voiceConfig.enabled ? '已启用' : '已禁用',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: _DarkTheme.textMuted),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, color: _DarkTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Future<void> _exportConfig() async {
    try {
      final config = <String, dynamic>{
        'modelProviders': widget.controller.modelProviders
            .map((p) => p.toJson())
            .toList(),
        'locale': widget.controller.locale,
        'voiceConfig': widget.controller.voiceConfig.toJson(),
        'exportTime': DateTime.now().toIso8601String(),
        'version': '1.0',
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '配置已复制到剪贴板',
              style: TextStyle(color: _DarkTheme.textPrimary),
            ),
            backgroundColor: _DarkTheme.card,
            action: SnackBarAction(
              label: '复制',
              textColor: _DarkTheme.primary,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '导出失败: $e',
              style: const TextStyle(color: _DarkTheme.textPrimary),
            ),
            backgroundColor: _DarkTheme.card,
          ),
        );
      }
    }
  }

  Future<void> _importConfig() async {
    // TODO: 实现从文件或剪贴板导入配置
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '导入功能开发中...',
            style: TextStyle(color: _DarkTheme.textPrimary),
          ),
          backgroundColor: _DarkTheme.card,
        ),
      );
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _DarkTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
          side: const BorderSide(color: _DarkTheme.border),
        ),
        title: const Text(
          '确认清除所有数据？',
          style: TextStyle(color: _DarkTheme.textPrimary),
        ),
        content: const Text(
          '这将删除所有模型商配置、语言设置等数据。此操作不可撤销。',
          style: TextStyle(color: _DarkTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: _DarkTheme.textSecondary,
            ),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDA3633),
              foregroundColor: Colors.white,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.controller.saveModelProviders([]);
        setState(() {
          _providerEditors.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '所有数据已清除',
                style: TextStyle(color: _DarkTheme.textPrimary),
              ),
              backgroundColor: _DarkTheme.card,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '清除失败: $e',
                style: const TextStyle(color: _DarkTheme.textPrimary),
              ),
              backgroundColor: _DarkTheme.card,
            ),
          );
        }
      }
    }
  }

  // ── Language Tab ─────────────────────────────────────────────────

  Widget _buildLanguageTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _LanguageTile(
          title: widget.strings.text('language.zh-CN'),
          selected: widget.controller.locale == 'zh-CN',
          onTap: () => _setLocale('zh-CN'),
        ),
        const SizedBox(height: 12),
        _LanguageTile(
          title: widget.strings.text('language.en'),
          selected: widget.controller.locale == 'en',
          onTap: () => _setLocale('en'),
        ),
      ],
    );
  }
}

// ── Provider Editor Helper ─────────────────────────────────────────

class _ProviderEditor {
  _ProviderEditor({
    required String name,
    required String apiKey,
    required String apiUrl,
    required String modelsText,
  }) : nameController = TextEditingController(text: name),
       apiKeyController = TextEditingController(text: apiKey),
       apiUrlController = TextEditingController(text: apiUrl),
       modelsController = TextEditingController(text: modelsText);

  factory _ProviderEditor.fromProvider(ModelProvider provider) {
    return _ProviderEditor(
      name: provider.name,
      apiKey: provider.apiKey,
      apiUrl: provider.apiUrl ?? '',
      modelsText: provider.models.join('\n'),
    );
  }

  final TextEditingController nameController;
  final TextEditingController apiKeyController;
  final TextEditingController apiUrlController;
  final TextEditingController modelsController;

  String get modelsText => modelsController.text;

  void dispose() {
    nameController.dispose();
    apiKeyController.dispose();
    apiUrlController.dispose();
    modelsController.dispose();
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
        border: Border.all(color: _DarkTheme.border),
        color: _DarkTheme.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _DarkTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
          border: Border.all(
            color: selected ? _DarkTheme.primary : _DarkTheme.border,
          ),
          color: selected ? _DarkTheme.selectedBg : _DarkTheme.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  color: _DarkTheme.textPrimary,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _DarkTheme.primary),
          ],
        ),
      ),
    );
  }
}
