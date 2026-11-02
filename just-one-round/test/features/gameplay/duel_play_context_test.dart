import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/duel_play_context.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';

void main() {
  test(
    'uses the server clock offset when calculating the shared start delay',
    () {
      final localNow = DateTime.now().toUtc();
      final context = DuelPlayContext(
        matchId: 'match-1',
        runId: 'run-1',
        gameId: 'number_rush',
        gameVersion: 1,
        challengeSeed: 42,
        startAt: localNow.add(const Duration(seconds: 10)),
        gameDuration: const Duration(seconds: 30),
        serverClockOffset: const Duration(seconds: 2),
      );

      final remaining = context.timeUntilStart;
      expect(remaining, greaterThan(const Duration(seconds: 7)));
      expect(remaining, lessThan(const Duration(seconds: 9)));
    },
  );

  test(
    'keeps the immutable run identity available to idempotent callbacks',
    () {
      final context = DuelPlayContext(
        matchId: 'match-1',
        runId: 'run-1',
        gameId: 'number_rush',
        gameVersion: 1,
        challengeSeed: 42,
        startAt: DateTime.now().toUtc(),
        gameDuration: const Duration(seconds: 30),
      );

      expect(context.matchId, 'match-1');
      expect(context.runId, 'run-1');
      expect(context.challengeSeed, 42);
    },
  );

  test('allows a first entry that is only a little late', () {
    final context = DuelPlayContext(
      matchId: 'match-1',
      runId: 'run-1',
      gameId: 'number_rush',
      gameVersion: 1,
      challengeSeed: 42,
      startAt: DateTime.now().toUtc().subtract(const Duration(milliseconds: 1)),
      gameDuration: const Duration(seconds: 30),
    );

    expect(
      context.canAcceptInitialEntry(enteredBeforeStart: false),
      isTrue,
    );
  });

  test('rejects a genuinely late first entry', () {
    final context = DuelPlayContext(
      matchId: 'match-1',
      runId: 'run-1',
      gameId: 'number_rush',
      gameVersion: 1,
      challengeSeed: 42,
      startAt: DateTime.now().toUtc().subtract(
        DuelPlayContext.initialEntryGrace + const Duration(milliseconds: 100),
      ),
      gameDuration: const Duration(seconds: 30),
    );

    expect(
      context.canAcceptInitialEntry(enteredBeforeStart: false),
      isFalse,
    );
  });

  test('classifies mole timeout as no-result instead of a valid zero', () {
    final context = DuelPlayContext(
      matchId: 'match-1',
      runId: 'run-1',
      gameId: 'mole_reaction',
      gameVersion: 2,
      challengeSeed: 42,
      startAt: DateTime.now().toUtc(),
      gameDuration: const Duration(seconds: 180),
    );

    const timeout = GameResult(
      score: 0,
      starsCollected: 0,
      collisions: 1,
      duration: Duration(seconds: 180),
      endType: GameEndType.timeUp,
    );

    expect(context.submissionKindFor(timeout), DuelSubmissionKind.noResult);
    expect(context.submissionKindFor(timeout).wireValue, 'no_result');
  });

  test('keeps a normal zero score valid for other duel runtimes', () {
    final context = DuelPlayContext(
      matchId: 'match-1',
      runId: 'run-1',
      gameId: 'number_rush',
      gameVersion: 1,
      challengeSeed: 42,
      startAt: DateTime.now().toUtc(),
      gameDuration: const Duration(seconds: 180),
    );

    const zeroScore = GameResult(
      score: 0,
      starsCollected: 0,
      collisions: 0,
      duration: Duration(seconds: 180),
      endType: GameEndType.timeUp,
    );

    expect(context.submissionKindFor(zeroScore), DuelSubmissionKind.valid);
    expect(context.submissionKindFor(zeroScore).wireValue, 'valid');
  });
}
