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
    expect(game.currentPathLengthForTesting, 4);
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
    expect(game.scoreForTesting, 425);
    expect(game.rescuedDuckCountForTesting, 1);
    expect(game.visibleRescuedDuckCountForTesting, 1);
    expect(game.feverTierForTesting, MamaDuckFeverTier.none);

    await tester.pump(const Duration(milliseconds: 600));
    expect(game.isCheeringForTesting, isTrue);
    expect(game.isMotherCheeringForTesting, isTrue);
    expect(game.successDuckCentersForTesting, hasLength(1));
    final duckAtSuccess = game.successDuckCentersForTesting.single;
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
    expect(game.currentPathLengthForTesting, 5);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('첫 4칸 경로부터 조기 손 떼기는 목숨을 차감하고 늑대만 표시한다', (tester) async {
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
    expect(path, hasLength(4));
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
    expect(game.successDuckCentersForTesting, hasLength(3));
    expect(game.isMotherCheeringForTesting, isTrue);
    expect(game.successDuckCentersForTesting.toSet(), hasLength(3));
    final successPath = game.pathForTesting;
    for (var duckIndex = 0; duckIndex < 3; duckIndex++) {
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
