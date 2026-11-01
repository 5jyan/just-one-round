class DailyNonplayer {
  const DailyNonplayer({
    required this.userId,
    required this.nickname,
    required this.nicknameColor,
    required this.level,
  });

  factory DailyNonplayer.fromJson(Map<String, dynamic> json) => DailyNonplayer(
    userId: json['user_id'] as String,
    nickname: json['nickname'] as String,
    nicknameColor: json['nickname_color'] as String? ?? 'default',
    level: (json['level'] as num?)?.toInt() ?? 1,
  );

  final String userId;
  final String nickname;
  final String nicknameColor;
  final int level;
}

class DailyNonplayersPage {
  const DailyNonplayersPage({required this.players, required this.nextCursor});

  factory DailyNonplayersPage.fromJson(Map<String, dynamic> json) {
    final rawPlayers = json['players'] as List<dynamic>? ?? const [];
    return DailyNonplayersPage(
      players: rawPlayers
          .map(
            (item) =>
                DailyNonplayer.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      nextCursor: json['next_cursor'] as String?,
    );
  }

  final List<DailyNonplayer> players;
  final String? nextCursor;
}
