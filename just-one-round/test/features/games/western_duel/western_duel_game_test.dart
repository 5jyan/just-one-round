import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/western_duel/domain/western_duel_opponent.dart';
import 'package:just_one_round/features/games/western_duel/western_duel_game.dart';

void main() {
  test('uses the approved detailed full-body 4x4 atlas', () {
    expect(WesternDuelGame.playerIdleSheetColumns, 2);
    expect(WesternDuelGame.playerIdleSheetRows, 2);
    expect(WesternDuelGame.playerIdleFrameCount, 4);
    expect(WesternDuelGame.playerIdleFrameForTesting(0), 0);
    expect(WesternDuelGame.playerIdleFrameForTesting(0.749), 0);
    expect(WesternDuelGame.playerIdleFrameForTesting(0.75), 1);
    expect(WesternDuelGame.playerIdleFrameForTesting(3), 0);
    expect(WesternDuelGame.playerActionSheetColumns, 4);
    expect(WesternDuelGame.playerActionSheetRows, 4);
    expect(WesternDuelGame.playerActionFrameCount, 16);
    expect(WesternDuelGame.playerActionFireFrame, 7);
    expect(WesternDuelGame.playerActionDurationSeconds, closeTo(0.57, 0.0001));
    expect(WesternDuelGame.playerActionSourceCellWidth, 540);
    expect(WesternDuelGame.playerActionSourceCellHeight, 1080);
    expect(WesternDuelGame.playerActionScaleX, 1);
    expect(WesternDuelGame.playerActionScaleY, 1);
    expect(WesternDuelGame.playerActionFrameForTesting(0), 0);
    expect(WesternDuelGame.playerActionFrameForTesting(0.209), 6);
    expect(WesternDuelGame.playerActionFrameForTesting(0.21), 7);
    expect(WesternDuelGame.playerActionFrameForTesting(0.249), 7);
    expect(WesternDuelGame.playerActionFrameForTesting(0.25), 8);
    expect(WesternDuelGame.playerActionFrameForTesting(0.57), 15);
    expect(WesternDuelGame.playerActionFrameForTesting(1), 15);
    const frameBoundaries = [
      0.0,
      0.03,
      0.06,
      0.09,
      0.12,
      0.15,
      0.18,
      0.21,
      0.25,
      0.29,
      0.33,
      0.37,
      0.41,
      0.45,
      0.49,
      0.53,
    ];
    for (var frame = 0; frame < frameBoundaries.length; frame++) {
      final boundary = frameBoundaries[frame];
      expect(WesternDuelGame.playerActionFrameForTesting(boundary), frame);
      if (frame > 0) {
        expect(
          WesternDuelGame.playerActionFrameForTesting(boundary - 1e-7),
          frame - 1,
        );
      }
    }
    expect(
      WesternDuelGame.playerActionFrameForTesting(
        WesternDuelGame.playerActionDurationSeconds,
      ),
      WesternDuelGame.playerActionFrameCount - 1,
    );
    expect(WesternDuelGame.playerActionDisplayX, -254);
    expect(WesternDuelGame.playerActionDisplayWidth, 540);
    expect(WesternDuelGame.playerActionDisplayHeight, 1080);
    expect(WesternDuelGame.playerMuzzleSourceX, 410);
    expect(WesternDuelGame.playerMuzzleSourceY, 365);
    expect(
      WesternDuelGame.playerMuzzleSourceForActionFrame(7),
      const Offset(410, 365),
    );
    expect(
      WesternDuelGame.playerMuzzleSourceForActionFrame(8),
      const Offset(413, 360),
    );
    expect(
      WesternDuelGame.playerMuzzleSourceForActionFrame(9),
      const Offset(412, 365),
    );
    expect(
      WesternDuelGame.playerMuzzleSourceForActionFrame(10),
      const Offset(411, 365),
    );
    expect(WesternDuelGame.playerMuzzleDisplayX, closeTo(156, 0.5));
    expect(WesternDuelGame.playerMuzzleDisplayY, 365);
  });

  test('keeps the viewport crop and muzzle aligned across viewports', () {
    for (final height in [640.0, 720.0, 800.0]) {
      final firingRect = WesternDuelGame.playerUnifiedRectForHeight(height);
      expect(firingRect.left, -254);
      expect(firingRect.right, 286);
      expect(firingRect.top, height - 680);
      expect(firingRect.height, 1080);

      final ready = WesternDuelGame.playerActionRectForHeight(height, 0);
      final firing = WesternDuelGame.playerActionRectForHeight(
        height,
        WesternDuelGame.playerActionFireFrame,
      );
      expect(ready, firing);
      expect(firing, firingRect);

      final opponent = WesternDuelGame.opponentRectForHeight(height);
      expect(opponent.left, closeTo(102.72, 0.01));
      expect(opponent.width, closeTo(154.56, 0.01));
      expect(opponent.height, closeTo(220.8, 0.01));
      expect(opponent.center.dx, 180);
      expect(opponent.bottom, closeTo(430 + (height - 720) / 2, 0.01));
      expect(opponent.center.dy, closeTo(height / 2 - 40.4, 0.01));

      final opponentMuzzle = WesternDuelGame.opponentMuzzleRectForHeight(
        height,
      );
      expect(opponentMuzzle.left, closeTo(196.56, 0.01));
      expect(opponentMuzzle.top, closeTo(308.56 + (height - 720) / 2, 0.01));
      expect(opponentMuzzle.width, closeTo(57.96, 0.01));

      final muzzle = WesternDuelGame.playerMuzzlePositionForHeight(height);
      expect(muzzle.dx, closeTo(156, 0.5));
      expect(muzzle.dy, height - 315);
      // The compact first-person gun reaches the opponent's left silhouette;
      // the projectile direction, rather than muzzle separation, is the
      // intentional targeting contract.
      expect(muzzle.dx, lessThan(opponent.center.dx));
      expect(muzzle.dx, inInclusiveRange(0, 360));
      expect(muzzle.dy, inInclusiveRange(0, height));

      final target = WesternDuelGame.playerShotTargetPositionForHeight(height);
      expect(opponent.contains(target), isTrue);
      expect(target.dx, greaterThan(muzzle.dx));
      expect(target.dy, lessThan(muzzle.dy));
      expect(WesternDuelGame.playerShotAngleForHeight(height), lessThan(0));
      for (final frame in [7, 8, 9, 10]) {
        final trackedMuzzle = WesternDuelGame.playerMuzzlePositionForHeight(
          height,
          frame: frame,
        );
        expect(trackedMuzzle.dx, inInclusiveRange(0, 360));
        expect(trackedMuzzle.dy, inInclusiveRange(0, height));
        expect(
          WesternDuelGame.playerShotAngleForHeight(height, frame: frame),
          lessThan(0),
        );
      }

      final breech = WesternDuelGame.playerBreechPositionForHeight(height);
      final t = (opponent.center.dx - breech.dx) / (muzzle.dx - breech.dx);
      final barrelRayY = breech.dy + (muzzle.dy - breech.dy) * t;
      expect(t, greaterThan(1));
      expect(barrelRayY, inInclusiveRange(opponent.top, opponent.bottom));

      for (
        var frame = 0;
        frame < WesternDuelGame.playerActionFrameCount;
        frame++
      ) {
        final action = WesternDuelGame.playerActionRectForHeight(height, frame);
        expect(action, firingRect);
        expect(action.height, 1080);
        expect(action.top, height - 680);
      }
      for (
        var frame = 0;
        frame < WesternDuelGame.playerIdleFrameCount;
        frame++
      ) {
        expect(
          WesternDuelGame.playerIdleRectForHeight(height, frame),
          firingRect,
        );
      }
    }
  });

  test('forward fall stays at 65% and moves 45 pixels right, 40 back', () {
    const height = 800.0;
    final planted = WesternDuelGame.playerUnifiedRectForHeight(height);
    final atBlend = WesternDuelGame.playerForwardFallRectForHeight(
      height,
      WesternDuelGame.playerForwardFallBlendSeconds,
    );
    final midpoint = WesternDuelGame.playerForwardFallRectForHeight(
      height,
      WesternDuelGame.playerForwardFallBlendSeconds +
          (WesternDuelGame.playerForwardFallDurationSeconds -
                  WesternDuelGame.playerForwardFallBlendSeconds) /
              2,
    );
    final finalRect = WesternDuelGame.playerForwardFallRectForHeight(
      height,
      WesternDuelGame.playerForwardFallDurationSeconds,
    );

    expect(atBlend.width, planted.width * 0.65);
    expect(atBlend.height, planted.height * 0.65);
    expect(midpoint.left, greaterThan(atBlend.left));
    expect(midpoint.top, greaterThan(atBlend.top));
    expect(finalRect.left, atBlend.left + 45);
    expect(finalRect.top, atBlend.top + 40);
    expect(finalRect.size, atBlend.size);

    final kneel = WesternDuelGame.playerForwardFallRectForHeight(height, 0.26);
    final kneelHold = WesternDuelGame.playerForwardFallRectForHeight(
      height,
      0.64,
    );
    expect(kneelHold, kneel);

    // The delivered v13 atlas's final opaque body bounds are x40..491,
    // y567..851; its full pose remains in the lower foreground.
    final finalOpaqueBounds = Rect.fromLTWH(
      finalRect.left + 40 * 0.65,
      finalRect.top + 567 * 0.65,
      451 * 0.65,
      284 * 0.65,
    );
    expect(
      finalOpaqueBounds.overlaps(Rect.fromLTWH(0, 0, 360, height)),
      isTrue,
    );
    expect(finalOpaqueBounds.right, lessThan(210));
    expect(finalOpaqueBounds.top, greaterThan(height - 230));
    // The viewport may hide the bottom edge, never the authored atlas itself.
    expect(finalOpaqueBounds.top, lessThan(height - 150));
  });

  test('breathes slowly around a stationary waist anchor', () {
    const height = 720.0;
    const frame = 0;
    const headSourceY = 306.0;
    final base = WesternDuelGame.playerIdleRectForHeight(height, frame);
    final quarter = WesternDuelGame.playerIdleRectForHeight(
      height,
      frame,
      elapsedSeconds: 0.75,
    );
    final oppositeQuarter = WesternDuelGame.playerIdleRectForHeight(
      height,
      frame,
      elapsedSeconds: 2.25,
    );
    final cycle = WesternDuelGame.playerIdleRectForHeight(
      height,
      frame,
      elapsedSeconds: 3,
    );
    double headY(Rect rect) =>
        rect.top + headSourceY * (rect.height / base.height);
    double waistY(Rect rect) =>
        rect.top +
        WesternDuelGame.playerIdleBreathingWaistSourceY *
            (rect.height / base.height);

    expect(quarter.height, greaterThan(base.height));
    expect(oppositeQuarter.height, lessThan(base.height));
    expect(quarter.top, closeTo(base.top - 5.85, 0.01));
    expect(quarter.left, base.left);
    expect(quarter.width, base.width);
    expect(oppositeQuarter.left, base.left);
    expect(oppositeQuarter.width, base.width);
    expect(waistY(quarter), closeTo(waistY(base), 0.01));
    expect(waistY(oppositeQuarter), closeTo(waistY(base), 0.01));
    expect((headY(quarter) - headY(base)).abs(), closeTo(3.10, 0.1));
    expect((headY(oppositeQuarter) - headY(base)).abs(), closeTo(3.10, 0.1));
    expect(cycle.left, base.left);
    expect(cycle.top, closeTo(base.top, 0.0001));
    expect(cycle.width, base.width);
    expect(cycle.height, closeTo(base.height, 0.0001));
  });

  testWidgets('captures reaction immediately while visual shots are pending', (
    tester,
  ) async {
    final results = <GameResult>[];
    final game = WesternDuelGame(
      onFinished: results.add,
      challengeSeed: 16,
      enableHaptics: false,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);
    game.setOpponent(
      const WesternDuelOpponent(
        nickname: '먼저 쏘는 총잡이',
        reactionMilliseconds: 200,
        isBot: false,
      ),
    );
    game.update(3.2);
    game.update(8);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 260)),
    );
    game.update(0.01);
    expect(game.opponentFired, isTrue);

    game.tapForTesting(reactionMs: 123);

    // Input timing is committed synchronously; the unified draw and both
    // muzzle flashes still need to reach their visual firing frame.
    expect(game.reactionMilliseconds, 123);
    expect(game.playerFired, isTrue);
    expect(game.playerVisualShotForTesting, isFalse);
    expect(game.impactAppliedForTesting, isFalse);
    game.update(0.20);
    expect(game.playerVisualShotForTesting, isFalse);
    expect(game.impactAppliedForTesting, isFalse);
    game.update(0.02);
    expect(game.playerVisualShotForTesting, isTrue);
    expect(game.opponentVisualShotForTesting, isTrue);
    expect(game.impactAppliedForTesting, isTrue);
    expect(results, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'opponent firing never blocks my shot; both shots precede result',
    (tester) async {
      final results = <GameResult>[];
      final game = WesternDuelGame(
        onFinished: results.add,
        challengeSeed: 17,
        enableHaptics: false,
      );
      addTearDown(game.disposeController);
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await _waitUntilReady(tester, game);
      game.setOpponent(
        const WesternDuelOpponent(
          nickname: '총잡이',
          reactionMilliseconds: 200,
          isBot: false,
        ),
      );
      game.update(3.2);
      expect(game.phase, WesternDuelPhase.standoff);
      game.update(8);
      expect(game.phase, WesternDuelPhase.draw);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 260)),
      );
      game.update(0.01);
      expect(game.opponentFired, isTrue);
      expect(game.playerFired, isFalse);
      expect(game.impactAppliedForTesting, isFalse);
      game.tapForTesting(reactionMs: 300);
      expect(game.playerFired, isTrue);
      expect(game.impactAppliedForTesting, isFalse);
      game.update(0.1);
      expect(game.opponentFired, isTrue);
      expect(game.impactAppliedForTesting, isFalse);
      expect(results, isEmpty);
      game.update(0.2);
      expect(game.impactAppliedForTesting, isTrue);
      game.update(1.2);
      expect(game.winnerCelebrationElapsedForTesting, isNotNull);
      expect(results.single.score, 999700);
      expect(results.single.endType, GameEndType.gameOver);
      game.update(5);
      expect(results.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('early tap warns without drawing or firing and scores zero', (
    tester,
  ) async {
    final results = <GameResult>[];
    final game = WesternDuelGame(
      onFinished: results.add,
      challengeSeed: 18,
      enableHaptics: false,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);
    game.setOpponent(
      const WesternDuelOpponent(
        nickname: '맥크리',
        reactionMilliseconds: 440,
        isBot: true,
      ),
    );
    game.update(3.2);
    game.tapForTesting();
    expect(game.failureMessage, '너무 빨리 눌렀어요');
    expect(game.playerFired, isFalse);
    expect(game.playerVisualShotForTesting, isFalse);
    game.update(0.2);
    game.update(1.4);
    expect(game.playerFired, isFalse);
    expect(game.winnerCelebrationElapsedForTesting, isNotNull);
    expect(results.single.score, 0);
    expect(results.single.endType, GameEndType.gameOver);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('my faster shot still waits for the recorded opponent shot', (
    tester,
  ) async {
    final results = <GameResult>[];
    final game = WesternDuelGame(
      onFinished: results.add,
      challengeSeed: 19,
      enableHaptics: false,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);
    game.setOpponent(
      const WesternDuelOpponent(
        nickname: '느린 총잡이',
        reactionMilliseconds: 400,
        isBot: false,
      ),
    );
    game.update(3.2);
    game.update(8);
    game.tapForTesting(reactionMs: 100);
    expect(game.playerFired, isTrue);
    expect(game.opponentFired, isFalse);
    expect(game.impactAppliedForTesting, isFalse);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 460)),
    );
    game.update(0.46);
    expect(game.opponentFired, isTrue);
    expect(game.impactAppliedForTesting, isFalse);
    game.update(0.22);
    expect(game.impactAppliedForTesting, isTrue);
    game.update(1.3);
    expect(game.winnerCelebrationElapsedForTesting, isNotNull);
    expect(results.single.score, 999900);
    expect(results.single.endType, GameEndType.clear);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('999ms is valid while 1000ms becomes a ranked timeout', (
    tester,
  ) async {
    final results = <GameResult>[];
    final game = WesternDuelGame(
      onFinished: results.add,
      challengeSeed: 20,
      enableHaptics: false,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);
    game.setOpponent(
      const WesternDuelOpponent(
        nickname: '기록 보유자',
        reactionMilliseconds: 1200,
        isBot: false,
      ),
    );
    game.update(3.2);
    game.update(8);
    game.tapForTesting(reactionMs: 999);
    expect(game.reactionMilliseconds, 999);
    expect(game.playerFired, isTrue);
    expect(game.forcedTimeoutForTesting, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());

    final timeoutResults = <GameResult>[];
    final timeoutGame = WesternDuelGame(
      onFinished: timeoutResults.add,
      challengeSeed: 21,
      enableHaptics: false,
    );
    addTearDown(timeoutGame.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: timeoutGame)));
    await _waitUntilReady(tester, timeoutGame);
    timeoutGame.setOpponent(
      const WesternDuelOpponent(
        nickname: '느린 기록 보유자',
        reactionMilliseconds: 1200,
        isBot: false,
      ),
    );
    timeoutGame.update(3.2);
    timeoutGame.update(8);
    timeoutGame.tapForTesting(reactionMs: 1000);
    expect(timeoutGame.reactionMilliseconds, 1000);
    expect(timeoutGame.playerFired, isFalse);
    expect(timeoutGame.playerVisualShotForTesting, isFalse);
    expect(timeoutGame.forcedTimeoutForTesting, isTrue);
    expect(timeoutGame.playerForwardFallStartedForTesting, isTrue);

    timeoutGame.update(0.2);
    expect(timeoutGame.opponentFired, isTrue);
    timeoutGame.update(0.21);
    timeoutGame.update(0.6);
    expect(timeoutGame.playerForwardFallCompletedForTesting, isTrue);
    timeoutGame.update(0.8);
    expect(timeoutResults.single.score, 999000);
    expect(timeoutResults.single.endType, GameEndType.gameOver);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no input reaches the one-second deadline without a fake shot', (
    tester,
  ) async {
    final results = <GameResult>[];
    final game = WesternDuelGame(
      onFinished: results.add,
      challengeSeed: 24,
      enableHaptics: false,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);
    game.setOpponent(
      const WesternDuelOpponent(
        nickname: '역사적 느린 기록',
        reactionMilliseconds: 1500,
        isBot: false,
      ),
    );
    game.update(3.2);
    game.update(8);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1050)),
    );
    game.update(0.01);
    expect(game.reactionMilliseconds, 1000);
    expect(game.playerFired, isFalse);
    expect(game.playerVisualShotForTesting, isFalse);
    expect(game.forcedTimeoutForTesting, isTrue);
    expect(game.playerForwardFallStartedForTesting, isTrue);

    game.update(0.2);
    game.update(0.21);
    game.update(0.5);
    game.update(0.8);
    expect(results.single.score, 999000);
    expect(results.single.endType, GameEndType.gameOver);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('decorative atmosphere does not consume challenge RNG', (
    tester,
  ) async {
    final atmosphericGame = WesternDuelGame(
      onFinished: (_) {},
      challengeSeed: 25,
      enableHaptics: false,
    );
    addTearDown(atmosphericGame.disposeController);
    await tester.pumpWidget(
      MaterialApp(home: GameWidget(game: atmosphericGame)),
    );
    await _waitUntilReady(tester, atmosphericGame);
    atmosphericGame.setOpponent(
      const WesternDuelOpponent(
        nickname: '장식 RNG 상대',
        reactionMilliseconds: 440,
        isBot: true,
      ),
    );
    final beforeAtmosphere = atmosphericGame.nextChallengeRandomForTesting();
    atmosphericGame.update(3.2);
    atmosphericGame.update(2.0);
    expect(atmosphericGame.atmosphereActiveForTesting, isTrue);
    final afterAtmosphere = atmosphericGame.nextChallengeRandomForTesting();
    final standoffSeconds = atmosphericGame.standoffSecondsForTesting;
    atmosphericGame.update(8);
    expect(atmosphericGame.phase, WesternDuelPhase.draw);
    expect(atmosphericGame.atmosphereActiveForTesting, isTrue);
    atmosphericGame.tapForTesting(reactionMs: 300);
    expect(atmosphericGame.phase, WesternDuelPhase.resolve);
    atmosphericGame.update(0.1);
    expect(atmosphericGame.atmosphereActiveForTesting, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());

    final controlGame = WesternDuelGame(
      onFinished: (_) {},
      challengeSeed: 25,
      enableHaptics: false,
    );
    addTearDown(controlGame.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: controlGame)));
    await _waitUntilReady(tester, controlGame);
    controlGame.setOpponent(
      const WesternDuelOpponent(
        nickname: '제어 RNG 상대',
        reactionMilliseconds: 440,
        isBot: true,
      ),
    );
    expect(controlGame.nextChallengeRandomForTesting(), beforeAtmosphere);
    controlGame.update(3.2);
    expect(controlGame.standoffSecondsForTesting, standoffSeconds);
    expect(controlGame.nextChallengeRandomForTesting(), afterAtmosphere);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'the slower player falls after the visual shot, but the winner does not',
    (tester) async {
      final losingResults = <GameResult>[];
      final losingGame = WesternDuelGame(
        onFinished: losingResults.add,
        challengeSeed: 22,
        enableHaptics: false,
      );
      addTearDown(losingGame.disposeController);
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: losingGame)));
      await _waitUntilReady(tester, losingGame);
      losingGame.setOpponent(
        const WesternDuelOpponent(
          nickname: '빠른 총잡이',
          reactionMilliseconds: 200,
          isBot: false,
        ),
      );
      losingGame.update(3.2);
      losingGame.update(8);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 260)),
      );
      losingGame.update(0.01);
      expect(losingGame.opponentFired, isTrue);
      losingGame.tapForTesting(reactionMs: 500);
      expect(losingGame.playerForwardFallStartedForTesting, isFalse);
      losingGame.update(0.20);
      expect(losingGame.playerForwardFallStartedForTesting, isFalse);
      losingGame.update(0.02);
      expect(losingGame.playerVisualShotForTesting, isTrue);
      expect(losingGame.playerForwardFallStartedForTesting, isTrue);
      losingGame.update(0.96);
      expect(losingGame.playerForwardFallCompletedForTesting, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());

      final winningGame = WesternDuelGame(
        onFinished: (_) {},
        challengeSeed: 23,
        enableHaptics: false,
      );
      addTearDown(winningGame.disposeController);
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: winningGame)));
      await _waitUntilReady(tester, winningGame);
      winningGame.setOpponent(
        const WesternDuelOpponent(
          nickname: '느린 총잡이',
          reactionMilliseconds: 1200,
          isBot: false,
        ),
      );
      winningGame.update(3.2);
      winningGame.update(8);
      winningGame.tapForTesting(reactionMs: 999);
      winningGame.update(0.22);
      expect(winningGame.playerVisualShotForTesting, isTrue);
      expect(winningGame.playerForwardFallStartedForTesting, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _waitUntilReady(WidgetTester tester, WesternDuelGame game) async {
  for (var attempt = 0; attempt < 100 && !game.isReadyForTesting; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(game.isReadyForTesting, isTrue);
}
