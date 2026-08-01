import 'dart:math';

import 'package:flame/game.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/sausage_dachshund/domain/sausage_dachshund_rules.dart';
import 'package:just_one_round/features/games/sausage_dachshund/sausage_dachshund_game.dart';

void main() {
  test('초기 HUD와 반복 중단은 결과를 제출하지 않는다', () {
    var finishCount = 0;
    final game = SausageDachshundGame(
      random: Random(7),
      onFinished: (_) => finishCount++,
    );

    expect(game.hud.value.phase, MiniGamePhase.countdown);
    expect(game.hud.value.remainingSeconds, 150);
    game.interrupt();
    game.interrupt();

    expect(finishCount, 0);
    expect(game.hud.value.phase, MiniGamePhase.finished);
    game.disposeController();
  });

  testWidgets('보드와 에셋을 로드하고 한 틱에 입력 하나만 예약한다', (tester) async {
    final game = SausageDachshundGame(
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

    expect(game.boardRectForTesting, const Rect.fromLTWH(36, 112, 288, 480));
    expect(game.stateForTesting.body, hasLength(4));
    expect(game.queueSwipeForTesting(Vector2(0, -30)), isTrue);
    expect(game.queueSwipeForTesting(Vector2(0, 30)), isFalse);

    await tester.pump(const Duration(milliseconds: 650));
    expect(game.stateForTesting.direction, DachshundDirection.up);
    expect(game.stateForTesting.head, const DachshundCell(6, 4));
    expect(game.movementProgressForTesting, 0);

    await tester.pump(const Duration(milliseconds: 80));
    expect(game.movementProgressForTesting, inExclusiveRange(0, 1));

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('첫 소시지를 먹어 점수와 길이를 올린다', (tester) async {
    final game = SausageDachshundGame(
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
    for (var tick = 0; tick < 13; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(game.stateForTesting.score, 1);
    expect(game.stateForTesting.body, hasLength(5));
    expect(game.bodySpriteIndicesForTesting, [0, 0, 0]);
    expect(game.hud.value.score, 1);

    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('시간 종료 결과는 정확히 한 번만 방출한다', (tester) async {
    var finishCount = 0;
    final results = <Object>[];
    final game = SausageDachshundGame(
      random: Random(7),
      countdownDuration: Duration.zero,
      gameDuration: const Duration(seconds: 1),
      onFinished: (result) {
        finishCount++;
        results.add(result);
      },
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
    expect(results, hasLength(1));
    expect(game.isTerminalForTesting, isTrue);
    expect(game.hud.value.phase, MiniGamePhase.finished);

    await tester.pump(const Duration(seconds: 1));
    expect(finishCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
