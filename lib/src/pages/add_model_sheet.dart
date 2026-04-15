import 'package:flutter/material.dart';

import '../widgets/segmented_control.dart';

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
  static const double radius = 8;
  static const double radiusLg = 12;
}

class AddModelSheet extends StatefulWidget {
  const AddModelSheet({super.key});

  @override
  State<AddModelSheet> createState() => _AddModelSheetState();
}

class _AddModelSheetState extends State<AddModelSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _modelIdController = TextEditingController();
  final TextEditingController _modelNameController = TextEditingController();

  String _selectedModelType = 'chat';
  Set<String> _inputModalities = {'text'};
  Set<String> _outputModalities = {'text'};
  Set<String> _capabilities = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _modelIdController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  void _confirmAdd() {
    final modelId = _modelIdController.text.trim();
    if (modelId.isNotEmpty) {
      Navigator.of(context).pop({'model': modelId});
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _DarkTheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 拖拽条
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _DarkTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '添加模型',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _DarkTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: _DarkTheme.textMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // TabBar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: _DarkTheme.card,
                  borderRadius: BorderRadius.circular(_DarkTheme.radius),
                  border: Border.all(color: _DarkTheme.border),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: _DarkTheme.selectedBg,
                    borderRadius: BorderRadius.circular(_DarkTheme.radius - 2),
                  ),
                  labelColor: _DarkTheme.primary,
                  unselectedLabelColor: _DarkTheme.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: '基本设置'),
                    Tab(text: '高级设置'),
                    Tab(text: '内置工具'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // TabBarView
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBasicTab(),
                    _buildAdvancedTab(),
                    _buildToolsTab(),
                  ],
                ),
              ),
              // 底部按钮
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  16 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: const BoxDecoration(
                  color: _DarkTheme.card,
                  border: Border(top: BorderSide(color: _DarkTheme.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: _DarkTheme.textSecondary,
                      ),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _confirmAdd,
                      style: FilledButton.styleFrom(
                        backgroundColor: _DarkTheme.primary,
                        foregroundColor: _DarkTheme.background,
                      ),
                      child: const Text('添加'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBasicTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // 模型ID
        _buildTextField(
          controller: _modelIdController,
          label: '模型ID',
          hint: '例如：gpt-4o',
        ),
        const SizedBox(height: 16),
        // 模型显示名称
        _buildTextField(
          controller: _modelNameController,
          label: '模型显示名称',
          hint: '例如：GPT-4o',
        ),
        const SizedBox(height: 24),
        // 模型类型
        const Text(
          '模型类型',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _DarkTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedControl<String>(
          segments: const [
            Segment(value: 'chat', label: '聊天'),
            Segment(value: 'image', label: '图像'),
            Segment(value: 'embedding', label: '嵌入'),
          ],
          selectedValue: _selectedModelType,
          onValueChanged: (value) => setState(() => _selectedModelType = value),
        ),
        const SizedBox(height: 24),
        // 输入模态
        const Text(
          '输入模态',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _DarkTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        MultiSelectSegmentedControl<String>(
          segments: const [
            Segment(value: 'text', label: '文本'),
            Segment(value: 'image', label: '图片'),
          ],
          selectedValues: _inputModalities,
          onValueChanged: (values) => setState(() => _inputModalities = values),
        ),
        const SizedBox(height: 24),
        // 输出模态
        const Text(
          '输出模态',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _DarkTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        MultiSelectSegmentedControl<String>(
          segments: const [
            Segment(value: 'text', label: '文本'),
            Segment(value: 'image', label: '图片'),
          ],
          selectedValues: _outputModalities,
          onValueChanged: (values) => setState(() => _outputModalities = values),
        ),
        const SizedBox(height: 24),
        // 能力
        const Text(
          '能力',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _DarkTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        MultiSelectSegmentedControl<String>(
          segments: const [
            Segment(value: 'tools', label: '工具'),
            Segment(value: 'reasoning', label: '推理'),
          ],
          selectedValues: _capabilities,
          onValueChanged: (values) => setState(() => _capabilities = values),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildAdvancedTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
              const Text(
                '高级参数',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _DarkTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: '上下文长度',
                hint: '例如：128000',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: '最大输出长度',
                hint: '例如：4096',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: '温度',
                hint: '例如：0.7',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
              const Text(
                '内置工具',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _DarkTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _buildToolItem('代码解释器', Icons.code),
              const Divider(height: 1, color: _DarkTheme.border),
              _buildToolItem('网页搜索', Icons.search),
              const Divider(height: 1, color: _DarkTheme.border),
              _buildToolItem('图像生成', Icons.image),
              const Divider(height: 1, color: _DarkTheme.border),
              _buildToolItem('文件分析', Icons.folder_open),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    TextEditingController? controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
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

  Widget _buildToolItem(String name, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: _DarkTheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 15,
                color: _DarkTheme.textPrimary,
              ),
            ),
          ),
          Switch(
            value: false,
            onChanged: (value) {},
            activeColor: _DarkTheme.primary,
          ),
        ],
      ),
    );
  }
}
