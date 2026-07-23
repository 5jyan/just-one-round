import 'dart:math';

abstract final class GravitySwitchRules {
  // One course column is exactly one displayed player width.
  static const columnWidth = 48.0;
  static const gravityAcceleration = 5200.0;
  static const maxVerticalSpeed = 1400.0;
  static const surfaceSnapTolerance = 10.0;

  static double scrollSpeed(double elapsedSeconds) =>
      min(360, 108 + (1.9 * elapsedSeconds));

  static int safeColumnCount(double elapsedSeconds) =>
      max(1, 4 - (elapsedSeconds / 20).floor());

  static double hazardHeight(double elapsedSeconds) =>
      min(205, 112 + (1.55 * elapsedSeconds));

  static double alternatingPatternChance(double elapsedSeconds) =>
      min(0.92, 0.42 + (0.0083 * elapsedSeconds));

  static String formatSurvival(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(2)}초';
}
