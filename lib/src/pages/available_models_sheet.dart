import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../services/cors_proxy_client.dart';
import '../services/provider_api_utils.dart';

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
  static const double radiusSm = 6;
}

class AvailableModelsSheet extends StatefulWidget {
  const AvailableModelsSheet({
    super.key,
    this.providerName,
    this.apiKey,
    this.apiUrl,
  });

  final String? providerName;
  final String? apiKey;
  final String? apiUrl;

  @override
  State<AvailableModelsSheet> createState() => _AvailableModelsSheetState();
}

class _AvailableModelsSheetState extends State<AvailableModelsSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedModels = {};

  List<_AvailableModel> _allModels = [];
  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';
  bool _useCorsProxy = false;

  @override
  void initState() {
    super.initState();
    _fetchModelsFromApi();
  }

  Future<void> _fetchModelsFromApi() async {
    setState(() {
      _isLoading = true;
      _isError = false;
      _errorMessage = '';
    });

    try {
      final providerName = widget.providerName ?? 'openai';
      final apiKey = widget.apiKey ?? '';
      final apiUrl = widget.apiUrl;

      Object? response;

      if (kIsWeb && _useCorsProxy) {
        final proxyClient = CorsProxyClient();
        try {
          response = await proxyClient.fetchModels(
            provider: providerName,
            apiKey: apiKey,
            customApiUrl: apiUrl,
          );
        } finally {
          proxyClient.dispose();
        }
      } else {
        final modelsUrl = buildProviderModelsUrl(
          provider: providerName,
          customApiUrl: apiUrl,
        );

        final httpResponse = await http
            .get(
              Uri.parse(modelsUrl),
              headers: buildProviderHeaders(
                provider: providerName,
                apiKey: apiKey,
              ),
            )
            .timeout(const Duration(seconds: 30));

        if (httpResponse.statusCode == 200) {
          response = jsonDecode(httpResponse.body);
        } else if (httpResponse.statusCode == 401 ||
            httpResponse.statusCode == 403) {
          throw Exception('认证失败: 请检查 API Key 是否正确');
        } else if (httpResponse.statusCode == 404) {
          throw Exception('接口不存在: $modelsUrl');
        } else {
          throw Exception(
            'HTTP ${httpResponse.statusCode}: ${httpResponse.body.substring(0, httpResponse.body.length.clamp(0, 200))}',
          );
        }
      }

      final modelsData = <_AvailableModel>[];
      for (final modelId in parseModelIdsFromResponse(response)) {
        if (modelId.isEmpty || modelId.startsWith('ft:')) {
          continue;
        }
        modelsData.add(_AvailableModel(modelId, modelId, providerName));
      }

      if (modelsData.isEmpty) {
        final defaults =
            ModelProvider.defaultModels[providerName.toLowerCase()];
        if (defaults != null) {
          for (final modelId in defaults) {
            modelsData.add(_AvailableModel(modelId, modelId, providerName));
          }
        }
      }

      if (mounted) {
        setState(() {
          _allModels = modelsData;
          _isLoading = false;
        });
      }
    } on http.ClientException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          if (kIsWeb) {
            _errorMessage =
                '网络连接失败: ${e.message}\n\n这是 Web 端的 CORS 限制问题。\n\n解决方法：\n1. 点击下方"使用 CORS 代理"按钮\n2. 或者使用桌面版应用';
          } else {
            _errorMessage = '网络连接失败: ${e.message}\n\n请检查网络连接和 API 配置';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  String _getProviderFromUrl(String url) {
    if (url.contains('nvidia')) return 'NVIDIA';
    if (url.contains('openai')) return 'OpenAI';
    if (url.contains('aliyun') || url.contains('dashscope')) return '阿里云';
    if (url.contains('anthropic')) return 'Anthropic';
    if (url.contains('google') || url.contains('gemini')) return 'Google';
    if (url.contains('volcengine') || url.contains('ark')) return '火山引擎';
    return '未知';
  }

  List<_AvailableModel> get _filteredModels {
    if (_searchQuery.isEmpty) {
      return _allModels;
    }
    final query = _searchQuery.toLowerCase();
    return _allModels.where((m) {
      return m.id.toLowerCase().contains(query) ||
          m.name.toLowerCase().contains(query) ||
          m.provider.toLowerCase().contains(query);
    }).toList();
  }

  void _toggleSelection(String modelId) {
    setState(() {
      if (_selectedModels.contains(modelId)) {
        _selectedModels.remove(modelId);
      } else {
        _selectedModels.add(modelId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedModels.length == _filteredModels.length) {
        _selectedModels.clear();
      } else {
        _selectedModels.addAll(_filteredModels.map((m) => m.id));
      }
    });
  }

  void _confirmSelection() {
    Navigator.of(context).pop(_selectedModels.toList());
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '可用模型',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _DarkTheme.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : _fetchModelsFromApi,
                      style: TextButton.styleFrom(
                        foregroundColor: _DarkTheme.primary,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh, size: 16),
                          SizedBox(width: 4),
                          Text('刷新'),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _selectAll,
                      style: TextButton.styleFrom(
                        foregroundColor: _DarkTheme.primary,
                      ),
                      child: Text(
                        _selectedModels.length == _filteredModels.length &&
                                _filteredModels.isNotEmpty
                            ? '取消全选'
                            : '全选',
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
              if (_selectedModels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '已选择 ${_selectedModels.length} 个模型',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _DarkTheme.primary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(child: _buildContent()),
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
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      style: const TextStyle(color: _DarkTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: '输入模型名称筛选 (${_allModels.length} 个模型)',
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
                    const SizedBox(height: 12),
                    Row(
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
                          onPressed: _selectedModels.isNotEmpty
                              ? _confirmSelection
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _DarkTheme.primary,
                            foregroundColor: _DarkTheme.background,
                            disabledBackgroundColor: _DarkTheme.border,
                            disabledForegroundColor: _DarkTheme.textMuted,
                          ),
                          child: Text('添加 (${_selectedModels.length})'),
                        ),
                      ],
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

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _DarkTheme.primary),
            SizedBox(height: 16),
            Text(
              '正在获取模型列表...',
              style: TextStyle(color: _DarkTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_isError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: _DarkTheme.textMuted.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              '获取失败',
              style: TextStyle(color: _DarkTheme.textMuted.withOpacity(0.7)),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: _DarkTheme.textMuted.withOpacity(0.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _fetchModelsFromApi,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _DarkTheme.primary,
                    side: const BorderSide(color: _DarkTheme.primary),
                  ),
                ),
                if (kIsWeb && !_useCorsProxy) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _useCorsProxy = true);
                      _fetchModelsFromApi();
                    },
                    icon: const Icon(Icons.security),
                    label: const Text('使用 CORS 代理'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _DarkTheme.primary,
                      side: const BorderSide(color: _DarkTheme.primary),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }

    if (_allModels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.model_training_outlined,
              size: 48,
              color: _DarkTheme.textMuted.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无可用模型',
              style: TextStyle(color: _DarkTheme.textMuted.withOpacity(0.7)),
            ),
            const SizedBox(height: 4),
            Text(
              '请检查 API 地址和密钥配置',
              style: TextStyle(
                fontSize: 12,
                color: _DarkTheme.textMuted.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _filteredModels.length,
      itemBuilder: (context, index) {
        final model = _filteredModels[index];
        final isSelected = _selectedModels.contains(model.id);
        return _buildModelItem(model, isSelected);
      },
    );
  }

  Widget _buildModelItem(_AvailableModel model, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? _DarkTheme.selectedBg : _DarkTheme.card,
        borderRadius: BorderRadius.circular(_DarkTheme.radius),
        border: Border.all(
          color: isSelected ? _DarkTheme.primary : _DarkTheme.border,
        ),
      ),
      child: ListTile(
        onTap: () => _toggleSelection(model.id),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected
                ? _DarkTheme.primary.withOpacity(0.2)
                : _DarkTheme.selectedBg,
            borderRadius: BorderRadius.circular(_DarkTheme.radiusSm),
          ),
          child: Icon(
            Icons.model_training,
            color: isSelected ? _DarkTheme.primary : _DarkTheme.textSecondary,
            size: 20,
          ),
        ),
        title: Text(
          model.name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: _DarkTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          '${model.provider} · ${model.id}',
          style: const TextStyle(fontSize: 12, color: _DarkTheme.textMuted),
        ),
        trailing: Checkbox(
          value: isSelected,
          onChanged: (_) => _toggleSelection(model.id),
          activeColor: _DarkTheme.primary,
          checkColor: _DarkTheme.background,
          side: const BorderSide(color: _DarkTheme.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

class _AvailableModel {
  final String id;
  final String name;
  final String provider;

  _AvailableModel(this.id, this.name, this.provider);
}
