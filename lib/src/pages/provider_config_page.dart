import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';
import 'model_list_page.dart';

class _DarkTheme {
  static const Color background = Color(0xFF0D1117);
  static const Color card = Color(0xFF161B22);
  static const Color border = Color(0xFF30363D);
  static const Color primary = Color(0xFFD6922F);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);
  static const Color selectedBg = Color(0xFF21262D);
  static const Color tagGreen = Color(0xFF238636);
  static const Color tagGreenText = Color(0xFF7EE787);
  static const Color tagRed = Color(0xFFDA3633);
  static const Color tagRedText = Color(0xFFFF7B72);
  static const double radius = 8;
  static const double radiusLg = 12;
}

class ProviderConfigPage extends StatefulWidget {
  const ProviderConfigPage({
    super.key,
    required this.controller,
    required this.strings,
    this.provider,
  });

  final AppController controller;
  final AppStrings strings;
  final ModelProvider? provider;

  @override
  State<ProviderConfigPage> createState() => _ProviderConfigPageState();
}

class _ProviderConfigPageState extends State<ProviderConfigPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiUrlController;
  late List<String> _models;

  String _selectedProviderType = 'openai';
  bool _isEnabled = true;
  int _bottomTabIndex = 0;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _testResult;

  bool get _isEditing => widget.provider != null;
  bool get _isCustomProvider => _selectedProviderType == 'custom';
  bool get _isZh => widget.strings.locale.startsWith('zh');

  String get _effectiveProviderName {
    if (_isCustomProvider) {
      return _nameController.text.trim();
    }
    return _selectedProviderType;
  }

  String? get _effectiveApiUrl {
    if (_isCustomProvider) {
      final value = _apiUrlController.text.trim();
      return value.isEmpty ? null : value;
    }
    return ModelProvider.fixedApiUrlFor(_selectedProviderType);
  }

  String t(String zh, String en) => _isZh ? zh : en;

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    final providerName = provider == null
        ? 'openai'
        : ModelProvider.canonicalProviderName(provider.name);
    _selectedProviderType = ModelProvider.knownProviders.contains(providerName)
        ? providerName
        : 'custom';
    _nameController = TextEditingController(
      text: _selectedProviderType == 'custom' ? provider?.name ?? '' : '',
    );
    _apiKeyController = TextEditingController(text: provider?.apiKey ?? '');
    _apiUrlController = TextEditingController(text: provider?.apiUrl ?? '');
    _models = List<String>.from(
      provider?.models ??
          ModelProvider.suggestedModelsFor(_selectedProviderType),
    );
    _isEnabled = provider?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveProvider() async {
    final name = _effectiveProviderName;
    if (name.isEmpty) {
      _showError(t('请输入提供商名称', 'Please enter a provider name'));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final newProvider = ModelProvider(
        name: name,
        apiKey: _apiKeyController.text.trim(),
        apiUrl: _effectiveApiUrl,
        models: _models.isEmpty
            ? ModelProvider.suggestedModelsFor(name)
            : List<String>.from(_models),
        enabled: _isEnabled,
      );

      final existing = widget.controller.modelProviders
          .where((p) => p.name != widget.provider?.name)
          .toList();
      existing.add(newProvider);

      await widget.controller.saveModelProviders(existing);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showError(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _testConnection() async {
    final apiKey = _apiKeyController.text.trim();
    final name = _effectiveProviderName;
    if (apiKey.isEmpty) {
      _showError(t('请输入 API Key', 'Please enter an API Key'));
      return;
    }
    if (name.isEmpty) {
      _showError(t('请先选择提供商', 'Please select a provider first'));
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final provider = ModelProvider(
        name: name,
        apiKey: apiKey,
        apiUrl: _effectiveApiUrl,
        models: _models.isEmpty
            ? ModelProvider.suggestedModelsFor(name)
            : List<String>.from(_models),
        enabled: _isEnabled,
      );

      await widget.controller.api.testModelProvider(provider);
      if (mounted) {
        setState(() => _testResult = 'success');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _testResult = 'failed');
        _showError(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: _DarkTheme.textPrimary),
        ),
        backgroundColor: _DarkTheme.card,
      ),
    );
  }

  Future<void> _saveModels(List<String> newModels) async {
    if (!mounted) {
      return;
    }
    setState(() => _models = List<String>.from(newModels));
  }

  void _selectProvider(String providerType) {
    setState(() {
      _selectedProviderType = providerType;
      _testResult = null;
      if (providerType != 'custom' && _models.isEmpty) {
        _models = List<String>.from(
          ModelProvider.suggestedModelsFor(providerType),
        );
      }
    });
  }

  Widget _buildProviderChip(String providerType) {
    final isSelected = _selectedProviderType == providerType;
    final label = providerType == 'custom'
        ? t('自定义', 'Custom')
        : ModelProvider.displayNameFor(providerType);
    return GestureDetector(
      onTap: () => _selectProvider(providerType),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _DarkTheme.selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(_DarkTheme.radius),
          border: Border.all(
            color: isSelected ? _DarkTheme.primary : _DarkTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Icon(
                Icons.check_circle,
                size: 16,
                color: _DarkTheme.primary,
              ),
            if (isSelected) const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? _DarkTheme.primary
                    : _DarkTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
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

  Widget _buildFixedUrlCard() {
    final fixedUrl = _effectiveApiUrl ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _DarkTheme.background,
        borderRadius: BorderRadius.circular(_DarkTheme.radius),
        border: Border.all(color: _DarkTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('固定 API 地址', 'Fixed API Base'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _DarkTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            fixedUrl,
            style: const TextStyle(fontSize: 14, color: _DarkTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              '这类官方提供商不需要手动填写 URL，只保留 API Key。',
              'This built-in provider uses a fixed official URL, so you only need the API key.',
            ),
            style: const TextStyle(fontSize: 12, color: _DarkTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    if (_testResult == null) {
      return const SizedBox.shrink();
    }

    final isSuccess = _testResult == 'success';
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_DarkTheme.radius),
        color: (isSuccess ? _DarkTheme.tagGreen : _DarkTheme.tagRed)
            .withOpacity(0.15),
        border: Border.all(
          color: isSuccess ? _DarkTheme.tagGreen : _DarkTheme.tagRed,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.error,
            color: isSuccess ? _DarkTheme.tagGreenText : _DarkTheme.tagRedText,
          ),
          const SizedBox(width: 8),
          Text(
            isSuccess
                ? t('连接成功', 'Connection successful')
                : t('连接失败', 'Connection failed'),
            style: TextStyle(
              color: isSuccess
                  ? _DarkTheme.tagGreenText
                  : _DarkTheme.tagRedText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DarkTheme.card,
            borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
            border: Border.all(color: _DarkTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('提供商类型', 'Provider Type'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _DarkTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final providerType in ModelProvider.presetProviderOrder)
                    _buildProviderChip(providerType),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DarkTheme.card,
            borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
            border: Border.all(color: _DarkTheme.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.power_settings_new, color: _DarkTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t('启用此提供商', 'Enable this provider'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _DarkTheme.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: _isEnabled,
                onChanged: (value) => setState(() => _isEnabled = value),
                activeColor: _DarkTheme.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DarkTheme.card,
            borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
            border: Border.all(color: _DarkTheme.border),
          ),
          child: Column(
            children: [
              if (_isCustomProvider) ...[
                _buildTextField(
                  controller: _nameController,
                  label: t('名称', 'Name'),
                  hint: t(
                    '例如：my-openai-compatible',
                    'e.g. my-openai-compatible',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _buildTextField(
                controller: _apiKeyController,
                label: 'API Key',
                hint: 'sk-...',
                obscure: true,
              ),
              const SizedBox(height: 16),
              if (_isCustomProvider)
                _buildTextField(
                  controller: _apiUrlController,
                  label: t('API Base URL', 'API Base URL'),
                  hint: 'https://example.com/v1',
                )
              else
                _buildFixedUrlCard(),
            ],
          ),
        ),
        _buildStatusCard(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _DarkTheme.textSecondary,
                        ),
                      )
                    : const Icon(Icons.wifi_tethering_rounded),
                label: Text(t('测试连接', 'Test Connection')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _DarkTheme.textPrimary,
                  side: const BorderSide(color: _DarkTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _isSaving ? null : _saveProvider,
                style: FilledButton.styleFrom(
                  backgroundColor: _DarkTheme.primary,
                  foregroundColor: _DarkTheme.background,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _DarkTheme.background,
                        ),
                      )
                    : Text(t('保存', 'Save')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildModelBody() {
    return ModelListView(
      providerName: _effectiveProviderName.isEmpty
          ? _selectedProviderType
          : _effectiveProviderName,
      models: _models,
      onModelsChanged: _saveModels,
      apiKey: _apiKeyController.text.trim(),
      apiUrl: _effectiveApiUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing
        ? t('编辑提供商', 'Edit Provider')
        : t('添加提供商', 'Add Provider');
    return Scaffold(
      backgroundColor: _DarkTheme.background,
      appBar: AppBar(
        backgroundColor: _DarkTheme.background,
        elevation: 0,
        leading: const BackButton(color: _DarkTheme.textPrimary),
        title: Text(
          title,
          style: const TextStyle(color: _DarkTheme.textPrimary),
        ),
      ),
      body: _bottomTabIndex == 0 ? _buildConfigBody() : _buildModelBody(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: _DarkTheme.card,
          border: Border(top: BorderSide(color: _DarkTheme.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _BottomTabButton(
                    icon: Icons.settings_outlined,
                    label: t('配置', 'Config'),
                    isSelected: _bottomTabIndex == 0,
                    onTap: () => setState(() => _bottomTabIndex = 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _BottomTabButton(
                    icon: Icons.model_training_outlined,
                    label: t('模型', 'Models'),
                    isSelected: _bottomTabIndex == 1,
                    onTap: () => setState(() => _bottomTabIndex = 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? _DarkTheme.selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(_DarkTheme.radius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? _DarkTheme.primary : _DarkTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? _DarkTheme.primary : _DarkTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
