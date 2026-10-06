import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/theme/app_theme.dart';
import 'package:just_one_round/features/games/western_duel/presentation/western_duel_presentation.dart';
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
    qcTheme = AppTheme.dark.copyWith(
      textTheme: AppTheme.dark.textTheme.apply(fontFamily: 'AppleKorean'),
    );
  });

  testWidgets('western duel home and all three guide pages fit both phone sheets', (
    tester,
  ) async {
    const sizes = [Size(360, 640), Size(430, 932)];
    final output = Directory('/tmp/western-guide-qc')
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
      final boundaryKey = ValueKey('western-duel-qc-${size.width}');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dailyGameRepositoryProvider.overrideWithValue(
              PreviewDailyGameRepository(initialGameId: 'western_duel'),
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
      await _pumpUntilHomeReady(tester);
      await _precacheWesternAssets(tester);
      await _pumpUntilImagesReady(tester);
      await tester.pump();
      expect(find.text('오늘의 게임'), findsOneWidget);
      expect(
        find.byKey(const Key('western-duel-preview-clip')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        find.byKey(boundaryKey),
        File(
          '${output.path}/home_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );

      final guideButton = find.byKey(const Key('game-guide-button'));
      // The tall cohesive preview can place this action below a short sheet;
      // invoke the same button callback so the modal is tested at its real
      // viewport instead of scrolling the home page first.
      final guideButtonControl = find.descendant(
        of: guideButton,
        matching: find.byType(OutlinedButton),
      );
      tester.widget<OutlinedButton>(guideButtonControl).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('HOW TO PLAY · 1/3'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('guide-previous-button')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('western-duel-preview-clip')), findsWidgets);

      // Verify swipe navigation and the matching previous-button state.
      await tester.drag(
        find.byKey(const Key('game-guide-pages')),
        const Offset(-280, 0),
      );
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.text('HOW TO PLAY · 2/3'), findsOneWidget);
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('guide-previous-button')),
          )
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.text('HOW TO PLAY · 1/3'), findsOneWidget);

      for (
        var page = 1;
        page <= westernDuelPresentation.guidePages.length;
        page++
      ) {
        expect(find.text('HOW TO PLAY · $page/3'), findsOneWidget);
        expect(find.byKey(Key('guide-page-dot-${page - 1}')), findsOneWidget);
        expect(
          find.byKey(const Key('western-duel-preview-clip')),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
        await _pumpUntilImagesReady(tester);
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
          await _pumpUntilImagesReady(tester);
          await _capture(
            tester,
            find.byKey(boundaryKey),
            File(
              '${output.path}/guide_${size.width.toInt()}x${size.height.toInt()}_page${page}_bottom.png',
            ),
          );
        }

        if (page == westernDuelPresentation.guidePages.length) break;
        tester
            .widget<PixelButton>(find.byKey(const Key('guide-next-button')))
            .onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 320));
      }

      expect(find.text('설명 끝'), findsOneWidget);
      tester
          .widget<PixelButton>(find.byKey(const Key('guide-next-button')))
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('game-guide-pages')), findsNothing);
    }
  });
}

Future<void> _pumpUntilHomeReady(WidgetTester tester) async {
  final ready = find.byKey(const Key('western-duel-preview-clip'));
  for (var attempt = 0; attempt < 100 && ready.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _precacheWesternAssets(WidgetTester tester) async {
  final assets = <String>[
    'assets/images/western_duel/background/saloon_day_180x480.png',
    'assets/images/western_duel/first_person/player_detail_action_v11/sheet-transparent.png',
    'assets/images/western_duel/first_person/player_detail_idle_v11/sheet-transparent.png',
    for (var frame = 1; frame <= 4; frame++)
      'assets/images/western_duel/first_person/opponent_idle_close/frame_${frame.toString().padLeft(2, '0')}.png',
    for (var frame = 1; frame <= 8; frame++)
      'assets/images/western_duel/first_person/opponent_draw_fire_close/frame_${frame.toString().padLeft(2, '0')}.png',
    'assets/images/western_duel/first_person/opponent_hit_fall_close/frame_06.png',
    'assets/images/western_duel/fx/muzzle_flash/frame_04.png',
  ];
  final context = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final asset in assets) {
      await precacheImage(AssetImage(asset), context);
    }
  });
}

Future<void> _pumpUntilImagesReady(WidgetTester tester) async {
  final imageCache = PaintingBinding.instance.imageCache;
  for (
    var attempt = 0;
    attempt < 100 && imageCache.pendingImageCount > 0;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, Finder finder, File file) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not encode ${file.path}');
      file.writeAsBytesSync(bytes.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}
