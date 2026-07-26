import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  test('시뮬레이터용 저장소는 tester 계정으로 동작한다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    final state = await repository.fetchToday();

    expect(state.testMode, isTrue);
    expect(state.profile.nickname, 'tester');
    expect(state.canClaimDaily, isTrue);
    expect(state.result?.leaders, hasLength(8));
  });

  test('시뮬레이터에서 선택한 게임 ID를 플레이 시도에 전달한다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('apple_game');
    final attempt = await repository.claimDailyAttempt();

    expect(attempt.gameId, 'apple_game');
  });

  test('시뮬레이터 개발자 메뉴에서 넘버 러시를 선택할 수 있다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('number_rush');
    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt();

    expect(state.game?.displayName, '넘버 러시');
    expect(state.game?.durationSeconds, 180);
    expect(attempt.gameId, 'number_rush');
  });

  test('시뮬레이터 개발자 메뉴에서 사과게임 2를 선택할 수 있다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('apple_game_v2');
    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt();

    expect(state.game?.displayName, '사과게임 2');
    expect(state.game?.durationSeconds, 120);
    expect(attempt.gameId, 'apple_game_v2');
  });

  test('시뮬레이터 개발자 메뉴에서 똥피하기 2를 선택할 수 있다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('dung_dodge_v2');
    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt();

    expect(state.game?.displayName, '똥피하기 2');
    expect(state.game?.durationSeconds, 300);
    expect(attempt.gameId, 'dung_dodge_v2');
  });

  testWidgets('오늘의 게임과 플레이 기회를 보여준다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('오늘의 게임'), findsOneWidget);
    expect(find.text('똥피하기 2'), findsOneWidget);
    expect(find.textContaining('오늘 24명 도전 중'), findsOneWidget);
    expect(find.textContaining('오늘의 한 판 시작'), findsOneWidget);
    expect(find.byKey(const Key('game-guide-button')), findsOneWidget);
    expect(find.byKey(const Key('ranking-button')), findsOneWidget);
  });

  testWidgets('게임 설명은 다섯 페이지를 옆으로 넘기며 안내한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    final guideButton = find.byKey(const Key('game-guide-button'));
    await tester.ensureVisible(guideButton);
    await tester.pump();
    await tester.tap(guideButton);
    await tester.pumpAndSettle();

    expect(find.text('HOW TO PLAY · 1/5'), findsOneWidget);
    expect(find.text('누른 채로 좌우로 드래그'), findsOneWidget);
    expect(find.textContaining('가볍게 터치만 하면 움직이지 않아요'), findsOneWidget);
    expect(find.text('이전'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('guide-previous-button')),
          )
          .onPressed,
      isNull,
    );

    for (final expectedTitle in [
      '떨어지는 똥 사이로 피하기',
      '시간이 갈수록 더 어려워져요',
      '한 번 부딪히면 즉시 종료',
      '최대한 오래 살아남으세요',
    ]) {
      await tester.tap(find.byKey(const Key('guide-next-button')));
      await tester.pumpAndSettle();
      expect(find.text(expectedTitle), findsOneWidget);
    }

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('guide-previous-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('최대 5분 동안'), findsOneWidget);
    expect(find.text('설명 끝'), findsOneWidget);
  });

  testWidgets('랭킹 버튼은 오늘 상위 기록을 연다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    final rankingButton = find.byKey(const Key('ranking-button'));
    await tester.ensureVisible(rankingButton);
    await tester.pump();
    await tester.tap(rankingButton);
    await tester.pumpAndSettle();

    expect(find.text('DAILY LEADERBOARD'), findsOneWidget);
    expect(find.text('24명'), findsOneWidget);
    expect(find.text('작은공룡'), findsOneWidget);
    expect(find.text('5.39초'), findsWidgets);
    expect(find.text('전체'), findsNothing);
    expect(find.text('전체 랭킹'), findsOneWidget);
    expect(find.text('내 주변 랭킹'), findsNothing);
    expect(find.byKey(const Key('overall-leaderboard')), findsOneWidget);
    expect(find.byKey(const Key('nearby-leaderboard')), findsNothing);
    expect(find.byKey(const Key('leaderboard-gap')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('overall-leaderboard')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-leaderboard-rank')), findsOneWidget);
    expect(find.byKey(const Key('my-rank-badge')), findsOneWidget);
    expect(find.text('tester'), findsWidgets);
    expect(find.text('말랑주먹'), findsOneWidget);
    expect(find.text('느린번개'), findsOneWidget);
    expect(find.text('8등'), findsOneWidget);
  });

  testWidgets('시작 버튼으로 게임 화면에 진입한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    final startButton = find.byType(PixelButton);
    await tester.ensureVisible(startButton);
    await tester.pump();
    await tester.tap(startButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('SURVIVE'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('화면을 좌우로 드래그하세요'), findsOneWidget);
  });

  testWidgets('중단 화면의 홈 버튼은 홈으로 이동한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    final startButton = find.byType(PixelButton);
    await tester.ensureVisible(startButton);
    await tester.pump();
    await tester.tap(startButton);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    await tester.tap(find.text('홈으로'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(find.text('오늘의 게임'), findsOneWidget);
    expect(find.text('SURVIVE'), findsNothing);
    expect(find.text('기회 받는 중...'), findsNothing);
  });

  testWidgets('플레이 정보 없이 /play로 시작하면 홈으로 이동한다', (tester) async {
    final router = createAppRouter(initialLocation: '/play');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘의 게임'), findsOneWidget);
    expect(find.textContaining('오늘의 한 판 시작'), findsOneWidget);
    expect(find.text('SURVIVE'), findsNothing);
  });

  testWidgets('일반 계정 설정에는 개발자 모드가 보이지 않는다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TodayScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('developer-mode-menu')), findsNothing);
  });

  testWidgets('설정 버튼을 5초 안에 10번 누르면 테스터 계정이 된다', (tester) async {
    final repository = _ActivatableRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (var tap = 0; tap < 10; tap++) {
      await tester.tap(find.byTooltip('설정'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.enableCalls, 1);
    expect(find.text('테스터 계정이 활성화됐어요.'), findsOneWidget);
  });

  testWidgets('테스트 계정은 개발자 모드에서 오늘 횟수를 초기화한다', (tester) async {
    final repository = _TestAccountRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('developer-mode-menu')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('developer-game-dropdown')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reset-daily-progress')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, '초기화'));
    await tester.pumpAndSettle();

    expect(repository.resetCalls, 1);
  });
}

class _ActivatableRepository extends PreviewDailyGameRepository {
  var enableCalls = 0;

  @override
  Future<void> enableTestMode() async {
    enableCalls++;
    await super.enableTestMode();
  }
}

class _TestAccountRepository extends PreviewDailyGameRepository {
  var resetCalls = 0;

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 22),
    game: const TodayGame(
      id: 'dung_dodge',
      version: 1,
      displayName: '똥 피하기',
      description: '테스트',
      durationSeconds: 60,
    ),
    attempts: const [],
    adAttemptAvailable: false,
    testMode: true,
    result: const DailyRankResult(
      score: null,
      rank: null,
      participants: 0,
      topPercent: null,
      nickname: '테스트',
      nearby: [],
    ),
    profile: const UserProfile(
      nickname: '테스트',
      birthYear: null,
      birthMonth: null,
      gender: null,
    ),
  );

  @override
  Future<List<DeveloperGame>> fetchDeveloperGames() async => const [
    DeveloperGame(id: 'dung_dodge', version: 1, displayName: '똥 피하기'),
  ];

  @override
  Future<void> resetDeveloperDailyProgress() async {
    resetCalls += 1;
  }
}
