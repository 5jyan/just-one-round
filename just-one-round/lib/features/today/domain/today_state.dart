import 'package:just_one_round/features/economy/domain/player_economy.dart';

class TodayGame {
  const TodayGame({
    required this.id,
    required this.version,
    required this.displayName,
    required this.description,
    required this.durationSeconds,
  });

  factory TodayGame.fromJson(Map<String, dynamic> json) => TodayGame(
    id: json['id'] as String,
    version: json['version'] as int,
    displayName: json['display_name'] as String,
    description: json['description'] as String,
    durationSeconds: json['duration_seconds'] as int,
  );

  final String id;
  final int version;
  final String displayName;
  final String description;
  final int durationSeconds;
}

class TomorrowGame {
  const TomorrowGame({required this.playDate, required this.game});

  factory TomorrowGame.fromJson(Map<String, dynamic> json) => TomorrowGame(
    playDate: DateTime.parse(json['play_date'] as String),
    game: TodayGame.fromJson(json['game'] as Map<String, dynamic>),
  );

  final DateTime playDate;
  final TodayGame game;
}

class DeveloperGame {
  const DeveloperGame({
    required this.id,
    required this.version,
    required this.displayName,
  });

  factory DeveloperGame.fromJson(Map<String, dynamic> json) => DeveloperGame(
    id: json['id'] as String,
    version: (json['version'] as num).toInt(),
    displayName: json['display_name'] as String,
  );

  final String id;
  final int version;
  final String displayName;
}

class PlayAttempt {
  const PlayAttempt({
    required this.id,
    required this.ordinal,
    required this.status,
    required this.grantType,
    this.gameId,
    this.gameVersion,
    this.gameDurationSeconds,
    this.playDate,
    this.issuedAt,
    this.practiceOrdinal,
    this.clientRequestId,
    this.resolveForSubmission,
  });

  factory PlayAttempt.fromJson(Map<String, dynamic> json) => PlayAttempt(
    id: json['id'] as String,
    ordinal: json['ordinal'] as int,
    status: json['status'] as String,
    grantType: json['grant_type'] as String,
    gameId: json['game_id'] as String?,
    gameVersion: (json['game_version'] as num?)?.toInt(),
    gameDurationSeconds: (json['game_duration_seconds'] as num?)?.toInt(),
    playDate: json['play_date'] == null
        ? null
        : DateTime.parse(json['play_date'] as String),
    issuedAt: json['issued_at'] == null
        ? null
        : DateTime.tryParse(json['issued_at'] as String),
    practiceOrdinal: (json['practice_ordinal'] as num?)?.toInt(),
    clientRequestId: json['client_request_id'] as String?,
  );

  final String id;
  final int ordinal;
  final String status;
  final String grantType;
  final String? gameId;
  final int? gameVersion;
  final int? gameDurationSeconds;
  final DateTime? playDate;
  final DateTime? issuedAt;
  final int? practiceOrdinal;
  final String? clientRequestId;

  // Rewarded attempts can enter the game before the server has received the
  // provider's SSV callback. The resolver is intentionally transient and is
  // never decoded from the API response; it lets score submission wait for
  // the verified server attempt without treating a client-side placeholder
  // as a real attempt.
  final Future<PlayAttempt?> Function()? resolveForSubmission;

  bool get isPractice =>
      grantType == 'practice_ad' || grantType == 'practice_daily';
}

class ClientCompatibility {
  const ClientCompatibility({
    required this.currentBuild,
    required this.minimumSupportedBuild,
    required this.updateRequired,
    this.storeUrl,
    this.reason,
  });

  const ClientCompatibility.supported()
    : currentBuild = 1,
      minimumSupportedBuild = 1,
      updateRequired = false,
      storeUrl = null,
      reason = null;

  factory ClientCompatibility.fromJson(Map<String, dynamic> json) =>
      ClientCompatibility(
        currentBuild: (json['current_build'] as num?)?.toInt() ?? 1,
        minimumSupportedBuild:
            (json['minimum_supported_build'] as num?)?.toInt() ?? 1,
        updateRequired: json['update_required'] as bool? ?? false,
        storeUrl: json['store_url'] as String?,
        reason: json['reason'] as String?,
      );

  final int currentBuild;
  final int minimumSupportedBuild;
  final bool updateRequired;
  final String? storeUrl;
  final String? reason;

  ClientCompatibility requiringUpdate({required String reason}) =>
      ClientCompatibility(
        currentBuild: currentBuild,
        minimumSupportedBuild: minimumSupportedBuild,
        updateRequired: true,
        storeUrl: storeUrl,
        reason: reason,
      );
}

class NearbyRank {
  const NearbyRank({
    required this.rank,
    required this.nickname,
    required this.score,
    required this.isMe,
    this.level = 1,
    this.nicknameColor = 'default',
    this.userId,
    this.isNpc = false,
  });

  factory NearbyRank.fromJson(Map<String, dynamic> json) => NearbyRank(
    rank: (json['rank'] as num).toInt(),
    nickname: json['nickname'] as String,
    score: (json['score'] as num).toInt(),
    isMe: json['is_me'] as bool,
    level: (json['level'] as num?)?.toInt() ?? 1,
    nicknameColor: json['nickname_color'] as String? ?? 'default',
    userId: json['user_id'] as String?,
    isNpc: json['is_npc'] as bool? ?? false,
  );

  final int rank;
  final String nickname;
  final int score;
  final bool isMe;
  final int level;
  final String nicknameColor;
  final String? userId;
  final bool isNpc;
}

class DailyRankResult {
  const DailyRankResult({
    required this.score,
    required this.rank,
    required this.participants,
    required this.topPercent,
    required this.nickname,
    required this.nearby,
    this.bestScore,
    this.leaders = const [],
  });

  factory DailyRankResult.fromJson(Map<String, dynamic> json) =>
      DailyRankResult(
        score: (json['score'] as num?)?.toInt(),
        rank: (json['rank'] as num?)?.toInt(),
        participants: (json['participants'] as num?)?.toInt() ?? 0,
        topPercent: (json['top_percent'] as num?)?.toInt(),
        nickname: json['nickname'] as String?,
        bestScore: (json['best_score'] as num?)?.toInt(),
        nearby: (json['nearby'] as List<dynamic>? ?? const [])
            .map((item) => NearbyRank.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        leaders: (json['leaders'] as List<dynamic>? ?? const [])
            .map((item) => NearbyRank.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final int? score;
  final int? rank;
  final int participants;
  final int? topPercent;
  final String? nickname;
  final int? bestScore;
  final List<NearbyRank> nearby;
  final List<NearbyRank> leaders;
}

class TodayState {
  const TodayState({
    required this.playDate,
    required this.game,
    required this.attempts,
    required this.adAttemptAvailable,
    required this.testMode,
    required this.result,
    required this.nickname,
    this.dailyClaimed = false,
    this.practiceAvailable = false,
    this.playCount,
    this.practicePlayCount = 0,
    this.challengePending = false,
    this.practicePending = false,
    this.challengeAvailable,
    this.adChallengeAvailable,
    this.extraChallengeAvailable,
    this.challengeTicketAvailable,
    this.nextPlayRequiresAd,
    this.challengeRequiresAd,
    this.practiceRequiresAd,
    this.practiceTicketCapacity = 1,
    this.practiceTicketsRemaining = 0,
    this.practiceRewardAvailable = false,
    this.practiceRewardEarned = false,
    this.storePracticeTickets = 0,
    this.storeChallengeTickets = 0,
    this.storeNicknameColorTickets = 0,
    this.storeNicknameChangeTickets = 0,
    this.nicknameColor = 'default',
    this.socialNotificationsEnabled = true,
    this.rankedAdAttemptUsed = false,
    this.coinAdAvailable = false,
    this.deviceDailyLimitReached = false,
    this.requiresKakaoForDailyPlay = false,
    this.compatibility = const ClientCompatibility.supported(),
    this.economy = const PlayerEconomy.zero(),
    this.levelRewardedThrough = 0,
    this.levelCelebrationSeenThrough = 0,
    this.tomorrow,
  });

  factory TodayState.fromJson(Map<String, dynamic> json) {
    final attempts = (json['attempts'] as List<dynamic>? ?? const [])
        .map((item) => PlayAttempt.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    final gameJson = json['game'] as Map<String, dynamic>?;
    final resultJson = json['result'] as Map<String, dynamic>?;
    final explicitAdChallengeAvailable =
        json['ad_challenge_available'] as bool?;
    final extraChallengeAvailable = json['extra_challenge_available'] as bool?;
    final challengeRequiresAd = json['challenge_requires_ad'] as bool?;
    final rankedAdAttemptUsed =
        json['ranked_ad_attempt_used'] as bool? ?? false;
    return TodayState(
      playDate: DateTime.parse(json['play_date'] as String),
      game: gameJson == null ? null : TodayGame.fromJson(gameJson),
      attempts: attempts,
      adAttemptAvailable: json['ad_attempt_available'] as bool? ?? false,
      testMode: json['test_mode'] as bool? ?? false,
      result: resultJson == null ? null : DailyRankResult.fromJson(resultJson),
      nickname:
          json['nickname'] as String? ??
          (json['profile'] as Map<String, dynamic>?)?['nickname'] as String?,
      dailyClaimed: json['daily_claimed'] as bool? ?? attempts.isNotEmpty,
      practiceAvailable: json['practice_available'] as bool? ?? false,
      playCount: (json['play_count'] as num?)?.toInt(),
      practicePlayCount: (json['practice_play_count'] as num?)?.toInt() ?? 0,
      challengePending: json['challenge_pending'] as bool? ?? false,
      practicePending: json['practice_pending'] as bool? ?? false,
      challengeAvailable: json['challenge_available'] as bool?,
      // Older responses exposed only the combined extra-challenge flag. Once
      // the ranked ad has been consumed, that flag may still be true for a
      // purchased challenge ticket, so it cannot be used as an ad fallback.
      // An explicit challenge_requires_ad value is more specific and wins
      // over the legacy combined flag.
      adChallengeAvailable:
          explicitAdChallengeAvailable ??
          challengeRequiresAd ??
          (rankedAdAttemptUsed ? false : extraChallengeAvailable),
      extraChallengeAvailable: extraChallengeAvailable,
      challengeTicketAvailable: json['challenge_ticket_available'] as bool?,
      nextPlayRequiresAd: json['next_play_requires_ad'] as bool?,
      challengeRequiresAd: challengeRequiresAd,
      practiceRequiresAd: json['practice_requires_ad'] as bool?,
      practiceTicketCapacity:
          (json['practice_ticket_capacity'] as num?)?.toInt() ?? 1,
      practiceTicketsRemaining:
          (json['practice_tickets_remaining'] as num?)?.toInt() ?? 0,
      practiceRewardAvailable:
          json['practice_reward_available'] as bool? ?? false,
      practiceRewardEarned: json['practice_reward_earned'] as bool? ?? false,
      storePracticeTickets:
          (json['store_practice_tickets'] as num?)?.toInt() ?? 0,
      storeChallengeTickets:
          (json['store_challenge_tickets'] as num?)?.toInt() ?? 0,
      storeNicknameColorTickets:
          (json['store_nickname_color_tickets'] as num?)?.toInt() ?? 0,
      storeNicknameChangeTickets:
          (json['store_nickname_change_tickets'] as num?)?.toInt() ?? 0,
      nicknameColor: json['nickname_color'] as String? ?? 'default',
      socialNotificationsEnabled:
          json['social_notifications_enabled'] as bool? ?? true,
      rankedAdAttemptUsed: rankedAdAttemptUsed,
      coinAdAvailable: json['coin_ad_available'] as bool? ?? false,
      deviceDailyLimitReached:
          json['device_daily_limit_reached'] as bool? ?? false,
      requiresKakaoForDailyPlay:
          json['requires_kakao_for_daily_play'] as bool? ?? false,
      economy: _economyFromJson(json),
      levelRewardedThrough:
          (json['level_rewarded_through'] as num?)?.toInt() ?? 0,
      levelCelebrationSeenThrough:
          (json['level_celebration_seen_through'] as num?)?.toInt() ?? 0,
      tomorrow: json['tomorrow'] is Map
          ? TomorrowGame.fromJson(
              Map<String, dynamic>.from(json['tomorrow'] as Map),
            )
          : null,
    );
  }

  static PlayerEconomy _economyFromJson(Map<String, dynamic> json) {
    final economy = json['economy'];
    if (economy is Map) {
      return PlayerEconomy.fromJson(Map<String, dynamic>.from(economy));
    }
    final profile = json['profile'];
    if (profile is Map) {
      return PlayerEconomy.fromJson(Map<String, dynamic>.from(profile));
    }
    return const PlayerEconomy.zero();
  }

  final DateTime playDate;
  final TodayGame? game;
  final List<PlayAttempt> attempts;
  final bool adAttemptAvailable;
  final bool testMode;
  final DailyRankResult? result;
  final String? nickname;
  final bool dailyClaimed;
  final bool practiceAvailable;
  final int? playCount;
  final int practicePlayCount;
  final bool challengePending;
  final bool practicePending;
  final bool? challengeAvailable;
  final bool? adChallengeAvailable;
  final bool? extraChallengeAvailable;
  final bool? challengeTicketAvailable;
  final bool? nextPlayRequiresAd;
  final bool? challengeRequiresAd;
  final bool? practiceRequiresAd;
  final int practiceTicketCapacity;
  final int practiceTicketsRemaining;
  final bool practiceRewardAvailable;
  final bool practiceRewardEarned;
  final int storePracticeTickets;
  final int storeChallengeTickets;
  final int storeNicknameColorTickets;
  final int storeNicknameChangeTickets;
  final String nicknameColor;
  final bool socialNotificationsEnabled;
  final bool rankedAdAttemptUsed;
  final bool coinAdAvailable;
  final bool deviceDailyLimitReached;
  final bool requiresKakaoForDailyPlay;
  final ClientCompatibility compatibility;
  final PlayerEconomy economy;
  final int levelRewardedThrough;
  final int levelCelebrationSeenThrough;
  final TomorrowGame? tomorrow;

  bool get requiresUpdate => compatibility.updateRequired;
  bool get canClaimDaily => testMode || (!dailyClaimed && attempts.isEmpty);
  int get completedPlayCount => playCount ?? attempts.length;
  bool get canChooseChallenge =>
      testMode ||
      (challengeAvailable ??
          (canClaimDaily || canChooseExtraChallenge || adAttemptAvailable));
  bool get canChooseAdChallenge =>
      !testMode &&
      !deviceDailyLimitReached &&
      (adChallengeAvailable ??
          challengeRequiresAd ??
          (rankedAdAttemptUsed ? false : extraChallengeAvailable) ??
          false);
  bool get canChooseExtraChallenge =>
      canChooseAdChallenge || canChooseChallengeTicket;
  bool get canChooseChallengeTicket =>
      !testMode &&
      !deviceDailyLimitReached &&
      (challengeTicketAvailable ??
          (rankedAdAttemptUsed && storeChallengeTickets > 0));
  bool get canChoosePractice => practiceAvailable;
  bool get canClaimPracticeReward => !testMode && practiceRewardAvailable;
  bool get requiresAdForNextPlay =>
      nextPlayRequiresAd ?? (!testMode && !canClaimDaily);
  bool get requiresAdForChallenge =>
      !testMode && (challengeRequiresAd ?? requiresAdForNextPlay);
  bool get requiresAdForPractice =>
      !testMode && (practiceRequiresAd ?? requiresAdForNextPlay);
  bool get hasPlayed => result?.score != null;
  bool get isTomorrowPreview =>
      tomorrow != null &&
      playDate.year == tomorrow!.playDate.year &&
      playDate.month == tomorrow!.playDate.month &&
      playDate.day == tomorrow!.playDate.day;
  bool get isExhausted =>
      !testMode && !canChooseChallenge && !canChoosePractice;

  TodayState withCompatibility(ClientCompatibility value) => TodayState(
    playDate: playDate,
    game: game,
    attempts: attempts,
    adAttemptAvailable: adAttemptAvailable,
    testMode: testMode,
    result: result,
    nickname: nickname,
    dailyClaimed: dailyClaimed,
    playCount: playCount,
    practicePlayCount: practicePlayCount,
    challengePending: challengePending,
    practicePending: practicePending,
    challengeAvailable: challengeAvailable,
    adChallengeAvailable: adChallengeAvailable,
    extraChallengeAvailable: extraChallengeAvailable,
    challengeTicketAvailable: challengeTicketAvailable,
    nextPlayRequiresAd: nextPlayRequiresAd,
    challengeRequiresAd: challengeRequiresAd,
    practiceRequiresAd: practiceRequiresAd,
    practiceTicketCapacity: practiceTicketCapacity,
    practiceTicketsRemaining: practiceTicketsRemaining,
    practiceRewardAvailable: practiceRewardAvailable,
    practiceRewardEarned: practiceRewardEarned,
    storePracticeTickets: storePracticeTickets,
    storeChallengeTickets: storeChallengeTickets,
    storeNicknameColorTickets: storeNicknameColorTickets,
    storeNicknameChangeTickets: storeNicknameChangeTickets,
    nicknameColor: nicknameColor,
    socialNotificationsEnabled: socialNotificationsEnabled,
    rankedAdAttemptUsed: rankedAdAttemptUsed,
    coinAdAvailable: coinAdAvailable,
    deviceDailyLimitReached: deviceDailyLimitReached,
    requiresKakaoForDailyPlay: requiresKakaoForDailyPlay,
    compatibility: value,
    economy: economy,
    levelRewardedThrough: levelRewardedThrough,
    levelCelebrationSeenThrough: levelCelebrationSeenThrough,
    tomorrow: tomorrow,
    practiceAvailable: practiceAvailable,
  );

  TodayState? get tomorrowPreview {
    final preview = tomorrow;
    if (preview == null) return null;
    return TodayState(
      playDate: preview.playDate,
      game: preview.game,
      attempts: const [],
      adAttemptAvailable: false,
      testMode: testMode,
      result: null,
      nickname: nickname,
      dailyClaimed: true,
      practiceAvailable: practiceAvailable,
      playCount: playCount,
      practicePlayCount: practicePlayCount,
      challengePending: false,
      practicePending: practicePending,
      challengeAvailable: false,
      adChallengeAvailable: false,
      extraChallengeAvailable: false,
      challengeTicketAvailable: false,
      nextPlayRequiresAd: false,
      challengeRequiresAd: false,
      practiceRequiresAd: practiceRequiresAd,
      practiceTicketCapacity: practiceTicketCapacity,
      practiceTicketsRemaining: practiceTicketsRemaining,
      practiceRewardAvailable: practiceRewardAvailable,
      practiceRewardEarned: practiceRewardEarned,
      storePracticeTickets: storePracticeTickets,
      storeChallengeTickets: storeChallengeTickets,
      storeNicknameColorTickets: storeNicknameColorTickets,
      storeNicknameChangeTickets: storeNicknameChangeTickets,
      nicknameColor: nicknameColor,
      socialNotificationsEnabled: socialNotificationsEnabled,
      rankedAdAttemptUsed: rankedAdAttemptUsed,
      coinAdAvailable: coinAdAvailable,
      deviceDailyLimitReached: deviceDailyLimitReached,
      requiresKakaoForDailyPlay: requiresKakaoForDailyPlay,
      compatibility: compatibility,
      economy: economy,
      levelRewardedThrough: levelRewardedThrough,
      levelCelebrationSeenThrough: levelCelebrationSeenThrough,
      tomorrow: tomorrow,
    );
  }
}
