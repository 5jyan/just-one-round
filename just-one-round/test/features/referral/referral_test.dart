import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/referral/domain/referral.dart';

void main() {
  test('normalizes an invite code and builds its landing URL', () {
    final invite = ReferralInvite.fromJson({'code': 'ABCDEF0123456789'});

    expect(invite.code, 'abcdef0123456789');
    expect(invite.url, 'https://legal.shook.party/invite/abcdef0123456789');
  });

  test('parses referral counts returned by Supabase JSON', () {
    final status = ReferralStatus.fromJson({
      'code': 'abcdef0123456789',
      'invited_count': 3,
      'completed_count': 2,
      'pending_count': 1,
      'accepted': true,
      'played': true,
      'reward_granted': true,
    });

    expect(status.invitedCount, 3);
    expect(status.completedCount, 2);
    expect(status.pendingCount, 1);
    expect(status.accepted, isTrue);
    expect(status.played, isTrue);
    expect(status.rewardGranted, isTrue);
  });

  test('rejects malformed invite codes before sharing', () {
    expect(
      () => ReferralInvite.fromJson({'code': 'short'}),
      throwsFormatException,
    );
  });
}
