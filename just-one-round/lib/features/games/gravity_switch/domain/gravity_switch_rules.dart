import 'dart:math';

abstract final class GravitySwitchRules {
  static const switchDuration = 0.23;
  static const columnWidth = 40.0;

  static double scrollSpeed(double elapsedSeconds) =>
      min(360, 112 + (2.2 * elapsedSeconds));

  static int safeColumnCount(double elapsedSeconds) =>
      max(1, 4 - (elapsedSeconds / 20).floor());

  static double hazardHeight(double elapsedSeconds) =>
      min(205, 112 + (1.55 * elapsedSeconds));

  static double alternatingPatternChance(double elapsedSeconds) =>
      min(0.92, 0.42 + (0.0083 * elapsedSeconds));

  static String formatSurvival(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(2)}초';
}
