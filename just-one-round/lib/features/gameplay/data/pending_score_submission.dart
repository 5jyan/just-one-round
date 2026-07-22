import 'dart:convert';

import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingScoreSubmission {
  const PendingScoreSubmission({
    required this.attemptId,
    required this.starsCollected,
    required this.collisions,
    required this.durationMs,
  });

  factory PendingScoreSubmission.fromGameResult(
    String attemptId,
    GameResult result,
  ) => PendingScoreSubmission(
    attemptId: attemptId,
    starsCollected: result.starsCollected,
    collisions: result.collisions,
    durationMs: result.duration.inMilliseconds,
  );

  factory PendingScoreSubmission.fromJson(Map<String, dynamic> json) =>
      PendingScoreSubmission(
        attemptId: json['attempt_id'] as String,
        starsCollected: (json['stars_collected'] as num).toInt(),
        collisions: (json['collisions'] as num).toInt(),
        durationMs: (json['duration_ms'] as num).toInt(),
      );

  final String attemptId;
  final int starsCollected;
  final int collisions;
  final int durationMs;

  Map<String, dynamic> toJson() => {
    'attempt_id': attemptId,
    'stars_collected': starsCollected,
    'collisions': collisions,
    'duration_ms': durationMs,
  };
}

abstract interface class PendingScoreStore {
  Future<PendingScoreSubmission?> load();
  Future<void> save(PendingScoreSubmission submission);
  Future<void> clear();
}

class PendingScoreRetryService<T> {
  const PendingScoreRetryService(this._store);

  final PendingScoreStore _store;

  Future<T> sendAndPersist(
    PendingScoreSubmission submission,
    Future<T> Function(PendingScoreSubmission submission) send,
  ) async {
    await _store.save(submission);
    final result = await send(submission);
    await _store.clear();
    return result;
  }

  Future<T?> retry(
    Future<T> Function(PendingScoreSubmission submission) send,
  ) async {
    final submission = await _store.load();
    if (submission == null) return null;
    try {
      final result = await send(submission);
      await _store.clear();
      return result;
    } catch (_) {
      return null;
    }
  }
}

class SharedPreferencesPendingScoreStore implements PendingScoreStore {
  SharedPreferencesPendingScoreStore()
    : _preferences = SharedPreferences.getInstance();

  static const _storageKey = 'pending_score_submission_v1';
  final Future<SharedPreferences> _preferences;

  @override
  Future<PendingScoreSubmission?> load() async {
    final raw = (await _preferences).getString(_storageKey);
    if (raw == null) return null;
    try {
      return PendingScoreSubmission.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(PendingScoreSubmission submission) async {
    await (await _preferences).setString(_storageKey, jsonEncode(submission));
  }

  @override
  Future<void> clear() async {
    await (await _preferences).remove(_storageKey);
  }
}
