import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/core/notifications/push_opt_in_reward.dart';

void main() {
  test('status keeps the server popup and acceptance bits', () {
    final status = PushOptInRewardStatus.fromJson({
      'should_show': true,
      'accepted': false,
      'claimed': false,
    });

    expect(status.shouldShow, isTrue);
    expect(status.accepted, isFalse);
    expect(status.claimed, isFalse);
    expect(status.eligible, isTrue);
  });

  test('claimed status is never eligible even when should_show is stale', () {
    final status = PushOptInRewardStatus.fromJson({
      'should_show': true,
      'accepted': true,
      'claimed': true,
    });

    expect(status.eligible, isFalse);
  });

  test('claim reports only a positive ticket grant as a reward', () {
    expect(
      PushOptInRewardClaim.fromJson({
        'claimed': true,
        'granted': true,
        'tickets_granted': 1,
        'challenge_tickets': 2,
      }).hasReward,
      isTrue,
    );
    expect(
      PushOptInRewardClaim.fromJson({
        'claimed': true,
        'granted': false,
        'tickets_granted': 0,
      }).hasReward,
      isFalse,
    );
  });
}
