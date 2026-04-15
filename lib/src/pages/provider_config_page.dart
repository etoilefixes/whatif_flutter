import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';
import 'model_list_page.dart';

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
  late final TextEditingController _apiPathController;
  late List<String> _models;

  String _selectedProviderType = 'openai';
  bool _isEnabled = true;
  int _bottomTabIndex = 0;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _testResult;

  final List<String> _providerTypes = [
    'openai',
    'gemini',
    'anthropic',
    'dashscope',
    'volcengine',
    'nvidia',
  ];

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _nameController = TextEditingController(text: provider?.name ?? '');
    _apiKeyController = TextEditingController(text: provider?.apiKey ?? '');
    _apiUrlController = TextEditingController(text: provider?.apiUrl ?? '');
    _apiPathController = TextEditingController(text: '/v1/chat/completions');
    _models = List<String>.from(provider?.models ?? const <String>[]);

    if (provider != null) {
      final name = provider.name.toLowerCase();
      if (_providerTypes.contains(name)) {
        _selectedProviderType = name;
      }
      _isEnabled = provider.enabled;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _apiUrlController.dispose();
    _apiPathController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.provider != null;

  Future<void> _saveProvider() async {
    final name = _nameController.text.trim().isEmpty
        ? _selectedProviderType
        : _nameController.text.trim();
    if (name.isEmpty) {
      _showError('请输入提供商名称');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final newProvider = ModelProvider(
        name: name,
        apiKey: _apiKeyController.text.trim(),
        apiUrl: _apiUrlController.text.trim().isEmpty
            ? null
            : _apiUrlController.text.trim(),
        models: List<String>.from(_models),
        enabled: _isEnabled,
      );

      final existing = widget.controller.modelProviders
          .where((p) => p.name != widget.provider?.name)
          .toList();
      existing.add(newProvider);

      await widget.controller.saveModelProviders(existing);

      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testConnection() async {
    final apiKey = _apiKeyController.text.trim();
    final name = _nameController.text.trim().isEmpty
        ? _selectedProviderType
        : _nameController.text.trim();
    if (apiKey.isEmpty) {
      _showError('请输入 API Key');
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
        apiUrl: _apiUrlController.text.trim().isEmpty
            ? null
            : _apiUrlController.text.trim(),
        models: List<String>.from(_models),
        enabled: _isEnabled,
      );

      await widget.controller.api.testModelProvider(provider);
      if (mounted) {
        setState(() {
          _testResult = 'success';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _testResult = 'failed';
        });
        _showError(error.toString());
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
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

  void _navigateToModels() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ModelListPage(
          controller: widget.controller,
          strings: widget.strings,
          providerName: _nameController.text.trim(),
          models: _models,
          onModelsChanged: _saveModels,
        ),
      ),
    );
  }

  Future<void> _saveModels(List<String> newModels) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _models = List<String>.from(newModels);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DarkTheme.background,
      appBar: AppBar(
        backgroundColor: _DarkTheme.background,
        elevation: 0,
        leading: const BackButton(color: _DarkTheme.textPrimary),
        title: Text(
          _isEditing ? '编辑提供商' : '添加提供商',
          style: const TextStyle(color: _DarkTheme.textPrimary),
        ),
      ),
      body: _bottomTabIndex == 0 ? _buildConfigBody() : _buildModelBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
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
                  label: '配置',
                  isSelected: _bottomTabIndex == 0,
                  onTap: () => setState(() => _bottomTabIndex = 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BottomTabButton(
                  icon: Icons.model_training_outlined,
                  label: '模型',
                  isSelected: _bottomTabIndex == 1,
                  onTap: () => setState(() => _bottomTabIndex = 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 提供商类型选择器
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
              const Text(
                '提供商类型',
                style: TextStyle(
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
                  _buildProviderChip('openai', 'OpenAI'),
                  _buildProviderChip('gemini', 'Google Gemini'),
                  _buildProviderChip('anthropic', 'Anthropic Claude'),
                  _buildProviderChip('dashscope', '阿里云'),
                  _buildProviderChip('volcengine', '火山引擎'),
                  _buildProviderChip('nvidia', 'NVIDIA'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 是否启用开关
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
              const Expanded(
                child: Text(
                  '启用此提供商',
                  style: TextStyle(
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
        // 表单
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DarkTheme.card,
            borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
            border: Border.all(color: _DarkTheme.border),
          ),
          child: Column(
            children: [
              _buildTextField(
                controller: _nameController,
                label: '名称',
                hint: '例如：OpenAI',
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _apiKeyController,
                label: 'API Key',
                hint: 'sk-...',
                obscure: true,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _apiUrlController,
                label: 'API Base URL',
                hint: 'https://api.openai.com/v1',
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _apiPathController,
                label: 'API 路径',
                hint: '/v1/chat/completions',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 测试结果显示
        if (_testResult != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_DarkTheme.radius),
              color: _testResult == 'success'
                  ? _DarkTheme.tagGreen.withOpacity(0.2)
                  : _DarkTheme.tagRed.withOpacity(0.2),
              border: Border.all(
                color: _testResult == 'success'
                    ? _DarkTheme.tagGreen
                    : _DarkTheme.tagRed,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _testResult == 'success' ? Icons.check_circle : Icons.error,
                  color: _testResult == 'success'
                      ? _DarkTheme.tagGreenText
                      : _DarkTheme.tagRedText,
                ),
                const SizedBox(width: 8),
                Text(
                  _testResult == 'success' ? '连接成功' : '连接失败',
                  style: TextStyle(
                    color: _testResult == 'success'
                        ? _DarkTheme.tagGreenText
                        : _DarkTheme.tagRedText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        // 底部按钮
        Row(
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.share_outlined),
              color: _DarkTheme.textSecondary,
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.delete_outline),
              color: _DarkTheme.textSecondary,
            ),
            IconButton(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _DarkTheme.textSecondary,
                      ),
                    )
                  : const Icon(Icons.refresh),
              color: _DarkTheme.textSecondary,
            ),
            const Spacer(),
            FilledButton(
              onPressed: _isSaving ? null : _saveProvider,
              style: FilledButton.styleFrom(
                backgroundColor: _DarkTheme.primary,
                foregroundColor: _DarkTheme.background,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _DarkTheme.background,
                      ),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
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

  Widget _buildProviderChip(String value, String label) {
    final isSelected = _selectedProviderType == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedProviderType = value);
        _nameController.text = value;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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
              Icon(Icons.check_circle, size: 16, color: _DarkTheme.primary),
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

  Widget _buildModelBody() {
    // 直接在当前页面显示模型列表（使用 ModelListView 组件）
    // 使用选中的提供商类型或已保存的提供商名称
    final currentName = _nameController.text.trim();
    final providerName = currentName.isEmpty
        ? _selectedProviderType
        : currentName;
    return ModelListView(
      providerName: providerName,
      models: _models,
      onModelsChanged: _saveModels,
      apiKey: _apiKeyController.text.trim(),
      apiUrl: _apiUrlController.text.trim(),
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
        duration: const Duration(milliseconds: 200),
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
