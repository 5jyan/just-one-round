enum RamenTimerVerdict { perfect, tooEarly, tooLate }

abstract final class RamenTimerRules {
  static const rulesVersion = 4;
  static const targetMilliseconds = <int>[10000, 20000, 30000];
  static const culinaryActionLabels = <String>['파 넣기', '계란 넣기', '뚜껑 열기'];
  static const calibrationVisibleMilliseconds = 3000;
  static const inputUnlockMilliseconds = 3200;
  static const inputLockMilliseconds = 250;
  static const ingredientEventMilliseconds = 720;
  static const checkpointFeedbackMilliseconds = 2000;
  static const timeoutMilliseconds = 45000;
  static const rankingCeilingMilliseconds = 3600000;
  static const timeoutRankingScore = 0;
  static const perfectErrorMaximumMilliseconds = 190;

  static const earliestTapMilliseconds = <int>[3200, 3450, 3700];
  static const latestTapMilliseconds = <int>[44500, 44750, 45000];

  static final int maximumNormalErrorMilliseconds = totalErrorMilliseconds(
    latestTapMilliseconds,
  );

  static final int minimumNormalRankingScore =
      rankingCeilingMilliseconds - maximumNormalErrorMilliseconds;

  static int quantizeMilliseconds(int milliseconds) {
    if (milliseconds < 0) {
      throw ArgumentError.value(milliseconds, 'milliseconds');
    }
    return ((milliseconds + 5) ~/ 10) * 10;
  }

  static int quantizeMicroseconds(int microseconds) {
    if (microseconds < 0) {
      throw ArgumentError.value(microseconds, 'microseconds');
    }
    return ((microseconds + 5000) ~/ 10000) * 10;
  }

  static List<int> quantizedTapMilliseconds(Iterable<int> tapMilliseconds) {
    final taps = tapMilliseconds.toList(growable: false);
    _checkTapCount(taps);
    return List<int>.unmodifiable(taps.map(quantizeMilliseconds));
  }

  static List<int> signedErrorsMilliseconds(Iterable<int> tapMilliseconds) {
    final taps = quantizedTapMilliseconds(tapMilliseconds);
    return List<int>.unmodifiable(
      List<int>.generate(
        targetMilliseconds.length,
        (index) => taps[index] - targetMilliseconds[index],
      ),
    );
  }

  static int totalErrorMilliseconds(Iterable<int> tapMilliseconds) =>
      signedErrorsMilliseconds(
        tapMilliseconds,
      ).fold(0, (total, error) => total + error.abs());

  static int rankingScore(Iterable<int> tapMilliseconds) =>
      rankingCeilingMilliseconds - totalErrorMilliseconds(tapMilliseconds);

  static int? errorMillisecondsFromRankingScore(int score) {
    if (score == timeoutRankingScore) return null;
    if (score < minimumNormalRankingScore ||
        score > rankingCeilingMilliseconds) {
      throw ArgumentError.value(score, 'score');
    }
    return rankingCeilingMilliseconds - score;
  }

  static bool isNormalRankingScore(int score) =>
      score >= minimumNormalRankingScore &&
      score <= rankingCeilingMilliseconds &&
      score % 10 == 0;

  static bool isValidTapSequence(Iterable<int> tapMilliseconds) {
    final taps = tapMilliseconds.toList(growable: false);
    if (taps.length != targetMilliseconds.length) return false;
    if (taps.first < inputUnlockMilliseconds ||
        taps.last > timeoutMilliseconds) {
      return false;
    }
    for (var index = 1; index < taps.length; index++) {
      if (taps[index] - taps[index - 1] < inputLockMilliseconds) return false;
    }
    return true;
  }

  static RamenTimerVerdict verdict(Iterable<int> tapMilliseconds) {
    final taps = tapMilliseconds.toList(growable: false);
    final errors = signedErrorsMilliseconds(taps);
    final total = errors.fold(0, (sum, error) => sum + error.abs());
    if (total <= perfectErrorMaximumMilliseconds) {
      return RamenTimerVerdict.perfect;
    }

    var decidingError = errors.last;
    if (decidingError == 0) {
      decidingError = errors.reduce(
        (current, candidate) =>
            candidate.abs() > current.abs() ? candidate : current,
      );
    }
    return decidingError < 0
        ? RamenTimerVerdict.tooEarly
        : RamenTimerVerdict.tooLate;
  }

  static int largestErrorIndex(Iterable<int> tapMilliseconds) {
    final errors = signedErrorsMilliseconds(tapMilliseconds);
    var largestIndex = 0;
    for (var index = 1; index < errors.length; index++) {
      if (errors[index].abs() > errors[largestIndex].abs()) {
        largestIndex = index;
      }
    }
    return largestIndex;
  }

  static String formatMilliseconds(int milliseconds) {
    final centiseconds = (milliseconds.abs() / 10).round();
    final seconds = centiseconds ~/ 100;
    final fraction = centiseconds % 100;
    return '$seconds.${fraction.toString().padLeft(2, '0')}초';
  }

  static String formatSignedError(int signedErrorMilliseconds) {
    if (signedErrorMilliseconds == 0) return '정확!';
    final direction = signedErrorMilliseconds < 0 ? '빠름' : '늦음';
    return '${formatMilliseconds(signedErrorMilliseconds)} $direction';
  }

  static String formatSignedDelta(int signedErrorMilliseconds) {
    if (signedErrorMilliseconds == 0) return '±0.00초';
    final sign = signedErrorMilliseconds > 0 ? '+' : '-';
    return '$sign${formatMilliseconds(signedErrorMilliseconds)}';
  }

  static int signedErrorForTap(int tapIndex, int tapMilliseconds) {
    if (tapIndex < 0 || tapIndex >= targetMilliseconds.length) {
      throw RangeError.index(tapIndex, targetMilliseconds, 'tapIndex');
    }
    return quantizeMilliseconds(tapMilliseconds) - targetMilliseconds[tapIndex];
  }

  static String formatRankingScore(int score) {
    final error = errorMillisecondsFromRankingScore(score);
    return error == null ? '시간 초과' : '총 오차 ${formatMilliseconds(error)}';
  }

  static String targetLabelForTapCount(int tapCount) {
    final safeIndex = tapCount.clamp(0, targetMilliseconds.length - 1);
    return '${targetMilliseconds[safeIndex] ~/ 1000}초';
  }

  static String culinaryActionLabelForTapCount(int tapCount) {
    final safeIndex = tapCount.clamp(0, targetMilliseconds.length - 1);
    return '${targetLabelForTapCount(safeIndex)} · '
        '${culinaryActionLabels[safeIndex]}';
  }

  static void _checkTapCount(List<int> taps) {
    if (taps.length != targetMilliseconds.length) {
      throw ArgumentError.value(
        taps.length,
        'tapMilliseconds.length',
        'Exactly ${targetMilliseconds.length} taps are required.',
      );
    }
  }
}
