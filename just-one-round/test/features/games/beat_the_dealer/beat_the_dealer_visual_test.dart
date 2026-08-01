import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/beat_the_dealer/beat_the_dealer_game.dart';

void main() {
  testWidgets('betting scene fits the real 360x640 runtime', (tester) async {
    final fontLoader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await fontLoader.load();
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const captureKey = Key('beat-dealer-runtime-capture');
    final game = BeatTheDealerGame(
      attemptOrdinal: 1,
      seedInstant: DateTime.utc(2026, 7, 30),
      countdownDuration: Duration.zero,
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
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);
    await tester.pump(const Duration(seconds: 1));
    game.pauseEngine();
    await tester.pump();

    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_BEAT_THE_DEALER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/beat_the_dealer/'
          'trump_v3/qc/runtime-gameplay-360x640.png',
        ),
      );
      game.resumeEngine();
      game.tapLogicalPosition(Vector2(70, 515));
      await tester.pump();
      game.pauseEngine();
      await tester.pump();
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/beat_the_dealer/'
          'trump_v3/qc/runtime-minimum-bet-message-360x640.png',
        ),
      );
      game.resumeEngine();
      for (var tap = 0; tap < 10; tap++) {
        game.tapLogicalPosition(Vector2(290, 515));
      }
      await tester.pump();
      game.pauseEngine();
      await tester.pump();
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/beat_the_dealer/'
          'trump_v3/qc/runtime-maximum-bet-message-360x640.png',
        ),
      );
      game.resumeEngine();
      game.tapLogicalPosition(Vector2(180, 580));
      await tester.pump();
      game.pauseEngine();
      await tester.pump();
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/beat_the_dealer/'
          'trump_v3/qc/runtime-player-turn-360x640.png',
        ),
      );
      game.resumeEngine();
      game.tapLogicalPosition(Vector2(80, 580));
      await tester.pump();
      if (game.gamePhase == BeatTheDealerPhase.playerTurn) {
        game.tapLogicalPosition(Vector2(260, 580));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 800));
      game.pauseEngine();
      await tester.pump();
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/beat_the_dealer/'
          'trump_v3/qc/runtime-dealer-three-cards-360x640.png',
        ),
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
