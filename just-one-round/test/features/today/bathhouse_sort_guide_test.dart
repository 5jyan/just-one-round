import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Galmuri')
      ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
    await loader.load();
  });

  testWidgets('남탕 여탕 홈은 다른 게임과 같은 카드 경계를 지킨다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<(Rect, Rect, Rect)> renderHome({
      required String gameId,
      required Key previewKey,
      required String title,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey('home-$gameId'),
          overrides: [
            dailyGameRepositoryProvider.overrideWithValue(
              PreviewDailyGameRepository(initialGameId: gameId),
            ),
          ],
          child: const MaterialApp(home: TodayScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      return (
        tester.getRect(find.text('오늘의 게임')),
        tester.getRect(find.byKey(previewKey)),
        tester.getRect(find.text(title)),
      );
    }

    final bathhouse = await renderHome(
      gameId: 'bathhouse_sort',
      previewKey: const Key('bathhouse-sort-preview-clip'),
      title: '남탕! 여탕!',
    );
    expect(bathhouse.$1.bottom, lessThan(bathhouse.$2.top));
    expect(bathhouse.$2.bottom, lessThan(bathhouse.$3.top));
    expect(
      find.byKey(const Key('bathhouse-sort-preview-clip')),
      findsOneWidget,
    );

    final numberRush = await renderHome(
      gameId: 'number_rush',
      previewKey: const Key('number-rush-home-hero'),
      title: '탭50',
    );
    expect(bathhouse.$2.top, closeTo(numberRush.$2.top, 1));
    expect(bathhouse.$2.height, closeTo(numberRush.$2.height, 1));
    expect(bathhouse.$3.top, closeTo(numberRush.$3.top, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('393x852 실제 홈에서 미리보기는 제목과 설명 영역을 침범하지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const captureKey = Key('bathhouse-sort-home-screen-capture');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            PreviewDailyGameRepository(initialGameId: 'bathhouse_sort'),
          ),
        ],
        child: const MaterialApp(
          home: RepaintBoundary(key: captureKey, child: TodayScreen()),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 100 &&
          find
              .byKey(const Key('bathhouse-sort-preview-ready'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/bathhouse_sort_home_393x852.png'),
    );
  });

  testWidgets('남탕 여탕 설명서는 성별·동물 도감·시간 변화·콤보를 네 페이지로 안내한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            PreviewDailyGameRepository(initialGameId: 'bathhouse_sort'),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('남탕! 여탕!'), findsOneWidget);
    expect(find.byKey(const Key('bathhouse-sort-preview')), findsOneWidget);
    final homePreviewSize = tester.getSize(
      find.byKey(const Key('bathhouse-sort-preview')),
    );
    expect(homePreviewSize.height, lessThan(470));
    expect(homePreviewSize.width / homePreviewSize.height, closeTo(0.78, 0.01));
    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.tap(guideButton);
    await tester.pump(const Duration(milliseconds: 500));

    final previous = tester.widget<OutlinedButton>(
      find.byKey(const Key('guide-previous-button')),
    );
    expect(previous.onPressed, isNull);
    final previewSizes = find
        .byKey(const Key('bathhouse-sort-preview'))
        .evaluate()
        .map((element) => (element.renderObject! as RenderBox).size);
    expect(previewSizes.any((size) => size.height == 360), isTrue);

    const pages = [
      ('남자는 남탕, 여자는 여탕', '순서대로 예약'),
      ('동물과 옷 색을 기억하세요', '남자는 파란 옷'),
      ('시간마다 동물이 달라져요', '15·30·45초'),
      ('정확한 콤보로 고득점', '점수 없이 판이 소진'),
    ];
    for (var index = 0; index < pages.length; index++) {
      expect(find.text('HOW TO PLAY · ${index + 1}/4'), findsOneWidget);
      expect(find.text(pages[index].$1), findsOneWidget);
      expect(find.textContaining(pages[index].$2), findsOneWidget);
      expect(find.byKey(const Key('bathhouse-sort-preview')), findsWidgets);
      expect(tester.takeException(), isNull);
      if (index < pages.length - 1) {
        final next = find.byKey(const Key('guide-next-button'));
        tester.widget<PixelButton>(next).onPressed!();
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }
    }
    expect(find.text('설명 끝'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 5000));
    expect(tester.takeException(), isNull);
  });
}
