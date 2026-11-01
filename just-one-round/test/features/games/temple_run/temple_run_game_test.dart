import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/temple_run_game.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  test('countdown ignores input and pauses distance and score', () {
    final game = TempleRunGame(random: Random(1), onFinished: (_) {});
    addTearDown(game.disposeController);

    expect(game.gamePhase, MiniGamePhase.countdown);
    expect(game.queueSwipeForTesting(Vector2(40, 0)), isFalse);
    expect(game.laneForTesting, TempleRunRules.centerLane);

    game.advanceTimeForTesting(const Duration(milliseconds: 550));
    expect(game.countdownElapsedForTesting, .55);
    game.advanceTimeForTesting(const Duration(milliseconds: 950));
    expect(game.countdownElapsedForTesting, 1.5);
    game.advanceTimeForTesting(const Duration(milliseconds: 1150));
    expect(game.gamePhase, MiniGamePhase.countdown);
    expect(game.distanceMetersForTesting, 0);
    expect(game.playingElapsedForTesting, 0);
    expect(game.hud.value.score, 0);
    expect(game.queueSwipeForTesting(Vector2(40, 0)), isFalse);
    game.advanceTimeForTesting(const Duration(milliseconds: 350));
    expect(game.gamePhase, MiniGamePhase.playing);
    expect(game.distanceMetersForTesting, 0);
    expect(game.playingElapsedForTesting, 0);
    expect(game.queueSwipeForTesting(Vector2(40, 0)), isFalse);
    expect(game.laneForTesting, TempleRunRules.centerLane);
  });

  test('countdown boundary consumes only time beyond the countdown', () {
    final game = TempleRunGame(onFinished: (_) {});
    addTearDown(game.disposeController);

    game.advanceTimeForTesting(const Duration(milliseconds: 2990));
    expect(game.gamePhase, MiniGamePhase.countdown);
    expect(game.playingElapsedForTesting, 0);
    game.advanceTimeForTesting(const Duration(milliseconds: 10));
    expect(game.gamePhase, MiniGamePhase.playing);
    expect(game.playingElapsedForTesting, closeTo(0, .000001));
    expect(game.distanceMetersForTesting, closeTo(0, .000001));
  });

  test('a zero countdown enters play immediately', () {
    final game = TempleRunGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    expect(game.gamePhase, MiniGamePhase.playing);
  });

  test('jump and slide are mutually exclusive and ignore short swipes', () {
    final game = TempleRunGame(
      random: Random(2),
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    expect(game.queueSwipeForTesting(Vector2(10, 2)), isFalse);
    expect(game.queueSwipeForTesting(Vector2(0, -40)), isTrue);
    expect(game.jumpRemainingForTesting, greaterThan(0));
    expect(game.queueSwipeForTesting(Vector2(0, 40)), isTrue);
    expect(game.pendingVerticalSwipeForTesting, TempleRunSwipe.down);
    game.advanceTimeForTesting(const Duration(seconds: 1));
    expect(game.jumpRemainingForTesting, 0);
    expect(game.queueSwipeForTesting(Vector2(0, 40)), isTrue);
    expect(game.slideRemainingForTesting, greaterThan(0));
  });

  test('vertical buffering is one-slot FIFO, consumed once, and expires', () {
    final game = TempleRunGame(
      gameDuration: const Duration(seconds: 5),
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      random: Random(23),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    expect(game.handleSwipeForTesting(TempleRunSwipe.up), isTrue);
    game.advanceTimeForTesting(const Duration(milliseconds: 600));
    expect(game.handleSwipeForTesting(TempleRunSwipe.down), isTrue);
    expect(game.handleSwipeForTesting(TempleRunSwipe.up), isFalse);
    expect(game.pendingVerticalSwipeForTesting, TempleRunSwipe.down);

    // The first queued action executes as soon as the jump unlocks.
    game.advanceTimeForTesting(const Duration(milliseconds: 200));
    expect(game.pendingVerticalSwipeForTesting, isNull);
    expect(game.slideRemainingForTesting, greaterThan(0));
    game.advanceTimeForTesting(const Duration(milliseconds: 800));
    expect(game.slideRemainingForTesting, 0);

    final expiring = TempleRunGame(
      gameDuration: const Duration(seconds: 5),
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      random: Random(24),
      onFinished: (_) {},
    );
    addTearDown(expiring.disposeController);
    expiring.handleSwipeForTesting(TempleRunSwipe.up);
    expiring.advanceTimeForTesting(const Duration(milliseconds: 200));
    expect(expiring.handleSwipeForTesting(TempleRunSwipe.down), isTrue);
    expiring.advanceTimeForTesting(const Duration(milliseconds: 310));
    expect(expiring.pendingVerticalSwipeForTesting, isNull);
    expiring.advanceTimeForTesting(const Duration(milliseconds: 400));
    expect(expiring.slideRemainingForTesting, 0);
  });

  test(
    'vertical input expires at the exact buffer boundary without replay',
    () {
      final game = TempleRunGame(
        gameDuration: const Duration(seconds: 5),
        countdownDuration: Duration.zero,
        enableTiltInput: false,
        random: Random(26),
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);

      expect(game.handleSwipeForTesting(TempleRunSwipe.up), isTrue);
      game.advanceTimeForTesting(const Duration(milliseconds: 200));
      expect(game.handleSwipeForTesting(TempleRunSwipe.down), isTrue);
      expect(game.pendingVerticalSwipeForTesting, TempleRunSwipe.down);

      // The jump remains active, so an exact 300ms buffer expiry must discard
      // the queued slide instead of giving it an extra simulation step.
      game.advanceTimeForTesting(const Duration(milliseconds: 300));
      expect(game.pendingVerticalSwipeForTesting, isNull);
      expect(game.slideRemainingForTesting, 0);
      game.advanceTimeForTesting(const Duration(milliseconds: 700));
      expect(game.slideRemainingForTesting, 0);
    },
  );

  test('interrupt clears a queued vertical action without submitting', () {
    final results = <GameResult>[];
    final game = TempleRunGame(
      gameDuration: const Duration(seconds: 5),
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      random: Random(25),
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    game.handleSwipeForTesting(TempleRunSwipe.up);
    game.advanceTimeForTesting(const Duration(milliseconds: 600));
    expect(game.handleSwipeForTesting(TempleRunSwipe.down), isTrue);
    expect(game.pendingVerticalSwipeForTesting, isNotNull);

    game.interrupt();
    game.advanceTimeForTesting(const Duration(seconds: 2));
    expect(game.pendingVerticalSwipeForTesting, isNull);
    expect(results, isEmpty);
  });

  test('timeout emits a ranked result exactly once', () {
    final results = <GameResult>[];
    final game = TempleRunGame(
      gameDuration: const Duration(milliseconds: 350),
      countdownDuration: Duration.zero,
      random: Random(3),
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    game.advanceTimeForTesting(const Duration(seconds: 2));
    game.advanceTimeForTesting(const Duration(seconds: 2));

    expect(results, hasLength(1));
    expect(results.single.endType, GameEndType.timeUp);
    expect(results.single.score, greaterThanOrEqualTo(0));
    expect(game.resultReportedForTesting, isTrue);
  });

  test('collision terminal wins the race and never emits twice', () {
    final results = <GameResult>[];
    final game = TempleRunGame(
      gameDuration: const Duration(seconds: 8),
      countdownDuration: Duration.zero,
      course: TempleRunCourse(
        obstacles: const [
          TempleRunObstacle(
            distanceMeters: 18,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.rubble,
          ),
        ],
        coins: const [],
        powerUps: const [],
        turns: const [],
        totalDistanceMeters: 100,
      ),
      onFinished: results.add,
    );
    addTearDown(game.disposeController);
    const firstObstacleDistance = 18.0;
    final contact = TempleRunRules.elapsedForDistance(firstObstacleDistance);
    game.advanceTimeForTesting(
      Duration(milliseconds: ((contact + 0.25) * 1000).round()),
    );
    final terminalCount = results.length;
    game.advanceTimeForTesting(const Duration(seconds: 10));

    expect(terminalCount, 1);
    expect(results, hasLength(1));
    expect(results.single.endType, GameEndType.gameOver);
    expect(game.collisionsForTesting, greaterThanOrEqualTo(1));
  });

  test(
    'jumping just before the collision gate survives while standing hits',
    () {
      TempleRunGame makeGame(List<GameResult> results) => TempleRunGame(
        gameDuration: const Duration(seconds: 8),
        countdownDuration: Duration.zero,
        enableTiltInput: false,
        course: TempleRunCourse(
          obstacles: [
            TempleRunObstacle(
              distanceMeters: 20,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.hurdle,
            ),
          ],
          coins: [],
          powerUps: [],
          turns: [],
          totalDistanceMeters: 100,
        ),
        onFinished: results.add,
      );

      final standingResults = <GameResult>[];
      final standing = makeGame(standingResults);
      addTearDown(standing.disposeController);
      final gateDistance = 20.0 - TempleRunRules.collisionWindowMeters;
      final gateTime = TempleRunRules.elapsedForDistance(gateDistance);
      standing.advanceTimeForTesting(
        Duration(milliseconds: ((gateTime + .03) * 1000).round()),
      );
      expect(standingResults, hasLength(1));
      expect(standingResults.single.endType, GameEndType.gameOver);
      expect(standing.collisionsForTesting, 1);

      final jumpingResults = <GameResult>[];
      final jumping = makeGame(jumpingResults);
      addTearDown(jumping.disposeController);
      const justBeforeGateDistance = 20.0 - .85 - .10;
      final justBeforeGateTime = TempleRunRules.elapsedForDistance(
        justBeforeGateDistance,
      );
      jumping.advanceTimeForTesting(
        Duration(milliseconds: (justBeforeGateTime * 1000).round()),
      );
      expect(jumping.gamePhase, MiniGamePhase.playing);
      expect(jumping.handleSwipeForTesting(TempleRunSwipe.up), isTrue);

      final afterGateTime = TempleRunRules.elapsedForDistance(20) + .03;
      jumping.advanceTimeForTesting(
        Duration(
          milliseconds: ((afterGateTime - justBeforeGateTime) * 1000).round(),
        ),
      );
      expect(jumpingResults, isEmpty);
      expect(jumping.gamePhase, MiniGamePhase.playing);
      expect(jumping.collisionsForTesting, 0);
    },
  );

  test('interrupting before or after countdown never submits a result', () {
    final results = <GameResult>[];
    final game = TempleRunGame(random: Random(5), onFinished: results.add);
    addTearDown(game.disposeController);
    game.advanceTimeForTesting(const Duration(milliseconds: 900));
    expect(game.gamePhase, MiniGamePhase.countdown);
    expect(game.distanceMetersForTesting, 0);
    game.interrupt();
    game.interrupt();
    game.advanceTimeForTesting(const Duration(seconds: 10));

    expect(results, isEmpty);
    expect(game.isInterruptedForTesting, isTrue);
    expect(game.gamePhase, MiniGamePhase.finished);
  });

  test(
    'boost expiry grants recovery and automatically clears an opened turn',
    () {
      final results = <GameResult>[];
      final course = TempleRunCourse(
        obstacles: const [
          TempleRunObstacle(
            distanceMeters: 31,
            lane: 1,
            kind: TempleRunObstacleKind.rubble,
          ),
        ],
        coins: const [],
        powerUps: const [
          TempleRunPowerUp(
            distanceMeters: 1,
            lane: 1,
            kind: TempleRunPowerUpKind.boost,
          ),
        ],
        turns: const [
          TempleRunTurn(
            distanceMeters: 42,
            direction: TempleRunTurnDirection.left,
            windowStartMeters: 30,
            windowEndMeters: 46,
          ),
        ],
        totalDistanceMeters: 100,
      );
      final game = TempleRunGame(
        gameDuration: const Duration(seconds: 10),
        countdownDuration: Duration.zero,
        course: course,
        onFinished: results.add,
      );
      addTearDown(game.disposeController);

      game.advanceTimeForTesting(const Duration(seconds: 3));
      expect(game.boostRemainingForTesting, closeTo(0.0, 0.001));
      expect(game.protectedRecoveryRemainingForTesting, greaterThan(0.6));
      expect(game.turnArmedForTesting, isTrue);
      game.advanceTimeForTesting(const Duration(seconds: 2));

      expect(
        game.protectedRecoveryRemainingForTesting,
        greaterThanOrEqualTo(0),
      );
      expect(game.activeTurnForTesting, isNull);
      expect(game.cameraYawForTesting, lessThan(0));
      expect(results, isEmpty);
    },
  );

  test('boost recovery protects only the remaining narrow-path interval', () {
    final results = <GameResult>[];
    final course = TempleRunCourse(
      obstacles: const [
        TempleRunObstacle(
          distanceMeters: 15,
          lane: TempleRunRules.centerLane,
          kind: TempleRunObstacleKind.narrowPath,
          lengthMeters: 30,
        ),
      ],
      coins: const [],
      powerUps: const [
        TempleRunPowerUp(
          distanceMeters: 1,
          lane: TempleRunRules.centerLane,
          kind: TempleRunPowerUpKind.boost,
        ),
      ],
      turns: const [],
      totalDistanceMeters: 100,
    );
    final game = TempleRunGame(
      gameDuration: const Duration(seconds: 10),
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      course: course,
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    // Move toward the right edge only after entering the path. The boost
    // expires while the runner is still inside it, so recovery must protect
    // the wrong position briefly and then hand collision checking back.
    final pathStart = TempleRunRules.elapsedForDistance(15);
    game.advanceTimeForTesting(
      Duration(milliseconds: (pathStart * 1000).round()),
    );
    game.setTiltNeutralForTesting(0);
    game.pushAccelerometerEventForTesting(
      AccelerometerEvent(-4, 0, 0, DateTime.now()),
    );
    game.advanceTimeForTesting(const Duration(seconds: 1));
    expect(results, isEmpty);
    expect(game.protectedRecoveryRemainingForTesting, greaterThan(0));

    final recovery = game.protectedRecoveryRemainingForTesting;
    game.advanceTimeForTesting(
      Duration(milliseconds: ((recovery + .25) * 1000).round()),
    );
    expect(results, hasLength(1));
    expect(results.single.endType, GameEndType.gameOver);
    expect(results.single.collisions, 1);
  });

  test('corner window requires its announced direction', () {
    final course = TempleRunCourse(
      obstacles: const [],
      coins: const [],
      powerUps: const [],
      turns: const [
        TempleRunTurn(
          distanceMeters: 42,
          direction: TempleRunTurnDirection.left,
          windowStartMeters: 30,
          windowEndMeters: 46,
        ),
      ],
      totalDistanceMeters: 100,
    );
    final game = TempleRunGame(
      gameDuration: const Duration(seconds: 10),
      countdownDuration: Duration.zero,
      course: course,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    game.advanceTimeForTesting(const Duration(seconds: 4));
    expect(game.activeTurnForTesting, isNotNull);
    expect(game.handleSwipeForTesting(TempleRunSwipe.right), isTrue);
    expect(game.activeTurnForTesting, isNotNull);
    expect(game.turnArmedForTesting, isFalse);
    expect(game.cameraYawForTesting, 0);
    expect(game.handleSwipeForTesting(TempleRunSwipe.left), isTrue);
    expect(game.activeTurnForTesting, isNotNull);
    expect(game.turnArmedForTesting, isTrue);
    expect(game.completedTurnCountForTesting, 0);
    expect(game.cameraYawForTesting, 0);
    game.advanceTimeForTesting(const Duration(seconds: 2));
    expect(game.activeTurnForTesting, isNull);
    expect(game.completedTurnCountForTesting, 1);
    expect(
      game.cameraYawForTesting,
      closeTo(-TempleRunRules.turnAngleRadians, 0.001),
    );
    game.advanceTimeForTesting(const Duration(milliseconds: 800));
    expect(
      game.cameraYawForTesting,
      closeTo(-TempleRunRules.turnAngleRadians, 0.001),
    );
  });

  test(
    'turns stay silent in the HUD while vertical buffering still speaks',
    () {
      final course = TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: const [
          TempleRunTurn(
            distanceMeters: 42,
            direction: TempleRunTurnDirection.left,
            windowStartMeters: 18,
            windowEndMeters: 47,
          ),
        ],
        totalDistanceMeters: 100,
      );
      final game = TempleRunGame(
        gameDuration: const Duration(seconds: 10),
        countdownDuration: Duration.zero,
        enableTiltInput: false,
        course: course,
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);

      game.advanceTimeForTesting(const Duration(seconds: 4));
      expect(game.activeTurnForTesting, isNotNull);
      expect(game.hud.value.message, isNull);
      expect(game.handleSwipeForTesting(TempleRunSwipe.left), isTrue);
      expect(game.hud.value.message, isNull);

      expect(game.handleSwipeForTesting(TempleRunSwipe.up), isTrue);
      game.advanceTimeForTesting(const Duration(milliseconds: 100));
      expect(game.handleSwipeForTesting(TempleRunSwipe.down), isTrue);
      expect(game.hud.value.message, contains('슬라이드'));
    },
  );

  test(
    'corner camera stays neutral before commit and eases to exact 90 degrees',
    () {
      final course = TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: const [
          TempleRunTurn(
            distanceMeters: 42,
            direction: TempleRunTurnDirection.left,
            windowStartMeters: 18,
            windowEndMeters: 47,
          ),
        ],
        totalDistanceMeters: 100,
      );
      final game = TempleRunGame(
        gameDuration: const Duration(seconds: 10),
        countdownDuration: Duration.zero,
        enableTiltInput: false,
        course: course,
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);

      game.advanceTimeForTesting(const Duration(seconds: 4));
      expect(game.handleSwipeForTesting(TempleRunSwipe.left), isTrue);
      while (game.distanceMetersForTesting < 41.9) {
        game.advanceTimeForTesting(const Duration(milliseconds: 1));
      }
      expect(game.completedTurnCountForTesting, 0);
      expect(game.cameraYawForTesting, closeTo(0, 0.001));

      while (game.completedTurnCountForTesting == 0) {
        game.advanceTimeForTesting(const Duration(milliseconds: 1));
      }
      expect(game.cameraYawForTesting, lessThan(0));
      game.advanceTimeForTesting(const Duration(milliseconds: 90));
      expect(
        game.cameraYawForTesting.abs(),
        greaterThanOrEqualTo(79 * pi / 180),
      );
      game.advanceTimeForTesting(const Duration(milliseconds: 100));
      expect(
        game.cameraYawForTesting,
        closeTo(-TempleRunRules.turnAngleRadians, 0.001),
      );
    },
  );

  testWidgets(
    'real drag callbacks commit at 20 logical pixels on short and tall views',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const viewports = [Size(360, 640), Size(390, 844)];
      for (var index = 0; index < viewports.length; index++) {
        final viewport = viewports[index];
        final game = TempleRunGame(
          gameDuration: const Duration(seconds: 8),
          countdownDuration: Duration.zero,
          random: Random(22 + index),
          onFinished: (_) {},
        );
        addTearDown(game.disposeController);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: GameWidget(game: game),
            ),
          ),
        );
        await _pumpTempleRunUntilLoaded(tester, game);
        await tester.pump();
        expect(game.gamePhase, MiniGamePhase.playing);

        final start = Offset(index == 0 ? 110 : 125, 320);
        final gesture = await tester.startGesture(start);
        // The tall surface is mapped to the 360px logical camera and the
        // recognizer consumes touch-slop first, so use enough physical travel
        // to cross the same 20 logical-pixel contract.
        await gesture.moveBy(Offset(0, index == 0 ? -20.5 : -48));
        await tester.pump();
        expect(game.jumpRemainingForTesting, greaterThan(0));
        await gesture.moveBy(const Offset(0, -160));
        await tester.pump();
        expect(game.jumpRemainingForTesting, greaterThan(0));
        await gesture.up();
        await tester.pump();
        game.interrupt();
        game.disposeController();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  test('a generated course can be driven safely for the full 300 seconds', () {
    final results = <GameResult>[];
    final game = TempleRunGame(
      gameDuration: TempleRunRules.maximumDuration,
      countdownDuration: Duration.zero,
      random: Random(20261015),
      onFinished: results.add,
    );
    addTearDown(game.disposeController);
    expect(game.courseForTesting.turns, isNotEmpty);
    expect(game.courseForTesting.powerUps, isNotEmpty);

    var guard = 0;
    while (game.gamePhase == MiniGamePhase.playing && guard < 7000) {
      _prepareSafeAction(game);
      game.advanceTimeForTesting(const Duration(milliseconds: 50));
      guard++;
    }

    expect(guard, lessThan(7000));
    expect(results, hasLength(1));
    expect(results.single.endType, GameEndType.timeUp);
    expect(results.single.duration, TempleRunRules.maximumDuration);
    expect(game.distanceMetersForTesting, greaterThan(4000));
    expect(
      game.distanceMetersForTesting,
      lessThanOrEqualTo(game.courseForTesting.totalDistanceMeters),
    );
    expect(game.resultReportedForTesting, isTrue);
    expect(game.coinsForTesting, greaterThan(0));
  });

  test(
    'bounded tilt controller completes several deterministic 300 second runs',
    () {
      var collectedBoostDuringSoak = false;
      for (final seed in [0, 17, 20261015, 20261017]) {
        final results = <GameResult>[];
        final game = TempleRunGame(
          gameDuration: TempleRunRules.maximumDuration,
          countdownDuration: Duration.zero,
          random: Random(seed),
          onFinished: results.add,
        );
        try {
          var guard = 0;
          while (game.gamePhase == MiniGamePhase.playing && guard < 7000) {
            _prepareSafeAction(game);
            game.advanceTimeForTesting(const Duration(milliseconds: 50));
            guard++;
          }

          expect(guard, lessThan(7000), reason: 'seed $seed');
          expect(results, hasLength(1), reason: 'seed $seed');
          expect(
            results.single.endType,
            GameEndType.timeUp,
            reason: 'seed $seed',
          );
          expect(
            results.single.duration,
            TempleRunRules.maximumDuration,
            reason: 'seed $seed',
          );
          expect(
            game.distanceMetersForTesting,
            greaterThan(4000),
            reason: 'seed $seed',
          );
          collectedBoostDuringSoak |= game.courseForTesting.powerUps
              .asMap()
              .entries
              .any(
                (entry) =>
                    entry.value.kind == TempleRunPowerUpKind.boost &&
                    game.collectedPowerUpIndicesForTesting.contains(entry.key),
              );
        } finally {
          game.disposeController();
        }
      }
      expect(
        collectedBoostDuringSoak,
        isTrue,
        reason: 'at least one controller run exercises a generated boost',
      );
    },
  );

  testWidgets('sensor stream is cancelled on interrupt and dispose', (
    tester,
  ) async {
    var cancelled = false;
    final stream = StreamController<AccelerometerEvent>(
      onCancel: () {
        cancelled = true;
      },
    );
    addTearDown(stream.close);
    final game = TempleRunGame(
      gameDuration: const Duration(seconds: 5),
      countdownDuration: Duration.zero,
      accelerometerEvents: stream.stream,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(GameWidget(game: game));
    await _pumpTempleRunUntilLoaded(tester, game);
    expect(cancelled, isFalse);

    game.interrupt();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    expect(cancelled, isTrue);

    var disposed = false;
    final disposedStream = StreamController<AccelerometerEvent>(
      onCancel: () {
        disposed = true;
      },
    );
    addTearDown(disposedStream.close);
    final disposedGame = TempleRunGame(
      gameDuration: const Duration(seconds: 5),
      countdownDuration: Duration.zero,
      accelerometerEvents: disposedStream.stream,
      onFinished: (_) {},
    );
    addTearDown(disposedGame.disposeController);
    await tester.pumpWidget(GameWidget(game: disposedGame));
    await _pumpTempleRunUntilLoaded(tester, disposedGame);
    disposedGame.disposeController();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    expect(disposed, isTrue);
  });

  test(
    'shield absorbs one solid hit before a later solid hit ends the run',
    () {
      final results = <GameResult>[];
      final course = TempleRunCourse(
        obstacles: const [
          TempleRunObstacle(
            distanceMeters: 18,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.rubble,
          ),
          TempleRunObstacle(
            distanceMeters: 30,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.hurdle,
          ),
        ],
        coins: const [],
        powerUps: const [
          TempleRunPowerUp(
            distanceMeters: 5,
            lane: TempleRunRules.centerLane,
            kind: TempleRunPowerUpKind.shield,
          ),
        ],
        turns: const [],
        totalDistanceMeters: 100,
      );
      final game = TempleRunGame(
        gameDuration: const Duration(seconds: 10),
        countdownDuration: Duration.zero,
        course: course,
        onFinished: results.add,
      );
      addTearDown(game.disposeController);

      final shieldTime = TempleRunRules.elapsedForDistance(8);
      game.advanceTimeForTesting(
        Duration(milliseconds: (shieldTime * 1000).round()),
      );
      expect(game.shieldChargesForTesting, 1);
      final firstHitTime = TempleRunRules.elapsedForDistance(18);
      game.advanceTimeForTesting(
        Duration(
          milliseconds: ((firstHitTime - shieldTime + 0.2) * 1000).round(),
        ),
      );
      expect(results, isEmpty);
      expect(game.shieldChargesForTesting, 0);
      expect(game.collisionsForTesting, 1);

      final secondHitTime = TempleRunRules.elapsedForDistance(30);
      game.advanceTimeForTesting(
        Duration(
          milliseconds: ((secondHitTime - firstHitTime + 0.2) * 1000).round(),
        ),
      );
      expect(results, hasLength(1));
      expect(results.single.endType, GameEndType.gameOver);
      expect(results.single.collisions, 2);
    },
  );

  test(
    'a missed mandatory turn ends once without inflating collision count',
    () {
      final results = <GameResult>[];
      final course = TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: const [
          TempleRunTurn(
            distanceMeters: 18,
            direction: TempleRunTurnDirection.right,
            windowStartMeters: 12,
            windowEndMeters: 20,
          ),
        ],
        totalDistanceMeters: 100,
      );
      final game = TempleRunGame(
        gameDuration: const Duration(seconds: 10),
        countdownDuration: Duration.zero,
        course: course,
        onFinished: results.add,
      );
      addTearDown(game.disposeController);

      final turnEnd = TempleRunRules.elapsedForDistance(20);
      game.advanceTimeForTesting(
        Duration(milliseconds: ((turnEnd + 0.2) * 1000).round()),
      );
      game.advanceTimeForTesting(const Duration(seconds: 2));

      expect(results, hasLength(1));
      expect(results.single.endType, GameEndType.gameOver);
      expect(results.single.collisions, 0);
      expect(game.resultReportedForTesting, isTrue);
    },
  );

  test(
    'runner stays centred and horizontal swipes only arm announced turns',
    () {
      final game = TempleRunGame(
        countdownDuration: Duration.zero,
        random: Random(24),
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);

      expect(game.handleSwipeForTesting(TempleRunSwipe.right), isFalse);
      expect(game.laneForTesting, TempleRunRules.centerLane);
      expect(game.visualLaneForTesting, TempleRunRules.centerLane);
    },
  );

  test('portrait tilt maps negative X right, smooths, and stays bounded', () {
    final game = TempleRunGame(
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      course: TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: const [],
        totalDistanceMeters: 100,
      ),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    game.setTiltNeutralForTesting(0);
    game.pushAccelerometerEventForTesting(
      AccelerometerEvent(-4, 0, 0, DateTime.now()),
    );
    game.advanceTimeForTesting(const Duration(milliseconds: 500));
    expect(game.visualLaneForTesting, greaterThan(1));
    expect(game.visualLaneForTesting, lessThanOrEqualTo(2));

    game.pushAccelerometerEventForTesting(
      AccelerometerEvent(4, 0, 0, DateTime.now()),
    );
    game.advanceTimeForTesting(const Duration(seconds: 2));
    expect(game.visualLaneForTesting, greaterThanOrEqualTo(0));
    expect(game.visualLaneForTesting, lessThanOrEqualTo(2));
  });

  test('full tilt moves from center to the side in bounded sensor time', () {
    final game = TempleRunGame(
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      course: TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: const [],
        totalDistanceMeters: 100,
      ),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    game.setTiltNeutralForTesting(0);

    final elapsed = _timeToSideWithFullTilt(game);

    expect(game.visualLaneForTesting, greaterThanOrEqualTo(1.9));
    expect(elapsed.inMilliseconds, inInclusiveRange(250, 350));
  });

  test('countdown calibrates tilt without moving the runner', () {
    final game = TempleRunGame(
      countdownDuration: const Duration(seconds: 2),
      enableTiltInput: false,
      course: TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: const [],
        totalDistanceMeters: 100,
      ),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    game.pushAccelerometerEventForTesting(
      AccelerometerEvent(-4, 0, 0, DateTime.now()),
    );
    game.advanceTimeForTesting(const Duration(seconds: 1));
    expect(game.visualLaneForTesting, 1);
    game.advanceTimeForTesting(const Duration(seconds: 1));
    game.pushAccelerometerEventForTesting(
      AccelerometerEvent(-4, 0, 0, DateTime.now()),
    );
    game.advanceTimeForTesting(const Duration(milliseconds: 400));
    expect(game.visualLaneForTesting, 1);
  });

  test('narrow path checks the whole interval and poses cannot bypass it', () {
    final results = <GameResult>[];
    final course = TempleRunCourse(
      obstacles: const [
        TempleRunObstacle(
          distanceMeters: 18,
          lane: TempleRunRules.firstLane,
          kind: TempleRunObstacleKind.narrowPath,
          lengthMeters: 6,
        ),
      ],
      coins: const [],
      powerUps: const [],
      turns: const [],
      totalDistanceMeters: 100,
    );
    final game = TempleRunGame(
      gameDuration: const Duration(seconds: 8),
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      course: course,
      onFinished: results.add,
    );
    addTearDown(game.disposeController);
    game.handleSwipeForTesting(TempleRunSwipe.up);
    final contact = TempleRunRules.elapsedForDistance(18);
    game.advanceTimeForTesting(
      Duration(milliseconds: ((contact + .15) * 1000).round()),
    );
    expect(results, hasLength(1));
    expect(results.single.endType, GameEndType.gameOver);
    expect(results.single.collisions, 1);
  });

  test('matching corner swipe buffers early and executes at the junction', () {
    final course = TempleRunCourse(
      obstacles: const [],
      coins: const [],
      powerUps: const [],
      turns: const [
        TempleRunTurn(
          distanceMeters: 42,
          direction: TempleRunTurnDirection.right,
          windowStartMeters: 18,
          windowEndMeters: 47,
        ),
      ],
      totalDistanceMeters: 100,
    );
    final game = TempleRunGame(
      gameDuration: const Duration(seconds: 10),
      countdownDuration: Duration.zero,
      enableTiltInput: false,
      course: course,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    game.advanceTimeForTesting(const Duration(milliseconds: 2500));
    expect(game.activeTurnForTesting, isNotNull);
    expect(game.handleSwipeForTesting(TempleRunSwipe.right), isTrue);
    expect(game.completedTurnCountForTesting, 0);
    game.advanceTimeForTesting(const Duration(seconds: 3));
    expect(game.completedTurnCountForTesting, 1);
    expect(game.cameraYawForTesting, greaterThan(0));
  });
}

Future<void> _pumpTempleRunUntilLoaded(
  WidgetTester tester,
  TempleRunGame game,
) async {
  for (var attempt = 0; attempt < 30 && !game.isLoaded; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(game.isLoaded, isTrue);
  expect(tester.takeException(), isNull);
}

Duration _timeToSideWithFullTilt(TempleRunGame game) {
  var elapsed = Duration.zero;
  while (game.visualLaneForTesting < 1.9 &&
      elapsed < const Duration(seconds: 2)) {
    game.pushAccelerometerEventForTesting(
      AccelerometerEvent(-3, 0, 0, DateTime.now()),
    );
    game.advanceTimeForTesting(const Duration(milliseconds: 20));
    elapsed += const Duration(milliseconds: 20);
  }
  return elapsed;
}

void _prepareSafeAction(TempleRunGame game) {
  final turn = game.activeTurnForTesting;
  if (turn != null) {
    game.handleSwipeForTesting(
      turn.direction == TempleRunTurnDirection.left
          ? TempleRunSwipe.left
          : TempleRunSwipe.right,
    );
  }
  final distance = game.distanceMetersForTesting;
  // A narrow path is an interval, not a point event. Start steering before
  // its entrance and keep selecting it until its exit so the soak controller
  // cannot leave the safe strip while a previous non-zero tilt is still
  // filtered through the runtime.
  final narrowPath = game.courseForTesting.obstacles.firstWhere(
    (candidate) =>
        candidate.isNarrowPath &&
        candidate.endDistanceMeters >= distance - .05 &&
        candidate.distanceMeters <= distance + 50,
    orElse: () => const TempleRunObstacle(
      distanceMeters: double.infinity,
      lane: 0,
      kind: TempleRunObstacleKind.rubble,
    ),
  );
  if (narrowPath.isNarrowPath) {
    if (game.tiltNeutralForTesting == null) {
      game.setTiltNeutralForTesting(0);
    }
    final error = narrowPath.lane - game.visualLaneForTesting;
    // Keep a little room inside the legal strip before returning to neutral;
    // the filter can otherwise carry the old steering direction across the
    // next 50ms step.
    final centered =
        error.abs() <= TempleRunRules.narrowPathSafeHalfWidthInLanes * .5;
    game.pushAccelerometerEventForTesting(
      AccelerometerEvent(
        centered
            ? 0.0
            : error.sign > 0
            ? -4.0
            : 4.0,
        0,
        0,
        DateTime.now(),
      ),
    );
  } else {
    if (game.tiltNeutralForTesting == null) {
      game.setTiltNeutralForTesting(0);
    }
    // Keep the soak controller representative of a player who takes the
    // authored power-up line when no narrow terrain has priority. This also
    // exercises the generated boost/recovery path instead of only testing
    // obstacle survival.
    final powerUpEntry = game.courseForTesting.powerUps
        .asMap()
        .entries
        .cast<MapEntry<int, TempleRunPowerUp>?>()
        .firstWhere(
          (entry) =>
              entry != null &&
              !game.collectedPowerUpIndicesForTesting.contains(entry.key) &&
              entry.value.distanceMeters >=
                  distance - TempleRunRules.powerUpPickupWindowMeters &&
              entry.value.distanceMeters <= distance + 50,
          orElse: () => null,
        );
    final targetLane = powerUpEntry?.value.lane;
    final error = targetLane == null
        ? 0.0
        : targetLane - game.visualLaneForTesting;
    final centered = error.abs() <= .05;
    game.pushAccelerometerEventForTesting(
      AccelerometerEvent(
        centered
            ? 0.0
            : error.sign > 0
            ? -4.0
            : 4.0,
        0,
        0,
        DateTime.now(),
      ),
    );
  }

  final obstacle = game.courseForTesting.obstacles.firstWhere(
    (candidate) =>
        candidate.distanceMeters >=
        distance - TempleRunRules.collisionWindowMeters,
    orElse: () => const TempleRunObstacle(
      distanceMeters: double.infinity,
      lane: 0,
      kind: TempleRunObstacleKind.rubble,
    ),
  );
  final relative = obstacle.distanceMeters - distance;
  if (relative > 6 || obstacle.distanceMeters.isInfinite) return;
  if (obstacle.spansFullRoad) {
    if (obstacle.kind == TempleRunObstacleKind.arch) {
      final canStartSlide =
          game.jumpRemainingForTesting <= 0 &&
          game.slideRemainingForTesting <= 0;
      final canQueueSlide =
          game.jumpRemainingForTesting <= 0 &&
          game.slideRemainingForTesting > 0 &&
          game.slideRemainingForTesting <=
              TempleRunRules.verticalInputBufferSeconds;
      if (canStartSlide || canQueueSlide) {
        game.handleSwipeForTesting(TempleRunSwipe.down);
      }
    } else if (game.jumpRemainingForTesting <= 0 &&
        game.slideRemainingForTesting <= 0) {
      game.handleSwipeForTesting(TempleRunSwipe.up);
    } else if (game.slideRemainingForTesting > 0 &&
        game.slideRemainingForTesting <=
            TempleRunRules.verticalInputBufferSeconds) {
      game.handleSwipeForTesting(TempleRunSwipe.up);
    }
    return;
  }
  if (obstacle.lane != TempleRunRules.centerLane) return;
  switch (obstacle.kind) {
    case TempleRunObstacleKind.hurdle:
    case TempleRunObstacleKind.gap:
      if (game.jumpRemainingForTesting <= 0 &&
          game.slideRemainingForTesting <= 0) {
        game.handleSwipeForTesting(TempleRunSwipe.up);
      }
    case TempleRunObstacleKind.arch:
      if (game.jumpRemainingForTesting <= 0 &&
          game.slideRemainingForTesting <= 0) {
        game.handleSwipeForTesting(TempleRunSwipe.down);
      }
    case TempleRunObstacleKind.rubble:
      // The authored route does not generate dodge-only rubble. Keep this
      // branch for old custom fixtures; centred rubble is intentionally fatal.
      return;
    case TempleRunObstacleKind.narrowPath:
      return;
  }
}
