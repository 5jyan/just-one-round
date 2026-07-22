import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  test('복귀 상태를 제외한 모든 앱 상태에서 판을 소진한다', () {
    expect(shouldInterruptGame(AppLifecycleState.resumed), isFalse);
    expect(shouldInterruptGame(AppLifecycleState.inactive), isTrue);
    expect(shouldInterruptGame(AppLifecycleState.hidden), isTrue);
    expect(shouldInterruptGame(AppLifecycleState.paused), isTrue);
    expect(shouldInterruptGame(AppLifecycleState.detached), isTrue);
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

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(find.text('한 판 종료!'), findsOneWidget);
    expect(find.byKey(const Key('final-score')), findsOneWidget);
    expect(find.text('홈으로'), findsOneWidget);
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
}

class _RecordingRepository implements DailyGameRepository {
  final expiredAttemptIds = <String>[];

  @override
  Future<void> expireAttempt(String attemptId) async {
    expiredAttemptIds.add(attemptId);
  }

  @override
  Future<PlayAttempt> claimDailyAttempt() => throw UnimplementedError();

  @override
  Future<PlayAttempt> claimRewardedAttempt() => throw UnimplementedError();

  @override
  Future<TodayState> fetchToday() => throw UnimplementedError();

  @override
  Future<DailyRankResult> submitScore(String attemptId, GameResult result) =>
      throw UnimplementedError();

  @override
  Future<DailyRankResult> fetchFilteredRank({
    int? birthDecade,
    ProfileGender? gender,
  }) => throw UnimplementedError();

  @override
  Future<UserProfile> setNickname(String nickname) =>
      throw UnimplementedError();

  @override
  Future<UserProfile> updateDemographics({
    required int? birthDecade,
    required ProfileGender? gender,
  }) => throw UnimplementedError();
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
  Future<UserProfile> setNickname(String nickname) async {
    savedNickname = nickname;
    return UserProfile(nickname: nickname, birthDecade: null, gender: null);
  }

  @override
  Future<DailyRankResult> fetchFilteredRank({
    int? birthDecade,
    ProfileGender? gender,
  }) async {
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
