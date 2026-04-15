import 'package:flutter/material.dart';

/// 暖色米色调主题配置
class AppTheme {
  // 背景色
  static const Color background = Color(0xFFF5F0E3);
  // 卡片色
  static const Color card = Color(0xFFFAF6EC);
  // 主色（深棕）
  static const Color primary = Color(0xFF6B5D3E);
  // 边框色
  static const Color border = Color(0xFFD4C9A8);
  // 标签绿色
  static const Color tagGreen = Color(0xFFD4EDDA);
  static const Color tagGreenText = Color(0xFF155724);
  // 标签蓝色
  static const Color tagBlue = Color(0xFFD1ECF1);
  static const Color tagBlueText = Color(0xFF0C5460);
  // 标签红色（未启用）
  static const Color tagRed = Color(0xFFF8D7DA);
  static const Color tagRedText = Color(0xFF721C24);
  // 浅棕色（用于选中背景）
  static const Color selectedBg = Color(0xFFE8DFC8);
  // 文字颜色
  static const Color textPrimary = Color(0xFF3D3525);
  static const Color textSecondary = Color(0xFF6B5D3E);
  static const Color textMuted = Color(0xFF9A8B6B);

  // 圆角
  static const double radius = 12.0;
  static const double radiusSm = 8.0;
  static const double radiusLg = 16.0;

  /// 获取主题数据
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        surface: card,
        background: background,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        floatingLabelStyle: const TextStyle(color: primary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primary;
          }
          return Colors.grey;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primary.withOpacity(0.3);
          }
          return Colors.grey.withOpacity(0.3);
        }),
      ),
    );
  }
}
