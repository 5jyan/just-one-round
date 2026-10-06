import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/economy/domain/daily_reward_rules.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';

void main() {
  test('기본 보상에 순위별 랭킹 보너스를 더한다', () {
    expect(DailyRewardRules.dailyBaseCoins, 30);
    expect(
      DailyRewardRules.rankingBonusForResult(rank: 1, participants: 24),
      250,
    );
    expect(DailyRewardRules.coinsForResult(rank: 1, participants: 24), 280);
    expect(DailyRewardRules.coinsForResult(rank: 2, participants: 24), 150);
    expect(DailyRewardRules.coinsForResult(rank: 3, participants: 24), 110);
    expect(DailyRewardRules.coinsForResult(rank: 10, participants: 100), 150);
    expect(DailyRewardRules.coinsForResult(rank: 30, participants: 100), 110);
    expect(DailyRewardRules.coinsForResult(rank: 50, participants: 100), 80);
    expect(DailyRewardRules.coinsForResult(rank: 70, participants: 100), 50);
    expect(DailyRewardRules.coinsForResult(rank: 71, participants: 100), 30);
    expect(DailyRewardRules.coinsForResult(rank: 4, participants: 24), 110);
    expect(DailyRewardRules.coinsForResult(rank: 8, participants: 24), 80);
    expect(DailyRewardRules.coinsForResult(rank: 13, participants: 24), 50);
    expect(DailyRewardRules.coinsForResult(rank: 17, participants: 24), 30);
  });

  test('잘못된 랭킹은 코인을 만들지 못한다', () {
    expect(DailyRewardRules.coinsForResult(rank: 0, participants: 24), 0);
    expect(DailyRewardRules.coinsForResult(rank: 25, participants: 24), 0);
  });

  test('경험치는 코인 사용과 무관하게 누적되고 레벨은 경험치에서 계산된다', () {
    final economy = PlayerEconomy.fromTotals(coins: 40, experiencePoints: 100);

    expect(economy.coins, 40);
    expect(economy.experiencePoints, 100);
    expect(economy.level, 2);
    expect(economy.experienceToNextLevel, 300);
  });
}
