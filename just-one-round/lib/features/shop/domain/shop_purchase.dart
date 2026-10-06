import 'package:just_one_round/features/economy/domain/player_economy.dart';

abstract final class ShopCatalog {
  static const practiceTicketPrice = 100;
  static const challengeTicketPrice = 250;
  static const nicknameColorTicketPrice = 300;
  static const nicknameChangeTicketPrice = 500;
  static const coinAdReward = 50;
}

class CoinAdRewardResult {
  const CoinAdRewardResult({required this.coinsGranted, required this.economy});

  factory CoinAdRewardResult.fromJson(Map<String, dynamic> json) =>
      CoinAdRewardResult(
        coinsGranted: (json['coins_granted'] as num).toInt(),
        economy: PlayerEconomy.fromJson(json),
      );

  final int coinsGranted;
  final PlayerEconomy economy;
}

class ShopPurchaseResult {
  const ShopPurchaseResult({
    required this.itemId,
    required this.quantity,
    required this.coinsSpent,
    required this.practiceTickets,
    required this.challengeTickets,
    required this.nicknameColorTickets,
    required this.nicknameChangeTickets,
    required this.economy,
  });

  factory ShopPurchaseResult.fromJson(Map<String, dynamic> json) =>
      ShopPurchaseResult(
        itemId: json['item_id'] as String,
        quantity: (json['quantity'] as num).toInt(),
        coinsSpent: (json['coins_spent'] as num).toInt(),
        practiceTickets: (json['practice_tickets'] as num?)?.toInt() ?? 0,
        challengeTickets: (json['challenge_tickets'] as num?)?.toInt() ?? 0,
        nicknameColorTickets:
            (json['nickname_color_tickets'] as num?)?.toInt() ?? 0,
        nicknameChangeTickets:
            (json['nickname_change_tickets'] as num?)?.toInt() ?? 0,
        economy: PlayerEconomy.fromJson(json),
      );

  final String itemId;
  final int quantity;
  final int coinsSpent;
  final int practiceTickets;
  final int challengeTickets;
  final int nicknameColorTickets;
  final int nicknameChangeTickets;
  final PlayerEconomy economy;
}
