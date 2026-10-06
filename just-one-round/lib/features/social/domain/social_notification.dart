import 'package:just_one_round/features/games/game_registry.dart';

class SocialNotification {
  const SocialNotification({
    required this.id,
    required this.actionType,
    required this.senderNickname,
    required this.createdAt,
    this.giftItemId,
    this.senderRank,
    this.senderScore,
    this.senderGameId,
  });

  factory SocialNotification.fromJson(Map<String, dynamic> json) =>
      SocialNotification(
        id: json['id'] as String,
        actionType: json['action_type'] as String,
        senderNickname: json['sender_nickname'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        giftItemId: json['gift_item_id'] as String?,
        senderRank: (json['sender_rank'] as num?)?.toInt(),
        senderScore: (json['sender_score'] as num?)?.toInt(),
        senderGameId: json['sender_game_id'] as String?,
      );

  final String id;
  final String actionType;
  final String senderNickname;
  final DateTime createdAt;
  final String? giftItemId;
  final int? senderRank;
  final int? senderScore;
  final String? senderGameId;

  String get scoreLabel {
    final score = senderScore;
    if (score == null) return '-';
    try {
      return GameRegistry.formatScore(senderGameId, score);
    } on Object {
      return score.toString();
    }
  }

  String get message => switch (actionType) {
    'poke' => '$senderNickname님이 콕 찔렀어요. 이건 못 참죠?',
    'boast' =>
      '$senderNickname님은 기록이 $scoreLabel로 오늘 '
          '${senderRank ?? '-'}등으로 자랑했어요.',
    'gift' => '$senderNickname님이 ${giftLabel(giftItemId)} 1장을 선물했습니다.',
    _ => '$senderNickname님이 소식을 보냈습니다.',
  };

  static String giftLabel(String? itemId) => switch (itemId) {
    'practice_ticket' => '연습권',
    'challenge_ticket' => '도전권',
    'nickname_color_ticket' => '닉네임 색상권',
    'nickname_change_ticket' => '닉네임 변경권',
    _ => '선물',
  };
}
