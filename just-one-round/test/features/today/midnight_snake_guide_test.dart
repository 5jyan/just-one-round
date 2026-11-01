import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

void main() {
  testWidgets('야식털이 뱀 메인은 실제 런타임 에셋으로 긴 플레이 루프를 재생한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            _MidnightSnakeRepository(),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('야식털이 뱀'), findsOneWidget);
    expect(
      find.byKey(const Key('midnight-snake-home-animation')),
      findsOneWidget,
    );
    final homePreviewFittedBox = tester.widget<FittedBox>(
      find.ancestor(
        of: find.byKey(const Key('midnight-snake-home-animation')),
        matching: find.byType(FittedBox),
      ),
    );
    expect(homePreviewFittedBox.clipBehavior, Clip.hardEdge);
    expect(find.text('오늘의 게임'), findsOneWidget);
    expect(find.byTooltip('설정'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith(
              'midnight_snake/apartment_background.png',
            ),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 12));
    expect(
      find.byKey(const Key('midnight-snake-home-animation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('설명서는 예약 입력 적용을 포함한 네 개 애니메이션을 안내한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            _MidnightSnakeRepository(),
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

    expect(find.text('HOW TO PLAY · 1/4'), findsOneWidget);
    expect(find.text('하단 버튼으로 방향 전환'), findsOneWidget);
    expect(
      find.byKey(const Key('midnight-snake-buttons-guide-animation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('midnight-snake-direction-buttons')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('왼쪽 방향 버튼'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('HOW TO PLAY · 2/4'), findsOneWidget);
    expect(find.text('야식을 먹고 길어지기'), findsOneWidget);
    expect(find.textContaining('황금 소시지는 3점'), findsOneWidget);
    expect(find.textContaining('쥐는 3점'), findsOneWidget);
    expect(
      find.byKey(const Key('midnight-snake-grow-guide-animation')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('guide-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('HOW TO PLAY · 3/4'), findsOneWidget);
    expect(find.text('방향을 최대 3개까지 예약'), findsOneWidget);
    expect(
      find.byKey(const Key('midnight-snake-queued-inputs')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.textContaining('예약 3/3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.textContaining('예약 2/3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('HOW TO PLAY · 4/4'), findsOneWidget);
    expect(find.text('벽과 자기 몸은 즉시 종료'), findsOneWidget);
    expect(find.textContaining('5분'), findsWidgets);
    expect(find.text('설명 끝'), findsOneWidget);
    expect(
      find.byKey(const Key('midnight-snake-collision-guide-animation')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}

class _MidnightSnakeRepository extends PreviewDailyGameRepository {
  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 30),
    game: const TodayGame(
      id: 'midnight_snake',
      version: 2,
      displayName: '야식털이 뱀',
      description: '밤에 탈출한 애완뱀을 조종해 야식을 털어 먹으세요.',
      durationSeconds: 300,
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
