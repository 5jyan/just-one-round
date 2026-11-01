import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_opponent.dart';
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

  testWidgets('defers HUD notifications until after a sibling layout build', (
    tester,
  ) async {
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
    game.pauseEngine();

    var updatedDuringLayout = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: game.hud,
                builder: (context, state, _) => Text('${state.elapsedSeconds}'),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!updatedDuringLayout) {
                    updatedDuringLayout = true;
                    game.updateForTesting(1);
                  }
                  return const SizedBox.expand();
                },
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(updatedDuringLayout, isTrue);
    await tester.pump();
    expect(game.hud.value.elapsedSeconds, 1);
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
    'loads the pub backdrop and scores exactly seven held-release shots',
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
          frame < 15 && game.phase == WindDartsPhase.flight;
          frame++
        ) {
          game.updateForTesting(0.1);
        }
        expect(game.phase, WindDartsPhase.impact);
        final stoppedBoardAngle = game.boardAngle;
        expect(game.shotRecords, hasLength(shot + 1));
        expect(
          game.shotRecords.last.isGoldenDart,
          WindDartsRules.isGoldenDart(shot),
        );
        if (WindDartsRules.isGoldenDart(shot)) {
          final baseImpact = WindDartsRules.resolveImpact(
            point: game.shotOffset,
            boardRadius:
                WindDartsRules.baseBoardRadius *
                WindDartsRules.boardScaleForShot(shot),
            boardAngle: game.boardAngle,
          );
          expect(game.shotRecords.last.score, baseImpact.score * 2);
        }
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
      expect(result?.windDartsShotScores, hasLength(7));
      expect(
        result?.windDartsShotScores?.reduce((a, b) => a + b),
        result?.score,
      );
      expect(result?.score, inInclusiveRange(0, WindDartsRules.maximumScore));
      expect(result?.endType, GameEndType.clear);
      game.updateForTesting(1);
      expect(finishCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'keeps the guide opponent preview static until the real opponent arrives',
    (tester) async {
      final game = WindDartsGame(
        challengeSeed: 246,
        countdownDuration: const Duration(seconds: 3),
        gameDuration: WindDartsRules.gameDuration,
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);
      game.prepareOpponentPreview();

      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      for (var i = 0; i < 30 && !game.assetsReady; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(game.assetsReady, isTrue);
      expect(game.phase, WindDartsPhase.opponentPreview);
      expect(
        game.displayedBoardScale,
        closeTo(WindDartsArt.worldBoardScale, 0.000001),
      );
      expect(game.cameraZoom, closeTo(1, 0.000001));
      expect(game.opponent, isNull);

      game.updateForTesting(120);
      expect(game.phase, WindDartsPhase.opponentPreview);
      expect(game.hud.value.elapsedSeconds, 0);
      expect(game.shotRecords, isEmpty);
      game.pointerDown(1, Offset.zero);
      game.beginAimForTesting();
      game.releaseForTesting();
      expect(game.phase, WindDartsPhase.opponentPreview);
      expect(game.shotRecords, isEmpty);

      game.setOpponent(
        const WindDartsOpponent(
          nickname: '총구 연기',
          shotScores: [45, 60, 39, 57, 60, 60, 120],
          isBot: true,
        ),
      );
      expect(game.phase, WindDartsPhase.opponentIntro);
      for (var frame = 0; frame < 24; frame++) {
        game.updateForTesting(0.1);
      }
      expect(game.phase, WindDartsPhase.opponentIntro);
      game.updateForTesting(0.1);
      expect(game.phase, WindDartsPhase.boardApproach);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a pending opponent intro takes priority over the guide preview',
    (tester) async {
      final game = WindDartsGame(
        challengeSeed: 246,
        countdownDuration: const Duration(seconds: 3),
        gameDuration: WindDartsRules.gameDuration,
        onFinished: (_) {},
      );
      addTearDown(game.disposeController);
      game.prepareOpponentPreview();
      game.setOpponent(
        const WindDartsOpponent(
          nickname: '총구 연기',
          shotScores: [45, 60, 39, 57, 60, 60, 120],
          isBot: true,
        ),
      );

      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      for (var i = 0; i < 30 && !game.assetsReady; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(game.assetsReady, isTrue);
      expect(game.phase, WindDartsPhase.opponentIntro);
      expect(game.opponent?.nickname, '총구 연기');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'plays the opponent intro and resolves each opponent shot after mine',
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

      const opponentScores = [45, 60, 39, 57, 60, 60, 120];
      game.setOpponent(
        const WindDartsOpponent(
          nickname: '총구 연기',
          shotScores: opponentScores,
          isBot: true,
        ),
      );
      expect(game.phase, WindDartsPhase.opponentIntro);
      expect(game.hud.value.phase.name, 'playing');
      expect(
        game.displayedBoardScale,
        closeTo(WindDartsArt.worldBoardScale, 0.000001),
      );
      expect(game.cameraZoom, closeTo(1, 0.000001));
      for (var frame = 0; frame < 24; frame++) {
        game.updateForTesting(0.1);
      }
      expect(game.phase, WindDartsPhase.opponentIntro);
      game.updateForTesting(0.1);
      expect(game.phase, WindDartsPhase.boardApproach);
      expect(
        game.displayedBoardScale,
        closeTo(WindDartsArt.worldBoardScale, 0.000001),
      );

      var previousScale = game.displayedBoardScale;
      for (var frame = 0; frame < 6; frame++) {
        game.updateForTesting(0.1);
        expect(game.phase, WindDartsPhase.boardApproach);
        expect(game.displayedBoardScale, greaterThan(previousScale));
        previousScale = game.displayedBoardScale;
      }
      game.pointerDown(1, Offset.zero);
      game.beginAimForTesting();
      expect(game.phase, WindDartsPhase.boardApproach);
      expect(game.shotRecords, isEmpty);
      game.updateForTesting(0.1);
      expect(game.phase, WindDartsPhase.shotPreview);
      expect(game.displayedBoardScale, closeTo(1, 0.000001));
      expect(game.revealedOpponentTotalForTesting, 0);

      game.beginAimForTesting();
      game.updateForTesting(0.1);
      game.releaseForTesting();
      while (game.phase == WindDartsPhase.flight) {
        game.updateForTesting(0.1);
      }
      expect(game.phase, WindDartsPhase.impact);
      for (var frame = 0; frame < 20; frame++) {
        game.updateForTesting(0.1);
      }
      expect(game.phase, WindDartsPhase.opponentFlight);
      expect(game.revealedOpponentShotCountForTesting, 0);
      expect(game.revealedOpponentTotalForTesting, 0);

      game.pointerDown(1, Offset.zero);
      expect(game.phase, WindDartsPhase.opponentFlight);
      for (var frame = 0; frame < 6; frame++) {
        game.updateForTesting(0.1);
      }
      expect(game.phase, WindDartsPhase.opponentImpact);
      expect(game.revealedOpponentShotCountForTesting, 1);
      expect(game.revealedOpponentTotalForTesting, opponentScores.first);
      for (var frame = 0; frame < 9; frame++) {
        game.updateForTesting(0.1);
      }
      expect(game.phase, WindDartsPhase.shotPreview);
      expect(game.shotIndex, 1);
      expect(game.revealedOpponentShotCountForTesting, 1);

      var expectedOpponentTotal = opponentScores.first;
      for (var shot = 1; shot < WindDartsRules.shotCount; shot++) {
        while (game.cameraRetreating) {
          game.updateForTesting(0.1);
        }
        game.beginAimForTesting();
        game.updateForTesting(0.1);
        game.releaseForTesting();
        while (game.phase == WindDartsPhase.flight) {
          game.updateForTesting(0.1);
        }
        expect(game.phase, WindDartsPhase.impact);
        for (var frame = 0; frame < 20; frame++) {
          game.updateForTesting(0.1);
        }
        expect(game.phase, WindDartsPhase.opponentFlight);
        expect(game.revealedOpponentTotalForTesting, expectedOpponentTotal);
        for (var frame = 0; frame < 6; frame++) {
          game.updateForTesting(0.1);
        }
        expect(game.phase, WindDartsPhase.opponentImpact);
        expectedOpponentTotal += opponentScores[shot];
        expect(game.revealedOpponentTotalForTesting, expectedOpponentTotal);
        for (var frame = 0; frame < 9; frame++) {
          game.updateForTesting(0.1);
        }
      }
      expect(game.phase, WindDartsPhase.finished);
      expect(
        game.revealedOpponentTotalForTesting,
        opponentScores.reduce((sum, score) => sum + score),
      );
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
