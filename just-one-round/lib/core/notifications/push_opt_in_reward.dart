/// Server-backed status for the one-time push opt-in challenge-ticket reward.
class PushOptInRewardStatus {
  const PushOptInRewardStatus({
    required this.shouldShow,
    required this.accepted,
    required this.claimed,
  });

  factory PushOptInRewardStatus.fromJson(Map<String, dynamic> json) {
    return PushOptInRewardStatus(
      shouldShow: json['should_show'] as bool? ?? false,
      accepted: json['accepted'] as bool? ?? false,
      claimed: json['claimed'] as bool? ?? false,
    );
  }

  final bool shouldShow;
  final bool accepted;
  final bool claimed;

  bool get eligible => shouldShow && !claimed;
}

/// Result of the idempotent server-side push opt-in reward claim.
class PushOptInRewardClaim {
  const PushOptInRewardClaim({
    required this.claimed,
    required this.granted,
    this.ticketsGranted = 0,
    this.challengeTickets,
  });

  factory PushOptInRewardClaim.fromJson(Map<String, dynamic> json) {
    return PushOptInRewardClaim(
      claimed: json['claimed'] as bool? ?? false,
      granted: json['granted'] as bool? ?? false,
      ticketsGranted: (json['tickets_granted'] as num?)?.toInt() ?? 0,
      challengeTickets: (json['challenge_tickets'] as num?)?.toInt(),
    );
  }

  final bool claimed;
  final bool granted;
  final int ticketsGranted;
  final int? challengeTickets;

  bool get hasReward => granted && ticketsGranted > 0;
}

/// Optional production capability for the startup push opt-in reward.
abstract interface class PushOptInRewardRepository {
  Future<PushOptInRewardStatus> fetchPushOptInRewardStatus();

  Future<PushOptInRewardStatus> recordPushOptInRewardPrompt({
    bool accepted = false,
  });

  Future<PushOptInRewardClaim> claimPushOptInReward();
}
