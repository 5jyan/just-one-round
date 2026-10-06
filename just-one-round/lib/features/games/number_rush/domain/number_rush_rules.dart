import 'dart:math';

abstract final class NumberRushRules {
  static const boardSlotCount = 25;
  static const columnCount = 5;
  static const initialHighestNumber = 25;
  static const maximumNumber = 50;
  static const activeNumberTarget = 15;
  static const firstReserveNumber = initialHighestNumber + 1;
  static const rankingCeilingMs = 3600000;
  static const minimumRefillDelaySeconds = 0.5;
  static const maximumRefillDelaySeconds = 2.0;
  static const hintDelaySeconds = 3.0;
  static const pressureStageCount = 6;
  static const bossBurstDurationSeconds = 0.72;
  static const timeoutRankingScore = 0;

  static bool isMilestoneNumber(int number) =>
      number == 1 ||
      (number >= 10 && number <= maximumNumber && number % 10 == 0);

  static bool isBossMilestoneNumber(int number) =>
      number >= 10 && number <= maximumNumber && number % 10 == 0;

  static int pressureStageForClearedNumber(int clearedNumber) {
    if (clearedNumber >= 50) return 5;
    if (clearedNumber >= 40) return 4;
    if (clearedNumber >= 30) return 3;
    if (clearedNumber >= 20) return 2;
    if (clearedNumber >= 10) return 1;
    return 0;
  }

  static bool shouldRevealHint({
    required double secondsSinceProgress,
    required bool targetVisible,
    required bool isPlaying,
  }) => isPlaying && targetVisible && secondsSinceProgress >= hintDelaySeconds;

  static List<int> shuffledTiles(Random random) {
    final values = List<int>.generate(boardSlotCount, (index) => index + 1);
    values.shuffle(random);
    return values;
  }

  static bool shouldRefill({
    required int activeCount,
    required int nextReserveNumber,
  }) => activeCount < activeNumberTarget && nextReserveNumber <= maximumNumber;

  static double refillDelaySeconds(Random random) =>
      minimumRefillDelaySeconds +
      random.nextDouble() *
          (maximumRefillDelaySeconds - minimumRefillDelaySeconds);

  static bool isCorrectTap({required int expected, required int tapped}) =>
      expected == tapped;

  static int rankingScoreFromElapsedMs(int elapsedMs) =>
      (rankingCeilingMs - elapsedMs).clamp(1, rankingCeilingMs - 1);

  static int rankingScoreForResult({
    required int elapsedMs,
    required bool timedOut,
  }) => timedOut ? timeoutRankingScore : rankingScoreFromElapsedMs(elapsedMs);

  static int elapsedMsFromRankingScore(int score) =>
      (rankingCeilingMs - score).clamp(1, rankingCeilingMs - 1);

  static String formatElapsedMs(int elapsedMs) {
    final centiseconds = (elapsedMs / 10).round();
    final seconds = centiseconds ~/ 100;
    final fraction = centiseconds % 100;
    return '$seconds.${fraction.toString().padLeft(2, '0')}초';
  }

  static String formatRankingScore(int score) => score == timeoutRankingScore
      ? '0점'
      : formatElapsedMs(elapsedMsFromRankingScore(score));
}
