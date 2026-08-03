import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:just_one_round/core/auth/anonymous_session_guard.dart';
import 'package:just_one_round/core/auth/device_registration_guard.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/data/pending_score_submission.dart';
import 'package:just_one_round/features/economy/domain/economy_transaction.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
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
  Future<RewardedAdSession> preparePracticeAd(DateTime expectedPlayDate);
  Future<PlayAttempt> claimPracticeAttempt(String rewardSessionId);
  Future<void> expireAttempt(String attemptId);
  Future<DailyRankResult> submitScore(String attemptId, GameResult result);
  Future<DailyRankResult?> retryPendingScore();
  Future<void> setNickname(String nickname);
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate});
  Future<List<PlayHistoryEntry>> fetchHistory();
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult();
  Future<RewardGrant> acknowledgePreviousDailyResult(
    DateTime playDate,
    String gameId,
  );
  Future<CoinSpendResult> spendCoins({
    required int amount,
    required String gameId,
    required String referenceId,
  });
  Future<List<DeveloperGame>> fetchDeveloperGames();
  Future<void> reportNickname(String userId);
  Future<void> blockUser(String userId);
  Future<void> deleteAccount();
  Future<TesterActivationResult> activateTestMode(String pin);
  Future<void> deactivateTestMode();
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

final dailyRankProvider = FutureProvider.autoDispose
    .family<DailyRankResult, DateTime>(
      (ref, playDate) => ref
          .watch(dailyGameRepositoryProvider)
          .fetchDailyRank(playDate: playDate),
    );

class AppUpdateRequiredException implements Exception {
  const AppUpdateRequiredException(this.reason);

  final String reason;

  @override
  String toString() => 'AppUpdateRequiredException: $reason';
}

class SupabaseDailyGameRepository implements DailyGameRepository {
  SupabaseDailyGameRepository(
    this._client, {
    PendingScoreStore? pendingStore,
    Future<String> Function()? deviceHashLoader,
  }) : _deviceHashLoader = deviceHashLoader ?? readDeviceInstallHash,
       _pendingStore = pendingStore ?? SharedPreferencesPendingScoreStore(),
       _sessionGuard = AnonymousSessionGuard(
         hasSession: () => _client.auth.currentSession != null,
         signInAnonymously: () async {
           await _client.auth.signInAnonymously();
         },
       );

  final SupabaseClient _client;
  final Future<String> Function() _deviceHashLoader;
  final PendingScoreStore _pendingStore;
  final AnonymousSessionGuard _sessionGuard;
  late final DeviceRegistrationGuard _deviceRegistration =
      DeviceRegistrationGuard(
        currentUserId: () => _client.auth.currentUser?.id,
        readDeviceHash: _deviceHashLoader,
        registerDevice: (deviceHash) async {
          await _client.rpc(
            'register_device_installation',
            params: {'device_hash': deviceHash},
          );
        },
      );
  late final _pendingScoreRetry = PendingScoreRetryService<DailyRankResult>(
    _pendingStore,
  );

  Future<void> _ensureSignedIn() async {
    await _sessionGuard.ensureSignedIn();
    await _deviceRegistration.ensureRegistered();
  }

  @override
  Future<TodayState> fetchToday() async {
    await _ensureSignedIn();
    final compatibility = await _fetchClientCompatibility();
    if (compatibility.updateRequired) {
      return _blockedState(compatibility);
    }

    var state = TodayState.fromJson(
      Map<String, dynamic>.from(await _client.rpc('get_today_state') as Map),
    );
    final unsupported = _unsupportedGameCompatibility(state, compatibility);
    if (unsupported != null) {
      return state.withCompatibility(unsupported);
    }

    state = await refreshStateAfterPendingRetry(
      currentState: state,
      retry: retryPendingScore,
      refresh: () async => TodayState.fromJson(
        Map<String, dynamic>.from(await _client.rpc('get_today_state') as Map),
      ),
    );
    // A terminal server rejection removes the saved payload. Re-read the
    // store so that the now-unrecoverable issued attempt is expired during
    // this same refresh instead of surviving for one extra app launch.
    final pending = await _pendingStore.loadAll();
    final recoveredUnsupported = _unsupportedGameCompatibility(
      state,
      compatibility,
    );
    if (recoveredUnsupported != null) {
      return state.withCompatibility(recoveredUnsupported);
    }

    final interrupted = issuedAttemptsWithoutPending(
      state,
      pending.map((submission) => submission.attemptId).toSet(),
    );
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
    economy: const PlayerEconomy.zero(),
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
    try {
      return await _claimDailyAttempt(expectedPlayDate);
    } on PostgrestException catch (error) {
      if (!error.message.contains('device registration required')) rethrow;

      // A restored Android session or another installation can leave the
      // in-memory registration cache newer than the server-side association.
      // The claim has not been issued when this error is raised, so one
      // registration refresh and retry is safe.
      await _deviceRegistration.registerAgain();
      return _claimDailyAttempt(expectedPlayDate);
    }
  }

  Future<PlayAttempt> _claimDailyAttempt(DateTime expectedPlayDate) async =>
      _attemptFromRpc(
        await _client.rpc(
          'claim_daily_attempt',
          params: {'expected_play_date': playDateParameter(expectedPlayDate)},
        ),
      );

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
  Future<RewardedAdSession> preparePracticeAd(DateTime expectedPlayDate) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'prepare_practice_ad',
      params: {'expected_play_date': playDateParameter(expectedPlayDate)},
    );
    return RewardedAdSession.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<PlayAttempt> claimPracticeAttempt(String rewardSessionId) async {
    await _ensureSignedIn();
    return _attemptFromRpc(
      await _client.rpc(
        'claim_practice_attempt',
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
    final pending = PendingScoreSubmission.fromGameResult(attemptId, result);
    // Persist the completed result before any authentication or network work.
    // If session recovery fails, the next app launch can still retry it.
    await _pendingStore.save(pending);
    await _ensureSignedIn();
    return _pendingScoreRetry.sendPersisted(pending, _submitPendingScore);
  }

  @override
  Future<DailyRankResult?> retryPendingScore() async {
    await _ensureSignedIn();
    return _pendingScoreRetry.retry(
      _submitPendingScore,
      discardWhen: isTerminalScoreSubmissionError,
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
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'get_my_daily_result',
      params: playDate == null
          ? null
          : {'target_date': playDateParameter(playDate)},
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
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_unseen_previous_daily_result');
    if (response == null) return null;
    return PreviousDailyResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<RewardGrant> acknowledgePreviousDailyResult(
    DateTime playDate,
    String gameId,
  ) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'acknowledge_previous_daily_result',
      params: {
        'target_date': playDateParameter(playDate),
        'target_game_id': gameId,
      },
    );
    return RewardGrant.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<CoinSpendResult> spendCoins({
    required int amount,
    required String gameId,
    required String referenceId,
  }) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'spend_coins',
      params: {
        'amount': amount,
        'game_id': gameId,
        'reference_id': referenceId,
      },
    );
    return CoinSpendResult.fromJson(Map<String, dynamic>.from(response as Map));
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
  Future<void> deactivateTestMode() async {
    await _ensureSignedIn();
    await _client.rpc('deactivate_test_mode');
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

List<PlayAttempt> issuedAttemptsWithoutPending(
  TodayState state,
  Set<String> pendingAttemptIds, {
  DateTime? now,
}) {
  final currentTime = (now ?? DateTime.now()).toUtc();
  return state.attempts
      .where((attempt) => attempt.status == 'issued')
      .where((attempt) => !pendingAttemptIds.contains(attempt.id))
      .where((attempt) => _isStaleIssuedAttempt(attempt, currentTime))
      .toList(growable: false);
}

bool _isStaleIssuedAttempt(PlayAttempt attempt, DateTime now) {
  final issuedAt = attempt.issuedAt;
  // Keep the old cleanup behavior for older API responses that do not expose
  // issued_at yet. Current responses include it, which lets us avoid expiring
  // a freshly claimed attempt while an ad-return refresh is still in flight.
  if (issuedAt == null) return true;

  final durationSeconds = attempt.gameDurationSeconds ?? 300;
  final playableSeconds = durationSeconds < 1 ? 1 : durationSeconds;
  final expiry = issuedAt.toUtc().add(
    Duration(seconds: playableSeconds) + const Duration(minutes: 2),
  );
  return !now.isBefore(expiry);
}

bool isTerminalScoreSubmissionError(Object error) {
  if (error is! PostgrestException) return false;
  const terminalMessages = <String>[
    'score submission window closed',
    'attempt expired',
    'attempt not found',
    'active attempt not found',
    'game version not found',
    'active game version not found',
    'unsupported game result',
    'invalid dung dodge v2 result',
    'invalid gravity switch result',
    'invalid apple game v2 result',
    'invalid number rush result',
    'invalid mama duck trail result',
    'invalid sausage dachshund result',
    'invalid midnight snake result',
    'invalid beat the dealer result',
  ];
  return terminalMessages.any(error.message.contains);
}

Future<T> refreshStateAfterPendingRetry<T, R>({
  required T currentState,
  required Future<R?> Function() retry,
  required Future<T> Function() refresh,
}) async {
  final recovered = await retry();
  return recovered == null ? currentState : refresh();
}

class PreviewDailyGameRepository implements DailyGameRepository {
  PreviewDailyGameRepository({
    this.testMode = false,
    this.compatibility = const ClientCompatibility.supported(),
    this.initialEconomy = const PlayerEconomy.zero(),
  });

  bool testMode;
  final ClientCompatibility compatibility;
  final PlayerEconomy initialEconomy;
  late PlayerEconomy _economy = initialEconomy;
  String _selectedGameId = 'dung_dodge_v2';

  static const _games = [
    DeveloperGame(id: 'dung_dodge_v2', version: 1, displayName: '똥피하기'),
    DeveloperGame(id: 'gravity_switch', version: 1, displayName: '중력 스위치'),
    DeveloperGame(id: 'apple_game_v2', version: 1, displayName: '사과게임'),
    DeveloperGame(id: 'number_rush', version: 1, displayName: '탭50'),
    DeveloperGame(id: 'mama_duck_trail', version: 1, displayName: '엄마, 어디가'),
    DeveloperGame(id: 'midnight_snake', version: 2, displayName: '야식털이 뱀'),
    DeveloperGame(id: 'beat_the_dealer', version: 3, displayName: '블랙잭 가즈아'),
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
        NearbyRank(rank: 7, nickname: '말랑주먹', score: 3146, isMe: false),
        NearbyRank(rank: 8, nickname: 'tester', score: 2978, isMe: true),
        NearbyRank(rank: 9, nickname: '느린번개', score: 2811, isMe: false),
      ],
      leaders: [
        NearbyRank(rank: 1, nickname: '작은공룡', score: 5387, isMe: false),
        NearbyRank(rank: 2, nickname: '졸린감자', score: 4729, isMe: false),
        NearbyRank(rank: 3, nickname: '한번만더', score: 4312, isMe: false),
        NearbyRank(rank: 4, nickname: '공룡발자국', score: 3895, isMe: false),
        NearbyRank(rank: 5, nickname: '퇴근요정', score: 3514, isMe: false),
        NearbyRank(rank: 6, nickname: '새벽질주', score: 3328, isMe: false),
        NearbyRank(rank: 7, nickname: '말랑주먹', score: 3146, isMe: false),
        NearbyRank(rank: 8, nickname: 'tester', score: 2978, isMe: false),
      ],
    ),
    nickname: testMode ? 'tester' : null,
    compatibility: compatibility,
    economy: _economy,
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
  Future<RewardedAdSession> preparePracticeAd(
    DateTime expectedPlayDate,
  ) async => RewardedAdSession(
    id: '00000000-0000-4000-8000-000000000002',
    userId: 'preview-user',
    status: 'prepared',
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
  );

  @override
  Future<PlayAttempt> claimPracticeAttempt(String rewardSessionId) async =>
      _previewAttempt('practice_ad', ordinal: 3);

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
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async =>
      (await fetchToday()).result!;

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async => const [];

  @override
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult() async => null;

  @override
  Future<RewardGrant> acknowledgePreviousDailyResult(
    DateTime playDate,
    String gameId,
  ) async =>
      RewardGrant(coinsGranted: 0, experienceGranted: 0, economy: _economy);

  @override
  Future<CoinSpendResult> spendCoins({
    required int amount,
    required String gameId,
    required String referenceId,
  }) async {
    if (amount <= 0 || amount > _economy.coins) {
      throw StateError('insufficient coin balance');
    }
    _economy = PlayerEconomy.fromTotals(
      coins: _economy.coins - amount,
      experiencePoints: _economy.experiencePoints,
    );
    return CoinSpendResult(coinsSpent: amount, economy: _economy);
  }

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
  Future<void> deactivateTestMode() async {
    testMode = false;
  }

  @override
  Future<void> resetDeveloperDailyProgress() async {}

  @override
  Future<void> setDeveloperGame(String gameId) async {
    if (_games.any((game) => game.id == gameId)) {
      _selectedGameId = gameId;
    }
  }

  PlayAttempt _previewAttempt(String grantType, {int ordinal = 1}) =>
      PlayAttempt(
        id: 'preview-attempt',
        ordinal: ordinal,
        status: 'issued',
        grantType: grantType,
        gameId: _selectedGameId,
        gameVersion: switch (_selectedGameId) {
          'midnight_snake' => 2,
          'beat_the_dealer' => 3,
          _ => 1,
        },
        gameDurationSeconds: _previewGame(_selectedGameId).durationSeconds,
        playDate: dailyPlayDateAt(DateTime.now()),
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
      displayName: '중력 스위치',
      description: '탭으로 중력을 뒤집어 위아래로 이어지는 입체 기둥 미로를 돌파하세요.',
      durationSeconds: 300,
    ),
    'apple_game_v2' => const TodayGame(
      id: 'apple_game_v2',
      version: 1,
      displayName: '사과게임',
      description: '달빛 과수원에서 사과 숫자의 합을 10으로 만들어 최대한 많이 지우세요.',
      durationSeconds: 140,
    ),
    'number_rush' => const TodayGame(
      id: 'number_rush',
      version: 1,
      displayName: '탭50',
      description: '숫자를 1부터 50까지 순서대로 최대한 빠르게 터치하세요.',
      durationSeconds: 180,
    ),
    'mama_duck_trail' => const TodayGame(
      id: 'mama_duck_trail',
      version: 1,
      displayName: '엄마, 어디가',
      description: '비에 지워진 엄마 오리의 발자국을 기억해 같은 길을 따라가세요.',
      durationSeconds: 120,
    ),
    'midnight_snake' => const TodayGame(
      id: 'midnight_snake',
      version: 2,
      displayName: '야식털이 뱀',
      description: '야식과 한 번씩 나타나는 황금 소시지·쥐를 노리고 몸과 벽을 피하세요.',
      durationSeconds: 300,
    ),
    'beat_the_dealer' => const TodayGame(
      id: 'beat_the_dealer',
      version: 3,
      displayName: '블랙잭 가즈아',
      description: '딜러의 공개 카드를 보고 배팅한 뒤 21에 가까운 패를 만들어 코인을 불리세요.',
      durationSeconds: 180,
    ),
    _ => throw UnsupportedError('Unsupported preview game id: $gameId'),
  };
}
