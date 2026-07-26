import 'dart:math';

abstract final class GravitySwitchRules {
  // One course column is exactly one displayed player width.
  static const columnWidth = 48.0;
  static const gravityAcceleration = 5200.0;
  static const maxVerticalSpeed = 1400.0;
  static const surfaceSnapTolerance = 10.0;
  static const initialScrollSpeed = 160.0;
  static const accelerationPerSecond = 1.5;

  static double scrollSpeed(double elapsedSeconds) => min(
    360,
    initialScrollSpeed + (accelerationPerSecond * max(0, elapsedSeconds)),
  );

  static int safeColumnCount(double elapsedSeconds) =>
      max(1, 4 - (elapsedSeconds / 20).floor());

  static double hazardHeight(double elapsedSeconds) =>
      min(205, 112 + (1.55 * elapsedSeconds));

  static double alternatingPatternChance(double elapsedSeconds) =>
      min(0.92, 0.42 + (0.0083 * elapsedSeconds));

  static String formatSurvival(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(2)}초';

  static String formatHudTime(int milliseconds) =>
      (milliseconds / 1000).toStringAsFixed(2);
}
