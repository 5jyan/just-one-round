import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';

abstract final class NicknameColors {
  static const tokens = ['default', 'coral', 'mint', 'sky', 'violet', 'pink'];
  static const selectableTokens = ['coral', 'mint', 'sky', 'violet', 'pink'];

  static Color resolve(String token) => switch (token) {
    'coral' => const Color(0xFFFF8A80),
    'mint' => AppColors.reward,
    'sky' => const Color(0xFF76C7FF),
    'violet' => const Color(0xFFC7A0FF),
    'pink' => const Color(0xFFFF8FD0),
    _ => AppColors.text,
  };

  static String label(String token) => switch (token) {
    'coral' => '코랄',
    'mint' => '민트',
    'sky' => '스카이',
    'violet' => '바이올렛',
    'pink' => '핑크',
    _ => '기본',
  };
}
