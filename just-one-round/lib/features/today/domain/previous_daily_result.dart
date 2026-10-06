import 'package:just_one_round/features/economy/domain/daily_reward_rules.dart';

class PreviousDailyResult {
  const PreviousDailyResult({
    required this.playDate,
    required this.gameId,
    required this.displayName,
    required this.score,
    required this.rank,
    required this.participants,
    required this.topPercent,
    this.rewardCoins,
    this.rewardExperiencePoints,
  });

  factory PreviousDailyResult.fromJson(Map<String, dynamic> json) =>
      PreviousDailyResult(
        playDate: DateTime.parse(json['play_date'] as String),
        gameId: json['game_id'] as String,
        displayName: json['display_name'] as String,
        score: (json['score'] as num).toInt(),
        rank: (json['rank'] as num).toInt(),
        participants: (json['participants'] as num).toInt(),
        topPercent: (json['top_percent'] as num).toInt(),
        rewardCoins: (json['reward_coins'] as num?)?.toInt(),
        rewardExperiencePoints: (json['reward_experience_points'] as num?)
            ?.toInt(),
      );

  final DateTime playDate;
  final String gameId;
  final String displayName;
  final int score;
  final int rank;
  final int participants;
  final int topPercent;
  final int? rewardCoins;
  final int? rewardExperiencePoints;

  int get effectiveRankingBonusCoins => DailyRewardRules.rankingBonusForResult(
    rank: rank,
    participants: participants,
  );

  int get effectiveRewardCoins =>
      rewardCoins ??
      DailyRewardRules.coinsForResult(rank: rank, participants: participants);

  int get effectiveRewardExperiencePoints =>
      rewardExperiencePoints ??
      DailyRewardRules.experienceForCoins(effectiveRewardCoins);
}
