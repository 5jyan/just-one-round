import 'dart:math';

enum BeatTheDealerSuit { spades, hearts, diamonds, clubs }

enum BeatTheDealerRank {
  ace,
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
}

enum BeatTheDealerOutcome { blackjack, win, push, lose }

class BeatTheDealerCard {
  const BeatTheDealerCard(this.suit, this.rank);

  final BeatTheDealerSuit suit;
  final BeatTheDealerRank rank;

  int get hardValue => switch (rank) {
    BeatTheDealerRank.ace => 1,
    BeatTheDealerRank.two => 2,
    BeatTheDealerRank.three => 3,
    BeatTheDealerRank.four => 4,
    BeatTheDealerRank.five => 5,
    BeatTheDealerRank.six => 6,
    BeatTheDealerRank.seven => 7,
    BeatTheDealerRank.eight => 8,
    BeatTheDealerRank.nine => 9,
    BeatTheDealerRank.ten ||
    BeatTheDealerRank.jack ||
    BeatTheDealerRank.queen ||
    BeatTheDealerRank.king => 10,
  };

  String get rankLabel => switch (rank) {
    BeatTheDealerRank.ace => 'A',
    BeatTheDealerRank.two => '2',
    BeatTheDealerRank.three => '3',
    BeatTheDealerRank.four => '4',
    BeatTheDealerRank.five => '5',
    BeatTheDealerRank.six => '6',
    BeatTheDealerRank.seven => '7',
    BeatTheDealerRank.eight => '8',
    BeatTheDealerRank.nine => '9',
    BeatTheDealerRank.ten => '10',
    BeatTheDealerRank.jack => 'J',
    BeatTheDealerRank.queen => 'Q',
    BeatTheDealerRank.king => 'K',
  };

  bool get isRed =>
      suit == BeatTheDealerSuit.hearts || suit == BeatTheDealerSuit.diamonds;

  @override
  bool operator ==(Object other) =>
      other is BeatTheDealerCard && suit == other.suit && rank == other.rank;

  @override
  int get hashCode => Object.hash(suit, rank);
}

class BeatTheDealerHandValue {
  const BeatTheDealerHandValue({
    required this.total,
    required this.isSoft,
    required this.isBlackjack,
  });

  final int total;
  final bool isSoft;
  final bool isBlackjack;

  bool get isBust => total > BeatTheDealerRules.blackjackLimit;
}

class BeatTheDealerRound {
  const BeatTheDealerRound(this.deck);

  final List<BeatTheDealerCard> deck;

  BeatTheDealerCard get dealerUpCard => deck[1];
  BeatTheDealerCard get dealerHoleCard => deck[3];

  List<BeatTheDealerCard> playerHandAfter(int cardCount) {
    final count = max(BeatTheDealerRules.initialCardCount, cardCount);
    return List.unmodifiable([
      deck[0],
      deck[2],
      ...deck.skip(4).take(count - BeatTheDealerRules.initialCardCount),
    ]);
  }

  List<BeatTheDealerCard> dealerHandAfterPlayer(int playerCardCount) {
    final hand = <BeatTheDealerCard>[dealerUpCard, dealerHoleCard];
    var nextIndex =
        4 +
        max(0, playerCardCount - BeatTheDealerRules.initialCardCount).toInt();
    while (BeatTheDealerRules.handValue(hand).total <
            BeatTheDealerRules.dealerStandTotal &&
        nextIndex < deck.length) {
      hand.add(deck[nextIndex]);
      nextIndex++;
    }
    return List.unmodifiable(hand);
  }

  @override
  bool operator ==(Object other) =>
      other is BeatTheDealerRound && _listsEqual(deck, other.deck);

  @override
  int get hashCode => Object.hashAll(deck);

  static bool _listsEqual(
    List<BeatTheDealerCard> left,
    List<BeatTheDealerCard> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class BeatTheDealerSettlement {
  const BeatTheDealerSettlement({
    required this.outcome,
    required this.coins,
    required this.payout,
  });

  final BeatTheDealerOutcome outcome;
  final int coins;
  final int payout;
}

abstract final class BeatTheDealerRules {
  static const gameId = 'beat_the_dealer';
  static const rulesVersion = 3;
  static const roundCount = 10;
  static const startingCoins = 100;
  static const minimumBet = 5;
  static const maximumBet = 50;
  static const finalRoundMaximumBet = 100;
  static const betStep = 5;
  static const initialCardCount = 2;
  static const blackjackLimit = 21;
  static const dealerStandTotal = 17;
  static const minimumScore = 0;
  static const maximumScore = 925;
  static const gameDuration = Duration(minutes: 3);
  static const bettingDuration = Duration(seconds: 8);
  static const decisionDuration = Duration(seconds: 8);

  static String formatScore(int score) => '${score.clamp(0, maximumScore)}코인';

  static int productDay(DateTime instant) {
    final koreaTime = instant.toUtc().add(const Duration(hours: 9));
    final productDate = koreaTime.subtract(const Duration(hours: 6));
    return productDate.year * 10000 + productDate.month * 100 + productDate.day;
  }

  static int dailySeed(DateTime instant, {required int attemptOrdinal}) {
    var hash = 0x811c9dc5;
    for (final value in [
      productDay(instant),
      rulesVersion,
      attemptOrdinal.clamp(1, 2),
    ]) {
      hash ^= value;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static List<BeatTheDealerRound> generateRounds(int seed) {
    final random = Random(seed);
    for (var attempt = 0; attempt < 512; attempt++) {
      final rounds = List.generate(
        roundCount,
        (_) => BeatTheDealerRound(_shuffledDeck(random)),
        growable: false,
      );
      if (_isFairSet(rounds)) return List.unmodifiable(rounds);
    }
    throw StateError('Unable to generate a fair blackjack set');
  }

  static List<BeatTheDealerCard> _shuffledDeck(Random random) {
    final deck = <BeatTheDealerCard>[
      for (final suit in BeatTheDealerSuit.values)
        for (final rank in BeatTheDealerRank.values)
          BeatTheDealerCard(suit, rank),
    ]..shuffle(random);
    return List.unmodifiable(deck);
  }

  static bool _isFairSet(List<BeatTheDealerRound> rounds) {
    if (!rounds.every(isLegalRound)) return false;
    final weakUpCards = rounds.where((round) {
      final value = round.dealerUpCard.hardValue;
      return value >= 2 && value <= 6;
    }).length;
    final strongUpCards = rounds
        .where(
          (round) =>
              round.dealerUpCard.rank == BeatTheDealerRank.ace ||
              round.dealerUpCard.hardValue == 10,
        )
        .length;
    return weakUpCards >= 3 && strongUpCards <= 3;
  }

  static bool isLegalRound(BeatTheDealerRound round) =>
      round.deck.length == 52 && round.deck.toSet().length == 52;

  static BeatTheDealerHandValue handValue(List<BeatTheDealerCard> hand) {
    var total = hand.fold<int>(0, (sum, card) => sum + card.hardValue);
    final hasAce = hand.any((card) => card.rank == BeatTheDealerRank.ace);
    final isSoft = hasAce && total + 10 <= blackjackLimit;
    if (isSoft) total += 10;
    return BeatTheDealerHandValue(
      total: total,
      isSoft: isSoft,
      isBlackjack: hand.length == 2 && total == blackjackLimit,
    );
  }

  static int maximumBetForRound(int roundIndex) =>
      roundIndex == roundCount - 1 ? finalRoundMaximumBet : maximumBet;

  static int maximumLegalBet(int coins, {int roundIndex = 0}) {
    if (coins < minimumBet) return 0;
    return min(maximumBetForRound(roundIndex), coins ~/ betStep * betStep);
  }

  static int normalizeBet(int requestedBet, int coins, {int roundIndex = 0}) {
    final maximum = maximumLegalBet(coins, roundIndex: roundIndex);
    if (maximum == 0) return 0;
    return (requestedBet.clamp(minimumBet, maximum) ~/ betStep) * betStep;
  }

  static BeatTheDealerOutcome outcome({
    required List<BeatTheDealerCard> playerHand,
    required List<BeatTheDealerCard> dealerHand,
  }) {
    final player = handValue(playerHand);
    final dealer = handValue(dealerHand);
    if (player.isBust) return BeatTheDealerOutcome.lose;
    if (player.isBlackjack && dealer.isBlackjack) {
      return BeatTheDealerOutcome.push;
    }
    if (player.isBlackjack) return BeatTheDealerOutcome.blackjack;
    if (dealer.isBlackjack) return BeatTheDealerOutcome.lose;
    if (dealer.isBust || player.total > dealer.total) {
      return BeatTheDealerOutcome.win;
    }
    if (player.total == dealer.total) return BeatTheDealerOutcome.push;
    return BeatTheDealerOutcome.lose;
  }

  static BeatTheDealerSettlement settle({
    required int coins,
    required int bet,
    required List<BeatTheDealerCard> playerHand,
    required List<BeatTheDealerCard> dealerHand,
    int roundIndex = 0,
  }) {
    final legalBet = normalizeBet(bet, coins, roundIndex: roundIndex);
    final result = outcome(playerHand: playerHand, dealerHand: dealerHand);
    final payout = switch (result) {
      BeatTheDealerOutcome.blackjack => ((legalBet * 3 + 9) ~/ 10) * betStep,
      BeatTheDealerOutcome.win => legalBet,
      BeatTheDealerOutcome.push => 0,
      BeatTheDealerOutcome.lose => -legalBet,
    };
    return BeatTheDealerSettlement(
      outcome: result,
      coins: (coins + payout).clamp(minimumScore, maximumScore),
      payout: payout,
    );
  }
}
