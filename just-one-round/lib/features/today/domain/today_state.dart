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

class PlayAttempt {
  const PlayAttempt({
    required this.id,
    required this.ordinal,
    required this.status,
    required this.grantType,
  });

  factory PlayAttempt.fromJson(Map<String, dynamic> json) => PlayAttempt(
    id: json['id'] as String,
    ordinal: json['ordinal'] as int,
    status: json['status'] as String,
    grantType: json['grant_type'] as String,
  );

  final String id;
  final int ordinal;
  final String status;
  final String grantType;
}

class DailyRankResult {
  const DailyRankResult({
    required this.score,
    required this.rank,
    required this.participants,
    required this.topPercent,
  });

  factory DailyRankResult.fromJson(Map<String, dynamic> json) =>
      DailyRankResult(
        score: (json['score'] as num?)?.toInt(),
        rank: (json['rank'] as num?)?.toInt(),
        participants: (json['participants'] as num?)?.toInt() ?? 0,
        topPercent: (json['top_percent'] as num?)?.toInt(),
      );

  final int? score;
  final int? rank;
  final int participants;
  final int? topPercent;
}

class TodayState {
  const TodayState({
    required this.playDate,
    required this.game,
    required this.attempts,
    required this.adAttemptAvailable,
    required this.result,
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
      result: resultJson == null ? null : DailyRankResult.fromJson(resultJson),
    );
  }

  final DateTime playDate;
  final TodayGame? game;
  final List<PlayAttempt> attempts;
  final bool adAttemptAvailable;
  final DailyRankResult? result;

  bool get canClaimDaily => attempts.isEmpty;
  bool get hasPlayed => result?.score != null;
  bool get isExhausted =>
      attempts.length >= 2 ||
      (attempts.isNotEmpty && !adAttemptAvailable && !canClaimDaily);
}
