const referralLandingBaseUrl = String.fromEnvironment(
  'REFERRAL_LANDING_BASE_URL',
  defaultValue: 'https://legal.shook.party/invite',
);
final _referralCodePattern = RegExp(r'^[a-f0-9]{16}$');

String referralInviteUrl(String code) =>
    '$referralLandingBaseUrl/${Uri.encodeComponent(code)}';

class ReferralInvite {
  const ReferralInvite({required this.code});

  factory ReferralInvite.fromJson(Map<String, dynamic> json) {
    final code = (json['code'] as String? ?? '').trim().toLowerCase();
    if (!_referralCodePattern.hasMatch(code)) {
      throw const FormatException('referral code is invalid');
    }
    return ReferralInvite(code: code);
  }

  final String code;

  String get url => referralInviteUrl(code);
}

class ReferralStatus {
  const ReferralStatus({
    required this.invitedCount,
    required this.completedCount,
    required this.pendingCount,
    required this.accepted,
    required this.played,
    required this.rewardGranted,
    this.code,
  });

  const ReferralStatus.empty()
    : invitedCount = 0,
      completedCount = 0,
      pendingCount = 0,
      accepted = false,
      played = false,
      rewardGranted = false,
      code = null;

  factory ReferralStatus.fromJson(Map<String, dynamic> json) => ReferralStatus(
    code: (json['code'] as String?)?.trim().toLowerCase(),
    invitedCount: _intValue(json['invited_count']),
    completedCount: _intValue(json['completed_count']),
    pendingCount: _intValue(json['pending_count']),
    accepted: json['accepted'] as bool? ?? false,
    played: json['played'] as bool? ?? false,
    rewardGranted: json['reward_granted'] as bool? ?? false,
  );

  final String? code;
  final int invitedCount;
  final int completedCount;
  final int pendingCount;
  final bool accepted;
  final bool played;
  final bool rewardGranted;

  static int _intValue(Object? value) => (value as num?)?.toInt() ?? 0;
}

abstract interface class ReferralRepository {
  Future<ReferralInvite> getOrCreateReferralInvite();
  Future<ReferralStatus> fetchReferralStatus();
}

class NoopReferralRepository implements ReferralRepository {
  const NoopReferralRepository();

  @override
  Future<ReferralInvite> getOrCreateReferralInvite() async {
    throw StateError('referrals are unavailable in preview mode');
  }

  @override
  Future<ReferralStatus> fetchReferralStatus() async =>
      const ReferralStatus.empty();
}
