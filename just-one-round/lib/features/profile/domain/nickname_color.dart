import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';

abstract final class NicknameColors {
  static Color forLevel(int level) {
    if (level >= 30) return const Color(0xFFFFD23F);
    if (level >= 25) return const Color(0xFFFF4FA7);
    if (level >= 20) return const Color(0xFFB477FF);
    if (level >= 15) return const Color(0xFF5894FF);
    if (level >= 10) return const Color(0xFF36F58A);
    if (level >= 5) return const Color(0xFFFFF15A);
    return AppColors.text;
  }

  static String labelForLevel(int level) {
    if (level >= 30) return '골드';
    if (level >= 25) return '핑크';
    if (level >= 20) return '퍼플';
    if (level >= 15) return '블루';
    if (level >= 10) return '그린';
    if (level >= 5) return '노랑';
    return '기본';
  }

  /// Resolves nickname color tokens from historical/server snapshots.
  static Color resolve(String token) => switch (token) {
    'coral' => const Color(0xFFFF8A80),
    'yellow' => const Color(0xFFFFF15A),
    'mint' => const Color(0xFF36F58A),
    'cyan' => const Color(0xFF20DFFF),
    'sky' => const Color(0xFF5894FF),
    'violet' => const Color(0xFFB477FF),
    'pink' => const Color(0xFFFF4FA7),
    'gold' => const Color(0xFFFFD23F),
    _ => AppColors.text,
  };
}
