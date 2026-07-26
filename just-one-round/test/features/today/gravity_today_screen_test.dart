import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

void main() {
  testWidgets('그래비티 스위치 메인 애니메이션은 TIME과 함께 반복한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(_GravityRepository()),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('그래비티 스위치'), findsOneWidget);
    expect(find.byKey(const Key('gravity-home-animation')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith(
              'gravity_switch_v2/gravity_runtime_main.webp',
            ),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.contains(
              'gravity_switch_v2',
            ),
      ),
      findsOneWidget,
    );

    expect(
      find.byKey(const Key('gravity-home-runtime-capture')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('그래비티 스위치 설명서는 실제 규칙과 KO GAME OVER를 네 페이지로 안내한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(_GravityRepository()),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.pump();
    await tester.tap(guideButton);
    await tester.pumpAndSettle();

    expect(find.text('탭해서 중력 뒤집기'), findsOneWidget);
    expect(find.text('HOW TO PLAY · 1/4'), findsOneWidget);
    expect(
      find.byKey(const Key('gravity-control-sprite-animation')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith(
              'gravity_switch_v2/gravity_runtime_control.webp',
            ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gravity-runtime-control')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('guide-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('벽에 박기 전에 안전한 쪽으로'), findsOneWidget);
    expect(find.textContaining('고철 벽이 캐릭터 옆을 지나갑니다'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gravity-runtime-obstacle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('guide-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('갈수록 더 빠르고 어려워져요'), findsOneWidget);
    expect(find.textContaining('점점 더 빠르게'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gravity-runtime-difficulty')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('guide-next-button')));
    await tester.pumpAndSettle();

    expect(find.text('한 번 부딪히면 GAME OVER'), findsOneWidget);
    expect(find.textContaining('KO 상태'), findsOneWidget);
    expect(find.text('설명 끝'), findsOneWidget);

    expect(
      find.byKey(const ValueKey('gravity-runtime-collision')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('그래비티 스위치 설명서는 짧은 화면에서도 모든 페이지가 잘리지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(_GravityRepository()),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.tap(guideButton);
    await tester.pumpAndSettle();

    for (var page = 1; page <= 4; page++) {
      expect(find.text('HOW TO PLAY · $page/4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (page < 4) {
        await tester.tap(find.byKey(const Key('guide-next-button')));
        await tester.pumpAndSettle();
      }
    }
  });
}

class _GravityRepository extends PreviewDailyGameRepository {
  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 22),
    game: const TodayGame(
      id: 'gravity_switch',
      version: 1,
      displayName: '그래비티 스위치',
      description: '입체 기둥 미로를 돌파하세요.',
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
