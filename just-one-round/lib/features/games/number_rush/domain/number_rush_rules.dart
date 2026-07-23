import 'dart:math';

abstract final class NumberRushRules {
  static const tileCount = 25;
  static const columnCount = 5;
  static const rankingCeilingMs = 3600000;

  static List<int> shuffledTiles(Random random) {
    final values = List<int>.generate(tileCount, (index) => index + 1);
    values.shuffle(random);
    return values;
  }

  static bool isCorrectTap({required int expected, required int tapped}) =>
      expected == tapped;

  static int rankingScoreFromElapsedMs(int elapsedMs) =>
      (rankingCeilingMs - elapsedMs).clamp(1, rankingCeilingMs - 1);

  static int elapsedMsFromRankingScore(int score) =>
      (rankingCeilingMs - score).clamp(1, rankingCeilingMs - 1);

  static String formatElapsedMs(int elapsedMs) {
    final centiseconds = (elapsedMs / 10).round();
    final seconds = centiseconds ~/ 100;
    final fraction = centiseconds % 100;
    return '$seconds.${fraction.toString().padLeft(2, '0')}초';
  }

  static String formatRankingScore(int score) =>
      formatElapsedMs(elapsedMsFromRankingScore(score));
}
