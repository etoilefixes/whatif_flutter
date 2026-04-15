import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';
import 'provider_config_page.dart';

// 深色主题颜色常量
class _DarkTheme {
  static const Color background = Color(0xFF0D1117);
  static const Color card = Color(0xFF161B22);
  static const Color border = Color(0xFF30363D);
  static const Color primary = Color(0xFFD6922F);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF6E7681);
  static const Color tagGreen = Color(0xFF238636);
  static const Color tagGreenBg = Color(0xFF2EA043);
  static const Color tagBlue = Color(0xFF1F6FEB);
  static const Color tagBlueBg = Color(0xFF388BFD);
  static const double radius = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusSm = 8.0;
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ModelProvider> get _filteredProviders {
    if (_searchQuery.isEmpty) {
      return widget.controller.modelProviders;
    }
    final query = _searchQuery.toLowerCase();
    return widget.controller.modelProviders
        .where((p) => p.name.toLowerCase().contains(query))
        .toList();
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
        title: Text(widget.strings.text('provider.deleteTitle')),
        content: Text(
          widget.strings
              .text('provider.deleteConfirm')
              .replaceAll('{name}', provider.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final updated = widget.controller.modelProviders
          .where((p) => p.name != provider.name)
          .toList();
      await widget.controller.saveModelProviders(updated);
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
        title: const Text(
          '模型商',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: _DarkTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.history, color: _DarkTheme.textPrimary),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.terminal, color: _DarkTheme.textPrimary),
          ),
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
            // 搜索栏
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(color: _DarkTheme.textPrimary),
              decoration: InputDecoration(
                hintText: '搜索提供商',
                hintStyle: const TextStyle(color: _DarkTheme.textMuted),
                prefixIcon: const Icon(
                  Icons.search,
                  color: _DarkTheme.textMuted,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(
                          Icons.clear,
                          color: _DarkTheme.textMuted,
                        ),
                      )
                    : null,
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
            // 双列网格
            Expanded(
              child: _filteredProviders.isEmpty
                  ? _buildEmptyState()
                  : _buildProviderGrid(),
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
            '暂无提供商',
            style: TextStyle(
              color: _DarkTheme.textMuted.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _navigateToProviderConfig(null),
            icon: const Icon(Icons.add),
            label: const Text('添加第一个提供商'),
            style: FilledButton.styleFrom(backgroundColor: _DarkTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: _filteredProviders.length,
      itemBuilder: (context, index) {
        final provider = _filteredProviders[index];
        return ProviderCard(
          provider: provider,
          onTap: () => _navigateToProviderConfig(provider),
          onDelete: () => _deleteProvider(provider),
        );
      },
    );
  }
}

class ProviderCard extends StatelessWidget {
  const ProviderCard({
    super.key,
    required this.provider,
    required this.onTap,
    required this.onDelete,
  });

  final ModelProvider provider;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  String get _displayName {
    final name = provider.name.toLowerCase();
    if (ModelProvider.knownProviders.contains(name)) {
      return provider.name;
    }
    return '自定义';
  }

  IconData get _providerIcon {
    final name = provider.name.toLowerCase();
    switch (name) {
      case 'openai':
        return Icons.psychology;
      case 'anthropic':
      case 'claude':
        return Icons.auto_awesome;
      case 'gemini':
        return Icons.diamond_outlined;
      case 'dashscope':
        return Icons.cloud_outlined;
      case 'volcengine':
        return Icons.bar_chart;
      default:
        return Icons.hub;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(_providerIcon, size: 32, color: _DarkTheme.primary),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider.isUsable)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: _DarkTheme.tagGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.drag_indicator,
                      color: _DarkTheme.textMuted,
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Text(
              _displayName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _DarkTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _Tag(
                  text: provider.isUsable ? '已配置' : '未配置',
                  backgroundColor: provider.isUsable
                      ? _DarkTheme.tagGreen.withOpacity(0.2)
                      : const Color(0x33C96B54),
                  textColor: provider.isUsable
                      ? _DarkTheme.tagGreen
                      : const Color(0xFFC96B54),
                ),
                const SizedBox(width: 6),
                _Tag(
                  text: '${provider.models.length}个模型',
                  backgroundColor: _DarkTheme.primary.withOpacity(0.15),
                  textColor: _DarkTheme.primary,
                ),
              ],
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(_DarkTheme.radiusSm),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: textColor)),
    );
  }
}
