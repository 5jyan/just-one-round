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
  });

  test('시뮬레이터에서 선택한 게임 ID를 플레이 시도에 전달한다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('apple_game');
    final attempt = await repository.claimDailyAttempt();

    expect(attempt.gameId, 'apple_game');
  });

  testWidgets('오늘의 게임과 플레이 기회를 보여준다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('딱한판만'), findsOneWidget);
    expect(find.text('별빛 피하기'), findsOneWidget);
    expect(find.text('오늘의 한 판 시작'), findsOneWidget);
    expect(find.text('아직 플레이하지 않았어요 · 기회 1회'), findsOneWidget);
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

    expect(find.text('딱한판만'), findsOneWidget);
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

    expect(find.text('딱한판만'), findsOneWidget);
    expect(find.text('오늘의 한 판 시작'), findsOneWidget);
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
