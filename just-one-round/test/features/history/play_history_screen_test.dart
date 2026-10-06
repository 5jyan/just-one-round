import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/history/presentation/play_history_screen.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';

class _HistoryRepository extends PreviewDailyGameRepository {
  _HistoryRepository({this.participants = 100, this.secondRank = 10});

  final int participants;
  final int secondRank;

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async => [
    PlayHistoryEntry(
      playDate: DateTime(2026, 8, 21),
      gameId: 'dung_dodge_v2',
      displayName: '똥피하기',
      score: 3500,
      rank: 1,
      participants: participants,
    ),
    PlayHistoryEntry(
      playDate: DateTime(2026, 8, 20),
      gameId: 'dung_dodge_v2',
      displayName: '똥피하기',
      score: 2800,
      rank: secondRank,
      participants: participants,
    ),
  ];
}

void main() {
  testWidgets('내 기록에 개인 통계와 최근 7일 그래프를 보여준다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(_HistoryRepository()),
        ],
        child: MaterialApp(
          home: PlayHistoryScreen(referencePlayDate: DateTime(2026, 8, 21)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('personal-stats-overview')), findsOneWidget);
    expect(find.byKey(const Key('personal-game-stats')), findsNothing);
    expect(find.text('2일'), findsOneWidget);
    expect(find.text('1회'), findsOneWidget);
    expect(find.text('1등'), findsOneWidget);
    expect(find.text('참여일'), findsOneWidget);
    expect(find.text('1위'), findsOneWidget);
    expect(find.text('최고 순위'), findsOneWidget);
    expect(find.text('평균 성적'), findsOneWidget);
    expect(find.text('상위 5%'), findsOneWidget);
    expect(find.text('최근 7일 통계'), findsOneWidget);
    expect(find.byKey(const Key('recent-performance-chart')), findsOneWidget);
    expect(
      find.byKey(const Key('recent-performance-chart-canvas')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('8/20 상위 10%')), findsOneWidget);
    expect(find.text('게임별 기록'), findsNothing);
  });

  testWidgets('참여자가 적은 기록도 평균 성적과 그래프에 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyGameRepositoryProvider.overrideWithValue(
            _HistoryRepository(participants: 2, secondRank: 2),
          ),
        ],
        child: MaterialApp(
          home: PlayHistoryScreen(referencePlayDate: DateTime(2026, 8, 21)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('상위 50%'), findsOneWidget);
    expect(find.text('-'), findsNothing);
    expect(find.byKey(const Key('recent-performance-chart')), findsOneWidget);
    expect(
      find.byKey(const Key('recent-performance-chart-empty')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('recent-performance-chart-canvas')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('8/20 상위 100%')), findsOneWidget);
  });

  testWidgets('좁은 화면에서도 최근 성적 그래프가 넘치지 않는다', (tester) async {
    final originalPhysicalSize = tester.view.physicalSize;
    final originalDevicePixelRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalPhysicalSize;
      tester.view.devicePixelRatio = originalDevicePixelRatio;
    });

    for (final width in [360.0, 393.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dailyGameRepositoryProvider.overrideWithValue(_HistoryRepository()),
          ],
          child: MaterialApp(
            home: PlayHistoryScreen(referencePlayDate: DateTime(2026, 8, 21)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('recent-performance-chart')), findsOneWidget);
    }
  });
}
