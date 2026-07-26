class RewardedAdSession {
  const RewardedAdSession({
    required this.id,
    required this.userId,
    required this.status,
    required this.expiresAt,
  });

  factory RewardedAdSession.fromJson(Map<String, dynamic> json) {
    return RewardedAdSession(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String id;
  final String userId;
  final String status;
  final DateTime expiresAt;

  bool get isVerified => status == 'verified';
}
