import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/beat_the_dealer/domain/beat_the_dealer_rules.dart';

void main() {
  const spades = BeatTheDealerSuit.spades;
  const hearts = BeatTheDealerSuit.hearts;

  BeatTheDealerCard card(
    BeatTheDealerRank rank, [
    BeatTheDealerSuit suit = spades,
  ]) => BeatTheDealerCard(suit, rank);

  group('daily seed', () {
    test('uses the 06:00 KST product-day boundary', () {
      expect(
        BeatTheDealerRules.productDay(DateTime.utc(2026, 7, 29, 20, 59)),
        20260729,
      );
      expect(
        BeatTheDealerRules.productDay(DateTime.utc(2026, 7, 29, 21)),
        20260730,
      );
    });

    test('is reproducible and separates the two attempts', () {
      final instant = DateTime.utc(2026, 7, 30, 3);
      final first = BeatTheDealerRules.dailySeed(instant, attemptOrdinal: 1);
      expect(first, BeatTheDealerRules.dailySeed(instant, attemptOrdinal: 1));
      expect(
        first,
        isNot(BeatTheDealerRules.dailySeed(instant, attemptOrdinal: 2)),
      );
    });
  });

  test('generates ten legal reproducible 52-card rounds for many seeds', () {
    for (var seed = 0; seed < 250; seed++) {
      final rounds = BeatTheDealerRules.generateRounds(seed);
      expect(rounds.length, BeatTheDealerRules.roundCount);
      expect(rounds.every(BeatTheDealerRules.isLegalRound), isTrue);
      expect(BeatTheDealerRules.generateRounds(seed), rounds);
      final weakUpCards = rounds.where((round) {
        final value = round.dealerUpCard.hardValue;
        return value >= 2 && value <= 6;
      }).length;
      expect(weakUpCards, greaterThanOrEqualTo(3));
    }
  });

  test('all ranks are real cards and no rank can display zero', () {
    final labels = BeatTheDealerRank.values
        .map((rank) => card(rank).rankLabel)
        .toList();
    expect(labels, containsAll(['A', '10', 'J', 'Q', 'K']));
    expect(labels, isNot(contains('0')));
    expect(labels.length, 13);
  });

  test('aces automatically use the best legal one or eleven value', () {
    expect(
      BeatTheDealerRules.handValue([
        card(BeatTheDealerRank.ace),
        card(BeatTheDealerRank.king),
      ]).total,
      21,
    );
    final threeCards = BeatTheDealerRules.handValue([
      card(BeatTheDealerRank.ace),
      card(BeatTheDealerRank.six),
      card(BeatTheDealerRank.nine),
    ]);
    expect(threeCards.total, 16);
    expect(threeCards.isSoft, isFalse);
  });

  test('dealer hits through sixteen and stands on soft seventeen', () {
    final deck = <BeatTheDealerCard>[
      card(BeatTheDealerRank.ten),
      card(BeatTheDealerRank.ace),
      card(BeatTheDealerRank.seven),
      card(BeatTheDealerRank.six),
      card(BeatTheDealerRank.king),
      for (final suit in BeatTheDealerSuit.values)
        for (final rank in BeatTheDealerRank.values)
          if (!{
            card(BeatTheDealerRank.ten),
            card(BeatTheDealerRank.ace),
            card(BeatTheDealerRank.seven),
            card(BeatTheDealerRank.six),
            card(BeatTheDealerRank.king),
          }.contains(card(rank, suit)))
            card(rank, suit),
    ];
    final round = BeatTheDealerRound(deck.take(52).toList());
    final dealer = round.dealerHandAfterPlayer(2);
    expect(dealer.length, 2);
    expect(BeatTheDealerRules.handValue(dealer).total, 17);
    expect(BeatTheDealerRules.handValue(dealer).isSoft, isTrue);
  });

  test('normalizes bets to legal five-coin steps', () {
    expect(BeatTheDealerRules.normalizeBet(3, 100), 5);
    expect(BeatTheDealerRules.normalizeBet(48, 100), 45);
    expect(BeatTheDealerRules.normalizeBet(500, 100), 50);
    expect(BeatTheDealerRules.normalizeBet(50, 23), 20);
    expect(BeatTheDealerRules.normalizeBet(5, 4), 0);
    expect(BeatTheDealerRules.normalizeBet(500, 100, roundIndex: 8), 50);
    expect(BeatTheDealerRules.normalizeBet(500, 100, roundIndex: 9), 100);
  });

  test('settles blackjack, win, push, loss, and bust', () {
    final dealer20 = [
      card(BeatTheDealerRank.king),
      card(BeatTheDealerRank.queen, hearts),
    ];
    expect(
      BeatTheDealerRules.settle(
        coins: 100,
        bet: 20,
        playerHand: [
          card(BeatTheDealerRank.ace),
          card(BeatTheDealerRank.king, hearts),
        ],
        dealerHand: dealer20,
      ).coins,
      130,
    );
    expect(
      BeatTheDealerRules.settle(
        coins: 100,
        bet: 5,
        playerHand: [
          card(BeatTheDealerRank.ace),
          card(BeatTheDealerRank.king, hearts),
        ],
        dealerHand: dealer20,
      ).coins,
      110,
    );
    expect(
      BeatTheDealerRules.settle(
        coins: 100,
        bet: 20,
        playerHand: [
          card(BeatTheDealerRank.ten),
          card(BeatTheDealerRank.nine),
          card(BeatTheDealerRank.two),
        ],
        dealerHand: dealer20,
      ).coins,
      120,
    );
    expect(
      BeatTheDealerRules.settle(
        coins: 100,
        bet: 20,
        playerHand: [
          card(BeatTheDealerRank.ten),
          card(BeatTheDealerRank.queen, hearts),
        ],
        dealerHand: dealer20,
      ).coins,
      100,
    );
    expect(
      BeatTheDealerRules.settle(
        coins: 100,
        bet: 20,
        playerHand: [
          card(BeatTheDealerRank.ten),
          card(BeatTheDealerRank.eight),
        ],
        dealerHand: dealer20,
      ).coins,
      80,
    );
    expect(
      BeatTheDealerRules.settle(
        coins: 100,
        bet: 20,
        playerHand: [
          card(BeatTheDealerRank.king),
          card(BeatTheDealerRank.queen),
          card(BeatTheDealerRank.two),
        ],
        dealerHand: [
          card(BeatTheDealerRank.two),
          card(BeatTheDealerRank.three),
        ],
      ).coins,
      80,
    );
  });

  test('the final round accepts a one-hundred-coin blackjack bet', () {
    final settlement = BeatTheDealerRules.settle(
      coins: 775,
      bet: 100,
      roundIndex: BeatTheDealerRules.roundCount - 1,
      playerHand: [
        card(BeatTheDealerRank.ace),
        card(BeatTheDealerRank.king, hearts),
      ],
      dealerHand: [
        card(BeatTheDealerRank.king),
        card(BeatTheDealerRank.queen, hearts),
      ],
    );

    expect(settlement.payout, 150);
    expect(settlement.coins, BeatTheDealerRules.maximumScore);
  });

  test('score formatting stays inside the v3 contract bounds', () {
    expect(BeatTheDealerRules.formatScore(-1), '0코인');
    expect(BeatTheDealerRules.formatScore(926), '925코인');
  });
}
