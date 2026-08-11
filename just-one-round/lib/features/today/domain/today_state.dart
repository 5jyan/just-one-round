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
    this.userId,
    this.isNpc = false,
  });

  factory NearbyRank.fromJson(Map<String, dynamic> json) => NearbyRank(
    rank: (json['rank'] as num).toInt(),
    nickname: json['nickname'] as String,
    score: (json['score'] as num).toInt(),
    isMe: json['is_me'] as bool,
    userId: json['user_id'] as String?,
    isNpc: json['is_npc'] as bool? ?? false,
  );

  final int rank;
  final String nickname;
  final int score;
  final bool isMe;
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
    this.challengeAvailable,
    this.nextPlayRequiresAd,
    this.requiresKakaoForDailyPlay = false,
    this.compatibility = const ClientCompatibility.supported(),
    this.economy = const PlayerEconomy.zero(),
  });

  factory TodayState.fromJson(Map<String, dynamic> json) {
    final attempts = (json['attempts'] as List<dynamic>? ?? const [])
        .map((item) => PlayAttempt.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    final gameJson = json['game'] as Map<String, dynamic>?;
    final resultJson = json['result'] as Map<String, dynamic>?;
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
      challengeAvailable: json['challenge_available'] as bool?,
      nextPlayRequiresAd: json['next_play_requires_ad'] as bool?,
      requiresKakaoForDailyPlay:
          json['requires_kakao_for_daily_play'] as bool? ?? false,
      economy: _economyFromJson(json),
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
  final bool? challengeAvailable;
  final bool? nextPlayRequiresAd;
  final bool requiresKakaoForDailyPlay;
  final ClientCompatibility compatibility;
  final PlayerEconomy economy;

  bool get requiresUpdate => compatibility.updateRequired;
  bool get canClaimDaily => testMode || (!dailyClaimed && attempts.isEmpty);
  int get completedPlayCount => playCount ?? attempts.length;
  bool get canChooseChallenge =>
      challengeAvailable ?? (canClaimDaily || adAttemptAvailable);
  bool get canChoosePractice => practiceAvailable;
  bool get requiresAdForNextPlay =>
      nextPlayRequiresAd ?? (!testMode && !canClaimDaily);
  bool get hasPlayed => result?.score != null;
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
    challengeAvailable: challengeAvailable,
    nextPlayRequiresAd: nextPlayRequiresAd,
    requiresKakaoForDailyPlay: requiresKakaoForDailyPlay,
    compatibility: value,
    economy: economy,
    practiceAvailable: practiceAvailable,
  );
}
