import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/games/western_duel/domain/western_duel_opponent.dart';
import 'package:just_one_round/features/games/western_duel/western_duel_game.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await loader.load();
  });

  testWidgets('real Flame renderer fits waiting and firing poses on phone sizes', (
    tester,
  ) async {
    addTearDown(tester.view.reset);

    for (final viewport in const [
      Size(360, 640),
      Size(438, 898),
      Size(430, 932), // iPhone 16 Plus logical viewport
      Size(360, 800),
      Size(640, 976), // exact dimensions of the supplied Simulator screenshot
    ]) {
      tester.view
        ..physicalSize = viewport
        ..devicePixelRatio = 1;
      final captureKey = GlobalKey();
      final game = WesternDuelGame(
        onFinished: (_) {},
        challengeSeed: 2127,
        countdownDuration: Duration.zero,
        enableHaptics: false,
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
      game.pauseEngine();
      expect(game.isLoaded, isTrue);

      final expectedHeight = (360 * viewport.height / viewport.width)
          .clamp(640, 800)
          .toDouble();
      final visibleWorld = game.camera.visibleWorldRect;
      expect(visibleWorld.width, closeTo(360, 0.01));
      expect(visibleWorld.height, closeTo(expectedHeight, 0.01));

      game.setOpponent(
        const WesternDuelOpponent(
          nickname: '렌더 검증 상대',
          reactionMilliseconds: 1500,
          isBot: false,
        ),
      );
      game.update(0.01);
      expect(game.phase, WesternDuelPhase.standoff);
      game.update(1.5);
      expect(game.phase, WesternDuelPhase.standoff);
      await _pumpRuntimeFrame(tester, game);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_${viewport.width.toInt()}x${viewport.height.toInt()}_standoff',
      );
      game.update(8);
      expect(game.phase, WesternDuelPhase.draw);
      await _pumpRuntimeFrame(tester, game);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_${viewport.width.toInt()}x${viewport.height.toInt()}_wait',
      );

      game.tapForTesting(reactionMs: 123);
      game.update(0.21);
      await _pumpRuntimeFrame(tester, game);
      expect(game.playerVisualShotForTesting, isTrue);
      expect(
        WesternDuelGame.playerActionFrameForTesting(0.21),
        WesternDuelGame.playerActionFireFrame,
      );
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_${viewport.width.toInt()}x${viewport.height.toInt()}_shot',
      );

      game.update(0.06);
      await _pumpRuntimeFrame(tester, game);
      expect(WesternDuelGame.playerActionFrameForTesting(0.27), 8);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_${viewport.width.toInt()}x${viewport.height.toInt()}_shot_final',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('full game screen fits iPhone and supplied viewports', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    const attempt = PlayAttempt(
      id: 'western-visual-practice',
      ordinal: 1,
      status: 'practice',
      grantType: 'practice',
      gameId: 'western_duel',
      gameVersion: 1,
    );

    for (final viewport in const [Size(430, 932), Size(640, 976)]) {
      tester.view
        ..physicalSize = viewport
        ..devicePixelRatio = 1;
      final captureKey = GlobalKey();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: RepaintBoundary(
              key: captureKey,
              child: const GameScreen(
                attempt: attempt,
                countdownDuration: Duration.zero,
              ),
            ),
          ),
        ),
      );

      final game =
          tester
                  .widget<GameWidget>(
                    find.byWidgetPredicate((widget) => widget is GameWidget),
                  )
                  .game
              as WesternDuelGame;
      for (
        var i = 0;
        i < 100 && (!game.isLoaded || game.opponent == null);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(game.isLoaded, isTrue);
      expect(
        game.opponent?.isBot,
        isTrue,
      ); // preview-only; no ticket/API request

      game.pauseEngine();
      if (game.phase == WesternDuelPhase.countdown) game.update(4);
      if (game.phase == WesternDuelPhase.standoff) game.update(9);
      expect(game.phase, WesternDuelPhase.draw);
      await _pumpRuntimeFrame(tester, game);
      final viewportLabel =
          '${viewport.width.toInt()}x${viewport.height.toInt()}';
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_full_screen_${viewportLabel}_wait',
      );

      game.tapForTesting(reactionMs: 123);
      game.update(0.21);
      await _pumpRuntimeFrame(tester, game);
      expect(game.playerVisualShotForTesting, isTrue);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_full_screen_${viewportLabel}_shot',
      );
      game.update(0.06);
      await _pumpRuntimeFrame(tester, game);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_full_screen_${viewportLabel}_shot_final',
      );

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('captures the player forward fall and ranked timeout states', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    for (final viewport in const [Size(430, 932), Size(360, 640)]) {
      tester.view
        ..physicalSize = viewport
        ..devicePixelRatio = 1;
      final viewportLabel =
          '${viewport.width.toInt()}x${viewport.height.toInt()}';
      final captureKey = GlobalKey();
      final losingGame = WesternDuelGame(
        onFinished: (_) {},
        challengeSeed: 909,
        countdownDuration: Duration.zero,
        enableHaptics: false,
      );
      addTearDown(losingGame.disposeController);

      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: captureKey,
            child: SizedBox.expand(child: GameWidget(game: losingGame)),
          ),
        ),
      );
      await _waitUntilReady(tester, losingGame);
      losingGame.pauseEngine();
      losingGame.setOpponent(
        const WesternDuelOpponent(
          nickname: '빠른 렌더 상대',
          reactionMilliseconds: 200,
          isBot: false,
        ),
      );
      losingGame.update(0.01);
      losingGame.update(8);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 260)),
      );
      losingGame.update(0.01);
      losingGame.tapForTesting(reactionMs: 500);
      losingGame.update(0.22);
      await _pumpRuntimeFrame(tester, losingGame);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_${viewportLabel}_player_fall_entry',
      );
      losingGame.update(0.48);
      await _pumpRuntimeFrame(tester, losingGame);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_${viewportLabel}_player_fall_kneel',
      );
      losingGame.update(0.48);
      await _pumpRuntimeFrame(tester, losingGame);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_${viewportLabel}_player_fall_final',
      );

      final timeoutGame = WesternDuelGame(
        onFinished: (_) {},
        challengeSeed: 910,
        countdownDuration: Duration.zero,
        enableHaptics: false,
      );
      addTearDown(timeoutGame.disposeController);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: captureKey,
            child: SizedBox.expand(child: GameWidget(game: timeoutGame)),
          ),
        ),
      );
      await _waitUntilReady(tester, timeoutGame);
      timeoutGame.pauseEngine();
      timeoutGame.setOpponent(
        const WesternDuelOpponent(
          nickname: '느린 렌더 상대',
          reactionMilliseconds: 1200,
          isBot: false,
        ),
      );
      timeoutGame.update(0.01);
      timeoutGame.update(8);
      timeoutGame.tapForTesting(reactionMs: 1000);
      timeoutGame.update(0.48);
      await _pumpRuntimeFrame(tester, timeoutGame);
      await _captureIfRequested(
        tester,
        captureKey,
        'western_duel_${viewportLabel}_player_timeout_fall',
      );
      expect(timeoutGame.playerFired, isFalse);
      expect(timeoutGame.forcedTimeoutForTesting, isTrue);
      expect(timeoutGame.playerForwardFallStartedForTesting, isTrue);
      expect(timeoutGame.playerVisualShotForTesting, isFalse);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('captures both victory poses and an unfired false start', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view
      ..physicalSize = const Size(430, 932)
      ..devicePixelRatio = 1;
    final captureKey = GlobalKey();

    Future<WesternDuelGame> startGame(int seed, int opponentMs) async {
      final game = WesternDuelGame(
        onFinished: (_) {},
        challengeSeed: seed,
        countdownDuration: Duration.zero,
        enableHaptics: false,
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
      game.pauseEngine();
      game.setOpponent(
        WesternDuelOpponent(
          nickname: '맥크리',
          reactionMilliseconds: opponentMs,
          isBot: true,
        ),
      );
      game.update(0.01);
      return game;
    }

    final playerWin = await startGame(121, 200);
    playerWin.update(8);
    playerWin.tapForTesting(reactionMs: 100);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 220)),
    );
    playerWin.update(0.01);
    playerWin.update(0.21);
    playerWin.update(0.56);
    playerWin.update(0.2);
    expect(playerWin.winnerCelebrationElapsedForTesting, isNotNull);
    await _pumpRuntimeFrame(tester, playerWin);
    await _captureIfRequested(
      tester,
      captureKey,
      'western_duel_430x932_player_victory',
    );

    final falseStart = await startGame(122, 440);
    expect(falseStart.phase, WesternDuelPhase.standoff);
    falseStart.tapForTesting();
    expect(falseStart.playerFired, isFalse);
    await _pumpRuntimeFrame(tester, falseStart);
    await _captureIfRequested(
      tester,
      captureKey,
      'western_duel_430x932_false_start',
    );
    falseStart.update(0.2);
    falseStart.update(0.21);
    falseStart.update(0.62);
    falseStart.update(0.2);
    expect(falseStart.winnerCelebrationElapsedForTesting, isNotNull);
    await _pumpRuntimeFrame(tester, falseStart);
    await _captureIfRequested(
      tester,
      captureKey,
      'western_duel_430x932_opponent_victory',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpRuntimeFrame(
  WidgetTester tester,
  WesternDuelGame game,
) async {
  game.resumeEngine();
  await tester.pump(const Duration(milliseconds: 16));
  game.pauseEngine();
  await tester.pump();
}

Future<void> _waitUntilReady(WidgetTester tester, WesternDuelGame game) async {
  for (var attempt = 0; attempt < 100 && !game.isReadyForTesting; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(game.isReadyForTesting, isTrue);
}

Future<void> _captureIfRequested(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (Platform.environment['CAPTURE_WESTERN_DUEL_RENDER'] != '1') return;

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        Platform.environment['WESTERN_DUEL_CAPTURE_DIR'] ?? '/tmp',
      )..createSync(recursive: true);
      File(
        '${directory.path}/$name.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
