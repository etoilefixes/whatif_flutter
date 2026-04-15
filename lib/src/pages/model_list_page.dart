import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';
import 'add_model_sheet.dart';
import 'available_models_sheet.dart';

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
  static const Color tagBlue = Color(0xFF1F6FEB);
  static const Color tagBlueText = Color(0xFF79C0FF);
  static const double radius = 8;
  static const double radiusLg = 12;
  static const double radiusSm = 6;
}

/// 模型列表页面（独立页面模式）
class ModelListPage extends StatelessWidget {
  const ModelListPage({
    super.key,
    required this.controller,
    required this.strings,
    required this.providerName,
    required this.models,
    required this.onModelsChanged,
  });

  final AppController controller;
  final AppStrings strings;
  final String providerName;
  final List<String> models;
  final ValueChanged<List<String>> onModelsChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DarkTheme.background,
      appBar: AppBar(
        backgroundColor: _DarkTheme.background,
        elevation: 0,
        leading: const BackButton(color: _DarkTheme.textPrimary),
        title: const Text(
          '模型列表',
          style: TextStyle(color: _DarkTheme.textPrimary),
        ),
      ),
      body: ModelListView(
        providerName: providerName,
        models: models,
        onModelsChanged: onModelsChanged,
      ),
    );
  }
}

/// 模型列表视图（可复用组件）
class ModelListView extends StatefulWidget {
  const ModelListView({
    super.key,
    required this.providerName,
    required this.models,
    required this.onModelsChanged,
    this.apiKey,
    this.apiUrl,
  });

  final String providerName;
  final List<String> models;
  final ValueChanged<List<String>> onModelsChanged;
  final String? apiKey;
  final String? apiUrl;

  @override
  State<ModelListView> createState() => _ModelListViewState();
}

class _ModelListViewState extends State<ModelListView> {
  late List<String> _models;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _models = List.from(widget.models);
    // 如果模型列表为空，自动加载预设模型
    if (_models.isEmpty) {
      _loadDefaultModels();
    }
  }

  @override
  void didUpdateWidget(ModelListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当外部数据变化时同步
    if (widget.models.length != _models.length ||
        !widget.models.every((m) => _models.contains(m))) {
      setState(() => _models = List.from(widget.models));
    }
  }

  /// 加载预设模型列表
  void _loadDefaultModels() {
    final defaultModels = ModelProvider.suggestedModelsFor(widget.providerName);
    if (defaultModels.isNotEmpty) {
      setState(() => _models = List.from(defaultModels));
      widget.onModelsChanged(_models);
    }
  }

  /// 从云端获取可用模型列表
  Future<void> _fetchModelsFromCloud() async {
    setState(() => _isLoading = true);

    // 模拟从 API 获取模型列表
    await Future.delayed(const Duration(seconds: 1));

    final defaultModels = ModelProvider.suggestedModelsFor(widget.providerName);

    if (mounted) {
      setState(() {
        _isLoading = false;
        // 合并现有模型和获取到的模型，去重
        final newModels = <String>{..._models, ...defaultModels}.toList();
        _models = newModels;
      });
      widget.onModelsChanged(_models);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '已获取模型',
            style: TextStyle(color: _DarkTheme.textPrimary),
          ),
          backgroundColor: _DarkTheme.card,
        ),
      );
    }
  }

  void _addModel() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddModelSheet(),
    );

    if (result != null && result['model'] != null) {
      final model = result['model'] as String;
      if (!_models.contains(model)) {
        setState(() => _models.add(model));
        widget.onModelsChanged(List.from(_models));
      }
    }
  }

  void _addFromAvailable() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AvailableModelsSheet(
        providerName: widget.providerName,
        apiKey: widget.apiKey,
        apiUrl: widget.apiUrl,
      ),
    );

    if (result != null && result.isNotEmpty) {
      for (final model in result) {
        if (!_models.contains(model)) {
          _models.add(model);
        }
      }
      setState(() {});
      widget.onModelsChanged(List.from(_models));
    }
  }

  void _removeModel(int index) {
    setState(() => _models.removeAt(index));
    widget.onModelsChanged(List.from(_models));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _DarkTheme.background,
      body: _models.isEmpty ? _buildEmptyState() : _buildModelList(),
      floatingActionButton: _buildFloatingButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildFloatingButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 刷新/获取模型按钮
          Container(
            decoration: BoxDecoration(
              color: _DarkTheme.card,
              borderRadius: BorderRadius.circular(_DarkTheme.radius),
              border: Border.all(color: _DarkTheme.border),
              boxShadow: [
                BoxShadow(
                  color: _DarkTheme.textPrimary.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _isLoading ? null : _fetchModelsFromCloud,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _DarkTheme.textSecondary,
                      ),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              color: _DarkTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          // 添加新模型按钮
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_DarkTheme.radius),
                boxShadow: [
                  BoxShadow(
                    color: _DarkTheme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _addFromAvailable,
                icon: const Icon(Icons.add),
                label: const Text('添加新模型'),
                style: FilledButton.styleFrom(
                  backgroundColor: _DarkTheme.primary,
                  foregroundColor: _DarkTheme.background,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_DarkTheme.radius),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.model_training_outlined,
            size: 64,
            color: _DarkTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无模型',
            style: TextStyle(
              color: _DarkTheme.textMuted.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击「获取模型」或「添加模型」按钮',
            style: TextStyle(
              color: _DarkTheme.textMuted.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _fetchModelsFromCloud,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _DarkTheme.textSecondary,
                        ),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: const Text('获取模型'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _DarkTheme.textSecondary,
                  side: const BorderSide(color: _DarkTheme.border),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _addFromAvailable,
                icon: const Icon(Icons.add),
                label: const Text('添加模型'),
                style: FilledButton.styleFrom(
                  backgroundColor: _DarkTheme.primary,
                  foregroundColor: _DarkTheme.background,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _models.length,
      itemBuilder: (context, index) {
        final model = _models[index];
        return ModelCard(model: model, onDelete: () => _removeModel(index));
      },
    );
  }
}

class ModelCard extends StatelessWidget {
  const ModelCard({super.key, required this.model, required this.onDelete});

  final String model;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                child: const Icon(
                  Icons.model_training,
                  color: _DarkTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _DarkTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '聊天模型',
                      style: TextStyle(
                        fontSize: 12,
                        color: _DarkTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                color: _DarkTheme.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: _DarkTheme.border),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTag('文本', Icons.text_fields),
              const SizedBox(width: 8),
              _buildTag('图片', Icons.image_outlined),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    Icons.build_outlined,
                    size: 16,
                    color: _DarkTheme.textMuted.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.psychology_outlined,
                    size: 16,
                    color: _DarkTheme.textMuted.withOpacity(0.7),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _DarkTheme.tagBlue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(_DarkTheme.radiusSm),
        border: Border.all(color: _DarkTheme.tagBlue.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _DarkTheme.tagBlueText),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: _DarkTheme.tagBlueText),
          ),
        ],
      ),
    );
  }
}
