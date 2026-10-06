import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/midnight_snake/midnight_snake_game.dart';

void main() {
  test('direction hit areas expand without accepting board taps', () {
    final visuals = MidnightSnakeGame.controlVisualRects;
    final hits = MidnightSnakeGame.controlHitRects;

    expect(hits[0].width, closeTo(visuals[0].width + 36, 0.0001));
    expect(hits[0].height, closeTo(visuals[0].height + 36, 0.0001));
    expect(hits[1].top, MidnightSnakeGame.controlBarRect.top);
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(70, 650)),
      SnakeDirection.left,
    );
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(140, 610)),
      SnakeDirection.up,
    );
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(290, 650)),
      SnakeDirection.right,
    );

    // The point is in the expanded overlap between left and down, outside
    // both visual rects, and exactly equidistant from their centers.
    final leftCenter = visuals[0].center;
    final downCenter = visuals[2].center;
    final tiePoint = Vector2(
      (leftCenter.dx + downCenter.dx) / 2,
      leftCenter.dy,
    );
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(tiePoint),
      SnakeDirection.left,
    );

    // A visual button wins when its expanded neighbor also contains the tap.
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(150, 680)),
      SnakeDirection.down,
    );
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(100, 500)),
      isNull,
    );
  });

  test('initial HUD and repeated interruption never submit a score', () {
    var finishCount = 0;
    final game = MidnightSnakeGame(
      random: Random(7),
      onFinished: (_) => finishCount++,
    );

    expect(game.hud.value.phase, MiniGamePhase.countdown);
    expect(game.hud.value.remainingSeconds, 300);
    game.interrupt();
    game.interrupt();

    expect(finishCount, 0);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    game.disposeController();
  });

  testWidgets('loads every bonus asset and creates non-overlapping events', (
    tester,
  ) async {
    final game = MidnightSnakeGame(
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

    expect(game.isLoaded, isTrue);
    expect(game.boardRectForTesting, const Rect.fromLTWH(48, 108, 264, 468));
    expect(game.stateForTesting.goldenSpawnAtSeconds, inInclusiveRange(30, 60));
    expect(game.stateForTesting.mouseSpawnAtSeconds, double.infinity);

    game.pauseEngine();
    final state = game.stateForTesting;
    state.updateBonusEvents(
      elapsedSeconds: state.goldenSpawnAtSeconds,
      random: Random(21),
    );
    expect(state.goldenSausage, isNotNull);
    expect(state.mouse, isNull);

    state.updateBonusEvents(
      elapsedSeconds:
          state.goldenSpawnAtSeconds + const Duration(seconds: 10).inSeconds,
      random: Random(22),
    );
    state.updateBonusEvents(
      elapsedSeconds: state.mouseSpawnAtSeconds,
      random: Random(23),
    );
    expect(state.goldenSausage, isNull);
    expect(state.mouse, isNotNull);
    expect(state.body, isNot(contains(state.mouse)));
    expect(state.food, isNot(state.mouse));

    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bottom direction buttons steer through the real pointer path', (
    tester,
  ) async {
    const gameKey = Key('midnight-snake-pointer-game-widget');
    tester.view
      ..physicalSize = const Size(360, 680)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final game = MidnightSnakeGame(
      random: Random(12),
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: GameWidget(key: gameKey, game: game),
        ),
      ),
    );
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    game.pauseEngine();
    await tester.pump();

    expect(
      game.boardRectForTesting.bottom,
      lessThan(game.controlsRectForTesting.top),
    );
    expect(game.controlsRectForTesting, const Rect.fromLTWH(0, 590, 360, 174));
    expect(
      MidnightSnakeGame.controlBackgroundSourceRect,
      const Rect.fromLTWH(0, 590, 360, 114),
    );
    expect(
      MidnightSnakeGame.controlCabinetSourceRect,
      const Rect.fromLTWH(43, 596, 68, 84),
    );
    final controls = game.controlButtonRectsForTesting;
    expect(controls[1].center.dy, lessThan(controls[2].center.dy));
    expect(controls[1].center.dx, closeTo(controls[2].center.dx, 3));
    expect(
      MidnightSnakeGame.controlVisualRects[0].width,
      closeTo(62.475, 0.0001),
    );
    expect(
      MidnightSnakeGame.controlVisualRects[0].height,
      closeTo(60.9875, 0.0001),
    );
    expect(
      MidnightSnakeGame.controlVisualRects[1].width,
      closeTo(62.475, 0.0001),
    );
    expect(
      MidnightSnakeGame.controlVisualRects[1].height,
      closeTo(59.5, 0.0001),
    );
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(84, 720)),
      SnakeDirection.left,
    );
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(149, 601)),
      SnakeDirection.up,
    );
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(149, 720)),
      SnakeDirection.down,
    );
    expect(
      MidnightSnakeGame.directionAtLogicalPoint(Vector2(275, 720)),
      SnakeDirection.right,
    );
    for (final rect in game.controlButtonRectsForTesting) {
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
    }

    final gameOrigin = tester.getTopLeft(find.byKey(gameKey));
    final sameDirectionRect = MidnightSnakeGame.controlVisualRects[3];
    final sameDirectionCanvasPosition = game.camera.viewport.localToGlobal(
      Vector2(sameDirectionRect.center.dx, sameDirectionRect.center.dy),
    );
    await tester.tapAt(
      gameOrigin +
          Offset(sameDirectionCanvasPosition.x, sameDirectionCanvasPosition.y),
    );
    expect(game.lastTappedDirectionForTesting, SnakeDirection.right);
    expect(game.pressedDirectionForTesting, SnakeDirection.right);

    final tapOrder = [0, 1, 3, 2];
    for (final index in tapOrder) {
      final rect = game.controlButtonRectsForTesting[index];
      final canvasPosition = game.camera.viewport.localToGlobal(
        Vector2(rect.center.dx, rect.center.dy),
      );
      await tester.tapAt(
        gameOrigin + Offset(canvasPosition.x, canvasPosition.y),
      );
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.lastTappedDirectionForTesting, SnakeDirection.down);
    game.advanceForTesting();
    expect(game.stateForTesting.direction, SnakeDirection.up);
    game.advanceForTesting();
    expect(game.stateForTesting.direction, SnakeDirection.right);
    game.advanceForTesting();
    expect(game.stateForTesting.direction, SnakeDirection.down);
    expect(game.stateForTesting.head, const SnakeCell(7, 5));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('timeout result is emitted exactly once', (tester) async {
    var finishCount = 0;
    final game = MidnightSnakeGame(
      random: Random(7),
      countdownDuration: Duration.zero,
      gameDuration: const Duration(seconds: 1),
      onFinished: (_) => finishCount++,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var tick = 0; tick < 20; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(finishCount, 1);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    await tester.pump(const Duration(seconds: 1));
    expect(finishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('each pickup shows its actual gained score', (tester) async {
    final game = MidnightSnakeGame(
      random: Random(41),
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
    game.pauseEngine();

    expect(game.advanceForTesting().scoreGained, 0);
    expect(game.advanceForTesting().scoreGained, 1);
    expect(game.scorePopupForTesting, '+1');

    game.stateForTesting
      ..food = null
      ..goldenSausage = const SnakeCell(7, 7);
    expect(game.advanceForTesting().scoreGained, 3);
    expect(game.scorePopupForTesting, '+3');

    game.stateForTesting.mouse = const SnakeCell(7, 8);
    expect(game.advanceForTesting().scoreGained, 2);
    expect(game.scorePopupForTesting, '+2');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('collision death motion finishes before result emission', (
    tester,
  ) async {
    var finishCount = 0;
    final game = MidnightSnakeGame(
      random: Random(43),
      countdownDuration: Duration.zero,
      onFinished: (_) => finishCount++,
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    game.finishForTesting(SnakeFinishReason.wall);
    expect(game.deathProgressForTesting, 0);
    game.update(0.3);
    await tester.pump();
    expect(game.deathProgressForTesting, inExclusiveRange(0, 1));
    expect(finishCount, 0);
    game.update(1.0);
    await tester.pump();
    expect(game.deathProgressForTesting, 1);
    expect(finishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
