import 'dart:math';

import 'package:just_one_round/features/games/lily_frog/domain/lily_frog_rules.dart';

class LilyPadSpec {
  const LilyPadSpec({
    required this.id,
    required this.center,
    required this.diameter,
    required this.clockwise,
    required this.angularSpeed,
    required this.variant,
    required this.risky,
    required this.progressIndex,
    this.golden = false,
    this.expectedLandingPoint,
  });

  final int id;
  final Point<double> center;
  final double diameter;
  final bool clockwise;
  final double angularSpeed;
  final int variant;
  final bool risky;
  final int progressIndex;
  final bool golden;
  final Point<double>? expectedLandingPoint;

  double get landingRadius => diameter / 2 + LilyFrogRules.landingGrace;
  double get orbitRadius => diameter / 2;

  LilyPadSpec copyWith({
    Point<double>? center,
    bool? clockwise,
    double? angularSpeed,
    Point<double>? expectedLandingPoint,
  }) => LilyPadSpec(
    id: id,
    center: center ?? this.center,
    diameter: diameter,
    clockwise: clockwise ?? this.clockwise,
    angularSpeed: angularSpeed ?? this.angularSpeed,
    variant: variant,
    risky: risky,
    progressIndex: progressIndex,
    golden: golden,
    expectedLandingPoint: expectedLandingPoint ?? this.expectedLandingPoint,
  );
}

class LilyGeneration {
  const LilyGeneration({
    required this.safe,
    this.preparedFromClockwise,
    this.risky,
    this.continuation,
    this.flies = const [],
  });

  final LilyPadSpec safe;
  final bool? preparedFromClockwise;
  final LilyPadSpec? risky;
  final LilyPadSpec? continuation;
  final List<FlySpec> flies;
  FlySpec? get fly => flies.isEmpty ? null : flies.first;

  Iterable<LilyPadSpec> get pads sync* {
    yield safe;
    if (risky case final risky?) yield risky;
    if (continuation case final continuation?) yield continuation;
  }
}

class FlySpec {
  const FlySpec({required this.id, required this.center, required this.padId});

  final int id;
  final Point<double> center;
  final int padId;
}

class LilyFieldGenerator {
  LilyFieldGenerator(Random random) : _random = random;

  static const worldLeft = 8.0;
  static const worldRight = 352.0;
  static const _sampleCount = 720;

  final Random _random;

  LilyGeneration generate({
    required LilyPadSpec from,
    required int nextPadId,
    required int nextFlyId,
    required double elapsedSeconds,
    required Iterable<LilyPadSpec> existing,
  }) {
    final difficulty = LilyFrogRules.difficultyAt(elapsedSeconds);
    final occupied = existing.toList(growable: false);
    final offersGolden =
        (from.progressIndex + 1) % LilyFrogRules.goldenBranchInterval == 0;
    LilyPadSpec? safe;
    LilyPadSpec? safeFallback;
    LilyPadSpec? golden;
    LilyPadSpec? continuation;
    for (var pairAttempt = 0; pairAttempt < 32; pairAttempt++) {
      final safeCandidate = _findPad(
        from: from,
        id: nextPadId,
        progressIndex: from.progressIndex + 1,
        difficulty: difficulty,
        existing: occupied,
        risky: false,
      );
      safeFallback = safeCandidate;
      if (!offersGolden) {
        safe = safeCandidate;
        break;
      }
      final goldenCandidate = _tryFindGoldenPad(
        from: from,
        id: nextPadId + 1,
        progressIndex: safeCandidate.progressIndex,
        difficulty: difficulty,
        existing: [...occupied, safeCandidate],
      );
      if (goldenCandidate != null) {
        final continuationCandidate = _tryFindSharedContinuation(
          safe: safeCandidate,
          golden: goldenCandidate,
          id: nextPadId + 2,
          difficulty: difficulty,
          existing: [...occupied, safeCandidate, goldenCandidate],
        );
        if (continuationCandidate != null) {
          safe = safeCandidate;
          golden = goldenCandidate;
          continuation = continuationCandidate;
          break;
        }
      }
    }
    // A crowded look-ahead can make the optional golden fork impossible even
    // though the normal route is still legal. Never let that bonus layout
    // failure stop the real game (or its live home preview); keep the last
    // verified normal pad and offer the next golden fork five landings later.
    if (safe == null && safeFallback != null) {
      safe = safeFallback;
      golden = null;
      continuation = null;
    }
    if (safe == null) {
      throw StateError('Unable to place a reachable lily pad');
    }
    final preparedFromClockwise = LilyFrogRules.optimalClockwiseForNextJump(
      fromCenter: from.center,
      orbitRadius: from.orbitRadius,
      landingPoint:
          from.expectedLandingPoint ??
          LilyFrogRules.orbitPosition(
            center: from.center,
            radius: from.orbitRadius,
            theta: -pi / 2,
          ),
      angularSpeed: difficulty.angularSpeed,
      targetCenter: safe.center,
      targetLandingRadius: safe.landingRadius,
      fallbackClockwise: from.clockwise,
    );
    final preparedFrom = from.copyWith(
      clockwise: preparedFromClockwise,
      angularSpeed: difficulty.angularSpeed,
    );
    safe = safe.copyWith(
      expectedLandingPoint: _expectedLandingPoint(
        from: preparedFrom,
        target: safe,
      ),
    );
    if (golden case final goldenPad?) {
      golden = goldenPad.copyWith(
        expectedLandingPoint: _expectedLandingPoint(
          from: preparedFrom,
          target: goldenPad,
        ),
      );
    }
    if (continuation case final continuationPad?) {
      safe = _preparePadRotation(
        pad: safe,
        target: continuationPad,
        angularSpeed: difficulty.angularSpeed,
      );
      if (golden case final goldenPad?) {
        golden = _preparePadRotation(
          pad: goldenPad,
          target: continuationPad,
          angularSpeed: difficulty.angularSpeed,
        );
      }
      continuation = continuationPad.copyWith(
        expectedLandingPoint: _expectedLandingPoint(
          from: safe,
          target: continuationPad,
        ),
      );
    }
    final flies =
        !offersGolden &&
            _random.nextDouble() < LilyFrogRules.normalRouteFlyChance
        ? _fliesOnBestRoute(
            from: preparedFrom,
            target: safe,
            firstId: nextFlyId,
          )
        : const <FlySpec>[];
    return LilyGeneration(
      safe: safe,
      preparedFromClockwise: preparedFromClockwise,
      risky: golden,
      continuation: continuation,
      flies: flies,
    );
  }

  LilyPadSpec? _tryFindSharedContinuation({
    required LilyPadSpec safe,
    required LilyPadSpec golden,
    required int id,
    required LilyFrogDifficulty difficulty,
    required List<LilyPadSpec> existing,
  }) {
    const diameter = 160.0;
    LilyPadSpec candidateAt(double x, double y) => LilyPadSpec(
      id: id,
      center: Point<double>(x, y),
      diameter: diameter,
      clockwise: _random.nextBool(),
      angularSpeed: difficulty.angularSpeed,
      variant: _random.nextInt(3),
      risky: false,
      progressIndex: safe.progressIndex + 1,
    );

    bool isSharedLegal(LilyPadSpec candidate) =>
        _isLegal(
          from: safe,
          candidate: candidate,
          existing: existing,
          minimumWindowSeconds: LilyFrogRules.minimumSafeWindowSeconds,
        ) &&
        _isLegal(
          from: golden,
          candidate: candidate,
          existing: existing,
          minimumWindowSeconds: LilyFrogRules.minimumRiskWindowSeconds,
        );

    final midpointX = (safe.center.x + golden.center.x) / 2;
    final topY = min(safe.center.y, golden.center.y);
    for (var attempt = 0; attempt < 160; attempt++) {
      final x = (midpointX + _between(-88, 88)).clamp(88.0, 272.0);
      final y = topY - _between(168, 224);
      final candidate = candidateAt(x, y);
      if (isSharedLegal(candidate)) return candidate;
    }
    for (final yOffset in [168.0, 180.0, 192.0, 204.0, 216.0, 224.0]) {
      for (var x = 88.0; x <= 272.0; x += 4) {
        final candidate = candidateAt(x, topY - yOffset);
        if (isSharedLegal(candidate)) return candidate;
      }
    }
    return null;
  }

  LilyPadSpec _findPad({
    required LilyPadSpec from,
    required int id,
    required int progressIndex,
    required LilyFrogDifficulty difficulty,
    required List<LilyPadSpec> existing,
    required bool risky,
  }) {
    for (var attempt = 0; attempt < 80; attempt++) {
      final diameter = _diameterFor(difficulty, risky: risky);
      final clearanceDistance =
          (from.diameter + diameter) / 2 + LilyFrogRules.minimumPadEdgeGap;
      final configuredMinimum = risky
          ? max(206.0, difficulty.minimumGap + 8.0)
          : difficulty.minimumGap;
      final configuredMaximum = risky ? 232.0 : difficulty.maximumGap;
      final minimumDistance = max(configuredMinimum, clearanceDistance);
      if (minimumDistance > configuredMaximum) continue;
      final distance = _between(minimumDistance, configuredMaximum);
      final angle = -pi * (0.18 + _random.nextDouble() * 0.64);
      final center = Point<double>(
        from.center.x + cos(angle) * distance,
        from.center.y + sin(angle) * distance,
      );
      if (attempt < 48 && (center.x - from.center.x).abs() < 60) {
        continue;
      }
      final candidate = LilyPadSpec(
        id: id,
        center: center,
        diameter: diameter,
        clockwise: _random.nextBool(),
        angularSpeed: difficulty.angularSpeed,
        variant: _random.nextInt(3),
        risky: risky,
        progressIndex: progressIndex,
      );
      final minimumWindow = risky
          ? LilyFrogRules.minimumRiskWindowSeconds
          : LilyFrogRules.minimumSafeWindowSeconds;
      if (_isLegal(
        from: from,
        candidate: candidate,
        existing: existing,
        minimumWindowSeconds: minimumWindow,
      )) {
        return candidate;
      }
    }
    return _fallbackPad(
      from: from,
      id: id,
      progressIndex: progressIndex,
      difficulty: difficulty,
      existing: existing,
    );
  }

  LilyPadSpec? _tryFindGoldenPad({
    required LilyPadSpec from,
    required int id,
    required int progressIndex,
    required LilyFrogDifficulty difficulty,
    required List<LilyPadSpec> existing,
  }) {
    const diameter = LilyFrogRules.goldenLilyDiameter;
    for (var attempt = 0; attempt < 96; attempt++) {
      final minimumDistance = max(
        max(206.0, difficulty.minimumGap + 8.0),
        (from.diameter + diameter) / 2 + LilyFrogRules.minimumPadEdgeGap,
      );
      if (minimumDistance > 232) continue;
      final distance = _between(minimumDistance, 232.0);
      final angle = -pi * (0.18 + _random.nextDouble() * 0.64);
      final candidate = LilyPadSpec(
        id: id,
        center: Point<double>(
          from.center.x + cos(angle) * distance,
          from.center.y + sin(angle) * distance,
        ),
        diameter: diameter,
        clockwise: _random.nextBool(),
        angularSpeed: difficulty.angularSpeed,
        variant: _random.nextInt(3),
        risky: true,
        progressIndex: progressIndex,
        golden: true,
      );
      if (_isLegal(
        from: from,
        candidate: candidate,
        existing: existing,
        minimumWindowSeconds: LilyFrogRules.minimumRiskWindowSeconds,
      )) {
        return candidate;
      }
    }
    for (final distance in [206.0, 214.0, 222.0, 230.0]) {
      for (var index = 0; index < _sampleCount; index++) {
        final angle = -pi * (0.12 + 0.76 * index / (_sampleCount - 1));
        final candidate = LilyPadSpec(
          id: id,
          center: Point<double>(
            from.center.x + cos(angle) * distance,
            from.center.y + sin(angle) * distance,
          ),
          diameter: diameter,
          clockwise: progressIndex.isEven,
          angularSpeed: difficulty.angularSpeed,
          variant: progressIndex % 3,
          risky: true,
          progressIndex: progressIndex,
          golden: true,
        );
        if (_isLegal(
          from: from,
          candidate: candidate,
          existing: existing,
          minimumWindowSeconds: LilyFrogRules.minimumRiskWindowSeconds,
        )) {
          return candidate;
        }
      }
    }
    return null;
  }

  LilyPadSpec _fallbackPad({
    required LilyPadSpec from,
    required int id,
    required int progressIndex,
    required LilyFrogDifficulty difficulty,
    required List<LilyPadSpec> existing,
  }) {
    const angles = [-pi / 2, -1.25, -1.89, -0.93, -2.21, -0.61, -2.53];
    for (final diameter in [208.0, 192.0, 176.0, 160.0]) {
      final minimumDistance =
          (from.diameter + diameter) / 2 + LilyFrogRules.minimumPadEdgeGap;
      for (final distance in [minimumDistance, 224.0, 232.0, 240.0]) {
        if (distance < minimumDistance) continue;
        for (final angle in angles) {
          final x = (from.center.x + cos(angle) * distance).clamp(
            worldLeft,
            worldRight,
          );
          final candidate = LilyPadSpec(
            id: id,
            center: Point<double>(x, from.center.y + sin(angle) * distance),
            diameter: diameter,
            clockwise: progressIndex.isEven,
            angularSpeed: difficulty.angularSpeed,
            variant: progressIndex % 3,
            risky: false,
            progressIndex: progressIndex,
          );
          if (_isLegal(
            from: from,
            candidate: candidate,
            existing: existing,
            minimumWindowSeconds: LilyFrogRules.minimumSafeWindowSeconds,
          )) {
            return candidate;
          }
        }
      }
    }
    throw StateError(
      'Unable to place a reachable lily pad with the required edge clearance',
    );
  }

  bool _isLegal({
    required LilyPadSpec from,
    required LilyPadSpec candidate,
    required List<LilyPadSpec> existing,
    required double minimumWindowSeconds,
  }) {
    if (candidate.center.x - candidate.diameter / 2 < worldLeft ||
        candidate.center.x + candidate.diameter / 2 > worldRight) {
      return false;
    }
    for (final other in existing) {
      final minimumDistance =
          candidate.diameter / 2 +
          other.diameter / 2 +
          LilyFrogRules.minimumPadEdgeGap;
      if (_distance(candidate.center, other.center) < minimumDistance) {
        return false;
      }
    }
    return reachableWindowSeconds(from: from, target: candidate) >=
        minimumWindowSeconds;
  }

  double reachableWindowSeconds({
    required LilyPadSpec from,
    required LilyPadSpec target,
  }) {
    var longestRun = 0;
    var currentRun = 0;
    final hits = List<bool>.filled(_sampleCount, false);
    for (var index = 0; index < _sampleCount; index++) {
      final theta = 2 * pi * index / _sampleCount;
      hits[index] = _launchHits(from: from, target: target, theta: theta);
    }
    for (var index = 0; index < _sampleCount * 2; index++) {
      if (hits[index % _sampleCount]) {
        currentRun++;
        longestRun = max(longestRun, currentRun);
      } else {
        currentRun = 0;
      }
      if (longestRun >= _sampleCount) break;
    }
    longestRun = min(longestRun, _sampleCount);
    final angularWindow = longestRun * 2 * pi / _sampleCount;
    return angularWindow / from.angularSpeed;
  }

  bool _launchHits({
    required LilyPadSpec from,
    required LilyPadSpec target,
    required double theta,
  }) => LilyFrogRules.tangentLaunchHits(
    fromCenter: from.center,
    orbitRadius: from.orbitRadius,
    clockwise: from.clockwise,
    theta: theta,
    targetCenter: target.center,
    targetLandingRadius: target.landingRadius,
  );

  Point<double> _expectedLandingPoint({
    required LilyPadSpec from,
    required LilyPadSpec target,
  }) =>
      LilyFrogRules.bestTangentLandingPoint(
        fromCenter: from.center,
        orbitRadius: from.orbitRadius,
        clockwise: from.clockwise,
        targetCenter: target.center,
        targetLandingRadius: target.landingRadius,
      ) ??
      LilyFrogRules.orbitPosition(
        center: target.center,
        radius: target.orbitRadius,
        theta: -pi / 2,
      );

  LilyPadSpec _preparePadRotation({
    required LilyPadSpec pad,
    required LilyPadSpec target,
    required double angularSpeed,
  }) => pad.copyWith(
    clockwise: LilyFrogRules.optimalClockwiseForNextJump(
      fromCenter: pad.center,
      orbitRadius: pad.orbitRadius,
      landingPoint:
          pad.expectedLandingPoint ??
          LilyFrogRules.orbitPosition(
            center: pad.center,
            radius: pad.orbitRadius,
            theta: -pi / 2,
          ),
      angularSpeed: angularSpeed,
      targetCenter: target.center,
      targetLandingRadius: target.landingRadius,
      fallbackClockwise: pad.clockwise,
    ),
  );

  List<FlySpec> _fliesOnBestRoute({
    required LilyPadSpec from,
    required LilyPadSpec target,
    required int firstId,
  }) {
    final expectedLandingPoint =
        from.expectedLandingPoint ??
        LilyFrogRules.orbitPosition(
          center: from.center,
          radius: from.orbitRadius,
          theta: -pi / 2,
        );
    final startTheta = atan2(
      expectedLandingPoint.y - from.center.y,
      expectedLandingPoint.x - from.center.x,
    );
    final rotationDirection = from.clockwise ? -1 : 1;
    final thetaStep = 2 * pi / _sampleCount;
    int? firstWindowStart;
    int? firstWindowEnd;
    for (var index = 0; index <= _sampleCount; index++) {
      final theta = startTheta + rotationDirection * thetaStep * index;
      final hitsTarget = _launchHits(from: from, target: target, theta: theta);
      if (hitsTarget) {
        firstWindowStart ??= index;
        firstWindowEnd = index;
      } else if (firstWindowStart != null) {
        break;
      }
    }
    if (firstWindowStart == null || firstWindowEnd == null) return const [];
    final bestTheta =
        startTheta +
        rotationDirection *
            thetaStep *
            (firstWindowStart + (firstWindowEnd - firstWindowStart) / 2);
    final start = LilyFrogRules.orbitPosition(
      center: from.center,
      radius: from.orbitRadius,
      theta: bestTheta,
    );
    final direction = LilyFrogRules.tangentDirection(
      theta: bestTheta,
      clockwise: from.clockwise,
    );
    final travel =
        LilyFrogRules.launchSpeed * LilyFrogRules.maximumFlightSeconds;
    final maximumEnd = Point<double>(
      start.x + direction.x * travel,
      start.y + direction.y * travel,
    );
    final landingT = LilyFrogRules.firstSegmentCircleHit(
      start: start,
      end: maximumEnd,
      center: target.center,
      radius: target.landingRadius,
      minimumT: 0.04,
    );
    if (landingT == null) return const [];
    final landingDistance = travel * landingT;
    final count = 2 + _random.nextInt(2);
    final flies = [
      for (var index = 0; index < count; index++)
        FlySpec(
          id: firstId + index,
          padId: target.id,
          center: Point<double>(
            start.x + direction.x * landingDistance * (0.32 + index * 0.20),
            start.y + direction.y * landingDistance * (0.32 + index * 0.20),
          ),
        ),
    ];
    final landingEnd = Point<double>(
      start.x + (maximumEnd.x - start.x) * landingT,
      start.y + (maximumEnd.y - start.y) * landingT,
    );
    if (!flies.every(
      (fly) =>
          LilyFrogRules.firstSegmentCircleHit(
            start: start,
            end: landingEnd,
            center: fly.center,
            radius: LilyFrogRules.flyPickupRadius,
          ) !=
          null,
    )) {
      return const [];
    }
    return flies;
  }

  double _diameterFor(LilyFrogDifficulty difficulty, {required bool risky}) {
    final allowed = LilyFrogRules.lilyDiameters.where((diameter) {
      if (risky) return diameter == LilyFrogRules.goldenLilyDiameter;
      return diameter >= difficulty.minimumDiameter &&
          diameter <= difficulty.maximumDiameter;
    }).toList();
    if (allowed.isEmpty) {
      return risky ? LilyFrogRules.goldenLilyDiameter : 208;
    }
    return allowed[_random.nextInt(allowed.length)];
  }

  double _between(double minimum, double maximum) =>
      minimum + _random.nextDouble() * (maximum - minimum);

  static double _distance(Point<double> a, Point<double> b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }
}
