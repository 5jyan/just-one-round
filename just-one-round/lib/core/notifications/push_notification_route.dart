/// The route used for 1:1 duel notifications.
const duelLobbyRoutePath = '/duels';

/// Returns the in-app destination for a notification tap.
///
/// A duel invitation opens the duel list. The list refreshes from the server,
/// so an expired room or a room the viewer can no longer enter is handled by
/// the same participant checks as an ordinary list visit. This intentionally
/// does not join a room, toggle READY, or start a game as a side effect of a
/// notification tap.
///
/// Social notifications sent before destination metadata was added, malformed
/// payloads, and unknown destinations keep the legacy daily-game home route.
String pushDestinationPath(Map<String, dynamic> data) {
  final actionType = data['action_type']?.toString().trim();
  final destination = data['destination']?.toString().trim();
  if (actionType == 'duel_room_invite' && destination == 'duel_room') {
    return duelLobbyRoutePath;
  }

  // Keep all legacy social payloads on the safe landing page. `/play` requires
  // a server-issued PlayAttempt, so a push must never create one implicitly.
  final route = data['route']?.toString().trim();
  if (destination == null ||
      destination.isEmpty ||
      destination == 'today_game' ||
      route == null ||
      route == 'today') {
    return '/';
  }
  return '/';
}
