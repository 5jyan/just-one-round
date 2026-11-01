import 'dart:math';

/// Stable inputs understood by the Temple Run runtime.
enum TempleRunSwipe { left, right, up, down }

enum TempleRunObstacleKind { hurdle, arch, rubble, gap, narrowPath }

/// The authored width of a hazard on the three-lane road.
///
/// A single-lane obstacle is still represented by [TempleRunObstacle.lane],
/// while a full-road obstacle occupies the collision plane from edge to edge.
enum TempleRunObstacleSpan { singleLane, fullRoad }

enum TempleRunPowerUpKind { magnet, shield, boost }

enum TempleRunTurnDirection { left, right }

/// A hazard on the road. Distances are measured from the beginning of a run
/// in metres, with the runner at distance zero.
class TempleRunObstacle {
  const TempleRunObstacle({
    required this.distanceMeters,
    required this.lane,
    required this.kind,
    this.id = 0,
    this.span = TempleRunObstacleSpan.singleLane,
    this.lengthMeters = 0,
  });

  final int id;
  final double distanceMeters;
  final int lane;
  final TempleRunObstacleKind kind;
  final TempleRunObstacleSpan span;

  /// Only [TempleRunObstacleKind.narrowPath] occupies a longitudinal interval.
  /// Other hazards use the shared collision window around their authored point.
  final double lengthMeters;

  bool get spansFullRoad => span == TempleRunObstacleSpan.fullRoad;
  bool get isNarrowPath => kind == TempleRunObstacleKind.narrowPath;

  double get occupiedLengthMeters => isNarrowPath
      ? max(
          0.0,
          lengthMeters > 0
              ? lengthMeters
              : TempleRunRules.narrowPathHalfLengthMeters,
        )
      : 0.0;

  double get endDistanceMeters => distanceMeters + occupiedLengthMeters;

  /// Width in logical lane units. The runner's position uses the same scale:
  /// 0 is the left lane centre and 2 is the right lane centre.
  double get widthInLanes => spansFullRoad
      ? TempleRunRules.laneCount.toDouble()
      : isNarrowPath
      ? TempleRunRules.narrowPathSafeWidthInLanes
      : TempleRunRules.singleLaneObstacleWidthInLanes;

  /// Returns whether the runner's continuous centre position is unsafe.
  /// Narrow paths invert the usual meaning: their authored lane is the safe
  /// strip and every other position is a terrain failure.
  bool blocksPosition(double positionInLanes) {
    if (isNarrowPath) {
      return (positionInLanes - lane).abs() >
          TempleRunRules.narrowPathSafeHalfWidthInLanes +
              TempleRunRules.narrowPathLateralEpsilon +
              1e-9;
    }
    if (spansFullRoad) return true;
    return (positionInLanes - lane).abs() <=
        widthInLanes / 2 + TempleRunRules.runnerHalfWidthInLanes;
  }

  bool get isJumpable =>
      kind == TempleRunObstacleKind.hurdle || kind == TempleRunObstacleKind.gap;

  /// Narrow terrain is not a solid hit: a shield cannot save the wrong lane.
  bool get isSolid => kind != TempleRunObstacleKind.gap && !isNarrowPath;

  @override
  bool operator ==(Object other) =>
      other is TempleRunObstacle &&
      id == other.id &&
      distanceMeters == other.distanceMeters &&
      lane == other.lane &&
      kind == other.kind &&
      span == other.span &&
      lengthMeters == other.lengthMeters;

  @override
  int get hashCode =>
      Object.hash(id, distanceMeters, lane, kind, span, lengthMeters);
}

class TempleRunCoin {
  const TempleRunCoin({required this.distanceMeters, required this.lane});

  final double distanceMeters;
  final int lane;
}

class TempleRunPowerUp {
  const TempleRunPowerUp({
    required this.distanceMeters,
    required this.lane,
    required this.kind,
  });

  final double distanceMeters;
  final int lane;
  final TempleRunPowerUpKind kind;
}

/// A required 90 degree bend. A swipe during the inclusive window commits the
/// turn. The window reserves the upcoming junction early, while execution is
/// always delayed until [distanceMeters] so the camera and route stay aligned.
class TempleRunTurn {
  const TempleRunTurn({
    required this.distanceMeters,
    required this.direction,
    required this.windowStartMeters,
    required this.windowEndMeters,
  });

  final double distanceMeters;
  final TempleRunTurnDirection direction;
  final double windowStartMeters;
  final double windowEndMeters;

  bool contains(double runnerDistanceMeters) =>
      runnerDistanceMeters >= windowStartMeters &&
      runnerDistanceMeters <= windowEndMeters;

  @override
  bool operator ==(Object other) =>
      other is TempleRunTurn &&
      distanceMeters == other.distanceMeters &&
      direction == other.direction &&
      windowStartMeters == other.windowStartMeters &&
      windowEndMeters == other.windowEndMeters;

  @override
  int get hashCode => Object.hash(
    distanceMeters,
    direction,
    windowStartMeters,
    windowEndMeters,
  );
}

/// The deterministic, prebuilt route for a run.
class TempleRunCourse {
  TempleRunCourse({
    required Iterable<TempleRunObstacle> obstacles,
    required Iterable<TempleRunCoin> coins,
    required Iterable<TempleRunPowerUp> powerUps,
    required Iterable<TempleRunTurn> turns,
    required this.totalDistanceMeters,
  }) : obstacles = List.unmodifiable(obstacles),
       coins = List.unmodifiable(coins),
       powerUps = List.unmodifiable(powerUps),
       turns = List.unmodifiable(turns);

  final List<TempleRunObstacle> obstacles;
  final List<TempleRunCoin> coins;
  final List<TempleRunPowerUp> powerUps;
  final List<TempleRunTurn> turns;
  final double totalDistanceMeters;

  bool get isReachable => TempleRunRules.hasReachableSafeContinuation(this);
}

/// Difficulty, score, gesture, movement, and generation rules for 집에 좀 가자.
///
/// All values that affect fairness live here so the Flame adapter can remain a
/// thin input/rendering shell and server-side score validation can mirror the
/// same bounded contract.
abstract final class TempleRunRules {
  static const gameId = 'temple_run';
  static const rulesVersion = 1;
  static const title = '집에 좀 가자';

  static const logicalWidth = 360.0;
  static const logicalHeight = 640.0;
  static const laneCount = 3;
  static const firstLane = 0;
  static const centerLane = 1;
  static const lastLane = laneCount - 1;
  static const singleLaneObstacleWidthInLanes = 0.72;
  static const runnerHalfWidthInLanes = 0.14;
  static const pickupHalfWidthInLanes = 0.38;
  static const fullRoadGapWidthMeters = 5.5;

  static const gameDuration = Duration(seconds: 300);
  static const maximumDuration = Duration(seconds: 300);
  static const countdownDuration = Duration(seconds: 3);
  static const maximumSubmittedScore = 100000;
  static const maximumCoinsPerRun = 1000;
  static const coinLineCadenceSeconds = 3.5;
  static const powerUpCadenceSeconds = 30.0;

  static const swipeThreshold = 20.0;
  static const jumpDurationSeconds = 0.78;
  static const slideDurationSeconds = 0.72;
  static const verticalInputBufferSeconds = 0.30;
  static const collisionWindowMeters = 0.85;
  static const powerUpPickupWindowMeters = 1.65;
  static const coinPickupWindowMeters = 1.65;
  static const magnetDurationSeconds = 7.0;
  static const boostDurationSeconds = 2.8;
  static const boostSpeedMultiplier = 1.32;

  /// The late-game cap is intentionally higher than the first pass so the
  /// route keeps accelerating all the way to the finish.  The 300 second
  /// distance curve (including the three scheduled boosts) still stays below
  /// the server's conservative 24m/s distance envelope.
  static const maximumSpeedMetersPerSecond = 42.0;
  static const maximumBoostedSpeedMetersPerSecond =
      maximumSpeedMetersPerSecond * boostSpeedMultiplier;

  /// Horizontal corner gestures reserve the junction for three seconds.
  static const mandatoryTurnLeadSeconds = 3.0;
  static const mandatoryTurnTailSeconds = 0.45;

  /// A committed corner is one short, shared animation used by the runtime
  /// camera, runner basis, road, and facade projection. Keeping this in the
  /// rules prevents the game and renderer from drifting back to separate
  /// chase durations.
  static const turnAnimationDurationSeconds = 0.18;
  static const turnAnimationDuration = Duration(milliseconds: 180);
  static const turnAngleRadians = pi / 2;

  /// The camera can normally sit six metres behind the runner. At a corner it
  /// temporarily shortens its boom so the outer facade, including its relief,
  /// stays outside the sightline with the required clearance.
  static const cameraBoomMaxMeters = 6.0;
  static const cameraCornerClearanceMeters = 0.35;
  static const maximumFacadeReliefDepthMeters = 0.50;

  /// The road uses a continuous 0..2 lateral coordinate. The filter is kept
  /// separate from the hard speed cap so a physical tilt cannot teleport.
  /// Narrow terrain now uses two short construction squeezes. The old 6m
  /// value is retained only as a provenance/reference constant for legacy
  /// hand-authored fixtures; generated routes never emit it.
  static const narrowPathReferenceLengthMeters = 6.0;
  static const narrowPathQuarterLengthMeters =
      narrowPathReferenceLengthMeters / 4;
  static const narrowPathHalfLengthMeters = narrowPathReferenceLengthMeters / 2;

  /// @deprecated Use [narrowPathQuarterLengthMeters] or
  /// [narrowPathHalfLengthMeters]. This keeps older preview/test fixtures
  /// source-compatible while the live generator uses only the shorter forms.
  @Deprecated('Generated routes no longer use the 6m narrow-path length.')
  static const narrowPathLengthMeters = narrowPathReferenceLengthMeters;

  /// Deterministic length alternation keeps both short forms visible without
  /// making a seeded route depend on an extra random roll.
  static double narrowPathLengthForIndex(int narrowPathIndex) =>
      narrowPathIndex.isEven
      ? narrowPathHalfLengthMeters
      : narrowPathQuarterLengthMeters;
  static const narrowPathSafeWidthInLanes = 0.84;
  static const narrowPathSafeStripHalfWidthInLanes =
      narrowPathSafeWidthInLanes / 2;

  /// Centre-position tolerance after subtracting the runner's foot half width.
  static const narrowPathSafeHalfWidthInLanes =
      narrowPathSafeStripHalfWidthInLanes - runnerHalfWidthInLanes;

  /// Covers one substep of filter settling at the edge without widening the
  /// authored strip enough to permit a lane change to count as safe.
  static const narrowPathLateralEpsilon = 0.02;
  static const maximumLateralSpeedInLanesPerSecond = 4.2;
  static const tiltDeadzone = 0.85;
  static const tiltSmoothing = 0.32;
  static const tiltFullScaleAcceleration = 3.0;

  /// The grace period after a boost ends is a runtime protection window. It
  /// stays fixed even as generated route floors tighten over time.
  static const boostExitRecoverySeconds = 1.10;

  /// Event spacing tightens through the full run. Hazard floors remain long
  /// enough for a buffered jump/slide to finish, even at maximum boosted speed.
  static const _routeTimeAnchors = <double>[5, 12, 25, 45, 90, 180, 300];
  static const _actionCadenceAnchors = <double>[
    .90,
    .78,
    .68,
    .60,
    .54,
    .50,
    .46,
  ];
  static const _hazardReactionAnchors = <double>[
    .74,
    .68,
    .62,
    .57,
    .52,
    .48,
    .44,
  ];
  static const _maneuverSeparationAnchors = <double>[
    .82,
    .72,
    .62,
    .54,
    .48,
    .44,
    .42,
  ];
  static const _turnSeparationAnchors = <double>[
    2.60,
    2.35,
    2.10,
    1.85,
    1.60,
    1.40,
    1.25,
  ];

  static const openingSafeSeconds = 4.5;
  static const farClipDistanceMeters = 190.0;

  /// Normal motion reaches 42m/s. Boosted motion is bounded separately at
  /// 55.44m/s.
  static double speedForElapsed(double elapsedSeconds) {
    final seconds = elapsedSeconds.clamp(
      0.0,
      maximumDuration.inSeconds.toDouble(),
    );
    if (seconds < 30) return _lerp(8.0, 14.0, seconds / 30);
    if (seconds < 120) return _lerp(14.0, 20.0, (seconds - 30) / 90);
    if (seconds < 210) return _lerp(20.0, 27.0, (seconds - 120) / 90);
    return _lerp(27.0, maximumSpeedMetersPerSecond, (seconds - 210) / 90);
  }

  static TempleRunDifficultyStage difficultyStageAt(double elapsedSeconds) {
    final seconds = elapsedSeconds.clamp(0.0, 300.0);
    if (seconds < 45) return TempleRunDifficultyStage.learn;
    if (seconds < 120) return TempleRunDifficultyStage.establish;
    if (seconds < 210) return TempleRunDifficultyStage.combine;
    return TempleRunDifficultyStage.mastery;
  }

  /// Target time between required action events. The generator stays inside
  /// this route-time curve, then widens around corners when their safety
  /// window needs it.
  static double actionCadenceSecondsAt(double elapsedSeconds) {
    return _interpolateRouteTime(elapsedSeconds, _actionCadenceAnchors);
  }

  /// Minimum time to recover from one hazard before the next hazard can be
  /// authored. This is intentionally separate from boost exit protection.
  static double hazardReactionSecondsAt(double elapsedSeconds) =>
      _interpolateRouteTime(elapsedSeconds, _hazardReactionAnchors);

  /// Minimum time between a turn and its neighboring hazard.
  static double maneuverSeparationSecondsAt(double elapsedSeconds) =>
      _interpolateRouteTime(elapsedSeconds, _maneuverSeparationAnchors);

  /// A short extra beat after a turn lets the player reorient before the next
  /// hazard. It is deliberately shorter than the pre-turn recovery so a
  /// turn→hazard→turn chain can become a real late-run combo.
  static double postTurnObstacleSeparationSecondsAt(double elapsedSeconds) =>
      maneuverSeparationSecondsAt(elapsedSeconds) + 0.18;

  /// Minimum time between successive turn junctions before the additional
  /// reservation-window rule is applied.
  static double turnSeparationSecondsAt(double elapsedSeconds) =>
      _interpolateRouteTime(elapsedSeconds, _turnSeparationAnchors);

  static double _interpolateRouteTime(
    double elapsedSeconds,
    List<double> values,
  ) {
    if (!elapsedSeconds.isFinite || elapsedSeconds <= _routeTimeAnchors.first) {
      return values.first;
    }
    for (var index = 1; index < _routeTimeAnchors.length; index++) {
      final end = _routeTimeAnchors[index];
      if (elapsedSeconds <= end) {
        final start = _routeTimeAnchors[index - 1];
        final amount = (elapsedSeconds - start) / (end - start);
        return values[index - 1] + (values[index] - values[index - 1]) * amount;
      }
    }
    return values.last;
  }

  /// Integral of the piecewise speed curve. Keeping this exact makes score
  /// values reproducible even when frames arrive with uneven dt values.
  static double distanceForElapsed(double elapsedSeconds) {
    final seconds = elapsedSeconds.clamp(0.0, 300.0);
    if (seconds <= 30) return _integratedLinear(8.0, 14.0, seconds, 30.0);
    final first = _integratedLinear(8.0, 14.0, 30.0, 30.0);
    if (seconds <= 120) {
      return first + _integratedLinear(14.0, 20.0, seconds - 30, 90.0);
    }
    final second = _integratedLinear(14.0, 20.0, 90.0, 90.0);
    if (seconds <= 210) {
      return first +
          second +
          _integratedLinear(20.0, 27.0, seconds - 120, 90.0);
    }
    final third = _integratedLinear(20.0, 27.0, 90.0, 90.0);
    return first +
        second +
        third +
        _integratedLinear(
          27.0,
          maximumSpeedMetersPerSecond,
          seconds - 210,
          90.0,
        );
  }

  /// Route generation may need a short look-ahead beyond the 300 second
  /// ranking clock. After the final stage the runner stays at the 42m/s cap.
  static double distanceForGeneration(double elapsedSeconds) {
    if (elapsedSeconds <= maximumDuration.inSeconds) {
      return distanceForElapsed(elapsedSeconds);
    }
    return distanceForElapsed(maximumDuration.inSeconds.toDouble()) +
        (elapsedSeconds - maximumDuration.inSeconds) *
            maximumSpeedMetersPerSecond;
  }

  static double elapsedForDistance(double distanceMeters) {
    final distance = max(0.0, distanceMeters);
    final first = _integratedLinear(8.0, 14.0, 30.0, 30.0);
    final second = _integratedLinear(14.0, 20.0, 90.0, 90.0);
    final third = _integratedLinear(20.0, 27.0, 90.0, 90.0);
    if (distance <= first) {
      return _inverseLinearIntegral(8.0, 14.0, distance, 30.0);
    }
    if (distance <= first + second) {
      return 30 + _inverseLinearIntegral(14.0, 20.0, distance - first, 90.0);
    }
    if (distance <= first + second + third) {
      return 120 +
          _inverseLinearIntegral(20.0, 27.0, distance - first - second, 90.0);
    }
    final tail = _inverseLinearIntegral(
      27.0,
      maximumSpeedMetersPerSecond,
      distance - first - second - third,
      90.0,
    );
    return 210 + tail;
  }

  static double elapsedForGenerationDistance(double distanceMeters) {
    final distance = max(0.0, distanceMeters);
    final runDistance = distanceForElapsed(
      maximumDuration.inSeconds.toDouble(),
    );
    if (distance <= runDistance) return elapsedForDistance(distance);
    return maximumDuration.inSeconds +
        (distance - runDistance) / maximumSpeedMetersPerSecond;
  }

  static int scoreFor({required double distanceMeters, required int coins}) {
    final distanceScore = max(0, distanceMeters.floor());
    final coinScore = max(0, coins) * 10;
    return min(maximumSubmittedScore, distanceScore + coinScore);
  }

  static String formatScore(int score) => '${max(0, score)}점';

  static String formatHudScore(int score) => max(0, score).toString();

  static int clampLane(int lane) => lane.clamp(firstLane, lastLane);

  static double clampPosition(double positionInLanes) => positionInLanes
      .clamp(firstLane.toDouble(), lastLane.toDouble())
      .toDouble();

  /// Kept for legacy fixtures. Horizontal swipes in the game are reserved for
  /// corner turns and never call this lane-changing helper.
  static int laneAfterSwipe(int lane, TempleRunSwipe swipe) {
    final current = clampLane(lane);
    return switch (swipe) {
      TempleRunSwipe.left => max(firstLane, current - 1),
      TempleRunSwipe.right => min(lastLane, current + 1),
      _ => current,
    };
  }

  static TempleRunSwipe? swipeForDelta({
    required double dx,
    required double dy,
  }) {
    if (max(dx.abs(), dy.abs()) < swipeThreshold) return null;
    if (dx.abs() >= dy.abs()) {
      return dx < 0 ? TempleRunSwipe.left : TempleRunSwipe.right;
    }
    return dy < 0 ? TempleRunSwipe.up : TempleRunSwipe.down;
  }

  static bool isJumpActive(double remainingSeconds) => remainingSeconds > 0;

  static bool isSlideActive(double remainingSeconds) => remainingSeconds > 0;

  /// Ease used by both the game camera yaw and the visual lateral basis. It
  /// reaches the exact endpoint at one, which keeps a 90° corner atomic.
  static double turnEaseOut(double progress) {
    final t = progress.clamp(0.0, 1.0).toDouble();
    final remaining = 1.0 - t;
    return 1.0 - remaining * remaining * remaining;
  }

  static bool survivesObstacle({
    required TempleRunObstacle obstacle,
    required int lane,
    required double jumpRemainingSeconds,
    required double slideRemainingSeconds,
  }) => survivesObstacleAtPosition(
    obstacle: obstacle,
    positionInLanes: clampLane(lane).toDouble(),
    jumpRemainingSeconds: jumpRemainingSeconds,
    slideRemainingSeconds: slideRemainingSeconds,
  );

  static bool survivesObstacleAtPosition({
    required TempleRunObstacle obstacle,
    required double positionInLanes,
    required double jumpRemainingSeconds,
    required double slideRemainingSeconds,
  }) {
    final position = clampPosition(positionInLanes);
    if (!overlapsObstaclePosition(
      obstacle: obstacle,
      positionInLanes: position,
    )) {
      return true;
    }
    return switch (obstacle.kind) {
      TempleRunObstacleKind.hurdle ||
      TempleRunObstacleKind.gap => isJumpActive(jumpRemainingSeconds),
      TempleRunObstacleKind.arch => isSlideActive(slideRemainingSeconds),
      TempleRunObstacleKind.rubble || TempleRunObstacleKind.narrowPath => false,
    };
  }

  /// Spatial collision rule used by the runtime and deterministic tests.
  static bool overlapsObstaclePosition({
    required TempleRunObstacle obstacle,
    required double positionInLanes,
  }) => obstacle.blocksPosition(clampPosition(positionInLanes));

  static bool overlapsLanePosition({
    required int lane,
    required double positionInLanes,
    double halfWidthInLanes = runnerHalfWidthInLanes,
  }) => (positionInLanes - clampLane(lane)).abs() <= halfWidthInLanes;

  /// Opposite vertical poses need a complete release window between them.
  /// Same-kind hazards can be chained by one held pose and stay on the tight
  /// late-run cadence; jump↔slide pairs cannot.
  static bool requiresVerticalTransition(
    TempleRunObstacleKind previous,
    TempleRunObstacleKind next,
  ) {
    final previousIsVertical =
        previous == TempleRunObstacleKind.hurdle ||
        previous == TempleRunObstacleKind.arch;
    final nextIsVertical =
        next == TempleRunObstacleKind.hurdle ||
        next == TempleRunObstacleKind.arch;
    return previousIsVertical && nextIsVertical && previous != next;
  }

  static Set<int> safeLanesFor(TempleRunObstacle obstacle) {
    if (obstacle.isNarrowPath) return {clampLane(obstacle.lane)};
    if (obstacle.spansFullRoad) return const <int>{};
    return {
      for (var lane = firstLane; lane <= lastLane; lane++)
        if (lane != obstacle.lane) lane,
    };
  }

  /// Checks the generated route as intervals, including the full length of a
  /// narrow path. A narrow terrain has a safe strip, but jumps, slides, and a
  /// shield never bypass its lateral requirement.
  static bool hasReachableSafeContinuation(TempleRunCourse course) {
    final obstacles = [...course.obstacles]
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    TempleRunObstacle? previous;
    var previousEnd = -double.infinity;
    for (final obstacle in obstacles) {
      if (!obstacle.distanceMeters.isFinite || obstacle.distanceMeters < 0) {
        return false;
      }
      if (obstacle.isNarrowPath && obstacle.occupiedLengthMeters <= 0) {
        return false;
      }
      final eventEnd = obstacle.isNarrowPath
          ? obstacle.endDistanceMeters
          : obstacle.distanceMeters + collisionWindowMeters;
      if (previous != null) {
        final gap = obstacle.distanceMeters - previousEnd;
        final speed = maxBoostedSpeedAtDistance(previousEnd);
        final previousElapsed = elapsedForGenerationDistance(previousEnd);
        if (gap / speed < hazardReactionSecondsAt(previousElapsed) - 0.0001) {
          return false;
        }
        if (requiresVerticalTransition(previous.kind, obstacle.kind) &&
            gap / speed <
                max(jumpDurationSeconds, slideDurationSeconds) + .10 - .0001) {
          return false;
        }
      }
      if (obstacle.spansFullRoad &&
          obstacle.kind == TempleRunObstacleKind.rubble) {
        return false;
      }
      if (obstacle.spansFullRoad &&
          obstacle.kind == TempleRunObstacleKind.gap &&
          fullRoadGapWidthMeters /
                  maxBoostedSpeedAtDistance(obstacle.distanceMeters) >
              jumpDurationSeconds) {
        return false;
      }
      previous = obstacle;
      previousEnd = eventEnd;
    }

    final turns = [...course.turns]
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    for (final turn in turns) {
      if (turn.windowEndMeters < turn.windowStartMeters ||
          !turn.distanceMeters.isFinite ||
          !turn.windowStartMeters.isFinite ||
          !turn.windowEndMeters.isFinite) {
        return false;
      }
      for (final obstacle in obstacles) {
        final obstacleStart = obstacle.distanceMeters;
        final obstacleEnd = obstacle.isNarrowPath
            ? obstacle.endDistanceMeters
            : obstacle.distanceMeters + collisionWindowMeters;
        final turnBeforeObstacle = turn.distanceMeters < obstacleStart;
        final referenceDistance = turnBeforeObstacle
            ? turn.distanceMeters
            : obstacleEnd;
        final distance = turnBeforeObstacle
            ? obstacleStart - turn.distanceMeters
            : turn.distanceMeters > obstacleEnd
            ? turn.distanceMeters - obstacleEnd
            : 0.0;
        final referenceElapsed = elapsedForGenerationDistance(
          referenceDistance,
        );
        final requiredSeparation = turnBeforeObstacle
            ? postTurnObstacleSeparationSecondsAt(referenceElapsed)
            : maneuverSeparationSecondsAt(referenceElapsed);
        if (distance / maxBoostedSpeedAtDistance(referenceDistance) <
            requiredSeparation - 0.0001) {
          return false;
        }
      }
    }

    for (var index = 1; index < turns.length; index++) {
      final previousTurn = turns[index - 1];
      final turn = turns[index];
      final previousElapsed = elapsedForGenerationDistance(
        previousTurn.distanceMeters,
      );
      final elapsed = elapsedForGenerationDistance(turn.distanceMeters);
      if (elapsed - previousElapsed <
          turnSeparationSecondsAt(previousElapsed) - 0.0001) {
        return false;
      }
      final minimumWindowStart =
          previousTurn.windowEndMeters +
          maxBoostedSpeedAtDistance(previousTurn.distanceMeters) *
              turnAnimationDurationSeconds;
      if (turn.windowStartMeters < minimumWindowStart - 0.0001) {
        return false;
      }
    }
    return true;
  }

  static double maxBoostedSpeedAtDistance(double distanceMeters) => min(
    maximumBoostedSpeedMetersPerSecond,
    speedForElapsed(elapsedForGenerationDistance(distanceMeters)) *
        boostSpeedMultiplier,
  );

  static double _lerp(double start, double end, double amount) =>
      start + ((end - start) * amount.clamp(0.0, 1.0));

  static double _integratedLinear(
    double startSpeed,
    double endSpeed,
    double elapsed,
    double stageDuration,
  ) {
    final t = elapsed.clamp(0.0, stageDuration);
    return (startSpeed * t) +
        (0.5 * (endSpeed - startSpeed) * t * t / stageDuration);
  }

  static double _inverseLinearIntegral(
    double startSpeed,
    double endSpeed,
    double distance,
    double stageDuration,
  ) {
    final slope = (endSpeed - startSpeed) / stageDuration;
    if (slope.abs() < 0.000001) return distance / startSpeed;
    final discriminant = (startSpeed * startSpeed) + (2 * slope * distance);
    return ((sqrt(max(0.0, discriminant)) - startSpeed) / slope).clamp(
      0.0,
      stageDuration,
    );
  }
}

enum TempleRunDifficultyStage { learn, establish, combine, mastery }

/// Builds deterministic hazard clusters with a corner after each cluster.
/// Cluster size is seeded and grows by time band; the action clock remains
/// independent from the coin and power-up clocks.
class TempleRunCourseGenerator {
  TempleRunCourseGenerator(this.random);

  final Random random;

  TempleRunCourse generate({Duration duration = TempleRunRules.gameDuration}) {
    final durationSeconds = min(
      duration.inMicroseconds / Duration.microsecondsPerSecond,
      TempleRunRules.maximumDuration.inSeconds.toDouble(),
    );
    final obstacles = <TempleRunObstacle>[];
    final coins = <TempleRunCoin>[];
    final powerUps = <TempleRunPowerUp>[];
    final turns = <TempleRunTurn>[];

    final boostedTargetDistance =
        TempleRunRules.distanceForElapsed(durationSeconds) *
            TempleRunRules.boostSpeedMultiplier +
        TempleRunRules.farClipDistanceMeters;
    final generationEndSeconds = max(
      durationSeconds + TempleRunRules.boostDurationSeconds + 1.0,
      TempleRunRules.elapsedForGenerationDistance(boostedTargetDistance) + 1.0,
    );

    final firstTurnTime = 4.2 + random.nextDouble() * 0.4;
    turns.add(_makeTurn(firstTurnTime));
    var obstacleId = 1;
    var obstacleActionIndex = 0;
    var narrowPathIndex = 0;
    var nextNarrowLane = TempleRunRules.firstLane;
    var eventTime = 5.8;
    var previousTurnTime = firstTurnTime;
    TempleRunTurn? previousTurn = turns.first;
    TempleRunObstacle? previousObstacle;
    // Every junction gets a readable recovery beat: the first obstacle on
    // the new heading is always a vertical read, never a tilt lane check.
    // If the weighted action pattern would have placed a narrow path there,
    // defer that narrow path to the next member of the same cluster so the
    // long-run 5:2 non-tilt/tilt ratio remains intact.
    var firstObstacleAfterTurn = true;
    var deferredNarrowPath = false;
    while (eventTime < generationEndSeconds) {
      var hazardClusterSize = 0;
      var addedHazards = 0;
      while (addedHazards == 0 || addedHazards < hazardClusterSize) {
        if (eventTime >= generationEndSeconds) break;
        if (addedHazards == 0) {
          hazardClusterSize = _hazardClusterSizeAt(eventTime);
        }
        // Tilt terrain is intentionally the minority mechanic: across every
        // seven authored actions, two require lateral tilt and five are
        // vertical obstacle reads (2.5× more non-tilt actions).  Keeping the
        // pattern deterministic makes the ratio stable for every seed while
        // still varying which vertical obstacle appears.
        final patternNarrow = switch (obstacleActionIndex % 7) {
          0 || 4 => true,
          _ => false,
        };
        final shouldGenerateNarrow =
            deferredNarrowPath || (!firstObstacleAfterTurn && patternNarrow);
        if (deferredNarrowPath) deferredNarrowPath = false;
        if (firstObstacleAfterTurn && patternNarrow) {
          // A one-obstacle cluster has no later member to receive the
          // deferred tilt check. Do not carry that state across the turn,
          // otherwise the next cluster would violate the turn→vertical rule.
          deferredNarrowPath = hazardClusterSize > 1;
        }
        final kind = shouldGenerateNarrow
            ? TempleRunObstacleKind.narrowPath
            : switch (obstacleActionIndex % 7) {
                1 || 5 => TempleRunObstacleKind.hurdle,
                _ => TempleRunObstacleKind.arch,
              };
        final actionTime = _safeObstacleTime(
          eventTime,
          previousObstacle: previousObstacle,
          previousTurn: previousTurn,
          nextKind: kind,
        );
        final lane = kind == TempleRunObstacleKind.narrowPath
            ? nextNarrowLane
            : TempleRunRules.centerLane;
        final obstacle = _makeObstacle(
          id: obstacleId++,
          elapsedSeconds: actionTime,
          kind: kind,
          lane: lane,
          narrowPathIndex: narrowPathIndex,
        );
        obstacles.add(obstacle);
        previousObstacle = obstacle;
        if (kind == TempleRunObstacleKind.narrowPath) {
          narrowPathIndex++;
          nextNarrowLane = lane == TempleRunRules.firstLane
              ? TempleRunRules.lastLane
              : TempleRunRules.firstLane;
        }
        firstObstacleAfterTurn = false;
        obstacleActionIndex++;
        addedHazards++;
        eventTime =
            actionTime + TempleRunRules.actionCadenceSecondsAt(actionTime);
      }
      if (addedHazards == 0 || eventTime >= generationEndSeconds) break;

      final turnTime = _safeTurnTime(
        eventTime,
        previousTurnTime: previousTurnTime,
        previousObstacle: previousObstacle,
      );
      final turn = _makeTurn(turnTime, previousTurn: previousTurn);
      turns.add(turn);
      previousTurnTime = turnTime;
      previousTurn = turn;
      firstObstacleAfterTurn = true;
      eventTime = turnTime + TempleRunRules.actionCadenceSecondsAt(turnTime);
    }

    _addTimedCoins(coins, durationSeconds, obstacles);
    _addTimedPowerUps(powerUps, durationSeconds, obstacles);

    obstacles.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    coins.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    if (coins.length > TempleRunRules.maximumCoinsPerRun) {
      coins.removeRange(TempleRunRules.maximumCoinsPerRun, coins.length);
    }
    powerUps.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    turns.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return TempleRunCourse(
      obstacles: obstacles,
      coins: coins,
      powerUps: powerUps,
      turns: turns,
      totalDistanceMeters: TempleRunRules.distanceForGeneration(
        generationEndSeconds,
      ),
    );
  }

  TempleRunTurn _makeTurn(
    double elapsedSeconds, {
    TempleRunTurn? previousTurn,
  }) {
    final speed = TempleRunRules.speedForElapsed(elapsedSeconds);
    final distance = TempleRunRules.distanceForGeneration(elapsedSeconds);
    final nominalWindowStart =
        distance - speed * TempleRunRules.mandatoryTurnLeadSeconds;
    final previousWindowEnd = previousTurn == null
        ? 0.0
        : previousTurn.windowEndMeters +
              TempleRunRules.maxBoostedSpeedAtDistance(
                    previousTurn.distanceMeters,
                  ) *
                  TempleRunRules.turnAnimationDurationSeconds;
    final tailDistance = speed * TempleRunRules.mandatoryTurnTailSeconds;
    return TempleRunTurn(
      distanceMeters: distance,
      direction: random.nextBool()
          ? TempleRunTurnDirection.left
          : TempleRunTurnDirection.right,
      windowStartMeters: max(0, max(nominalWindowStart, previousWindowEnd)),
      windowEndMeters: distance + tailDistance,
    );
  }

  int _hazardClusterSizeAt(double elapsedSeconds) {
    // Every corner can be preceded by one to five hazards. Short clusters
    // keep the opening readable while the later distribution makes the
    // player chain several actions before the next turn. The probabilities
    // are intentionally explicit so seeded routes remain easy to audit.
    final progress = (elapsedSeconds / 300).clamp(0.0, 1.0);
    final oneHazardChance = .16 - (.06 * progress);
    final twoHazardChance = .46 - (.16 * progress);
    final threeHazardChance = .28 + (.04 * progress);
    final fourHazardChance = .09 + (.10 * progress);
    final roll = random.nextDouble();
    if (roll < oneHazardChance) return 1;
    if (roll < oneHazardChance + twoHazardChance) return 2;
    if (roll < oneHazardChance + twoHazardChance + threeHazardChance) {
      return 3;
    }
    if (roll <
        oneHazardChance +
            twoHazardChance +
            threeHazardChance +
            fourHazardChance) {
      return 4;
    }
    return 5;
  }

  double _safeObstacleTime(
    double requestedTime, {
    required TempleRunObstacle? previousObstacle,
    required TempleRunTurn? previousTurn,
    required TempleRunObstacleKind nextKind,
  }) {
    var requiredDistance = TempleRunRules.distanceForGeneration(requestedTime);
    if (previousObstacle != null) {
      final end = previousObstacle.isNarrowPath
          ? previousObstacle.endDistanceMeters
          : previousObstacle.distanceMeters +
                TempleRunRules.collisionWindowMeters;
      final previousElapsed = TempleRunRules.elapsedForGenerationDistance(end);
      var requiredSeconds = TempleRunRules.hazardReactionSecondsAt(
        previousElapsed,
      );
      if (_requiresVerticalTransition(previousObstacle.kind, nextKind)) {
        // A jump and a slide cannot overlap: the first pose must have time to
        // settle before the opposite pose is needed. Same-kind vertical
        // hazards remain intentionally tight because one held pose clears
        // the sequence.
        requiredSeconds = max(
          requiredSeconds,
          max(
                TempleRunRules.jumpDurationSeconds,
                TempleRunRules.slideDurationSeconds,
              ) +
              .10,
        );
      }
      requiredDistance = max(
        requiredDistance,
        end + requiredSeconds * TempleRunRules.maxBoostedSpeedAtDistance(end),
      );
    }
    if (previousTurn != null) {
      requiredDistance = max(
        requiredDistance,
        previousTurn.distanceMeters +
            TempleRunRules.postTurnObstacleSeparationSecondsAt(
                  TempleRunRules.elapsedForGenerationDistance(
                    previousTurn.distanceMeters,
                  ),
                ) *
                TempleRunRules.maxBoostedSpeedAtDistance(
                  previousTurn.distanceMeters,
                ),
      );
    }
    return max(
      requestedTime,
      TempleRunRules.elapsedForGenerationDistance(requiredDistance),
    );
  }

  bool _requiresVerticalTransition(
    TempleRunObstacleKind previous,
    TempleRunObstacleKind next,
  ) => TempleRunRules.requiresVerticalTransition(previous, next);

  double _safeTurnTime(
    double requestedTime, {
    required double previousTurnTime,
    required TempleRunObstacle? previousObstacle,
  }) {
    var safeTime = max(
      requestedTime,
      previousTurnTime +
          TempleRunRules.turnSeparationSecondsAt(previousTurnTime),
    );
    if (previousObstacle != null) {
      final obstacleEnd = previousObstacle.isNarrowPath
          ? previousObstacle.endDistanceMeters
          : previousObstacle.distanceMeters +
                TempleRunRules.collisionWindowMeters;
      safeTime = max(
        safeTime,
        TempleRunRules.elapsedForGenerationDistance(
          obstacleEnd +
              TempleRunRules.maneuverSeparationSecondsAt(
                    TempleRunRules.elapsedForGenerationDistance(obstacleEnd),
                  ) *
                  TempleRunRules.maxBoostedSpeedAtDistance(obstacleEnd),
        ),
      );
    }
    return safeTime;
  }

  TempleRunObstacle _makeObstacle({
    required int id,
    required double elapsedSeconds,
    required TempleRunObstacleKind kind,
    required int lane,
    required int narrowPathIndex,
  }) {
    final narrowPath = kind == TempleRunObstacleKind.narrowPath;
    return TempleRunObstacle(
      id: id,
      distanceMeters: TempleRunRules.distanceForGeneration(elapsedSeconds),
      lane: lane,
      kind: kind,
      span: narrowPath
          ? TempleRunObstacleSpan.singleLane
          : TempleRunObstacleSpan.fullRoad,
      lengthMeters: narrowPath
          ? TempleRunRules.narrowPathLengthForIndex(narrowPathIndex)
          : 0,
    );
  }

  void _addTimedCoins(
    List<TempleRunCoin> coins,
    double durationSeconds,
    List<TempleRunObstacle> obstacles,
  ) {
    final maximumDistance = TempleRunRules.distanceForElapsed(durationSeconds);
    for (
      var time = 2.5;
      time < durationSeconds;
      time += TempleRunRules.coinLineCadenceSeconds
    ) {
      final lineCenter = TempleRunRules.distanceForElapsed(time);
      final lane = random.nextInt(TempleRunRules.laneCount);
      for (var offset = -1; offset <= 1; offset++) {
        final distance = max(0.0, lineCenter + offset * 4.2);
        if (distance > maximumDistance) continue;
        coins.add(
          TempleRunCoin(
            distanceMeters: distance,
            lane: _safePickupLane(distance, lane, obstacles),
          ),
        );
      }
    }
  }

  void _addTimedPowerUps(
    List<TempleRunPowerUp> powerUps,
    double durationSeconds,
    List<TempleRunObstacle> obstacles,
  ) {
    var kindIndex = 0;
    for (
      var time = TempleRunRules.powerUpCadenceSeconds;
      time < durationSeconds;
      time += TempleRunRules.powerUpCadenceSeconds
    ) {
      final distance = TempleRunRules.distanceForElapsed(time);
      powerUps.add(
        TempleRunPowerUp(
          distanceMeters: distance,
          lane: _safePickupLane(
            distance,
            TempleRunRules.centerLane,
            obstacles,
            TempleRunRules.powerUpPickupWindowMeters,
          ),
          kind: switch (kindIndex++ % 3) {
            0 => TempleRunPowerUpKind.magnet,
            1 => TempleRunPowerUpKind.shield,
            _ => TempleRunPowerUpKind.boost,
          },
        ),
      );
    }
  }

  int _safePickupLane(
    double distance,
    int preferredLane, [
    List<TempleRunObstacle>? obstacles,
    double pickupWindowMeters = TempleRunRules.coinPickupWindowMeters,
  ]) {
    for (final obstacle in obstacles ?? const <TempleRunObstacle>[]) {
      if (obstacle.isNarrowPath &&
          distance >= obstacle.distanceMeters - pickupWindowMeters &&
          distance <= obstacle.endDistanceMeters + pickupWindowMeters) {
        return obstacle.lane;
      }
    }
    return preferredLane;
  }
}
