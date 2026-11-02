import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/data/duel_runtime_launch_guard.dart';
import 'package:just_one_round/features/gameplay/domain/duel_play_context.dart';

void main() {
  test('claims a duel run only once', () async {
    final store = InMemoryDuelRuntimeLaunchStore();
    final guard = DuelRuntimeLaunchGuard(store: store);
    final context = _context(matchId: 'match-1', runId: 'run-1');

    expect(await guard.claim(context), isTrue);
    expect(await guard.claim(context), isFalse);
    expect(store.claimedRunKeys, {'match-1:run-1'});
  });

  test('does not conflate runs from different matches', () async {
    final guard = DuelRuntimeLaunchGuard(
      store: InMemoryDuelRuntimeLaunchStore(),
    );

    expect(
      await guard.claim(_context(matchId: 'match-1', runId: 'run-1')),
      isTrue,
    );
    expect(
      await guard.claim(_context(matchId: 'match-2', runId: 'run-1')),
      isTrue,
    );
    expect(
      await guard.claim(_context(matchId: 'match-1', runId: 'run-2')),
      isTrue,
    );
  });

  test('concurrent claims still allow only one local launch', () async {
    final guard = DuelRuntimeLaunchGuard(
      store: InMemoryDuelRuntimeLaunchStore(),
    );
    final context = _context(matchId: 'match-1', runId: 'run-1');

    final results = await Future.wait([
      guard.claim(context),
      guard.claim(context),
    ]);

    expect(results.where((claimed) => claimed), hasLength(1));
  });
}

DuelPlayContext _context({required String matchId, required String runId}) =>
    DuelPlayContext(
      matchId: matchId,
      runId: runId,
      gameId: 'number_rush',
      gameVersion: 1,
      challengeSeed: 42,
      startAt: DateTime.now().toUtc(),
      gameDuration: const Duration(seconds: 180),
    );
