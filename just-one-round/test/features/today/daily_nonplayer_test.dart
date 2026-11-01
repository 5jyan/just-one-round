import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/daily_nonplayer.dart';

void main() {
  test('daily nonplayer pages parse profile details and cursor', () {
    final page = DailyNonplayersPage.fromJson({
      'players': [
        {
          'user_id': 'user-1',
          'nickname': '관전중',
          'nickname_color': 'mint',
          'level': 4,
        },
      ],
      'next_cursor': 'user-1',
    });

    expect(page.players, hasLength(1));
    expect(page.players.single.userId, 'user-1');
    expect(page.players.single.nickname, '관전중');
    expect(page.players.single.nicknameColor, 'mint');
    expect(page.players.single.level, 4);
    expect(page.nextCursor, 'user-1');
  });

  test(
    'preview repository exposes nonplayers and consumes the cursor',
    () async {
      final repository = PreviewDailyGameRepository();

      final firstPage = await repository.fetchDailyNonplayers(
        playDate: DateTime(2026, 10, 12),
        gameId: 'dung_dodge_v2',
      );
      final nextPage = await repository.fetchDailyNonplayers(
        playDate: DateTime(2026, 10, 12),
        gameId: 'dung_dodge_v2',
        afterUserId: firstPage.players.first.userId,
      );

      expect(firstPage.players, hasLength(2));
      expect(firstPage.nextCursor, isNull);
      expect(nextPage.players, isEmpty);
    },
  );
}
