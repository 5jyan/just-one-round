import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';

void main() {
  test('speed stages rise to the capped 42m/s and integrate consistently', () {
    expect(TempleRunRules.speedForElapsed(0), 8);
    expect(TempleRunRules.speedForElapsed(30), 14);
    expect(TempleRunRules.speedForElapsed(45), 15);
    expect(TempleRunRules.speedForElapsed(120), 20);
    expect(TempleRunRules.speedForElapsed(210), 27);
    expect(TempleRunRules.speedForElapsed(300), 42);
    expect(TempleRunRules.speedForElapsed(999), 42);
    expect(
      TempleRunRules.maximumBoostedSpeedMetersPerSecond,
      closeTo(55.44, .000001),
    );
    expect(
      TempleRunRules.maxBoostedSpeedAtDistance(double.infinity),
      closeTo(55.44, .000001),
    );
    expect(TempleRunRules.distanceForElapsed(300), closeTo(7080, 0.000001));

    var previousSpeed = 0.0;
    for (var millisecond = 0; millisecond <= 300000; millisecond += 100) {
      final speed = TempleRunRules.speedForElapsed(millisecond / 1000);
      expect(speed, greaterThanOrEqualTo(previousSpeed));
      expect(speed, inInclusiveRange(8, 42));
      previousSpeed = speed;
    }

    for (final seconds in [0.0, 12.5, 45.0, 91.0, 120.0, 209.5, 300.0]) {
      final distance = TempleRunRules.distanceForElapsed(seconds);
      expect(
        TempleRunRules.elapsedForDistance(distance),
        closeTo(seconds, 0.00001),
        reason: '$seconds seconds',
      );
    }
    final boostedTarget =
        TempleRunRules.distanceForElapsed(300) *
            TempleRunRules.boostSpeedMultiplier +
        TempleRunRules.farClipDistanceMeters;
    expect(
      TempleRunRules.elapsedForGenerationDistance(boostedTarget),
      greaterThan(300),
    );
  });

  test('score is natural higher-is-better and bounded', () {
    expect(TempleRunRules.scoreFor(distanceMeters: 12.9, coins: 3), 42);
    expect(TempleRunRules.scoreFor(distanceMeters: -4, coins: -2), 0);
    expect(
      TempleRunRules.scoreFor(distanceMeters: 99_999, coins: 99_999),
      TempleRunRules.maximumSubmittedScore,
    );
  });

  test('three maximum boosts stay under the server distance ceiling', () {
    // The route offers exactly three boosts. This bounds all legal pickup
    // placements more conservatively than their actual 90/180/270s schedule:
    // all available boost time is assigned the run's final speed.
    final maximumBoostSeconds = 3 * TempleRunRules.boostDurationSeconds;
    var largestDistanceExcess = double.negativeInfinity;
    var worstBoundTime = 0.0;
    for (var millisecond = 0; millisecond <= 300000; millisecond++) {
      final seconds = millisecond / 1000;
      final boostSeconds = min(seconds, maximumBoostSeconds);
      final distanceUpperBound =
          TempleRunRules.distanceForElapsed(seconds) +
          boostSeconds *
              TempleRunRules.speedForElapsed(seconds) *
              (TempleRunRules.boostSpeedMultiplier - 1);
      final distanceExcess = distanceUpperBound - 24 * seconds;
      if (distanceExcess > largestDistanceExcess) {
        largestDistanceExcess = distanceExcess;
        worstBoundTime = seconds;
      }
    }
    // The 1ms sweep covers every client-reported millisecond; the RPC also
    // permits two metres for rounding and frame integration.
    expect(
      largestDistanceExcess,
      lessThanOrEqualTo(2.000001),
      reason: '$worstBoundTime seconds',
    );
  });

  test('swipes use a 20px dominant axis and legacy lanes stay bounded', () {
    expect(TempleRunRules.swipeForDelta(dx: 19.9, dy: 0), isNull);
    expect(TempleRunRules.swipeForDelta(dx: -20, dy: 20), TempleRunSwipe.left);
    expect(TempleRunRules.swipeForDelta(dx: 0, dy: -24), TempleRunSwipe.up);
    expect(TempleRunRules.laneAfterSwipe(0, TempleRunSwipe.left), 0);
    expect(TempleRunRules.laneAfterSwipe(2, TempleRunSwipe.right), 2);
    expect(TempleRunRules.clampPosition(-2), 0);
    expect(TempleRunRules.clampPosition(4), 2);
  });

  test('runner and obstacle boundaries leave the authored edges usable', () {
    const narrowPath = TempleRunObstacle(
      distanceMeters: 50,
      lane: TempleRunRules.centerLane,
      kind: TempleRunObstacleKind.narrowPath,
      lengthMeters: 6,
    );
    expect(narrowPath.blocksPosition(1.28), isFalse);
    expect(narrowPath.blocksPosition(1.34), isTrue);

    const hurdle = TempleRunObstacle(
      distanceMeters: 50,
      lane: TempleRunRules.centerLane,
      kind: TempleRunObstacleKind.hurdle,
    );
    expect(
      TempleRunRules.overlapsObstaclePosition(
        obstacle: hurdle,
        positionInLanes: 1.52,
      ),
      isFalse,
    );
    expect(
      TempleRunRules.overlapsObstaclePosition(
        obstacle: hurdle,
        positionInLanes: 1.48,
      ),
      isTrue,
    );
  });

  test('action cadence tightens without cutting reaction or turn recovery', () {
    expect(TempleRunRules.actionCadenceSecondsAt(0), .90);
    expect(TempleRunRules.actionCadenceSecondsAt(5), .90);
    expect(TempleRunRules.actionCadenceSecondsAt(12), .78);
    expect(TempleRunRules.actionCadenceSecondsAt(25), .68);
    expect(TempleRunRules.actionCadenceSecondsAt(45), .60);
    expect(TempleRunRules.actionCadenceSecondsAt(90), .54);
    expect(TempleRunRules.actionCadenceSecondsAt(300), .46);
    expect(TempleRunRules.actionCadenceSecondsAt(18.5), closeTo(.73, .000001));
    expect(TempleRunRules.hazardReactionSecondsAt(18.5), closeTo(.65, .000001));
    expect(
      TempleRunRules.maneuverSeparationSecondsAt(18.5),
      closeTo(.67, .000001),
    );
    expect(
      TempleRunRules.postTurnObstacleSeparationSecondsAt(18.5),
      closeTo(.85, .000001),
    );
    expect(
      TempleRunRules.turnSeparationSecondsAt(18.5),
      closeTo(2.225, .000001),
    );
    // Generation reserves this floor at the conservative boosted speed. A
    // non-boosted runner therefore sees roughly 0.74s between hazards, while
    // a boosted run is protected by the boost/recovery contract itself.
    expect(TempleRunRules.hazardReactionSecondsAt(0), .74);
    expect(TempleRunRules.hazardReactionSecondsAt(12), .68);
    expect(TempleRunRules.hazardReactionSecondsAt(25), .62);
    expect(TempleRunRules.hazardReactionSecondsAt(45), .57);
    expect(TempleRunRules.hazardReactionSecondsAt(90), .52);
    expect(TempleRunRules.hazardReactionSecondsAt(300), .44);
    expect(
      TempleRunRules.maxBoostedSpeedAtDistance(double.infinity),
      greaterThan(TempleRunRules.speedForElapsed(300)),
    );
  });

  test('seeded courses reproduce and cover boosted look-ahead', () {
    final first = TempleRunCourseGenerator(Random(20261015)).generate();
    final second = TempleRunCourseGenerator(Random(20261015)).generate();

    expect(first.obstacles, second.obstacles);
    expect(first.turns, second.turns);
    expect(first.coins.length, second.coins.length);
    expect(first.isReachable, isTrue);
    expect(
      TempleRunRules.elapsedForGenerationDistance(
        first.obstacles.first.distanceMeters,
      ),
      closeTo(_expectedFirstHazardTime(first), .0001),
    );
    final distances = first.obstacles
        .map((obstacle) => obstacle.distanceMeters)
        .toList();
    expect(distances.toSet().length, distances.length);
    final boostedTarget =
        TempleRunRules.distanceForElapsed(300) *
            TempleRunRules.boostSpeedMultiplier +
        TempleRunRules.farClipDistanceMeters;
    expect(first.totalDistanceMeters, greaterThanOrEqualTo(boostedTarget));
  });

  test('only the post-turn side receives the added recovery gap', () {
    final turnDistance = TempleRunRules.distanceForGeneration(90);
    final turnElapsed = TempleRunRules.elapsedForGenerationDistance(
      turnDistance,
    );
    final speed = TempleRunRules.maxBoostedSpeedAtDistance(turnDistance);
    final maneuverGap = TempleRunRules.maneuverSeparationSecondsAt(turnElapsed);
    final turn = TempleRunTurn(
      distanceMeters: turnDistance,
      direction: TempleRunTurnDirection.left,
      windowStartMeters: turnDistance - 100,
      windowEndMeters: turnDistance + 10,
    );

    TempleRunCourse courseWith(TempleRunObstacle obstacle) => TempleRunCourse(
      obstacles: [obstacle],
      coins: const [],
      powerUps: const [],
      turns: [turn],
      totalDistanceMeters: turnDistance + 100,
    );

    final tooCloseAfterTurn = courseWith(
      TempleRunObstacle(
        distanceMeters: turnDistance + speed * (maneuverGap + .15),
        lane: TempleRunRules.centerLane,
        kind: TempleRunObstacleKind.hurdle,
      ),
    );
    final safeAfterTurn = courseWith(
      TempleRunObstacle(
        distanceMeters:
            turnDistance +
            speed *
                (TempleRunRules.postTurnObstacleSeparationSecondsAt(
                      turnElapsed,
                    ) +
                    .15),
        lane: TempleRunRules.centerLane,
        kind: TempleRunObstacleKind.hurdle,
      ),
    );
    expect(tooCloseAfterTurn.isReachable, isFalse);
    expect(safeAfterTurn.isReachable, isTrue);

    final beforeTurnGap = maneuverGap + .15;
    final safeBeforeTurn = courseWith(
      TempleRunObstacle(
        distanceMeters:
            turnDistance -
            speed * beforeTurnGap -
            TempleRunRules.collisionWindowMeters,
        lane: TempleRunRules.centerLane,
        kind: TempleRunObstacleKind.hurdle,
      ),
    );
    expect(safeBeforeTurn.isReachable, isTrue);
  });

  test(
    '250 deterministic seeds keep safe intervals and generated action kinds',
    () {
      for (var seed = 0; seed < 250; seed++) {
        final course = TempleRunCourseGenerator(Random(seed)).generate();
        expect(course.isReachable, isTrue, reason: 'seed $seed');
        expect(course.obstacles, isNotEmpty, reason: 'seed $seed');
        expect(
          course.obstacles.any(
            (obstacle) => obstacle.kind == TempleRunObstacleKind.gap,
          ),
          isFalse,
          reason: 'seed $seed generated a removed gap hazard',
        );
        expect(
          course.obstacles.any(
            (obstacle) => obstacle.kind == TempleRunObstacleKind.narrowPath,
          ),
          isTrue,
          reason: 'seed $seed has tilt terrain',
        );
        for (var index = 1; index < course.obstacles.length; index++) {
          final previous = course.obstacles[index - 1];
          final current = course.obstacles[index];
          final gap = current.distanceMeters - previous.endDistanceMeters;
          final speed = TempleRunRules.maxBoostedSpeedAtDistance(
            previous.endDistanceMeters,
          );
          expect(
            gap / speed,
            greaterThanOrEqualTo(
              TempleRunRules.hazardReactionSecondsAt(
                    TempleRunRules.elapsedForGenerationDistance(
                      previous.endDistanceMeters,
                    ),
                  ) -
                  .0001,
            ),
            reason: 'seed $seed obstacle $index',
          );
        }
        for (final turn in course.turns) {
          final followingObstacles = course.obstacles
              .where(
                (obstacle) => obstacle.distanceMeters > turn.distanceMeters,
              )
              .toList();
          if (followingObstacles.isEmpty) continue;
          final nextObstacle = followingObstacles.first;
          final speed = TempleRunRules.maxBoostedSpeedAtDistance(
            turn.distanceMeters,
          );
          final elapsed = TempleRunRules.elapsedForGenerationDistance(
            turn.distanceMeters,
          );
          expect(
            (nextObstacle.distanceMeters - turn.distanceMeters) / speed,
            greaterThanOrEqualTo(
              TempleRunRules.postTurnObstacleSeparationSecondsAt(elapsed) -
                  .0001,
            ),
            reason: 'seed $seed turn at ${turn.distanceMeters}',
          );
        }
      }
      final course = TempleRunCourseGenerator(Random(20261017)).generate();
      expect(
        course.obstacles.map((obstacle) => obstacle.kind).toSet(),
        containsAll(const [
          TempleRunObstacleKind.narrowPath,
          TempleRunObstacleKind.hurdle,
          TempleRunObstacleKind.arch,
        ]),
      );
      expect(
        course.obstacles.map((obstacle) => obstacle.kind),
        everyElement(isNot(TempleRunObstacleKind.gap)),
      );
    },
  );

  test('generated IDs exercise both authored vertical obstacle variants', () {
    var sawJumpVariant = false;
    var sawSlideVariant = false;
    for (var seed = 0; seed < 50; seed++) {
      final course = TempleRunCourseGenerator(Random(seed)).generate();
      for (final obstacle in course.obstacles) {
        if (obstacle.kind == TempleRunObstacleKind.hurdle &&
            obstacle.id > 0 &&
            obstacle.id % 4 == 0) {
          sawJumpVariant = true;
        }
        if (obstacle.kind == TempleRunObstacleKind.arch &&
            obstacle.id > 0 &&
            obstacle.id % 4 == 2) {
          sawSlideVariant = true;
        }
      }
    }
    expect(sawJumpVariant, isTrue, reason: 'jump variant IDs are reachable');
    expect(sawSlideVariant, isTrue, reason: 'slide variant IDs are reachable');
  });

  test('short tilt intervals alternate and never lead a turn combo', () {
    final generatedLengths = <double>{};
    for (var seed = 0; seed < 50; seed++) {
      final course = TempleRunCourseGenerator(Random(seed)).generate();
      final narrowPaths = course.obstacles
          .where((obstacle) => obstacle.isNarrowPath)
          .toList();
      expect(narrowPaths, isNotEmpty, reason: 'seed $seed');
      generatedLengths.addAll(
        narrowPaths.map((obstacle) => obstacle.occupiedLengthMeters),
      );
      expect(
        narrowPaths,
        everyElement(
          predicate<TempleRunObstacle>(
            (obstacle) =>
                obstacle.occupiedLengthMeters ==
                    TempleRunRules.narrowPathQuarterLengthMeters ||
                obstacle.occupiedLengthMeters ==
                    TempleRunRules.narrowPathHalfLengthMeters,
          ),
        ),
        reason: 'seed $seed generated an obsolete long tilt interval',
      );

      for (final turn in course.turns) {
        final nextObstacle = course.obstacles
            .cast<TempleRunObstacle?>()
            .firstWhere(
              (obstacle) => obstacle!.distanceMeters > turn.distanceMeters,
              orElse: () => null,
            );
        if (nextObstacle == null) continue;
        expect(
          nextObstacle.isNarrowPath,
          isFalse,
          reason: 'seed $seed turn at ${turn.distanceMeters}',
        );
      }
    }
    expect(
      generatedLengths,
      containsAll(<double>[
        TempleRunRules.narrowPathQuarterLengthMeters,
        TempleRunRules.narrowPathHalfLengthMeters,
      ]),
    );
  });

  test('generated hazard clusters tighten while corners stay frequent', () {
    final earlyClusterSizes = <int>[];
    final transitionClusterSizes = <int>[];
    final lateClusterSizes = <int>[];
    final earlyHazardGaps = <double>[];
    final lateHazardGaps = <double>[];
    final cornerIntervals = <double>[];
    final cornerIntervals90To150 = <double>[];
    final cornerIntervals45To90 = <double>[];
    final directions = <TempleRunTurnDirection>{};
    var earlyHazardCount = 0;
    var earlyAdjacentHazardCount = 0;
    var lateHazardCount = 0;
    var lateAdjacentHazardCount = 0;
    var narrowPathCount = 0;
    var nonTiltObstacleCount = 0;
    final earlyObstacleToTurnGaps = <double>[];
    final lateObstacleToTurnGaps = <double>[];

    for (var seed = 0; seed < 50; seed++) {
      final course = TempleRunCourseGenerator(Random(seed)).generate();
      narrowPathCount += course.obstacles
          .where((obstacle) => obstacle.isNarrowPath)
          .length;
      nonTiltObstacleCount += course.obstacles
          .where((obstacle) => !obstacle.isNarrowPath)
          .length;
      final events = <(double, bool)>[
        for (final turn in course.turns)
          (
            TempleRunRules.elapsedForGenerationDistance(turn.distanceMeters),
            true,
          ),
        for (final obstacle in course.obstacles)
          (
            TempleRunRules.elapsedForGenerationDistance(
              obstacle.distanceMeters,
            ),
            false,
          ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      var clusterStart = 0.0;
      var clusterSize = 0;
      var previousHazardTime = 0.0;
      var previousCornerTime = 0.0;

      for (final turn in course.turns) {
        final time = TempleRunRules.elapsedForGenerationDistance(
          turn.distanceMeters,
        );
        if (time <= 300) directions.add(turn.direction);
        if (previousCornerTime > 0 && time <= 300) {
          final interval = time - previousCornerTime;
          cornerIntervals.add(interval);
          if (time >= 45 && time < 90) {
            cornerIntervals45To90.add(interval);
          } else if (time >= 90 && time < 150) {
            cornerIntervals90To150.add(interval);
          }
        }
        final priorObstacles = course.obstacles
            .where(
              (obstacle) => obstacle.endDistanceMeters <= turn.distanceMeters,
            )
            .toList();
        if (priorObstacles.isNotEmpty && time <= 300) {
          final previousObstacle = priorObstacles.last;
          final obstacleEndTime = TempleRunRules.elapsedForGenerationDistance(
            previousObstacle.endDistanceMeters,
          );
          final gap = time - obstacleEndTime;
          (time < 90 ? earlyObstacleToTurnGaps : lateObstacleToTurnGaps).add(
            gap,
          );
        }
        if (time <= 300) previousCornerTime = time;
      }

      for (final event in events) {
        if (event.$1 > 300) break;
        if (event.$2) {
          if (clusterSize > 0) {
            if (clusterStart < 90) {
              earlyClusterSizes.add(clusterSize);
            } else if (clusterStart < 150) {
              transitionClusterSizes.add(clusterSize);
            } else {
              lateClusterSizes.add(clusterSize);
            }
          }
          clusterSize = 0;
          previousHazardTime = 0;
          continue;
        }

        if (clusterSize == 0) clusterStart = event.$1;
        if (previousHazardTime > 0) {
          final gap = event.$1 - previousHazardTime;
          if (event.$1 < 90 && previousHazardTime < 90) {
            earlyHazardGaps.add(gap);
            earlyAdjacentHazardCount++;
          }
          if (event.$1 >= 180 && previousHazardTime >= 180) {
            lateHazardGaps.add(gap);
            lateAdjacentHazardCount++;
          }
        }
        if (event.$1 < 90) earlyHazardCount++;
        if (event.$1 >= 180) lateHazardCount++;
        previousHazardTime = event.$1;
        clusterSize++;
      }
    }

    double median(List<double> values) {
      final sorted = [...values]..sort();
      return sorted[sorted.length ~/ 2];
    }

    expect(earlyClusterSizes, isNotEmpty);
    expect(earlyClusterSizes, everyElement(inInclusiveRange(1, 5)));
    expect(earlyClusterSizes, contains(1));
    expect(earlyClusterSizes, contains(2));
    expect(earlyClusterSizes, contains(3));
    expect(transitionClusterSizes, isNotEmpty);
    expect(transitionClusterSizes, everyElement(inInclusiveRange(1, 5)));
    expect(lateClusterSizes, isNotEmpty);
    expect(lateClusterSizes, everyElement(inInclusiveRange(1, 5)));
    expect(lateClusterSizes, contains(1));
    expect(lateClusterSizes, contains(2));
    expect(lateClusterSizes, contains(3));
    expect(lateClusterSizes, contains(4));
    expect(lateClusterSizes, contains(5));
    expect(directions, containsAll(TempleRunTurnDirection.values));
    expect(cornerIntervals, isNotEmpty);
    // A five-obstacle pre-turn cluster still keeps the next turn inside the
    // original seven-second readability ceiling.
    expect(cornerIntervals, everyElement(lessThan(7.0)));
    expect(median(cornerIntervals), lessThan(5.5));
    expect(cornerIntervals45To90, isNotEmpty);
    expect(cornerIntervals90To150, isNotEmpty);
    expect(
      median(cornerIntervals90To150),
      lessThanOrEqualTo(median(cornerIntervals45To90) * 1.15),
      reason: 'corner cadence should not sharply slow after 90 seconds',
    );

    expect(earlyHazardGaps, isNotEmpty);
    expect(lateHazardGaps, isNotEmpty);
    expect(
      median(lateHazardGaps),
      lessThan(median(earlyHazardGaps)),
      reason: 'consecutive hazard spacing trends down by elapsed-time band',
    );
    expect(
      lateAdjacentHazardCount / lateHazardCount,
      greaterThan(earlyAdjacentHazardCount / earlyHazardCount),
      reason: 'later routes contain a larger share of consecutive hazards',
    );
    expect(
      nonTiltObstacleCount / narrowPathCount,
      inInclusiveRange(2.2, 2.8),
      reason: 'vertical hazards should be about 2.5× as common as tilt paths',
    );
    expect(earlyObstacleToTurnGaps, isNotEmpty);
    expect(lateObstacleToTurnGaps, isNotEmpty);
    expect(
      lateObstacleToTurnGaps.reduce(min),
      lessThan(earlyObstacleToTurnGaps.reduce(max)),
      reason: 'late turns follow hazards with a shorter recovery beat',
    );
    expect(
      lateObstacleToTurnGaps.reduce(max),
      lessThanOrEqualTo(TempleRunRules.maneuverSeparationSecondsAt(90) + .30),
      reason: 'late obstacle→turn gaps remain close to the tuned floor',
    );
  });

  test('time-based pickups cover the whole run without exceeding coin cap', () {
    final course = TempleRunCourseGenerator(Random(20261017)).generate();
    final coinTimes = course.coins
        .map(
          (coin) =>
              TempleRunRules.elapsedForGenerationDistance(coin.distanceMeters),
        )
        .toList();
    final powerUpTimes = course.powerUps
        .map(
          (powerUp) => TempleRunRules.elapsedForGenerationDistance(
            powerUp.distanceMeters,
          ),
        )
        .toList();

    expect(course.coins.length, lessThan(TempleRunRules.maximumCoinsPerRun));
    expect(coinTimes.first, lessThan(5));
    expect(coinTimes.any((time) => time > 280), isTrue);
    expect(powerUpTimes, hasLength(9));
    for (var index = 0; index < powerUpTimes.length; index++) {
      expect(powerUpTimes[index], closeTo((index + 1) * 30, 0.0001));
    }
    final boostTimes = [
      for (final powerUp in course.powerUps)
        if (powerUp.kind == TempleRunPowerUpKind.boost)
          TempleRunRules.elapsedForGenerationDistance(powerUp.distanceMeters),
    ];
    expect(boostTimes, hasLength(3));
    for (var index = 0; index < boostTimes.length; index++) {
      expect(boostTimes[index], closeTo((index + 1) * 90, 0.0001));
    }
    expect(
      course.powerUps.map((item) => item.kind).toSet(),
      containsAll(TempleRunPowerUpKind.values),
    );
  });

  test(
    'narrow path is a continuous safe interval and ignores poses/shields',
    () {
      const path = TempleRunObstacle(
        distanceMeters: 50,
        lane: TempleRunRules.firstLane,
        kind: TempleRunObstacleKind.narrowPath,
        lengthMeters: 6,
      );
      expect(path.endDistanceMeters, 56);
      expect(path.isSolid, isFalse);
      expect(path.blocksPosition(0), isFalse);
      expect(
        TempleRunRules.narrowPathSafeHalfWidthInLanes,
        closeTo(.28, .000001),
      );
      expect(path.blocksPosition(.30), isFalse);
      expect(path.blocksPosition(.31), isTrue);
      expect(path.blocksPosition(1), isTrue);
      expect(
        const TempleRunObstacle(
          distanceMeters: 50,
          lane: TempleRunRules.lastLane,
          kind: TempleRunObstacleKind.narrowPath,
          lengthMeters: 6,
        ).blocksPosition(1.70),
        isFalse,
      );
      expect(
        const TempleRunObstacle(
          distanceMeters: 50,
          lane: TempleRunRules.lastLane,
          kind: TempleRunObstacleKind.narrowPath,
          lengthMeters: 6,
        ).blocksPosition(1.69),
        isTrue,
      );
      expect(TempleRunRules.safeLanesFor(path), {0});
      expect(
        TempleRunRules.survivesObstacleAtPosition(
          obstacle: path,
          positionInLanes: 1,
          jumpRemainingSeconds: 1,
          slideRemainingSeconds: 1,
        ),
        isFalse,
      );
      expect(
        TempleRunRules.survivesObstacleAtPosition(
          obstacle: path,
          positionInLanes: 0,
          jumpRemainingSeconds: 0,
          slideRemainingSeconds: 0,
        ),
        isTrue,
      );
    },
  );

  test('full-road gaps remain jumpable and shields apply only to solids', () {
    const fullGap = TempleRunObstacle(
      distanceMeters: 50,
      lane: TempleRunRules.centerLane,
      kind: TempleRunObstacleKind.gap,
      span: TempleRunObstacleSpan.fullRoad,
    );
    const singleRubble = TempleRunObstacle(
      distanceMeters: 50,
      lane: TempleRunRules.firstLane,
      kind: TempleRunObstacleKind.rubble,
    );

    expect(fullGap.widthInLanes, TempleRunRules.laneCount);
    expect(fullGap.blocksPosition(TempleRunRules.firstLane.toDouble()), isTrue);
    expect(TempleRunRules.safeLanesFor(fullGap), isEmpty);
    expect(
      TempleRunRules.fullRoadGapWidthMeters /
          TempleRunRules.maxBoostedSpeedAtDistance(fullGap.distanceMeters),
      lessThan(TempleRunRules.jumpDurationSeconds),
    );
    expect(singleRubble.blocksPosition(0.46), isTrue);
    expect(
      TempleRunRules.survivesObstacleAtPosition(
        obstacle: singleRubble,
        positionInLanes: 0.46,
        jumpRemainingSeconds: 0,
        slideRemainingSeconds: 0,
      ),
      isFalse,
    );
  });

  test('turns lead into the combos and stay far enough apart', () {
    final course = TempleRunCourseGenerator(Random(20261016)).generate();
    final turnTimes = course.turns
        .map(
          (turn) =>
              TempleRunRules.elapsedForGenerationDistance(turn.distanceMeters),
        )
        .toList();

    expect(turnTimes.first, inInclusiveRange(4.2, 4.6));
    expect(
      TempleRunRules.elapsedForGenerationDistance(
        course.obstacles.first.distanceMeters,
      ),
      closeTo(_expectedFirstHazardTime(course), .0001),
    );
    expect(
      course.turns.map((turn) => turn.direction).toSet(),
      containsAll(TempleRunTurnDirection.values),
    );
    for (var index = 1; index < turnTimes.length; index++) {
      final interval = turnTimes[index] - turnTimes[index - 1];
      expect(
        interval,
        greaterThanOrEqualTo(
          TempleRunRules.turnSeparationSecondsAt(turnTimes[index - 1]) - 0.002,
        ),
      );
      final previous = course.turns[index - 1];
      final current = course.turns[index];
      expect(
        current.windowStartMeters,
        greaterThanOrEqualTo(
          previous.windowEndMeters +
              TempleRunRules.maxBoostedSpeedAtDistance(
                    previous.distanceMeters,
                  ) *
                  TempleRunRules.turnAnimationDurationSeconds -
              0.002,
        ),
      );
    }
    for (var index = 1; index < course.obstacles.length; index++) {
      final previous = course.obstacles[index - 1];
      final current = course.obstacles[index];
      if (!previous.isNarrowPath || !current.isNarrowPath) continue;
      expect(current.lane, isNot(previous.lane));
    }
  });

  test('mixed vertical hazards leave a pose transition window', () {
    final requiredTransition =
        max(
          TempleRunRules.jumpDurationSeconds,
          TempleRunRules.slideDurationSeconds,
        ) +
        .10;
    var sawMixedPair = false;
    for (var seed = 0; seed < 250; seed++) {
      final course = TempleRunCourseGenerator(Random(seed)).generate();
      for (var index = 1; index < course.obstacles.length; index++) {
        final previous = course.obstacles[index - 1];
        final current = course.obstacles[index];
        final mixedVertical =
            (previous.kind == TempleRunObstacleKind.hurdle &&
                current.kind == TempleRunObstacleKind.arch) ||
            (previous.kind == TempleRunObstacleKind.arch &&
                current.kind == TempleRunObstacleKind.hurdle);
        if (!mixedVertical) continue;
        sawMixedPair = true;
        final speed = TempleRunRules.maxBoostedSpeedAtDistance(
          previous.endDistanceMeters,
        );
        expect(
          (current.distanceMeters - previous.endDistanceMeters) / speed,
          greaterThanOrEqualTo(requiredTransition - .0001),
          reason: 'seed $seed obstacle $index',
        );
      }
    }
    expect(sawMixedPair, isTrue);
  });

  test('reachability rejects an impossible opposite-pose pair', () {
    final first = TempleRunObstacle(
      distanceMeters: 100,
      lane: TempleRunRules.centerLane,
      kind: TempleRunObstacleKind.hurdle,
      span: TempleRunObstacleSpan.fullRoad,
    );
    final speed = TempleRunRules.maxBoostedSpeedAtDistance(
      first.distanceMeters + TempleRunRules.collisionWindowMeters,
    );
    final transition =
        max(
          TempleRunRules.jumpDurationSeconds,
          TempleRunRules.slideDurationSeconds,
        ) +
        .10;

    TempleRunCourse courseWithGap(double gapSeconds) {
      final secondDistance =
          first.distanceMeters +
          TempleRunRules.collisionWindowMeters +
          speed * gapSeconds;
      return TempleRunCourse(
        obstacles: [
          first,
          TempleRunObstacle(
            distanceMeters: secondDistance,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.arch,
            span: TempleRunObstacleSpan.fullRoad,
          ),
        ],
        coins: const [],
        powerUps: const [],
        turns: const [],
        totalDistanceMeters: secondDistance + 100,
      );
    }

    expect(courseWithGap(transition - .01).isReachable, isFalse);
    expect(courseWithGap(transition + .01).isReachable, isTrue);
  });
}

double _expectedFirstHazardTime(TempleRunCourse course) {
  final firstTurn = course.turns.first;
  final minimumDistance =
      firstTurn.distanceMeters +
      TempleRunRules.maxBoostedSpeedAtDistance(firstTurn.distanceMeters) *
          TempleRunRules.postTurnObstacleSeparationSecondsAt(
            TempleRunRules.elapsedForGenerationDistance(
              firstTurn.distanceMeters,
            ),
          );
  return TempleRunRules.elapsedForGenerationDistance(
    max(TempleRunRules.distanceForGeneration(5.8), minimumDistance),
  );
}
