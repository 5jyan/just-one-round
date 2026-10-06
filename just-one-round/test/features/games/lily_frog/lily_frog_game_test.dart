import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_frog_rules.dart';
import 'package:just_one_round/features/games/lily_frog/lily_frog_game.dart';

void main() {
  test('긴 화면은 360 폭을 유지하고 최대 800 높이까지만 보인다', () {
    expect(
      LilyFrogGame.viewportResolutionForCanvas(Vector2(360, 640)),
      Vector2(360, 640),
    );
    expect(
      LilyFrogGame.viewportResolutionForCanvas(Vector2(1080, 2400)),
      Vector2(360, 800),
    );
  });

  test('중단은 결과를 만들지 않고 반복 호출해도 안전하다', () {
    final results = <GameResult>[];
    final game = LilyFrogGame(onFinished: results.add);

    game.interrupt();
    game.interrupt();

    expect(results, isEmpty);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    game.disposeController();
  });

  testWidgets('첫 3초에는 실패 방향 탭을 실행하지 않는다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(7),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    game.setOrbitThetaForTesting(0);

    expect(game.tapForTesting(), isFalse);
    expect(game.motionPhaseForTesting, LilyFrogMotionPhase.orbiting);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('연잎만 회전하고 개구리는 항상 화면 위를 본다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(5),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    final initialPadAngle = game.padAngleForTesting(0)!;

    game.update(0.1);

    expect(game.frogAngleForTesting, 0);
    expect(game.padAngleForTesting(0), greaterThan(initialPadAngle));

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('모든 연잎 비주얼이 현재 실제 각속도를 함께 따른다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(5),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);

    for (final padId in [0, 1, 2]) {
      expect(game.padAngularSpeedForTesting(padId), closeTo(1.35, 1e-9));
    }

    game.setElapsedSecondsForPreview(140);
    game.update(0.001);

    for (final padId in [0, 1, 2]) {
      expect(game.padAngularSpeedForTesting(padId), closeTo(2.80, 1e-9));
    }

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('카운트다운에도 개구리가 연잎과 함께 공전한다', (tester) async {
    final game = LilyFrogGame(random: Random(6), onFinished: (_) {});
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    final initialPosition = game.frogPositionForTesting;

    game.update(0.1);

    expect(
      game.frogPositionForTesting.distanceTo(initialPosition),
      greaterThan(0),
    );
    expect(game.frogAngleForTesting, 0);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('시작부터 안전한 후속 연잎 네 세대를 미리 만든다', (tester) async {
    final game = LilyFrogGame(random: Random(9), onFinished: (_) {});
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);

    expect(game.safeFuturePadCountForTesting, greaterThanOrEqualTo(4));
    expect(game.padEdgeGapForTesting(0, 1), greaterThanOrEqualTo(12));
    expect(game.padEdgeGapForTesting(1, 2), greaterThanOrEqualTo(12));

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('점프 후 맨 위에 드러난 연잎은 출발 전부터 존재한다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(31),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    final padsBeforeLaunch = game.allPadIdsForTesting;
    final targetId = game.nextSafePadIdForTesting!;
    game.setOrbitThetaForTesting(game.launchThetaForPadForTesting(targetId)!);
    expect(game.tapForTesting(), isTrue);

    for (var tick = 0; tick < 300; tick++) {
      game.update(0.005);
      if (game.currentPadIdForTesting == targetId &&
          game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 40));

    expect(game.visiblePadIdsForTesting.difference(padsBeforeLaunch), isEmpty);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('접선 점프로 첫 연잎에 착지해 기본 점수를 얻는다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(11),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    final theta = game.launchThetaForPadForTesting(1);
    expect(theta, isNotNull);
    game.setOrbitThetaForTesting(theta!);
    expect(game.predictedLandingPadIdForTesting, 1);
    final predictedLanding = game.predictedLandingPointForTesting;
    expect(predictedLanding, isNotNull);
    expect(game.tapForTesting(), isTrue);
    expect(
      game.visibleTrajectoryEndForTesting!.distanceTo(predictedLanding!),
      lessThan(0.001),
    );

    for (var tick = 0; tick < 200; tick++) {
      game.update(0.005);
      if (game.currentPadIdForTesting == 1) {
        break;
      }
    }
    expect(
      game.frogPositionForTesting.distanceTo(predictedLanding),
      lessThan(1),
    );
    for (var tick = 0; tick < 20; tick++) {
      game.update(0.02);
      if (game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) break;
    }

    expect(game.currentPadIdForTesting, 1);
    expect(game.scoreForTesting, 310);
    expect(game.newLandingsForTesting, 1);
    expect(game.safeFuturePadCountForTesting, greaterThanOrEqualTo(2));

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('착지한 프레임부터 멈추지 않고 새 연잎을 공전한다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(11),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    final theta = game.launchThetaForPadForTesting(1)!;
    game.setOrbitThetaForTesting(theta);
    expect(game.tapForTesting(), isTrue);

    for (var tick = 0; tick < 100; tick++) {
      game.update(0.01);
      if (game.currentPadIdForTesting == 1 &&
          game.motionPhaseForTesting == LilyFrogMotionPhase.landing) {
        break;
      }
    }
    expect(game.motionPhaseForTesting, LilyFrogMotionPhase.landing);
    final positionAtContact = game.frogPositionForTesting;

    game.update(0.03);

    expect(
      game.frogPositionForTesting.distanceTo(positionAtContact),
      greaterThan(0),
    );

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('착지 중 받은 탭은 지연 없이 다음 점프로 이어진다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(11),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    final firstTargetId = game.nextSafePadIdForTesting!;
    game.setOrbitThetaForTesting(
      game.launchThetaForPadForTesting(firstTargetId)!,
    );
    expect(game.tapForTesting(), isTrue);

    for (var tick = 0; tick < 120; tick++) {
      game.update(0.01);
      if (game.motionPhaseForTesting == LilyFrogMotionPhase.landing) break;
    }
    expect(game.currentPadIdForTesting, firstTargetId);
    expect(game.motionPhaseForTesting, LilyFrogMotionPhase.landing);

    final secondTargetId = game.nextSafePadIdForTesting!;
    final secondTheta = game.launchThetaForPadForTesting(secondTargetId);
    expect(secondTheta, isNotNull);
    game.setOrbitThetaForTesting(secondTheta!);

    expect(game.tapForTesting(), isTrue);
    expect(game.motionPhaseForTesting, LilyFrogMotionPhase.airborne);
    expect(game.launchCountForTesting, 2);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('연잎 회전 방향은 생성 때 정해지고 점프·착지 중 바뀌지 않는다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(11),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);

    const startCenter = Point<double>(122, 500);
    const firstCenter = Point<double>(238, 312);
    const secondCenter = Point<double>(122, 144);
    final startClockwise = LilyFrogRules.optimalClockwiseForNextJump(
      fromCenter: startCenter,
      orbitRadius: 104,
      landingPoint: const Point<double>(122, 396),
      angularSpeed: 1.35,
      targetCenter: firstCenter,
      targetLandingRadius: 106,
      fallbackClockwise: false,
    );
    final firstLandingPoint =
        LilyFrogRules.bestTangentLandingPoint(
          fromCenter: startCenter,
          orbitRadius: 104,
          clockwise: startClockwise,
          targetCenter: firstCenter,
          targetLandingRadius: 106,
        ) ??
        LilyFrogRules.orbitPosition(
          center: firstCenter,
          radius: 96,
          theta: -pi / 2,
        );
    final expectedFirstDirection = LilyFrogRules.optimalClockwiseForNextJump(
      fromCenter: firstCenter,
      orbitRadius: 96,
      landingPoint: firstLandingPoint,
      angularSpeed: 1.35,
      targetCenter: secondCenter,
      targetLandingRadius: 98,
      fallbackClockwise: true,
    );
    expect(game.padClockwiseForTesting(1), expectedFirstDirection);

    final firstDirection = game.padClockwiseForTesting(1);
    final secondDirection = game.padClockwiseForTesting(2);
    final firstTargetId = game.nextSafePadIdForTesting!;
    game.setOrbitThetaForTesting(
      game.launchThetaForPadForTesting(firstTargetId)!,
    );
    expect(game.tapForTesting(), isTrue);
    expect(game.padClockwiseForTesting(1), firstDirection);
    expect(game.padClockwiseForTesting(2), secondDirection);

    for (var tick = 0; tick < 120; tick++) {
      game.update(0.01);
      if (game.motionPhaseForTesting == LilyFrogMotionPhase.landing) break;
    }
    expect(game.currentPadIdForTesting, firstTargetId);
    expect(game.padClockwiseForTesting(1), firstDirection);
    expect(game.padClockwiseForTesting(2), secondDirection);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('홈 시연 시드로 연속 자동 착지해도 생성기가 멈추지 않는다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(20260815),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);

    var wideJumps = 0;
    for (var landing = 0; landing < 18; landing++) {
      final previousX = game
          .padCenterForTesting(game.currentPadIdForTesting)!
          .x;
      final nextX = game.padCenterForTesting(game.nextSafePadIdForTesting!)!.x;
      if ((nextX - previousX).abs() >= 60) wideJumps++;
      expect(game.launchSafeImmediatelyForPreview(), isTrue);
      for (var tick = 0; tick < 300; tick++) {
        game.update(0.01);
        await tester.pump();
        if (game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) break;
      }
      expect(
        game.motionPhaseForTesting,
        LilyFrogMotionPhase.orbiting,
        reason: 'landing=$landing',
      );
    }

    expect(game.newLandingsForTesting, 18);
    expect(wideJumps, greaterThanOrEqualTo(9));
    expect(game.comboForTesting, 18);
    expect(game.hud.value.distance, 18);
    final landingPercent = game.hud.value.comboRemainingPercent!;
    expect(landingPercent, inExclusiveRange(0, 101));
    game.update(0.5);
    final drainingPercent = game.hud.value.comboRemainingPercent!;
    expect(drainingPercent, lessThan(landingPercent));
    expect(game.launchSafeImmediatelyForPreview(), isTrue);
    final frozenPercent = game.hud.value.comboRemainingPercent;
    game.update(0.05);
    expect(game.motionPhaseForTesting, LilyFrogMotionPhase.airborne);
    expect(game.hud.value.comboRemainingPercent, frozenPercent);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('착지 후 한 바퀴를 넘기면 콤보가 끊기고 다음 착지에서 1로 시작한다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(11),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    expect(game.launchSafeImmediatelyForPreview(), isTrue);
    for (var tick = 0; tick < 300; tick++) {
      game.update(0.01);
      await tester.pump();
      if (game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) break;
    }
    expect(game.comboForTesting, 1);
    expect(game.hud.value.comboRemainingPercent, inExclusiveRange(0, 101));
    final scoreAfterFirstLanding = game.scoreForTesting;

    final speed = LilyFrogRules.difficultyAt(0).angularSpeed;
    for (var tick = 0; tick < 500; tick++) {
      game.update(0.01);
      if (tick * 0.01 * speed >= 2 * pi) break;
    }
    expect(game.comboForTesting, 0);
    expect(game.hud.value.distance, 0);
    expect(game.hud.value.comboRemainingPercent, isNull);

    expect(game.launchSafeImmediatelyForPreview(), isTrue);
    for (var tick = 0; tick < 300; tick++) {
      game.update(0.01);
      await tester.pump();
      if (game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) break;
    }
    expect(game.comboForTesting, 1);
    expect(game.hud.value.comboRemainingPercent, inExclusiveRange(0, 101));
    expect(
      game.scoreForTesting,
      greaterThanOrEqualTo(scoreAfterFirstLanding + 310),
    );
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('설명 시연은 각도를 순간이동하지 않고 실제 회전 후 점프한다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(20260816),
      enableHaptics: false,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    final targetId = game.nextSafePadIdForTesting!;

    for (var index = 0; index < 360; index++) {
      game.setOrbitThetaForTesting(2 * pi * index / 360);
      if (game.predictedLandingPadIdForTesting != targetId) break;
    }
    final positionBefore = game.frogPositionForTesting;

    expect(game.launchWhenSafeForPreview(), isFalse);
    expect(game.frogPositionForTesting, positionBefore);

    var waitedSeconds = 0.0;
    var launched = false;
    for (var tick = 0; tick < 600; tick++) {
      game.update(0.01);
      waitedSeconds += 0.01;
      if (game.launchWhenSafeForPreview()) {
        launched = true;
        break;
      }
    }

    expect(launched, isTrue);
    expect(waitedSeconds, greaterThan(0.05));
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('세 번째 착지 뒤 다섯 번째 일반·황금 선택지가 미리 보인다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(27),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);

    for (var landing = 0; landing < 3; landing++) {
      final targetId = game.nextSafePadIdForTesting;
      expect(targetId, isNotNull);
      final theta = game.launchThetaForPadForTesting(targetId!);
      expect(theta, isNotNull);
      game.setOrbitThetaForTesting(theta!);
      expect(game.tapForTesting(), isTrue);
      for (var tick = 0; tick < 240; tick++) {
        game.update(0.005);
        if (game.currentPadIdForTesting == targetId) break;
      }
      for (var tick = 0; tick < 120; tick++) {
        game.update(0.01);
        if (game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) break;
      }
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(game.goldenFuturePadCountForTesting, 1);
    expect(game.fliesTargetOnlyNormalPadsForTesting, isTrue);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('일반 경로의 파리에 닿으면 즉시 점수와 POP 이펙트가 생긴다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(27),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);

    var observedPop = false;
    for (var landing = 0; landing < 8 && !observedPop; landing++) {
      final targetId = game.nextSafePadIdForTesting!;
      final fliesBefore = game.fliesCaughtForTesting;
      final hasFlyRoute = game.flyTargetPadIdsForTesting.contains(targetId);
      final theta = hasFlyRoute
          ? game.launchThetaForFlyRouteForTesting(targetId)
          : game.launchThetaForPadForTesting(targetId);
      expect(
        theta,
        isNotNull,
        reason:
            'landing=$landing current=${game.currentPadIdForTesting} '
            'currentCenter=${game.padCenterForTesting(game.currentPadIdForTesting)} '
            'target=$targetId targetCenter=${game.padCenterForTesting(targetId)} '
            'window=${game.reachableWindowSecondsForTesting(game.currentPadIdForTesting, targetId)}',
      );
      if (theta == null) break;
      game.setOrbitThetaForTesting(theta);
      expect(game.predictedLandingPadIdForTesting, targetId);
      expect(game.tapForTesting(), isTrue);
      for (var tick = 0; tick < 260; tick++) {
        game.update(0.005);
        if (game.fliesCaughtForTesting > fliesBefore) {
          game.update(0.001);
          expect(game.activeFlyCollectEffectCountForTesting, greaterThan(0));
          observedPop = true;
          break;
        }
        if (game.currentPadIdForTesting == targetId) break;
      }
      if (observedPop) break;
      for (var tick = 0; tick < 120; tick++) {
        game.update(0.01);
        if (game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) break;
      }
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(observedPop, isTrue);
    expect(game.scoreForTesting, greaterThanOrEqualTo(LilyFrogRules.flyScore));

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('파리 경로로 점프하면 착지 전에 해당 경로의 파리를 모두 먹는다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(27),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);

    for (var landing = 0; landing < 8; landing++) {
      final targetId = game.nextSafePadIdForTesting!;
      final flyCount = game.flyCountForPadForTesting(targetId);
      final theta = flyCount > 0
          ? game.launchThetaForFlyRouteForTesting(targetId)
          : game.launchThetaForPadForTesting(targetId);
      expect(theta, isNotNull);
      final caughtBefore = game.fliesCaughtForTesting;
      final scoreBefore = game.scoreForTesting;
      game.setOrbitThetaForTesting(theta!);
      expect(game.tapForTesting(), isTrue);
      for (var tick = 0; tick < 260; tick++) {
        game.update(0.005);
        if (game.currentPadIdForTesting == targetId) break;
      }
      if (flyCount > 0) {
        expect(game.fliesCaughtForTesting - caughtBefore, flyCount);
        final expectedLandingScore =
            LilyFrogRules.baseLandingScore +
            game.comboForTesting * LilyFrogRules.comboScore;
        final expectedFlightScore =
            expectedLandingScore + flyCount * LilyFrogRules.flyScore;
        expect(game.scoreForTesting - scoreBefore, expectedFlightScore);
        expect(game.hud.value.message, '+$expectedLandingScore');
        break;
      }
      for (var tick = 0; tick < 120; tick++) {
        game.update(0.01);
        if (game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) break;
      }
      await tester.pump(const Duration(milliseconds: 30));
    }

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('점프 경로 가이드는 처음 세 번의 점프까지만 표시한다', (tester) async {
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(17),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);

    expect(game.trajectoryGuideVisibleForTesting, isTrue);
    for (var launch = 1; launch <= 3; launch++) {
      final targetId = game.nextSafePadIdForTesting!;
      game.setOrbitThetaForTesting(game.launchThetaForPadForTesting(targetId)!);
      expect(game.tapForTesting(), isTrue);
      expect(game.launchCountForTesting, launch);
      expect(game.trajectoryGuideVisibleForTesting, isTrue);
      for (var tick = 0; tick < 260; tick++) {
        game.update(0.005);
        if (game.currentPadIdForTesting == targetId) break;
      }
      for (var tick = 0; tick < 120; tick++) {
        game.update(0.01);
        if (game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting) break;
      }
    }

    expect(game.motionPhaseForTesting, LilyFrogMotionPhase.orbiting);
    expect(game.trajectoryGuideVisibleForTesting, isFalse);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('시간 종료는 정확히 한 번 결과를 방출한다', (tester) async {
    final results = <GameResult>[];
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      gameDuration: const Duration(milliseconds: 100),
      random: Random(3),
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(seconds: 1));

    expect(results, hasLength(1));
    expect(results.single.endType, GameEndType.timeUp);
    expect(results.single.collisions, 0);
    expect(game.isTerminalForTesting, isTrue);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('기본 경기 시간 150초에 정확히 종료한다', (tester) async {
    final results = <GameResult>[];
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(3),
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    expect(game.hud.value.remainingSeconds, 150);
    game.setElapsedSecondsForPreview(149.99);
    game.update(0.02);

    expect(results, hasLength(1));
    expect(results.single.endType, GameEndType.timeUp);
    expect(results.single.duration, const Duration(seconds: 150));
    expect(game.hud.value.remainingSeconds, 0);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('안전 오프닝 뒤 물에 빠지면 게임오버 결과를 한 번만 방출한다', (tester) async {
    final results = <GameResult>[];
    final game = LilyFrogGame(
      countdownDuration: Duration.zero,
      random: Random(19),
      onFinished: results.add,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _pumpUntilLoaded(tester, game);
    for (var frame = 0; frame < 31; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    game.setOrbitThetaForTesting(0);
    expect(game.tapForTesting(), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(results, hasLength(1));
    expect(results.single.endType, GameEndType.gameOver);
    expect(results.single.collisions, 1);
    expect(game.isTerminalForTesting, isTrue);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpUntilLoaded(WidgetTester tester, LilyFrogGame game) async {
  for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(game.isLoaded, isTrue);
}
