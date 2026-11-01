class WindDartsOpponent {
  const WindDartsOpponent({
    required this.nickname,
    required this.shotScores,
    required this.isBot,
  });

  final String nickname;
  final List<int> shotScores;
  final bool isBot;

  int get score => shotScores.fold(0, (sum, value) => sum + value);

  factory WindDartsOpponent.fromJson(
    Map<String, dynamic> json, {
    required int attemptVersion,
  }) {
    final expectedShotCount = switch (attemptVersion) {
      1 => 5,
      2 || 3 => 6,
      4 => 7,
      _ => throw FormatException(
        'Unsupported wind darts attempt version: $attemptVersion',
      ),
    };
    final rawShots = json['shot_scores'];
    if (rawShots is! List<dynamic>) {
      throw const FormatException('Wind darts opponent scores are missing');
    }
    final shots = rawShots
        .map((value) => (value as num).toInt())
        .toList(growable: false);
    if (shots.length != expectedShotCount) {
      throw FormatException(
        'Expected $expectedShotCount dart scores for version $attemptVersion',
      );
    }
    return WindDartsOpponent(
      nickname: json['nickname'] as String? ?? '펍의 단골',
      shotScores: shots,
      isBot: json['is_bot'] as bool? ?? false,
    );
  }
}
