import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/economy/domain/economy_transaction.dart';
import 'package:just_one_round/features/gameplay/presentation/game_end_transition.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_session.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/previous_daily_result.dart';
import 'package:just_one_round/features/today/domain/tester_activation_result.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  test('복귀 상태를 제외한 모든 앱 상태에서 판을 소진한다', () {
    expect(shouldInterruptGame(AppLifecycleState.resumed), isFalse);
    expect(shouldInterruptGame(AppLifecycleState.inactive), isTrue);
    expect(shouldInterruptGame(AppLifecycleState.hidden), isTrue);
    expect(shouldInterruptGame(AppLifecycleState.paused), isTrue);
    expect(shouldInterruptGame(AppLifecycleState.detached), isTrue);
  });

  testWidgets('게임이 시작되면 다음 보상형 광고를 미리 불러온다', (tester) async {
    final adService = _PreloadTrackingRewardedAdService();
    const attempt = PlayAttempt(
      id: 'attempt-preload-next-ad',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
      gameId: 'dung_dodge_v2',
      gameVersion: 1,
      gameDurationSeconds: 300,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rewardedAdServiceProvider.overrideWithValue(adService)],
        child: const MaterialApp(
          home: GameScreen(attempt: attempt, countdownDuration: Duration.zero),
        ),
      ),
    );
    await tester.pump();

    expect(adService.preloadCalls, 1);
  });

  testWidgets('플레이 중 시스템 뒤로가기와 스와이프 이탈을 막는다', (tester) async {
    const attempt = PlayAttempt(
      id: 'practice-back-guard',
      ordinal: 1,
      status: 'practice',
      grantType: 'practice_ad',
      gameId: 'dung_dodge_v2',
      gameVersion: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GameScreen(attempt: attempt),
                ),
              ),
              child: const Text('게임 시작'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('게임 시작'));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('게임 시작'), findsNothing);
  });

  testWidgets('컵라면은 3.2초 후 pointer down에서 다음 목표로 넘어간다', (tester) async {
    const attempt = PlayAttempt(
      id: 'ramen-timer-practice',
      ordinal: 1,
      status: 'practice',
      grantType: 'practice_ad',
      gameId: 'ramen_timer',
      gameVersion: 1,
      gameDurationSeconds: 45,
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GameScreen(attempt: attempt, countdownDuration: Duration.zero),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('ramen-timer-hud-message')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3300)),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final action = find.byKey(const Key('ramen-timer-action-button'));
    expect(action, findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);
    expect(find.text('10초'), findsOneWidget);
    expect(find.text('10초 지금 찍기!'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(action));
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('20초'), findsOneWidget);
    expect(find.text('20초 지금 찍기!'), findsOneWidget);
    expect(find.text('파 투입! 다음은 20초'), findsOneWidget);
    await gesture.up();
  });

  testWidgets('제한 시간이 끝나면 결과를 보여준다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GameScreen(
            gameDuration: Duration(milliseconds: 100),
            countdownDuration: Duration.zero,
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.byKey(const Key('game-end-title')));

    final titleElement = tester.element(
      find.byKey(const Key('game-end-title')),
    );
    final titleCenter = tester.getCenter(
      find.byKey(const Key('game-end-title')),
    );
    final backdropSize = tester.getSize(
      find.byKey(const Key('game-end-backdrop')),
    );
    expect(find.byKey(const Key('game-end-title')), findsOneWidget);
    expect(find.text('TIME UP!'), findsNWidgets(2));
    expect(find.text('한 판 종료!'), findsNothing);

    await tester.pump(
      gameEndTransitionDuration + const Duration(milliseconds: 100),
    );
    await tester.pump();

    final panelStart = tester.getTopLeft(find.byKey(const Key('result-panel')));
    await tester.pump(gameEndResultRevealDuration);

    expect(find.text('한 판 종료!'), findsOneWidget);
    expect(find.byKey(const Key('final-score')), findsOneWidget);
    final finalScore = tester.widget<Text>(
      find.byKey(const Key('final-score')),
    );
    expect(finalScore.maxLines, 1);
    expect(finalScore.softWrap, isFalse);
    expect(
      find.ancestor(
        of: find.byKey(const Key('final-score')),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
    expect(find.text('0.01초'), findsNothing);
    expect(find.text('기록 단위'), findsNothing);
    expect(find.text('홈으로'), findsOneWidget);
    expect(find.byKey(const Key('game-end-title')), findsOneWidget);
    expect(
      identical(
        titleElement,
        tester.element(find.byKey(const Key('game-end-title'))),
      ),
      isTrue,
    );
    expect(
      tester.getCenter(find.byKey(const Key('game-end-title'))),
      titleCenter,
    );
    expect(
      tester.getSize(find.byKey(const Key('game-end-backdrop'))),
      backdropSize,
    );
    expect(
      titleCenter.dy,
      lessThan(tester.getTopLeft(find.text('한 판 종료!')).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('result-panel'))).dy,
      lessThan(panelStart.dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('result-panel'))).dy,
      lessThan(180),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('result-panel'))).dy -
          tester.getBottomLeft(find.byKey(const Key('game-end-title'))).dy,
      greaterThan(16),
    );
  });

  testWidgets('연습 판 결과는 랭킹을 제출하지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(_RecordingRepository()),
        ],
        child: const MaterialApp(
          home: GameScreen(
            attempt: PlayAttempt(
              id: 'practice-session',
              ordinal: 3,
              status: 'practice',
              grantType: 'practice_ad',
              gameId: 'dung_dodge_v2',
              gameVersion: 1,
              gameDurationSeconds: 1,
            ),
            countdownDuration: Duration.zero,
            gameDuration: Duration(milliseconds: 100),
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('연습 모드 · 이 점수는 랭킹에 반영되지 않아요'));
    expect(find.text('오늘 순위를 계산하고 있어요...'), findsNothing);
  });

  testWidgets('시도에 발급된 게임 시간이 기본 시간보다 우선한다', (tester) async {
    const attempt = PlayAttempt(
      id: 'attempt-issued-duration',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
      gameId: 'dung_dodge_v2',
      gameVersion: 1,
      gameDurationSeconds: 1,
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GameScreen(attempt: attempt, countdownDuration: Duration.zero),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.byKey(const Key('game-end-title')));

    expect(find.byKey(const Key('game-end-title')), findsOneWidget);
  });

  testWidgets('공통 종료 연출 중에도 완료 기록은 즉시 제출한다', (tester) async {
    final repository = _CompletedScoreRepository();
    const attempt = PlayAttempt(
      id: 'attempt-transition-submit',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: GameScreen(
            attempt: attempt,
            gameDuration: Duration(milliseconds: 100),
            countdownDuration: Duration.zero,
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.byKey(const Key('game-end-title')));

    expect(find.byKey(const Key('game-end-title')), findsOneWidget);
    expect(repository.submittedAttemptId, 'attempt-transition-submit');
    expect(find.byKey(const Key('final-score')), findsNothing);
  });

  testWidgets('게임 ID가 중력 스위치면 전용 게임과 HUD를 실행한다', (tester) async {
    const attempt = PlayAttempt(
      id: 'attempt-gravity',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
      gameId: 'gravity_switch',
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GameScreen(
            attempt: attempt,
            countdownDuration: Duration(seconds: 3),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('탭해서 중력을 뒤집고 반대편으로 이동하세요'), findsOneWidget);
    expect(find.byKey(const Key('survival-time')), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('0.00초'), findsNothing);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('SURVIVE'), findsNothing);
  });

  testWidgets('사과 HUD 나가기 아이콘과 사과 개수는 같은 높이에 표시된다', (tester) async {
    const attempt = PlayAttempt(
      id: 'attempt-apple-hud',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
      gameId: 'apple_game_v2',
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GameScreen(
            attempt: attempt,
            countdownDuration: Duration(seconds: 3),
          ),
        ),
      ),
    );

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final exitIcon = find.byKey(const Key('game-exit-icon'));
    final appleScore = find.byKey(const Key('apple-hud-score'));
    expect(exitIcon, findsOneWidget);
    expect(appleScore, findsOneWidget);
    expect(tester.getCenter(appleScore).dy - tester.getCenter(exitIcon).dy, 1);
  });

  testWidgets('엄마 어디가 HUD는 LIVES 아래에 오리 얼굴 목숨을 표시한다', (tester) async {
    const attempt = PlayAttempt(
      id: 'attempt-mama-duck-hud',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
      gameId: 'mama_duck_trail',
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GameScreen(
            attempt: attempt,
            countdownDuration: Duration(seconds: 3),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 32));

    final score = find.byKey(const Key('mama-hud-score'));
    final time = find.byKey(const Key('mama-hud-time'));
    final livesLabel = find.byKey(const Key('mama-hud-lives-label'));
    expect(score, findsOneWidget);
    expect(time, findsOneWidget);
    expect(livesLabel, findsOneWidget);
    for (var index = 0; index < 3; index++) {
      final life = find.byKey(Key('mama-duck-life-$index'));
      expect(life, findsOneWidget);
      expect(tester.widget<Opacity>(life).opacity, 1);
      final image = tester.widget<Image>(
        find.descendant(of: life, matching: find.byType(Image)),
      );
      expect(image.width, 48);
      expect(image.height, 48);
      expect(
        tester.getCenter(life).dy,
        greaterThan(tester.getCenter(livesLabel).dy),
      );
      expect(
        tester.getCenter(life).dx,
        inExclusiveRange(tester.getCenter(score).dx, tester.getCenter(time).dx),
      );
    }
    final lives = [
      for (var index = 0; index < 3; index++)
        tester.getRect(find.byKey(Key('mama-duck-life-$index'))),
    ];
    expect(lives[1].center.dx - lives[0].center.dx, 24);
    expect(lives[2].center.dx - lives[1].center.dx, 24);
    expect(lives.last.right - lives.first.left, 96);
    expect(
      (lives.first.left + lives.last.right) / 2,
      closeTo(tester.getCenter(livesLabel).dx, 0.01),
    );
  });

  testWidgets('넘버러시는 게임기 하단의 전용 EXIT 버튼을 사용한다', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    const attempt = PlayAttempt(
      id: 'attempt-number-rush-exit',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
      gameId: 'number_rush',
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GameScreen(
            attempt: attempt,
            countdownDuration: Duration(seconds: 3),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();

    final exitButton = find.byKey(const Key('game-exit-button'));
    final exitImage = find.byKey(const Key('number-rush-exit-image'));
    expect(find.byKey(const Key('game-exit-icon')), findsNothing);
    expect(exitButton, findsOneWidget);
    expect(exitImage, findsOneWidget);
    expect(tester.getTopLeft(exitButton), const Offset(30, 523));
    expect(tester.getSize(exitButton), const Size(62, 56));
    expect(tester.getTopLeft(exitImage), const Offset(33, 523));
    expect(tester.getSize(exitImage), const Size.square(56));

    final gesture = await tester.startGesture(tester.getCenter(exitButton));
    await tester.pump();
    expect(
      (tester.widget<Image>(exitImage).image as AssetImage).assetName,
      'assets/images/number_rush/exit_button_pressed.png',
    );
    await gesture.up();
    await tester.pump();
    expect(
      (tester.widget<Image>(exitImage).image as AssetImage).assetName,
      'assets/images/number_rush/exit_button_idle.png',
    );
  });

  testWidgets('똥피하기는 생존 시간을 한 번만 표시한다', (tester) async {
    const attempt = PlayAttempt(
      id: 'attempt-dung-dodge-hud',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
      gameId: 'dung_dodge_v2',
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: GameScreen(
            attempt: attempt,
            countdownDuration: Duration(seconds: 3),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 32));

    expect(find.byKey(const Key('survival-time')), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
    expect(find.text('0.00초'), findsNothing);
    expect(find.text('SURVIVE'), findsNothing);
  });

  testWidgets('똥피하기 생존 시간을 ms 단위로 서버에 제출한다', (tester) async {
    final repository = _CompletedScoreRepository();
    const attempt = PlayAttempt(
      id: 'attempt-score',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: GameScreen(
            attempt: attempt,
            gameDuration: Duration(milliseconds: 100),
            countdownDuration: Duration.zero,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(repository.submittedAttemptId, 'attempt-score');
    expect(repository.submittedResult?.score, 100);
    expect(repository.submittedResult?.duration.inMilliseconds, 100);
  });

  testWidgets('백그라운드로 전환되면 게임을 중단하고 시도를 소진한다', (tester) async {
    final repository = _RecordingRepository();
    const attempt = PlayAttempt(
      id: 'attempt-1',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GameScreen(attempt: attempt)),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.byKey(const Key('interrupted-title')), findsOneWidget);
    expect(repository.expiredAttemptIds, ['attempt-1']);
  });

  testWidgets('게임에서 홈으로 돌아오면 오늘 플레이 상태를 다시 불러온다', (tester) async {
    final repository = _HomeRefreshRepository();
    final container = ProviderContainer(
      overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(todayStateProvider.future);
    expect(repository.fetchTodayCalls, 1);

    const attempt = PlayAttempt(
      id: 'attempt-home-refresh',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
    );
    final router = GoRouter(
      initialLocation: '/play',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Consumer(
            builder: (context, ref, child) {
              final today = ref.watch(todayStateProvider);
              return Material(
                child: Center(
                  child: today.when(
                    data: (state) =>
                        Text(state.canClaimDaily ? 'available' : 'exhausted'),
                    error: (error, stackTrace) => const Text('error'),
                    loading: () => const Text('loading'),
                  ),
                ),
              );
            },
          ),
        ),
        GoRoute(
          path: '/play',
          builder: (context, state) => const GameScreen(attempt: attempt),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    final exitButton = find.byKey(const Key('game-exit-button'));
    final exitIcon = find.byKey(const Key('game-exit-icon'));
    expect(exitIcon, findsOneWidget);
    expect(tester.getSize(exitButton), const Size.square(48));
    expect(tester.getSize(exitIcon), const Size.square(32));
    expect(tester.getTopLeft(exitButton), const Offset(8, 13));
    expect(tester.getTopLeft(exitIcon), const Offset(16, 29));

    await tester.tap(exitButton);
    await tester.pump();

    expect(find.text('exhausted'), findsNothing);
    expect(repository.fetchTodayCalls, 1);

    await tester.longPress(exitButton);
    await tester.pumpAndSettle();

    expect(find.text('exhausted'), findsOneWidget);
    expect(repository.fetchTodayCalls, 2);
  });

  testWidgets('첫 정상 완료 후 닉네임 입력창을 자동으로 보여준다', (tester) async {
    final repository = _NicknameRepository();
    const attempt = PlayAttempt(
      id: 'attempt-nickname',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: GameScreen(
            attempt: attempt,
            gameDuration: Duration(milliseconds: 100),
            countdownDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.text('랭킹 닉네임'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('nickname-field')), '별하나');
    await tester.tap(find.byKey(const Key('save-nickname')));
    await tester.pumpAndSettle();

    expect(repository.savedNickname, '별하나');
    expect(find.text('별하나'), findsOneWidget);
  });

  testWidgets('제출 실패 후 사용자가 즉시 재시도할 수 있다', (tester) async {
    final repository = _FlakyRepository();
    const attempt = PlayAttempt(
      id: 'attempt-retry',
      ordinal: 1,
      status: 'issued',
      grantType: 'daily',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: GameScreen(
            attempt: attempt,
            gameDuration: Duration(milliseconds: 100),
            countdownDuration: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.text('지금 다시 전송'), findsOneWidget);
    await tester.tap(find.text('지금 다시 전송'));
    await tester.pumpAndSettle();

    expect(repository.submitCalls, 2);
    expect(find.byKey(const Key('daily-rank')), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _RecordingRepository implements DailyGameRepository {
  final expiredAttemptIds = <String>[];

  @override
  Future<void> expireAttempt(String attemptId) async {
    expiredAttemptIds.add(attemptId);
  }

  @override
  Future<PlayAttempt> claimDailyAttempt(DateTime expectedPlayDate) =>
      throw UnimplementedError();

  @override
  Future<RewardedAdSession> prepareRewardedAd(DateTime expectedPlayDate) =>
      throw UnimplementedError();

  @override
  Future<PlayAttempt> claimRewardedAttempt(String rewardSessionId) =>
      throw UnimplementedError();

  @override
  Future<RewardedAdSession> preparePracticeAd(DateTime expectedPlayDate) =>
      throw UnimplementedError();

  @override
  Future<PlayAttempt> claimPracticeAttempt(String rewardSessionId) =>
      throw UnimplementedError();

  @override
  Future<TodayState> fetchToday() => throw UnimplementedError();

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() => throw UnimplementedError();

  @override
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult() =>
      throw UnimplementedError();

  @override
  Future<RewardGrant> acknowledgePreviousDailyResult(
    DateTime playDate,
    String gameId,
  ) => throw UnimplementedError();

  @override
  Future<CoinSpendResult> spendCoins({
    required int amount,
    required String gameId,
    required String referenceId,
  }) => throw UnimplementedError();

  @override
  Future<List<DeveloperGame>> fetchDeveloperGames() =>
      throw UnimplementedError();

  @override
  Future<void> reportNickname(String userId) => throw UnimplementedError();

  @override
  Future<void> blockUser(String userId) => throw UnimplementedError();

  @override
  Future<void> deleteAccount() => throw UnimplementedError();

  @override
  Future<TesterActivationResult> activateTestMode(String pin) =>
      throw UnimplementedError();

  @override
  Future<void> deactivateTestMode() => throw UnimplementedError();

  @override
  Future<void> resetDeveloperDailyProgress() => throw UnimplementedError();

  @override
  Future<void> setDeveloperGame(String gameId) => throw UnimplementedError();

  @override
  Future<DailyRankResult> submitScore(String attemptId, GameResult result) =>
      throw UnimplementedError();

  @override
  Future<DailyRankResult?> retryPendingScore() => throw UnimplementedError();

  @override
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) =>
      throw UnimplementedError();

  @override
  Future<void> setNickname(String nickname) => throw UnimplementedError();
}

class _HomeRefreshRepository extends _RecordingRepository {
  var fetchTodayCalls = 0;
  var expired = false;

  @override
  Future<TodayState> fetchToday() async {
    fetchTodayCalls++;
    return TodayState(
      playDate: DateTime(2026, 7, 26),
      game: const TodayGame(
        id: 'dung_dodge_v2',
        version: 1,
        displayName: '똥피하기',
        description: '테스트',
        durationSeconds: 300,
      ),
      attempts: expired
          ? const [
              PlayAttempt(
                id: 'attempt-home-refresh',
                ordinal: 1,
                status: 'expired',
                grantType: 'daily',
              ),
            ]
          : const [],
      adAttemptAvailable: false,
      testMode: false,
      result: null,
      nickname: null,
    );
  }

  @override
  Future<void> expireAttempt(String attemptId) async {
    expired = true;
    await super.expireAttempt(attemptId);
  }
}

class _NicknameRepository extends _RecordingRepository {
  String? savedNickname;

  @override
  Future<DailyRankResult> submitScore(
    String attemptId,
    GameResult result,
  ) async {
    return const DailyRankResult(
      score: 600,
      rank: 1,
      participants: 1,
      topPercent: 100,
      nickname: null,
      nearby: [NearbyRank(rank: 1, nickname: '이름 미설정', score: 600, isMe: true)],
    );
  }

  @override
  Future<void> setNickname(String nickname) async {
    savedNickname = nickname;
  }

  @override
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async {
    return DailyRankResult(
      score: 600,
      rank: 1,
      participants: 1,
      topPercent: 100,
      nickname: savedNickname,
      nearby: [
        NearbyRank(
          rank: 1,
          nickname: savedNickname ?? '이름 미설정',
          score: 600,
          isMe: true,
        ),
      ],
    );
  }
}

class _CompletedScoreRepository extends _RecordingRepository {
  String? submittedAttemptId;
  GameResult? submittedResult;

  @override
  Future<DailyRankResult> submitScore(
    String attemptId,
    GameResult result,
  ) async {
    submittedAttemptId = attemptId;
    submittedResult = result;
    return DailyRankResult(
      score: result.score,
      rank: 1,
      participants: 1,
      topPercent: 100,
      nickname: '테스트',
      nearby: const [],
    );
  }
}

class _FlakyRepository extends _RecordingRepository {
  var submitCalls = 0;

  @override
  Future<DailyRankResult> submitScore(
    String attemptId,
    GameResult result,
  ) async {
    submitCalls += 1;
    if (submitCalls == 1) throw Exception('network unavailable');
    return const DailyRankResult(
      score: 600,
      rank: 1,
      participants: 1,
      topPercent: 100,
      nickname: '테스트',
      nearby: [],
    );
  }
}

class _PreloadTrackingRewardedAdService extends FakeRewardedAdService {
  var preloadCalls = 0;

  @override
  Future<void> preload() async {
    preloadCalls++;
    await super.preload();
  }
}
