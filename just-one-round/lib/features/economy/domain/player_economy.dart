import 'dart:math' show max, sqrt;

class PlayerEconomy {
  static const maxExperiencePoints = 1000000000;

  const PlayerEconomy({
    required this.coins,
    required this.experiencePoints,
    required this.level,
    required this.experienceToNextLevel,
  });

  const PlayerEconomy.zero()
    : coins = 0,
      experiencePoints = 0,
      level = 1,
      experienceToNextLevel = 100;

  factory PlayerEconomy.fromJson(Map<String, dynamic> json) {
    return fromTotals(
      coins:
          (json['coins'] as num?)?.toInt() ??
          (json['coin_balance'] as num?)?.toInt() ??
          0,
      experiencePoints: (json['experience_points'] as num?)?.toInt() ?? 0,
    );
  }

  final int coins;
  final int experiencePoints;
  final int level;
  final int experienceToNextLevel;

  static PlayerEconomy fromTotals({
    required int coins,
    required int experiencePoints,
  }) {
    final safeCoins = max(0, coins);
    final safeExperience = max(0, experiencePoints);
    final level = levelForExperience(safeExperience);
    final nextLevelExperience = experienceThresholdForLevel(level + 1);
    return PlayerEconomy(
      coins: safeCoins,
      experiencePoints: safeExperience,
      level: level,
      experienceToNextLevel: max(0, nextLevelExperience - safeExperience),
    );
  }

  /// Returns the cumulative XP required to reach [level].
  ///
  /// The first level-up costs 100 XP, and each later level-up costs 150 XP
  /// more than the previous one.
  static int experienceThresholdForLevel(int level) {
    final n = max(0, level - 1);
    return n * (75 * n + 25);
  }

  static int levelForExperience(int experiencePoints) {
    final safeExperience = max(0, experiencePoints);
    // The closed-form inverse is fast for large ledgers. The small correction
    // loops make exact threshold values stable around floating point rounding.
    final estimate =
        ((sqrt(625 + 300 * safeExperience) - 25) / 150).floor() + 1;
    var level = max(1, estimate);
    while (level > 1 && experienceThresholdForLevel(level) > safeExperience) {
      level--;
    }
    while (experienceThresholdForLevel(level + 1) <= safeExperience) {
      level++;
    }
    return level;
  }
}
