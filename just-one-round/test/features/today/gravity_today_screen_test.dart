import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/presentation/today_screen.dart';

void main() {
  testWidgets('중력 스위치는 홈에서 제한 없음으로 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(_GravityRepository()),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('뒤집어! 공룡'), findsOneWidget);
    expect(find.text('제한 없음'), findsOneWidget);
  });
}

class _GravityRepository extends PreviewDailyGameRepository {
  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime(2026, 7, 22),
    game: const TodayGame(
      id: 'gravity_switch',
      version: 1,
      displayName: '뒤집어! 공룡',
      description: '중력을 뒤집으세요.',
      durationSeconds: 180,
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
    profile: const UserProfile(
      nickname: null,
      birthYear: null,
      birthMonth: null,
      gender: null,
    ),
  );
}
