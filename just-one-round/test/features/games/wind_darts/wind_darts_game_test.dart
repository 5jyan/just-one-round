import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/wind_darts_game.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_art.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_input_surface.dart';

void main() {
  testWidgets('drag adjusts aim continuously and release throws the shot', (
    tester,
  ) async {
    final game = WindDartsGame(
      challengeSeed: 246,
      countdownDuration: Duration.zero,
      gameDuration: WindDartsRules.gameDuration,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(
      MaterialApp(
        home: WindDartsInputSurface(
          game: game,
          child: GameWidget(game: game),
        ),
      ),
    );
    for (var i = 0; i < 30 && !game.assetsReady; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(game.phase, WindDartsPhase.shotPreview);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MaterialApp)),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(game.phase, WindDartsPhase.aiming);
    expect(game.shotRecords, isEmpty);

    final aimBeforeDrag = game.currentAim.offset;
    await gesture.moveBy(const Offset(28, 18));
    await tester.pump();
    expect(game.phase, WindDartsPhase.aiming);
    expect(game.currentAim.offset, isNot(aimBeforeDrag));
    expect(game.shotRecords, isEmpty);

    await gesture.up();
    await tester.pump();
    expect(game.phase, WindDartsPhase.flight);
    expect(game.shotRecords, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'release-time aim plus wind determines the shot offset, not gauge fraction',
    (tester) async {
      const targetAim = Offset(8, -11);
      final firstGame = WindDartsGame(
        challengeSeed: 246,
        countdownDuration: Duration.zero,
        gameDuration: WindDartsRules.gameDuration,
        onFinished: (_) {},
      );
      final secondGame = WindDartsGame(
        challengeSeed: 246,
        countdownDuration: Duration.zero,
        gameDuration: WindDartsRules.gameDuration,
        onFinished: (_) {},
      );
      addTearDown(firstGame.disposeController);
      addTearDown(secondGame.disposeController);

      Future<void> waitForAssets(WindDartsGame game) async {
        for (var i = 0; i < 30 && !game.assetsReady; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(game.phase, WindDartsPhase.shotPreview);
      }

      Offset throwAtAim(WindDartsGame game, int pointerId, int holdFrames) {
        game.pointerDown(pointerId, Offset.zero);
        for (var frame = 0; frame < holdFrames; frame++) {
          game.updateForTesting(0.1);
        }
        final wobble = game.currentAim.offset;
        game.pointerMove(pointerId, targetAim - wobble);
        expect(game.currentAim.offset.dx, closeTo(targetAim.dx, 0.000001));
        expect(game.currentAim.offset.dy, closeTo(targetAim.dy, 0.000001));
        game.pointerUp(pointerId);
        expect(game.phase, WindDartsPhase.flight);
        return game.shotOffset;
      }

      await tester.pumpWidget(MaterialApp(home: GameWidget(game: firstGame)));
      await waitForAssets(firstGame);
      final firstOffset = throwAtAim(firstGame, 41, 10);

      await tester.pumpWidget(MaterialApp(home: GameWidget(game: secondGame)));
      await waitForAssets(secondGame);
      final secondOffset = throwAtAim(secondGame, 42, 20);

      final wind = firstGame.currentWind;
      final windOffset =
          wind.unitVector *
          (wind.metersPerSecond /
              3.5 *
              firstGame.boardRadius *
              WindDartsRules.windOffsetCoefficient *
              0.87);
      final expectedOffset = targetAim + windOffset;
      expect(windOffset.distance, greaterThan(0));
      expect(firstOffset.dx, closeTo(expectedOffset.dx, 0.000001));
      expect(firstOffset.dy, closeTo(expectedOffset.dy, 0.000001));
      expect(secondOffset.dx, closeTo(firstOffset.dx, 0.000001));
      expect(secondOffset.dy, closeTo(firstOffset.dy, 0.000001));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'loads the pub backdrop and scores exactly six held-release shots',
    (tester) async {
      GameResult? result;
      var finishCount = 0;
      final game = WindDartsGame(
        challengeSeed: 246,
        countdownDuration: Duration.zero,
        gameDuration: WindDartsRules.gameDuration,
        onFinished: (value) {
          result = value;
          finishCount++;
        },
      );
      addTearDown(game.disposeController);

      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      for (var i = 0; i < 30 && !game.assetsReady; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(game.assetsReady, isTrue);
      expect(game.phase, WindDartsPhase.shotPreview);

      // A long idle period must not consume the run or trigger a timeout.
      game.updateForTesting(120);
      expect(game.phase, WindDartsPhase.shotPreview);
      expect(game.hud.value.remainingSeconds, isNull);

      for (var shot = 0; shot < WindDartsRules.shotCount; shot++) {
        game.beginAimForTesting();
        game.updateForTesting(0.45);
        game.releaseForTesting();
        expect(game.phase, WindDartsPhase.flight);
        for (
          var frame = 0;
          frame < 10 && game.phase == WindDartsPhase.flight;
          frame++
        ) {
          game.updateForTesting(0.1);
        }
        expect(game.phase, WindDartsPhase.impact);
        final stoppedBoardAngle = game.boardAngle;
        expect(game.shotRecords, hasLength(shot + 1));
        final displayFrames =
            WindDartsRules.impactDisplayDuration.inMilliseconds ~/ 100;
        for (var frame = 1; frame < displayFrames - 1; frame++) {
          game.updateForTesting(0.1);
        }
        expect(game.phase, WindDartsPhase.impact);
        expect(game.boardAngle, stoppedBoardAngle);
        game.updateForTesting(0.1);
        expect(game.phase, WindDartsPhase.impact);
        expect(game.boardAngle, stoppedBoardAngle);
        game.updateForTesting(0.1);
        expect(
          game.phase,
          shot == WindDartsRules.shotCount - 1
              ? WindDartsPhase.finished
              : WindDartsPhase.shotPreview,
        );
        expect(game.boardAngle, stoppedBoardAngle);
        if (shot < WindDartsRules.shotCount - 1) {
          expect(game.cameraRetreating, isTrue);
          final retreatStartScale = game.displayedBoardScale;
          game.beginAimForTesting();
          expect(game.phase, WindDartsPhase.shotPreview);
          var retreatFrames = 0;
          while (game.cameraRetreating && retreatFrames < 10) {
            game.updateForTesting(0.1);
            if (retreatFrames == 0) {
              expect(game.boardAngle, stoppedBoardAngle);
            }
            retreatFrames++;
          }
          expect(retreatFrames, 7);
          expect(game.cameraRetreating, isFalse);
          expect(
            game.displayedBoardScale,
            closeTo(WindDartsRules.boardScaleForShot(shot + 1), 0.000001),
          );
          expect(game.displayedBoardScale, lessThan(retreatStartScale));
          game.updateForTesting(0.1);
          expect(game.boardAngle, stoppedBoardAngle);
        }
      }

      expect(game.phase, WindDartsPhase.finished);
      expect(finishCount, 1);
      expect(result?.score, game.score);
      expect(
        result?.duration,
        greaterThanOrEqualTo(const Duration(seconds: 120)),
      );
      expect(result?.windDartsShotScores, hasLength(6));
      expect(
        result?.windDartsShotScores?.reduce((a, b) => a + b),
        result?.score,
      );
      expect(result?.score, inInclusiveRange(0, 360));
      expect(result?.endType, GameEndType.clear);
      game.updateForTesting(1);
      expect(finishCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'freezes launch geometry while the camera approaches and retreats',
    (tester) async {
      final game = WindDartsGame(
        challengeSeed: 246,
        countdownDuration: Duration.zero,
        gameDuration: WindDartsRules.gameDuration,
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);

      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      for (var i = 0; i < 30 && !game.assetsReady; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(game.assetsReady, isTrue);

      game.pointerDown(7, Offset.zero);
      game.pointerMove(7, const Offset(18, -12));
      game.pointerUp(7);
      expect(game.phase, WindDartsPhase.flight);
      expect(game.boardAngle, WindDartsRules.boardAngle);

      final launchOffset = game.shotOffset;
      final launchZoom = game.launchCameraZoom;
      final targetWorldOffset =
          game.flightWorldTarget - WindDartsGame.boardCenter;
      final startWorldOffset =
          game.flightWorldStart - WindDartsGame.boardCenter;
      expect(
        targetWorldOffset.dx * launchZoom,
        closeTo(launchOffset.dx, 0.000001),
      );
      expect(
        targetWorldOffset.dy * launchZoom,
        closeTo(launchOffset.dy, 0.000001),
      );
      expect(
        startWorldOffset.dx * launchZoom,
        closeTo(
          WindDartsGame.flightStart.dx - WindDartsGame.boardCenter.dx,
          0.000001,
        ),
      );
      expect(
        startWorldOffset.dy * launchZoom,
        closeTo(
          WindDartsGame.flightStart.dy - WindDartsGame.boardCenter.dy,
          0.000001,
        ),
      );

      final launchRatio = launchOffset / game.boardRadius;
      final worldRatio = targetWorldOffset / WindDartsArt.worldBoardRadius;
      expect(worldRatio.dx, closeTo(launchRatio.dx, 0.000001));
      expect(worldRatio.dy, closeTo(launchRatio.dy, 0.000001));

      final capturedTail = game.flightTailDirectionWorld;
      while (game.phase == WindDartsPhase.flight) {
        game.updateForTesting(0.1);
        expect(game.shotOffset, launchOffset);
        expect(game.displayedBoardScale, lessThanOrEqualTo(1));
        expect(game.boardAngle, WindDartsRules.boardAngle);
      }
      expect(game.phase, WindDartsPhase.impact);
      expect(game.displayedBoardScale, closeTo(1, 0.000001));
      expect(
        game.flightWorldTarget,
        WindDartsGame.boardCenter + targetWorldOffset,
      );
      expect(game.flightTailDirectionWorld, capturedTail);

      while (game.phase == WindDartsPhase.impact) {
        game.updateForTesting(0.1);
        expect(
          game.flightWorldTarget,
          WindDartsGame.boardCenter + targetWorldOffset,
        );
        expect(game.flightTailDirectionWorld, capturedTail);
        expect(game.boardAngle, WindDartsRules.boardAngle);
      }
      expect(game.phase, WindDartsPhase.shotPreview);
      expect(game.cameraRetreating, isTrue);
      expect(game.displayedBoardScale, closeTo(1, 0.000001));
      while (game.cameraRetreating) {
        game.updateForTesting(0.1);
        expect(game.boardAngle, WindDartsRules.boardAngle);
      }
      expect(game.displayedBoardScale, closeTo(0.91, 0.000001));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('has no player timer and requires pointer-up after a long hold', (
    tester,
  ) async {
    GameResult? result;
    final game = WindDartsGame(
      challengeSeed: 246,
      countdownDuration: Duration.zero,
      gameDuration: WindDartsRules.gameDuration,
      onFinished: (value) => result = value,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var i = 0; i < 30 && !game.assetsReady; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(game.assetsReady, isTrue);
    game.beginAimForTesting();
    for (var frame = 0; frame < 100; frame++) {
      game.updateForTesting(0.1);
    }
    expect(game.phase, WindDartsPhase.aiming);
    expect(game.holdSeconds, closeTo(10, 0.000001));
    expect(game.hud.value.remainingSeconds, isNull);
    expect(result, isNull);

    game.releaseForTesting();
    expect(game.phase, WindDartsPhase.flight);
    expect(result, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
