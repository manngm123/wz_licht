// theme.dart – Farben wie in der Web-Version

import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF111827);
  static const card = Color(0xFF1F2937);
  static const border = Color(0xFF4B5563);
  static const text = Color(0xFFF9FAFB);
  static const muted = Color(0xFF9CA3AF);
  static const value = Color(0xFFD1D5DB);
  static const info = Color(0xFF6B7280);
  static const stepButton = Color(0xFF374151);

  static const onButton = Color(0xFF22C55E);
  static const onButtonText = Color(0xFF052E16);
  static const offButton = Color(0xFFEF4444);

  static const stateOn = Color(0xFF4ADE80);
  static const stateOff = Color(0xFFF87171);
  static const accent = Color(0xFFFACC15);
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.background,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: true,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      thumbColor: AppColors.accent,
      inactiveTrackColor: AppColors.stepButton,
      trackHeight: 6,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
