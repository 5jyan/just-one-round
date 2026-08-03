import 'dart:math' show max, sqrt;

class PlayerEconomy {
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
    final economy = fromTotals(
      coins:
          (json['coins'] as num?)?.toInt() ??
          (json['coin_balance'] as num?)?.toInt() ??
          0,
      experiencePoints: (json['experience_points'] as num?)?.toInt() ?? 0,
    );
    return PlayerEconomy(
      coins: economy.coins,
      experiencePoints: economy.experiencePoints,
      level: (json['level'] as num?)?.toInt() ?? economy.level,
      experienceToNextLevel:
          (json['experience_to_next_level'] as num?)?.toInt() ??
          economy.experienceToNextLevel,
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
    final nextLevelExperience = level * level * 100;
    return PlayerEconomy(
      coins: safeCoins,
      experiencePoints: safeExperience,
      level: level,
      experienceToNextLevel: max(0, nextLevelExperience - safeExperience),
    );
  }

  static int levelForExperience(int experiencePoints) {
    final safeExperience = max(0, experiencePoints);
    return sqrt(safeExperience / 100).floor() + 1;
  }
}
