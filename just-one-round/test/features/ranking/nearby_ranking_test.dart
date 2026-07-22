import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/ranking/presentation/nearby_ranking.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  testWidgets('내 위와 아래를 포함한 주변 랭킹을 표시한다', (tester) async {
    const result = DailyRankResult(
      score: 800,
      rank: 2,
      participants: 3,
      topPercent: 67,
      nickname: '별하나',
      nearby: [
        NearbyRank(
          rank: 1,
          nickname: '별셋',
          score: 900,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(rank: 2, nickname: '별하나', score: 800, isMe: true),
        NearbyRank(rank: 3, nickname: '별둘', score: 700, isMe: false),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NearbyRanking(result: result)),
      ),
    );

    expect(find.text('별셋'), findsOneWidget);
    expect(find.text('별하나'), findsOneWidget);
    expect(find.text('별둘'), findsOneWidget);
    expect(find.byKey(const Key('my-nearby-rank')), findsOneWidget);
    expect(find.byKey(const Key('npc-rank-badge')), findsOneWidget);
  });
}
