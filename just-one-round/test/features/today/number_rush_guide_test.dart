import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

void main() {
  testWidgets('탭50 메인 화면은 1·2·3 탭과 NEXT 변경을 반복한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            _NumberRushRepository(),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pump();

    String nextValue() => tester
        .widget<Text>(find.byKey(const Key('number-rush-home-next-value')))
        .data!;
    double timeValue() => double.parse(
      tester
          .widget<Text>(find.byKey(const Key('number-rush-home-time-value')))
          .data!,
    );

    expect(nextValue(), '1');
    final initialTime = timeValue();
    await tester.pump(const Duration(milliseconds: 900));
    expect(nextValue(), '2');
    expect(timeValue(), greaterThan(initialTime));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(nextValue(), '3');
    expect(timeValue(), greaterThan(initialTime + 1));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(nextValue(), '1');
    expect(timeValue(), closeTo(initialTime, 0.01));
  });

  testWidgets('탭50 설명서는 실제 규칙을 다섯 페이지로 안내한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            _NumberRushRepository(),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('number-rush-home-hero')), findsOneWidget);
    expect(
      find.byKey(const Key('number-rush-home-tap-animation')),
      findsOneWidget,
    );
    for (final number in [1, 2, 3]) {
      expect(find.byKey(Key('number-rush-home-tile-$number')), findsOneWidget);
    }

    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.tap(guideButton);
    await tester.pumpAndSettle();

    const expectedPages = [
      (
        progress: 'HOW TO PLAY · 1/5',
        title: '1부터 차례대로 탭',
        copy: '숫자 타일을 하나씩 탭',
        visualKey: 'number-rush-sequence-animation',
      ),
      (
        progress: 'HOW TO PLAY · 2/5',
        title: 'NEXT 숫자를 확인',
        copy: '타일을 누를 때마다 다음 숫자로',
        visualKey: 'number-rush-next-animation',
      ),
      (
        progress: 'HOW TO PLAY · 3/5',
        title: '빈칸에 새 숫자가 켜져요',
        copy: '약 0.5~2초 뒤',
        visualKey: 'number-rush-refill-animation',
      ),
      (
        progress: 'HOW TO PLAY · 4/5',
        title: '틀리면 시간 손해',
        copy: '타이머는 계속',
        visualKey: 'number-rush-mistake-animation',
      ),
      (
        progress: 'HOW TO PLAY · 5/5',
        title: '50을 누르면 기록 확정',
        copy: '최대 3분 안에',
        visualKey: 'number-rush-result-animation',
      ),
    ];

    for (var index = 0; index < expectedPages.length; index++) {
      final page = expectedPages[index];
      expect(find.text(page.progress), findsOneWidget);
      expect(find.text(page.title), findsOneWidget);
      expect(find.textContaining(page.copy), findsOneWidget);
      expect(find.byKey(Key(page.visualKey)), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (index < expectedPages.length - 1) {
        await tester.tap(find.byKey(const Key('guide-next-button')));
        await tester.pumpAndSettle();
      }
    }

    expect(find.text('설명 끝'), findsOneWidget);
  });

  testWidgets('탭50 설명서는 짧은 화면에서도 모든 페이지가 잘리지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            _NumberRushRepository(),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.tap(guideButton);
    await tester.pumpAndSettle();

    final previous = tester.widget<OutlinedButton>(
      find.byKey(const Key('guide-previous-button')),
    );
    expect(previous.onPressed, isNull);

    for (var index = 0; index < 5; index++) {
      expect(find.text('HOW TO PLAY · ${index + 1}/5'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (index < 4) {
        await tester.tap(find.byKey(const Key('guide-next-button')));
        await tester.pumpAndSettle();
      }
    }
  });
}

class _NumberRushRepository extends PreviewDailyGameRepository {
  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 26),
    game: const TodayGame(
      id: 'number_rush',
      version: 1,
      displayName: '탭50',
      description: '1부터 50까지 빠르게 찾으세요.',
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
