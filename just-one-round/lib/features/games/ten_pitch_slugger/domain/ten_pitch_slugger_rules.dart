import 'dart:math';

enum TenPitchMovement {
  straight,
  inside,
  outside,
  curve,
  slider,
  changeup,
  forkball,
  magic,
}

enum TenPitchJudgement { perfect, good, weak, earlyMiss, lateMiss, watched }

enum TenPitchHitType { groundBall, single, double, longHit, homeRun }

class TenPitchSpec {
  const TenPitchSpec({
    required this.number,
    required this.name,
    required this.flightSeconds,
    required this.hitWindowSeconds,
    required this.maximumDistanceCm,
    required this.movement,
    this.horizontalBreak = 0,
    this.verticalBreak = 0,
    this.breakDirection = 1,
  });

  final int number;
  final String name;
  final double flightSeconds;
  final double hitWindowSeconds;
  final int maximumDistanceCm;
  final TenPitchMovement movement;
  final double horizontalBreak;
  final double verticalBreak;
  final int breakDirection;

  double get idealTapSeconds =>
      flightSeconds - TenPitchSluggerRules.swingLeadSeconds;
}

abstract final class TenPitchSluggerRules {
  static const rulesVersion = 8;
  static const gameId = 'ten_pitch_slugger';
  static const pitchCount = 10;
  static const sluggerPitchNumber = 7;
  static const sluggerDistanceMultiplier = 1.25;
  static const safeOpeningSeconds = 2.0;
  static const watchdogDuration = Duration(seconds: 300);
  static const swingLeadSeconds = 0.12;
  static const swingCooldownSeconds = 0.30;
  static const minimumIdealTapSeconds = 0.46;
  static const minimumHitDistanceCm = 3500;
  static const homeRunDistanceCm = 10000;
  static const homeRunTimingRatio = 0.12;
  static const latePitchDistanceBonusMaxCm = 4000;
  static const latePitchProgressExponent = 1.8;
  static const wallClearDistanceCm = homeRunDistanceCm;
  // Keep the authored wall-flight curve unchanged for pitches 1-10. The
  // seventh-pitch score ceiling is higher, but distances beyond this visual
  // ceiling already use the fully-cleared trajectory.
  static const wallTrajectoryMaximumDistanceCm = 15000;
  static const theoreticalMaximumScoreCm = 16875;
  static const wallClearTrajectoryProgress =
      (wallClearDistanceCm - homeRunDistanceCm) /
      (theoreticalMaximumScoreCm - homeRunDistanceCm);

  static const _names = <String>[
    '연습 직구',
    '느린 직구',
    '빠른 직구',
    '몸쪽 직구',
    '바깥쪽 직구',
    '커브',
    '슬라이더',
    '체인지업',
    '포크볼',
    '도깨비 마구',
  ];

  static const _flightSeconds = <double>[
    1.55,
    1.34,
    1.17,
    1.03,
    0.92,
    0.83,
    0.76,
    0.70,
    0.65,
    0.60,
  ];

  static const _hitWindows = <double>[
    0.190,
    0.170,
    0.155,
    0.145,
    0.135,
    0.125,
    0.115,
    0.105,
    0.090,
    0.075,
  ];

  static const _movements = <TenPitchMovement>[
    TenPitchMovement.straight,
    TenPitchMovement.straight,
    TenPitchMovement.straight,
    TenPitchMovement.inside,
    TenPitchMovement.outside,
    TenPitchMovement.curve,
    TenPitchMovement.slider,
    TenPitchMovement.changeup,
    TenPitchMovement.forkball,
    TenPitchMovement.magic,
  ];

  static List<TenPitchSpec> buildPitchSequence(Random random) {
    return List<TenPitchSpec>.generate(pitchCount, (index) {
      final number = index + 1;
      final direction = random.nextBool() ? 1 : -1;
      // A tiny deterministic speed variation keeps daily attempts from feeling
      // mechanical without changing the authored difficulty order.
      final speedFactor = 0.99 + random.nextDouble() * 0.02;
      final movement = _movements[index];
      return TenPitchSpec(
        number: number,
        name: _names[index],
        flightSeconds: max(
          _flightSeconds[index] * speedFactor,
          minimumIdealTapSeconds + swingLeadSeconds,
        ),
        hitWindowSeconds: _hitWindows[index],
        maximumDistanceCm: 10500 + 500 * index,
        movement: movement,
        horizontalBreak: switch (movement) {
          TenPitchMovement.inside => 12,
          TenPitchMovement.outside => 18,
          TenPitchMovement.slider => 26,
          TenPitchMovement.magic => 28,
          _ => 0,
        },
        verticalBreak: switch (movement) {
          TenPitchMovement.curve => 24,
          TenPitchMovement.forkball || TenPitchMovement.magic => 32,
          _ => 0,
        },
        breakDirection: direction,
      );
    }, growable: false);
  }

  static int distanceForTiming({
    required TenPitchSpec pitch,
    required double timingErrorSeconds,
  }) {
    final error = timingErrorSeconds.abs();
    if (error > pitch.hitWindowSeconds) {
      return _applySluggerDistance(pitch, 0);
    }
    final ratio = error / pitch.hitWindowSeconds;

    // The first pitch establishes the base contact bands. Later pitches add a
    // deterministic quality-weighted distance bonus, so equivalent contact
    // travels farther without turning the outer edge into a free long hit.
    late int baseDistanceCm;
    if (ratio >= 0.8) {
      baseDistanceCm = _distanceWithinBand(
        ratio: ratio,
        outerRatio: 1,
        innerRatio: 0.8,
        minimumCm: minimumHitDistanceCm,
        maximumCm: 4299,
      );
    } else if (ratio >= 0.6) {
      baseDistanceCm = _distanceWithinBand(
        ratio: ratio,
        outerRatio: 0.8,
        innerRatio: 0.6,
        minimumCm: 4300,
        maximumCm: 5499,
      );
    } else if (ratio >= 0.4) {
      baseDistanceCm = _distanceWithinBand(
        ratio: ratio,
        outerRatio: 0.6,
        innerRatio: 0.4,
        minimumCm: 5500,
        maximumCm: 6999,
      );
    } else if (ratio >= homeRunTimingRatio) {
      baseDistanceCm = _distanceWithinBand(
        ratio: ratio,
        outerRatio: 0.4,
        innerRatio: homeRunTimingRatio,
        minimumCm: 7000,
        maximumCm: homeRunDistanceCm - 1,
      );
    } else {
      final perfectBandProgress =
          ((homeRunTimingRatio - ratio) / homeRunTimingRatio).clamp(0.0, 1.0);
      final restrainedProgress = pow(perfectBandProgress, 2.0).toDouble();
      return _applySluggerDistance(
        pitch,
        (homeRunDistanceCm +
                (pitch.maximumDistanceCm - homeRunDistanceCm) *
                    restrainedProgress)
            .round(),
      );
    }

    final pitchProgress = (pitch.number - 1) / (pitchCount - 1);
    final latePitchWeight = pow(
      pitchProgress,
      latePitchProgressExponent,
    ).toDouble();
    final contactStrength = ((1 - ratio) / (1 - homeRunTimingRatio)).clamp(
      0.0,
      1.0,
    );
    final latePitchBonus =
        (latePitchDistanceBonusMaxCm *
                latePitchWeight *
                pow(contactStrength, 1.4))
            .round();
    return _applySluggerDistance(
      pitch,
      min(homeRunDistanceCm - 1, baseDistanceCm + latePitchBonus),
    );
  }

  static int _applySluggerDistance(TenPitchSpec pitch, int distanceCm) {
    if (pitch.number != sluggerPitchNumber) return distanceCm;
    return (distanceCm * sluggerDistanceMultiplier).round();
  }

  static int _distanceWithinBand({
    required double ratio,
    required double outerRatio,
    required double innerRatio,
    required int minimumCm,
    required int maximumCm,
  }) {
    final progress = ((outerRatio - ratio) / (outerRatio - innerRatio)).clamp(
      0.0,
      1.0,
    );
    return (minimumCm + (maximumCm - minimumCm) * progress).round();
  }

  static TenPitchHitType? hitTypeForDistance(int distanceCm) {
    if (distanceCm <= 0) return null;
    if (distanceCm < 4300) return TenPitchHitType.groundBall;
    if (distanceCm < 5500) return TenPitchHitType.single;
    if (distanceCm < 7000) return TenPitchHitType.double;
    if (distanceCm < homeRunDistanceCm) return TenPitchHitType.longHit;
    return TenPitchHitType.homeRun;
  }

  static String hitTypeLabel(TenPitchHitType hitType) => switch (hitType) {
    TenPitchHitType.groundBall => '땅볼',
    TenPitchHitType.single => '1루타급',
    TenPitchHitType.double => '2루타급',
    TenPitchHitType.longHit => '장타',
    TenPitchHitType.homeRun => '홈런!',
  };

  static double normalizedHitQuality({
    required TenPitchSpec pitch,
    required int distanceCm,
  }) =>
      ((distanceCm - minimumHitDistanceCm) /
              (pitch.maximumDistanceCm - minimumHitDistanceCm))
          .clamp(0.0, 1.0)
          .toDouble();

  /// Progress inside the current hit tier, used for tier-specific impact
  /// intensity and flight variation. Fence clearance is handled separately.
  static double hitTypeProgress({
    required TenPitchSpec pitch,
    required int distanceCm,
  }) {
    final hitType = hitTypeForDistance(distanceCm);
    if (hitType == null) return 0;
    final (minimumCm, maximumCm) = switch (hitType) {
      TenPitchHitType.groundBall => (minimumHitDistanceCm, 4299),
      TenPitchHitType.single => (4300, 5499),
      TenPitchHitType.double => (5500, 6999),
      TenPitchHitType.longHit => (7000, homeRunDistanceCm - 1),
      TenPitchHitType.homeRun => (homeRunDistanceCm, pitch.maximumDistanceCm),
    };
    if (maximumCm <= minimumCm) return 1;
    return ((distanceCm - minimumCm) / (maximumCm - minimumCm))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Fixed trajectory progress from the 100m home-run threshold to the
  /// authored 150m visual ceiling. Every home run clears the wall before
  /// descending; the 7th-pitch score extension stays at full clearance.
  static double wallHeightProgress(int distanceCm) =>
      ((distanceCm - homeRunDistanceCm) /
              (wallTrajectoryMaximumDistanceCm - homeRunDistanceCm))
          .clamp(0.0, 1.0)
          .toDouble();

  /// Early contact pulls toward left field, late contact pushes toward right.
  /// Near-perfect contact keeps the pitch's seeded direction for variation.
  static double launchDirectionForTiming({
    required TenPitchSpec pitch,
    required double timingErrorSeconds,
  }) {
    const lanes = <double>[-1, -0.45, 0.45, 1];
    final seededLane =
        (pitch.number * 2 + (pitch.breakDirection > 0 ? 1 : 0)) % lanes.length;
    final normalizedTiming = timingErrorSeconds / pitch.hitWindowSeconds;
    final timingBias = normalizedTiming < -0.15
        ? -1
        : normalizedTiming > 0.15
        ? 1
        : 0;
    final laneIndex = (seededLane + timingBias).clamp(0, lanes.length - 1);
    return lanes[laneIndex];
  }

  static TenPitchJudgement judgementForTiming({
    required TenPitchSpec pitch,
    required double? timingErrorSeconds,
  }) {
    if (timingErrorSeconds == null) return TenPitchJudgement.watched;
    final error = timingErrorSeconds.abs();
    if (error > pitch.hitWindowSeconds) {
      return timingErrorSeconds < 0
          ? TenPitchJudgement.earlyMiss
          : TenPitchJudgement.lateMiss;
    }
    final ratio = error / pitch.hitWindowSeconds;
    if (ratio <= 0.2) return TenPitchJudgement.perfect;
    if (ratio <= 0.6) return TenPitchJudgement.good;
    return TenPitchJudgement.weak;
  }

  static String judgementLabel(TenPitchJudgement judgement) =>
      switch (judgement) {
        TenPitchJudgement.perfect => '정타!',
        TenPitchJudgement.good => '좋아!',
        TenPitchJudgement.weak => '빗맞음',
        TenPitchJudgement.earlyMiss => '너무 빨랐어!',
        TenPitchJudgement.lateMiss => '너무 늦었어!',
        TenPitchJudgement.watched => '공이 지나갔어!',
      };

  static String formatScore(int scoreCm) => _formatMeters(scoreCm, 2);

  static String formatHudScore(int scoreCm) => _formatMeters(scoreCm, 1);

  static String _formatMeters(int scoreCm, int fractionDigits) {
    final parts = (scoreCm / 100).toStringAsFixed(fractionDigits).split('.');
    final whole = parts.first;
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return fractionDigits == 0 ? '${grouped}m' : '$grouped.${parts.last}m';
  }
}
