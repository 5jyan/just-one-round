import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
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
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('한 판 종료!'), findsOneWidget);
    expect(find.byKey(const Key('final-score')), findsOneWidget);
    expect(find.text('홈으로'), findsOneWidget);
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

    expect(find.text('탭해서 중력을 뒤집으세요'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
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
  Future<List<PlayHistoryEntry>> fetchHistory() => throw UnimplementedError();

  @override
  Future<List<DeveloperGame>> fetchDeveloperGames() =>
      throw UnimplementedError();

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
  Future<DailyRankResult> fetchFilteredRank({
    int? birthDecade,
    ProfileGender? gender,
  }) => throw UnimplementedError();

  @override
  Future<UserProfile> setNickname(String nickname) =>
      throw UnimplementedError();

  @override
  Future<UserProfile> updateDemographics({
    required int? birthYear,
    required int? birthMonth,
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
    return UserProfile(
      nickname: nickname,
      birthYear: null,
      birthMonth: null,
      gender: null,
    );
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
