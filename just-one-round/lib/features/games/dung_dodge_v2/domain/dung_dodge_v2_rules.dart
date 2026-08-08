abstract final class DungDodgeV2Rules {
  static const maximumDifficultySeconds = 260.0;

  static const _difficultyMilestones =
      <({double seconds, double spawnInterval, double fallingSpeed})>[
        (seconds: 0, spawnInterval: 0.62, fallingSpeed: 170),
        (seconds: 20, spawnInterval: 0.38, fallingSpeed: 297.5),
        (seconds: 80, spawnInterval: 0.14, fallingSpeed: 680),
        (seconds: 140, spawnInterval: 0.12, fallingSpeed: 760),
        (seconds: 200, spawnInterval: 0.10, fallingSpeed: 840),
        (seconds: 260, spawnInterval: 0.08, fallingSpeed: 920),
      ];

  static String formatSurvival(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(2)}초';

  static String formatHudTime(int milliseconds) =>
      (milliseconds / 1000).toStringAsFixed(2);

  static double spawnInterval(double elapsedSeconds) => _interpolateDifficulty(
    elapsedSeconds,
    valueOf: (milestone) => milestone.spawnInterval,
  );

  static double fallingSpeed(double elapsedSeconds) => _interpolateDifficulty(
    elapsedSeconds,
    valueOf: (milestone) => milestone.fallingSpeed,
  );

  static double _interpolateDifficulty(
    double elapsedSeconds, {
    required double Function(
      ({double seconds, double spawnInterval, double fallingSpeed}),
    )
    valueOf,
  }) {
    final seconds = elapsedSeconds.clamp(0.0, maximumDifficultySeconds);
    for (var index = 1; index < _difficultyMilestones.length; index++) {
      final previous = _difficultyMilestones[index - 1];
      final next = _difficultyMilestones[index];
      if (seconds <= next.seconds) {
        final progress =
            (seconds - previous.seconds) / (next.seconds - previous.seconds);
        final start = valueOf(previous);
        return start + ((valueOf(next) - start) * progress);
      }
    }
    return valueOf(_difficultyMilestones.last);
  }
}
