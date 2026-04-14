import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';

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
  final Map<String, TextEditingController> _modelControllers = {};
  final Map<String, TextEditingController> _temperatureControllers = {};
  final Map<String, TextEditingController> _budgetControllers = {};

  LlmConfigMap? _localConfig;
  late VoiceConfig _voiceDraft;
  List<VoiceInfo> _voices = const <VoiceInfo>[];

  bool _savingProviders = false;
  bool _savingConfig = false;
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

    _bootstrapConfig();
    _loadVoices();
  }

  Future<void> _bootstrapConfig() async {
    if (widget.controller.llmConfig == null) {
      await widget.controller.ensureLlmConfigLoaded();
    }
    if (!mounted) {
      return;
    }

    final config = widget.controller.llmConfig;
    if (config != null) {
      _populateConfigControllers(config);
    } else {
      setState(() {
        _localConfig = null;
      });
    }
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

  void _populateConfigControllers(LlmConfigMap config) {
    _disposeConfigControllers();

    void addSection(String section, Map<String, LlmSlotConfig> slots) {
      slots.forEach((name, slot) {
        final key = '$section::$name';
        _modelControllers[key] = TextEditingController(text: slot.model);
        _temperatureControllers[key] = TextEditingController(
          text: slot.temperature.toString(),
        );
        _budgetControllers[key] = TextEditingController(
          text: slot.thinkingBudget.toString(),
        );
      });
    }

    addSection('extractors', config.extractors);
    addSection('agents', config.agents);

    setState(() {
      _localConfig = config;
    });
  }

  // ── Provider Actions ─────────────────────────────────────────────

  void _addProvider() {
    setState(() {
      _providerEditors.add(_ProviderEditor(
        name: '',
        apiKey: '',
        apiUrl: '',
        modelsText: '',
      ));
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
      final providers = _providerEditors.map((e) {
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
      }).where((p) => p.name.isNotEmpty).toList();

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
          content: Text(widget.strings.text('settings.connectionSaved')),
        ),
      );
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
        SnackBar(content: Text(widget.strings.text('settings.testSuccess'))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.text('settings.testFailed'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _testingProviderName = null;
        });
      }
    }
  }

  // ── Config Actions ───────────────────────────────────────────────

  Future<void> _saveConfig() async {
    if (_localConfig == null) {
      return;
    }

    setState(() {
      _savingConfig = true;
    });

    try {
      final config = _buildConfigFromControllers(_localConfig!);
      await widget.controller.saveLlmConfig(config);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.text('settings.saved'))),
      );
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
          _savingConfig = false;
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
        SnackBar(content: Text(widget.strings.text('settings.saved'))),
      );
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

  void _applyPreset(String model) {
    if (_localConfig == null) {
      return;
    }

    void updateSection(String section, Map<String, LlmSlotConfig> slots) {
      slots.forEach((name, _) {
        final key = '$section::$name';
        _modelControllers[key]!.text = model;
      });
    }

    updateSection('extractors', _localConfig!.extractors);
    updateSection('agents', _localConfig!.agents);

    setState(() {});
  }

  LlmConfigMap _buildConfigFromControllers(LlmConfigMap source) {
    Map<String, LlmSlotConfig> buildSection(
      String section,
      Map<String, LlmSlotConfig> slots,
    ) {
      final next = <String, LlmSlotConfig>{};
      slots.forEach((name, slot) {
        final key = '$section::$name';
        next[name] = slot.copyWith(
          model: _modelControllers[key]!.text.trim(),
          temperature:
              double.tryParse(_temperatureControllers[key]!.text.trim()) ??
              slot.temperature,
          thinkingBudget:
              int.tryParse(_budgetControllers[key]!.text.trim()) ??
              slot.thinkingBudget,
        );
      });
      return next;
    }

    return LlmConfigMap(
      extractors: buildSection('extractors', source.extractors),
      agents: buildSection('agents', source.agents),
    );
  }

  void _disposeConfigControllers() {
    for (final controller in _modelControllers.values) {
      controller.dispose();
    }
    for (final controller in _temperatureControllers.values) {
      controller.dispose();
    }
    for (final controller in _budgetControllers.values) {
      controller.dispose();
    }
    _modelControllers.clear();
    _temperatureControllers.clear();
    _budgetControllers.clear();
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    for (final editor in _providerEditors) {
      editor.dispose();
    }
    _disposeConfigControllers();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
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
                    widget.strings.text('settings.title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: widget.strings.text('settings.tabProviders')),
                Tab(text: widget.strings.text('settings.tabModels')),
                Tab(text: widget.strings.text('settings.tabVoice')),
                Tab(text: widget.strings.text('settings.tabLanguage')),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildProvidersTab(),
                _buildModelConfigTab(),
                _buildVoiceTab(),
                _buildLanguageTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Providers Tab ────────────────────────────────────────────────

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
                decoration: InputDecoration(
                  hintText: widget.controller.backendUrlManaged
                      ? 'Managed by the desktop runtime'
                      : widget.strings.text('settings.backendUrlHint'),
                ),
              ),
              if (widget.controller.backendUrlManaged) ...[
                const SizedBox(height: 10),
                Text(
                  'The Flutter desktop app starts and owns the backend process automatically.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA7B5CC),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mode: ${widget.controller.backendModeLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A2BD),
                  ),
                ),
              ],
              if (widget.controller.runtimeError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0x33C96B54),
                  ),
                  child: Text(widget.controller.runtimeError!),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
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
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _savingProviders ? null : _saveProviders,
            child: _savingProviders
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.strings.text('settings.save')),
          ),
        ),
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
          TextField(
            controller: editor.nameController,
            decoration: InputDecoration(
              labelText: widget.strings.text('settings.providerName'),
              hintText: widget.strings.text('settings.providerNameHint'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: editor.apiKeyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: widget.strings.text('settings.apiKey'),
              hintText: 'sk-...',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: editor.apiUrlController,
            decoration: InputDecoration(
              labelText: widget.strings.text('settings.apiUrl'),
              hintText: widget.strings.text('settings.apiUrlHint'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: editor.modelsController,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: widget.strings.text('settings.models'),
              hintText: widget.strings.text('settings.modelsHint'),
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
                child: _testingProviderName ==
                        editor.nameController.text.trim()
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.strings.text('settings.test')),
              ),
              const Spacer(),
              IconButton.outlined(
                onPressed: () => _removeProvider(index),
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: widget.strings.text('settings.removeProvider'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Model Config Tab ─────────────────────────────────────────────

  Widget _buildModelConfigTab() {
    if (_localConfig == null) {
      return Center(child: Text(widget.strings.text('settings.noModelConfig')));
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonal(
              onPressed: () => _applyPreset('dashscope/qwen3.5-flash'),
              child: Text(widget.strings.text('settings.presetFlash')),
            ),
            FilledButton.tonal(
              onPressed: () => _applyPreset('dashscope/qwen3.5-plus'),
              child: Text(widget.strings.text('settings.presetPlus')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildConfigSection(
          title: widget.strings.text('settings.extractors'),
          section: 'extractors',
          slots: _localConfig!.extractors,
        ),
        const SizedBox(height: 16),
        _buildConfigSection(
          title: widget.strings.text('settings.agents'),
          section: 'agents',
          slots: _localConfig!.agents,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _savingConfig ? null : _saveConfig,
            child: _savingConfig
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.strings.text('settings.save')),
          ),
        ),
      ],
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
                title: Text(widget.strings.text('settings.voiceEnable')),
                subtitle: Text(widget.strings.text('settings.voiceHint')),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedVoice,
                      items: [
                        for (final voice in items)
                          DropdownMenuItem<String>(
                            value: voice.name,
                            child: Text(
                              voice.friendlyName.isEmpty
                                  ? voice.name
                                  : voice.friendlyName,
                              overflow: TextOverflow.ellipsis,
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
                        hintText: _loadingVoices
                            ? widget.strings.text('settings.voiceLoading')
                            : widget.strings.text('settings.voiceUnavailable'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: _loadingVoices ? null : _loadVoices,
                    child: _loadingVoices
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0x33C96B54),
                  ),
                  child: Text(_voiceError!),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _savingVoice ? null : _saveVoiceConfig,
                  child: _savingVoice
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
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

  Widget _buildConfigSection({
    required String title,
    required String section,
    required Map<String, LlmSlotConfig> slots,
  }) {
    return _SectionCard(
      title: title,
      child: Column(
        children: slots.entries.map((entry) {
          final slotKey = '$section::${entry.key}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.strings.slotLabel(entry.key),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _modelControllers[slotKey],
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _temperatureControllers[slotKey],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: widget.strings.text(
                            'settings.temperature',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _budgetControllers[slotKey],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: widget.strings.text(
                            'settings.thinkingBudget',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
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
  })  : nameController = TextEditingController(text: name),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x223A4A68)),
        color: const Color(0xCC101A2B),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0x88D6922F) : const Color(0x223A4A68),
          ),
          color: const Color(0xCC101A2B),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFFD6922F)),
          ],
        ),
      ),
    );
  }
}
