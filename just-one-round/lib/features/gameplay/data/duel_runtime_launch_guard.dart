import 'dart:async';

import 'package:just_one_round/features/gameplay/domain/duel_play_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage used to remember that a duel run has been claimed by a game screen.
///
/// A run token is single-use on the server. The client keeps the same rule
/// across process restarts so reopening a room cannot create a second local
/// run for the same server run, including while the first screen is still
/// loading.
abstract interface class DuelRuntimeLaunchStore {
  Future<bool> claim(String runKey);
}

/// In-memory implementation for deterministic runtime tests.
class InMemoryDuelRuntimeLaunchStore implements DuelRuntimeLaunchStore {
  final Set<String> claimedRunKeys = <String>{};

  @override
  Future<bool> claim(String runKey) async => claimedRunKeys.add(runKey);
}

/// Shared-preferences implementation used by the app runtime.
class SharedPreferencesDuelRuntimeLaunchStore
    implements DuelRuntimeLaunchStore {
  SharedPreferencesDuelRuntimeLaunchStore()
    : _preferences = SharedPreferences.getInstance();

  static const _storageKey = 'duel_runtime_started_runs_v1';
  static Future<void> _operation = Future<void>.value();

  final Future<SharedPreferences> _preferences;

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operation = _operation.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<bool> claim(String runKey) => _synchronized(() async {
    final preferences = await _preferences;
    final claimed = preferences.getStringList(_storageKey) ?? <String>[];
    if (claimed.contains(runKey)) return false;
    await preferences.setStringList(_storageKey, <String>[...claimed, runKey]);
    return true;
  });
}

/// Single-use launch gate for a server-issued duel run.
class DuelRuntimeLaunchGuard {
  DuelRuntimeLaunchGuard({DuelRuntimeLaunchStore? store})
    : _store = store ?? SharedPreferencesDuelRuntimeLaunchStore();

  final DuelRuntimeLaunchStore _store;

  String keyFor(DuelPlayContext context) =>
      '${context.matchId}:${context.runId}';

  Future<bool> claim(DuelPlayContext context) => _store.claim(keyFor(context));
}
