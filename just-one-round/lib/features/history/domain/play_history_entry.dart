class PlayHistoryEntry {
  const PlayHistoryEntry({
    required this.playDate,
    required this.gameId,
    required this.displayName,
    required this.score,
    required this.rank,
    required this.participants,
  });

  factory PlayHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PlayHistoryEntry(
        playDate: DateTime.parse(json['play_date'] as String),
        gameId: json['game_id'] as String,
        displayName: json['display_name'] as String,
        score: (json['score'] as num).toInt(),
        rank: (json['rank'] as num).toInt(),
        participants: (json['participants'] as num).toInt(),
      );

  final DateTime playDate;
  final String gameId;
  final String displayName;
  final int score;
  final int rank;
  final int participants;
}
