import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

void main() {
  testWidgets('home preview animates a coherent bet-to-win loop', (
    tester,
  ) async {
    await _pumpToday(tester);

    expect(find.text('블랙잭'), findsOneWidget);
    expect(find.byKey(const Key('beat-dealer-home-animation')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('beat-dealer-home-animation')),
        matching: find.text('100'),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 5400));
    expect(
      find.descendant(
        of: find.byKey(const Key('beat-dealer-home-animation')),
        matching: find.text('120'),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 2100));
    expect(
      find.descendant(
        of: find.byKey(const Key('beat-dealer-home-animation')),
        matching: find.text('100'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'five guide pages teach bet, cards, choice, dealer, and ranking',
    (tester) async {
      await _pumpToday(tester);

      final guideButton = find.byKey(const Key('game-guide-button'));
      await tester.ensureVisible(guideButton);
      await tester.tap(guideButton);
      await tester.pumpAndSettle();

      expect(find.text('HOW TO PLAY · 1/5'), findsOneWidget);
      expect(find.text('공개 카드를 보고 배팅'), findsOneWidget);
      expect(find.textContaining('5~50코인'), findsOneWidget);
      expect(find.textContaining('최대 100코인'), findsOneWidget);
      expect(find.textContaining('8초가 지나면'), findsOneWidget);
      expect(find.textContaining('자동 배팅'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('HOW TO PLAY · 2/5'), findsOneWidget);
      expect(find.text('21에 가깝게 만들기'), findsOneWidget);
      expect(find.textContaining('J·Q·K'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('HOW TO PLAY · 3/5'), findsOneWidget);
      expect(find.text('한 장 더 또는 멈추기'), findsOneWidget);
      expect(find.textContaining('자동으로 멈춰요'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('HOW TO PLAY · 4/5'), findsOneWidget);
      expect(find.text('딜러 규칙은 자동'), findsOneWidget);
      expect(find.textContaining('딜러도 버스트여도 패배'), findsOneWidget);
      expect(find.textContaining('같은 합계일 때만 무승부'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('HOW TO PLAY · 5/5'), findsOneWidget);
      expect(find.text('10라운드 코인 랭킹'), findsOneWidget);
      expect(find.textContaining('기회가 소진'), findsOneWidget);
      expect(find.text('설명 끝'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(360, 640), const Size(360, 840)]) {
    testWidgets('guide fits ${size.width}x${size.height}', (tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpToday(tester);

      final guideButton = find.byKey(const Key('game-guide-button'));
      await tester.ensureVisible(guideButton);
      await tester.tap(guideButton);
      await tester.pumpAndSettle();

      expect(find.text('HOW TO PLAY · 1/5'), findsOneWidget);
      expect(find.byKey(const Key('beat-dealer-guide-bet')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpToday(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dailyGameRepositoryProvider.overrideWithValue(
          _BeatTheDealerRepository(),
        ),
      ],
      child: const MaterialApp(home: TodayScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _BeatTheDealerRepository extends PreviewDailyGameRepository {
  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 30),
    game: const TodayGame(
      id: 'beat_the_dealer',
      version: 3,
      displayName: '블랙잭',
      description: '공개 카드를 보고 배팅한 뒤 21에 가까운 패를 만드세요.',
      durationSeconds: 180,
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
