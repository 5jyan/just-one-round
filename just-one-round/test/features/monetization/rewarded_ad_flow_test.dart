import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_session.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('보상형 광고 완료 뒤 검증 세션으로 두 번째 판을 발급한다', (tester) async {
    final repository = _RewardedFlowRepository();
    final adService = _RecordingRewardedAdService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(repository),
          rewardedAdServiceProvider.overrideWithValue(adService),
        ],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    final rewardedButton = find.text('광고 보고 한 판 더');
    expect(rewardedButton, findsOneWidget);
    await tester.ensureVisible(rewardedButton);
    await tester.pump();
    await tester.tap(rewardedButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.prepareCalls, 1);
    expect(adService.showCalls, 1);
    expect(repository.claimedSessionIds, ['reward-session', 'reward-session']);
  });
}

class _RewardedFlowRepository extends PreviewDailyGameRepository {
  var prepareCalls = 0;
  final claimedSessionIds = <String>[];

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 26),
    game: const TodayGame(
      id: 'dung_dodge_v2',
      version: 1,
      displayName: '똥피하기',
      description: '테스트',
      durationSeconds: 300,
    ),
    attempts: const [
      PlayAttempt(
        id: 'daily-attempt',
        ordinal: 1,
        status: 'completed',
        grantType: 'daily',
        gameId: 'dung_dodge_v2',
      ),
    ],
    adAttemptAvailable: true,
    testMode: false,
    result: const DailyRankResult(
      score: 100,
      rank: 1,
      participants: 1,
      topPercent: 1,
      nickname: '테스터',
      nearby: [],
    ),
    nickname: '테스터',
  );

  @override
  Future<RewardedAdSession> prepareRewardedAd(DateTime expectedPlayDate) async {
    prepareCalls++;
    return RewardedAdSession(
      id: 'reward-session',
      userId: 'user-id',
      status: 'prepared',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<PlayAttempt> claimRewardedAttempt(String rewardSessionId) async {
    claimedSessionIds.add(rewardSessionId);
    if (claimedSessionIds.length == 1) {
      throw const PostgrestException(message: 'reward verification pending');
    }
    return const PlayAttempt(
      id: 'rewarded-attempt',
      ordinal: 2,
      status: 'issued',
      grantType: 'rewarded_ad',
      gameId: 'dung_dodge_v2',
    );
  }
}

class _RecordingRewardedAdService extends FakeRewardedAdService {
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
