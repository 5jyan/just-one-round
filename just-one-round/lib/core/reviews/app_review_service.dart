import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AppReviewClient {
  Future<bool> isAvailable();

  Future<void> requestReview();
}

class InAppReviewClient implements AppReviewClient {
  const InAppReviewClient();

  @override
  Future<bool> isAvailable() => InAppReview.instance.isAvailable();

  @override
  Future<void> requestReview() => InAppReview.instance.requestReview();
}

final appReviewServiceProvider = Provider<AppReviewService>(
  (ref) => AppReviewService(),
);

class AppReviewService {
  AppReviewService({
    AppReviewClient? client,
    Future<SharedPreferences>? preferences,
    DateTime Function()? now,
  }) : _client = client ?? const InAppReviewClient(),
       _preferences = preferences ?? SharedPreferences.getInstance(),
       _now = now ?? DateTime.now;

  static const lastRequestedAtStorageKey = 'app_review_last_requested_utc_v1';
  static const reviewInterval = Duration(days: 90);
  static const requiredCompletedPlayDates = 3;

  final AppReviewClient _client;
  final Future<SharedPreferences> _preferences;
  final DateTime Function() _now;
  Future<void>? _inFlight;
  var _pending = false;

  bool get hasPendingRequest => _pending;

  void markPending() {
    _pending = true;
  }

  Future<void> consumePending({
    required Future<List<PlayHistoryEntry>> Function() fetchHistory,
    required FutureOr<bool> Function() canRequest,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final operation = _consumePending(
      fetchHistory: fetchHistory,
      canRequest: canRequest,
    );
    _inFlight = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_inFlight, operation)) _inFlight = null;
      }),
    );
    return operation;
  }

  Future<void> _consumePending({
    required Future<List<PlayHistoryEntry>> Function() fetchHistory,
    required FutureOr<bool> Function() canRequest,
  }) async {
    if (!_pending) return;

    try {
      if (!await canRequest()) return;

      late final SharedPreferences preferences;
      try {
        preferences = await _preferences;
      } catch (_) {
        _pending = false;
        return;
      }
      final now = _now().toUtc();
      final lastRequestedAt = _readLastRequestedAt(preferences);
      if (lastRequestedAt != null &&
          now.isBefore(lastRequestedAt.add(reviewInterval))) {
        // The current completed play was before the next review window. A
        // later completed play must create a fresh pending request.
        _pending = false;
        return;
      }

      if (!await canRequest()) return;

      final history = await fetchHistory();
      if (!await canRequest()) return;

      final completedPlayDates = history
          .map((entry) => _playDateKey(entry.playDate))
          .toSet();
      if (completedPlayDates.length < requiredCompletedPlayDates) {
        _pending = false;
        return;
      }

      if (!await canRequest()) return;

      late final bool available;
      try {
        available = await _client.isAvailable();
      } catch (_) {
        _pending = false;
        return;
      }
      if (!available) {
        _pending = false;
        return;
      }
      if (!await canRequest()) return;

      final requestedAt = _now().toUtc();
      late final bool stored;
      try {
        stored = await preferences.setString(
          lastRequestedAtStorageKey,
          requestedAt.toIso8601String(),
        );
      } catch (_) {
        _pending = false;
        return;
      }
      if (!stored) return;
      if (!await canRequest()) {
        await _removeLastRequestedAt(preferences);
        return;
      }

      _pending = false;
      try {
        await _client.requestReview();
      } catch (_) {
        // Keep a failed native call from immediately looping on the next
        // home rebuild. A future completed play can try again.
        await _removeLastRequestedAt(preferences);
      }
    } catch (_) {
      // Review prompts are best effort and must never affect gameplay or home.
    }
  }

  DateTime? _readLastRequestedAt(SharedPreferences preferences) {
    final raw = preferences.getString(lastRequestedAtStorageKey);
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
    return null;
  }

  Future<void> _removeLastRequestedAt(SharedPreferences preferences) async {
    try {
      await preferences.remove(lastRequestedAtStorageKey);
    } catch (_) {
      // Best effort cleanup only.
    }
  }

  String _playDateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
