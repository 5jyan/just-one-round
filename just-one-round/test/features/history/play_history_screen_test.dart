import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/history/presentation/play_history_screen.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

void main() {
  testWidgets('날짜별 최고 점수와 당시 순위를 보여준다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(_HistoryRepository()),
        ],
        child: const MaterialApp(home: PlayHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('내 기록'), findsOneWidget);
    expect(find.text('2026.07.22'), findsOneWidget);
    expect(find.text('별빛 피하기'), findsOneWidget);
    expect(find.text('2등 / 30명'), findsOneWidget);
    expect(find.text('0.80초'), findsOneWidget);
  });
}

class _HistoryRepository extends PreviewDailyGameRepository {
  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async => [
    PlayHistoryEntry(
      playDate: DateTime(2026, 7, 22),
      gameId: 'star_dodge',
      displayName: '별빛 피하기',
      score: 800,
      rank: 2,
      participants: 30,
    ),
  ];
}
