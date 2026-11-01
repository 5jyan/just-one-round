import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/app_environment.dart';
import 'package:just_one_round/core/auth/anonymous_session_guard.dart';
import 'package:just_one_round/core/auth/device_registration_guard.dart';
import 'package:just_one_round/core/auth/shared_test_profile.dart';
import 'package:just_one_round/core/events/chuseok_gift.dart';
import 'package:just_one_round/core/notifications/push_opt_in_reward.dart';
import 'package:just_one_round/core/update/app_update_reward.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/data/pending_score_submission.dart';
import 'package:just_one_round/features/economy/domain/economy_transaction.dart';
import 'package:just_one_round/features/economy/domain/player_economy.dart';
import 'package:just_one_round/features/games/apple_game_v2/domain/apple_game_v2_rules.dart';
import 'package:just_one_round/features/games/bathhouse_sort/domain/bathhouse_sort_rules.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_frog_rules.dart';
import 'package:just_one_round/features/games/western_duel/domain/western_duel_opponent.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_opponent.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/net_boat/domain/net_boat_rules.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/monetization/domain/rewarded_ad_session.dart';
import 'package:just_one_round/features/referral/domain/referral.dart';
import 'package:just_one_round/features/shop/domain/shop_purchase.dart';
import 'package:just_one_round/features/social/domain/social_notification.dart';
import 'package:just_one_round/features/today/data/pending_play_request.dart';
import 'package:just_one_round/features/today/domain/daily_reset.dart';
import 'package:just_one_round/features/today/domain/daily_nonplayer.dart';
import 'package:just_one_round/features/today/domain/previous_daily_result.dart';
import 'package:just_one_round/features/today/domain/level_up_reward.dart';
import 'package:just_one_round/features/today/domain/tester_activation_result.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _untimedWindDartsVersions = <int>{3, WindDartsRules.rulesVersion};

abstract interface class DailyGameRepository {
  Future<TodayState> fetchToday();
  Future<PlayAttempt> claimDailyAttempt(DateTime expectedPlayDate);
  Future<PlayAttempt> claimChallengeTicketAttempt(DateTime expectedPlayDate);
  Future<RewardedAdSession> prepareRewardedAd(DateTime expectedPlayDate);
  Future<PlayAttempt> claimRewardedAttempt(String rewardSessionId);
  Future<RewardedAdSession> preparePracticeAd(DateTime expectedPlayDate);
  Future<int> claimPracticeTicketReward(String rewardSessionId);
  Future<RewardedAdSession> prepareCoinAd(DateTime expectedPlayDate);
  Future<CoinAdRewardResult> claimCoinAdReward(String rewardSessionId);
  Future<PlayAttempt> claimPracticeAttempt(String rewardSessionId);
  Future<void> confirmPlayStarted(PlayAttempt attempt);
  Future<void> expireAttempt(String attemptId);
  Future<DailyRankResult> submitScore(String attemptId, GameResult result);
  Future<DailyRankResult?> retryPendingScore();
  Future<void> setNickname(String nickname);
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate});
  Future<DailyRankResult?> fetchPreviousGameWinner({
    required String gameId,
    required DateTime beforeDate,
  });
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
  Future<ShopPurchaseResult> purchaseShopItem({
    required String itemId,
    required String requestId,
  });
  Future<List<DeveloperGame>> fetchDeveloperGames();
  Future<String> submitSupportInquiry({
    required String message,
    required String appVersion,
    required int buildNumber,
  });
  Future<void> deleteAccount();
  Future<TesterActivationResult> activateTestMode(String pin);
  Future<void> deactivateTestMode();
  Future<void> resetDeveloperDailyProgress();
  Future<void> setDeveloperGame(String gameId);
}

abstract interface class DailyNonplayersRepository {
  Future<DailyNonplayersPage> fetchDailyNonplayers({
    required DateTime playDate,
    required String gameId,
    String? afterUserId,
  });
}

abstract interface class LevelUpRewardRepository {
  Future<LevelUpReward?> fetchPendingLevelUpReward();

  Future<void> acknowledgeLevelUpReward({
    required int throughLevel,
    required String expectedUserId,
  });
}

class NoopLevelUpRewardRepository implements LevelUpRewardRepository {
  const NoopLevelUpRewardRepository();

  @override
  Future<LevelUpReward?> fetchPendingLevelUpReward() async => null;

  @override
  Future<void> acknowledgeLevelUpReward({
    required int throughLevel,
    required String expectedUserId,
  }) async {}
}

class NoopDailyNonplayersRepository implements DailyNonplayersRepository {
  const NoopDailyNonplayersRepository();

  @override
  Future<DailyNonplayersPage> fetchDailyNonplayers({
    required DateTime playDate,
    required String gameId,
    String? afterUserId,
  }) async => const DailyNonplayersPage(players: [], nextCursor: null);
}

abstract interface class WesternDuelStartRepository {
  Future<WesternDuelOpponent> confirmWesternDuelStarted(PlayAttempt attempt);
}

abstract interface class WindDartsStartRepository {
  Future<WindDartsOpponent> confirmWindDartsStarted(PlayAttempt attempt);
}

abstract interface class FirstChallengeNicknamePromptRepository {
  Future<bool> claimFirstChallengeNicknamePrompt();
}

abstract interface class SocialRepository {
  Future<void> setSocialNotificationsEnabled(bool enabled);
  Future<void> sendSocialAction({
    required String targetUserId,
    required String action,
  });
  Future<void> giftShopItem({
    required String targetUserId,
    required String itemId,
  });
  Future<List<SocialNotification>> fetchUnseenSocialNotifications();
  Future<void> acknowledgeSocialNotifications(List<String> ids);
  Future<void> registerPushDevice({
    required String platform,
    required String token,
  });
}

class NoopSocialRepository implements SocialRepository {
  const NoopSocialRepository();

  @override
  Future<void> acknowledgeSocialNotifications(List<String> ids) async {}
  @override
  Future<List<SocialNotification>> fetchUnseenSocialNotifications() async =>
      const [];
  @override
  Future<void> giftShopItem({
    required String targetUserId,
    required String itemId,
  }) async {
    if (itemId == 'nickname_color_ticket') {
      throw StateError('nickname color ticket is retired');
    }
  }

  @override
  Future<void> registerPushDevice({
    required String platform,
    required String token,
  }) async {}
  @override
  Future<void> sendSocialAction({
    required String targetUserId,
    required String action,
  }) async {}
  @override
  Future<void> setSocialNotificationsEnabled(bool enabled) async {}
}

abstract interface class DailyPracticeRepository {
  Future<String> getOrCreatePracticeRequestId(
    DateTime expectedPlayDate, {
    bool reuseExisting = true,
  });
  Future<PlayAttempt> claimDailyPractice(
    DateTime expectedPlayDate, {
    required String requestId,
    DateTime? gameDate,
  });
}

abstract interface class LocalPracticeAdVerificationRepository {
  Future<void> verifyLocalPracticeAd(String rewardSessionId);
  Future<void> verifyLocalRewardedAd(String rewardSessionId);
  Future<void> verifyLocalCoinAd(String rewardSessionId);
}

String createPlayRequestId({Random? random}) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

final dailyGameRepositoryProvider = Provider<DailyGameRepository>(
  (ref) => PreviewDailyGameRepository(),
);

final dailyNonplayersRepositoryProvider = Provider<DailyNonplayersRepository>((
  ref,
) {
  final repository = ref.watch(dailyGameRepositoryProvider);
  return repository is DailyNonplayersRepository
      ? repository as DailyNonplayersRepository
      : const NoopDailyNonplayersRepository();
});

final levelUpRewardRepositoryProvider = Provider<LevelUpRewardRepository>((
  ref,
) {
  final repository = ref.watch(dailyGameRepositoryProvider);
  return repository is LevelUpRewardRepository
      ? repository as LevelUpRewardRepository
      : const NoopLevelUpRewardRepository();
});

final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  final repository = ref.watch(dailyGameRepositoryProvider);
  return repository is ReferralRepository
      ? repository as ReferralRepository
      : const NoopReferralRepository();
});

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  final repository = ref.watch(dailyGameRepositoryProvider);
  return repository is SocialRepository
      ? repository as SocialRepository
      : const NoopSocialRepository();
});

final localTestAdVerificationProvider = Provider<bool>((ref) {
  const configuredSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  final host = Uri.tryParse(configuredSupabaseUrl)?.host ?? '';
  return !kReleaseMode &&
      (configuredSupabaseUrl.isEmpty ||
          host == '127.0.0.1' ||
          host == 'localhost' ||
          host == 'jor-api.shook.party' ||
          host == 'jor-api.shook.work');
});

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

final previousGameWinnerProvider = FutureProvider.autoDispose
    .family<DailyRankResult?, ({String gameId, DateTime beforeDate})>((
      ref,
      key,
    ) async {
      final keepAlive = ref.keepAlive();
      final cachedAt = DateTime.now();
      final cacheExpiresAt = cachedAt.add(
        durationUntilNextDailyReset(cachedAt),
      );
      Timer? expiryTimer;
      ref.onDispose(() {
        expiryTimer?.cancel();
        keepAlive.close();
      });

      try {
        final result = await ref
            .watch(dailyGameRepositoryProvider)
            .fetchPreviousGameWinner(
              gameId: key.gameId,
              beforeDate: key.beforeDate,
            );
        if (!ref.mounted) return result;
        final expiryDelay = cacheExpiresAt.difference(DateTime.now());
        expiryTimer = Timer(
          expiryDelay.isNegative ? Duration.zero : expiryDelay,
          () {
            if (!ref.mounted) return;
            keepAlive.close();
            ref.invalidateSelf();
          },
        );
        return result;
      } catch (_) {
        keepAlive.close();
        rethrow;
      }
    });

ClientCompatibility? unsupportedGameCompatibilityFor(
  TodayState state,
  ClientCompatibility compatibility,
) {
  // The tomorrow card is only a preview. It may legitimately be one game
  // version ahead of the live client while today's game remains playable.
  // Preview compatibility is checked again in TodayScreen before claiming
  // an attempt; it must not turn into a lobby-wide update gate here.
  final game = state.game;
  if (game != null && !GameRegistry.supports(game.id, game.version)) {
    return compatibility.requiringUpdate(reason: 'unsupported_game');
  }
  return null;
}

class AppUpdateRequiredException implements Exception {
  const AppUpdateRequiredException(this.reason);

  final String reason;

  @override
  String toString() => 'AppUpdateRequiredException: $reason';
}

class SupabaseDailyGameRepository
    implements
        DailyGameRepository,
        DailyNonplayersRepository,
        LevelUpRewardRepository,
        DailyPracticeRepository,
        LocalPracticeAdVerificationRepository,
        AppUpdateRewardRepository,
        ChuseokGiftRepository,
        PushOptInRewardRepository,
        FirstChallengeNicknamePromptRepository,
        WesternDuelStartRepository,
        WindDartsStartRepository,
        SocialRepository,
        ReferralRepository {
  SupabaseDailyGameRepository(
    this._client, {
    PendingScoreStore? pendingStore,
    PendingPlayRequestStore? pendingPlayRequestStore,
    Future<String> Function()? deviceHashLoader,
    SharedTestProfileConfig? sharedTestProfile,
    this.isFirebaseTestLab = false,
  }) : _deviceHashLoader = deviceHashLoader ?? readDeviceInstallHash,
       _pendingStore = pendingStore ?? SharedPreferencesPendingScoreStore(),
       _pendingPlayRequestStore =
           pendingPlayRequestStore ??
           SharedPreferencesPendingPlayRequestStore(),
       _sessionGuard = AnonymousSessionGuard(
         hasSession: () => _client.auth.currentSession != null,
         signInAnonymously: () async {
           final profile = sharedTestProfile;
           if (profile != null && profile.enabled) {
             await signInSharedTestProfile(_client, profile);
             return;
           }
           await _client.auth.signInAnonymously();
         },
       );

  final SupabaseClient _client;
  final Future<String> Function() _deviceHashLoader;
  final PendingScoreStore _pendingStore;
  final PendingPlayRequestStore _pendingPlayRequestStore;
  final bool isFirebaseTestLab;
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
    final compatibility = await _fetchClientCompatibility();
    if (compatibility.updateRequired) {
      return _blockedState(compatibility);
    }
    await _ensureSignedIn();

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

  @override
  Future<ReferralInvite> getOrCreateReferralInvite() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_or_create_referral_code');
    return ReferralInvite.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<ReferralStatus> fetchReferralStatus() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_referral_status');
    return ReferralStatus.fromJson(Map<String, dynamic>.from(response as Map));
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
  ) => unsupportedGameCompatibilityFor(state, compatibility);

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
  Future<PlayAttempt> claimChallengeTicketAttempt(
    DateTime expectedPlayDate,
  ) async {
    await _ensureSignedIn();
    return _attemptFromRpc(
      await _client.rpc(
        'claim_challenge_ticket_attempt',
        params: {'expected_play_date': playDateParameter(expectedPlayDate)},
      ),
    );
  }

  @override
  Future<PlayAttempt> claimDailyPractice(
    DateTime expectedPlayDate, {
    required String requestId,
    DateTime? gameDate,
  }) async {
    await _ensureSignedIn();
    final attempt = _attemptFromRpc(
      await _client.rpc(
        gameDate == null || isSamePlayDate(expectedPlayDate, gameDate)
            ? 'claim_daily_practice_v2'
            : 'claim_preview_practice',
        params: {
          'expected_play_date': playDateParameter(expectedPlayDate),
          'play_request_id': requestId,
          if (gameDate != null && !isSamePlayDate(expectedPlayDate, gameDate))
            'game_date': playDateParameter(gameDate),
        },
      ),
    );
    final serverRequestId = attempt.clientRequestId;
    if (serverRequestId != null && serverRequestId != requestId) {
      await _pendingPlayRequestStore.save(
        gameDate ?? expectedPlayDate,
        serverRequestId,
      );
    }
    return attempt;
  }

  @override
  Future<String> getOrCreatePracticeRequestId(
    DateTime expectedPlayDate, {
    bool reuseExisting = true,
  }) async {
    final saved = reuseExisting
        ? await _pendingPlayRequestStore.load(expectedPlayDate)
        : null;
    if (saved != null) return saved;
    final requestId = createPlayRequestId();
    await _pendingPlayRequestStore.save(expectedPlayDate, requestId);
    return requestId;
  }

  @override
  Future<void> confirmPlayStarted(PlayAttempt attempt) async {
    await _ensureSignedIn();
    await _client.rpc(
      'confirm_daily_play_started',
      params: {'play_reference_id': attempt.id},
    );
    final requestId = attempt.clientRequestId;
    final playDate = attempt.playDate;
    if (requestId != null && playDate != null) {
      await _pendingPlayRequestStore.remove(playDate, requestId);
    }
  }

  @override
  Future<WesternDuelOpponent> confirmWesternDuelStarted(
    PlayAttempt attempt,
  ) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'confirm_western_duel_started',
      params: {'play_reference_id': attempt.id},
    );
    final opponent = WesternDuelOpponent.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
    await _clearPendingPracticeRequest(attempt);
    return opponent;
  }

  @override
  Future<WindDartsOpponent> confirmWindDartsStarted(PlayAttempt attempt) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'confirm_wind_darts_started',
      params: {'play_reference_id': attempt.id},
    );
    final attemptVersion = attempt.gameVersion;
    if (attemptVersion == null) {
      throw const FormatException('Wind darts attempt version is missing');
    }
    final opponent = WindDartsOpponent.fromJson(
      Map<String, dynamic>.from(response as Map),
      attemptVersion: attemptVersion,
    );
    await _clearPendingPracticeRequest(attempt);
    return opponent;
  }

  Future<void> _clearPendingPracticeRequest(PlayAttempt attempt) async {
    final requestId = attempt.clientRequestId;
    final playDate = attempt.playDate;
    if (requestId == null || playDate == null) return;
    await _pendingPlayRequestStore.remove(playDate, requestId);
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
  Future<int> claimPracticeTicketReward(String rewardSessionId) async {
    await _ensureSignedIn();
    final response = Map<String, dynamic>.from(
      await _client.rpc(
            'claim_practice_ticket_reward',
            params: {'reward_session_id': rewardSessionId},
          )
          as Map,
    );
    return (response['tickets_granted'] as num).toInt();
  }

  @override
  Future<AppUpdateReward> claimAppUpdateReward() async {
    await _ensureSignedIn();
    final response = await _client.rpc('claim_app_update_reward');
    return AppUpdateReward.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<ChuseokGiftStatus> fetchChuseokGiftStatus() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_chuseok_gift_status');
    return ChuseokGiftStatus.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<ChuseokGiftClaim> claimChuseokGift() async {
    await _ensureSignedIn();
    final response = await _client.rpc('claim_chuseok_gift');
    return ChuseokGiftClaim.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<PushOptInRewardStatus> fetchPushOptInRewardStatus() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_push_opt_in_reward_status');
    return PushOptInRewardStatus.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<PushOptInRewardStatus> recordPushOptInRewardPrompt({
    bool accepted = false,
  }) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'record_push_opt_in_reward_prompt',
      params: {'accepted': accepted},
    );
    return PushOptInRewardStatus.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<PushOptInRewardClaim> claimPushOptInReward() async {
    await _ensureSignedIn();
    final response = await _client.rpc('claim_push_opt_in_reward');
    return PushOptInRewardClaim.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<RewardedAdSession> prepareCoinAd(DateTime expectedPlayDate) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'prepare_coin_ad',
      params: {'expected_play_date': playDateParameter(expectedPlayDate)},
    );
    return RewardedAdSession.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<CoinAdRewardResult> claimCoinAdReward(String rewardSessionId) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'claim_coin_ad_reward',
      params: {'reward_session_id': rewardSessionId},
    );
    return CoinAdRewardResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<void> verifyLocalPracticeAd(String rewardSessionId) async {
    await _ensureSignedIn();
    await _client.rpc(
      'verify_local_practice_ad_for_development',
      params: {'reward_session_id': rewardSessionId},
    );
  }

  @override
  Future<void> verifyLocalRewardedAd(String rewardSessionId) async {
    await _ensureSignedIn();
    await _client.rpc(
      'verify_local_ranked_ad_for_development',
      params: {'reward_session_id': rewardSessionId},
    );
  }

  @override
  Future<void> verifyLocalCoinAd(String rewardSessionId) async {
    await _ensureSignedIn();
    await _client.rpc(
      'verify_local_coin_ad_for_development',
      params: {'reward_session_id': rewardSessionId},
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

  @override
  Future<bool> claimFirstChallengeNicknamePrompt() async {
    await _ensureSignedIn();
    final response = await _client.rpc('claim_first_challenge_nickname_prompt');
    return response as bool? ?? false;
  }

  Future<DailyRankResult> _submitPendingScore(
    PendingScoreSubmission pending,
  ) async {
    if (pending.windDartsShotScores case final shots?) {
      final response = await _client.rpc(
        'submit_wind_darts_score',
        params: {
          'attempt_id': pending.attemptId,
          'shot_scores': shots,
          'duration_ms': pending.durationMs,
        },
      );
      return DailyRankResult.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    }
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
  Future<void> setSocialNotificationsEnabled(bool enabled) async {
    await _ensureSignedIn();
    await _client.rpc(
      'set_social_notifications_enabled',
      params: {'enabled': enabled},
    );
  }

  @override
  Future<void> sendSocialAction({
    required String targetUserId,
    required String action,
  }) async {
    if (isFirebaseTestLab) return;
    await _ensureSignedIn();
    await _client.rpc(
      'send_social_action',
      params: {
        'target_user_id': targetUserId,
        'social_action': action,
        'action_request_id': createPlayRequestId(),
      },
    );
  }

  @override
  Future<void> giftShopItem({
    required String targetUserId,
    required String itemId,
  }) async {
    if (itemId == 'nickname_color_ticket') {
      throw StateError('nickname color ticket is retired');
    }
    if (isFirebaseTestLab) return;
    await _ensureSignedIn();
    await _client.rpc(
      'gift_shop_item',
      params: {
        'target_user_id': targetUserId,
        'item_id': itemId,
        'gift_request_id': createPlayRequestId(),
      },
    );
  }

  @override
  Future<List<SocialNotification>> fetchUnseenSocialNotifications() async {
    await _ensureSignedIn();
    final response = await _client.rpc('get_unseen_social_notifications');
    return (response as List<dynamic>)
        .map(
          (item) => SocialNotification.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> acknowledgeSocialNotifications(List<String> ids) async {
    if (ids.isEmpty) return;
    await _ensureSignedIn();
    await _client.rpc(
      'acknowledge_social_notifications',
      params: {'notification_ids': ids},
    );
  }

  @override
  Future<void> registerPushDevice({
    required String platform,
    required String token,
  }) async {
    await _ensureSignedIn();
    await _client.rpc(
      'register_push_device',
      params: {'device_platform': platform, 'device_token': token},
    );
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
  Future<DailyRankResult?> fetchPreviousGameWinner({
    required String gameId,
    required DateTime beforeDate,
  }) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'get_previous_game_winner',
      params: {
        'target_game_id': gameId,
        'before_date': playDateParameter(beforeDate),
      },
    );
    if (response == null) return null;
    return DailyRankResult.fromJson(Map<String, dynamic>.from(response as Map));
  }

  @override
  Future<DailyNonplayersPage> fetchDailyNonplayers({
    required DateTime playDate,
    required String gameId,
    String? afterUserId,
  }) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'get_daily_nonplayers',
      params: {
        'target_date': playDateParameter(playDate),
        'target_game_id': gameId,
        'after_user_id': ?afterUserId,
      },
    );
    return DailyNonplayersPage.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'get_my_play_history',
      params: {'history_limit': 100},
    );
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
  Future<LevelUpReward?> fetchPendingLevelUpReward() async {
    await _ensureSignedIn();
    final raw = await _client.rpc('get_pending_level_up_reward');
    if (raw == null) return null;
    final value = raw is List ? (raw.isEmpty ? null : raw.first) : raw;
    if (value is! Map) return null;
    return LevelUpReward.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> acknowledgeLevelUpReward({
    required int throughLevel,
    required String expectedUserId,
  }) async {
    await _ensureSignedIn();
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId != expectedUserId) {
      throw StateError('account changed before acknowledging level-up reward');
    }
    await _client.rpc(
      'acknowledge_level_up_reward',
      params: {
        'through_level': throughLevel,
        'expected_user_id': expectedUserId,
      },
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
  Future<ShopPurchaseResult> purchaseShopItem({
    required String itemId,
    required String requestId,
  }) async {
    if (itemId == 'nickname_color_ticket') {
      throw StateError('nickname color ticket is retired');
    }
    await _ensureSignedIn();
    final response = await _client.rpc(
      'purchase_shop_item',
      params: {'item_id': itemId, 'purchase_request_id': requestId},
    );
    return ShopPurchaseResult.fromJson(
      Map<String, dynamic>.from(response as Map),
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
  Future<String> submitSupportInquiry({
    required String message,
    required String appVersion,
    required int buildNumber,
  }) async {
    await _ensureSignedIn();
    final response = await _client.rpc(
      'submit_support_inquiry',
      params: {
        'inquiry_message': message,
        'client_app_version': appVersion,
        'client_build_number': buildNumber,
      },
    );
    return response as String;
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
  if (state.challengePending) return const [];
  final currentTime = (now ?? DateTime.now()).toUtc();
  return state.attempts
      .where((attempt) => attempt.status == 'issued')
      .where((attempt) => !pendingAttemptIds.contains(attempt.id))
      .where((attempt) => _isStaleIssuedAttempt(attempt, currentTime))
      .toList(growable: false);
}

bool _isStaleIssuedAttempt(PlayAttempt attempt, DateTime now) {
  // Wind Darts v3/v4 has no player-facing timer. Never expire its issued
  // attempt from a state refresh; explicit interruption and the server's
  // daily deadline keep their existing authority.
  if (attempt.gameId == 'wind_darts' &&
      _untimedWindDartsVersions.contains(attempt.gameVersion)) {
    return false;
  }

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
    'invalid lily frog result',
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

class PreviewDailyGameRepository
    implements
        DailyGameRepository,
        DailyNonplayersRepository,
        LevelUpRewardRepository,
        DailyPracticeRepository,
        AppUpdateRewardRepository,
        ChuseokGiftRepository,
        PushOptInRewardRepository,
        FirstChallengeNicknamePromptRepository,
        WesternDuelStartRepository,
        WindDartsStartRepository,
        SocialRepository,
        ReferralRepository {
  PreviewDailyGameRepository({
    this.testMode = false,
    this.compatibility = const ClientCompatibility.supported(),
    this.initialEconomy = const PlayerEconomy.zero(),
    String initialGameId = 'dung_dodge_v2',
  }) : _selectedGameId = initialGameId,
       _levelRewardedThrough = initialEconomy.level,
       _levelCelebrationSeenThrough = initialEconomy.level;

  bool testMode;
  final ClientCompatibility compatibility;
  final PlayerEconomy initialEconomy;
  late PlayerEconomy _economy = initialEconomy;
  var _storePracticeTickets = 0;
  var _storeChallengeTickets = 0;
  var _storeNicknameChangeTickets = 0;
  final int _levelRewardedThrough;
  int _levelCelebrationSeenThrough;
  String _selectedGameId;

  static const _games = [
    DeveloperGame(id: 'dung_dodge_v2', version: 1, displayName: '똥피하기'),
    DeveloperGame(id: 'gravity_switch', version: 1, displayName: '중력 스위치'),
    DeveloperGame(
      id: 'apple_game_v2',
      version: AppleGameV2Rules.rulesVersion,
      displayName: '사과게임',
    ),
    DeveloperGame(id: 'number_rush', version: 1, displayName: '탭50'),
    DeveloperGame(id: 'mole_reaction', version: 1, displayName: '두더지 반응속도'),
    DeveloperGame(id: 'western_duel', version: 1, displayName: '딱 한 발만'),
    DeveloperGame(
      id: 'wind_darts',
      version: WindDartsRules.rulesVersion,
      displayName: '펍 다트',
    ),
    DeveloperGame(id: 'mama_duck_trail', version: 1, displayName: '엄마, 어디가'),
    DeveloperGame(
      id: 'midnight_snake',
      version: MidnightSnakeRules.rulesVersion,
      displayName: '야식털이 뱀',
    ),
    DeveloperGame(id: 'beat_the_dealer', version: 3, displayName: '블랙잭'),
    DeveloperGame(id: 'ten_pitch_slugger', version: 7, displayName: '홈런왕'),
    DeveloperGame(id: 'ramen_timer', version: 3, displayName: '30초 컵라면'),
    DeveloperGame(
      id: 'bathhouse_sort',
      version: BathhouseSortRules.rulesVersion,
      displayName: '남탕! 여탕!',
    ),
    DeveloperGame(
      id: 'lily_frog',
      version: LilyFrogRules.rulesVersion,
      displayName: '빙글개굴',
    ),
    DeveloperGame(
      id: 'net_boat',
      version: NetBoatRules.rulesVersion,
      displayName: '만선호',
    ),
    DeveloperGame(
      id: 'temple_run',
      version: TempleRunRules.rulesVersion,
      displayName: '집에 좀 가자',
    ),
  ];

  @override
  Future<TodayState> fetchToday() async => TodayState(
    playDate: dailyPlayDateAt(DateTime.now()),
    game: _previewGame(_selectedGameId),
    attempts: const [],
    adAttemptAvailable: false,
    practiceAvailable: !testMode,
    practiceTicketCapacity: testMode ? 0 : 1,
    practiceTicketsRemaining: testMode ? 0 : 1,
    playCount: 0,
    challengeAvailable: true,
    extraChallengeAvailable: false,
    nextPlayRequiresAd: false,
    testMode: testMode,
    result: _previewRankResult(_selectedGameId),
    nickname: testMode ? 'tester' : null,
    compatibility: compatibility,
    economy: _economy,
    levelRewardedThrough: _levelRewardedThrough,
    levelCelebrationSeenThrough: _levelCelebrationSeenThrough,
    storePracticeTickets: _storePracticeTickets,
    storeChallengeTickets: _storeChallengeTickets,
    storeNicknameChangeTickets: _storeNicknameChangeTickets,
    coinAdAvailable: !testMode,
    tomorrow: TomorrowGame(
      playDate: dailyPlayDateAt(DateTime.now()).add(const Duration(days: 1)),
      game: _previewGame(
        _games[(_games.indexWhere((game) => game.id == _selectedGameId) + 1) %
                _games.length]
            .id,
      ),
    ),
  );

  @override
  Future<ReferralInvite> getOrCreateReferralInvite() async =>
      const ReferralInvite(code: '0000000000000000');

  @override
  Future<ReferralStatus> fetchReferralStatus() async =>
      const ReferralStatus.empty();

  DailyRankResult _previewRankResult(String gameId) {
    if (gameId == 'ramen_timer') {
      return _withPreviewInteractions(
        DailyRankResult(
          score: 3586000,
          rank: 4,
          participants: 4,
          topPercent: 75,
          nickname: 'tester',
          bestScore: 3599920,
          nearby: const [
            NearbyRank(rank: 3, nickname: '한번만더', score: 3599410, isMe: false),
            NearbyRank(rank: 4, nickname: 'tester', score: 3586000, isMe: true),
          ],
          leaders: [
            NearbyRank(rank: 1, nickname: '작은공룡', score: 3599920, isMe: false),
            NearbyRank(rank: 2, nickname: '졸린감자', score: 3599760, isMe: false),
            NearbyRank(rank: 3, nickname: '한번만더', score: 3599410, isMe: false),
            NearbyRank(rank: 4, nickname: 'tester', score: 3586000, isMe: true),
          ],
        ),
      );
    }

    return _withPreviewInteractions(
      DailyRankResult(
        score: 2978,
        rank: 4,
        participants: 4,
        topPercent: 75,
        nickname: 'tester',
        bestScore: 5387,
        nearby: const [
          NearbyRank(rank: 3, nickname: '한번만더', score: 4312, isMe: false),
          NearbyRank(rank: 4, nickname: 'tester', score: 2978, isMe: true),
        ],
        leaders: [
          NearbyRank(rank: 1, nickname: '작은공룡', score: 5387, isMe: false),
          NearbyRank(rank: 2, nickname: '졸린감자', score: 4729, isMe: false),
          NearbyRank(rank: 3, nickname: '한번만더', score: 4312, isMe: false),
          NearbyRank(rank: 4, nickname: 'tester', score: 2978, isMe: true),
        ],
      ),
    );
  }

  DailyRankResult _withPreviewInteractions(DailyRankResult result) {
    final leaders = result.leaders
        .map(
          (entry) => entry.isMe || entry.isNpc || entry.userId != null
              ? entry
              : NearbyRank(
                  rank: entry.rank,
                  nickname: entry.nickname,
                  score: entry.score,
                  isMe: entry.isMe,
                  level: entry.level,
                  nicknameColor: entry.nicknameColor,
                  userId: 'preview-user-${entry.rank}',
                  isNpc: entry.isNpc,
                ),
        )
        .toList(growable: false);
    return DailyRankResult(
      score: result.score,
      rank: result.rank,
      participants: result.participants,
      topPercent: result.topPercent,
      nickname: result.nickname,
      bestScore: result.bestScore,
      nearby: result.nearby,
      leaders: leaders,
    );
  }

  @override
  Future<PlayAttempt> claimDailyAttempt(DateTime expectedPlayDate) async =>
      _previewAttempt('daily');

  @override
  Future<PlayAttempt> claimChallengeTicketAttempt(
    DateTime expectedPlayDate,
  ) async => _previewAttempt('store_ticket');

  @override
  Future<PlayAttempt> claimDailyPractice(
    DateTime expectedPlayDate, {
    required String requestId,
    DateTime? gameDate,
  }) async => _previewAttempt(
    'practice_daily',
    gameId: gameDate == null || isSamePlayDate(expectedPlayDate, gameDate)
        ? null
        : _games[(_games.indexWhere((game) => game.id == _selectedGameId) + 1) %
                  _games.length]
              .id,
    playDate: gameDate,
  );

  @override
  Future<String> getOrCreatePracticeRequestId(
    DateTime expectedPlayDate, {
    bool reuseExisting = true,
  }) async {
    return createPlayRequestId();
  }

  @override
  Future<void> confirmPlayStarted(PlayAttempt attempt) async {}

  @override
  Future<WesternDuelOpponent> confirmWesternDuelStarted(
    PlayAttempt attempt,
  ) async => const WesternDuelOpponent(
    nickname: '맥크리',
    reactionMilliseconds: 440,
    isBot: true,
  );

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
  Future<int> claimPracticeTicketReward(String rewardSessionId) async => 2;

  @override
  Future<AppUpdateReward> claimAppUpdateReward() async =>
      const AppUpdateReward(granted: false);

  @override
  Future<ChuseokGiftStatus> fetchChuseokGiftStatus() async =>
      const ChuseokGiftStatus(eligible: false, claimed: false);

  @override
  Future<ChuseokGiftClaim> claimChuseokGift() async =>
      const ChuseokGiftClaim(eligible: false, claimed: false, granted: false);

  @override
  Future<PushOptInRewardStatus> fetchPushOptInRewardStatus() async =>
      const PushOptInRewardStatus(
        shouldShow: false,
        accepted: false,
        claimed: false,
      );

  @override
  Future<PushOptInRewardStatus> recordPushOptInRewardPrompt({
    bool accepted = false,
  }) async => const PushOptInRewardStatus(
    shouldShow: false,
    accepted: false,
    claimed: false,
  );

  @override
  Future<PushOptInRewardClaim> claimPushOptInReward() async =>
      const PushOptInRewardClaim(claimed: false, granted: false);

  @override
  Future<RewardedAdSession> prepareCoinAd(DateTime expectedPlayDate) async =>
      RewardedAdSession(
        id: '00000000-0000-4000-8000-000000000003',
        userId: 'preview-user',
        status: 'prepared',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

  @override
  Future<CoinAdRewardResult> claimCoinAdReward(String rewardSessionId) async {
    _economy = PlayerEconomy.fromTotals(
      coins: _economy.coins + ShopCatalog.coinAdReward,
      experiencePoints: _economy.experiencePoints,
    );
    return CoinAdRewardResult(
      coinsGranted: ShopCatalog.coinAdReward,
      economy: _economy,
    );
  }

  @override
  Future<WindDartsOpponent> confirmWindDartsStarted(
    PlayAttempt attempt,
  ) async => const WindDartsOpponent(
    nickname: '서부의 단골',
    shotScores: [7, 19, 10, 20, 6, 9, 22],
    isBot: true,
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
  Future<bool> claimFirstChallengeNicknamePrompt() async => true;

  @override
  Future<void> setNickname(String nickname) async {}

  @override
  Future<void> setSocialNotificationsEnabled(bool enabled) async {}

  @override
  Future<void> sendSocialAction({
    required String targetUserId,
    required String action,
  }) async {}

  @override
  Future<void> giftShopItem({
    required String targetUserId,
    required String itemId,
  }) async {
    if (itemId == 'nickname_color_ticket') {
      throw StateError('nickname color ticket is retired');
    }
  }

  @override
  Future<List<SocialNotification>> fetchUnseenSocialNotifications() async =>
      const [];

  @override
  Future<void> acknowledgeSocialNotifications(List<String> ids) async {}

  @override
  Future<void> registerPushDevice({
    required String platform,
    required String token,
  }) async {}

  @override
  Future<DailyRankResult> fetchDailyRank({DateTime? playDate}) async {
    final result = (await fetchToday()).result!;
    final currentPlayDate = dailyPlayDateAt(DateTime.now());
    if (playDate != null && playDate.isBefore(currentPlayDate)) {
      return _previewPreviousRankResult(_selectedGameId);
    }
    return result;
  }

  @override
  Future<DailyRankResult?> fetchPreviousGameWinner({
    required String gameId,
    required DateTime beforeDate,
  }) async => _previewPreviousRankResult(gameId);

  @override
  Future<DailyNonplayersPage> fetchDailyNonplayers({
    required DateTime playDate,
    required String gameId,
    String? afterUserId,
  }) async {
    if (afterUserId != null) {
      return const DailyNonplayersPage(players: [], nextCursor: null);
    }
    return const DailyNonplayersPage(
      players: [
        DailyNonplayer(
          userId: '90000000-0000-4000-8000-000000000001',
          nickname: '연습중인감자',
          nicknameColor: 'mint',
          level: 3,
        ),
        DailyNonplayer(
          userId: '90000000-0000-4000-8000-000000000002',
          nickname: '오늘은관전',
          nicknameColor: 'default',
          level: 1,
        ),
      ],
      nextCursor: null,
    );
  }

  DailyRankResult _previewPreviousRankResult(String gameId) =>
      _withPreviewInteractions(
        DailyRankResult(
          score: null,
          rank: null,
          participants: 3,
          topPercent: null,
          nickname: null,
          nearby: const [],
          leaders: [
            NearbyRank(
              rank: 1,
              nickname: '어제의챔피언',
              score: gameId == 'ramen_timer' ? 3598000 : 4890,
              isMe: false,
              level: 6,
              nicknameColor: 'mint',
            ),
            const NearbyRank(
              rank: 2,
              nickname: '지난기록',
              score: 4700,
              isMe: false,
              level: 3,
            ),
          ],
        ),
      );

  @override
  Future<List<PlayHistoryEntry>> fetchHistory() async => const [];

  @override
  Future<PreviousDailyResult?> fetchUnseenPreviousDailyResult() async => null;

  @override
  Future<LevelUpReward?> fetchPendingLevelUpReward() async {
    if (_levelRewardedThrough <= _levelCelebrationSeenThrough) return null;
    final fromLevel = max(1, _levelCelebrationSeenThrough);
    return LevelUpReward(
      userId: 'preview-user',
      fromLevel: fromLevel,
      toLevel: _levelRewardedThrough,
      challengeTickets: max(0, _levelRewardedThrough - fromLevel),
    );
  }

  @override
  Future<void> acknowledgeLevelUpReward({
    required int throughLevel,
    required String expectedUserId,
  }) async {
    if (expectedUserId != 'preview-user') {
      throw StateError('account changed before acknowledging level-up reward');
    }
    if (throughLevel < 1 || throughLevel > _levelRewardedThrough) {
      throw StateError('invalid level acknowledgement');
    }
    _levelCelebrationSeenThrough = max(
      _levelCelebrationSeenThrough,
      throughLevel,
    );
  }

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
  Future<ShopPurchaseResult> purchaseShopItem({
    required String itemId,
    required String requestId,
  }) async {
    final price = switch (itemId) {
      'practice_ticket' => ShopCatalog.practiceTicketPrice,
      'challenge_ticket' => ShopCatalog.challengeTicketPrice,
      'nickname_change_ticket' => ShopCatalog.nicknameChangeTicketPrice,
      _ => throw StateError('unknown shop item'),
    };
    if (_economy.coins < price) {
      throw StateError('insufficient coin balance');
    }
    _economy = PlayerEconomy.fromTotals(
      coins: _economy.coins - price,
      experiencePoints: _economy.experiencePoints,
    );
    if (itemId == 'practice_ticket') {
      _storePracticeTickets++;
    } else if (itemId == 'challenge_ticket') {
      _storeChallengeTickets++;
    } else {
      _storeNicknameChangeTickets++;
    }
    return ShopPurchaseResult(
      itemId: itemId,
      quantity: 1,
      coinsSpent: price,
      practiceTickets: _storePracticeTickets,
      challengeTickets: _storeChallengeTickets,
      nicknameChangeTickets: _storeNicknameChangeTickets,
      economy: _economy,
    );
  }

  @override
  Future<List<DeveloperGame>> fetchDeveloperGames() async => _games;

  @override
  Future<String> submitSupportInquiry({
    required String message,
    required String appVersion,
    required int buildNumber,
  }) async => '00000000-0000-4000-8000-000000000004';

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

  PlayAttempt _previewAttempt(
    String grantType, {
    int ordinal = 1,
    String? gameId,
    DateTime? playDate,
  }) {
    final selectedGame = _previewGame(gameId ?? _selectedGameId);
    return PlayAttempt(
      id: 'preview-attempt',
      ordinal: ordinal,
      status: 'issued',
      grantType: grantType,
      gameId: selectedGame.id,
      gameVersion: selectedGame.version,
      gameDurationSeconds: selectedGame.durationSeconds,
      playDate: playDate ?? dailyPlayDateAt(DateTime.now()),
      practiceOrdinal: grantType.startsWith('practice') ? ordinal : null,
    );
  }

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
      version: AppleGameV2Rules.rulesVersion,
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
    'mole_reaction' => const TodayGame(
      id: 'mole_reaction',
      version: 1,
      displayName: '두더지 반응속도',
      description: '준비 두더지 한 번 뒤, 진짜 황금 두더지 한 마리의 반응시간을 줄이세요.',
      durationSeconds: 180,
    ),
    'western_duel' => const TodayGame(
      id: 'western_duel',
      version: 1,
      displayName: '딱 한 발만',
      description: 'DRAW!가 뜨면 한 발. 실제 랭킹 총잡이와 반응속도를 겨루세요.',
      durationSeconds: 30,
    ),
    'wind_darts' => TodayGame(
      id: 'wind_darts',
      version: WindDartsRules.rulesVersion,
      displayName: '펍 다트',
      description: '12방향 바람과 흔들리는 조준점을 읽으며 여섯 발의 점수를 겨루세요. 시간 제한 없음.',
      durationSeconds: WindDartsRules.gameDuration.inSeconds,
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
      version: 4,
      displayName: '야식털이 뱀',
      description: '야식과 30초 간격으로 반복 등장하는 황금 소시지·쥐를 노리고 몸과 벽을 피하세요.',
      durationSeconds: 300,
    ),
    'beat_the_dealer' => const TodayGame(
      id: 'beat_the_dealer',
      version: 3,
      displayName: '블랙잭',
      description: '딜러의 공개 카드를 보고 배팅한 뒤 21에 가까운 패를 만들어 코인을 불리세요.',
      durationSeconds: 180,
    ),
    'ten_pitch_slugger' => const TodayGame(
      id: 'ten_pitch_slugger',
      version: 7,
      displayName: '홈런왕',
      description: '점점 빨라지는 10구를 받아쳐 최대 비거리를 기록하세요. 뒤로 갈수록 같은 정타도 더 멀리 갑니다.',
      durationSeconds: 300,
    ),
    'ramen_timer' => const TodayGame(
      id: 'ramen_timer',
      version: 3,
      displayName: '30초 컵라면',
      description: '첫 두 입력의 목표 오차를 바로 확인하며 10초, 20초, 30초 조리 타이밍을 맞추세요.',
      durationSeconds: 45,
    ),
    'bathhouse_sort' => const TodayGame(
      id: 'bathhouse_sort',
      version: BathhouseSortRules.rulesVersion,
      displayName: '남탕! 여탕!',
      description: '동물 종을 기억하고 줄을 미리 읽어 남탕과 여탕을 빠르게 연속 탭하세요.',
      durationSeconds: 60,
    ),
    'lily_frog' => const TodayGame(
      id: 'lily_frog',
      version: LilyFrogRules.rulesVersion,
      displayName: '빙글개굴',
      description: '연잎 가장자리를 도는 개구리를 접선 방향으로 점프시켜 연못을 건너세요.',
      durationSeconds: 150,
    ),
    'net_boat' => const TodayGame(
      id: 'net_boat',
      version: NetBoatRules.rulesVersion,
      displayName: '만선호',
      description: '빠른 통통배로 위험한 바다생물을 피해 더 크고 비싼 생물을 그물로 잡으세요.',
      durationSeconds: NetBoatRules.gameDurationSeconds,
    ),
    'temple_run' => const TodayGame(
      id: 'temple_run',
      version: TempleRunRules.rulesVersion,
      displayName: '집에 좀 가자',
      description: '덮개 자재와 작업발판을 피해 골목을 달리고 차단대를 뛰어넘어 집에 도착하세요.',
      durationSeconds: 300,
    ),
    _ => throw UnsupportedError('Unsupported preview game id: $gameId'),
  };
}
