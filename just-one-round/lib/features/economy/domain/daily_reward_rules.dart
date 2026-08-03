import 'dart:math' show max;

/// The server uses the same tiers when it grants the previous day's reward.
/// Keep this copy for previews, UI copy, and deterministic client tests.
abstract final class DailyRewardRules {
  static const baseParticipationCoins = 10;
  static const otherCoins = 5;
  static const topSeventyPercentCoins = baseParticipationCoins;
  static const topHalfCoins = 30;
  static const topThirtyPercentCoins = 40;
  static const topTenPercentCoins = 50;
  static const thirdPlaceCoins = 70;
  static const secondPlaceCoins = 80;
  static const firstPlaceCoins = 100;

  static int coinsForResult({required int rank, required int participants}) {
    if (rank <= 0 || participants <= 0 || rank > participants) return 0;
    if (rank == 1) return firstPlaceCoins;
    if (rank == 2) return secondPlaceCoins;
    if (rank == 3) return thirdPlaceCoins;

    final topPercent = max(1, (rank * 100 + participants - 1) ~/ participants);
    if (topPercent <= 10) return topTenPercentCoins;
    if (topPercent <= 30) return topThirtyPercentCoins;
    if (topPercent <= 50) return topHalfCoins;
    if (topPercent <= 70) return topSeventyPercentCoins;
    return otherCoins;
  }

  static int experienceForCoins(int coins) => max(0, coins);
}
