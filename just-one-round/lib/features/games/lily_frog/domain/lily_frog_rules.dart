import 'dart:math';

abstract final class LilyFrogRules {
  static const rulesVersion = 5;
  static const gameDuration = Duration(seconds: 150);
  static const maximumSubmittedScore = 200000;
  static const safeOpeningSeconds = 3.0;
  static const launchSpeed = 260.0;
  static const maximumFlightSeconds = 0.88;
  static const landingGrace = 10.0;
  static const landingLockSeconds = 0.0;
  static const minimumSafeWindowSeconds = 0.24;
  static const minimumRiskWindowSeconds = 0.12;
  static const baseLandingScore = 300;
  static const comboScore = 10;
  static const riskyLandingBonus = 100;
  static const flyScore = 100;
  static const goldenLandingBonus = 700;
  static const goldenBranchInterval = 5;
  static const goldenLilyDiameter = 104.0;
  static const normalRouteFlyChance = 0.50;
  static const prebuiltSafeLookahead = 4;
  static const flyCollectEffectSeconds = 0.28;
  static const trajectoryGuideLaunches = 3;
  static const flyPickupRadius = 16.0;
  static const minimumPadEdgeGap = landingGrace * 2;

  static const lilyDiameters = <double>[128, 160, 176, 192, 208];

  /// Linearly interpolates the requested 20-second speed milestones.
  /// Orbit angle and combo expiry both use this same angular speed.
  static double angularSpeedAt(double elapsedSeconds) {
    const milestones = <double>[1.35, 1.70, 2.10, 2.30, 2.50, 2.60, 2.70, 2.80];
    final seconds = elapsedSeconds.clamp(0.0, 140.0).toDouble();
    final segment = seconds ~/ 20;
    if (segment >= milestones.length - 1) return milestones.last;
    final fraction = (seconds - segment * 20) / 20;
    return milestones[segment] +
        (milestones[segment + 1] - milestones[segment]) * fraction;
  }

  static LilyFrogDifficulty difficultyAt(double elapsedSeconds) {
    final angularSpeed = angularSpeedAt(elapsedSeconds);
    if (elapsedSeconds >= 110) {
      return LilyFrogDifficulty(
        angularSpeed: angularSpeed,
        minimumDiameter: 160,
        maximumDiameter: 176,
        minimumGap: 196,
        maximumGap: 224,
        riskyChance: 0.72,
      );
    }
    if (elapsedSeconds >= 90) {
      return LilyFrogDifficulty(
        angularSpeed: angularSpeed,
        minimumDiameter: 160,
        maximumDiameter: 176,
        minimumGap: 194,
        maximumGap: 222,
        riskyChance: 0.62,
      );
    }
    if (elapsedSeconds >= 50) {
      return LilyFrogDifficulty(
        angularSpeed: angularSpeed,
        minimumDiameter: 176,
        maximumDiameter: 192,
        minimumGap: 196,
        maximumGap: 224,
        riskyChance: 0.48,
      );
    }
    if (elapsedSeconds >= 30) {
      return LilyFrogDifficulty(
        angularSpeed: angularSpeed,
        minimumDiameter: 176,
        maximumDiameter: 208,
        minimumGap: 202,
        maximumGap: 228,
        riskyChance: 0.32,
      );
    }
    return LilyFrogDifficulty(
      angularSpeed: angularSpeed,
      minimumDiameter: 192,
      maximumDiameter: 208,
      minimumGap: 212,
      maximumGap: 228,
      riskyChance: 0.12,
    );
  }

  static Point<double> tangentDirection({
    required double theta,
    required bool clockwise,
  }) {
    final direction = Point<double>(-sin(theta), cos(theta));
    return clockwise ? Point<double>(-direction.x, -direction.y) : direction;
  }

  /// Returns whether a tangent launch from the given orbit position reaches
  /// the target during the normal flight window.
  static bool tangentLaunchHits({
    required Point<double> fromCenter,
    required double orbitRadius,
    required bool clockwise,
    required double theta,
    required Point<double> targetCenter,
    required double targetLandingRadius,
    double minimumT = 0.04,
  }) {
    final start = orbitPosition(
      center: fromCenter,
      radius: orbitRadius,
      theta: theta,
    );
    final direction = tangentDirection(theta: theta, clockwise: clockwise);
    final travel = launchSpeed * maximumFlightSeconds;
    final end = Point<double>(
      start.x + direction.x * travel,
      start.y + direction.y * travel,
    );
    return firstSegmentCircleHit(
          start: start,
          end: end,
          center: targetCenter,
          radius: targetLandingRadius,
          minimumT: minimumT,
        ) !=
        null;
  }

  /// Returns the landing point of the cleanest legal tangent route found by
  /// the deterministic launch sampler. This is used while a pad is being
  /// prepared, so its future rotation can be chosen before the player lands
  /// on it.
  static Point<double>? bestTangentLandingPoint({
    required Point<double> fromCenter,
    required double orbitRadius,
    required bool clockwise,
    required Point<double> targetCenter,
    required double targetLandingRadius,
    int sampleCount = 720,
  }) {
    if (sampleCount <= 0) return null;
    final travel = launchSpeed * maximumFlightSeconds;
    Point<double>? bestLandingPoint;
    var bestMiss = double.infinity;
    for (var index = 0; index < sampleCount; index++) {
      final theta = 2 * pi * index / sampleCount;
      final start = orbitPosition(
        center: fromCenter,
        radius: orbitRadius,
        theta: theta,
      );
      final direction = tangentDirection(theta: theta, clockwise: clockwise);
      final toTarget = Point<double>(
        targetCenter.x - start.x,
        targetCenter.y - start.y,
      );
      final projection = toTarget.x * direction.x + toTarget.y * direction.y;
      if (projection <= 0) continue;
      final missX = toTarget.x - direction.x * projection;
      final missY = toTarget.y - direction.y * projection;
      final miss = sqrt(missX * missX + missY * missY);
      if (miss > targetLandingRadius * 0.75 || miss >= bestMiss) {
        continue;
      }
      final end = Point<double>(
        start.x + direction.x * travel,
        start.y + direction.y * travel,
      );
      final landingT = firstSegmentCircleHit(
        start: start,
        end: end,
        center: targetCenter,
        radius: targetLandingRadius,
        minimumT: 0.04,
      );
      if (landingT == null) continue;
      bestMiss = miss;
      bestLandingPoint = Point<double>(
        start.x + (end.x - start.x) * landingT,
        start.y + (end.y - start.y) * landingT,
      );
    }
    return bestLandingPoint;
  }

  /// Measures how long a pad rotating in one direction waits before its
  /// tangent points at the next target. A full orbit is sampled so the result
  /// is deterministic and uses the same collision rule as a real launch.
  static double? nextLaunchWaitSeconds({
    required Point<double> fromCenter,
    required double orbitRadius,
    required Point<double> landingPoint,
    required bool clockwise,
    required double angularSpeed,
    required Point<double> targetCenter,
    required double targetLandingRadius,
    int sampleCount = 720,
  }) {
    if (angularSpeed <= 0 || sampleCount <= 0) return null;
    final startTheta = atan2(
      landingPoint.y - fromCenter.y,
      landingPoint.x - fromCenter.x,
    );
    final thetaStep = 2 * pi / sampleCount;
    final timeStep = thetaStep / angularSpeed;
    final direction = clockwise ? -1 : 1;
    for (var index = 0; index <= sampleCount; index++) {
      final theta = startTheta + direction * thetaStep * index;
      if (tangentLaunchHits(
        fromCenter: fromCenter,
        orbitRadius: orbitRadius,
        clockwise: clockwise,
        theta: theta,
        targetCenter: targetCenter,
        targetLandingRadius: targetLandingRadius,
      )) {
        return index * timeStep;
      }
    }
    return null;
  }

  /// Chooses the rotation direction that reaches the following jump window
  /// sooner from the expected landing point.
  static bool optimalClockwiseForNextJump({
    required Point<double> fromCenter,
    required double orbitRadius,
    required Point<double> landingPoint,
    required double angularSpeed,
    required Point<double> targetCenter,
    required double targetLandingRadius,
    required bool fallbackClockwise,
  }) {
    final counterClockwiseWait = nextLaunchWaitSeconds(
      fromCenter: fromCenter,
      orbitRadius: orbitRadius,
      landingPoint: landingPoint,
      clockwise: false,
      angularSpeed: angularSpeed,
      targetCenter: targetCenter,
      targetLandingRadius: targetLandingRadius,
    );
    final clockwiseWait = nextLaunchWaitSeconds(
      fromCenter: fromCenter,
      orbitRadius: orbitRadius,
      landingPoint: landingPoint,
      clockwise: true,
      angularSpeed: angularSpeed,
      targetCenter: targetCenter,
      targetLandingRadius: targetLandingRadius,
    );
    if (counterClockwiseWait == null && clockwiseWait == null) {
      return fallbackClockwise;
    }
    if (counterClockwiseWait == null) return true;
    if (clockwiseWait == null) return false;
    if ((counterClockwiseWait - clockwiseWait).abs() <= 1e-9) {
      return fallbackClockwise;
    }
    return clockwiseWait < counterClockwiseWait;
  }

  static Point<double> orbitPosition({
    required Point<double> center,
    required double radius,
    required double theta,
  }) => Point<double>(
    center.x + cos(theta) * radius,
    center.y + sin(theta) * radius,
  );

  static double? firstSegmentCircleHit({
    required Point<double> start,
    required Point<double> end,
    required Point<double> center,
    required double radius,
    double minimumT = 0,
  }) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final fx = start.x - center.x;
    final fy = start.y - center.y;
    final a = dx * dx + dy * dy;
    if (a <= 1e-9) return null;
    final b = 2 * (fx * dx + fy * dy);
    final c = fx * fx + fy * fy - radius * radius;
    final discriminant = b * b - 4 * a * c;
    final grazingTolerance = 1e-9 * a * max(1.0, radius * radius);
    if (discriminant < -grazingTolerance) return null;
    final root = sqrt(max(0, discriminant));
    final t1 = (-b - root) / (2 * a);
    final t2 = (-b + root) / (2 * a);
    for (final t in [t1, t2]) {
      if (t >= minimumT && t <= 1) return t;
    }
    return null;
  }

  static int landingScore({
    required bool risky,
    required bool caughtFly,
    bool golden = false,
    int combo = 1,
  }) {
    final effectiveCombo = combo < 1 ? 1 : combo;
    return baseLandingScore +
        (risky && !golden ? riskyLandingBonus : 0) +
        (golden ? goldenLandingBonus : 0) +
        effectiveCombo * comboScore +
        (caughtFly ? flyScore : 0);
  }

  static int clampSubmittedScore(int score) =>
      score.clamp(0, maximumSubmittedScore);

  static String formatScore(int score) => '${_withThousands(score)}점';

  static String formatHudScore(int score) => _withThousands(score);

  static String _withThousands(int value) {
    final digits = value.clamp(0, maximumSubmittedScore).toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }
}

class LilyFrogDifficulty {
  const LilyFrogDifficulty({
    required this.angularSpeed,
    required this.minimumDiameter,
    required this.maximumDiameter,
    required this.minimumGap,
    required this.maximumGap,
    required this.riskyChance,
  });

  final double angularSpeed;
  final double minimumDiameter;
  final double maximumDiameter;
  final double minimumGap;
  final double maximumGap;
  final double riskyChance;
}
