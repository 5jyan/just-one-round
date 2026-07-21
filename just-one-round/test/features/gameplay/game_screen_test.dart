import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
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
}
