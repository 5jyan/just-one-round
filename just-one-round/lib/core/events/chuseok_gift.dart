/// Account-wide status for the 2026 Chuseok gift event.
class ChuseokGiftStatus {
  const ChuseokGiftStatus({
    required this.eligible,
    required this.claimed,
    this.eventId,
  });

  factory ChuseokGiftStatus.fromJson(Map<String, dynamic> json) {
    return ChuseokGiftStatus(
      eligible: json['eligible'] as bool? ?? false,
      claimed: json['claimed'] as bool? ?? false,
      eventId: json['event_id'] as String?,
    );
  }

  final bool eligible;
  final bool claimed;
  final String? eventId;

  bool get shouldShow => eligible && !claimed;
}

/// Result of the idempotent server-side gift claim.
class ChuseokGiftClaim {
  const ChuseokGiftClaim({
    required this.eligible,
    required this.claimed,
    required this.granted,
    this.ticketsGranted = 0,
    this.challengeTickets,
    this.message,
  });

  factory ChuseokGiftClaim.fromJson(Map<String, dynamic> json) {
    return ChuseokGiftClaim(
      eligible: json['eligible'] as bool? ?? false,
      claimed: json['claimed'] as bool? ?? false,
      granted: json['granted'] as bool? ?? false,
      ticketsGranted: (json['tickets_granted'] as num?)?.toInt() ?? 0,
      challengeTickets: (json['challenge_tickets'] as num?)?.toInt(),
      message: json['message'] as String?,
    );
  }

  final bool eligible;
  final bool claimed;
  final bool granted;
  final int ticketsGranted;
  final int? challengeTickets;
  final String? message;

  // A retry can arrive after the event cutoff even though the first request
  // already committed the claim. The server's claimed bit is authoritative.
  bool get completed => claimed;
}

/// Optional capability used by the startup event flow.
abstract interface class ChuseokGiftRepository {
  Future<ChuseokGiftStatus> fetchChuseokGiftStatus();

  Future<ChuseokGiftClaim> claimChuseokGift();
}
