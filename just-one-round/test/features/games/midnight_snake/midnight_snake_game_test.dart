import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/midnight_snake/midnight_snake_game.dart';

void main() {
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
    expect(game.boardRectForTesting, const Rect.fromLTWH(36, 112, 288, 480));
    expect(game.stateForTesting.goldenSpawnAtSeconds, inInclusiveRange(30, 60));
    expect(game.stateForTesting.mouseSpawnAtSeconds, inInclusiveRange(60, 90));

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
      elapsedSeconds: max(
        state.mouseSpawnAtSeconds,
        state.goldenSpawnAtSeconds + 10,
      ),
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
