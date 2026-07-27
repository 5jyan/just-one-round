import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

void main() {
  testWidgets('사과게임 설명서는 실제 규칙을 다섯 페이지로 안내한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAppleHome(tester);
    await _openGuide(tester);

    expect(find.text('HOW TO PLAY · 1/5'), findsOneWidget);
    expect(find.text('보드 안에서 시작해 드래그'), findsOneWidget);
    expect(find.textContaining('직사각형 안의 사과가 모두 선택'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('guide-previous-button')),
          )
          .onPressed,
      isNull,
    );
    for (var index = 0; index < 5; index++) {
      expect(find.byKey(Key('guide-page-dot-$index')), findsOneWidget);
    }
    expect(
      tester.getSize(find.byKey(const Key('apple-drag-guide-sprite'))),
      const Size(246, 176),
    );
    final dragSheet = tester.widget<Image>(
      find.byKey(const Key('apple-drag-guide-sheet')),
    );
    expect(dragSheet.width, 1968);
    expect(dragSheet.height, 176);
    expect(dragSheet.filterQuality, FilterQuality.none);
    expect(
      (dragSheet.image as AssetImage).assetName,
      'assets/images/apple_game_v2/guide_drag_sprite_sheet.png',
    );
    final initialFrame = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'apple-drag-guide-frame-',
          ),
    );
    expect(initialFrame, findsOneWidget);
    final initialFrameKey = tester.widget<Positioned>(initialFrame).key;
    await tester.pump(const Duration(milliseconds: 175));
    expect(tester.widget<Positioned>(initialFrame).key, isNot(initialFrameKey));

    await tester.tap(find.byKey(const Key('guide-next-button')));
    await tester.pumpAndSettle();
    _expectGuideSheet(
      tester,
      id: 'apple-target-guide',
      assetPath:
          'assets/images/apple_game_v2/guide_target_pop_sprite_sheet.png',
      width: 2952,
    );
    await tester.tap(find.byKey(const Key('guide-previous-button')));
    await tester.pumpAndSettle();
    expect(find.text('HOW TO PLAY · 1/5'), findsOneWidget);

    const expectedPages = [
      (
        progress: 'HOW TO PLAY · 2/5',
        title: '4 + 6으로 10 만들기',
        copy: '두 사과가 차례로 터지고',
      ),
      (
        progress: 'HOW TO PLAY · 3/5',
        title: 'ㄱ자 세 개도 네모로 선택',
        copy: '빈 칸은 0으로 계산',
      ),
      (
        progress: 'HOW TO PLAY · 4/5',
        title: '한 번에 많이 지우기',
        copy: '1+2+3+4는 4점',
      ),
      (
        progress: 'HOW TO PLAY · 5/5',
        title: '2분 20초 동안 최대한 많이',
        copy: '기록도 제출되지 않습니다',
      ),
    ];

    for (final page in expectedPages) {
      await tester.tap(find.byKey(const Key('guide-next-button')));
      await tester.pumpAndSettle();
      expect(find.text(page.progress), findsOneWidget);
      expect(find.text(page.title), findsOneWidget);
      expect(find.textContaining(page.copy), findsOneWidget);
      if (page.progress == 'HOW TO PLAY · 3/5') {
        _expectGuideSheet(
          tester,
          id: 'apple-sparse-guide',
          assetPath:
              'assets/images/apple_game_v2/guide_sparse_pop_sprite_sheet.png',
          width: 2952,
        );
      }
      expect(tester.takeException(), isNull);
    }

    expect(find.text('설명 끝'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('guide-previous-button')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('guide-next-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-guide-pages')), findsNothing);
  });

  testWidgets('사과게임 설명서는 스와이프와 닫기를 지원한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAppleHome(tester);
    await _openGuide(tester);

    await tester.drag(
      find.byKey(const Key('game-guide-pages')),
      const Offset(-320, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('HOW TO PLAY · 2/5'), findsOneWidget);
    expect(find.text('4 + 6으로 10 만들기'), findsOneWidget);
    await tester.drag(find.text('4 + 6으로 10 만들기'), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-guide-pages')), findsNothing);
  });

  testWidgets('사과게임 메인 화면은 드래그와 합계 10 제거를 반복한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAppleHome(tester);

    expect(find.byKey(const Key('apple-game-v2-preview')), findsOneWidget);
    expect(find.byKey(const Key('apple-home-animation')), findsOneWidget);
    final background = tester.widget<Image>(
      find.byKey(const Key('apple-home-background')),
    );
    expect(
      (background.image as AssetImage).assetName,
      'assets/images/apple_game_v2/apple_game_background.png',
    );
    expect(background.fit, BoxFit.cover);
    expect(background.filterQuality, FilterQuality.none);
    expect(find.text('드래그해서 10을 만드세요'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('apple-home-selection')), findsOneWidget);
    expect(find.byKey(const Key('apple-home-drag-pointer')), findsOneWidget);
    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.text('4 + 6 = 10'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('apple-home-pop-first')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('apple-home-pop-second')), findsOneWidget);
    expect(find.byKey(const Key('apple-home-combo')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.byKey(const Key('apple-home-score-burst')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('apple-home-score')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(find.text('사과 2개 제거!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('사과게임 메인 애니메이션은 짧은 화면에서도 카드에 맞는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpAppleHome(tester);

    final previewSize = tester.getSize(
      find.byKey(const Key('apple-game-v2-preview')),
    );
    expect(previewSize.width / previewSize.height, closeTo(0.78, 0.01));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.byKey(const Key('apple-home-score-burst')), findsOneWidget);
    expect(find.text('사과 2개 제거!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _expectGuideSheet(
  WidgetTester tester, {
  required String id,
  required String assetPath,
  required double width,
}) {
  expect(tester.getSize(find.byKey(Key('$id-sprite'))), const Size(246, 176));
  final sheet = tester.widget<Image>(find.byKey(Key('$id-sheet')));
  expect(sheet.width, width);
  expect(sheet.height, 176);
  expect(sheet.filterQuality, FilterQuality.none);
  expect((sheet.image as AssetImage).assetName, assetPath);
}

Future<void> _pumpAppleHome(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dailyGameRepositoryProvider.overrideWithValue(_AppleGuideRepository()),
      ],
      child: const MaterialApp(home: TodayScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openGuide(WidgetTester tester) async {
  final guideButton = find.byKey(const Key('game-guide-button'));
  await tester.ensureVisible(guideButton);
  await tester.pump();
  await tester.tap(guideButton);
  await tester.pumpAndSettle();
}

class _AppleGuideRepository extends PreviewDailyGameRepository {
  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 26),
    game: const TodayGame(
      id: 'apple_game_v2',
      version: 1,
      displayName: '사과게임',
      description: '달빛 과수원에서 사과 숫자의 합을 10으로 만드세요.',
      durationSeconds: 140,
    ),
    attempts: const [],
    adAttemptAvailable: false,
    testMode: false,
    result: const DailyRankResult(
      score: null,
      rank: null,
      participants: 0,
      topPercent: null,
      nickname: null,
      nearby: [],
    ),
    nickname: null,
  );
}
