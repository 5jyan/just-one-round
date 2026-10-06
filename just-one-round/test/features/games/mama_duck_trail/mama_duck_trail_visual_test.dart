import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/mama_duck_trail/domain/mama_duck_trail_rules.dart';
import 'package:just_one_round/features/games/mama_duck_trail/mama_duck_trail_game.dart';

void main() {
  testWidgets('360x640 실제 런타임이 에셋을 로드하고 렌더링한다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    final game = MamaDuckTrailGame(
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
    await tester.pump();
    for (var attempt = 0; attempt < 20 && !game.isLoaded; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.isLoaded, isTrue);
    await tester.pump(const Duration(milliseconds: 900));
    game.pauseEngine();

    final visibleRect = game.camera.visibleWorldRect;
    expect(visibleRect.left, closeTo(0, 0.01));
    expect(visibleRect.top, closeTo(0, 0.01));
    expect(visibleRect.width, closeTo(360, 0.01));
    expect(visibleRect.height, closeTo(640, 0.01));
    expect(find.byKey(captureKey), findsOneWidget);
    expect(tester.takeException(), isNull);

    if (Platform.environment['CAPTURE_MAMA_DUCK'] == '1') {
      final boundary =
          captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final outputPath =
          Platform.environment['MAMA_DUCK_CAPTURE_PATH'] ??
          '/tmp/mama_duck_trail_runtime.png';
      File(outputPath).writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('긴 아이폰 화면은 보드를 자르지 않고 위아래 배경을 추가로 보여준다', (tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final game = MamaDuckTrailGame(
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
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(game.isLoaded, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    game.pauseEngine();

    final visibleRect = game.camera.visibleWorldRect;
    expect(visibleRect.width, closeTo(360, 0.01));
    expect(visibleRect.height, greaterThan(640));
    expect(visibleRect.top, greaterThanOrEqualTo(-100));
    expect(visibleRect.top, lessThan(0));
    expect(visibleRect.bottom, greaterThan(640));
    expect(visibleRect.bottom, lessThanOrEqualTo(740));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('3콤보에서 모든 경로 칸의 새끼가 엄마 앞에 모여 기뻐한다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    final game = MamaDuckTrailGame(
      random: Random(37),
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

    for (var round = 0; round < 3; round++) {
      await _advanceToRecall(tester, game);
      final path = game.pathForTesting;
      game.beginLogicalDragForTesting(game.cellCenterForTesting(path.first));
      for (final cell in path.skip(1)) {
        game.updateLogicalDragForTesting(game.cellCenterForTesting(cell));
      }
    }
    await tester.pump(const Duration(milliseconds: 700));
    game.pauseEngine();
    await tester.pump();

    expect(game.rescuedDuckCountForTesting, 3);
    expect(game.visibleRescuedDuckCountForTesting, 3);
    expect(game.feverTierForTesting, MamaDuckFeverTier.goldenTrail);
    expect(
      game.successDuckCentersForTesting,
      hasLength(game.currentPathLengthForTesting - 1),
    );
    expect(game.isMotherCheeringForTesting, isTrue);
    expect(
      (game.successDuckCentersForTesting.first -
              game.successMotherCenterForTesting)
          .length,
      closeTo(72, 0.01),
    );
    expect(tester.takeException(), isNull);

    if (Platform.environment['CAPTURE_MAMA_DUCK_FEVER'] == '1') {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../../../../assets/source/imagegen/mama_duck_trail/'
          'duckling_yellow_varieties_v3/qc/runtime_full_path_success.png',
        ),
      );
    }
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
