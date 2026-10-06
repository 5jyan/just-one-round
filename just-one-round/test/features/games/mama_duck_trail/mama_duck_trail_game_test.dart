import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/mama_duck_trail/domain/mama_duck_trail_rules.dart';
import 'package:just_one_round/features/games/mama_duck_trail/mama_duck_trail_game.dart';

void main() {
  test('늑대는 실패 직후 입을 빠르게 벌리고 1초 안에 동작을 마친다', () {
    expect(MamaDuckTrailGame.wolfFailureFrameForElapsed(0), 0);
    expect(MamaDuckTrailGame.wolfFailureFrameForElapsed(0.10), 1);
    expect(MamaDuckTrailGame.wolfFailureFrameForElapsed(0.20), 2);
    expect(MamaDuckTrailGame.wolfFailureFrameForElapsed(0.43), 2);
    expect(MamaDuckTrailGame.wolfFailureFrameForElapsed(0.44), 3);
    expect(MamaDuckTrailGame.wolfFailureFrameForElapsed(0.60), 4);
    expect(MamaDuckTrailGame.wolfFailureFrameForElapsed(0.80), 5);
    expect(MamaDuckTrailGame.wolfFailureFrameForElapsed(1), 5);
  });

  test('초기 HUD와 반복 중단이 안전하다', () {
    var finishCount = 0;
    final game = MamaDuckTrailGame(
      random: Random(7),
      onFinished: (_) => finishCount++,
    );

    expect(game.hud.value.phase, MiniGamePhase.countdown);
    expect(game.hud.value.score, 0);
    expect(game.hud.value.remainingSeconds, 120);

    game.interrupt();
    game.interrupt();

    expect(finishCount, 0);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    game.disposeController();
  });

  testWidgets('보드는 화면 폭을 채우고 단계에 필요한 캐릭터만 표시한다', (tester) async {
    final game = MamaDuckTrailGame(
      random: Random(7),
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(game.boardRectForTesting, const Rect.fromLTWH(0, 68, 360, 504));
    expect(game.currentPathLengthForTesting, 7);
    expect(game.visibleActorsForTesting, {'mother'});

    for (
      var attempt = 0;
      attempt < 50 && !game.isRecallingForTesting;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.isRecallingForTesting, isTrue);
    expect(game.visibleActorsForTesting, {'mother'});

    final path = game.pathForTesting;
    game.beginLogicalDragForTesting(game.cellCenterForTesting(path.first));
    for (final cell in path.skip(1)) {
      game.updateLogicalDragForTesting(game.cellCenterForTesting(cell));
    }

    expect(game.visibleActorsForTesting, {'mother', 'duckling'});
    expect(game.livesForTesting, 3);
    expect(game.scoreForTesting, 725);
    expect(game.rescuedDuckCountForTesting, 1);
    expect(game.visibleRescuedDuckCountForTesting, 1);
    expect(game.feverTierForTesting, MamaDuckFeverTier.none);

    await tester.pump(const Duration(milliseconds: 600));
    expect(game.isCheeringForTesting, isTrue);
    expect(game.isMotherCheeringForTesting, isTrue);
    expect(game.successDuckCentersForTesting, hasLength(path.length - 1));
    final duckAtSuccess = game.successDuckCentersForTesting.first;
    for (var index = 0; index < path.length - 1; index++) {
      expect(
        game.successDuckCentersForTesting[index].distanceTo(
          game.cellCenterForTesting(path[path.length - 2 - index]),
        ),
        closeTo(0, 0.001),
      );
    }
    final expectedDuckCenter = game.cellCenterForTesting(path[path.length - 2]);
    final motherAtSuccess = game.successMotherCenterForTesting;
    final expectedMotherCenter = game.cellCenterForTesting(path.last);
    expect(duckAtSuccess.x, closeTo(expectedDuckCenter.x, 0.001));
    expect(duckAtSuccess.y, closeTo(expectedDuckCenter.y, 0.001));
    expect(motherAtSuccess.x, closeTo(expectedMotherCenter.x, 0.001));
    expect(motherAtSuccess.y, closeTo(expectedMotherCenter.y, 0.001));
    expect(duckAtSuccess.distanceTo(motherAtSuccess), closeTo(72, 0.001));
    final elapsedDuringCheer = game.playingElapsedForTesting;

    await tester.pump(const Duration(seconds: 1));
    expect(game.isCheeringForTesting, isTrue);
    expect(game.playingElapsedForTesting, elapsedDuringCheer);

    await tester.pump(const Duration(milliseconds: 600));
    expect(game.visibleActorsForTesting, {'mother'});
    expect(game.currentPathLengthForTesting, 8);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('첫 7칸 경로부터 조기 손 떼기는 목숨을 차감하고 늑대만 표시한다', (tester) async {
    final game = MamaDuckTrailGame(
      random: Random(7),
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (
      var attempt = 0;
      attempt < 50 && !game.isRecallingForTesting;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final path = game.pathForTesting;
    expect(path, hasLength(7));
    game.beginLogicalDragForTesting(game.cellCenterForTesting(path.first));
    game.endLogicalDragForTesting();

    expect(game.visibleActorsForTesting, {'wolf'});
    expect(game.livesForTesting, 2);
    expect(game.scoreForTesting, 0);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('구조 행렬은 성공마다 남고 3콤보 피버는 실패하면 해제된다', (tester) async {
    final game = MamaDuckTrailGame(
      random: Random(11),
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    for (var round = 1; round <= 3; round++) {
      await _advanceToRecall(tester, game);
      final path = game.pathForTesting;
      game.beginLogicalDragForTesting(game.cellCenterForTesting(path.first));
      for (final cell in path.skip(1)) {
        game.updateLogicalDragForTesting(game.cellCenterForTesting(cell));
      }
      expect(game.rescuedDuckCountForTesting, round);
      expect(game.visibleRescuedDuckCountForTesting, round);
    }

    expect(game.feverTierForTesting, MamaDuckFeverTier.goldenTrail);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      game.successDuckCentersForTesting,
      hasLength(game.currentPathLengthForTesting - 1),
    );
    expect(game.isMotherCheeringForTesting, isTrue);
    expect(
      game.successDuckCentersForTesting.toSet(),
      hasLength(game.currentPathLengthForTesting - 1),
    );
    final successPath = game.pathForTesting;
    for (var duckIndex = 0; duckIndex < successPath.length - 1; duckIndex++) {
      final expectedCenter = game.cellCenterForTesting(
        successPath[successPath.length - 2 - duckIndex],
      );
      expect(
        game.successDuckCentersForTesting[duckIndex].distanceTo(expectedCenter),
        closeTo(0, 0.001),
      );
    }

    await _advanceToRecall(tester, game);
    final nextPath = game.pathForTesting;
    game.beginLogicalDragForTesting(game.cellCenterForTesting(nextPath.first));
    game.endLogicalDragForTesting();

    expect(game.feverTierForTesting, MamaDuckFeverTier.none);
    expect(game.rescuedDuckCountForTesting, 3);
    expect(game.visibleRescuedDuckCountForTesting, 3);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('이동 중 입력은 무시하고 무효 시작 뒤에는 자동으로 회상으로 전환한다', (tester) async {
    final game = MamaDuckTrailGame(
      random: Random(7),
      countdownDuration: const Duration(seconds: 30),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await _preparePreview(tester, game);
    final path = game.pathForTesting;
    final travelDuration =
        (path.length - 1) * MamaDuckTrailRules.pathStepSeconds;
    final start = game.cellCenterForTesting(path.first);

    game.update(travelDuration - 0.02);
    game.beginLogicalDragForTesting(start);
    expect(game.isRecallingForTesting, isFalse);

    game.update(0.03);
    game.beginLogicalDragForTesting(game.cellCenterForTesting(path[1]));
    expect(game.isRecallingForTesting, isFalse);
    expect(game.livesForTesting, 3);

    game.update(
      path.length * MamaDuckTrailRules.pathStepSeconds +
          MamaDuckTrailRules.holdSecondsAt(0) +
          MamaDuckTrailRules.recallReadyDelaySeconds,
    );
    expect(game.isRecallingForTesting, isTrue);
    expect(game.visibleActorsForTesting, {'mother'});
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('도착 후 발자국 유지 구간의 같은 드래그가 즉시 첫 칸부터 성공한다', (tester) async {
    final game = MamaDuckTrailGame(
      random: Random(7),
      countdownDuration: const Duration(seconds: 30),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await _preparePreview(tester, game);
    final path = game.pathForTesting;
    final travelDuration =
        (path.length - 1) * MamaDuckTrailRules.pathStepSeconds;
    game.update(travelDuration + 0.1);

    game.beginLogicalDragForTesting(game.cellCenterForTesting(path.first));
    expect(game.isRecallingForTesting, isTrue);
    for (final cell in path.skip(1)) {
      game.updateLogicalDragForTesting(game.cellCenterForTesting(cell));
    }

    expect(game.scoreForTesting, 725);
    expect(game.livesForTesting, 3);
    expect(game.rescuedDuckCountForTesting, 1);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('도착 후 발자국이 사라지는 중에도 같은 드래그가 즉시 성공한다', (tester) async {
    final game = MamaDuckTrailGame(
      random: Random(7),
      countdownDuration: const Duration(seconds: 30),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await _preparePreview(tester, game);
    final path = game.pathForTesting;
    final travelDuration =
        (path.length - 1) * MamaDuckTrailRules.pathStepSeconds;
    final fadeStart =
        path.length * MamaDuckTrailRules.pathStepSeconds +
        MamaDuckTrailRules.holdSecondsAt(0);
    expect(fadeStart, greaterThan(travelDuration));
    game.update(fadeStart + 0.05);

    game.beginLogicalDragForTesting(game.cellCenterForTesting(path.first));
    expect(game.isRecallingForTesting, isTrue);
    for (final cell in path.skip(1)) {
      game.updateLogicalDragForTesting(game.cellCenterForTesting(cell));
    }

    expect(game.scoreForTesting, 725);
    expect(game.livesForTesting, 3);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('실제 드래그도 도착 직후 출발점을 첫 칸으로 소비한다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final game = MamaDuckTrailGame(
      random: Random(7),
      countdownDuration: const Duration(seconds: 30),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    final gameKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: GameWidget(key: gameKey, game: game),
        ),
      ),
    );
    await tester.pump();
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    game.update(game.countdownDuration.inMilliseconds / 1000);

    final path = game.pathForTesting;
    final travelDuration =
        (path.length - 1) * MamaDuckTrailRules.pathStepSeconds;
    game.update(travelDuration + 0.1);
    game.resumeEngine();

    final gameRect = tester.getRect(find.byKey(gameKey));
    final viewport = game.camera.viewport;
    Offset canvasPosition(Vector2 logicalPosition) {
      final point = viewport.localToGlobal(logicalPosition);
      return gameRect.topLeft + Offset(point.x, point.y);
    }

    final startPosition = canvasPosition(game.cellCenterForTesting(path.first));
    final gesture = await tester.startGesture(startPosition);
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(game.isRecallingForTesting, isTrue);
    await gesture.up();
    await tester.pump();

    expect(game.scoreForTesting, 0);
    expect(game.livesForTesting, 2);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _preparePreview(
  WidgetTester tester,
  MamaDuckTrailGame game,
) async {
  await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
  await tester.pump();
  for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(game.isLoaded, isTrue);
  game.pauseEngine();
  game.update(game.countdownDuration.inMilliseconds / 1000);
  expect(game.visibleActorsForTesting, {'mother'});
  expect(game.isRecallingForTesting, isFalse);
}

Future<void> _advanceToRecall(
  WidgetTester tester,
  MamaDuckTrailGame game,
) async {
  for (
    var attempt = 0;
    attempt < 100 && !game.isRecallingForTesting;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(game.isRecallingForTesting, isTrue);
}
