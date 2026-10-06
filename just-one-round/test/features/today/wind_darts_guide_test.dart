import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/theme/app_theme.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  late ThemeData qcTheme;

  setUpAll(() async {
    final loader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await loader.load();

    const systemKoreanPath = '/System/Library/Fonts/AppleSDGothicNeo.ttc';
    final systemKoreanFile = File(systemKoreanPath);
    if (systemKoreanFile.existsSync()) {
      final bytes = await systemKoreanFile.readAsBytes();
      final koreanLoader = FontLoader('AppleKorean')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await koreanLoader.load();
    }
    const materialIconsPath =
        '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf';
    final materialIconsFile = File(materialIconsPath);
    if (materialIconsFile.existsSync()) {
      final bytes = await materialIconsFile.readAsBytes();
      final materialIconsLoader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await materialIconsLoader.load();
    }
    final baseTheme = AppTheme.dark;
    qcTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(fontFamily: 'AppleKorean'),
    );
  });

  testWidgets(
    'wind darts home and every guide page fit the real sheet at two phone sizes',
    (tester) async {
      const sizes = [Size(360, 640), Size(430, 932)];
      final output = Directory('/tmp/dart-guide-qc')
        ..createSync(recursive: true);
      final originalPhysicalSize = tester.view.physicalSize;
      final originalDevicePixelRatio = tester.view.devicePixelRatio;
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        tester.view
          ..physicalSize = originalPhysicalSize
          ..devicePixelRatio = originalDevicePixelRatio;
      });

      for (final size in sizes) {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = size;
        await tester.binding.setSurfaceSize(size);
        final boundaryKey = ValueKey('wind-darts-qc-${size.width}');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dailyGameRepositoryProvider.overrideWithValue(
                PreviewDailyGameRepository(initialGameId: 'wind_darts'),
              ),
            ],
            child: MaterialApp(
              theme: qcTheme,
              home: const TodayScreen(),
              builder: (context, child) => RepaintBoundary(
                key: boundaryKey,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await _pumpUntilPreviewReady(tester);
        final rootMediaQuery = tester.widget<MediaQuery>(
          find.byType(MediaQuery).first,
        );
        expect(rootMediaQuery.data.size, size);
        expect(find.text('오늘의 게임'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          find.byKey(boundaryKey),
          File(
            '${output.path}/home_${size.width.toInt()}x${size.height.toInt()}.png',
          ),
        );

        final guideButton = find.byKey(const Key('game-guide-button'));
        await tester.ensureVisible(guideButton);
        await tester.tap(guideButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await _pumpGuideAssets(tester);
        expect(find.text('HOW TO PLAY · 1/4'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('guide-previous-button')),
              )
              .onPressed,
          isNull,
        );

        // Exercise horizontal swipe navigation before using the buttons.
        await tester.drag(
          find.byKey(const Key('game-guide-pages')),
          const Offset(-280, 0),
        );
        await tester.pump(const Duration(milliseconds: 320));
        expect(find.text('HOW TO PLAY · 2/4'), findsOneWidget);
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('guide-previous-button')),
            )
            .onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 320));
        await _pumpGuideAssets(tester);
        expect(find.text('HOW TO PLAY · 1/4'), findsOneWidget);

        for (var page = 1; page <= 4; page++) {
          expect(find.text('HOW TO PLAY · $page/4'), findsOneWidget);
          expect(find.byKey(Key('guide-page-dot-${page - 1}')), findsOneWidget);
          expect(find.byKey(const Key('guide-next-button')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            find.byKey(boundaryKey),
            File(
              '${output.path}/guide_${size.width.toInt()}x${size.height.toInt()}_page$page.png',
            ),
          );

          if (size.height <= 640) {
            final pageScrollable = find.byType(Scrollable).last;
            await tester.drag(pageScrollable, const Offset(0, -240));
            await tester.pump();
            expect(tester.takeException(), isNull);
            if (page == 4) {
              expect(find.textContaining('백그라운드'), findsOneWidget);
            }
            await _capture(
              tester,
              find.byKey(boundaryKey),
              File(
                '${output.path}/guide_${size.width.toInt()}x${size.height.toInt()}_page${page}_bottom.png',
              ),
            );
          }

          if (page == 4) break;
          tester
              .widget<PixelButton>(find.byKey(const Key('guide-next-button')))
              .onPressed!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 320));
          await _pumpGuideAssets(tester);
        }

        expect(find.text('설명 끝'), findsOneWidget);
        tester
            .widget<PixelButton>(find.byKey(const Key('guide-next-button')))
            .onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byKey(const Key('game-guide-pages')), findsNothing);
      }
    },
  );
}

Future<void> _pumpUntilPreviewReady(WidgetTester tester) async {
  final ready = find.byKey(const ValueKey('wind-darts-preview-ready'));
  for (var attempt = 0; attempt < 100 && ready.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpGuideAssets(WidgetTester tester) async {
  final ready = find.byKey(const ValueKey('wind-darts-preview-ready'));
  for (
    var attempt = 0;
    attempt < 100 && ready.evaluate().length < 2;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _capture(WidgetTester tester, Finder finder, File file) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Could not encode ${file.path}');
      }
      file.writeAsBytesSync(bytes.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}
