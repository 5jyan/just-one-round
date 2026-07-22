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
    this.gameId,
  });

  factory PlayAttempt.fromJson(Map<String, dynamic> json) => PlayAttempt(
    id: json['id'] as String,
    ordinal: json['ordinal'] as int,
    status: json['status'] as String,
    grantType: json['grant_type'] as String,
    gameId: json['game_id'] as String?,
  );

  final String id;
  final int ordinal;
  final String status;
  final String grantType;
  final String? gameId;
}

enum ProfileGender {
  male('male', '남성'),
  female('female', '여성');

  const ProfileGender(this.value, this.label);

  final String value;
  final String label;

  static ProfileGender? fromValue(String? value) {
    for (final gender in values) {
      if (gender.value == value) return gender;
    }
    return null;
  }
}

class UserProfile {
  const UserProfile({
    required this.nickname,
    required this.birthYear,
    required this.birthMonth,
    required this.gender,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    nickname: json['nickname'] as String?,
    birthYear: (json['birth_year'] as num?)?.toInt(),
    birthMonth: (json['birth_month'] as num?)?.toInt(),
    gender: ProfileGender.fromValue(json['gender'] as String?),
  );

  final String? nickname;
  final int? birthYear;
  final int? birthMonth;
  final ProfileGender? gender;

  int? get birthDecade => birthYear == null ? null : (birthYear! ~/ 10) * 10;
}

class NearbyRank {
  const NearbyRank({
    required this.rank,
    required this.nickname,
    required this.score,
    required this.isMe,
  });

  factory NearbyRank.fromJson(Map<String, dynamic> json) => NearbyRank(
    rank: (json['rank'] as num).toInt(),
    nickname: json['nickname'] as String,
    score: (json['score'] as num).toInt(),
    isMe: json['is_me'] as bool,
  );

  final int rank;
  final String nickname;
  final int score;
  final bool isMe;
}

class DailyRankResult {
  const DailyRankResult({
    required this.score,
    required this.rank,
    required this.participants,
    required this.topPercent,
    required this.nickname,
    required this.nearby,
  });

  factory DailyRankResult.fromJson(Map<String, dynamic> json) =>
      DailyRankResult(
        score: (json['score'] as num?)?.toInt(),
        rank: (json['rank'] as num?)?.toInt(),
        participants: (json['participants'] as num?)?.toInt() ?? 0,
        topPercent: (json['top_percent'] as num?)?.toInt(),
        nickname: json['nickname'] as String?,
        nearby: (json['nearby'] as List<dynamic>? ?? const [])
            .map((item) => NearbyRank.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final int? score;
  final int? rank;
  final int participants;
  final int? topPercent;
  final String? nickname;
  final List<NearbyRank> nearby;
}

class TodayState {
  const TodayState({
    required this.playDate,
    required this.game,
    required this.attempts,
    required this.adAttemptAvailable,
    required this.testMode,
    required this.result,
    required this.profile,
  });

  factory TodayState.fromJson(Map<String, dynamic> json) {
    final attempts = (json['attempts'] as List<dynamic>? ?? const [])
        .map((item) => PlayAttempt.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    final gameJson = json['game'] as Map<String, dynamic>?;
    final resultJson = json['result'] as Map<String, dynamic>?;
    final profileJson = json['profile'] as Map<String, dynamic>?;
    return TodayState(
      playDate: DateTime.parse(json['play_date'] as String),
      game: gameJson == null ? null : TodayGame.fromJson(gameJson),
      attempts: attempts,
      adAttemptAvailable: json['ad_attempt_available'] as bool? ?? false,
      testMode: json['test_mode'] as bool? ?? false,
      result: resultJson == null ? null : DailyRankResult.fromJson(resultJson),
      profile: profileJson == null
          ? const UserProfile(
              nickname: null,
              birthYear: null,
              birthMonth: null,
              gender: null,
            )
          : UserProfile.fromJson(profileJson),
    );
  }

  final DateTime playDate;
  final TodayGame? game;
  final List<PlayAttempt> attempts;
  final bool adAttemptAvailable;
  final bool testMode;
  final DailyRankResult? result;
  final UserProfile profile;

  bool get canClaimDaily => testMode || attempts.isEmpty;
  bool get hasPlayed => result?.score != null;
  bool get isExhausted =>
      (!testMode && attempts.length >= 2) ||
      (attempts.isNotEmpty && !adAttemptAvailable && !canClaimDaily);
}
