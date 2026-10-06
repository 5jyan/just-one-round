import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/games/ramen_timer/presentation/ramen_timer_preview.dart';
import 'package:just_one_round/features/games/ramen_timer/ramen_timer_game.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await loader.load();
  });

  testWidgets('hidden clock scene fits the short 360x640 runtime', (
    tester,
  ) async {
    await _renderRuntime(
      tester,
      size: const Size(360, 640),
      captureName: 'runtime-hidden-360x640.png',
      arrange: (clock, game) {
        clock.setMilliseconds(9800);
      },
    );
  });

  testWidgets('12.5 seconds stays hidden after tap feedback expires', (
    tester,
  ) async {
    await _renderRuntime(
      tester,
      size: const Size(360, 640),
      captureName: 'runtime-no-automatic-peek-360x640.png',
      arrange: (clock, game) {
        clock.setMilliseconds(10000);
        game.triggerPrimaryAction();
        game.update(2.01);
        clock.setMilliseconds(12500);
      },
    );
  });

  testWidgets('one checkpoint scene fits a tall 430x932 runtime', (
    tester,
  ) async {
    await _renderRuntime(
      tester,
      size: const Size(430, 932),
      captureName: 'runtime-checkpoint-430x932.png',
      arrange: (clock, game) {
        clock.setMilliseconds(10020);
        game.triggerPrimaryAction();
      },
    );
  });

  testWidgets('three checkpoint errors are visible before ranking', (
    tester,
  ) async {
    await _renderRuntime(
      tester,
      size: const Size(360, 640),
      captureName: 'runtime-result-360x640.png',
      arrange: (clock, game) {
        for (final milliseconds in [9820, 20310, 29900]) {
          clock.setMilliseconds(milliseconds);
          game.triggerPrimaryAction();
        }
      },
      settle: const Duration(milliseconds: 2200),
    );
  });

  testWidgets('real game screen keeps HUD and pointer-down button readable', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RepaintBoundary(
            key: captureKey,
            child: const GameScreen(
              attempt: PlayAttempt(
                id: 'ramen-timer-visual-practice',
                ordinal: 1,
                status: 'practice',
                grantType: 'practice_ad',
                gameId: 'ramen_timer',
                gameVersion: 4,
                gameDurationSeconds: 45,
              ),
              countdownDuration: Duration.zero,
            ),
          ),
        ),
      ),
    );
    final message = find.byKey(const Key('ramen-timer-hud-message'));
    for (
      var attempt = 0;
      attempt < 30 && message.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(message, findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3300)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const Key('ramen-timer-action-button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('ramen-timer-action-button')),
        matching: find.text('10초 · 파 넣기'),
      ),
      findsOneWidget,
    );
    expect(find.text('다음 목표 · 10초'), findsNothing);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_RAMEN_TIMER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ramen_timer/qc/'
          'game-screen-hidden-360x640.png',
        ),
      );
    }
  });

  testWidgets(
    'guide artwork keeps each rule visible in its real 393x268 slot',
    (tester) async {
      tester.view
        ..physicalSize = const Size(393, 268)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final scene in const [
        RamenTimerPreviewScene.calibration,
        RamenTimerPreviewScene.checkpoints,
        RamenTimerPreviewScene.result,
      ]) {
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: captureKey,
              child: SizedBox.expand(
                child: RamenTimerPreview(scene: scene, animate: false),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: scene.name);
        if (Platform.environment['CAPTURE_RAMEN_TIMER'] == '1') {
          await expectLater(
            find.byKey(captureKey),
            matchesGoldenFile(
              '../../../../assets/source/imagegen/ramen_timer/qc/'
              'guide-${scene.name}-393x268.png',
            ),
          );
        }
      }
    },
  );

  testWidgets('home preview shows only the covered first target', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 460)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: const SizedBox.expand(
            child: RamenTimerPreview(
              scene: RamenTimerPreviewScene.home,
              animate: false,
              initialFrame: 41,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('ramen-timer-preview-demo-label')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ramen-timer-preview-result')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('ramen-timer-preview-demo-button')),
        matching: find.text('30초·뚜껑 열기'),
      ),
      findsOneWidget,
    );
    expect(find.text('??.??초'), findsOneWidget);
    expect(find.text('+0.31초'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_RAMEN_TIMER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/ramen_timer/qc/'
          'home-preview-first-target-360x460.png',
        ),
      );
    }
  });
}

Future<void> _renderRuntime(
  WidgetTester tester, {
  required Size size,
  required String captureName,
  required void Function(_VisualRamenTimerClock, RamenTimerGame) arrange,
  Duration settle = const Duration(milliseconds: 100),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final captureKey = GlobalKey();
  final clock = _VisualRamenTimerClock();
  final game = RamenTimerGame(
    countdownDuration: Duration.zero,
    clock: clock,
    challengeSeed: 20260808,
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
  await _waitUntilLoaded(tester, game);
  arrange(clock, game);
  await tester.pump();
  await tester.pump(settle);
  game.pauseEngine();
  await tester.pump();

  expect(tester.takeException(), isNull);
  if (Platform.environment['CAPTURE_RAMEN_TIMER'] == '1') {
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile(
        '../../../../assets/source/imagegen/ramen_timer/qc/$captureName',
      ),
    );
  }
}

Future<void> _waitUntilLoaded(WidgetTester tester, RamenTimerGame game) async {
  for (var attempt = 0; attempt < 30 && !game.assetsReady; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(game.assetsReady, isTrue);
}

final class _VisualRamenTimerClock implements RamenTimerClock {
  Duration _elapsed = Duration.zero;
  var _isRunning = false;

  @override
  Duration get elapsed => _elapsed;

  @override
  bool get isRunning => _isRunning;

  void setMilliseconds(int value) {
    _elapsed = Duration(milliseconds: value);
  }

  @override
  void start() => _isRunning = true;

  @override
  void stop() => _isRunning = false;
}
