import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/bathhouse_sort/bathhouse_sort_game.dart';
import 'package:just_one_round/features/games/bathhouse_sort/domain/bathhouse_sort_rules.dart';

void main() {
  testWidgets('좌우 영역 탭만으로 현재 손님을 연속해서 보낸다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    for (var index = 0; index < 12; index++) {
      expect(_tapCurrent(game), BathhouseTapOutcome.correct);
      game.update(0.046);
    }

    expect(game.correctCount, 12);
    expect(game.combo, 12);
    expect(game.bestCombo, 12);
    expect(game.hud.value.score, 1860);
    expect(game.successBurstCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('실제 GameWidget 탭 이벤트도 좌우 분류로 연결된다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: GameWidget(key: const Key('tap-event-game-widget'), game: game),
      ),
    );
    await _waitUntilReady(tester, game);

    final logicalPosition = _positionFor(game.currentGuest.entrance);
    final canvasPosition = game.camera.viewport.localToGlobal(
      game.viewportPositionForWorld(logicalPosition),
    );
    final gameOrigin = tester.getTopLeft(
      find.byKey(const Key('tap-event-game-widget')),
    );
    await tester.tapAt(gameOrigin + Offset(canvasPosition.x, canvasPosition.y));
    await tester.pump();

    expect(game.correctCount, 1);
    expect(game.combo, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('실제 GameWidget의 빠른 7연타도 하나도 놓치지 않는다', (tester) async {
    const gameKey = Key('rapid-tap-game-widget');
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: GameWidget(key: gameKey, game: game),
      ),
    );
    await _waitUntilReady(tester, game);

    final entrances = game.guestQueue.map((guest) => guest.entrance).toList();
    final gameOrigin = tester.getTopLeft(find.byKey(gameKey));
    for (final entrance in entrances) {
      final canvasPosition = game.camera.viewport.localToGlobal(
        game.viewportPositionForWorld(_positionFor(entrance)),
      );
      await tester.tapAt(
        gameOrigin + Offset(canvasPosition.x, canvasPosition.y),
      );
    }
    game.update(0.13);
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.correctCount, 7);
    expect(game.combo, 7);
    expect(game.pendingInputCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('짧고 긴 휴대폰 비율을 월드 확장으로 채운다', () {
    expect(
      BathhouseSortGame.viewportResolutionForCanvas(Vector2(360, 800)),
      Vector2(360, 800),
    );
    expect(
      BathhouseSortGame.viewportResolutionForCanvas(Vector2(400, 640)),
      Vector2(400, 640),
    );
    expect(
      BathhouseSortGame.viewportResolutionForCanvas(Vector2(360, 1000)),
      Vector2(360, 900),
    );
  });

  testWidgets('카운트다운 HUD가 3, 2, 1을 차례로 갱신한다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: const Duration(seconds: 3),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    expect(game.hud.value.countdownNumber, 3);
    game.update(1.01);
    expect(game.hud.value.countdownNumber, 2);
    game.update(1);
    expect(game.hud.value.countdownNumber, 1);
    game.update(1);
    expect(game.gamePhase, BathhouseSortPhase.playing);
    expect(game.hud.value.countdownNumber, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('긴 화면의 추가 높이는 위에만 두고 버튼을 바닥에 붙인다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    expect(game.visibleTop, -160);
    expect(game.visibleBottom, 640);
    expect(game.viewportPositionForWorld(Vector2(80, 590)), Vector2(80, 750));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('콤보는 50에서 더 올라가지 않고 점수는 계속 누적된다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    for (var index = 0; index < 105; index++) {
      expect(_tapCurrent(game), BathhouseTapOutcome.correct);
      game.update(0.046);
    }

    expect(game.combo, 50);
    expect(game.bestCombo, 50);
    expect(game.hud.value.distance, 50);
    expect(game.hud.value.score, 34290);
    expect(game.hud.value.message, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('손님을 좌우로 드래그해도 판정되지 않는다', (tester) async {
    const gameKey = Key('tap-only-game-widget');
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: GameWidget(key: gameKey, game: game),
      ),
    );
    await _waitUntilReady(tester, game);

    final start = game.camera.viewport.localToGlobal(Vector2(180, 430));
    final origin = tester.getTopLeft(find.byKey(gameKey));
    await tester.dragFrom(
      origin + Offset(start.x, start.y),
      const Offset(80, 0),
    );
    await tester.pump();

    expect(game.correctCount, 0);
    expect(game.mistakeCount, 0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('반대쪽 탭은 오답 처리되고 상단 탭은 무시된다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    expect(game.tapLogical(Vector2(80, 100)), BathhouseTapOutcome.ignored);
    final wrongPosition = game.currentGuest.entrance == BathEntrance.mens
        ? Vector2(280, 590)
        : Vector2(80, 590);
    expect(game.tapLogical(wrongPosition), BathhouseTapOutcome.wrong);
    expect(game.mistakeCount, 1);
    expect(game.inputLocked, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('오답은 콤보를 끊고 250ms 동안 탭을 막는다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    expect(_tapCurrent(game), BathhouseTapOutcome.correct);
    final wrongPosition = game.currentGuest.entrance == BathEntrance.mens
        ? Vector2(280, 590)
        : Vector2(80, 590);
    expect(game.tapLogical(wrongPosition), BathhouseTapOutcome.queued);
    game.update(0.046);
    expect(game.combo, 0);
    expect(game.mistakeCount, 1);
    expect(_tapCurrent(game), BathhouseTapOutcome.ignored);

    game.update(0.249);
    expect(game.inputLocked, isTrue);
    game.update(0.002);
    expect(game.inputLocked, isFalse);
    expect(_tapCurrent(game), BathhouseTapOutcome.correct);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('60초 종료는 현재 점수를 정확히 한 번 제출한다', (tester) async {
    final results = <GameResult>[];
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      gameDuration: const Duration(seconds: 60),
      onFinished: results.add,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    _tapCurrent(game);
    game.update(64);
    game.update(1);

    expect(results, hasLength(1));
    expect(results.single.score, 100);
    expect(results.single.duration, const Duration(seconds: 60));
    expect(results.single.endType, GameEndType.timeUp);
    expect(_tapCurrent(game), BathhouseTapOutcome.ignored);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('15초에도 멈추거나 줄을 바꾸지 않고 얼굴표에 새 동물을 알린다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    expect(
      game.guestQueue.map((guest) => guest.species).toSet(),
      everyElement(
        isIn([BathhouseSpecies.blackBear, BathhouseSpecies.whiteRabbit]),
      ),
    );
    final queueBeforeMilestone = game.guestQueue;
    game.update(15);
    expect(game.gamePhase, BathhouseSortPhase.playing);
    expect(game.playingElapsed, 15);
    expect(game.activePairCount, 2);
    expect(game.rosterRevealPairIndex, 1);
    expect(game.guestQueue, queueBeforeMilestone);
    expect(_tapCurrent(game), BathhouseTapOutcome.correct);
    game.update(0.4);
    expect(game.playingElapsed, closeTo(15.4, 0.0001));
    expect(game.rosterRevealPairIndex, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('빠른 연속 탭을 FIFO로 예약해 보이는 일곱 손님을 순서대로 보낸다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    final visibleEntrances = game.guestQueue
        .map((guest) => guest.entrance)
        .toList();
    expect(
      game.tapLogical(_positionFor(visibleEntrances.first)),
      BathhouseTapOutcome.correct,
    );
    for (final entrance in visibleEntrances.skip(1)) {
      expect(
        game.tapLogical(_positionFor(entrance)),
        BathhouseTapOutcome.queued,
      );
    }
    expect(game.pendingInputCount, 6);

    game.update(0.3);
    expect(game.pendingInputCount, 0);
    expect(game.correctCount, 7);
    expect(game.combo, 7);
    expect(game.mistakeCount, 0);
    expect(game.successBurstCount, 7);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('예약 중 오답이 나오면 남은 입력을 비우고 250ms 잠근다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    expect(_tapCurrent(game), BathhouseTapOutcome.correct);
    final wrongEntrance = game.currentGuest.entrance == BathEntrance.mens
        ? BathEntrance.womens
        : BathEntrance.mens;
    expect(
      game.tapLogical(_positionFor(wrongEntrance)),
      BathhouseTapOutcome.queued,
    );
    expect(_tapCurrent(game), BathhouseTapOutcome.queued);
    game.update(0.046);

    expect(game.mistakeCount, 1);
    expect(game.pendingInputCount, 0);
    expect(game.inputLocked, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('예약 입력은 32개까지 받아 초고속 연타를 보존한다', (tester) async {
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    expect(_tapCurrent(game), BathhouseTapOutcome.correct);
    final queuedPosition = _positionFor(game.currentGuest.entrance);
    for (
      var index = 0;
      index < BathhouseSortRules.inputBufferCapacity;
      index++
    ) {
      expect(game.tapLogical(queuedPosition), BathhouseTapOutcome.queued);
    }
    expect(game.pendingInputCount, BathhouseSortRules.inputBufferCapacity);
    expect(game.tapLogical(queuedPosition), BathhouseTapOutcome.ignored);

    game.update(0.801);
    expect(game.pendingInputCount, 0);
    expect(game.correctCount, 1);
    expect(game.mistakeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('중단은 여러 번 호출해도 점수를 제출하지 않는다', (tester) async {
    final results = <GameResult>[];
    final game = BathhouseSortGame(
      countdownDuration: Duration.zero,
      onFinished: results.add,
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    game.interrupt();
    game.interrupt();
    game.update(100);

    expect(game.gamePhase, BathhouseSortPhase.interrupted);
    expect(game.hud.value.phase.name, 'finished');
    expect(results, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Vector2 _positionFor(BathEntrance entrance) =>
    entrance == BathEntrance.mens ? Vector2(80, 590) : Vector2(280, 590);

BathhouseTapOutcome _tapCurrent(BathhouseSortGame game) =>
    game.tapLogical(_positionFor(game.currentGuest.entrance));

Future<void> _waitUntilReady(
  WidgetTester tester,
  BathhouseSortGame game,
) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 100 && !game.isReady; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pump();
  expect(game.isReady, isTrue);
}
