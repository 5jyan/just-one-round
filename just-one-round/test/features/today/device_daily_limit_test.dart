import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';

void main() {
  test('blocks a new account when this device already claimed today', () {
    final state = TodayState.fromJson({
      'play_date': '2026-07-30',
      'game': null,
      'attempts': <Object?>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'daily_claimed': true,
      'device_daily_limit_reached': true,
      'result': null,
      'nickname': 'new-account',
    });

    expect(state.attempts, isEmpty);
    expect(state.dailyClaimed, isTrue);
    expect(state.deviceDailyLimitReached, isTrue);
    expect(state.canClaimDaily, isFalse);
    expect(state.isExhausted, isTrue);
  });

  test('allows a genuinely new device account to claim', () {
    final state = TodayState.fromJson({
      'play_date': '2026-07-30',
      'game': null,
      'attempts': <Object?>[],
      'ad_attempt_available': false,
      'test_mode': false,
      'daily_claimed': false,
      'result': null,
      'nickname': 'new-account',
    });

    expect(state.canClaimDaily, isTrue);
  });
}
