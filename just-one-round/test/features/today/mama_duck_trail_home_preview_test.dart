import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/presentation/mama_duck_trail_home_preview.dart';

void main() {
  testWidgets('엄마 어디가 홈 프리뷰는 실제 보드 스프라이트 루프를 재생한다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: const SizedBox(
            width: 360,
            height: 460,
            child: MamaDuckTrailHomePreview(),
          ),
        ),
      ),
    );

    for (
      var attempt = 0;
      attempt < 30 &&
          find
              .byKey(const Key('mama-duck-trail-home-animation'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const Key('mama-duck-trail-home-hero')), findsOneWidget);
    expect(
      find.byKey(const Key('mama-duck-trail-home-animation')),
      findsOneWidget,
    );

    if (Platform.environment['CAPTURE_MAMA_DUCK_HOME'] == '1') {
      await tester.pump(const Duration(seconds: 3, milliseconds: 700));
      final boundary =
          captureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final path =
          Platform.environment['MAMA_DUCK_HOME_CAPTURE_PATH'] ??
          '/tmp/mama_duck_trail_home.png';
      File(path).writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    }

    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
