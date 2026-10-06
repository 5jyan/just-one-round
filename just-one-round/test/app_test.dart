import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/core/update/app_update_reward.dart';
import 'package:just_one_round/core/update/critical_ota_update.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/daily_reset.dart';
import 'package:just_one_round/features/economy/domain/economy_transaction.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/today/domain/previous_daily_result.dart';
import 'package:just_one_round/features/today/domain/tester_activation_result.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/social/domain/social_notification.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  test('시뮬레이터용 저장소는 tester 계정으로 동작한다', () async {
    final repository = PreviewDailyGameRepository(testMode: true);

    final state = await repository.fetchToday();

    expect(state.testMode, isTrue);
    expect(state.nickname, 'tester');
    expect(state.canClaimDaily, isTrue);
    expect(state.result?.leaders, hasLength(4));
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

  test('시뮬레이터의 빙글개굴은 v5 150초 계약을 사용한다', () async {
    final repository = PreviewDailyGameRepository(
      testMode: true,
      initialGameId: 'lily_frog',
    );

    final state = await repository.fetchToday();
    final attempt = await repository.claimDailyAttempt(state.playDate);

    expect(state.game?.version, 5);
    expect(state.game?.durationSeconds, 150);
    expect(attempt.gameVersion, 5);
    expect(attempt.gameDurationSeconds, 150);
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
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('똥피하기'), findsOneWidget);
    expect(find.textContaining('오늘 비교 기록'), findsNothing);
    expect(find.textContaining('현재 최고'), findsNothing);
    expect(find.text('연습하기'), findsOneWidget);
    expect(find.byKey(const Key('practice-ticket-badge')), findsOneWidget);
    expect(find.text('오늘의 도전!'), findsOneWidget);
    expect(find.byKey(const Key('economy-summary')), findsNothing);
    expect(find.byKey(const Key('game-guide-button')), findsOneWidget);
    expect(find.byKey(const Key('ranking-button')), findsOneWidget);
    expect(find.byKey(const Key('app-update-reward-dialog')), findsNothing);
  });

  testWidgets('활성화된 업데이트 캠페인은 도전권 지급 팝업을 한 번 보여준다', (tester) async {
    final repository = _UpdateRewardRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.claimCalls, 1);
    expect(find.byKey(const Key('app-update-reward-dialog')), findsOneWidget);
    expect(find.text('업데이트 감사 보상'), findsOneWidget);
    expect(find.textContaining('도전권 1장이 지급되었어요!'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-update-reward-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-update-reward-dialog')), findsNothing);
  });

  testWidgets('내일 게임을 열면 연습권은 공유하고 도전만 막는다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tomorrow-selector')));
    await tester.pumpAndSettle();

    expect(find.text('내일의 게임'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
    expect(find.text('중력 스위치'), findsOneWidget);
    expect(find.text('연습하기'), findsOneWidget);
    expect(find.text('내일 도전 대기'), findsOneWidget);
    expect(find.textContaining('오늘과 공유하는 연습권 1장'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('challenge-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('challenge-button')));
    await tester.pump();
    expect(find.text('내일의 도전은 내일부터 시작할 수 있어요.'), findsOneWidget);
  });

  testWidgets('중요 OTA 패치가 준비되면 재실행 안내로 진입을 차단한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          criticalOtaUpdateServiceProvider.overrideWithValue(
            const PreviewCriticalOtaUpdateService(
              message: '새 패치를 적용하려면 앱을 다시 열어주세요.',
            ),
          ),
        ],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('critical-ota-restart-screen')),
      findsOneWidget,
    );
    expect(find.text('앱을 종료한 뒤\n다시 열어주세요'), findsOneWidget);
    expect(find.text('새 패치를 적용하려면 앱을 다시 열어주세요.'), findsOneWidget);
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

  testWidgets('강제 업데이트가 OTA 재실행 안내보다 우선한다', (tester) async {
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
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(repository),
          criticalOtaUpdateServiceProvider.overrideWithValue(
            const PreviewCriticalOtaUpdateService(
              message: '새 패치를 적용하려면 앱을 다시 열어주세요.',
            ),
          ),
        ],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('required-update-screen')), findsOneWidget);
    expect(find.byKey(const Key('critical-ota-restart-screen')), findsNothing);
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
    expect(find.text('4개'), findsNothing);
    expect(find.text('참여 기록'), findsNothing);
    expect(find.text('현재 최고'), findsNothing);
    expect(find.text('내 순위'), findsNothing);
    expect(find.text('TOP SCORES'), findsOneWidget);
    expect(find.textContaining('NPC'), findsNothing);
    expect(find.text('REAL PLAYERS'), findsNothing);
    expect(find.text('실제 기록'), findsNothing);
    expect(find.text('작은공룡'), findsOneWidget);
    expect(find.text('5.39초'), findsOneWidget);
    expect(find.text('전체'), findsNothing);
    expect(find.text('전체 랭킹'), findsOneWidget);
    expect(find.text('내 주변 랭킹'), findsNothing);
    expect(find.byKey(const Key('overall-leaderboard')), findsOneWidget);
    expect(find.byKey(const Key('nearby-leaderboard')), findsNothing);
    expect(find.byKey(const Key('leaderboard-gap')), findsNothing);
    expect(find.byTooltip('사용자 신고 또는 차단'), findsNothing);
    expect(find.byKey(const Key('rank-more-preview-user-1')), findsOneWidget);
    expect(find.byTooltip('상호작용'), findsWidgets);
    expect(find.byKey(const Key('my-leaderboard-rank')), findsOneWidget);
    expect(find.byKey(const Key('my-rank-badge')), findsOneWidget);
    expect(find.byKey(const Key('leaderboard-level-4')), findsOneWidget);
    expect(find.text('LV.1'), findsWidgets);
    expect(
      tester.getSize(find.byKey(const Key('my-leaderboard-rank'))).height,
      greaterThanOrEqualTo(74),
    );
    expect(find.text('tester'), findsWidgets);
    expect(find.text('졸린감자'), findsOneWidget);
    expect(find.text('한번만더'), findsOneWidget);
    expect(find.text('4등'), findsNothing);
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

    expect(repository.rankFetchCalls, 2);
    expect(repository.requestedPlayDate, isNotNull);
    expect(find.text('31개'), findsNothing);
    expect(find.text('최신랭커'), findsOneWidget);
  });

  testWidgets('지난 1등은 오늘 랭킹과 분리해 표시한다', (tester) async {
    final repository = _HistoricalRankingRepository(
      const DailyRankResult(
        score: null,
        rank: null,
        participants: 1,
        topPercent: null,
        nickname: null,
        nearby: [],
        leaders: [
          NearbyRank(
            rank: 1,
            nickname: '지난랭커',
            score: 4900,
            isMe: false,
            level: 6,
            nicknameColor: 'mint',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ranking-button')));
    await tester.tap(find.byKey(const Key('ranking-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('previous-winner-card')), findsOneWidget);
    expect(find.text('지난 1등'), findsOneWidget);
    expect(find.text('지난랭커'), findsOneWidget);
    expect(find.text('LV.6'), findsOneWidget);
    expect(find.text('작은공룡'), findsOneWidget);
    expect(find.byKey(const Key('overall-leaderboard')), findsOneWidget);
  });

  testWidgets('지난 1등이 비어도 오늘 랭킹은 계속 표시한다', (tester) async {
    final repository = _HistoricalRankingRepository(
      const DailyRankResult(
        score: null,
        rank: null,
        participants: 0,
        topPercent: null,
        nickname: null,
        nearby: [],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ranking-button')));
    await tester.tap(find.byKey(const Key('ranking-button')));
    await tester.pumpAndSettle();

    expect(find.text('지난 1등 기록이 없어요.'), findsOneWidget);
    expect(find.text('작은공룡'), findsOneWidget);
  });

  testWidgets('지난 1등 조회 오류가 오늘 랭킹을 막지 않는다', (tester) async {
    final repository = _HistoricalRankingRepository(null, failPrevious: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('ranking-button')));
    await tester.tap(find.byKey(const Key('ranking-button')));
    await tester.pumpAndSettle();

    expect(find.text('지난 1등을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('작은공룡'), findsOneWidget);
  });

  testWidgets('랭킹 유저 액션은 앱 스타일 바텀시트를 연다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    final rankingButton = find.byKey(const Key('ranking-button'));
    await tester.ensureVisible(rankingButton);
    await tester.tap(rankingButton);
    await tester.pumpAndSettle();
    final interactionButton = find.byKey(const Key('rank-more-preview-user-1'));
    await tester.ensureVisible(interactionButton);
    await tester.tap(interactionButton);
    await tester.pumpAndSettle();

    expect(find.text('RANKING PLAYER'), findsOneWidget);
    expect(find.text('작은공룡'), findsWidgets);
    expect(find.byKey(const Key('rank-action-poke')), findsOneWidget);
    expect(find.byKey(const Key('rank-action-boast')), findsOneWidget);
    expect(find.byKey(const Key('rank-action-gift')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rank-action-gift')));
    await tester.pumpAndSettle();
    expect(find.text('SEND A GIFT'), findsOneWidget);
    expect(find.text('연습권 1장'), findsOneWidget);
    expect(find.text('도전권 1장'), findsOneWidget);
    expect(find.text('닉네임 색상권 1장'), findsNothing);
  });

  testWidgets('찌르기·자랑하기·선물하기 성공 후 완료 팝업을 표시한다', (tester) async {
    final repository = PreviewDailyGameRepository(
      initialEconomy: PlayerEconomy.fromTotals(
        coins: 1000,
        experiencePoints: 0,
      ),
    );
    await repository.purchaseShopItem(
      itemId: 'practice_ticket',
      requestId: 'social-popup-test',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openActions() async {
      await tester.ensureVisible(find.byKey(const Key('ranking-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ranking-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rank-more-preview-user-1')));
      await tester.pumpAndSettle();
    }

    await openActions();
    await tester.tap(find.byKey(const Key('rank-action-poke')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('social-poke-completed')), findsOneWidget);
    expect(find.text('작은공룡님을 찔렀어요.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('social-poke-completed-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ranking-sheet-close')));
    await tester.pumpAndSettle();

    await openActions();
    await tester.tap(find.byKey(const Key('rank-action-boast')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('social-boast-completed')), findsOneWidget);
    expect(find.text('작은공룡님에게 내 순위를 자랑했어요.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('social-boast-completed-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ranking-sheet-close')));
    await tester.pumpAndSettle();

    await openActions();
    await tester.tap(find.byKey(const Key('rank-action-gift')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('연습권 1장'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('social-gift-completed')), findsOneWidget);
    expect(find.text('작은공룡님에게 연습권 1장을 선물했어요.'), findsOneWidget);
  });

  testWidgets('찌르기·자랑하기 횟수 제한은 앱 스타일 팝업으로 안내한다', (tester) async {
    final repository = _LimitedSocialRepository([
      'daily poke limit reached',
      'daily boast limit reached',
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openActions() async {
      await tester.ensureVisible(find.byKey(const Key('ranking-button')));
      await tester.tap(find.byKey(const Key('ranking-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rank-more-preview-user-1')));
      await tester.pumpAndSettle();
    }

    await openActions();
    await tester.tap(find.byKey(const Key('rank-action-poke')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('social-poke-error')), findsOneWidget);
    expect(find.text('오늘 찌르기는 3번까지 보낼 수 있어요.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const Key('social-poke-error-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ranking-sheet-close')));
    await tester.pumpAndSettle();

    await openActions();
    await tester.tap(find.byKey(const Key('rank-action-boast')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('social-boast-error')), findsOneWidget);
    expect(find.text('오늘 자랑하기는 3번까지 보낼 수 있어요.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('소셜 알림 팝업은 게임 중 보류하고 로비 복귀 후 표시한다', (tester) async {
    final repository = _DeferredSocialInboxRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    final startButton = find.byKey(const Key('challenge-button'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await _pumpUntilFound(tester, find.byKey(const Key('game-start-guide')));
    await tester.tap(find.byKey(const Key('game-start-guide-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    repository.exposeNotification = true;
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const Key('social-notification-confirm-button')),
      findsNothing,
    );

    await tester.ensureVisible(find.byKey(const Key('game-exit-button')));
    await tester.tap(find.byKey(const Key('game-exit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-game-exit-button')));
    await tester.pumpAndSettle();

    await _pumpUntilFound(
      tester,
      find.byKey(const Key('social-notification-confirm-button')),
    );
    expect(
      find.byKey(const Key('social-notification-confirm-button')),
      findsOneWidget,
    );
  });

  testWidgets('도전권 선물을 확인하면 도전 버튼을 활성화한다', (tester) async {
    final repository = _ChallengeTicketGiftRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    final challengeButton = find.byKey(const Key('challenge-button'));
    expect(tester.widget<PixelButton>(challengeButton).onPressed, isNull);
    expect(
      find.byKey(const Key('social-notification-confirm-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('social-notification-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.giftAcknowledged, isTrue);
    expect(tester.widget<PixelButton>(challengeButton).onPressed, isNotNull);
    expect(find.byKey(const Key('challenge-ticket-badge')), findsOneWidget);
  });

  testWidgets('시작 버튼으로 게임 화면에 진입한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    final startButton = find.byKey(const Key('challenge-button'));
    await tester.ensureVisible(startButton);
    await tester.pump();
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await _pumpUntilFound(tester, find.byKey(const Key('game-start-guide')));
    expect(find.byKey(const Key('game-start-guide')), findsOneWidget);
    await tester.tap(find.byKey(const Key('game-start-guide-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('SURVIVE'), findsNothing);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.byKey(const Key('survival-time')), findsOneWidget);
    expect(find.text('손가락을 움직인 만큼 캐릭터가 좌우로 따라가요'), findsOneWidget);
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
    final startButton = find.byKey(const Key('challenge-button'));
    await tester.ensureVisible(startButton);
    await tester.pump();
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('오늘의 게임이 바뀌었어요'), findsOneWidget);
    expect(find.text('날짜가 바뀌어 새로운 게임을 불러올게요.'), findsOneWidget);
    expect(repository.claimCalls, 0);

    await tester.tap(find.byKey(const Key('load-new-daily-game-button')));
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
    expect(find.text('+80'), findsNWidgets(2));
    expect(find.textContaining('기본 +30 C'), findsOneWidget);
    expect(
      find.byKey(const Key('previous-result-reward-help')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('previous-result-reward-help')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('daily-reward-rules-dialog')), findsOneWidget);
    expect(find.text('매일 보상 기준'), findsOneWidget);
    expect(find.text('이번 기록'), findsOneWidget);
    expect(find.text('8위 · 상위 34%'), findsOneWidget);
    expect(find.text('+30 C · +30 EXP'), findsOneWidget);
    expect(find.text('+250 보너스'), findsOneWidget);
    expect(find.text('총 +280 C · +280 EXP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('daily-reward-rules-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('daily-reward-rules-dialog')), findsNothing);

    await tester.tap(find.byKey(const Key('acknowledge-previous-result')));
    await tester.pumpAndSettle();

    expect(repository.acknowledged, isTrue);
    expect(repository.acknowledgedDate, DateTime(2026, 7, 26));
    expect(repository.acknowledgedGameId, 'dung_dodge_v2');
    expect(find.byKey(const Key('previous-daily-result-dialog')), findsNothing);
    expect(find.text('+80 코인 · +80 EXP를 받았어요!'), findsNothing);
  });

  testWidgets('전날 결과의 랭킹 보기는 해당 날짜의 전체 랭킹을 연다', (tester) async {
    final repository = _PreviousResultRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('랭킹 보기'), findsOneWidget);
    expect(find.text('내 기록 보기'), findsNothing);
    await tester.tap(find.byKey(const Key('previous-result-ranking')));
    await tester.pumpAndSettle();

    expect(repository.acknowledged, isFalse);
    expect(
      repository.requestedRankDates,
      containsAll(<DateTime?>[DateTime(2026, 7, 26), DateTime(2026, 7, 25)]),
    );
    expect(find.text('어제의 랭킹'), findsOneWidget);
    expect(find.byKey(const Key('overall-leaderboard')), findsOneWidget);
    expect(find.byKey(const Key('leaderboard-gap')), findsNothing);

    await tester.tap(find.byKey(const Key('ranking-sheet-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('previous-daily-result-dialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('acknowledge-previous-result')));
    await tester.pumpAndSettle();
    expect(repository.acknowledged, isTrue);
  });

  testWidgets('앱 중단 경고에서 진짜 나가면 홈으로 이동한다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JustOneRoundApp()));
    await tester.pumpAndSettle();

    final startButton = find.byKey(const Key('challenge-button'));
    await tester.ensureVisible(startButton);
    await tester.pump();
    await tester.tap(startButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('game-start-guide-button')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    final exitButton = find.byKey(const Key('confirm-game-exit-button'));
    await tester.ensureVisible(exitButton);
    await tester.pump();
    await tester.tap(exitButton);
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
    expect(find.byKey(const Key('challenge-button')), findsOneWidget);
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
    expect(find.byKey(const Key('legal-menu')), findsOneWidget);
    expect(find.text('정책 및 약관'), findsOneWidget);
    expect(find.text('개인정보처리방침'), findsNothing);
    expect(find.text('서비스 이용약관'), findsNothing);
    expect(find.text('커뮤니티 운영정책'), findsNothing);
    expect(find.byKey(const Key('support-menu')), findsOneWidget);
    expect(find.text('문의하기'), findsOneWidget);
    expect(find.text('앱에서 바로 문의를 남겨요'), findsNothing);
    expect(find.byKey(const Key('social-push-menu')), findsOneWidget);
    expect(find.text('소셜 푸시 알림'), findsOneWidget);
    expect(find.text('찌르기·자랑·선물 알림'), findsNothing);
    expect(find.text('닉네임·코인·경험치·카카오 계정'), findsNothing);
    expect(
      tester.getTopLeft(find.text('프로필')).dy,
      lessThan(tester.getTopLeft(find.text('소셜 푸시 알림')).dy),
    );
    expect(
      tester.getTopLeft(find.text('소셜 푸시 알림')).dy,
      lessThan(tester.getTopLeft(find.text('문의하기')).dy),
    );
    expect(tester.getSize(find.text('소셜 푸시 알림')).height, lessThan(30));
    expect(find.text('광고 개인정보 선택'), findsNothing);
    expect(find.text('앱 버전 1.0.4 (9)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('legal-menu')));
    await tester.pumpAndSettle();
    expect(find.text('개인정보처리방침'), findsOneWidget);
    expect(find.text('서비스 이용약관'), findsOneWidget);
    expect(find.text('커뮤니티 운영정책'), findsOneWidget);
  });

  testWidgets('설정에서 소셜 푸시 알림을 끌 수 있다', (tester) async {
    final repository = _SocialSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('social-push-menu')));
    await tester.pumpAndSettle();

    expect(repository.enabled, isFalse);
    expect(find.text('소셜 푸시 알림을 껐어요.'), findsOneWidget);
  });

  testWidgets('문의하기는 내용과 앱 버전을 서버에 저장한다', (tester) async {
    final repository = _SupportInquiryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dailyGameRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support-menu')));
    await tester.pumpAndSettle();

    final submitButton = find.byKey(const Key('submit-support-inquiry'));
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('support-inquiry-field')),
      '도전 중에 화면이 멈춰요.',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(repository.message, '도전 중에 화면이 멈춰요.');
    expect(repository.appVersion, '1.0.4');
    expect(repository.buildNumber, 9);
    expect(find.text('문의가 접수됐어요. 운영팀이 확인할게요.'), findsOneWidget);
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
    final developerMenu = find.byKey(const Key('developer-mode-menu'));
    await tester.ensureVisible(developerMenu);
    await tester.tap(developerMenu);
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

class _SupportInquiryRepository extends PreviewDailyGameRepository {
  String? message;
  String? appVersion;
  int? buildNumber;

  @override
  Future<String> submitSupportInquiry({
    required String message,
    required String appVersion,
    required int buildNumber,
  }) async {
    this.message = message;
    this.appVersion = appVersion;
    this.buildNumber = buildNumber;
    return '00000000-0000-4000-8000-000000000005';
  }
}

class _UpdateRewardRepository extends PreviewDailyGameRepository {
  var claimCalls = 0;

  @override
  Future<AppUpdateReward> claimAppUpdateReward() async {
    claimCalls += 1;
    return const AppUpdateReward(
      granted: true,
      ticketsGranted: 1,
      message: '새 버전으로 업데이트해 주셔서 감사해요.',
    );
  }
}

class _SocialSettingsRepository extends PreviewDailyGameRepository {
  bool? enabled;

  @override
  Future<void> setSocialNotificationsEnabled(bool enabled) async {
    this.enabled = enabled;
  }
}

class _DeferredSocialInboxRepository extends PreviewDailyGameRepository {
  var exposeNotification = false;

  @override
  Future<List<SocialNotification>> fetchUnseenSocialNotifications() async {
    if (!exposeNotification) return const [];
    return [
      SocialNotification(
        id: 'deferred-social-notification',
        actionType: 'poke',
        senderNickname: '작은공룡',
        createdAt: DateTime(2026, 8, 26),
      ),
    ];
  }
}

class _ChallengeTicketGiftRepository extends PreviewDailyGameRepository {
  var giftAcknowledged = false;

  @override
  Future<TodayState> fetchToday() async {
    final base = await super.fetchToday();
    final hasGift = giftAcknowledged;
    return TodayState(
      playDate: base.playDate,
      game: base.game,
      attempts: const [],
      adAttemptAvailable: false,
      testMode: false,
      result: base.result,
      nickname: base.nickname,
      dailyClaimed: true,
      practiceAvailable: true,
      playCount: 2,
      challengeAvailable: false,
      adChallengeAvailable: false,
      extraChallengeAvailable: hasGift,
      challengeTicketAvailable: hasGift,
      nextPlayRequiresAd: false,
      challengeRequiresAd: false,
      practiceRequiresAd: false,
      practiceTicketCapacity: 1,
      practiceTicketsRemaining: 1,
      storeChallengeTickets: hasGift ? 1 : 0,
      rankedAdAttemptUsed: true,
      economy: base.economy,
      tomorrow: base.tomorrow,
    );
  }

  @override
  Future<List<SocialNotification>> fetchUnseenSocialNotifications() async => [
    SocialNotification(
      id: 'challenge-ticket-gift',
      actionType: 'gift',
      senderNickname: '작은공룡',
      createdAt: DateTime(2026, 8, 26),
      giftItemId: 'challenge_ticket',
    ),
  ];

  @override
  Future<void> acknowledgeSocialNotifications(List<String> ids) async {
    giftAcknowledged = ids.contains('challenge-ticket-gift');
  }
}

class _LimitedSocialRepository extends PreviewDailyGameRepository {
  _LimitedSocialRepository(this.failures);

  final List<String> failures;

  @override
  Future<void> sendSocialAction({
    required String targetUserId,
    required String action,
  }) async {
    throw StateError(failures.removeAt(0));
  }
}

class _RefreshingRankingRepository extends PreviewDailyGameRepository {
  var rankFetchCalls = 0;
  DateTime? requestedPlayDate;
  final requestedPlayDates = <DateTime?>[];

  @override
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async {
    rankFetchCalls += 1;
    requestedPlayDate = playDate;
    requestedPlayDates.add(playDate);
    if (playDate != null &&
        playDate.isBefore(dailyPlayDateAt(DateTime.now()))) {
      return const DailyRankResult(
        score: null,
        rank: null,
        participants: 1,
        topPercent: null,
        nickname: null,
        nearby: [],
        leaders: [
          NearbyRank(rank: 1, nickname: '지난랭커', score: 4900, isMe: false),
        ],
      );
    }
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

class _HistoricalRankingRepository extends PreviewDailyGameRepository {
  _HistoricalRankingRepository(
    this.previousResult, {
    this.failPrevious = false,
  });

  final DailyRankResult? previousResult;
  final bool failPrevious;

  @override
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async {
    if (playDate != null &&
        playDate.isBefore(dailyPlayDateAt(DateTime.now()))) {
      if (failPrevious) throw StateError('historical ranking failed');
      return previousResult!;
    }
    return (await fetchToday()).result!;
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
  DateTime? requestedRankDate;
  final requestedRankDates = <DateTime?>[];

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
      coinsGranted: 70,
      experienceGranted: 70,
      economy: PlayerEconomy.fromTotals(coins: 70, experiencePoints: 70),
    );
  }

  @override
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async {
    requestedRankDate = playDate;
    requestedRankDates.add(playDate);
    return DailyRankResult(
      score: 12345,
      rank: 8,
      participants: 24,
      topPercent: 34,
      nickname: '플레이어',
      bestScore: 24000,
      nearby: const [],
      leaders: [
        for (var rank = 1; rank <= 24; rank++)
          NearbyRank(
            rank: rank,
            nickname: rank == 8 ? '플레이어' : '랭커$rank',
            score: 25000 - rank * 1000,
            isMe: rank == 8,
          ),
      ],
    );
  }
}
