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

  test('duel invitations open the duel list without starting a room', () {
    expect(
      pushDestinationPath({
        'schema_version': '1',
        'notification_id': 'notification-id',
        'action_type': 'duel_room_invite',
        'destination': 'duel_room',
        'duel_id': '65095082-d8d7-4c7b-af83-1c6a436caa98',
      }),
      duelLobbyRoutePath,
    );
  });

  test('incomplete or spoofed duel routes keep the legacy fallback', () {
    expect(
      pushDestinationPath({
        'action_type': 'duel_room_invite',
        'destination': 'today_game',
        'duel_id': '65095082-d8d7-4c7b-af83-1c6a436caa98',
      }),
      '/',
    );
    expect(
      pushDestinationPath({
        'action_type': 'duel_result',
        'destination': 'duel_room',
        'duel_id': '65095082-d8d7-4c7b-af83-1c6a436caa98',
      }),
      '/',
    );
  });
}
