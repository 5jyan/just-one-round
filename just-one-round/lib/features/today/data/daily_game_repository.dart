import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/data/pending_score_submission.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class DailyGameRepository {
  Future<TodayState> fetchToday();
  Future<PlayAttempt> claimDailyAttempt();
  Future<PlayAttempt> claimRewardedAttempt();
  Future<void> expireAttempt(String attemptId);
  Future<DailyRankResult> submitScore(String attemptId, GameResult result);
  Future<DailyRankResult?> retryPendingScore();
  Future<UserProfile> setNickname(String nickname);
  Future<UserProfile> updateDemographics({
    required int? birthYear,
    required int? birthMonth,
    required ProfileGender? gender,
  });
  Future<DailyRankResult> fetchFilteredRank({
    int? birthDecade,
    ProfileGender? gender,
  });
  Future<List<PlayHistoryEntry>> fetchHistory();
  Future<List<DeveloperGame>> fetchDeveloperGames();
  Future<void> enableTestMode();
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
    final pending = await _pendingStore.load();
    await retryPendingScore();
    var state = TodayState.fromJson(
      Map<String, dynamic>.from(await _client.rpc('get_today_state') as Map),
    );

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
    final pending = PendingScoreSubmission.fromGameResult(attemptId, result);
    return _pendingScoreRetry.sendAndPersist(pending, _submitPendingScore);
  }

  @override
  Future<DailyRankResult?> retryPendingScore() async {
    await _ensureSignedIn();
    return _pendingScoreRetry.retry(_submitPendingScore);
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
    required int? birthYear,
    required int? birthMonth,
    required ProfileGender? gender,
  }) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'update_my_demographics',
      params: {
        'new_birth_year': birthYear,
        'new_birth_month': birthMonth,
        'new_gender': gender?.value,
      },
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
  Future<void> enableTestMode() async {
    await _ensureSignedIn();
    await _client.rpc('enable_my_test_account');
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
    return PlayAttempt.fromJson(Map<String, dynamic>.from(response as Map));
  }
}

class PreviewDailyGameRepository implements DailyGameRepository {
  PreviewDailyGameRepository({this.testMode = false});

  bool testMode;
  String _selectedGameId = 'dung_dodge_v2';

  static const _games = [
    DeveloperGame(id: 'star_dodge', version: 1, displayName: '별빛 피하기'),
    DeveloperGame(id: 'dung_dodge_v2', version: 1, displayName: '똥피하기 2'),
    DeveloperGame(id: 'gravity_switch', version: 1, displayName: '그래비티 스위치'),
    DeveloperGame(id: 'failed_bakery', version: 1, displayName: '대충 케이크'),
    DeveloperGame(id: 'apple_game', version: 1, displayName: '사과게임'),
    DeveloperGame(id: 'apple_game_v2', version: 1, displayName: '사과게임 2'),
    DeveloperGame(id: 'number_rush', version: 1, displayName: '넘버 러시'),
  ];

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: DateTime.now(),
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
    profile: UserProfile(
      nickname: testMode ? 'tester' : null,
      birthYear: null,
      birthMonth: null,
      gender: null,
    ),
  );

  @override
  Future<PlayAttempt> claimDailyAttempt() async => _previewAttempt('daily');

  @override
  Future<PlayAttempt> claimRewardedAttempt() async =>
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
  Future<UserProfile> setNickname(String nickname) async => UserProfile(
    nickname: nickname,
    birthYear: null,
    birthMonth: null,
    gender: null,
  );

  @override
  Future<UserProfile> updateDemographics({
    required int? birthYear,
    required int? birthMonth,
    required ProfileGender? gender,
  }) async => UserProfile(
    nickname: '테스트',
    birthYear: birthYear,
    birthMonth: birthMonth,
    gender: gender,
  );

  @override
  Future<DailyRankResult> fetchFilteredRank({
    int? birthDecade,
    ProfileGender? gender,
  }) async => const DailyRankResult(
    score: null,
    rank: null,
    participants: 24,
    topPercent: null,
    nickname: null,
    bestScore: 5387,
    nearby: [],
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
    ],
  );

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async => const [];

  @override
  Future<List<DeveloperGame>> fetchDeveloperGames() async => _games;

  @override
  Future<void> enableTestMode() async {
    testMode = true;
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
  );

  TodayGame _previewGame(String gameId) => switch (gameId) {
    'dung_dodge_v2' => const TodayGame(
      id: 'dung_dodge_v2',
      version: 1,
      displayName: '똥피하기 2',
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
    'failed_bakery' => const TodayGame(
      id: 'failed_bakery',
      version: 1,
      displayName: '대충 케이크',
      description: '움직이는 못난이 케이크를 탭해 쌓으세요.',
      durationSeconds: 180,
    ),
    'apple_game' => const TodayGame(
      id: 'apple_game',
      version: 1,
      displayName: '사과게임',
      description: '드래그한 사과 숫자의 합을 10으로 만들어 최대한 많이 지우세요.',
      durationSeconds: 120,
    ),
    'apple_game_v2' => const TodayGame(
      id: 'apple_game_v2',
      version: 1,
      displayName: '사과게임 2',
      description: '달빛 과수원에서 사과 숫자의 합을 10으로 만들어 최대한 많이 지우세요.',
      durationSeconds: 120,
    ),
    'number_rush' => const TodayGame(
      id: 'number_rush',
      version: 1,
      displayName: '넘버 러시',
      description: '숫자를 1부터 50까지 순서대로 최대한 빠르게 터치하세요.',
      durationSeconds: 180,
    ),
    _ => const TodayGame(
      id: 'star_dodge',
      version: 1,
      displayName: '별빛 피하기',
      description: '장애물을 피하고 별을 모아\n오늘의 최고 기록에 도전하세요.',
      durationSeconds: 60,
    ),
  };
}
