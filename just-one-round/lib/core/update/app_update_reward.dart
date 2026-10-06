/// A one-time challenge-ticket grant for an existing player who crosses a
/// configured forced-update build.
class AppUpdateReward {
  const AppUpdateReward({
    required this.granted,
    this.campaignId,
    this.message = '업데이트 감사 보상으로 도전권 1장을 드려요.',
    this.ticketsGranted = 0,
    this.challengeTickets,
  });

  factory AppUpdateReward.fromJson(Map<String, dynamic> json) {
    return AppUpdateReward(
      granted: json['granted'] as bool? ?? false,
      campaignId: json['campaign_id'] as String?,
      message: json['message'] as String? ?? '업데이트 감사 보상으로 도전권 1장을 드려요.',
      ticketsGranted: (json['tickets_granted'] as num?)?.toInt() ?? 0,
      challengeTickets: (json['challenge_tickets'] as num?)?.toInt(),
    );
  }

  final bool granted;
  final String? campaignId;
  final String message;
  final int ticketsGranted;
  final int? challengeTickets;

  bool get hasReward => granted && ticketsGranted > 0;
}

/// Optional capability exposed by the production repository. Keeping this
/// separate from DailyGameRepository lets preview and game-specific fakes
/// remain source-compatible while the startup flow can claim the reward when
/// the server has an active campaign.
abstract interface class AppUpdateRewardRepository {
  Future<AppUpdateReward> claimAppUpdateReward();
}
