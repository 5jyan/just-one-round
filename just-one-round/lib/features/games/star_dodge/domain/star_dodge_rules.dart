abstract final class StarDodgeRules {
  static const starScore = 100;
  static const collisionPenalty = 50;
  static const survivalScorePerSecond = 10;

  static int calculateScore({
    required int starsCollected,
    required int collisions,
    required int survivalSeconds,
  }) {
    return (starsCollected * starScore +
            survivalSeconds * survivalScorePerSecond -
            collisions * collisionPenalty)
        .clamp(0, 1 << 31);
  }

  static int collectStar(int currentScore) => currentScore + starScore;

  static int hitObstacle(int currentScore) {
    return (currentScore - collisionPenalty).clamp(0, currentScore);
  }

  static int addSurvivalTime(int currentScore, int wholeSeconds) {
    return currentScore + (wholeSeconds * survivalScorePerSecond);
  }

  static double spawnInterval(double progress) {
    final normalizedProgress = progress.clamp(0.0, 1.0);
    return 0.78 - (0.43 * normalizedProgress);
  }

  static double fallingSpeed(double progress) {
    final normalizedProgress = progress.clamp(0.0, 1.0);
    return 115 + (135 * normalizedProgress);
  }
}
