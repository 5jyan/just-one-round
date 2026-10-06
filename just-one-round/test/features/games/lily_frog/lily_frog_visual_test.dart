import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/lily_frog/lily_frog_game.dart';
import 'package:just_one_round/features/games/lily_frog/presentation/lily_frog_combo_gauge.dart';
import 'package:just_one_round/features/games/lily_frog/presentation/lily_frog_home_preview.dart';

void main() {
  testWidgets('콤보 게이지는 숫자 아래에서 콤보 색을 쓰고 마지막 15%에 점멸한다', (tester) async {
    const colors = <int, Color>{
      2: Color(0xFF54EFFF),
      11: Color(0xFFFFCF45),
      21: Color(0xFFFF853F),
      41: Color(0xFFFF4ECA),
      71: Color(0xFFB878FF),
    };
    for (final entry in colors.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: LilyFrogComboGauge(remainingPercent: 14, combo: entry.key),
          ),
        ),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .color,
        entry.value,
      );
      expect(
        tester.getSize(find.byKey(const Key('lily-frog-combo-track'))),
        const Size(82, 11),
      );
    }
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.14,
    );
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0.4,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: LilyFrogComboGauge(remainingPercent: 12, combo: 71),
        ),
      ),
    );
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: LilyFrogComboGauge(
            remainingPercent: 80,
            combo: 2,
            compact: true,
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('lily-frog-combo-track'))),
      const Size(66, 9),
    );
  });

  setUpAll(() async {
    final loader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await loader.load();
  });

  testWidgets('실제 게임 장면이 360x640 화면에서 렌더링된다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('lily-frog-runtime-capture');
    final game = LilyFrogGame(
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
    await _pumpUntilLoaded(tester, game);
    await tester.pump(const Duration(milliseconds: 180));
    game.pauseEngine();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/lily_frog_runtime_360x640.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final targetCombo in [2, 10, 11]) {
    testWidgets('$targetCombo콤보의 색과 충격파가 나타난다', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const captureKey = Key('lily-frog-combo-capture');
      final game = LilyFrogGame(
        countdownDuration: Duration.zero,
        random: Random(20260815),
        enableHaptics: false,
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
      await _pumpUntilLoaded(tester, game);
      for (var landing = 1; landing <= targetCombo; landing++) {
        expect(game.launchSafeImmediatelyForPreview(), isTrue);
        for (var tick = 0; tick < 300; tick++) {
          game.update(0.01);
          await tester.pump();
          if (game.comboForTesting == landing &&
              (landing == targetCombo ||
                  game.motionPhaseForTesting == LilyFrogMotionPhase.orbiting)) {
            break;
          }
        }
        expect(game.comboForTesting, landing);
      }
      game.update(0.09);
      await tester.pump();
      expect(game.activeComboEffectsForTesting, greaterThan(0));
      game.pauseEngine();
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(switch (targetCombo) {
          2 => 'goldens/lily_frog_combo_360x640.png',
          10 => 'goldens/lily_frog_combo_10_360x640.png',
          _ => 'goldens/lily_frog_combo_11_360x640.png',
        }),
      );
      game.resumeEngine();
      game.update(0.8);
      await tester.pump();
      expect(game.activeComboEffectsForTesting, 0);
      game.pauseEngine();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('홈 미리보기는 실제 런타임을 비율 그대로 중앙 크롭한다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 462)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('lily-frog-preview-capture');
    await tester.pumpWidget(
      const MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(child: LilyFrogHomePreview()),
        ),
      ),
    );
    for (var attempt = 0; attempt < 50; attempt++) {
      if (find.byType(GameWidget).evaluate().isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('lily-frog-home-runtime-preview')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is GameWidget),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/lily_frog_home_runtime_360x462.png'),
    );

    expect(find.byKey(const Key('lily-frog-runtime-game-0')), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(find.byKey(const Key('lily-frog-runtime-game-1')), findsOneWidget);
  });

  testWidgets('설명 이미지는 353x360 슬롯에 전체 게임 화면을 사용한다', (tester) async {
    tester.view
      ..physicalSize = const Size(353, 360)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('lily-frog-guide-capture');
    await tester.pumpWidget(
      const MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: SizedBox.expand(
            child: LilyFrogRuntimePreview(
              mode: LilyFrogRuntimePreviewMode.tangent,
            ),
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 50; attempt++) {
      if (find
          .byKey(const Key('lily-frog-runtime-ready'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('lily-frog-guide-runtime-preview')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is GameWidget),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/lily_frog_guide_353x360.png'),
    );
  });
}

Future<void> _pumpUntilLoaded(WidgetTester tester, LilyFrogGame game) async {
  for (var attempt = 0; attempt < 30 && !game.isLoaded; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(game.isLoaded, isTrue);
}
