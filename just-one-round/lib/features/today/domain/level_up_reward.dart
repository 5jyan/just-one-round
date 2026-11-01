class LevelUpReward {
  const LevelUpReward({
    required this.userId,
    required this.fromLevel,
    required this.toLevel,
    required this.challengeTickets,
  });

  factory LevelUpReward.fromJson(Map<String, dynamic> json) => LevelUpReward(
    userId: json['user_id'] as String,
    fromLevel: (json['from_level'] as num).toInt(),
    toLevel: (json['to_level'] as num).toInt(),
    challengeTickets: (json['challenge_tickets'] as num).toInt(),
  );

  final String userId;
  final int fromLevel;
  final int toLevel;
  final int challengeTickets;
}
