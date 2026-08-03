import 'package:just_one_round/features/economy/domain/player_economy.dart';

class RewardGrant {
  const RewardGrant({
    required this.coinsGranted,
    required this.experienceGranted,
    required this.economy,
  });

  factory RewardGrant.fromJson(Map<String, dynamic> json) => RewardGrant(
    coinsGranted: (json['coins_granted'] as num?)?.toInt() ?? 0,
    experienceGranted: (json['experience_granted'] as num?)?.toInt() ?? 0,
    economy: PlayerEconomy.fromJson(json),
  );

  final int coinsGranted;
  final int experienceGranted;
  final PlayerEconomy economy;
}

class CoinSpendResult {
  const CoinSpendResult({required this.coinsSpent, required this.economy});

  factory CoinSpendResult.fromJson(Map<String, dynamic> json) =>
      CoinSpendResult(
        coinsSpent: (json['coins_spent'] as num?)?.toInt() ?? 0,
        economy: PlayerEconomy.fromJson(json),
      );

  final int coinsSpent;
  final PlayerEconomy economy;
}
