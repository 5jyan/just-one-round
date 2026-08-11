import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/app/app.dart';
import 'package:just_one_round/core/auth/kakao_auth_service.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_service.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  testWidgets('첫 플레이에는 연습하기와 도전하기를 함께 표시한다', (tester) async {
    final repository = _ChoiceRepository(_choiceState(playCount: 0));
    final adService = _CountingAdService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(repository),
          rewardedAdServiceProvider.overrideWithValue(adService),
          kakaoAuthServiceProvider.overrideWithValue(
            const _LinkedKakaoAuthService(),
          ),
        ],
        child: const JustOneRoundApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('연습하기'), findsOneWidget);
    expect(find.text('도전하기'), findsOneWidget);

    await tester.ensureVisible(find.text('연습하기'));
    await tester.pump();
    await tester.tap(find.text('연습하기'));
    await tester.pumpAndSettle();

    expect(repository.dailyPracticeClaims, 1);
    expect(adService.showCalls, 0);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('첫 플레이가 연습이면 두 번째에도 두 모드를 표시한다', (tester) async {
    await _pumpChoiceState(
      tester,
      _choiceState(playCount: 1, requiresAd: true),
    );

    expect(find.text('연습하기'), findsOneWidget);
    expect(find.text('도전하기'), findsOneWidget);
  });

  testWidgets('첫 두 플레이가 연습이면 세 번째에는 도전만 표시한다', (tester) async {
    await _pumpChoiceState(
      tester,
      _choiceState(playCount: 2, practiceAvailable: false, requiresAd: true),
    );

    expect(find.text('연습하기'), findsNothing);
    expect(find.text('도전하기'), findsOneWidget);
  });

  testWidgets('도전을 선택한 뒤에는 연습만 표시한다', (tester) async {
    await _pumpChoiceState(
      tester,
      _choiceState(playCount: 1, challengeAvailable: false, requiresAd: true),
    );

    expect(find.text('연습하기'), findsOneWidget);
    expect(find.text('도전하기'), findsNothing);
  });
}

Future<void> _pumpChoiceState(WidgetTester tester, TodayState state) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dailyGameRepositoryProvider.overrideWithValue(_ChoiceRepository(state)),
        rewardedAdServiceProvider.overrideWithValue(_CountingAdService()),
        kakaoAuthServiceProvider.overrideWithValue(
          const _LinkedKakaoAuthService(),
        ),
      ],
      child: const JustOneRoundApp(),
    ),
  );
  await tester.pumpAndSettle();
}

TodayState _choiceState({
  required int playCount,
  bool challengeAvailable = true,
  bool practiceAvailable = true,
  bool requiresAd = false,
}) => TodayState(
  playDate: DateTime(2026, 8, 11),
  game: const TodayGame(
    id: 'dung_dodge_v2',
    version: 1,
    displayName: '똥피하기',
    description: '테스트',
    durationSeconds: 300,
  ),
  attempts: const [],
  adAttemptAvailable: false,
  testMode: false,
  result: null,
  nickname: '테스터',
  dailyClaimed: playCount > 0,
  playCount: playCount,
  challengeAvailable: challengeAvailable,
  practiceAvailable: practiceAvailable,
  nextPlayRequiresAd: requiresAd,
);

class _ChoiceRepository extends PreviewDailyGameRepository {
  _ChoiceRepository(this.state);

  final TodayState state;
  var dailyPracticeClaims = 0;

  @override
  Future<TodayState> fetchToday() async => state;

  @override
  Future<PlayAttempt> claimDailyPractice(DateTime expectedPlayDate) async {
    dailyPracticeClaims++;
    return PlayAttempt(
      id: 'practice-daily-session',
      ordinal: 1,
      status: 'practice',
      grantType: 'practice_daily',
      gameId: state.game?.id,
      gameVersion: state.game?.version,
      gameDurationSeconds: state.game?.durationSeconds,
      playDate: state.playDate,
    );
  }
}

class _CountingAdService extends FakeRewardedAdService {
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

class _LinkedKakaoAuthService implements KakaoAuthService {
  const _LinkedKakaoAuthService();

  @override
  bool get isConfigured => true;

  @override
  bool get isLinked => true;

  @override
  Future<KakaoAccountLinkResult> linkAccount() async =>
      KakaoAccountLinkResult.alreadyLinked;
}
