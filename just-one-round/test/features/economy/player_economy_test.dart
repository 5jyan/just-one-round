import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';

void main() {
  test('150 XP progression uses the requested cumulative thresholds', () {
    expect(PlayerEconomy.experienceThresholdForLevel(1), 0);
    expect(PlayerEconomy.experienceThresholdForLevel(2), 100);
    expect(PlayerEconomy.experienceThresholdForLevel(3), 350);
    expect(PlayerEconomy.experienceThresholdForLevel(4), 750);

    for (var level = 1; level <= 50; level++) {
      final threshold = PlayerEconomy.experienceThresholdForLevel(level);
      expect(PlayerEconomy.levelForExperience(threshold), level);
      if (level > 1) {
        expect(PlayerEconomy.levelForExperience(threshold - 1), level - 1);
      }
    }
  });

  test('remaining XP is computed from the current XP without resetting it', () {
    final economy = PlayerEconomy.fromTotals(coins: 40, experiencePoints: 225);

    expect(economy.experiencePoints, 225);
    expect(economy.level, 2);
    expect(economy.experienceToNextLevel, 125);
  });

  test('inverse remains stable at the one billion XP cap', () {
    final economy = PlayerEconomy.fromTotals(
      coins: 0,
      experiencePoints: PlayerEconomy.maxExperiencePoints,
    );
    final threshold = PlayerEconomy.experienceThresholdForLevel(economy.level);

    expect(economy.experiencePoints, PlayerEconomy.maxExperiencePoints);
    expect(threshold, lessThanOrEqualTo(PlayerEconomy.maxExperiencePoints));
    expect(
      PlayerEconomy.experienceThresholdForLevel(economy.level + 1),
      greaterThan(PlayerEconomy.maxExperiencePoints),
    );
  });
}
