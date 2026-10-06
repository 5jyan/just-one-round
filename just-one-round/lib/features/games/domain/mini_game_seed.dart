import 'dart:math';

abstract final class MiniGameSeed {
  static const algorithmVersion = 1;

  /// Returns an unpredictable seed for games whose boards must differ for
  /// every play.  The optional source keeps the helper deterministic in unit
  /// tests while production callers use Dart's secure random source.
  static int randomSeed({Random? random}) =>
      (random ?? Random.secure()).nextInt(0x7fffffff);

  static int forAttempt({
    required String gameId,
    required int gameVersion,
    required DateTime? playDate,
    int? attemptOrdinal,
    int? practiceOrdinal,
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
      if (practiceOrdinal != null) 'practice-${practiceOrdinal.clamp(1, 9999)}',
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
