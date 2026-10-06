import 'dart:async';
import 'dart:convert';

import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingScoreSubmission {
  const PendingScoreSubmission({
    required this.attemptId,
    required this.rawScore,
    required this.starsCollected,
    required this.collisions,
    required this.durationMs,
    this.windDartsShotScores,
  });

  factory PendingScoreSubmission.fromGameResult(
    String attemptId,
    GameResult result,
  ) => PendingScoreSubmission(
    attemptId: attemptId,
    rawScore: result.score,
    starsCollected: result.starsCollected,
    collisions: result.collisions,
    durationMs: result.duration.inMilliseconds,
    windDartsShotScores: result.windDartsShotScores,
  );

  factory PendingScoreSubmission.fromJson(Map<String, dynamic> json) =>
      PendingScoreSubmission(
        attemptId: json['attempt_id'] as String,
        rawScore:
            (json['raw_score'] as num?)?.toInt() ??
            (json['duration_ms'] as num).toInt(),
        starsCollected: (json['stars_collected'] as num).toInt(),
        collisions: (json['collisions'] as num).toInt(),
        durationMs: (json['duration_ms'] as num).toInt(),
        windDartsShotScores: (json['wind_darts_shot_scores'] as List<dynamic>?)
            ?.map((value) => (value as num).toInt())
            .toList(growable: false),
      );

  final String attemptId;
  final int rawScore;
  final int starsCollected;
  final int collisions;
  final int durationMs;
  final List<int>? windDartsShotScores;

  Map<String, dynamic> toJson() => {
    'attempt_id': attemptId,
    'raw_score': rawScore,
    'stars_collected': starsCollected,
    'collisions': collisions,
    'duration_ms': durationMs,
    if (windDartsShotScores != null)
      'wind_darts_shot_scores': windDartsShotScores,
  };
}

abstract interface class PendingScoreStore {
  Future<PendingScoreSubmission?> load();
  Future<List<PendingScoreSubmission>> loadAll();
  Future<void> save(PendingScoreSubmission submission);
  Future<void> remove(String attemptId);
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
    return sendPersisted(submission, send);
  }

  Future<T> sendPersisted(
    PendingScoreSubmission submission,
    Future<T> Function(PendingScoreSubmission submission) send,
  ) async {
    final result = await send(submission);
    await _store.remove(submission.attemptId);
    return result;
  }

  Future<T?> retry(
    Future<T> Function(PendingScoreSubmission submission) send, {
    bool Function(Object error)? discardWhen,
  }) async {
    final submissions = await _store.loadAll();
    T? latestResult;
    for (final submission in submissions) {
      try {
        latestResult = await send(submission);
        await _store.remove(submission.attemptId);
      } catch (error) {
        if (discardWhen?.call(error) ?? false) {
          await _store.remove(submission.attemptId);
        }
      }
    }
    return latestResult;
  }
}

class SharedPreferencesPendingScoreStore implements PendingScoreStore {
  SharedPreferencesPendingScoreStore()
    : _preferences = SharedPreferences.getInstance();

  static const _legacyStorageKey = 'pending_score_submission_v1';
  static const _storageKey = 'pending_score_submissions_v2';
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
  Future<PendingScoreSubmission?> load() async {
    final submissions = await loadAll();
    return submissions.isEmpty ? null : submissions.first;
  }

  @override
  Future<List<PendingScoreSubmission>> loadAll() => _synchronized(() async {
    final preferences = await _preferences;
    final rawQueue = preferences.getString(_storageKey);
    if (rawQueue != null) {
      try {
        final submissions = (jsonDecode(rawQueue) as List<dynamic>)
            .map(
              (item) => PendingScoreSubmission.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false);
        await preferences.remove(_legacyStorageKey);
        return submissions;
      } catch (_) {
        await preferences.remove(_storageKey);
      }
    }

    final legacyRaw = preferences.getString(_legacyStorageKey);
    if (legacyRaw == null) return const [];
    try {
      final legacy = PendingScoreSubmission.fromJson(
        Map<String, dynamic>.from(jsonDecode(legacyRaw) as Map),
      );
      await _writeAll(preferences, [legacy]);
      await preferences.remove(_legacyStorageKey);
      return [legacy];
    } catch (_) {
      await preferences.remove(_legacyStorageKey);
      return const [];
    }
  });

  @override
  Future<void> save(PendingScoreSubmission submission) =>
      _synchronized(() async {
        final preferences = await _preferences;
        final submissions = await _readQueue(preferences);
        final existingIndex = submissions.indexWhere(
          (item) => item.attemptId == submission.attemptId,
        );
        if (existingIndex < 0) {
          submissions.add(submission);
        } else {
          submissions[existingIndex] = submission;
        }
        await _writeAll(preferences, submissions);
      });

  @override
  Future<void> remove(String attemptId) => _synchronized(() async {
    final preferences = await _preferences;
    final submissions = await _readQueue(preferences);
    submissions.removeWhere((item) => item.attemptId == attemptId);
    await _writeAll(preferences, submissions);
  });

  @override
  Future<void> clear() => _synchronized(() async {
    final preferences = await _preferences;
    await preferences.remove(_storageKey);
    await preferences.remove(_legacyStorageKey);
  });

  Future<List<PendingScoreSubmission>> _readQueue(
    SharedPreferences preferences,
  ) async {
    final raw = preferences.getString(_storageKey);
    if (raw != null) {
      try {
        final submissions = (jsonDecode(raw) as List<dynamic>)
            .map(
              (item) => PendingScoreSubmission.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
        await preferences.remove(_legacyStorageKey);
        return submissions;
      } catch (_) {
        await preferences.remove(_storageKey);
      }
    }

    final legacyRaw = preferences.getString(_legacyStorageKey);
    if (legacyRaw == null) return [];
    try {
      final legacy = PendingScoreSubmission.fromJson(
        Map<String, dynamic>.from(jsonDecode(legacyRaw) as Map),
      );
      await preferences.remove(_legacyStorageKey);
      return [legacy];
    } catch (_) {
      await preferences.remove(_legacyStorageKey);
      return [];
    }
  }

  Future<void> _writeAll(
    SharedPreferences preferences,
    List<PendingScoreSubmission> submissions,
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
