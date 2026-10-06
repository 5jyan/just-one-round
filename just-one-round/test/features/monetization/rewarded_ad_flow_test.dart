import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/core/auth/kakao_auth_service.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_session.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:postgrest/postgrest.dart';

void main() {
  testWidgets('연습권 광고를 끝까지 보면 두 장을 받고 게임은 시작하지 않는다', (tester) async {
    final repository = _PracticeTicketRepository()..pendingOnce = true;
    final adService = _RecordingRewardedAdService();
    await _pumpRewardFlow(tester, repository, adService);

    final rewardButton = find.text('티켓 받기 +2');
    await tester.ensureVisible(rewardButton);
    await tester.tap(rewardButton);
    for (
      var frame = 0;
      frame < 20 &&
          find.byKey(const Key('practice-ticket-delta')).evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('+2'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(repository.prepareCalls, 1);
    expect(repository.claimedSessionIds, [
      'practice-ticket-session',
      'practice-ticket-session',
    ]);
    expect(adService.showCalls, 1);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('연습권 2장을 받았어요!'), findsOneWidget);
  });

  testWidgets('이미 검증된 연습권 보상은 광고를 다시 보여주지 않고 복구한다', (tester) async {
    final repository = _PracticeTicketRepository();
    final adService = _RecordingRewardedAdService();
    await _pumpRewardFlow(tester, repository, adService);

    final rewardButton = find.text('티켓 받기 +2');
    await tester.ensureVisible(rewardButton);
    await tester.tap(rewardButton);
    await tester.pumpAndSettle();

    expect(repository.prepareCalls, 1);
    expect(repository.claimedSessionIds, ['practice-ticket-session']);
    expect(adService.showCalls, 0);
    expect(find.text('연습권 2장을 받았어요!'), findsOneWidget);
  });

  testWidgets('광고를 닫으면 연습권을 지급하지 않는다', (tester) async {
    final repository = _PracticeTicketRepository()..pendingOnce = true;
    final adService = _RecordingRewardedAdService(
      outcome: RewardedAdOutcome.dismissed,
    );
    await _pumpRewardFlow(tester, repository, adService);

    final rewardButton = find.text('티켓 받기 +2');
    await tester.ensureVisible(rewardButton);
    await tester.tap(rewardButton);
    await tester.pumpAndSettle();

    expect(adService.showCalls, 1);
    expect(repository.claimedSessionIds, ['practice-ticket-session']);
    expect(find.text('광고를 끝까지 보면 연습권 2장을 받아요.'), findsOneWidget);
  });

  testWidgets('로컬 검증은 테스트 광고 완료를 SSV 확인으로 전환한다', (tester) async {
    final repository = _LocalPracticeTicketRepository();
    final adService = _RecordingRewardedAdService();
    await _pumpRewardFlow(tester, repository, adService);

    final rewardButton = find.text('티켓 받기 +2');
    await tester.ensureVisible(rewardButton);
    await tester.tap(rewardButton);
    await tester.pumpAndSettle();

    expect(repository.localVerificationCalls, 1);
    expect(repository.claimedSessionIds, [
      'practice-ticket-session',
      'practice-ticket-session',
    ]);
    expect(find.text('연습권 2장을 받았어요!'), findsOneWidget);
  });
}

Future<void> _pumpRewardFlow(
  WidgetTester tester,
  _PracticeTicketRepository repository,
  _RecordingRewardedAdService adService,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dailyGameRepositoryProvider.overrideWithValue(repository),
        rewardedAdServiceProvider.overrideWithValue(adService),
        kakaoAuthServiceProvider.overrideWithValue(
          const _UnlinkedKakaoAuthService(),
        ),
      ],
      child: const JustOneRoundApp(),
    ),
  );
  await tester.pumpAndSettle();
}

class _PracticeTicketRepository extends PreviewDailyGameRepository {
  var prepareCalls = 0;
  var pendingOnce = false;
  final claimedSessionIds = <String>[];

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 8, 15),
    game: const TodayGame(
      id: 'dung_dodge_v2',
      version: 1,
      displayName: '똥피하기',
      description: '테스트',
      durationSeconds: 300,
    ),
    attempts: const [],
    adAttemptAvailable: false,
    dailyClaimed: true,
    playCount: 1,
    challengeAvailable: true,
    practiceAvailable: false,
    practiceTicketCapacity: 1,
    practiceTicketsRemaining: 0,
    practiceRewardAvailable: true,
    practiceRewardEarned: false,
    nextPlayRequiresAd: false,
    challengeRequiresAd: false,
    practiceRequiresAd: false,
    testMode: false,
    result: null,
    nickname: '테스터',
  );

  @override
  Future<RewardedAdSession> preparePracticeAd(DateTime expectedPlayDate) async {
    prepareCalls++;
    return RewardedAdSession(
      id: 'practice-ticket-session',
      userId: 'user-id',
      status: 'prepared',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<int> claimPracticeTicketReward(String rewardSessionId) async {
    claimedSessionIds.add(rewardSessionId);
    if (pendingOnce && claimedSessionIds.length == 1) {
      throw const PostgrestException(message: 'reward verification pending');
    }
    return 2;
  }
}

class _LocalPracticeTicketRepository extends _PracticeTicketRepository
    implements LocalPracticeAdVerificationRepository {
  var localVerificationCalls = 0;
  var locallyVerified = false;

  @override
  Future<int> claimPracticeTicketReward(String rewardSessionId) async {
    claimedSessionIds.add(rewardSessionId);
    if (!locallyVerified) {
      throw const PostgrestException(message: 'reward verification pending');
    }
    return 2;
  }

  @override
  Future<void> verifyLocalPracticeAd(String rewardSessionId) async {
    localVerificationCalls++;
    locallyVerified = true;
  }

  @override
  Future<void> verifyLocalCoinAd(String rewardSessionId) async {}

  @override
  Future<void> verifyLocalRewardedAd(String rewardSessionId) async {}
}

class _RecordingRewardedAdService extends FakeRewardedAdService {
  _RecordingRewardedAdService({super.outcome});

  var showCalls = 0;

  @override
  Future<RewardedAdOutcome> show({
    required String userId,
    required String verificationSessionId,
  }) async {
    showCalls++;
    return super.show(
      userId: userId,
      verificationSessionId: verificationSessionId,
    );
  }
}

class _UnlinkedKakaoAuthService implements KakaoAuthService {
  const _UnlinkedKakaoAuthService();

  @override
  bool get isConfigured => true;

  @override
  bool get isLinked => false;

  @override
  Future<KakaoAccountLinkResult> linkAccount() async =>
      KakaoAccountLinkResult.linked;
}
