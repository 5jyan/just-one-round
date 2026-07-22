import 'dart:math';

abstract final class GravitySwitchRules {
  static const switchDuration = 0.34;

  static double scrollSpeed(double elapsedSeconds) =>
      min(680, 200 + (6.2 * elapsedSeconds));

  static double spawnInterval(double elapsedSeconds) =>
      max(0.34, 1.24 - (0.015 * elapsedSeconds));

  static double alternatingPatternChance(double elapsedSeconds) =>
      min(0.95, 0.30 + (0.011 * elapsedSeconds));

  static String formatSurvival(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(2)}초';
}
