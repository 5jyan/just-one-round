import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.text,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          height: 1.1,
          letterSpacing: -1.2,
        ),
        titleLarge: TextStyle(
          color: AppColors.text,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: TextStyle(
          color: AppColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}
