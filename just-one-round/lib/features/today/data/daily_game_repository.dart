import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class DailyGameRepository {
  Future<TodayState> fetchToday();
  Future<PlayAttempt> claimDailyAttempt();
  Future<PlayAttempt> claimRewardedAttempt();
  Future<void> expireAttempt(String attemptId);
  Future<DailyRankResult> submitScore(String attemptId, GameResult result);
  Future<UserProfile> setNickname(String nickname);
  Future<UserProfile> updateDemographics({
    required int? birthDecade,
    required ProfileGender? gender,
  });
  Future<DailyRankResult> fetchFilteredRank({
    int? birthDecade,
    ProfileGender? gender,
  });
  Future<List<PlayHistoryEntry>> fetchHistory();
}

final dailyGameRepositoryProvider = Provider<DailyGameRepository>(
  (ref) => PreviewDailyGameRepository(),
);

final todayStateProvider = FutureProvider<TodayState>((ref) async {
  return ref.watch(dailyGameRepositoryProvider).fetchToday();
});

class SupabaseDailyGameRepository implements DailyGameRepository {
  SupabaseDailyGameRepository(this._client);

  final SupabaseClient _client;
  var _sessionValidated = false;

  Future<void> _ensureSignedIn() async {
    if (_client.auth.currentSession == null) {
      await _client.auth.signInAnonymously();
      _sessionValidated = true;
      return;
    }
    if (_sessionValidated) return;
    try {
      await _client.auth.getUser();
    } on AuthException {
      await _client.auth.signOut(scope: SignOutScope.local);
      await _client.auth.signInAnonymously();
    }
    _sessionValidated = true;
  }

  @override
  Future<TodayState> fetchToday() async {
    await _ensureSignedIn();
    var state = TodayState.fromJson(
      Map<String, dynamic>.from(await _client.rpc('get_today_state') as Map),
    );

    final interrupted = state.attempts
        .where((attempt) => attempt.status == 'issued')
        .toList(growable: false);
    if (interrupted.isNotEmpty) {
      for (final attempt in interrupted) {
        try {
          await expireAttempt(attempt.id);
        } on PostgrestException {
          // Another lifecycle callback may already have expired it.
        }
      }
      state = TodayState.fromJson(
        Map<String, dynamic>.from(await _client.rpc('get_today_state') as Map),
      );
    }
    return state;
  }

  @override
  Future<PlayAttempt> claimDailyAttempt() async {
    await _ensureSignedIn();
    return _attemptFromRpc(await _client.rpc('claim_daily_attempt'));
  }

  @override
  Future<PlayAttempt> claimRewardedAttempt() async {
    await _ensureSignedIn();
    return _attemptFromRpc(await _client.rpc('claim_rewarded_attempt'));
  }

  @override
  Future<void> expireAttempt(String attemptId) async {
    await _ensureSignedIn();
    await _client.rpc('expire_attempt', params: {'attempt_id': attemptId});
  }

  @override
  Future<DailyRankResult> submitScore(
    String attemptId,
    GameResult result,
  ) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'submit_daily_score',
      params: {
        'attempt_id': attemptId,
        'stars_collected': result.starsCollected,
        'collisions': result.collisions,
        'duration_ms': result.duration.inMilliseconds,
      },
    );
    return DailyRankResult.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<UserProfile> setNickname(String nickname) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'set_my_nickname',
      params: {'new_nickname': nickname},
    );
    return UserProfile.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<UserProfile> updateDemographics({
    required int? birthDecade,
    required ProfileGender? gender,
  }) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'update_my_demographics',
      params: {'new_birth_decade': birthDecade, 'new_gender': gender?.value},
    );
    return UserProfile.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<DailyRankResult> fetchFilteredRank({
    int? birthDecade,
    ProfileGender? gender,
  }) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'get_filtered_daily_result',
      params: {
        'filter_birth_decade': birthDecade,
        'filter_gender': gender?.value,
      },
    );
    return DailyRankResult.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_my_play_history');
    return (response as List<dynamic>)
        .map(
          (item) =>
              PlayHistoryEntry.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  PlayAttempt _attemptFromRpc(dynamic response) {
    return PlayAttempt.fromJson(Map<String, dynamic>.from(response as Map));
  }
}

class PreviewDailyGameRepository implements DailyGameRepository {
  final _attempt = const PlayAttempt(
    id: 'preview-attempt',
    ordinal: 1,
    status: 'issued',
    grantType: 'daily',
  );

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime.now(),
    game: const TodayGame(
      id: 'star_dodge',
      version: 1,
      displayName: '별빛 피하기',
      description: '장애물을 피하고 별을 모아\n오늘의 최고 기록에 도전하세요.',
      durationSeconds: 60,
    ),
    attempts: const [],
    adAttemptAvailable: false,
    result: const DailyRankResult(
      score: null,
      rank: null,
      participants: 0,
      topPercent: null,
      nickname: null,
      nearby: [],
    ),
    profile: const UserProfile(nickname: null, birthDecade: null, gender: null),
  );

  @override
  Future<PlayAttempt> claimDailyAttempt() async => _attempt;

  @override
  Future<PlayAttempt> claimRewardedAttempt() async => _attempt;

  @override
  Future<void> expireAttempt(String attemptId) async {}

  @override
  Future<DailyRankResult> submitScore(
    String attemptId,
    GameResult result,
  ) async => DailyRankResult(
    score: result.score,
    rank: 1,
    participants: 1,
    topPercent: 1,
    nickname: '테스트',
    nearby: [
      NearbyRank(rank: 1, nickname: '테스트', score: result.score, isMe: true),
    ],
  );

  @override
  Future<UserProfile> setNickname(String nickname) async =>
      UserProfile(nickname: nickname, birthDecade: null, gender: null);

  @override
  Future<UserProfile> updateDemographics({
    required int? birthDecade,
    required ProfileGender? gender,
  }) async =>
      UserProfile(nickname: '테스트', birthDecade: birthDecade, gender: gender);

  @override
  Future<DailyRankResult> fetchFilteredRank({
    int? birthDecade,
    ProfileGender? gender,
  }) async => const DailyRankResult(
    score: null,
    rank: null,
    participants: 0,
    topPercent: null,
    nickname: null,
    nearby: [],
  );

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async => const [];
}
