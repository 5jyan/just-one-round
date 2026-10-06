import 'dart:math';

import 'package:flutter/painting.dart';

class WindDartsWind {
  const WindDartsWind({
    required this.clockDirection,
    required this.metersPerSecond,
  });

  /// 0 is 12 o'clock; each following value advances 30 degrees clockwise.
  final int clockDirection;
  final double metersPerSecond;

  String get label => clockDirection == 0 ? '12시' : '$clockDirection시';
  Offset get unitVector {
    final angle = clockDirection * pi / 6;
    return Offset(sin(angle), -cos(angle));
  }
}

class WindDartsAimSample {
  const WindDartsAimSample({required this.offset, required this.power});

  final Offset offset;
  final double power;
}

enum WindDartsImpactKind { miss, single, double, triple, doubleBull }

class WindDartsImpact {
  const WindDartsImpact({
    required this.score,
    required this.sector,
    required this.multiplier,
    required this.kind,
  });

  final int score;
  final int? sector;
  final int multiplier;
  final WindDartsImpactKind kind;
}

abstract final class WindDartsRules {
  static const rulesVersion = 3;
  static const shotCount = 6;
  // Kept as catalog metadata for the shared attempt/session schema. It is not
  // a player-facing game timer; v3 ends only after all six throws complete.
  static const gameDuration = Duration(seconds: 75);
  static const aimGaugeFillSeconds = 6.0;
  // Compatibility alias used by the existing preview and guide test cycle.
  // Holding past this point remains legal and continues the jitter waveform.
  static const maxAimSeconds = aimGaugeFillSeconds;
  static const impactDisplayDuration = Duration(seconds: 2);
  // The source board's 20 sector is authored around the 12 o'clock axis.
  // Keep the scorer's compatibility angle at -9° so the visual renderer's
  // fixed +9° alignment leaves that sector exactly at the top.
  static const boardAngle = -pi / 20;
  // Retained as a zero-valued compatibility constant for older callers.
  static const boardRotationRadiansPerSecond = 0.0;
  static const windOffsetCoefficient = 0.48;
  static const aimJitterHorizontalCoefficient = 0.36;
  static const aimJitterVerticalCoefficient = 0.30;
  static const baseBoardRadius = 142.0;
  static const tripleInnerRadiusRatio = 95 / 170;
  static const tripleOuterRadiusRatio = 111 / 170;
  static const doubleInnerRadiusRatio = 154 / 170;
  static const doubleOuterRadiusRatio = 1.0;
  static const _shotDistances = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5];
  static const _boardScales = [1.0, 0.91, 0.82, 0.745, 0.67, 0.61];
  static const sectorOrder = <int>[
    20,
    1,
    18,
    4,
    13,
    6,
    10,
    15,
    2,
    17,
    3,
    19,
    7,
    16,
    8,
    11,
    14,
    9,
    12,
    5,
  ];

  static List<WindDartsWind> windsForSeed(int seed) {
    final random = Random(seed ^ 0x57494E44);
    return List.generate(
      shotCount,
      (_) => WindDartsWind(
        clockDirection: random.nextInt(12),
        metersPerSecond: (5 + random.nextInt(31)) / 10,
      ),
      growable: false,
    );
  }

  static double boardScaleForShot(int shotIndex) =>
      _boardScales[shotIndex.clamp(0, shotCount - 1)];

  static double distanceForShot(int shotIndex) =>
      _shotDistances[shotIndex.clamp(0, shotCount - 1)];

  static String distanceLabelForShot(int shotIndex) {
    final distance = distanceForShot(shotIndex);
    return distance == distance.roundToDouble()
        ? '${distance.toInt()}m'
        : '${distance}m';
  }

  static double boardAngleAt(double elapsedSeconds) => boardAngle;

  static WindDartsAimSample aimAt(double heldSeconds, double radius) {
    final t = max(0.0, heldSeconds);
    return WindDartsAimSample(
      offset: Offset(
        sin(t * 2.25) * radius * aimJitterHorizontalCoefficient,
        sin(t * 1.73) * radius * aimJitterVerticalCoefficient,
      ),
      power: powerAt(t),
    );
  }

  static double powerAt(double heldSeconds) {
    return (heldSeconds / aimGaugeFillSeconds).clamp(0.0, 1.0);
  }

  static WindDartsImpact resolveImpact({
    required Offset point,
    required double boardRadius,
    required double boardAngle,
  }) {
    final radius = point.distance;
    final r = radius / boardRadius;
    if (r > 1 || !r.isFinite) {
      return const WindDartsImpact(
        score: 0,
        sector: null,
        multiplier: 0,
        kind: WindDartsImpactKind.miss,
      );
    }
    if (r <= 15.9 / 170) {
      return const WindDartsImpact(
        score: 50,
        sector: 25,
        multiplier: 2,
        kind: WindDartsImpactKind.doubleBull,
      );
    }

    final localAngle =
        (atan2(point.dy, point.dx) - boardAngle + pi / 2) % (2 * pi);
    final normalized = localAngle < 0 ? localAngle + 2 * pi : localAngle;
    final sector = sectorOrder[(normalized / (2 * pi / 20)).floor() % 20];
    final multiplier =
        r >= doubleInnerRadiusRatio && r <= doubleOuterRadiusRatio
        ? 2
        : r >= tripleInnerRadiusRatio && r <= tripleOuterRadiusRatio
        ? 3
        : 1;
    final kind = switch (multiplier) {
      3 => WindDartsImpactKind.triple,
      2 => WindDartsImpactKind.double,
      _ => WindDartsImpactKind.single,
    };
    return WindDartsImpact(
      score: sector * multiplier,
      sector: sector,
      multiplier: multiplier,
      kind: kind,
    );
  }

  static int rankingScore(int points) => points.clamp(0, shotCount * 60);

  static String formatScore(int points) =>
      '${points.clamp(0, shotCount * 60)}점';
}
