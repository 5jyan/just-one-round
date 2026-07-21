class GameResult {
  const GameResult({
    required this.score,
    required this.starsCollected,
    required this.collisions,
    required this.duration,
  });

  final int score;
  final int starsCollected;
  final int collisions;
  final Duration duration;
}
