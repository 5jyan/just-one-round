import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/features/duels/data/duel_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class DuelResultSubmission {
  const DuelResultSubmission({
    required this.matchId,
    required this.runId,
    required this.runToken,
    this.resultKind = 'valid',
    required this.rawScore,
    required this.durationMs,
    this.starsCollected = 0,
    this.collisions = 0,
    this.windDartsShotScores,
  });

  factory DuelResultSubmission.fromJson(Map<String, dynamic> json) =>
      DuelResultSubmission(
        matchId: json['match_id'] as String,
        runId: json['run_id'] as String,
        runToken: json['run_token'] as String,
        resultKind: json['result_kind'] as String? ?? 'valid',
        rawScore: (json['raw_score'] as num).toInt(),
        durationMs: (json['duration_ms'] as num).toInt(),
        starsCollected: (json['stars_collected'] as num?)?.toInt() ?? 0,
        collisions: (json['collisions'] as num?)?.toInt() ?? 0,
        windDartsShotScores: (json['wind_darts_shot_scores'] as List<dynamic>?)
            ?.map((value) => (value as num).toInt())
            .toList(growable: false),
      );

  final String matchId;
  final String runId;
  final String runToken;
  final String resultKind;
  final int rawScore;
  final int durationMs;
  final int starsCollected;
  final int collisions;
  final List<int>? windDartsShotScores;

  String get key => '$matchId:$runId';

  Map<String, dynamic> toJson() => {
    'match_id': matchId,
    'run_id': runId,
    'run_token': runToken,
    'result_kind': resultKind,
    'raw_score': rawScore,
    'duration_ms': durationMs,
    'stars_collected': starsCollected,
    'collisions': collisions,
    if (windDartsShotScores != null)
      'wind_darts_shot_scores': windDartsShotScores,
  };
}

abstract interface class DuelResultStore {
  Future<List<DuelResultSubmission>> loadAll();
  Future<void> save(DuelResultSubmission submission);
  Future<void> remove(String key);
}

class SharedPreferencesDuelResultStore implements DuelResultStore {
  SharedPreferencesDuelResultStore()
    : _preferences = SharedPreferences.getInstance();

  static const _storageKey = 'pending_duel_results_v1';
  final Future<SharedPreferences> _preferences;
  Future<void> _operation = Future<void>.value();

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
  Future<List<DuelResultSubmission>> loadAll() => _synchronized(() async {
    final preferences = await _preferences;
    final raw = preferences.getString(_storageKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => DuelResultSubmission.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } on Object {
      await preferences.remove(_storageKey);
      return const [];
    }
  });

  @override
  Future<void> save(DuelResultSubmission submission) => _synchronized(() async {
    final preferences = await _preferences;
    final submissions = await _read(preferences);
    final index = submissions.indexWhere((item) => item.key == submission.key);
    if (index < 0) {
      submissions.add(submission);
    } else {
      submissions[index] = submission;
    }
    await _write(preferences, submissions);
  });

  @override
  Future<void> remove(String key) => _synchronized(() async {
    final preferences = await _preferences;
    final submissions = await _read(preferences)
      ..removeWhere((item) => item.key == key);
    await _write(preferences, submissions);
  });

  Future<List<DuelResultSubmission>> _read(
    SharedPreferences preferences,
  ) async {
    final raw = preferences.getString(_storageKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => DuelResultSubmission.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on Object {
      await preferences.remove(_storageKey);
      return [];
    }
  }

  Future<void> _write(
    SharedPreferences preferences,
    List<DuelResultSubmission> submissions,
  ) async {
    if (submissions.isEmpty) {
      await preferences.remove(_storageKey);
      return;
    }
    await preferences.setString(
      _storageKey,
      jsonEncode(submissions.map((item) => item.toJson()).toList()),
    );
  }
}

class DuelResultRetryService {
  const DuelResultRetryService(this._repository, this._store);

  final DuelRepository _repository;
  final DuelResultStore _store;

  Future<void> submit(DuelResultSubmission submission) async {
    await _store.save(submission);
    try {
      await _repository.submitDuelResult(
        matchId: submission.matchId,
        runId: submission.runId,
        runToken: submission.runToken,
        resultKind: submission.resultKind,
        rawScore: submission.rawScore,
        durationMs: submission.durationMs,
        starsCollected: submission.starsCollected,
        collisions: submission.collisions,
        windDartsShotScores: submission.windDartsShotScores,
      );
      await _store.remove(submission.key);
    } catch (_) {
      rethrow;
    }
  }

  Future<void> retry() async {
    final submissions = await _store.loadAll();
    for (final submission in submissions) {
      try {
        await _repository.submitDuelResult(
          matchId: submission.matchId,
          runId: submission.runId,
          runToken: submission.runToken,
          resultKind: submission.resultKind,
          rawScore: submission.rawScore,
          durationMs: submission.durationMs,
          starsCollected: submission.starsCollected,
          collisions: submission.collisions,
          windDartsShotScores: submission.windDartsShotScores,
        );
        await _store.remove(submission.key);
      } on Object {
        // Keep the payload until the next foreground retry.
      }
    }
  }
}

final duelResultStoreProvider = Provider<DuelResultStore>(
  (ref) => SharedPreferencesDuelResultStore(),
);

final duelResultRetryServiceProvider = Provider<DuelResultRetryService>((ref) {
  return DuelResultRetryService(
    ref.watch(duelRepositoryProvider),
    ref.watch(duelResultStoreProvider),
  );
});
