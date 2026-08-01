import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/sausage_dachshund/sausage_dachshund_game.dart';

void main() {
  testWidgets('360x640 실제 런타임이 에셋을 로드하고 렌더링한다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    final game = SausageDachshundGame(
      random: Random(29),
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
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.isLoaded, isTrue);
    for (var tick = 0; tick < 14; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.queueSwipeForTesting(Vector2(0, -30)), isTrue);
    for (var tick = 0; tick < 7; tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    game.pauseEngine();

    expect(find.byKey(captureKey), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (Platform.environment['CAPTURE_SAUSAGE_DACHSHUND'] == '1') {
      final boundary =
          captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final outputPath =
          Platform.environment['SAUSAGE_DACHSHUND_CAPTURE_PATH'] ??
          '/tmp/sausage_dachshund_runtime.png';
      File(outputPath).writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
