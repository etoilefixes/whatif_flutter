import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';
import 'provider_config_page.dart';

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
  static const double radius = 12;
  static const double radiusLg = 16;
  static const double radiusSm = 8;
}

class ProviderListPage extends StatefulWidget {
  const ProviderListPage({
    super.key,
    required this.controller,
    required this.strings,
  });

  final AppController controller;
  final AppStrings strings;

  @override
  State<ProviderListPage> createState() => _ProviderListPageState();
}

class _ProviderListPageState extends State<ProviderListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _isZh => widget.strings.locale.startsWith('zh');

  String t(String zh, String en) => _isZh ? zh : en;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ModelProvider> get _filteredProviders {
    final providers = widget.controller.modelProviders;
    if (_searchQuery.trim().isEmpty) {
      return providers;
    }

    final query = _searchQuery.trim().toLowerCase();
    return providers.where((provider) {
      final displayName = ModelProvider.displayNameFor(
        provider.name,
      ).toLowerCase();
      return provider.name.toLowerCase().contains(query) ||
          displayName.contains(query);
    }).toList();
  }

  Future<void> _navigateToProviderConfig(ModelProvider? provider) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProviderConfigPage(
          controller: widget.controller,
          strings: widget.strings,
          provider: provider,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _deleteProvider(ModelProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _DarkTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
          side: const BorderSide(color: _DarkTheme.border),
        ),
        title: Text(t('删除提供商', 'Delete Provider')),
        content: Text(
          t(
            '确定要删除 ${ModelProvider.displayNameFor(provider.name)} 吗？此操作无法撤销。',
            'Delete ${ModelProvider.displayNameFor(provider.name)}? This action cannot be undone.',
          ),
          style: const TextStyle(color: _DarkTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('删除', 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final updated = widget.controller.modelProviders
        .where((item) => item.name != provider.name)
        .toList();
    await widget.controller.saveModelProviders(updated);
    if (mounted) {
      setState(() {});
    }
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
          t('模型提供商', 'Model Providers'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: _DarkTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _navigateToProviderConfig(null),
            icon: const Icon(Icons.add, color: _DarkTheme.textPrimary),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(color: _DarkTheme.textPrimary),
              decoration: InputDecoration(
                hintText: t('搜索提供商', 'Search providers'),
                hintStyle: const TextStyle(color: _DarkTheme.textMuted),
                prefixIcon: const Icon(
                  Icons.search,
                  color: _DarkTheme.textMuted,
                ),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(
                          Icons.clear,
                          color: _DarkTheme.textMuted,
                        ),
                      ),
                filled: true,
                fillColor: _DarkTheme.card,
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
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredProviders.isEmpty
                  ? _buildEmptyState()
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.55,
                          ),
                      itemCount: _filteredProviders.length,
                      itemBuilder: (context, index) {
                        final provider = _filteredProviders[index];
                        return _ProviderCard(
                          provider: provider,
                          isZh: _isZh,
                          onTap: () => _navigateToProviderConfig(provider),
                          onDelete: () => _deleteProvider(provider),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 64,
            color: _DarkTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            t('还没有配置提供商', 'No providers configured yet'),
            style: TextStyle(
              color: _DarkTheme.textMuted.withOpacity(0.8),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _navigateToProviderConfig(null),
            icon: const Icon(Icons.add),
            label: Text(t('添加第一个提供商', 'Add your first provider')),
            style: FilledButton.styleFrom(
              backgroundColor: _DarkTheme.primary,
              foregroundColor: _DarkTheme.background,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.isZh,
    required this.onTap,
    required this.onDelete,
  });

  final ModelProvider provider;
  final bool isZh;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  String t(String zh, String en) => isZh ? zh : en;

  IconData get _providerIcon {
    switch (ModelProvider.canonicalProviderName(provider.name)) {
      case 'openai':
        return Icons.psychology;
      case 'deepseek':
        return Icons.bolt_outlined;
      case 'siliconflow':
        return Icons.stream_outlined;
      case 'anthropic':
        return Icons.auto_awesome;
      case 'gemini':
        return Icons.diamond_outlined;
      case 'dashscope':
        return Icons.cloud_outlined;
      case 'volcengine':
        return Icons.bar_chart_outlined;
      case 'nvidia':
        return Icons.memory_rounded;
      default:
        return Icons.hub;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        ModelProvider.knownProviders.contains(
          ModelProvider.canonicalProviderName(provider.name),
        )
        ? ModelProvider.displayNameFor(provider.name)
        : provider.name;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _DarkTheme.card,
            borderRadius: BorderRadius.circular(_DarkTheme.radiusLg),
            border: Border.all(color: _DarkTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _DarkTheme.selectedBg,
                      borderRadius: BorderRadius.circular(_DarkTheme.radius),
                    ),
                    child: Icon(_providerIcon, color: _DarkTheme.primary),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    color: _DarkTheme.card,
                    icon: const Icon(
                      Icons.more_horiz,
                      color: _DarkTheme.textMuted,
                    ),
                    onSelected: (value) {
                      if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(
                          t('删除', 'Delete'),
                          style: const TextStyle(color: _DarkTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _DarkTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                provider.apiKey.trim().isEmpty
                    ? t('未配置密钥', 'API key missing')
                    : t('只需填写密钥', 'Key-only preset'),
                style: const TextStyle(
                  fontSize: 12,
                  color: _DarkTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Tag(
                    text: provider.isUsable
                        ? t('已启用', 'Enabled')
                        : t('未启用', 'Disabled'),
                    backgroundColor: provider.isUsable
                        ? _DarkTheme.tagGreen.withOpacity(0.2)
                        : _DarkTheme.primary.withOpacity(0.15),
                    textColor: provider.isUsable
                        ? _DarkTheme.tagGreen
                        : _DarkTheme.primary,
                  ),
                  _Tag(
                    text: '${provider.models.length} ${t('个模型', 'models')}',
                    backgroundColor: _DarkTheme.selectedBg,
                    textColor: _DarkTheme.textPrimary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.backgroundColor,
    required this.textColor,
  });

  final String text;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(_DarkTheme.radiusSm),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: textColor)),
    );
  }
}
