import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/economy/domain/daily_reward_rules.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';

void main() {
  test('전날 순위별 코인 보상은 경계값에서 고정된다', () {
    expect(DailyRewardRules.coinsForResult(rank: 1, participants: 24), 100);
    expect(DailyRewardRules.coinsForResult(rank: 2, participants: 24), 80);
    expect(DailyRewardRules.coinsForResult(rank: 3, participants: 24), 70);
    expect(DailyRewardRules.coinsForResult(rank: 10, participants: 100), 50);
    expect(DailyRewardRules.coinsForResult(rank: 30, participants: 100), 40);
    expect(DailyRewardRules.coinsForResult(rank: 50, participants: 100), 30);
    expect(DailyRewardRules.coinsForResult(rank: 70, participants: 100), 10);
    expect(DailyRewardRules.coinsForResult(rank: 71, participants: 100), 5);
    expect(DailyRewardRules.coinsForResult(rank: 4, participants: 24), 40);
    expect(DailyRewardRules.coinsForResult(rank: 8, participants: 24), 30);
    expect(DailyRewardRules.coinsForResult(rank: 13, participants: 24), 10);
    expect(DailyRewardRules.coinsForResult(rank: 17, participants: 24), 5);
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
