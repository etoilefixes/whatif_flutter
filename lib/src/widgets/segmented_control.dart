import 'package:flutter/material.dart';

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
  static const double radiusSm = 6;
}

/// 自定义分段选择器
/// 使用 Container + Row + GestureDetector 实现，不用系统组件
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selectedValue,
    required this.onValueChanged,
    this.showCheckmark = true,
  });

  final List<Segment<T>> segments;
  final T selectedValue;
  final ValueChanged<T> onValueChanged;
  final bool showCheckmark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _DarkTheme.background,
        borderRadius: BorderRadius.circular(_DarkTheme.radius),
        border: Border.all(color: _DarkTheme.border),
      ),
      child: Row(
        children: segments.map((segment) {
          final isSelected = segment.value == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onValueChanged(segment.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _DarkTheme.selectedBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(_DarkTheme.radiusSm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showCheckmark && isSelected) ...[
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: _DarkTheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        segment.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? _DarkTheme.primary : _DarkTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 分段选择器选项
class Segment<T> {
  final T value;
  final String label;
  final IconData? icon;

  const Segment({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// 多选分段选择器
class MultiSelectSegmentedControl<T> extends StatelessWidget {
  const MultiSelectSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedValues,
    required this.onValueChanged,
  });

  final List<Segment<T>> segments;
  final Set<T> selectedValues;
  final ValueChanged<Set<T>> onValueChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _DarkTheme.background,
        borderRadius: BorderRadius.circular(_DarkTheme.radius),
        border: Border.all(color: _DarkTheme.border),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: segments.map((segment) {
          final isSelected = selectedValues.contains(segment.value);
          return GestureDetector(
            onTap: () {
              final newSet = Set<T>.from(selectedValues);
              if (isSelected) {
                newSet.remove(segment.value);
              } else {
                newSet.add(segment.value);
              }
              onValueChanged(newSet);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? _DarkTheme.selectedBg : Colors.transparent,
                borderRadius: BorderRadius.circular(_DarkTheme.radiusSm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected) ...[
                    const Icon(
                      Icons.check,
                      size: 14,
                      color: _DarkTheme.primary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    segment.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? _DarkTheme.primary : _DarkTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
