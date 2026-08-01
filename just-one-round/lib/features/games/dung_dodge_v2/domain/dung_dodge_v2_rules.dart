abstract final class DungDodgeV2Rules {
  static const baseRampSeconds = 120.0;
  static const maximumSeconds = 300.0;

  static String formatSurvival(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(2)}초';

  static String formatHudTime(int milliseconds) =>
      (milliseconds / 1000).toStringAsFixed(2);

  static double spawnInterval(double elapsedSeconds) {
    if (elapsedSeconds <= baseRampSeconds) {
      final progress = (elapsedSeconds / baseRampSeconds).clamp(0.0, 1.0);
      return 0.62 - (0.48 * progress);
    }
    final extendedProgress =
        ((elapsedSeconds - baseRampSeconds) /
                (maximumSeconds - baseRampSeconds))
            .clamp(0.0, 1.0);
    return 0.14 - (0.06 * extendedProgress);
  }

  static double fallingSpeed(double elapsedSeconds) {
    if (elapsedSeconds <= baseRampSeconds) {
      final progress = (elapsedSeconds / baseRampSeconds).clamp(0.0, 1.0);
      return 170 + (510 * progress * progress);
    }
    final extendedProgress =
        ((elapsedSeconds - baseRampSeconds) /
                (maximumSeconds - baseRampSeconds))
            .clamp(0.0, 1.0);
    return 680 + (240 * extendedProgress);
  }
}
