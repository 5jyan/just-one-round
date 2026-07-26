import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/data/pending_score_submission.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_session.dart';
import 'package:just_one_round/features/today/domain/daily_reset.dart';
import 'package:just_one_round/features/today/domain/previous_daily_result.dart';
import 'package:just_one_round/features/today/domain/tester_activation_result.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class DailyGameRepository {
  Future<TodayState> fetchToday();
  Future<PlayAttempt> claimDailyAttempt(DateTime expectedPlayDate);
  Future<RewardedAdSession> prepareRewardedAd(DateTime expectedPlayDate);
  Future<PlayAttempt> claimRewardedAttempt(String rewardSessionId);
  Future<void> expireAttempt(String attemptId);
  Future<DailyRankResult> submitScore(String attemptId, GameResult result);
  Future<DailyRankResult?> retryPendingScore();
  Future<void> setNickname(String nickname);
  Future<DailyRankResult> fetchDailyRank();
  Future<List<PlayHistoryEntry>> fetchHistory();
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult();
  Future<void> acknowledgePreviousDailyResult(DateTime playDate, String gameId);
  Future<List<DeveloperGame>> fetchDeveloperGames();
  Future<void> reportNickname(String userId);
  Future<void> blockUser(String userId);
  Future<void> deleteAccount();
  Future<TesterActivationResult> activateTestMode(String pin);
  Future<void> resetDeveloperDailyProgress();
  Future<void> setDeveloperGame(String gameId);
}

final dailyGameRepositoryProvider = Provider<DailyGameRepository>(
  (ref) => PreviewDailyGameRepository(),
);

final todayStateProvider = FutureProvider<TodayState>((ref) async {
  return ref
      .watch(dailyGameRepositoryProvider)
      .fetchToday()
      .timeout(const Duration(seconds: 12));
});

class AppUpdateRequiredException implements Exception {
  const AppUpdateRequiredException(this.reason);

  final String reason;

  @override
  String toString() => 'AppUpdateRequiredException: $reason';
}

class SupabaseDailyGameRepository implements DailyGameRepository {
  SupabaseDailyGameRepository(this._client, {PendingScoreStore? pendingStore})
    : _pendingStore = pendingStore ?? SharedPreferencesPendingScoreStore();

  final SupabaseClient _client;
  final PendingScoreStore _pendingStore;
  late final _pendingScoreRetry = PendingScoreRetryService<DailyRankResult>(
    _pendingStore,
  );
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
    final compatibility = await _fetchClientCompatibility();
    if (compatibility.updateRequired) {
      return _blockedState(compatibility);
    }

    final pending = await _pendingStore.load();
    var state = TodayState.fromJson(
      Map<String, dynamic>.from(await _client.rpc('get_today_state') as Map),
    );
    final unsupported = _unsupportedGameCompatibility(state, compatibility);
    if (unsupported != null) {
      return state.withCompatibility(unsupported);
    }

    await retryPendingScore();

    final interrupted = state.attempts
        .where((attempt) => attempt.status == 'issued')
        .where((attempt) => attempt.id != pending?.attemptId)
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
      final unsupported = _unsupportedGameCompatibility(state, compatibility);
      if (unsupported != null) {
        return state.withCompatibility(unsupported);
      }
    }
    return state.withCompatibility(compatibility);
  }

  Future<ClientCompatibility> _fetchClientCompatibility() async {
    final response = await _client.rpc('get_client_compatibility');
    return ClientCompatibility.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  TodayState _blockedState(ClientCompatibility compatibility) => TodayState(
    playDate: dailyPlayDateAt(DateTime.now()),
    game: null,
    attempts: const [],
    adAttemptAvailable: false,
    testMode: false,
    result: null,
    nickname: null,
    compatibility: compatibility,
  );

  ClientCompatibility? _unsupportedGameCompatibility(
    TodayState state,
    ClientCompatibility compatibility,
  ) {
    final game = state.game;
    if (game == null || GameRegistry.supports(game.id, game.version)) {
      return null;
    }
    return compatibility.requiringUpdate(reason: 'unsupported_game');
  }

  @override
  Future<PlayAttempt> claimDailyAttempt(DateTime expectedPlayDate) async {
    await _ensureSignedIn();
    return _attemptFromRpc(
      await _client.rpc(
        'claim_daily_attempt',
        params: {'expected_play_date': playDateParameter(expectedPlayDate)},
      ),
    );
  }

  @override
  Future<RewardedAdSession> prepareRewardedAd(DateTime expectedPlayDate) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'prepare_rewarded_ad',
      params: {'expected_play_date': playDateParameter(expectedPlayDate)},
    );
    return RewardedAdSession.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<PlayAttempt> claimRewardedAttempt(String rewardSessionId) async {
    await _ensureSignedIn();
    return _attemptFromRpc(
      await _client.rpc(
        'claim_rewarded_attempt',
        params: {'reward_session_id': rewardSessionId},
      ),
    );
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
    final pending = PendingScoreSubmission.fromGameResult(attemptId, result);
    return _pendingScoreRetry.sendAndPersist(pending, _submitPendingScore);
  }

  @override
  Future<DailyRankResult?> retryPendingScore() async {
    await _ensureSignedIn();
    return _pendingScoreRetry.retry(
      _submitPendingScore,
      discardWhen: (error) =>
          error is PostgrestException &&
          error.message.contains('score submission window closed'),
    );
  }

  Future<DailyRankResult> _submitPendingScore(
    PendingScoreSubmission pending,
  ) async {
    final response = await _client.rpc(
      'submit_daily_score',
      params: {
        'attempt_id': pending.attemptId,
        'raw_score': pending.rawScore,
        'stars_collected': pending.starsCollected,
        'collisions': pending.collisions,
        'duration_ms': pending.durationMs,
      },
    );
    return DailyRankResult.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<void> setNickname(String nickname) async {
    await _ensureSignedIn();
    await _client.rpc('set_my_nickname', params: {'new_nickname': nickname});
  }

  @override
  Future<DailyRankResult> fetchDailyRank() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_my_daily_result');
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

  @override
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_unseen_previous_daily_result');
    if (response == null) return null;
    return PreviousDailyResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<void> acknowledgePreviousDailyResult(
    DateTime playDate,
    String gameId,
  ) async {
    await _ensureSignedIn();
    await _client.rpc(
      'acknowledge_previous_daily_result',
      params: {
        'target_date': playDateParameter(playDate),
        'target_game_id': gameId,
      },
    );
  }

  @override
  Future<List<DeveloperGame>> fetchDeveloperGames() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_developer_games');
    return (response as List<dynamic>)
        .map(
          (item) =>
              DeveloperGame.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> reportNickname(String userId) async {
    await _ensureSignedIn();
    await _client.rpc('report_nickname', params: {'reported_user_id': userId});
  }

  @override
  Future<void> blockUser(String userId) async {
    await _ensureSignedIn();
    await _client.rpc('block_user', params: {'blocked_user_id': userId});
  }

  @override
  Future<void> deleteAccount() async {
    await _ensureSignedIn();
    final response = await _client.functions.invoke(
      'delete-account',
      method: HttpMethod.post,
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('account deletion failed');
    }
    await _pendingStore.clear();
    await _client.auth.signOut(scope: SignOutScope.local);
  }

  @override
  Future<TesterActivationResult> activateTestMode(String pin) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'activate_test_mode',
      params: {'tester_pin': pin},
    );
    return TesterActivationResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<void> resetDeveloperDailyProgress() async {
    await _ensureSignedIn();
    await _client.rpc('reset_developer_daily_progress');
    await _pendingStore.clear();
  }

  @override
  Future<void> setDeveloperGame(String gameId) async {
    await _ensureSignedIn();
    await _client.rpc(
      'set_developer_game',
      params: {'selected_game_id': gameId},
    );
    await _pendingStore.clear();
  }

  PlayAttempt _attemptFromRpc(dynamic response) {
    final attempt = PlayAttempt.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
    if (!GameRegistry.supports(attempt.gameId, attempt.gameVersion)) {
      throw const AppUpdateRequiredException('unsupported_game');
    }
    return attempt;
  }
}

class PreviewDailyGameRepository implements DailyGameRepository {
  PreviewDailyGameRepository({
    this.testMode = false,
    this.compatibility = const ClientCompatibility.supported(),
  });

  bool testMode;
  final ClientCompatibility compatibility;
  String _selectedGameId = 'dung_dodge_v2';

  static const _games = [
    DeveloperGame(id: 'dung_dodge_v2', version: 1, displayName: '똥피하기'),
    DeveloperGame(id: 'gravity_switch', version: 1, displayName: '그래비티 스위치'),
    DeveloperGame(id: 'apple_game_v2', version: 1, displayName: '사과게임'),
    DeveloperGame(id: 'number_rush', version: 1, displayName: '탭50'),
  ];

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: dailyPlayDateAt(DateTime.now()),
    game: _previewGame(_selectedGameId),
    attempts: const [],
    adAttemptAvailable: false,
    testMode: testMode,
    result: const DailyRankResult(
      score: 2978,
      rank: 8,
      participants: 24,
      topPercent: 34,
      nickname: 'tester',
      bestScore: 5387,
      nearby: [
        NearbyRank(
          rank: 7,
          nickname: '말랑주먹',
          score: 3146,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(rank: 8, nickname: 'tester', score: 2978, isMe: true),
        NearbyRank(
          rank: 9,
          nickname: '느린번개',
          score: 2811,
          isMe: false,
          isNpc: true,
        ),
      ],
      leaders: [
        NearbyRank(
          rank: 1,
          nickname: '작은공룡',
          score: 5387,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(
          rank: 2,
          nickname: '졸린감자',
          score: 4729,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(
          rank: 3,
          nickname: '한번만더',
          score: 4312,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(
          rank: 4,
          nickname: '공룡발자국',
          score: 3895,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(
          rank: 5,
          nickname: '퇴근요정',
          score: 3514,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(
          rank: 6,
          nickname: '새벽질주',
          score: 3328,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(
          rank: 7,
          nickname: '말랑주먹',
          score: 3146,
          isMe: false,
          isNpc: true,
        ),
        NearbyRank(rank: 8, nickname: 'tester', score: 2978, isMe: false),
      ],
    ),
    nickname: testMode ? 'tester' : null,
    compatibility: compatibility,
  );

  @override
  Future<PlayAttempt> claimDailyAttempt(DateTime expectedPlayDate) async =>
      _previewAttempt('daily');

  @override
  Future<RewardedAdSession> prepareRewardedAd(
    DateTime expectedPlayDate,
  ) async => RewardedAdSession(
    id: '00000000-0000-4000-8000-000000000001',
    userId: 'preview-user',
    status: 'prepared',
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
  );

  @override
  Future<PlayAttempt> claimRewardedAttempt(String rewardSessionId) async =>
      _previewAttempt('rewarded');

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
  Future<DailyRankResult?> retryPendingScore() async => null;

  @override
  Future<void> setNickname(String nickname) async {}

  @override
  Future<DailyRankResult> fetchDailyRank() async => const DailyRankResult(
    score: 2978,
    rank: 8,
    participants: 24,
    topPercent: 34,
    nickname: 'tester',
    bestScore: 5387,
    nearby: [NearbyRank(rank: 8, nickname: 'tester', score: 2978, isMe: true)],
  );

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async => const [];

  @override
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult() async => null;

  @override
  Future<void> acknowledgePreviousDailyResult(
    DateTime playDate,
    String gameId,
  ) async {}

  @override
  Future<List<DeveloperGame>> fetchDeveloperGames() async => _games;

  @override
  Future<void> reportNickname(String userId) async {}

  @override
  Future<void> blockUser(String userId) async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<TesterActivationResult> activateTestMode(String pin) async {
    testMode = true;
    return const TesterActivationResult(
      status: TesterActivationStatus.activated,
    );
  }

  @override
  Future<void> resetDeveloperDailyProgress() async {}

  @override
  Future<void> setDeveloperGame(String gameId) async {
    if (_games.any((game) => game.id == gameId)) {
      _selectedGameId = gameId;
    }
  }

  PlayAttempt _previewAttempt(String grantType) => PlayAttempt(
    id: 'preview-attempt',
    ordinal: 1,
    status: 'issued',
    grantType: grantType,
    gameId: _selectedGameId,
    gameVersion: 1,
  );

  TodayGame _previewGame(String gameId) => switch (gameId) {
    'dung_dodge_v2' => const TodayGame(
      id: 'dung_dodge_v2',
      version: 1,
      displayName: '똥피하기',
      description: '좌우로 움직여 떨어지는 똥을 피하세요.',
      durationSeconds: 300,
    ),
    'gravity_switch' => const TodayGame(
      id: 'gravity_switch',
      version: 1,
      displayName: '그래비티 스위치',
      description: '탭으로 중력을 뒤집어 위아래로 이어지는 입체 기둥 미로를 돌파하세요.',
      durationSeconds: 180,
    ),
    'apple_game_v2' => const TodayGame(
      id: 'apple_game_v2',
      version: 1,
      displayName: '사과게임',
      description: '달빛 과수원에서 사과 숫자의 합을 10으로 만들어 최대한 많이 지우세요.',
      durationSeconds: 120,
    ),
    'number_rush' => const TodayGame(
      id: 'number_rush',
      version: 1,
      displayName: '탭50',
      description: '숫자를 1부터 50까지 순서대로 최대한 빠르게 터치하세요.',
      durationSeconds: 180,
    ),
    _ => throw UnsupportedError('Unsupported preview game id: $gameId'),
  };
}
