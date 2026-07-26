abstract final class StarDodgeRules {
  static const dungDodgeV2BaseRampSeconds = 120.0;
  static const dungDodgeV2MaximumSeconds = 300.0;

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

  static double dungDodgeV2SpawnInterval(double elapsedSeconds) {
    if (elapsedSeconds <= dungDodgeV2BaseRampSeconds) {
      return spawnInterval(elapsedSeconds / dungDodgeV2BaseRampSeconds);
    }
    final extendedProgress =
        ((elapsedSeconds - dungDodgeV2BaseRampSeconds) /
                (dungDodgeV2MaximumSeconds - dungDodgeV2BaseRampSeconds))
            .clamp(0.0, 1.0);
    return 0.14 - (0.06 * extendedProgress);
  }

  static double dungDodgeV2FallingSpeed(double elapsedSeconds) {
    if (elapsedSeconds <= dungDodgeV2BaseRampSeconds) {
      return fallingSpeed(elapsedSeconds / dungDodgeV2BaseRampSeconds);
    }
    final extendedProgress =
        ((elapsedSeconds - dungDodgeV2BaseRampSeconds) /
                (dungDodgeV2MaximumSeconds - dungDodgeV2BaseRampSeconds))
            .clamp(0.0, 1.0);
    return 680 + (240 * extendedProgress);
  }
}
