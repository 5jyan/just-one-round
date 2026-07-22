abstract final class StarDodgeRules {
  static String formatSurvival(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(2)}초';

  static double spawnInterval(double progress) {
    final normalizedProgress = progress.clamp(0.0, 1.0);
    return 0.62 - (0.48 * normalizedProgress);
  }

  static double fallingSpeed(double progress) {
    final normalizedProgress = progress.clamp(0.0, 1.0);
    return 170 + (510 * normalizedProgress * normalizedProgress);
  }
}
