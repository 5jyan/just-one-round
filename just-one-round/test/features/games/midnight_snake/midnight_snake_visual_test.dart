import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/midnight_snake/midnight_snake_game.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

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

  testWidgets('real GameScreen keeps Snake controls above the safe bottom edge', (
    tester,
  ) async {
    for (final viewport in const [
      Size(320, 568),
      Size(360, 640),
      Size(430, 932),
    ]) {
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
                attempt: PlayAttempt(
                  id: 'midnight-snake-safe-area-practice',
                  ordinal: 1,
                  status: 'practice',
                  grantType: 'practice_ad',
                  gameId: 'midnight_snake',
                  gameVersion: 2,
                  gameDurationSeconds: 300,
                ),
                countdownDuration: Duration.zero,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pump();

      expect(find.text('야식을 먹고 몸과 벽을 피하세요!'), findsNothing);
      expect(tester.takeException(), isNull);

      final fitScale = min(
        viewport.width / MidnightSnakeGame.logicalSize.x,
        viewport.height / MidnightSnakeGame.logicalSize.y,
      );
      for (final button in MidnightSnakeGame.controlButtonRects) {
        expect(button.shortestSide * fitScale, greaterThanOrEqualTo(44));
        expect(
          MidnightSnakeGame.controlBarRect.contains(button.topLeft),
          isTrue,
        );
        expect(
          MidnightSnakeGame.controlBarRect.contains(button.bottomRight),
          isTrue,
        );
      }
      for (final button in MidnightSnakeGame.controlVisualRects) {
        expect(
          MidnightSnakeGame.controlBarRect.contains(button.topLeft),
          isTrue,
        );
        expect(
          MidnightSnakeGame.controlBarRect.contains(button.bottomRight),
          isTrue,
        );
      }

      if (Platform.environment['CAPTURE_MIDNIGHT_SNAKE_SCREEN'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final path =
              Platform.environment['MIDNIGHT_SNAKE_SCREEN_CAPTURE_DIR'] ??
              '/tmp';
          final file = File(
            '$path/midnight_snake_game_screen_${viewport.width.toInt()}x${viewport.height.toInt()}.png',
          );
          file.writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.reset();
  });
}
