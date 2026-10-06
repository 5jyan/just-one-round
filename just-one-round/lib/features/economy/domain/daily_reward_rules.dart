import 'dart:math' show max;

/// The server uses the same tiers when it grants the previous day's reward.
/// Keep this copy for previews, UI copy, and deterministic client tests.
abstract final class DailyRewardRules {
  static const dailyBaseCoins = 30;
  static const otherRankingBonusCoins = 0;
  static const topSeventyPercentRankingBonusCoins = 20;
  static const topHalfRankingBonusCoins = 50;
  static const topThirtyPercentRankingBonusCoins = 80;
  static const topTenPercentRankingBonusCoins = 120;
  static const firstPlaceRankingBonusCoins = 250;

  static int rankingBonusForResult({
    required int rank,
    required int participants,
  }) {
    if (rank <= 0 || participants <= 0 || rank > participants) return 0;
    if (rank == 1) return firstPlaceRankingBonusCoins;

    final topPercent = max(1, (rank * 100 + participants - 1) ~/ participants);
    if (topPercent <= 10) return topTenPercentRankingBonusCoins;
    if (topPercent <= 30) return topThirtyPercentRankingBonusCoins;
    if (topPercent <= 50) return topHalfRankingBonusCoins;
    if (topPercent <= 70) return topSeventyPercentRankingBonusCoins;
    return otherRankingBonusCoins;
  }

  static int coinsForResult({required int rank, required int participants}) {
    if (rank <= 0 || participants <= 0 || rank > participants) return 0;
    return dailyBaseCoins +
        rankingBonusForResult(rank: rank, participants: participants);
  }

  static int experienceForCoins(int coins) => max(0, coins);
}
