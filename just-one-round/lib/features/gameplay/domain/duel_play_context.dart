import 'package:just_one_round/features/gameplay/domain/game_result.dart';

/// The server-side result contract for a duel run.
///
/// A score of zero is not a no-result sentinel: games such as tap50 can end
/// normally with a valid zero. Only a game-specific terminal rule may classify
/// a result as [noResult].
enum DuelSubmissionKind {
  valid('valid'),
  noResult('no_result');

  const DuelSubmissionKind(this.wireValue);

  final String wireValue;
}

/// Runtime contract for a game launched from a two-player duel room.
///
/// A duel is deliberately separate from [PlayAttempt]. Daily attempts carry
/// ranking and ticket semantics; this context carries only the immutable
/// match/run data needed to start the already-authorized game and submit its
/// result. The repository that creates the context owns idempotency and
/// durable retry for the callbacks.
class DuelPlayContext {
  /// Small bridge for network and route-transition jitter around the common
  /// server start instant. This does not move [startAt] or relax server-side
  /// elapsed-time validation; it only prevents a first screen frame that is a
  /// few milliseconds late from being mistaken for a replay.
  static const initialEntryGrace = Duration(seconds: 5);

  const DuelPlayContext({
    required this.matchId,
    required this.runId,
    required this.gameId,
    required this.gameVersion,
    required this.challengeSeed,
    required this.startAt,
    required this.gameDuration,
    this.countdownDuration = Duration.zero,
    this.serverClockOffset = Duration.zero,
    this.submitResult,
    this.forfeit,
  });

  final String matchId;
  final String runId;
  final String gameId;
  final int gameVersion;
  final int challengeSeed;
  final DateTime startAt;
  final Duration gameDuration;
  final Duration countdownDuration;

  /// Difference to add to the device UTC clock to approximate server UTC.
  /// The room RPC should calculate this when it returns [startAt].
  final Duration serverClockOffset;

  /// Both callbacks must be idempotent for [runId]. A failed submit is kept on
  /// screen so the caller can retry with the same result and run ID.
  final Future<void> Function(GameResult result)? submitResult;
  final Future<void> Function()? forfeit;

  DateTime get estimatedServerNow =>
      DateTime.now().toUtc().add(serverClockOffset);

  Duration get timeUntilStart => startAt.difference(estimatedServerNow);

  bool canAcceptInitialEntry({required bool enteredBeforeStart}) {
    if (enteredBeforeStart) return true;
    return timeUntilStart >= -initialEntryGrace;
  }

  /// Classifies a completed game result without conflating a valid zero score
  /// with a missing/invalid result. Keep this mapping beside the duel runtime
  /// contract so every submitter can use the same game-specific rule.
  DuelSubmissionKind submissionKindFor(GameResult result) {
    if (gameId == 'mole_reaction' && result.endType == GameEndType.timeUp) {
      return DuelSubmissionKind.noResult;
    }
    return DuelSubmissionKind.valid;
  }
}
