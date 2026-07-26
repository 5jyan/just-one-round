enum GameEndType {
  gameOver('GAME OVER'),
  clear('CLEAR!'),
  timeUp('TIME UP!');

  const GameEndType(this.label);

  final String label;
}

class GameResult {
  const GameResult({
    required this.score,
    required this.starsCollected,
    required this.collisions,
    required this.duration,
    required this.endType,
  });

  final int score;
  final int starsCollected;
  final int collisions;
  final Duration duration;
  final GameEndType endType;
}
