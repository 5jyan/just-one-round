import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/economy/domain/economy_transaction.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
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
    expect(state.game?.durationSeconds, 140);
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

  test('시뮬레이터 개발자 메뉴에서 엄마 어디가를 선택할 수 있다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    await repository.setDeveloperGame('mama_duck_trail');
    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt(state.playDate);

    expect(state.game?.displayName, '엄마, 어디가');
    expect(state.game?.durationSeconds, 120);
    expect(attempt.gameId, 'mama_duck_trail');
  });

  test('시뮬레이터 개발자 메뉴에서 홈런왕을 선택할 수 있다', () async {
    final repository = PreviewDailyGameRepository(
      testMode: true,
      initialGameId: 'ten_pitch_slugger',
    );

    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt(state.playDate);

    expect(state.game?.displayName, '홈런왕');
    expect(state.game?.version, 7);
    expect(attempt.gameId, 'ten_pitch_slugger');
  });

  testWidgets('오늘의 게임과 플레이 기회를 보여준다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('오늘의 게임'), findsOneWidget);
    expect(find.text('똥피하기'), findsOneWidget);
    expect(find.textContaining('오늘 비교 기록 24개'), findsOneWidget);
    expect(find.text('딱 한 판만!'), findsOneWidget);
    expect(find.byKey(const Key('economy-summary')), findsNothing);
    expect(find.byKey(const Key('game-guide-button')), findsOneWidget);
    expect(find.byKey(const Key('ranking-button')), findsOneWidget);
  });

  testWidgets('지원하지 않는 빌드는 업데이트 화면에서 플레이를 차단한다', (tester) async {
    final repository = PreviewDailyGameRepository(
      compatibility: const ClientCompatibility(
        currentBuild: 1,
        minimumSupportedBuild: 2,
        updateRequired: true,
        storeUrl: 'https://example.com/store',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('required-update-screen')), findsOneWidget);
    expect(find.byKey(const Key('required-update-button')), findsOneWidget);
    expect(find.text('게임이 업데이트 되었어요'), findsOneWidget);
    expect(find.text('원활한 게임 플레이를 위해\n앱을 업데이트 해주세요'), findsOneWidget);
    expect(find.textContaining('현재 빌드'), findsNothing);
    expect(find.byKey(const Key('required-update-retry')), findsNothing);
    expect(find.text('업데이트 확인'), findsNothing);
    expect(find.text('딱 한 판만!'), findsNothing);
    expect(find.byKey(const Key('game-guide-button')), findsNothing);
  });

  testWidgets('강제 업데이트 중에는 전날 보상을 열지 않는다', (tester) async {
    final repository = _PreviousResultRepository(updateRequired: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('required-update-screen')), findsOneWidget);
    expect(find.byKey(const Key('previous-daily-result-dialog')), findsNothing);
    expect(repository.unseenCalls, 0);
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
    expect(find.text('참여 기록'), findsOneWidget);
    expect(find.text('TOP SCORES'), findsOneWidget);
    expect(find.textContaining('NPC'), findsNothing);
    expect(find.text('REAL PLAYERS'), findsNothing);
    expect(find.text('실제 기록'), findsNothing);
    expect(find.text('작은공룡'), findsOneWidget);
    expect(find.text('5.39초'), findsWidgets);
    expect(find.text('전체'), findsNothing);
    expect(find.text('전체 랭킹'), findsOneWidget);
    expect(find.text('내 주변 랭킹'), findsNothing);
    expect(find.byKey(const Key('overall-leaderboard')), findsOneWidget);
    expect(find.byKey(const Key('nearby-leaderboard')), findsNothing);
    await tester.drag(
      find.byKey(const Key('overall-leaderboard')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leaderboard-gap')), findsOneWidget);
    expect(find.byKey(const Key('my-leaderboard-rank')), findsOneWidget);
    expect(find.byKey(const Key('my-rank-badge')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('my-leaderboard-rank'))).height,
      greaterThanOrEqualTo(74),
    );
    expect(find.text('tester'), findsWidgets);
    expect(find.text('말랑주먹'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('느린번개'),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('overall-leaderboard')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('느린번개'), findsOneWidget);
    expect(find.text('8등'), findsOneWidget);
  });

  testWidgets('랭킹을 열 때 서버의 최신 결과를 다시 조회한다', (tester) async {
    final repository = _RefreshingRankingRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    final rankingButton = find.byKey(const Key('ranking-button'));
    await tester.ensureVisible(rankingButton);
    await tester.tap(rankingButton);
    await tester.pumpAndSettle();

    expect(repository.rankFetchCalls, 1);
    expect(repository.requestedPlayDate, isNotNull);
    expect(find.text('31개'), findsOneWidget);
    expect(find.text('최신랭커'), findsOneWidget);
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
    expect(find.text('실제 기록 24개 중 8위 · 상위 34%'), findsOneWidget);
    expect(find.byKey(const Key('previous-result-reward')), findsOneWidget);
    expect(find.text('+30'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('acknowledge-previous-result')));
    await tester.pumpAndSettle();

    expect(repository.acknowledged, isTrue);
    expect(repository.acknowledgedDate, DateTime(2026, 7, 26));
    expect(repository.acknowledgedGameId, 'dung_dodge_v2');
    expect(find.byKey(const Key('previous-daily-result-dialog')), findsNothing);
    expect(find.text('+30 코인 · +30 EXP를 받았어요!'), findsOneWidget);
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
    expect(find.text('앱 버전 1.0.4 (9)'), findsOneWidget);
  });

  testWidgets('설정의 프로필에서 닉네임·경제·카카오 연결을 관리한다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TodayScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-display-name')), findsOneWidget);
    expect(find.byKey(const Key('profile-economy-card')), findsOneWidget);
    expect(find.byKey(const Key('profile-nickname-action')), findsOneWidget);
    expect(find.byKey(const Key('profile-kakao-action')), findsOneWidget);
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

  testWidgets('테스트 계정은 앱 버전 7회 탭으로 PIN 없이 원래 모드로 돌아온다', (tester) async {
    final repository = _TestModeDeactivationRepository();
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

    expect(repository.deactivationCalls, 1);
    expect(find.byKey(const Key('tester-pin-field')), findsNothing);
    expect(find.text('원래 계정 모드로 돌아왔어요.'), findsOneWidget);

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('developer-mode-menu')), findsNothing);
  });
}

class _PrivacyRequiredAdService extends FakeRewardedAdService {
  @override
  Future<bool> isPrivacyOptionsRequired() async => true;
}

class _RefreshingRankingRepository extends PreviewDailyGameRepository {
  var rankFetchCalls = 0;
  DateTime? requestedPlayDate;

  @override
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async {
    rankFetchCalls += 1;
    requestedPlayDate = playDate;
    return const DailyRankResult(
      score: 4200,
      rank: 2,
      participants: 31,
      topPercent: 7,
      nickname: 'tester',
      bestScore: 5000,
      nearby: [
        NearbyRank(rank: 2, nickname: 'tester', score: 4200, isMe: true),
      ],
      leaders: [
        NearbyRank(rank: 1, nickname: '최신랭커', score: 5000, isMe: false),
        NearbyRank(rank: 2, nickname: 'tester', score: 4200, isMe: true),
      ],
    );
  }
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

class _TestModeDeactivationRepository extends PreviewDailyGameRepository {
  _TestModeDeactivationRepository() : super(testMode: true);

  var deactivationCalls = 0;

  @override
  Future<void> deactivateTestMode() async {
    deactivationCalls += 1;
    await super.deactivateTestMode();
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
  _PreviousResultRepository({this.updateRequired = false});

  final bool updateRequired;
  var acknowledged = false;
  var unseenCalls = 0;
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
    compatibility: updateRequired
        ? const ClientCompatibility(
            currentBuild: 1,
            minimumSupportedBuild: 2,
            updateRequired: true,
            storeUrl: 'https://example.com/store',
          )
        : const ClientCompatibility.supported(),
  );

  @override
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult() async {
    unseenCalls++;
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
  Future<RewardGrant> acknowledgePreviousDailyResult(
    DateTime playDate,
    String gameId,
  ) async {
    acknowledged = true;
    acknowledgedDate = playDate;
    acknowledgedGameId = gameId;
    return RewardGrant(
      coinsGranted: 30,
      experienceGranted: 30,
      economy: PlayerEconomy.fromTotals(coins: 30, experiencePoints: 30),
    );
  }
}
