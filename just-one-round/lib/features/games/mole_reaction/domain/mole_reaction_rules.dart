import 'dart:math';

/// The kind of target shown during a mole reaction event.
enum MoleReactionTargetKind { normal, golden }

/// Visual feedback tier for one successful reaction.
///
/// Reaction time is a lower-is-better measurement, so the first tier is the
/// fastest one. Keeping the thresholds in the rules layer lets the runtime HUD
/// and the Flame impact burst use exactly the same cutoffs.
enum MoleReactionSpeedTier { perfect, lightning, great, steady, late }

/// One deterministic target in a mole reaction challenge.
class MoleReactionEvent {
  const MoleReactionEvent({
    required this.index,
    required this.holeIndex,
    required this.kind,
    required this.waitSeconds,
  });

  final int index;
  final int holeIndex;
  final MoleReactionTargetKind kind;
  final int waitSeconds;

  bool get isGolden => kind == MoleReactionTargetKind.golden;

  /// The first event is a no-stakes warm-up. Only the final golden event is
  /// included in the ranked result.
  bool get isPreparation => index < MoleReactionRules.preparationEventCount;

  bool get isScored => !isPreparation;

  int get delaySeconds => waitSeconds;

  int get hole => holeIndex;

  bool get golden => isGolden;

  Duration get wait => Duration(seconds: waitSeconds);

  @override
  bool operator ==(Object other) =>
      other is MoleReactionEvent &&
      other.index == index &&
      other.holeIndex == holeIndex &&
      other.kind == kind &&
      other.waitSeconds == waitSeconds;

  @override
  int get hashCode => Object.hash(index, holeIndex, kind, waitSeconds);
}

/// The complete, pre-generated event roster for one run.
class MoleReactionChallenge {
  const MoleReactionChallenge({required this.seed, required this.events});

  final int seed;
  final List<MoleReactionEvent> events;

  int get goldenEventIndex => events.indexWhere((event) => event.isGolden);

  int get normalEventCount => events.where((event) => !event.isGolden).length;

  int get goldenEventCount => events.where((event) => event.isGolden).length;

  MoleReactionEvent operator [](int index) => events[index];

  int get length => events.length;
}

/// Pure rules and deterministic generation for the mole reaction game.
abstract final class MoleReactionRules {
  static const int rulesVersion = 2;

  static const int columnCount = 2;
  static const int rowCount = 2;
  static const int holeCount = columnCount * rowCount;

  static const int preparationEventCount = 1;
  static const int normalEventCount = preparationEventCount;
  static const int goldenEventCount = 1;
  static const int eventCount = normalEventCount + goldenEventCount;
  // Public aliases keep the contract readable at call sites and in HUD code.
  static const int totalEvents = eventCount;
  static const int normalMoleCount = normalEventCount;
  static const int goldenMoleCount = goldenEventCount;

  /// The two events are distributed across the four holes so the practice and
  /// scored target do not begin in the same slot by default.
  static const int maxHoleUsesPerRun =
      (eventCount + holeCount - 1) ~/ holeCount;

  /// Normal events use the same neutral brown mole. Only the final event
  /// changes identity to the attached-reference golden mole.
  static const int normalMoleColorVariantCount = 1;

  static const int minimumWaitSeconds = 3;
  static const int maximumWaitSeconds = 8;
  static const int minimumAppearanceDelaySeconds = minimumWaitSeconds;
  static const int maximumAppearanceDelaySeconds = maximumWaitSeconds;
  static const int countdownMilliseconds = 3200;
  static const int targetActiveMilliseconds = 1500;
  static const int invalidTapPenaltyMilliseconds = 1000;
  static const int normalMissPenaltyMilliseconds = 2000;
  static const int goldenMissPenaltyMilliseconds = 4000;
  static const int goldenReactionMultiplier = 2;
  static const int sessionDeadlineMilliseconds = 180000;
  static const int gameDurationSeconds = sessionDeadlineMilliseconds ~/ 1000;

  /// Prompt shown above the board while the player waits for the next mole.
  /// Keeping these strings in the rules layer lets the game runtime and HUD
  /// agree on when the large CLEAR-style title should be displayed.
  static const String preparationPrompt = '첫 두더지는 연습이에요!';
  static const String realPrompt = '이번엔 진짜에요!';

  /// The preparation event is excluded from the ranked result. The minimum
  /// valid total is therefore one 1ms golden reaction weighted by two.
  static const int minimumValidTotalMilliseconds = goldenReactionMultiplier;

  /// The shared leaderboard sorts raw scores descending.
  static const int rankingCeiling = 1000000;
  static const int timeoutRankingScore = 0;

  static const Duration countdownDuration = Duration(
    milliseconds: countdownMilliseconds,
  );
  static const Duration targetActiveDuration = Duration(
    milliseconds: targetActiveMilliseconds,
  );
  static const Duration sessionDeadline = Duration(
    milliseconds: sessionDeadlineMilliseconds,
  );

  /// Default wall-clock budget used by the game registry and runtime.
  static const Duration gameDuration = sessionDeadline;

  /// Generates the fixed one-preparation/one-golden roster for a seed.
  ///
  /// Each event receives an independent wait in the contracted three-to-eight
  /// second range. The wait pool is shuffled before each pass so the two-event
  /// run does not imply a predictable order while remaining reproducible.
  static MoleReactionChallenge challengeForSeed(int seed) {
    final random = Random(seed);
    final waits = <int>[];
    while (waits.length < eventCount) {
      final pool = [
        for (
          var seconds = minimumWaitSeconds;
          seconds <= maximumWaitSeconds;
          seconds++
        )
          seconds,
      ]..shuffle(random);
      waits.addAll(pool.take(min(eventCount - waits.length, pool.length)));
    }
    waits.shuffle(random);

    // The golden mole is the final reveal. The first event is a normal,
    // no-stakes warm-up so the player can settle before the one real attempt.
    final goldenIndex = eventCount - 1;
    final holeCounts = List<int>.filled(holeCount, 0);
    final events = <MoleReactionEvent>[];
    for (var index = 0; index < eventCount; index++) {
      final candidates = <int>[
        for (var hole = 0; hole < holeCount; hole++)
          if (holeCounts[hole] < maxHoleUsesPerRun) hole,
      ];
      final holeIndex = candidates[random.nextInt(candidates.length)];
      holeCounts[holeIndex]++;
      events.add(
        MoleReactionEvent(
          index: index,
          holeIndex: holeIndex,
          kind: index == goldenIndex
              ? MoleReactionTargetKind.golden
              : MoleReactionTargetKind.normal,
          waitSeconds: waits[index],
        ),
      );
    }
    return MoleReactionChallenge(
      seed: seed,
      events: List<MoleReactionEvent>.unmodifiable(events),
    );
  }

  /// Alias used by callers that prefer the term roster.
  static MoleReactionChallenge rosterForSeed(int seed) =>
      challengeForSeed(seed);

  static bool isValidHoleIndex(int holeIndex) =>
      holeIndex >= 0 && holeIndex < holeCount;

  static bool isValidEventIndex(int eventIndex) =>
      eventIndex >= 0 && eventIndex < eventCount;

  static bool isValidWaitSeconds(int seconds) =>
      seconds >= minimumWaitSeconds && seconds <= maximumWaitSeconds;

  static bool isValidReactionMilliseconds(int milliseconds) =>
      milliseconds >= 0 && milliseconds <= targetActiveMilliseconds;

  /// Classifies a reaction for its on-screen feedback effect.
  ///
  /// The fastest tier is 150ms or less, followed by 300ms, 450ms, and 600ms.
  /// Values above 600ms still count as a hit but receive the calmer late tier.
  static MoleReactionSpeedTier speedTierForMilliseconds(int milliseconds) {
    if (!isValidReactionMilliseconds(milliseconds)) {
      throw ArgumentError.value(milliseconds, 'milliseconds');
    }
    if (milliseconds <= 150) return MoleReactionSpeedTier.perfect;
    if (milliseconds <= 300) return MoleReactionSpeedTier.lightning;
    if (milliseconds <= 450) return MoleReactionSpeedTier.great;
    if (milliseconds <= 600) return MoleReactionSpeedTier.steady;
    return MoleReactionSpeedTier.late;
  }

  /// Returns an integer display value while preserving the zero-tick floor.
  static int quantizeReactionMilliseconds(int milliseconds) {
    if (!isValidReactionMilliseconds(milliseconds)) {
      throw ArgumentError.value(milliseconds, 'milliseconds');
    }
    return max(1, milliseconds);
  }

  static int weightedReactionMilliseconds({
    required int reactionMilliseconds,
    required bool golden,
  }) {
    final reaction = quantizeReactionMilliseconds(reactionMilliseconds);
    return golden ? reaction * goldenReactionMultiplier : reaction;
  }

  static int invalidTapPenalty({int count = 1}) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return count * invalidTapPenaltyMilliseconds;
  }

  static int missPenalty({required bool golden}) =>
      golden ? goldenMissPenaltyMilliseconds : normalMissPenaltyMilliseconds;

  static int totalMilliseconds({
    required int weightedReactionTotalMilliseconds,
    required int invalidTapCount,
    required int normalMissCount,
    required int goldenMissCount,
  }) {
    if (weightedReactionTotalMilliseconds < 0) {
      throw ArgumentError.value(
        weightedReactionTotalMilliseconds,
        'weightedReactionTotalMilliseconds',
      );
    }
    if (invalidTapCount < 0) {
      throw ArgumentError.value(invalidTapCount, 'invalidTapCount');
    }
    if (normalMissCount < 0) {
      throw ArgumentError.value(normalMissCount, 'normalMissCount');
    }
    if (goldenMissCount < 0) {
      throw ArgumentError.value(goldenMissCount, 'goldenMissCount');
    }
    return weightedReactionTotalMilliseconds +
        invalidTapPenalty(count: invalidTapCount) +
        normalMissCount * normalMissPenaltyMilliseconds +
        goldenMissCount * goldenMissPenaltyMilliseconds;
  }

  /// Converts the lower-is-better total into the shared higher-is-better score.
  static int rankingScoreForTotal(int totalMilliseconds) {
    if (totalMilliseconds < minimumValidTotalMilliseconds ||
        totalMilliseconds >= rankingCeiling) {
      throw ArgumentError.value(totalMilliseconds, 'totalMilliseconds');
    }
    return rankingCeiling - totalMilliseconds;
  }

  static int rankingScoreForResult({
    required int totalMilliseconds,
    required bool timedOut,
  }) =>
      timedOut ? timeoutRankingScore : rankingScoreForTotal(totalMilliseconds);

  static int rankingScoreFromTotalMs(int totalMilliseconds) =>
      rankingScoreForTotal(totalMilliseconds);

  static int totalFromRankingScore(int score) {
    if (score <= timeoutRankingScore || score >= rankingCeiling) {
      throw ArgumentError.value(score, 'score');
    }
    final total = rankingCeiling - score;
    if (total < minimumValidTotalMilliseconds || total >= rankingCeiling) {
      throw ArgumentError.value(score, 'score');
    }
    return total;
  }

  static int totalMsFromRankingScore(int score) => totalFromRankingScore(score);

  static String formatTotalMs(int totalMilliseconds) =>
      '${_formatInteger(totalMilliseconds)}ms';

  static String formatElapsedMs(int milliseconds) =>
      formatTotalMs(milliseconds);

  static String formatTotalMilliseconds(int milliseconds) =>
      formatTotalMs(milliseconds);

  static String formatRankingScore(int score) {
    if (score == timeoutRankingScore) return '시간 초과';
    return formatTotalMs(totalFromRankingScore(score));
  }

  static String _formatInteger(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
      buffer.write(text[index]);
    }
    return buffer.toString();
  }
}
