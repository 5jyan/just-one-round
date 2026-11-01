// This screenshot generator is run explicitly with `flutter test`; keep its
// test-only asset and preference setup available outside normal discovery.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/theme/app_theme.dart';
import 'package:just_one_round/features/games/presentation/game_presentation_registry.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_preview.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ThemeData qcTheme;

  setUpAll(() async {
    final galmuri = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await galmuri.load();

    const koreanPath = '/System/Library/Fonts/AppleSDGothicNeo.ttc';
    final koreanFile = File(koreanPath);
    if (koreanFile.existsSync()) {
      final koreanBytes = await koreanFile.readAsBytes();
      final korean = FontLoader('AppleKorean')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(koreanBytes)));
      await korean.load();
    }
    qcTheme = AppTheme.dark.copyWith(
      textTheme: AppTheme.dark.textTheme.apply(fontFamily: 'AppleKorean'),
    );
  });

  testWidgets('capture after-fix contact states and all guide pages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final output = Directory('artifacts/homebound_run/preview_repair/final')
      ..createSync(recursive: true);
    await tester.runAsync(TempleRunPreview.preloadAssets);

    for (final contact in const [
      (
        name: 'home_pallet_contact_after_fix.png',
        scene: TempleRunPreviewScene.home,
        frame: 36,
      ),
      (
        name: 'home_gap_contact_after_fix.png',
        scene: TempleRunPreviewScene.home,
        frame: 64,
      ),
      (
        name: 'home_shutter_contact_after_fix.png',
        scene: TempleRunPreviewScene.home,
        frame: 88,
      ),
      (
        name: 'narrow_path_midpoint_after_fix.png',
        scene: TempleRunPreviewScene.home,
        frame: 18,
      ),
      (
        name: 'maneuvers_pallet_contact_after_fix.png',
        scene: TempleRunPreviewScene.maneuvers,
        frame: 16,
      ),
      (
        name: 'maneuvers_gap_contact_after_fix.png',
        scene: TempleRunPreviewScene.maneuvers,
        frame: 44,
      ),
      (
        name: 'maneuvers_shutter_contact_after_fix.png',
        scene: TempleRunPreviewScene.maneuvers,
        frame: 72,
      ),
      (
        name: 'controls_turn_reserved_after_fix.png',
        scene: TempleRunPreviewScene.controls,
        frame: 7,
      ),
      (
        name: 'corner_turn_crossed_after_fix.png',
        scene: TempleRunPreviewScene.corner,
        frame: 55,
      ),
      (
        name: 'items_shield_active_after_fix.png',
        scene: TempleRunPreviewScene.items,
        frame: 64,
      ),
      (
        name: 'items_boost_active_after_fix.png',
        scene: TempleRunPreviewScene.items,
        frame: 89,
      ),
    ]) {
      await _capturePreview(
        tester,
        qcTheme,
        output,
        name: contact.name,
        scene: contact.scene,
        frame: contact.frame,
      );
    }

    for (final viewport in const [
      (name: 'short', size: Size(393, 700)),
      (name: 'tall', size: Size(393, 852)),
    ]) {
      await tester.binding.setSurfaceSize(viewport.size);
      final screenKey = ValueKey('preview-repair-${viewport.name}-screen');
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey('preview-repair-${viewport.name}-provider'),
          overrides: [
            dailyGameRepositoryProvider.overrideWithValue(
              PreviewDailyGameRepository(initialGameId: 'temple_run'),
            ),
          ],
          child: MaterialApp(
            theme: qcTheme,
            home: const TodayScreen(),
            builder: (context, child) => RepaintBoundary(
              key: screenKey,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await _pumpUntilReady(tester);
      await _capture(
        tester,
        find.byKey(screenKey),
        File('${output.path}/home_${viewport.name}_after_fix.png'),
      );

      await tester.ensureVisible(find.byKey(const Key('game-guide-button')));
      await tester.tap(find.byKey(const Key('game-guide-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('HOW TO PLAY · 5/5'), findsNothing);
      await _pumpUntilReady(tester);
      for (var page = 0; page < 5; page++) {
        expect(find.text('HOW TO PLAY · ${page + 1}/5'), findsOneWidget);
        await _capture(
          tester,
          find.byKey(screenKey),
          File(
            '${output.path}/guide_${viewport.name}_page${page + 1}_after_fix.png',
          ),
        );
        await _verifyGuideDetailScroll(tester, page);
        if (page < 4) {
          await tester.tap(find.byKey(const Key('guide-next-button')));
          await tester.pump(const Duration(milliseconds: 360));
          await tester.pump(const Duration(milliseconds: 80));
          await _pumpUntilReady(tester);
        }
      }
      expect(tester.takeException(), isNull, reason: viewport.name);
      await tester.tap(find.byKey(const Key('guide-next-button')));
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> _verifyGuideDetailScroll(
  WidgetTester tester,
  int pageIndex,
) async {
  final page = GamePresentationRegistry.forId(
    'temple_run',
  ).guidePages[pageIndex];
  final detail = find.text(page.detail);
  expect(detail, findsOneWidget);
  await tester.ensureVisible(detail);
  await tester.pump();

  final viewport = tester.getRect(find.byKey(const Key('game-guide-pages')));
  final detailRect = tester.getRect(detail);
  final footer = tester.getRect(find.byKey(const Key('guide-next-button')));
  expect(detailRect.top, greaterThanOrEqualTo(viewport.top));
  expect(detailRect.bottom, lessThanOrEqualTo(viewport.bottom));
  expect(viewport.bottom, lessThanOrEqualTo(footer.top));

  // Return to the top so moving to the next page starts with its preview.
  final pageScroll = find.descendant(
    of: find.byKey(const Key('game-guide-pages')),
    matching: find.byType(SingleChildScrollView),
  );
  await tester.drag(pageScroll.first, const Offset(0, 1000));
  await tester.pump();
}

Future<void> _capturePreview(
  WidgetTester tester,
  ThemeData theme,
  Directory output, {
  required String name,
  required TempleRunPreviewScene scene,
  required int frame,
}) async {
  const size = Size(393, 360);
  await tester.binding.setSurfaceSize(size);
  final boundaryKey = ValueKey('preview-repair-$name');
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: TempleRunPreview(
            scene: scene,
            animate: false,
            initialFrame: frame,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.byKey(const Key('temple-run-preview-ready')), findsOneWidget);
  await _capture(tester, find.byKey(boundaryKey), File('${output.path}/$name'));
}

Future<void> _pumpUntilReady(WidgetTester tester) async {
  final ready = find.byKey(const Key('temple-run-preview-ready'));
  for (var attempt = 0; attempt < 100 && ready.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 100));
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
