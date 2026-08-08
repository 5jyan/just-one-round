import 'dart:math' as math;
import 'dart:ui';

import 'package:just_one_round/features/games/ten_pitch_slugger/domain/ten_pitch_slugger_rules.dart';

/// Visual-only timing for the V3/V4 atlases. Gameplay windows live in the rules
/// class and deliberately do not depend on these animation helpers.
abstract final class TenPitchSluggerMotion {
  static const swingContactSeconds = 0.12;
  static const swingDurationSeconds = 0.45;
  static const contactCorrectionSeconds = 0.07;
  static const hitStopSeconds = 0.055;
  static const farFlightProgress = 0.18;
  static const homeRunCelebrationDuration = 1.35;

  static const _swingTimes = <double>[
    0,
    0.016,
    0.032,
    0.049,
    0.066,
    0.083,
    0.099,
    0.111,
    swingContactSeconds,
    0.145,
    0.175,
    0.210,
    0.250,
    0.300,
    0.360,
    swingDurationSeconds,
  ];

  static const _regularWindupFrames = <int>[0, 1, 2, 3, 4, 6, 5];
  static const _regularFollowFrames = <int>[5, 7, 8, 9, 10, 11];
  static const _magicWindupFrames = <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 11];
  static const _magicFollowFrames = <int>[11, 12, 13, 14, 15];

  static int batterSwingFrame(double elapsedSeconds) =>
      _frameAtTimes(elapsedSeconds, _swingTimes);

  static double hitStopDurationFor(TenPitchHitType hitType) =>
      switch (hitType) {
        TenPitchHitType.groundBall => 0.035,
        TenPitchHitType.single => 0.045,
        TenPitchHitType.double => hitStopSeconds,
        TenPitchHitType.longHit => 0.075,
        TenPitchHitType.homeRun => 0.125,
      };

  static double feedbackSwingDuration({
    required bool hit,
    TenPitchHitType? hitType,
  }) =>
      swingDurationSeconds -
      swingContactSeconds +
      (hit ? hitStopDurationFor(hitType ?? TenPitchHitType.double) : 0);

  static int batterFeedbackSwingFrame({
    required double elapsedSeconds,
    required bool hit,
    TenPitchHitType? hitType,
  }) {
    final hitStopDuration = hit
        ? hitStopDurationFor(hitType ?? TenPitchHitType.double)
        : 0.0;
    final postContactElapsed = hit
        ? math.max(0.0, elapsedSeconds - hitStopDuration)
        : elapsedSeconds;
    return batterSwingFrame(swingContactSeconds + postContactElapsed);
  }

  static int regularWindupFrame(double progress) =>
      _regularWindupFrames[(progress.clamp(0.0, 0.999999) *
              _regularWindupFrames.length)
          .floor()];

  static int magicWindupFrame(double progress) =>
      _magicWindupFrames[(progress.clamp(0.0, 0.999999) *
              _magicWindupFrames.length)
          .floor()];

  /// Returns -1 once the pitcher has naturally recovered to the idle atlas.
  static int regularFollowThroughFrame(double elapsedSeconds) {
    if (elapsedSeconds >= 0.52) return -1;
    return _regularFollowFrames[_normalizedIndex(
      elapsedSeconds / 0.52,
      _regularFollowFrames.length,
    )];
  }

  /// The magic delivery gets a slightly longer recovery without holding.
  static int magicFollowThroughFrame(double elapsedSeconds) {
    if (elapsedSeconds >= 0.66) return -1;
    return _magicFollowFrames[_normalizedIndex(
      elapsedSeconds / 0.66,
      _magicFollowFrames.length,
    )];
  }

  /// Perspective arrival: measured time is unchanged, but the far half moves
  /// more slowly on screen and the near half accelerates toward the hitter.
  static double perspectiveProgress(double rawProgress) {
    final t = rawProgress.clamp(0.0, 1.0);
    return t / (2.4 - 1.4 * t);
  }

  static double contactCorrection({
    required double elapsedSeconds,
    required double resolutionSeconds,
  }) {
    final start = resolutionSeconds - contactCorrectionSeconds;
    if (elapsedSeconds <= start) return 0;
    final t = ((elapsedSeconds - start) / contactCorrectionSeconds).clamp(
      0.0,
      1.0,
    );
    return 1 - math.pow(1 - t, 3).toDouble();
  }

  static double hitFxDurationFor(TenPitchHitType hitType) => switch (hitType) {
    TenPitchHitType.groundBall => 0.16,
    TenPitchHitType.single => 0.21,
    TenPitchHitType.double => 0.27,
    TenPitchHitType.longHit => 0.34,
    TenPitchHitType.homeRun => 0.52,
  };

  static double hitFxScaleFor(TenPitchHitType hitType) => switch (hitType) {
    TenPitchHitType.groundBall => 0.68,
    TenPitchHitType.single => 0.82,
    TenPitchHitType.double => 1.0,
    TenPitchHitType.longHit => 1.22,
    TenPitchHitType.homeRun => 1.75,
  };

  static int hitFxFrame(
    double elapsedSeconds, {
    required TenPitchHitType hitType,
  }) => ((elapsedSeconds / hitFxDurationFor(hitType)).clamp(0.0, 0.999999) * 8)
      .floor();

  static double hitFlashDurationFor(TenPitchHitType hitType) =>
      switch (hitType) {
        TenPitchHitType.groundBall => 0.025,
        TenPitchHitType.single => 0.035,
        TenPitchHitType.double => 0.045,
        TenPitchHitType.longHit => 0.060,
        TenPitchHitType.homeRun => 0.180,
      };

  static double hitFlashPeakOpacityFor(TenPitchHitType hitType) =>
      switch (hitType) {
        TenPitchHitType.groundBall => 0.04,
        TenPitchHitType.single => 0.07,
        TenPitchHitType.double => 0.11,
        TenPitchHitType.longHit => 0.17,
        TenPitchHitType.homeRun => 0.30,
      };

  static double hitFlashOpacity(
    double elapsedSeconds, {
    required TenPitchHitType hitType,
  }) {
    final duration = hitFlashDurationFor(hitType);
    if (elapsedSeconds >= duration) return 0;
    final progress = elapsedSeconds / duration;
    final pulse = hitType == TenPitchHitType.homeRun
        ? 0.72 + 0.28 * math.cos(progress * math.pi * 4).abs()
        : 1.0;
    return hitFlashPeakOpacityFor(hitType) * (1 - progress) * pulse;
  }

  static double homeRunCelebrationOpacity(double elapsedSeconds) {
    if (elapsedSeconds < 0 || elapsedSeconds >= homeRunCelebrationDuration) {
      return 0;
    }
    if (elapsedSeconds < 0.10) return elapsedSeconds / 0.10;
    if (elapsedSeconds < 0.92) return 1;
    return 1 - (elapsedSeconds - 0.92) / (homeRunCelebrationDuration - 0.92);
  }

  static double homeRunCelebrationScale(double elapsedSeconds) {
    if (elapsedSeconds <= 0) return 0.72;
    if (elapsedSeconds < 0.14) {
      return 0.72 + 0.38 * (elapsedSeconds / 0.14);
    }
    if (elapsedSeconds < 0.28) {
      return 1.10 - 0.10 * ((elapsedSeconds - 0.14) / 0.14);
    }
    return 1;
  }

  static double hitShakeStrengthFor(TenPitchHitType hitType) =>
      switch (hitType) {
        TenPitchHitType.groundBall => 0.8,
        TenPitchHitType.single => 2.0,
        TenPitchHitType.double => 3.5,
        TenPitchHitType.longHit => 5.5,
        TenPitchHitType.homeRun => 10.0,
      };

  static double hitShakeDurationFor(TenPitchHitType hitType) =>
      switch (hitType) {
        TenPitchHitType.groundBall => 0.08,
        TenPitchHitType.single => 0.12,
        TenPitchHitType.double => 0.17,
        TenPitchHitType.longHit => 0.24,
        TenPitchHitType.homeRun => 0.42,
      };

  static double launchDurationFor(TenPitchHitType hitType) => switch (hitType) {
    TenPitchHitType.groundBall => 1.15,
    TenPitchHitType.single => 1.28,
    TenPitchHitType.double => 1.42,
    TenPitchHitType.longHit => 1.58,
    TenPitchHitType.homeRun => 2.00,
  };

  static double launchProgress(
    double elapsedSeconds, {
    required TenPitchHitType hitType,
    double coastSeconds = 0,
  }) {
    final launchElapsed = elapsedSeconds - hitStopDurationFor(hitType);
    if (launchElapsed <= 0) return 0;
    final duration = launchDurationFor(hitType);
    final rawProgress = launchElapsed / duration;
    if (rawProgress <= 1) {
      final clamped = rawProgress.clamp(0.0, 1.0);
      return switch (hitType) {
        TenPitchHitType.homeRun => math.pow(clamped, 1.22).toDouble(),
        TenPitchHitType.longHit => math.pow(clamped, 1.06).toDouble(),
        _ => clamped,
      };
    }
    if (coastSeconds <= 0) return 1;
    final coastProgress = ((launchElapsed - duration) / coastSeconds).clamp(
      0.0,
      1.0,
    );
    return 1 + farFlightProgress * coastProgress;
  }

  static int afterimageCountFor(TenPitchHitType hitType) => switch (hitType) {
    TenPitchHitType.groundBall => 1,
    TenPitchHitType.single => 2,
    TenPitchHitType.double => 3,
    TenPitchHitType.longHit => 4,
    TenPitchHitType.homeRun => 7,
  };

  static Offset launchedBallPoint({
    required Offset contact,
    required double progress,
    required double quality,
    required double direction,
    required TenPitchHitType hitType,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final coast = ((progress - 1) / farFlightProgress).clamp(0.0, 1.0);
    final q = quality.clamp(0.0, 1.0);
    final ease = 1 - math.pow(1 - p, 2.0).toDouble();
    final depthProgress = ease;
    final (depth, horizontal, lift) = switch (hitType) {
      TenPitchHitType.groundBall => (
        155 + 8 * q,
        82 + 20 * q,
        math.sin(p * math.pi * 4).abs() * (3 + 2 * q) * (1 - p),
      ),
      TenPitchHitType.single => (
        165 + 8 * q,
        102 + 24 * q,
        (32 + 8 * q) * 4 * p * (1 - p),
      ),
      TenPitchHitType.double => (
        175 + 8 * q,
        116 + 18 * q,
        (48 + 10 * q) * 4 * p * (1 - p),
      ),
      TenPitchHitType.longHit => (
        180 + 8 * q,
        120 + 10 * q,
        (65 + 15 * q) * 4 * p * (1 - p),
      ),
      TenPitchHitType.homeRun => (
        q < TenPitchSluggerRules.wallClearTrajectoryProgress
            ? 185 + 83 * q
            : 234.8 +
                  225.2 *
                      ((q - TenPitchSluggerRules.wallClearTrajectoryProgress) /
                          (1 -
                              TenPitchSluggerRules
                                  .wallClearTrajectoryProgress)),
        105 + 15 * q,
        (75 + 65 * q) * 4 * p * (1 - p),
      ),
    };
    final horizontalProgress = 0.65 * p + 0.35 * ease;
    final base = Offset(
      contact.dx + horizontal * direction * horizontalProgress,
      contact.dy - depth * depthProgress - lift,
    );
    final (coastHorizontal, coastDepth) = switch (hitType) {
      TenPitchHitType.groundBall => (8.0, 4.0),
      TenPitchHitType.single => (10.0, 5.0),
      TenPitchHitType.double => (10.0, 6.0),
      TenPitchHitType.longHit => (12.0, 3.0),
      TenPitchHitType.homeRun => (12.0 + 6 * q, 15.0 + 43 * q),
    };
    final coastEase = 1 - math.pow(1 - coast, 1.6).toDouble();
    final coastVertical = hitType == TenPitchHitType.groundBall
        ? -coastDepth * coastEase
        : coastDepth * coastEase;
    return base +
        Offset(coastHorizontal * direction * coastEase, coastVertical);
  }

  static double launchedBallSize(
    double progress, {
    required TenPitchHitType hitType,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final coast = ((progress - 1) / farFlightProgress).clamp(0.0, 1.0);
    final endSize = switch (hitType) {
      TenPitchHitType.groundBall => 9.0,
      TenPitchHitType.single => 7.0,
      TenPitchHitType.double => 6.0,
      TenPitchHitType.longHit => 4.0,
      TenPitchHitType.homeRun => 3.0,
    };
    final launchSize =
        endSize + (30 - endSize) * math.pow(1 - p, 1.25).toDouble();
    return launchSize * (1 - 0.55 * coast);
  }

  /// A missed pitch keeps its incoming vector, grows as it passes the camera,
  /// and leaves below the viewport instead of disappearing on judgement.
  static Offset missedBallPoint({
    required Offset release,
    required Offset contact,
    required double progress,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final incoming = contact - release;
    final length = incoming.distance;
    final direction = length == 0 ? const Offset(0, 1) : incoming / length;
    final distance = 195 * (1 - math.pow(1 - p, 1.45).toDouble());
    return contact + direction * distance;
  }

  static double missedBallSize(double progress) {
    final p = progress.clamp(0.0, 1.0);
    return 30 + 12 * p;
  }

  static double missedBallOpacity(double progress) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.72) return 1;
    return (1 - (p - 0.72) / 0.28).clamp(0.0, 1.0);
  }

  static Offset hitShakeOffset({
    required double elapsedSeconds,
    required double strength,
    required double duration,
    required int seed,
  }) {
    if (elapsedSeconds >= duration || strength <= 0) {
      return Offset.zero;
    }
    final decay = 1 - elapsedSeconds / duration;
    final phase = seed * 0.73;
    return Offset(
      (math.sin(elapsedSeconds * 82 + phase) * strength * decay)
          .roundToDouble(),
      (math.cos(elapsedSeconds * 97 + phase) * strength * 0.65 * decay)
          .roundToDouble(),
    );
  }

  static int loopingFrame(double elapsedSeconds, int frameCount, double fps) =>
      (elapsedSeconds * fps).floor() % frameCount;

  static int _frameAtTimes(double elapsedSeconds, List<double> times) {
    for (var index = times.length - 1; index >= 0; index--) {
      if (elapsedSeconds >= times[index]) return index;
    }
    return 0;
  }

  static int _normalizedIndex(double progress, int count) =>
      (progress.clamp(0.0, 0.999999) * count).floor();
}
