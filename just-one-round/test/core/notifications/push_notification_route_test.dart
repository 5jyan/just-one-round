import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/core/notifications/push_notification_route.dart';

void main() {
  test('legacy and social notification taps open the daily-game home', () {
    expect(pushDestinationPath({}), '/');
    expect(pushDestinationPath({'action_type': 'poke'}), '/');
    expect(pushDestinationPath({'route': 'today'}), '/');
    expect(pushDestinationPath({'destination': 'today_game'}), '/');
  });

  test('unknown destinations fall back to the daily-game home', () {
    expect(pushDestinationPath({'route': 'unsupported'}), '/');
  });
}
