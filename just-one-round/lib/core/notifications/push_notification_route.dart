/// Returns the in-app destination for a notification tap.
///
/// Social notifications intentionally open the daily-game home instead of
/// `/play`: `/play` requires a server-issued [PlayAttempt], and starting one
/// silently from a system notification would consume a user's limited round.
/// A missing route is treated as the legacy home destination so notifications
/// sent before the route field was added keep working.
String pushDestinationPath(Map<String, dynamic> data) {
  // Keep all social/legacy notification payloads on the safe landing page.
  // Unknown values must not strand the user on the screen that happened to be
  // open when the notification was tapped.
  final destination = data['destination']?.toString();
  final route = data['route']?.toString();
  if (destination == null ||
      destination.isEmpty ||
      destination == 'today_game' ||
      route == null ||
      route == 'today') {
    return '/';
  }
  return '/';
}
