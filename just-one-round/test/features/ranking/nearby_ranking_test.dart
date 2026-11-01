import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/profile/domain/nickname_color.dart';
import 'package:just_one_round/features/ranking/presentation/nearby_ranking.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

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
        NearbyRank(
          rank: 3,
          userId: 'other-user',
          nickname: '별둘',
          score: 700,
          isMe: false,
          level: 30,
          nicknameColor: 'coral',
        ),
      ],
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: NearbyRanking(result: result)),
        ),
      ),
    );

    expect(find.text('별셋'), findsOneWidget);
    expect(find.text('별하나'), findsOneWidget);
    expect(find.text('별둘'), findsOneWidget);
    expect(find.byKey(const Key('my-nearby-rank')), findsOneWidget);
    expect(find.text('NPC'), findsNothing);
    expect(find.byTooltip('사용자 신고 또는 차단'), findsNothing);
    expect(find.text('닉네임 신고'), findsNothing);
    expect(find.text('사용자 차단'), findsNothing);
    final displayedNickname = tester.widget<WordSafeText>(find.text('별둘'));
    expect(displayedNickname.style?.color, NicknameColors.forLevel(30));
    expect(
      tester.getSize(find.byKey(const Key('my-nearby-rank'))).width,
      tester.getSize(find.text('내 주변 랭킹')).width,
    );
  });
}
