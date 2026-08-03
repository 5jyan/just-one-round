import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/beat_the_dealer/beat_the_dealer_game.dart';
import 'package:just_one_round/features/games/beat_the_dealer/domain/beat_the_dealer_rules.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';

void main() {
  test('initial HUD and repeated interruption never submit a score', () {
    var finishCount = 0;
    final game = BeatTheDealerGame(
      attemptOrdinal: 1,
      onFinished: (_) => finishCount++,
    );

    expect(game.hud.value.phase, MiniGamePhase.countdown);
    expect(game.hud.value.score, 100);
    game.interrupt();
    game.interrupt();

    expect(finishCount, 0);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    game.disposeController();
  });

  testWidgets('loads assets and accepts the simple bet and stand flow', (
    tester,
  ) async {
    final game = BeatTheDealerGame(
      attemptOrdinal: 1,
      seedInstant: DateTime.utc(2026, 7, 30),
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    await tester.pump(const Duration(seconds: 1));

    expect(game.gamePhase, BeatTheDealerPhase.betting);
    expect(game.bet, 5);
    game.tapLogicalPosition(Vector2(70, 515));
    expect(game.bet, 5);
    expect(game.activeBetLimitMessage, '최소 베팅은 5코인이에요');
    game.tapLogicalPosition(Vector2(290, 515));
    expect(game.bet, 10);
    for (var tap = 0; tap < 8; tap++) {
      game.tapLogicalPosition(Vector2(290, 515));
    }
    expect(game.bet, 50);
    game.tapLogicalPosition(Vector2(290, 515));
    expect(game.bet, 50);
    expect(game.activeBetLimitMessage, '최대 50코인까지 걸 수 있어요');
    game.tapLogicalPosition(Vector2(180, 580));
    expect(game.visibleCardCount, 2);
    if (game.gamePhase == BeatTheDealerPhase.playerTurn) {
      game.tapLogicalPosition(Vector2(260, 580));
    }
    expect(game.gamePhase, BeatTheDealerPhase.dealerTurn);
    await _pumpUntilPhase(tester, game, BeatTheDealerPhase.resolving);
    expect(game.gamePhase, BeatTheDealerPhase.resolving);
    await tester.pump(const Duration(milliseconds: 1250));
    expect(game.roundIndex, 1);
    expect(game.gamePhase, BeatTheDealerPhase.dealerPreview);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('safety timeout emits a result exactly once', (tester) async {
    var finishCount = 0;
    final game = BeatTheDealerGame(
      attemptOrdinal: 2,
      countdownDuration: Duration.zero,
      gameDuration: const Duration(seconds: 1),
      onFinished: (_) => finishCount++,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    for (var tick = 0; tick < 15; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(finishCount, 1);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    await tester.pump(const Duration(seconds: 1));
    expect(finishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dealer reveals one card at a time until reaching seventeen', (
    tester,
  ) async {
    BeatTheDealerGame? selected;
    for (var day = 1; day <= 31; day++) {
      final candidate = BeatTheDealerGame(
        attemptOrdinal: 1,
        seedInstant: DateTime.utc(2026, 8, day),
        countdownDuration: Duration.zero,
        onFinished: (_) {},
      );
      final round = candidate.rounds.first;
      if (BeatTheDealerRules.handValue(round.playerHandAfter(3)).isBust &&
          round.dealerHandAfterPlayer(3).length >= 3) {
        selected = candidate;
        break;
      }
      candidate.disposeController();
    }
    expect(selected, isNotNull);
    final game = selected!;
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);
    await _pumpUntilPhase(tester, game, BeatTheDealerPhase.betting);
    game.tapLogicalPosition(Vector2(180, 580));
    expect(game.gamePhase, BeatTheDealerPhase.playerTurn);
    game.tapLogicalPosition(Vector2(80, 580));

    expect(game.gamePhase, BeatTheDealerPhase.dealerTurn);
    expect(BeatTheDealerRules.handValue(game.playerHand).isBust, isTrue);
    expect(game.visibleDealerCardCount, 2);
    final finalDealerCardCount = game.dealerHand.length;
    expect(finalDealerCardCount, greaterThanOrEqualTo(3));

    await tester.pump(const Duration(milliseconds: 500));
    expect(game.visibleDealerCardCount, 2);
    await tester.pump(const Duration(milliseconds: 550));
    expect(game.visibleDealerCardCount, 3);
    expect(game.gamePhase, BeatTheDealerPhase.dealerTurn);

    var previousCount = game.visibleDealerCardCount;
    for (
      var reveal = 0;
      reveal < 8 && game.gamePhase == BeatTheDealerPhase.dealerTurn;
      reveal++
    ) {
      await tester.pump(const Duration(milliseconds: 1050));
      expect(
        game.visibleDealerCardCount,
        inInclusiveRange(previousCount, previousCount + 1),
      );
      previousCount = game.visibleDealerCardCount;
    }
    expect(game.gamePhase, BeatTheDealerPhase.resolving);
    expect(game.visibleDealerCardCount, finalDealerCardCount);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ten completed rounds emit one final coin result', (
    tester,
  ) async {
    var finishCount = 0;
    int? finalScore;
    final game = BeatTheDealerGame(
      attemptOrdinal: 1,
      seedInstant: DateTime.utc(2026, 7, 30),
      countdownDuration: Duration.zero,
      onFinished: (result) {
        finishCount++;
        finalScore = result.score;
      },
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilLoaded(tester, game);

    for (var round = 0; round < BeatTheDealerRules.roundCount; round++) {
      await _pumpUntilPhase(tester, game, BeatTheDealerPhase.betting);
      expect(game.gamePhase, BeatTheDealerPhase.betting);
      game.tapLogicalPosition(Vector2(180, 580));
      if (game.gamePhase == BeatTheDealerPhase.playerTurn) {
        game.tapLogicalPosition(Vector2(260, 580));
      }
      expect(game.gamePhase, BeatTheDealerPhase.dealerTurn);
      await _pumpUntilPhase(tester, game, BeatTheDealerPhase.resolving);
      expect(game.gamePhase, BeatTheDealerPhase.resolving);
      await tester.pump(const Duration(milliseconds: 1250));
    }

    expect(finishCount, 1);
    expect(finalScore, inInclusiveRange(0, BeatTheDealerRules.maximumScore));
    await tester.pump(const Duration(seconds: 1));
    expect(finishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _waitUntilLoaded(
  WidgetTester tester,
  BeatTheDealerGame game,
) async {
  for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(game.isLoaded, isTrue);
}

Future<void> _pumpUntilPhase(
  WidgetTester tester,
  BeatTheDealerGame game,
  BeatTheDealerPhase phase,
) async {
  for (var tick = 0; tick < 80 && game.gamePhase != phase; tick++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
