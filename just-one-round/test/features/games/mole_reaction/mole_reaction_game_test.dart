import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/mole_reaction/mole_reaction_game.dart';
import 'package:just_one_round/features/games/mole_reaction/domain/mole_reaction_rules.dart';

void main() {
  testWidgets('카운트다운 중에는 입력을 무시하고 첫 표적은 대기 뒤에 공개한다', (tester) async {
    final game = MoleReactionGame(
      challengeSeed: 17,
      countdownDuration: MoleReactionRules.countdownDuration,
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    expect(game.gamePhase, MoleReactionGamePhase.countdown);
    game.tapHoleForTesting(0);
    expect(game.totalMsForTesting, 0);

    await tester.pump(MoleReactionRules.countdownDuration);
    expect(game.gamePhase, MoleReactionGamePhase.waiting);
    expect(game.activeEventForTesting, isNull);
    expect(game.hud.value.distance, 0);
    expect(game.waitingElapsedSecondsForTesting, 0);
    expect(game.feedbackForTesting, MoleReactionRules.preparationPrompt);
    game.advanceTimeForTesting(const Duration(milliseconds: 500));
    expect(game.waitingElapsedSecondsForTesting, closeTo(0.5, 0.001));

    game.forceRevealTargetForTesting();
    expect(game.gamePhase, MoleReactionGamePhase.activeTarget);
    expect(game.activeEventForTesting, isNotNull);
    expect(game.feedbackForTesting, MoleReactionRules.preparationPrompt);
    expect(game.waitingElapsedSecondsForTesting, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('준비판 오답은 기록에 영향이 없고 실전 오답은 +1000ms를 더한다', (tester) async {
    final game = await _loadGame(tester, seed: 19);
    final event = game.activeEventForTesting!;
    final wrongHole = (event.holeIndex + 1) % MoleReactionRules.holeCount;

    game.tapHoleForTesting(wrongHole);
    expect(game.invalidTapCountForTesting, 0);
    expect(game.totalMsForTesting, 0);
    expect(game.gamePhase, MoleReactionGamePhase.activeTarget);

    game.tapHoleForTesting(event.holeIndex, reactionMilliseconds: 120);
    expect(game.resolvedEventsForTesting, 1);
    expect(game.preparationReactionMsForTesting, 120);
    expect(game.weightedReactionTotalMsForTesting, 0);
    expect(game.totalMsForTesting, 0);
    expect(game.feedbackTierForTesting, MoleReactionSpeedTier.perfect);
    game.advanceTimeForTesting(const Duration(milliseconds: 350));
    expect(game.feedbackForTesting, MoleReactionRules.realPrompt);
    game.forceRevealTargetForTesting();
    final realEvent = game.activeEventForTesting!;
    expect(game.feedbackForTesting, MoleReactionRules.realPrompt);
    game.tapHoleForTesting(
      (realEvent.holeIndex + 1) % MoleReactionRules.holeCount,
    );
    expect(game.invalidTapCountForTesting, 1);
    expect(game.totalMsForTesting, 1_000);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('황금 두더지는 실제 시간과 2배 가중 시간을 분리한다', (tester) async {
    final game = await _loadGame(tester, seed: 23);
    expect(game.eventsForTesting.last.isGolden, isTrue);
    expect(
      game.eventsForTesting
          .take(MoleReactionRules.normalEventCount)
          .any((event) => event.isGolden),
      isFalse,
    );
    game.forceRevealTargetForTesting();
    game.tapHoleForTesting(
      game.activeEventForTesting!.holeIndex,
      reactionMilliseconds: 10,
    );
    game.advanceTimeForTesting(const Duration(milliseconds: 350));
    game.forceRevealTargetForTesting();
    final goldenHole = game.activeEventForTesting!.holeIndex;
    game.tapHoleForTesting(goldenHole, reactionMilliseconds: 247);

    expect(game.goldenActualMsForTesting, 247);
    expect(game.goldenWeightedMsForTesting, 494);
    expect(game.rawReactionTotalMsForTesting, 247);
    expect(game.weightedReactionTotalMsForTesting, 494);
    expect(game.totalMsForTesting, 494);
    expect(game.feedbackForTesting, contains('×2'));
    game.advanceTimeForTesting(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('준비판 놓침은 무효이고 실전 황금 놓침만 +4000ms다', (tester) async {
    final game = await _loadGame(tester, seed: 31);
    game.forceMissForTesting();
    expect(game.preparationMissedForTesting, isTrue);
    expect(game.normalMissCountForTesting, 0);
    expect(game.totalMsForTesting, 0);
    game.advanceTimeForTesting(const Duration(milliseconds: 350));
    game.forceRevealTargetForTesting();
    game.forceMissForTesting();
    expect(game.goldenMissCountForTesting, 1);
    expect(
      game.totalMsForTesting,
      MoleReactionRules.goldenMissPenaltyMilliseconds,
    );
    game.advanceTimeForTesting(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('준비 한 번과 실전 한 번 완료 후 결과는 정확히 한 번 방출된다', (tester) async {
    GameResult? result;
    final game = MoleReactionGame(
      challengeSeed: 41,
      countdownDuration: Duration.zero,
      enableHaptics: false,
      onFinished: (value) => result = value,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    for (var event = 0; event < MoleReactionRules.eventCount; event++) {
      game.forceRevealTargetForTesting();
      final hole = game.activeEventForTesting!.holeIndex;
      game.tapHoleForTesting(hole, reactionMilliseconds: 1);
      game.advanceTimeForTesting(const Duration(milliseconds: 350));
    }
    expect(result, isNotNull);
    expect(result!.endType, GameEndType.clear);
    expect(result!.score, greaterThan(0));
    expect(result!.score, MoleReactionRules.rankingScoreForTotal(2));
    expect(result!.starsCollected, 0);
    expect(game.resolvedEventsForTesting, MoleReactionRules.eventCount);
    expect(game.resultReportedForTesting, isTrue);

    game.advanceTimeForTesting(const Duration(seconds: 5));
    expect(result!.endType, GameEndType.clear);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('세션 deadline은 타임아웃 결과를 한 번 방출한다', (tester) async {
    GameResult? result;
    final game = MoleReactionGame(
      gameDuration: const Duration(milliseconds: 400),
      countdownDuration: Duration.zero,
      enableHaptics: false,
      onFinished: (value) => result = value,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);
    game.forceRevealTargetForTesting();
    game.advanceTimeForTesting(const Duration(seconds: 2));

    expect(result, isNotNull);
    expect(result!.endType, GameEndType.timeUp);
    expect(result!.score, MoleReactionRules.timeoutRankingScore);
    expect(game.resultReportedForTesting, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('중단은 결과 콜백을 보내지 않는다', (tester) async {
    GameResult? result;
    final game = await _loadGame(
      tester,
      seed: 53,
      onFinished: (value) => result = value,
    );
    game.interrupt();
    game.advanceTimeForTesting(const Duration(seconds: 10));

    expect(game.gamePhase, MoleReactionGamePhase.interrupted);
    expect(result, isNull);
    expect(game.resultReportedForTesting, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('4개 히트박스는 서로 겹치지 않는다', () {
    final game = MoleReactionGame(onFinished: (_) {});
    addTearDown(game.disposeController);
    final rects = game.holeRectsForTesting;
    expect(rects, hasLength(MoleReactionRules.holeCount));
    expect(rects.map((rect) => rect.left), orderedEquals([70, 194, 70, 194]));
    expect(rects.map((rect) => rect.top), orderedEquals([330, 330, 462, 462]));
    for (var first = 0; first < rects.length; first++) {
      for (var second = first + 1; second < rects.length; second++) {
        expect(rects[first].overlaps(rects[second]), isFalse);
      }
    }
  });
}

Future<MoleReactionGame> _loadGame(
  WidgetTester tester, {
  required int seed,
  ValueChanged<GameResult>? onFinished,
}) async {
  final game = MoleReactionGame(
    challengeSeed: seed,
    countdownDuration: Duration.zero,
    enableHaptics: false,
    onFinished: onFinished ?? (_) {},
  );
  addTearDown(game.disposeController);
  await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
  await _waitUntilReady(tester, game);
  game.forceRevealTargetForTesting();
  return game;
}

Future<void> _waitUntilReady(WidgetTester tester, MoleReactionGame game) async {
  for (var attempt = 0; attempt < 100 && !game.isReadyForTesting; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(game.isReadyForTesting, isTrue);
}
