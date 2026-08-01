import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/midnight_snake/midnight_snake_game.dart';

void main() {
  testWidgets('bonus pickups render in the real 360x640 runtime', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final game = MidnightSnakeGame(
      random: Random(31),
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(child: GameWidget(game: game)),
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

    final state = game.stateForTesting;
    state.updateBonusEvents(
      elapsedSeconds: state.goldenSpawnAtSeconds,
      random: Random(33),
    );
    await tester.pump();
    expect(state.goldenSausage, isNotNull);
    expect(tester.takeException(), isNull);
    state.updateBonusEvents(
      elapsedSeconds: state.goldenSpawnAtSeconds + 10,
      random: Random(34),
    );
    state.updateBonusEvents(
      elapsedSeconds: max(
        state.mouseSpawnAtSeconds,
        state.goldenSpawnAtSeconds + 10,
      ),
      random: Random(35),
    );
    await tester.pump();
    expect(state.goldenSausage, isNull);
    expect(state.mouse, isNotNull);
    expect(tester.takeException(), isNull);

    game.finishForTesting(SnakeFinishReason.wall);
    game.update(0.4);
    await tester.pump();
    expect(game.deathProgressForTesting, inExclusiveRange(0, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
