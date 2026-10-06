import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/number_rush/number_rush_game.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await loader.load();
  });

  testWidgets('10 보스 폭발 중에도 11 입력을 계속 받는다', (tester) async {
    final game = NumberRushGame(
      countdownDuration: Duration.zero,
      random: Random(20260815),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await _waitUntilReady(tester, game);

    for (var number = 1; number <= 10; number++) {
      game.tapLogicalPosition(game.logicalCenterForNumberForTesting(number)!);
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(game.nextNumberForTesting, 11);
    expect(game.pressureStageForTesting, 1);
    expect(game.milestoneBurstNumberForTesting, 10);

    await tester.pump(const Duration(milliseconds: 90));
    game.tapLogicalPosition(game.logicalCenterForNumberForTesting(11)!);
    await tester.pump();

    expect(game.nextNumberForTesting, 12);
    expect(game.milestoneBurstNumberForTesting, 10);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('10 보스 폭발이 360x640 화면에 안전하게 표시된다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('number-rush-boss-burst-capture');
    final game = NumberRushGame(
      countdownDuration: Duration.zero,
      random: Random(20260815),
      onFinished: (_) {},
    );
    addTearDown(game.disposeController);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: GameWidget(game: game)),
        ),
      ),
    );
    await _waitUntilReady(tester, game);

    for (var number = 1; number <= 10; number++) {
      game.tapLogicalPosition(game.logicalCenterForNumberForTesting(number)!);
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pump(const Duration(milliseconds: 90));
    game.pauseEngine();
    await tester.pump();

    expect(game.milestoneBurstNumberForTesting, 10);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/number_rush_boss_burst_360x640.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _waitUntilReady(WidgetTester tester, NumberRushGame game) async {
  for (var attempt = 0; attempt < 100 && !game.isReadyForTesting; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(game.isReadyForTesting, isTrue);
}
