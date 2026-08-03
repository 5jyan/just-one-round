abstract final class MiniGameSeed {
  static const algorithmVersion = 1;

  static int forAttempt({
    required String gameId,
    required int gameVersion,
    required DateTime? playDate,
    int? attemptOrdinal,
  }) {
    final date = playDate ?? _currentProductDate();
    final parts = <String>[
      algorithmVersion.toString(),
      date.year.toString().padLeft(4, '0'),
      date.month.toString().padLeft(2, '0'),
      date.day.toString().padLeft(2, '0'),
      gameId,
      gameVersion.toString(),
      if (attemptOrdinal != null) attemptOrdinal.clamp(1, 2).toString(),
    ];

    var hash = 0x811c9dc5;
    for (final codeUnit in parts.join(':').codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static DateTime _currentProductDate() {
    final shifted = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 9))
        .subtract(const Duration(hours: 6));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }
}
