import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/previous_daily_result.dart';
import 'package:just_one_round/features/today/domain/tester_activation_result.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

void main() {
  test('시뮬레이터용 저장소는 tester 계정으로 동작한다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    final state = await repository.fetchToday();

    expect(state.testMode, isTrue);
    expect(state.nickname, 'tester');
    expect(state.canClaimDaily, isTrue);
    expect(state.result?.leaders, hasLength(8));
  });

  test('비운 게임은 시뮬레이터 선택 목록에서도 제외한다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('apple_game');
    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt(state.playDate);

    expect(attempt.gameId, 'dung_dodge_v2');
  });

  test('시뮬레이터 개발자 메뉴에서 탭50을 선택할 수 있다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('number_rush');
    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt(state.playDate);

    expect(state.game?.displayName, '탭50');
    expect(state.game?.durationSeconds, 180);
    expect(attempt.gameId, 'number_rush');
  });

  test('시뮬레이터 개발자 메뉴에서 사과게임을 선택할 수 있다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('apple_game_v2');
    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt(state.playDate);

    expect(state.game?.displayName, '사과게임');
    expect(state.game?.durationSeconds, 120);
    expect(attempt.gameId, 'apple_game_v2');
  });

  test('시뮬레이터 개발자 메뉴에서 똥피하기를 선택할 수 있다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('dung_dodge_v2');
    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt(state.playDate);

    expect(state.game?.displayName, '똥피하기');
    expect(state.game?.durationSeconds, 300);
    expect(attempt.gameId, 'dung_dodge_v2');
  });

  testWidgets('오늘의 게임과 플레이 기회를 보여준다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('오늘의 게임'), findsOneWidget);
    expect(find.text('똥피하기'), findsOneWidget);
    expect(find.textContaining('오늘 비교 기록 24개'), findsOneWidget);
    expect(find.text('딱 한 판만!'), findsOneWidget);
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
    expect(find.text('24개'), findsOneWidget);
    expect(find.text('작은공룡'), findsOneWidget);
    expect(find.text('5.39초'), findsWidgets);
    expect(find.text('전체'), findsNothing);
    expect(find.text('전체 비교 랭킹'), findsOneWidget);
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

    expect(find.text('SURVIVE'), findsNothing);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.byKey(const Key('survival-time')), findsOneWidget);
    expect(find.text('화면을 좌우로 드래그하세요'), findsOneWidget);
  });

  testWidgets('시작 직전에 날짜가 바뀌면 팝업 후 새 게임을 불러온다', (tester) async {
    final repository = _DailyResetRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('똥 피하기'), findsOneWidget);
    final startButton = find.byType(PixelButton);
    await tester.ensureVisible(startButton);
    await tester.pump();
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('오늘의 게임이 변경되었습니다.'), findsOneWidget);
    expect(repository.claimCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();

    expect(find.text('중력 스위치'), findsOneWidget);
    expect(find.text('SURVIVE'), findsNothing);
  });

  testWidgets('전날 최종 결과를 한 번 보여주고 확인 상태를 저장한다', (tester) async {
    final repository = _PreviousResultRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('previous-daily-result-dialog')),
      findsOneWidget,
    );
    expect(find.text('어제의 최종 결과'), findsOneWidget);
    expect(find.text('똥피하기'), findsOneWidget);
    expect(find.text('실제 기록 + NPC 24개 중 8위 · 상위 34%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('acknowledge-previous-result')));
    await tester.pumpAndSettle();

    expect(repository.acknowledged, isTrue);
    expect(repository.acknowledgedDate, DateTime(2026, 7, 26));
    expect(repository.acknowledgedGameId, 'dung_dodge_v2');
    expect(find.byKey(const Key('previous-daily-result-dialog')), findsNothing);
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

    final homeButton = find.text('홈으로');
    await tester.ensureVisible(homeButton);
    await tester.pump();
    await tester.tap(homeButton);
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
    expect(find.text('딱 한 판만!'), findsOneWidget);
    expect(find.text('SURVIVE'), findsNothing);
  });

  testWidgets('일반 계정 설정은 필요한 정책만 표시한다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TodayScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('developer-mode-menu')), findsNothing);
    expect(find.text('커뮤니티 운영정책'), findsOneWidget);
    expect(find.text('광고 개인정보 선택'), findsNothing);
  });

  testWidgets('UMP가 요구하는 지역에서만 광고 개인정보 선택을 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rewardedAdServiceProvider.overrideWithValue(
            _PrivacyRequiredAdService(),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    expect(find.text('광고 개인정보 선택'), findsOneWidget);
  });

  testWidgets('앱 버전을 7번 누르고 PIN을 입력하면 테스트 모드가 활성화된다', (tester) async {
    final repository = _TesterActivationRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    final versionTarget = find.byKey(const Key('app-version-tap-target'));
    await tester.ensureVisible(versionTarget);
    for (var tap = 0; tap < 7; tap++) {
      await tester.tap(versionTarget);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(find.text('테스터 인증'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tester-pin-field')), '111111');
    await tester.tap(find.byKey(const Key('activate-tester-mode')));
    await tester.pumpAndSettle();
    expect(find.textContaining('4회 남았어요'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('tester-pin-field')), '987654');
    await tester.tap(find.byKey(const Key('activate-tester-mode')));
    await tester.pumpAndSettle();

    expect(repository.activationPins, ['111111', '987654']);
    expect(find.text('테스트 모드가 활성화됐어요.'), findsOneWidget);

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('developer-mode-menu')), findsOneWidget);
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

class _PrivacyRequiredAdService extends FakeRewardedAdService {
  @override
  Future<bool> isPrivacyOptionsRequired() async => true;
}

class _TestAccountRepository extends PreviewDailyGameRepository {
  var resetCalls = 0;

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 22),
    game: const TodayGame(
      id: 'dung_dodge_v2',
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
    nickname: '테스트',
  );

  @override
  Future<List<DeveloperGame>> fetchDeveloperGames() async => const [
    DeveloperGame(id: 'dung_dodge_v2', version: 1, displayName: '똥 피하기'),
  ];

  @override
  Future<void> resetDeveloperDailyProgress() async {
    resetCalls += 1;
  }
}

class _DailyResetRepository extends PreviewDailyGameRepository {
  var fetchCalls = 0;
  var claimCalls = 0;

  @override
  Future<TodayState> fetchToday() async {
    fetchCalls += 1;
    return _state(
      playDate: fetchCalls == 1 ? DateTime(2026, 7, 26) : DateTime(2026, 7, 27),
      gameId: fetchCalls == 1 ? 'dung_dodge_v2' : 'gravity_switch',
      displayName: fetchCalls == 1 ? '똥 피하기' : '중력 스위치',
    );
  }

  @override
  Future<PlayAttempt> claimDailyAttempt(DateTime expectedPlayDate) async {
    claimCalls += 1;
    return const PlayAttempt(
      id: 'should-not-be-claimed',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
      gameId: 'gravity_switch',
    );
  }

  TodayState _state({
    required DateTime playDate,
    required String gameId,
    required String displayName,
  }) => TodayState(
    playDate: playDate,
    game: TodayGame(
      id: gameId,
      version: 1,
      displayName: displayName,
      description: '테스트',
      durationSeconds: 60,
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

class _TesterActivationRepository extends PreviewDailyGameRepository {
  final activationPins = <String>[];
  var activated = false;

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 26),
    game: const TodayGame(
      id: 'dung_dodge_v2',
      version: 1,
      displayName: '똥 피하기',
      description: '테스트',
      durationSeconds: 60,
    ),
    attempts: const [],
    adAttemptAvailable: false,
    testMode: activated,
    result: null,
    nickname: null,
  );

  @override
  Future<TesterActivationResult> activateTestMode(String pin) async {
    activationPins.add(pin);
    if (pin != '987654') {
      return const TesterActivationResult(
        status: TesterActivationStatus.invalid,
        attemptsRemaining: 4,
      );
    }
    activated = true;
    return const TesterActivationResult(
      status: TesterActivationStatus.activated,
    );
  }
}

class _PreviousResultRepository extends PreviewDailyGameRepository {
  var acknowledged = false;
  DateTime? acknowledgedDate;
  String? acknowledgedGameId;

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 27),
    game: const TodayGame(
      id: 'gravity_switch',
      version: 1,
      displayName: '중력 스위치',
      description: '테스트',
      durationSeconds: 180,
    ),
    attempts: const [],
    adAttemptAvailable: false,
    testMode: false,
    result: null,
    nickname: '플레이어',
  );

  @override
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult() async {
    if (acknowledged) return null;
    return PreviousDailyResult(
      playDate: DateTime(2026, 7, 26),
      gameId: 'dung_dodge_v2',
      displayName: '똥피하기',
      score: 12345,
      rank: 8,
      participants: 24,
      topPercent: 34,
    );
  }

  @override
  Future<void> acknowledgePreviousDailyResult(
    DateTime playDate,
    String gameId,
  ) async {
    acknowledged = true;
    acknowledgedDate = playDate;
    acknowledgedGameId = gameId;
  }
}
