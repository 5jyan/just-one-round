class WesternDuelOpponent {
  const WesternDuelOpponent({
    required this.nickname,
    required this.reactionMilliseconds,
    required this.isBot,
    this.nicknameColor,
  });

  final String nickname;
  final int reactionMilliseconds;
  final bool isBot;
  final String? nicknameColor;

  factory WesternDuelOpponent.fromJson(Map<String, dynamic> json) =>
      WesternDuelOpponent(
        nickname: json['nickname'] as String? ?? '맥크리',
        reactionMilliseconds: json['reaction_ms'] as int,
        isBot: json['is_bot'] as bool? ?? false,
        nicknameColor: json['nickname_color'] as String?,
      );
}
