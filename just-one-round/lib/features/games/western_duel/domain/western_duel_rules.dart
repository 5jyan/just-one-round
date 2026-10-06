import 'dart:math';

enum WesternDuelOutcome { win, lose, draw }

abstract final class WesternDuelRules {
  static const rulesVersion = 1;
  static const gameDuration = Duration(seconds: 30);
  static const safeCountdown = Duration(milliseconds: 3200);
  // A live player must respond within one second. Keep the wider historical
  // validation range for stored opponents and server compatibility.
  static const responseDeadlineMs = 1000;
  static const reactionWindowMs = 1500;

  static int standoffMilliseconds(Random random) => 3000 + random.nextInt(5001);

  static int botReactionMilliseconds(Random random) =>
      350 + random.nextInt(201);

  static bool isValidReaction(int milliseconds) =>
      milliseconds >= 1 && milliseconds <= reactionWindowMs;

  static int scoreForReaction(int milliseconds) {
    if (!isValidReaction(milliseconds)) {
      throw RangeError.range(milliseconds, 1, reactionWindowMs);
    }
    return 1000000 - milliseconds;
  }

  static int reactionForScore(int score) => 1000000 - score;

  static String formatMilliseconds(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(3)}초';

  static String formatRankingScore(int score) =>
      isValidReaction(reactionForScore(score))
      ? formatMilliseconds(reactionForScore(score))
      : '기록 없음';

  static WesternDuelOutcome compare(int mine, int theirs) => mine < theirs
      ? WesternDuelOutcome.win
      : mine > theirs
      ? WesternDuelOutcome.lose
      : WesternDuelOutcome.draw;
}
