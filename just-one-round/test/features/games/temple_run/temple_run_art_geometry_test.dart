import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

void main() {
  test('route camera keeps contact and lane projection through real turns', () {
    const viewports = [Size(360, 640), Size(360, 820)];
    const distancesAfterJunction = [-.1, .1, 1.5, 3.0, 6.0, 9.0];
    for (final direction in TempleRunTurnDirection.values) {
      final course = _geometryCourse(direction);
      final turns = course.turns;
      for (final viewport in viewports) {
        for (var turnIndex = 0; turnIndex < turns.length; turnIndex++) {
          final turn = turns[turnIndex];
          for (final offset in distancesAfterJunction) {
            final distance = turn.distanceMeters + offset;
            final completedTurns = turnIndex + (offset > 0 ? 1 : 0);
            final centered = _projectionFor(
              course: course,
              viewport: viewport,
              distanceMeters: distance,
              completedTurnCount: completedTurns,
              visualLane: TempleRunRules.centerLane.toDouble(),
            );
            _expectRunnerFoot(centered, viewport);
            for (final lane in [0.0, 1.0, 2.0]) {
              final projection = _projectionFor(
                course: course,
                viewport: viewport,
                distanceMeters: distance,
                completedTurnCount: completedTurns,
                visualLane: lane,
              );
              final expectedDx =
                  centered.center.dx +
                  (lane - TempleRunRules.centerLane) * centered.roadWidth / 3;
              expect(
                projection.center.dx,
                closeTo(expectedDx, .02),
                reason:
                    'lane=$lane direction=$direction distance=$distance viewport=$viewport',
              );
              expect(
                projection.center.dy,
                closeTo(centered.center.dy, .01),
                reason:
                    'lane=$lane direction=$direction distance=$distance viewport=$viewport',
              );
              expect(projection.depth, greaterThan(.12));
              final roadLeft = centered.center.dx - centered.roadWidth / 2;
              final roadRight = centered.center.dx + centered.roadWidth / 2;
              final runnerHalfWidth =
                  centered.roadWidth *
                  TempleRunRules.runnerHalfWidthInLanes /
                  3;
              expect(
                projection.center.dx - runnerHalfWidth,
                greaterThanOrEqualTo(roadLeft - .001),
              );
              expect(
                projection.center.dx + runnerHalfWidth,
                lessThanOrEqualTo(roadRight + .001),
              );
              _expectFiniteProjection(projection);
            }

            for (final tilt in [-1.0, 1.0]) {
              final projection = _projectionFor(
                course: course,
                viewport: viewport,
                distanceMeters: distance,
                completedTurnCount: completedTurns,
                phoneTilt: tilt,
              );
              expect(
                projection.center.dx,
                closeTo(
                  centered.center.dx + tilt * centered.roadWidth / 3,
                  .02,
                ),
                reason:
                    'tilt=$tilt direction=$direction distance=$distance viewport=$viewport',
              );
              expect(projection.center.dy, closeTo(centered.center.dy, .01));
              _expectFiniteProjection(projection);
            }
          }
        }
      }
    }
  });

  test('narrow banks only cover reachable unsafe sides', () {
    final roadHalf = TempleRunArt.roadWidthForTesting / 2;
    final laneStep =
        TempleRunArt.roadWidthForTesting / TempleRunRules.laneCount;
    final safeHalf = TempleRunRules.narrowPathSafeWidthInLanes * laneStep / 2;
    double safeCenter(int lane) =>
        (lane - TempleRunRules.centerLane) * laneStep;
    double safeStart(int lane) => safeCenter(lane) - safeHalf;
    double safeEnd(int lane) => safeCenter(lane) + safeHalf;

    final leftLaneBanks = TempleRunArt.narrowBankOffsetsForTesting(0);
    expect(leftLaneBanks, hasLength(1));
    expect(leftLaneBanks.single.innerOffset, closeTo(safeEnd(0), 1e-8));
    expect(leftLaneBanks.single.outerOffset, closeTo(roadHalf, 1e-8));
    expect(
      safeStart(0),
      lessThan(-(TempleRunRules.centerLane * laneStep)),
      reason: 'the dropped left lane-0 bank is outside legal center motion',
    );

    final centerLaneBanks = TempleRunArt.narrowBankOffsetsForTesting(1);
    expect(centerLaneBanks, hasLength(2));
    expect(centerLaneBanks[0].innerOffset, closeTo(safeStart(1), 1e-8));
    expect(centerLaneBanks[0].outerOffset, closeTo(-roadHalf, 1e-8));
    expect(centerLaneBanks[1].innerOffset, closeTo(safeEnd(1), 1e-8));
    expect(centerLaneBanks[1].outerOffset, closeTo(roadHalf, 1e-8));

    final rightLaneBanks = TempleRunArt.narrowBankOffsetsForTesting(2);
    expect(rightLaneBanks, hasLength(1));
    expect(rightLaneBanks.single.innerOffset, closeTo(safeStart(2), 1e-8));
    expect(rightLaneBanks.single.outerOffset, closeTo(-roadHalf, 1e-8));
    expect(
      safeEnd(2),
      greaterThan(
        (TempleRunRules.lastLane - TempleRunRules.centerLane) * laneStep,
      ),
      reason: 'the dropped right lane-2 bank is outside legal center motion',
    );

    // Collision uses the runner center, while the art shows the authored safe
    // strip. The runner's edge reaches just past that strip by the explicit
    // collision epsilon, so the bank and gameplay threshold remain aligned.
    final collisionCenterLimit =
        TempleRunRules.narrowPathSafeHalfWidthInLanes +
        TempleRunRules.narrowPathLateralEpsilon;
    final runnerEdgeAtLimit =
        collisionCenterLimit + TempleRunRules.runnerHalfWidthInLanes;
    expect(
      runnerEdgeAtLimit - TempleRunRules.narrowPathSafeWidthInLanes / 2,
      closeTo(TempleRunRules.narrowPathLateralEpsilon, 1e-8),
    );

    // Beyond the authored safe strip, every reachable player center is over a
    // retained bank. Only lane 0/2's unreachable outside edge is omitted.
    for (final lane in [0, 1, 2]) {
      final obstacleForLane = TempleRunObstacle(
        distanceMeters: 0,
        lane: lane,
        kind: TempleRunObstacleKind.narrowPath,
      );
      for (var position = 0.0; position <= 2.0001; position += .025) {
        if ((position - lane).abs() <=
            TempleRunRules.narrowPathSafeWidthInLanes / 2) {
          continue;
        }
        expect(obstacleForLane.blocksPosition(position), isTrue);
        final worldOffset = (position - TempleRunRules.centerLane) * laneStep;
        expect(
          TempleRunArt.narrowBankOffsetsForTesting(lane).any((bank) {
            final low = math.min(bank.innerOffset, bank.outerOffset);
            final high = math.max(bank.innerOffset, bank.outerOffset);
            return worldOffset >= low - .001 && worldOffset <= high + .001;
          }),
          isTrue,
          reason: 'lane=$lane position=$position must remain visibly unsafe',
        );
      }
    }
  });

  test('turn camera heading is cubic, exact, and shared by every lane', () {
    for (final direction in TempleRunTurnDirection.values) {
      final course = TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: [
          TempleRunTurn(
            distanceMeters: 20,
            direction: direction,
            windowStartMeters: 10,
            windowEndMeters: 24,
          ),
        ],
        totalDistanceMeters: 80,
      );
      final art = TempleRunArt(viewportWidth: 360, viewportHeight: 640);
      _updateGeometryScene(
        art,
        course: course,
        distanceMeters: 20,
        completedTurns: 0,
      );
      expect(art.cameraHeadingForTesting, closeTo(0, 1e-8));

      void update(double bendProgress, double lane) {
        art.updateScene(
          course: course,
          distanceMeters: 20,
          lane: lane.round(),
          visualLane: lane,
          jumpRemaining: 0,
          slideRemaining: 0,
          runnerFrame: 0,
          activeTurn: course.turns.single,
          bendProgress: bendProgress,
          bendDirection: direction,
          completedTurnCount: 1,
          guardianVisible: false,
          failureVisible: false,
          shieldVisible: false,
          boostVisible: false,
        );
      }

      for (final lane in [0.0, 1.0, 2.0]) {
        update(1, lane);
        expect(art.cameraHeadingForTesting, closeTo(0, 1e-8));
        expect(art.cameraBoomDistanceForTesting, greaterThan(.12));
        update(.5, lane);
        final expectedSign = direction == TempleRunTurnDirection.left
            ? -1.0
            : 1.0;
        expect(
          art.cameraHeadingForTesting,
          closeTo(expectedSign * 78.75 * math.pi / 180, 1e-8),
        );
        expect(art.project(0).center.dx.isFinite, isTrue);
        update(0, lane);
        expect(
          art.cameraHeadingForTesting,
          closeTo(expectedSign * TempleRunRules.turnAngleRadians, 1e-8),
        );
        expect(art.cameraBoomDistanceForTesting, greaterThan(.12));
      }
    }
  });

  test('background parallax follows yaw and repeats after a full turn', () {
    TempleRunCourse courseFor(TempleRunTurnDirection direction) =>
        TempleRunCourse(
          obstacles: const [],
          coins: const [],
          powerUps: const [],
          turns: [
            TempleRunTurn(
              distanceMeters: 20,
              direction: direction,
              windowStartMeters: 10,
              windowEndMeters: 24,
            ),
          ],
          totalDistanceMeters: 60,
        );

    for (final direction in TempleRunTurnDirection.values) {
      final course = courseFor(direction);
      final art = TempleRunArt(viewportWidth: 360, viewportHeight: 640);
      _updateGeometryScene(
        art,
        course: course,
        distanceMeters: 20,
        completedTurns: 0,
      );
      expect(art.backgroundParallaxForTesting, closeTo(0, 1e-8));
      _updateGeometryScene(
        art,
        course: course,
        distanceMeters: 20,
        completedTurns: 1,
        bendProgress: 0,
        bendDirection: direction,
      );
      final expected = direction == TempleRunTurnDirection.right
          ? -math.pi / 2 / (2 * math.pi) * 720
          : math.pi / 2 / (2 * math.pi) * 720;
      expect(art.backgroundParallaxForTesting, closeTo(expected, 1e-8));
    }

    final fourRightTurns = TempleRunCourse(
      obstacles: const [],
      coins: const [],
      powerUps: const [],
      turns: [
        for (var index = 0; index < 4; index++)
          TempleRunTurn(
            distanceMeters: 20.0 + index * 20,
            direction: TempleRunTurnDirection.right,
            windowStartMeters: 10.0 + index * 20,
            windowEndMeters: 24.0 + index * 20,
          ),
      ],
      totalDistanceMeters: 110,
    );
    final fullTurnArt = TempleRunArt(viewportWidth: 360, viewportHeight: 640);
    _updateGeometryScene(
      fullTurnArt,
      course: fourRightTurns,
      distanceMeters: 80,
      completedTurns: 4,
      bendProgress: 0,
      bendDirection: TempleRunTurnDirection.right,
    );
    expect(fullTurnArt.cameraHeadingForTesting, closeTo(2 * math.pi, 1e-8));
    expect(fullTurnArt.backgroundParallaxPhaseForTesting, closeTo(0, 1e-8));
  });

  test('ground homography agrees with direct world projection', () {
    const viewport = Size(360, 640);
    final course = _geometryCourse(TempleRunTurnDirection.left);
    final art = TempleRunArt(
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
    );
    _updateGeometryScene(
      art,
      course: course,
      distanceMeters: 20,
      completedTurns: 1,
      bendProgress: .5,
      bendDirection: TempleRunTurnDirection.left,
      activeTurn: course.turns.first,
    );

    final matrix = art.groundHomographyForTesting;
    final camera = art.cameraPositionForTesting;
    final forward = _forwardForTest(art.cameraHeadingForTesting);
    final right = _rightForTest(art.cameraHeadingForTesting);
    final focal =
        art.focalLengthForTesting *
        (art.cameraTargetDepthForTesting / TempleRunRules.cameraBoomMaxMeters);
    final samples = [
      camera + forward * 1.0 + right * -1.2,
      camera + forward * 7.0 + right * .8,
      camera + forward * 34.0 + right * -2.1,
    ];

    for (final world in samples) {
      final projected = art.projectWorldPointForTesting(world);
      expect(projected, isNotNull);
      final homogeneousX =
          matrix[0] * world.dx + matrix[4] * world.dy + matrix[12];
      final homogeneousY =
          matrix[1] * world.dx + matrix[5] * world.dy + matrix[13];
      final homogeneousW =
          matrix[3] * world.dx + matrix[7] * world.dy + matrix[15];
      final matrixPoint = Offset(
        homogeneousX / homogeneousW,
        homogeneousY / homogeneousW,
      );
      expect(matrixPoint.dx, closeTo(projected!.dx, 1e-8));
      expect(matrixPoint.dy, closeTo(projected.dy, 1e-8));

      final relative = world - camera;
      final depth = _dotForTest(relative, forward);
      final lateral = _dotForTest(relative, right);
      final directPoint = Offset(
        viewport.width / 2 + focal * lateral / depth,
        art.horizonYForTesting + art.cameraHeightForTesting * focal / depth,
      );
      expect(projected.dx, closeTo(directPoint.dx, 1e-8));
      expect(projected.dy, closeTo(directPoint.dy, 1e-8));
    }
  });

  test(
    'facade occluder cache uses the same route window as wall rendering',
    () {
      final course = _geometryCourse(TempleRunTurnDirection.right);
      final art = TempleRunArt(viewportWidth: 360, viewportHeight: 640);
      _updateGeometryScene(
        art,
        course: course,
        distanceMeters: 40,
        completedTurns: course.turns.length,
      );
      final window = art.facadeVisibleWindowForTesting;
      expect(window, isNotNull);
      expect(window!.start, closeTo(22, .0001));
      expect(window.end, closeTo(230, .0001));

      _updateGeometryScene(
        art,
        course: course,
        distanceMeters: 0,
        completedTurns: 0,
      );
      final startWindow = art.facadeVisibleWindowForTesting;
      expect(startWindow, isNotNull);
      expect(startWindow!.start, closeTo(-8, .0001));
      expect(startWindow.end, closeTo(190, .0001));
    },
  );

  test(
    'corner camera sightline and runner feet stay inside inset road geometry',
    () {
      const roadWidth = 4.4;
      const roadHalfWidth = roadWidth / 2;
      const laneWidth = roadWidth / TempleRunRules.laneCount;
      const cameraSpeeds = [
        8.0,
        TempleRunRules.maximumSpeedMetersPerSecond,
        TempleRunRules.maximumBoostedSpeedMetersPerSecond,
      ];
      const elapsedPhases = [0.0, .045, .09, .135, .18];
      const viewports = [Size(360, 640), Size(360, 820)];
      final safeWallOffset =
          roadHalfWidth +
          1.6 -
          TempleRunRules.maximumFacadeReliefDepthMeters -
          TempleRunRules.cameraCornerClearanceMeters;

      for (final firstDirection in TempleRunTurnDirection.values) {
        final course = _geometryCourse(firstDirection);
        for (var turnIndex = 0; turnIndex < course.turns.length; turnIndex++) {
          final turn = course.turns[turnIndex];
          final junction = _routeAtTurn(course, turnIndex);
          final outgoingHeading =
              junction.heading + _turnRadiansForTest(turn.direction);
          final junctionPolygon = TempleRunArt.roadJunctionPolygonForTesting(
            junction: junction.position,
            incomingHeading: junction.heading,
            outgoingHeading: outgoingHeading,
            roadWidth: roadWidth,
          );
          expect(
            _insideInsetLCorridor(
              junction.position - _forwardForTest(outgoingHeading) * 6,
              junction.position,
              junction.heading,
              outgoingHeading,
              safeWallOffset,
            ),
            isFalse,
            reason: 'the outer corner past the local L must be rejected',
          );
          for (final speed in cameraSpeeds) {
            for (final elapsed in elapsedPhases) {
              final distance = turn.distanceMeters + speed * elapsed;
              final bendProgress =
                  (1 - elapsed / TempleRunRules.turnAnimationDurationSeconds)
                      .clamp(0.0, 1.0);
              for (final viewport in viewports) {
                for (final lane in [
                  TempleRunRules.firstLane,
                  TempleRunRules.centerLane,
                  TempleRunRules.lastLane,
                ]) {
                  final art = TempleRunArt(
                    viewportWidth: viewport.width,
                    viewportHeight: viewport.height,
                  );
                  art.updateScene(
                    course: course,
                    distanceMeters: distance,
                    lane: lane,
                    visualLane: lane.toDouble(),
                    jumpRemaining: 0,
                    slideRemaining: 0,
                    runnerFrame: 0,
                    activeTurn: turn,
                    bendProgress: bendProgress,
                    bendDirection: turn.direction,
                    completedTurnCount: turnIndex + 1,
                    guardianVisible: false,
                    failureVisible: false,
                    shieldVisible: false,
                    boostVisible: false,
                  );

                  final camera = art.cameraPositionForTesting;
                  final runner = art.runnerWorldPositionForTesting;
                  expect(
                    art.cameraBoomDistanceForTesting,
                    inInclusiveRange(.12, 6.0),
                    reason:
                        'boom turn=$turnIndex direction=$firstDirection '
                        'speed=$speed elapsed=$elapsed lane=$lane '
                        'viewport=$viewport',
                  );
                  for (var sample = 0; sample <= 12; sample++) {
                    final amount = sample / 12;
                    final point = Offset.lerp(camera, runner, amount)!;
                    expect(
                      _insideInsetLCorridor(
                        point,
                        junction.position,
                        junction.heading,
                        outgoingHeading,
                        safeWallOffset,
                      ),
                      isTrue,
                      reason:
                          'sightline sample=$sample turn=$turnIndex '
                          'direction=$firstDirection speed=$speed '
                          'elapsed=$elapsed lane=$lane viewport=$viewport '
                          'point=$point',
                    );
                  }

                  final footHalfWidth =
                      laneWidth * TempleRunRules.runnerHalfWidthInLanes;
                  final footRight = _rightForTest(art.cameraHeadingForTesting);
                  final outgoingLegLength = turnIndex + 1 < course.turns.length
                      ? course.turns[turnIndex + 1].distanceMeters -
                            turn.distanceMeters
                      : course.totalDistanceMeters - turn.distanceMeters;
                  for (final side in [-1.0, 1.0]) {
                    final foot = runner + footRight * footHalfWidth * side;
                    final inJunction = _insideConvexPolygon(
                      junctionPolygon,
                      foot,
                    );
                    final outgoingRelative = foot - junction.position;
                    final outgoingLongitudinal = _dotForTest(
                      outgoingRelative,
                      _forwardForTest(outgoingHeading),
                    );
                    final outgoingLateral = _dotForTest(
                      outgoingRelative,
                      _rightForTest(outgoingHeading),
                    ).abs();
                    final inOutgoingStrip =
                        outgoingLongitudinal >= -.001 &&
                        outgoingLongitudinal <= outgoingLegLength + .001 &&
                        outgoingLateral <= roadHalfWidth + .001;
                    expect(
                      inJunction || inOutgoingStrip,
                      isTrue,
                      reason:
                          'road foot turn=$turnIndex direction='
                          '$firstDirection speed=$speed elapsed=$elapsed '
                          'lane=$lane viewport=$viewport foot=$foot '
                          'inJunction=$inJunction inOutgoingStrip='
                          '$inOutgoingStrip',
                    );
                  }
                }
              }
            }
          }
        }
      }
    },
  );

  test(
    'camera caps at facade height while preserving viewport foot anchor',
    () {
      const viewports = [
        Size(360, 640),
        Size(360, 820),
        Size(200, 320),
        Size(360, 1200),
      ];
      for (final viewport in viewports) {
        final art = TempleRunArt(
          viewportWidth: viewport.width,
          viewportHeight: viewport.height,
        );
        final assetModeArt = TempleRunArt(
          useImageAssets: true,
          viewportWidth: viewport.width,
          viewportHeight: viewport.height,
        );
        _updateGeometryScene(
          art,
          course: _emptyCourse(),
          distanceMeters: 0,
          completedTurns: 0,
        );
        _updateGeometryScene(
          assetModeArt,
          course: _emptyCourse(),
          distanceMeters: 0,
          completedTurns: 0,
        );

        final collisionY = viewport.height * .884;
        final naturalCameraHeight =
            (collisionY - viewport.height * .29) * 6 / (viewport.width * 1.23);
        final expectedCameraHeight = naturalCameraHeight < 5
            ? naturalCameraHeight
            : 5.0;
        expect(
          art.cameraHeightForTesting,
          closeTo(expectedCameraHeight, 1e-8),
          reason: 'camera height at $viewport',
        );
        expect(
          art.horizonYForTesting,
          closeTo(
            collisionY - expectedCameraHeight * viewport.width * 1.23 / 6,
            1e-8,
          ),
          reason: 'camera horizon at $viewport',
        );
        expect(
          art.cameraHeightForTesting,
          lessThan(TempleRunArt.facadeHeightMeters),
          reason: 'the camera remains below the facade cap at $viewport',
        );
        expect(
          assetModeArt.cameraHeightForTesting,
          closeTo(art.cameraHeightForTesting, 1e-8),
          reason: 'image and fallback rendering share one camera at $viewport',
        );
        expect(
          assetModeArt.horizonYForTesting,
          closeTo(art.horizonYForTesting, 1e-8),
          reason: 'image and fallback rendering share one horizon at $viewport',
        );
        final foot = art.project(0).center;
        expect(foot.dx, closeTo(viewport.width / 2, .001));
        expect(foot.dy, closeTo(collisionY, .001));
      }
    },
  );

  test('late unarmed turn holds and eases only the rendered distance', () {
    const seed = 20261018;
    const lateElapsedStartSeconds = 240.0;
    const lateElapsedEndSeconds = 260.0;
    const bendDuration = TempleRunRules.turnAnimationDurationSeconds;
    final course = TempleRunCourseGenerator(
      math.Random(seed),
    ).generate(duration: const Duration(seconds: 260));
    final turnIndex = course.turns.indexWhere((candidate) {
      final elapsed = TempleRunRules.elapsedForGenerationDistance(
        candidate.distanceMeters,
      );
      return elapsed >= lateElapsedStartSeconds &&
          elapsed <= lateElapsedEndSeconds;
    });
    expect(
      turnIndex,
      greaterThanOrEqualTo(0),
      reason:
          'the seeded course must contain a late turn in the high-speed band',
    );
    final turn = course.turns[turnIndex];
    final lateTurnElapsed = TempleRunRules.elapsedForGenerationDistance(
      turn.distanceMeters,
    );
    expect(
      lateTurnElapsed,
      inInclusiveRange(lateElapsedStartSeconds, lateElapsedEndSeconds),
    );
    final lateInputDistance = turn.windowEndMeters;
    final debt = lateInputDistance - turn.distanceMeters;
    expect(debt, greaterThan(3.8));

    TempleRunTurn? sceneTurnAt(double distance, int completedTurns) {
      if (completedTurns >= course.turns.length) return null;
      final candidate = course.turns[completedTurns];
      final distanceUntil = candidate.distanceMeters - distance;
      if (candidate.contains(distance) ||
          distanceUntil >= 0 && distanceUntil <= 80) {
        return candidate;
      }
      return null;
    }

    TempleRunTurnDirection? directionAt(int completedTurns) =>
        completedTurns == 0 ? null : course.turns[completedTurns - 1].direction;

    void update(
      TempleRunArt art, {
      required double distance,
      required int completedTurns,
      required double bendProgress,
      bool failure = false,
    }) {
      art.updateScene(
        course: course,
        distanceMeters: distance,
        lane: TempleRunRules.lastLane,
        visualLane: TempleRunRules.lastLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: distance * .8,
        activeTurn: sceneTurnAt(distance, completedTurns),
        bendProgress: bendProgress,
        bendDirection: directionAt(completedTurns),
        completedTurnCount: completedTurns,
        guardianVisible: false,
        failureVisible: failure,
        shieldVisible: false,
        boostVisible: false,
      );
    }

    final art = TempleRunArt(viewportWidth: 360, viewportHeight: 640);
    update(
      art,
      distance: lateInputDistance,
      completedTurns: turnIndex,
      bendProgress: 0,
    );
    expect(art.actualDistanceForTesting, lateInputDistance);
    expect(art.renderedDistanceForTesting, turn.distanceMeters);
    final heldRunner = art.runnerWorldPositionForTesting;
    final heldCamera = art.cameraPositionForTesting;
    final heldProjection = art.project(0);

    update(
      art,
      distance: lateInputDistance,
      completedTurns: turnIndex + 1,
      bendProgress: 1,
    );
    expect(art.actualDistanceForTesting, lateInputDistance);
    expect(art.renderedDistanceForTesting, turn.distanceMeters);
    expect(art.runnerWorldPositionForTesting, heldRunner);
    expect(art.cameraPositionForTesting, heldCamera);
    final committedProjection = art.project(0);
    expect(
      committedProjection.center.dx,
      closeTo(heldProjection.center.dx, 1e-8),
    );
    expect(
      committedProjection.center.dy,
      closeTo(heldProjection.center.dy, 1e-8),
    );

    final speed = TempleRunRules.maxBoostedSpeedAtDistance(turn.distanceMeters);
    for (final progress in [.75, .5, .25, 0.0]) {
      final elapsed = bendDuration * (1 - progress);
      final distance = lateInputDistance + speed * elapsed;
      update(
        art,
        distance: distance,
        completedTurns: turnIndex + 1,
        bendProgress: progress,
      );
      expect(
        art.renderedDistanceForTesting,
        closeTo(distance - debt * progress, 1e-8),
        reason: 'bend progress $progress should ease the renderer debt',
      );
    }
    final catchUpCompleteDistance = lateInputDistance + speed * bendDuration;
    final firstPostTurnHazard = course.obstacles
        .where((obstacle) => obstacle.distanceMeters > turn.distanceMeters)
        .map((obstacle) => obstacle.distanceMeters)
        .reduce(math.min);
    expect(
      firstPostTurnHazard - TempleRunRules.collisionWindowMeters,
      greaterThan(catchUpCompleteDistance),
      reason: 'the rendered camera must catch up before the next hazard',
    );

    final failureArt = TempleRunArt();
    update(
      failureArt,
      distance: lateInputDistance,
      completedTurns: turnIndex,
      bendProgress: 0,
    );
    update(
      failureArt,
      distance: lateInputDistance + .01,
      completedTurns: turnIndex,
      bendProgress: 0,
      failure: true,
    );
    expect(failureArt.actualDistanceForTesting, lateInputDistance + .01);
    expect(failureArt.renderedDistanceForTesting, turn.distanceMeters);
  });

  test('planned facade spans share mitered wall and roof corners', () {
    for (final direction in TempleRunTurnDirection.values) {
      final course = _geometryCourse(direction);
      final art = TempleRunArt();
      _updateGeometryScene(
        art,
        course: course,
        distanceMeters: 18,
        completedTurns: 0,
      );

      final spansBySide = <int, List<TempleRunFacadeWallSpan>>{};
      for (final side in [-1, 1]) {
        final spans = art.facadeWallSpansForTesting(side: side);
        expect(spans, hasLength(course.turns.length + 1));
        spansBySide[side] = spans;
        for (var index = 1; index < spans.length; index++) {
          final incoming = spans[index - 1];
          final outgoing = spans[index];
          expect(incoming.frontEnd.dx, closeTo(outgoing.frontStart.dx, 1e-8));
          expect(incoming.frontEnd.dy, closeTo(outgoing.frontStart.dy, 1e-8));
          expect(
            incoming.roofEndPoint.dx,
            closeTo(outgoing.roofStartPoint.dx, 1e-8),
          );
          expect(
            incoming.roofEndPoint.dy,
            closeTo(outgoing.roofStartPoint.dy, 1e-8),
          );
          expect(incoming.wallArcEnd, closeTo(outgoing.wallArcStart, 1e-8));

          const tileLength = TempleRunArt.wallTileLengthMeters;
          final cornerArc = incoming.wallArcEnd;
          final tileOrigin = TempleRunArt.facadeTileOriginForArc(
            cornerArc,
            tileLength,
          );
          final sourceXFromIncoming = TempleRunArt.facadeSourceXForArc(
            wallArc: incoming.wallArcEnd,
            tileOrigin: tileOrigin,
            tileLength: tileLength,
            sourceWidth: 512,
          );
          final sourceXFromOutgoing = TempleRunArt.facadeSourceXForArc(
            wallArc: outgoing.wallArcStart,
            tileOrigin: tileOrigin,
            tileLength: tileLength,
            sourceWidth: 512,
          );
          expect(sourceXFromIncoming, closeTo(sourceXFromOutgoing, 1e-8));
        }
      }

      _updateGeometryScene(
        art,
        course: course,
        distanceMeters: 48,
        completedTurns: course.turns.length,
      );
      for (final side in [-1, 1]) {
        final beforeCull = spansBySide[side]!;
        final afterCull = art.facadeWallSpansForTesting(side: side);
        expect(afterCull, hasLength(beforeCull.length));
        for (var index = 0; index < beforeCull.length; index++) {
          expect(
            afterCull[index].wallArcStart,
            closeTo(beforeCull[index].wallArcStart, 1e-8),
          );
          expect(
            afterCull[index].frontStart.dx,
            closeTo(beforeCull[index].frontStart.dx, 1e-8),
          );
          expect(
            afterCull[index].roofEndPoint.dy,
            closeTo(beforeCull[index].roofEndPoint.dy, 1e-8),
          );
        }
      }
    }

    for (final outgoingHeading in [-math.pi / 2, math.pi / 2]) {
      for (final side in [-1.0, 1.0]) {
        for (final offset in [3.8, 9.8]) {
          final junction = const Offset(5, 20);
          final miter = TempleRunArt.facadeMiterCorner(
            junction: junction,
            incomingHeading: 0,
            outgoingHeading: outgoingHeading,
            side: side,
            offset: offset,
          );
          expect(miter, isNotNull);
          final point = miter!;
          final incomingAnchor = junction + Offset(1, 0) * side * offset;
          final outgoingRight = Offset(
            math.cos(outgoingHeading),
            -math.sin(outgoingHeading),
          );
          final outgoingForward = Offset(
            math.sin(outgoingHeading),
            math.cos(outgoingHeading),
          );
          final outgoingAnchor = junction + outgoingRight * side * offset;
          expect(
            _crossForTest(point - incomingAnchor, const Offset(0, 1)),
            closeTo(0, 1e-8),
          );
          expect(
            _crossForTest(point - outgoingAnchor, outgoingForward),
            closeTo(0, 1e-8),
          );
        }
      }
    }

    const wallTileLength = TempleRunArt.wallTileLengthMeters;
    const materialLength = wallTileLength * 10;
    for (var block = 1; block <= 2; block++) {
      final boundary = materialLength * block;
      expect(
        TempleRunArt.facadeStyleIndexForArc(
          boundary - .0001,
          materialLength,
          4,
        ),
        (block - 1) % 4,
      );
      expect(
        TempleRunArt.facadeStyleIndexForArc(boundary, materialLength, 4),
        block % 4,
      );
      final previousTile = TempleRunArt.facadeTileOriginForArc(
        boundary - .0001,
        wallTileLength,
      );
      final nextTile = TempleRunArt.facadeTileOriginForArc(
        boundary,
        wallTileLength,
      );
      expect(boundary - previousTile, closeTo(wallTileLength, .0001));
      expect(boundary - nextTile, closeTo(0, .0001));
    }
  });

  test('wall schedule keeps global neighborhood proportions and variants', () {
    final fullLeft = [
      for (var tile = 0; tile < TempleRunArt.wallSlotCount; tile++)
        TempleRunArt.wallTileKindForArc(
          wallArc: (tile + .25) * TempleRunArt.wallTileLengthMeters,
          side: -1,
        ),
    ];
    final fullRight = [
      for (var tile = 0; tile < TempleRunArt.wallSlotCount; tile++)
        TempleRunArt.wallTileKindForArc(
          wallArc: (tile + .25) * TempleRunArt.wallTileLengthMeters,
          side: 1,
        ),
    ];
    String family(TempleRunWallTileKind kind) => switch (kind) {
      TempleRunWallTileKind.plasterA ||
      TempleRunWallTileKind.plasterB ||
      TempleRunWallTileKind.window ||
      TempleRunWallTileKind.door ||
      TempleRunWallTileKind.mural => 'P',
      TempleRunWallTileKind.houseBrick ||
      TempleRunWallTileKind.houseSage ||
      TempleRunWallTileKind.houseGarden => 'H',
      TempleRunWallTileKind.shopfront => 'S',
      TempleRunWallTileKind.schoolfront ||
      TempleRunWallTileKind.constructionfront => 'R',
    };

    expect(fullLeft.map(family).toList(), [
      'P',
      'H',
      'H',
      'S',
      'R',
      'H',
      'H',
      'S',
      'R',
      'H',
      'H',
      'S',
      'P',
      'H',
      'H',
      'S',
      'H',
      'H',
      'H',
      'H',
    ]);
    expect(fullRight.map(family).toList(), fullLeft.map(family).toList());
    expect(fullLeft.where((kind) => family(kind) == 'P'), hasLength(2));
    expect(fullLeft.where((kind) => family(kind) == 'H'), hasLength(12));
    expect(fullLeft.where((kind) => family(kind) == 'S'), hasLength(4));
    expect(fullLeft.where((kind) => family(kind) == 'R'), hasLength(2));
    expect(
      fullLeft.where(
        (kind) => TempleRunArt.isFullBleedFacadeKindForTesting(kind),
      ),
      hasLength(18),
    );
    expect(
      fullLeft,
      isNot(equals(fullRight)),
      reason:
          'sides vary house/plaster finishes without phase-shifting the schedule',
    );
    for (final start in [1, 5, 9, 13, 16, 18]) {
      expect(
        fullLeft[start],
        fullLeft[start + 1],
        reason: 'each two-tile house property keeps one material identity',
      );
    }
    expect(
      TempleRunArt.wallTileKindForArc(
        wallArc: (8.25) * TempleRunArt.wallTileLengthMeters,
        side: -1,
      ),
      TempleRunWallTileKind.constructionfront,
    );
    expect(
      TempleRunArt.wallTileKindForArc(
        wallArc: (28.25) * TempleRunArt.wallTileLengthMeters,
        side: -1,
      ),
      TempleRunWallTileKind.constructionfront,
    );

    for (final side in const [-1.0, 1.0]) {
      for (var tile = 0; tile < TempleRunArt.wallSlotCount; tile++) {
        final arc = (tile + .25) * TempleRunArt.wallTileLengthMeters;
        final kind = TempleRunArt.wallTileKindForArc(wallArc: arc, side: side);
        final base = TempleRunArt.wallBaseKindForArc(wallArc: arc, side: side);
        expect(base, kind, reason: 'the selected facade owns its full tile');
      }
    }

    final course = _geometryCourse(TempleRunTurnDirection.left);
    final art = TempleRunArt();
    _updateGeometryScene(
      art,
      course: course,
      distanceMeters: 18,
      completedTurns: 0,
    );
    final spans = art.facadeWallSpansForTesting(side: -1);
    for (var index = 1; index < spans.length; index++) {
      final boundary = spans[index].wallArcStart;
      expect(
        TempleRunArt.wallTileIndexForArc(boundary),
        (boundary / TempleRunArt.wallTileLengthMeters).floor(),
        reason: 'global wallArc must survive a route-leg boundary',
      );
    }
  });

  test('street obstacles keep world dimensions instead of billboard scale', () {
    expect(
      TempleRunArt.obstacleWidthForTesting(
        widthInLanes: TempleRunRules.singleLaneObstacleWidthInLanes,
        fullRoad: false,
      ),
      closeTo(
        TempleRunRules.singleLaneObstacleWidthInLanes *
            TempleRunArt.roadWidthForTesting /
            TempleRunRules.laneCount,
        1e-8,
      ),
    );
    expect(
      TempleRunArt.obstacleWidthForTesting(widthInLanes: 0, fullRoad: true),
      closeTo(TempleRunArt.roadWidthForTesting, 1e-8),
    );
    expect(
      TempleRunArt.obstacleHeightForTesting(TempleRunObstacleKind.hurdle),
      closeTo(.45, 1e-8),
    );
    expect(
      TempleRunArt.obstacleHeightForTesting(TempleRunObstacleKind.arch),
      closeTo(2.9, 1e-8),
    );
    expect(
      TempleRunArt.obstacleHeightForTesting(TempleRunObstacleKind.rubble),
      closeTo(1.25, 1e-8),
    );
    expect(
      TempleRunArt.obstacleScaffoldOpeningHeightMeters,
      closeTo(1.0, 1e-8),
    );
  });

  test('road-edge turn joins stay outside both playable lane envelopes', () {
    Offset right(double heading) =>
        Offset(math.cos(heading), -math.sin(heading));
    for (final outgoingHeading in [math.pi / 2, -math.pi / 2]) {
      for (final side in [-1.0, 1.0]) {
        final band = TempleRunArt.roadEdgeJunctionBandForTesting(
          junction: Offset.zero,
          incomingHeading: 0,
          outgoingHeading: outgoingHeading,
          side: side,
          innerOffset: TempleRunArt.roadGutterInnerMeters,
          outerOffset: TempleRunArt.roadGutterOuterMeters,
        );
        expect(band, hasLength(6));
        for (var index = 0; index < band.length; index++) {
          final point = Offset.lerp(
            band[index],
            band[(index + 1) % band.length],
            .5,
          )!;
          // Edges 0, 1, and 5 follow the incoming offset line. Edges 2–4
          // follow the outgoing line; the two miter vertices are shared by
          // both lines.
          final heading = index <= 1 || index == 5 ? 0.0 : outgoingHeading;
          final signedOffset =
              (point.dx * right(heading).dx + point.dy * right(heading).dy) *
              side;
          expect(
            signedOffset,
            greaterThanOrEqualTo(TempleRunArt.roadGutterInnerMeters - .0001),
            reason:
                'turn=$outgoingHeading side=$side edge=$index must stay outside road',
          );
        }
      }
    }
  });

  test('road-edge inner legs terminate at the offset-line miter', () {
    for (final outgoingHeading in [math.pi / 2, -math.pi / 2]) {
      final innerSide = outgoingHeading > 0 ? 1.0 : -1.0;
      for (final offset in [
        TempleRunArt.roadGutterInnerMeters,
        TempleRunArt.roadCurbOuterMeters,
      ]) {
        final expected = TempleRunArt.facadeMiterCorner(
          junction: Offset.zero,
          incomingHeading: 0,
          outgoingHeading: outgoingHeading,
          side: innerSide,
          offset: offset,
        )!;
        final incoming = TempleRunArt.roadEdgeTrimmedEndpointForTesting(
          junction: Offset.zero,
          incomingHeading: 0,
          outgoingHeading: outgoingHeading,
          side: innerSide,
          offset: offset,
          outgoingLeg: false,
        );
        final outgoing = TempleRunArt.roadEdgeTrimmedEndpointForTesting(
          junction: Offset.zero,
          incomingHeading: 0,
          outgoingHeading: outgoingHeading,
          side: innerSide,
          offset: offset,
          outgoingLeg: true,
        );
        expect(incoming.dx, closeTo(expected.dx, 1e-8));
        expect(incoming.dy, closeTo(expected.dy, 1e-8));
        expect(outgoing.dx, closeTo(expected.dx, 1e-8));
        expect(outgoing.dy, closeTo(expected.dy, 1e-8));

        final outerSide = -innerSide;
        final outerIncoming = TempleRunArt.roadEdgeTrimmedEndpointForTesting(
          junction: Offset.zero,
          incomingHeading: 0,
          outgoingHeading: outgoingHeading,
          side: outerSide,
          offset: offset,
          outgoingLeg: false,
        );
        final rawOuter = _rightForTest(0) * outerSide * offset;
        expect(outerIncoming.dx, closeTo(rawOuter.dx, 1e-8));
        expect(outerIncoming.dy, closeTo(rawOuter.dy, 1e-8));
      }
    }
  });

  test('neighborhood relief UVs stay bounded to architectural features', () {
    for (final kind in [
      TempleRunWallTileKind.houseBrick,
      TempleRunWallTileKind.houseSage,
      TempleRunWallTileKind.houseGarden,
      TempleRunWallTileKind.shopfront,
    ]) {
      final rects = TempleRunArt.wallReliefSourceRectsForTesting(kind);
      expect(rects, isNotEmpty, reason: '$kind needs worker UV bounds');
      for (final rect in rects) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(1));
        expect(rect.bottom, lessThanOrEqualTo(1));
        expect(rect.width, lessThan(.75));
        expect(rect.height, lessThan(.55));
      }
    }
    expect(
      TempleRunArt.wallReliefSourceRectsForTesting(
        TempleRunWallTileKind.houseGarden,
      ),
      contains(Rect.fromLTRB(96 / 256, 77 / 192, 188 / 256, 100 / 192)),
    );
  });

  test('neighborhood modules use real setbacks within the road envelope', () {
    for (final kind in [
      TempleRunWallTileKind.houseBrick,
      TempleRunWallTileKind.houseSage,
      TempleRunWallTileKind.houseGarden,
      TempleRunWallTileKind.shopfront,
      TempleRunWallTileKind.schoolfront,
      TempleRunWallTileKind.constructionfront,
    ]) {
      final depth = TempleRunArt.wallMassDepthForTesting(kind);
      final source = TempleRunArt.wallMassSourceRectForTesting(kind);
      expect(depth, inInclusiveRange(.4, .8), reason: '$kind setback');
      expect(source.left, greaterThanOrEqualTo(0));
      expect(source.top, greaterThanOrEqualTo(0));
      expect(source.right, lessThanOrEqualTo(1));
      expect(source.bottom, lessThanOrEqualTo(1));
      expect(source.width, greaterThan(.5));
      expect(source.height, greaterThan(.45));
    }
  });

  test(
    'full-bleed buildings keep feature scale while varying closed skyline heights',
    () {
      const modules = [
        TempleRunWallTileKind.houseBrick,
        TempleRunWallTileKind.houseSage,
        TempleRunWallTileKind.houseGarden,
        TempleRunWallTileKind.shopfront,
      ];
      final heights = <double>[
        for (final kind in modules)
          TempleRunArt.fullBleedHeightExtensionForTesting(kind),
      ];
      expect(heights, contains(0.12));
      expect(heights, contains(0.20));
      expect(heights, contains(0.30));
      expect(heights, contains(0.42));
      expect(heights.toSet(), hasLength(4));
      for (final kind in modules) {
        expect(
          TempleRunArt.fullBleedMaterialSwatchForTesting(kind).size,
          const Size(128, 128),
        );
        expect(
          TempleRunArt.fullBleedHeightExtensionForTesting(kind),
          inInclusiveRange(0, .5),
        );
      }
    },
  );

  test(
    'taller rear module still requests an independent extension side cap',
    () {
      const wallOffset = 4.0;
      final currentKind = TempleRunWallTileKind.houseBrick;
      final neighborKind = TempleRunWallTileKind.houseSage;
      final currentFrontOffset =
          wallOffset - TempleRunArt.fullBleedSetbackForTesting(currentKind);
      final neighborFrontOffset =
          wallOffset - TempleRunArt.fullBleedSetbackForTesting(neighborKind);
      final currentHeight = TempleRunArt.fullBleedHeightExtensionForTesting(
        currentKind,
      );
      final neighborHeight = TempleRunArt.fullBleedHeightExtensionForTesting(
        neighborKind,
      );

      expect(currentFrontOffset, greaterThan(neighborFrontOffset));
      expect(currentHeight, greaterThan(neighborHeight));
      expect(
        TempleRunArt.fullBleedHeightSideCapNeededForTesting(
          currentFrontOffset: currentFrontOffset,
          neighborFrontOffset: neighborFrontOffset,
          currentHeightExtension: currentHeight,
          neighborHeightExtension: neighborHeight,
          currentGuarded: false,
        ),
        isTrue,
        reason: 'a taller module behind its neighbor still needs a side cap',
      );

      expect(
        TempleRunArt.fullBleedHeightSideCapNeededForTesting(
          currentFrontOffset: currentFrontOffset,
          neighborFrontOffset: currentFrontOffset,
          currentHeightExtension: currentHeight,
          neighborHeightExtension: neighborHeight,
          currentGuarded: false,
        ),
        isTrue,
        reason: 'height-only differences must not be hidden by return ordering',
      );
      expect(
        TempleRunArt.fullBleedHeightSideCapNeededForTesting(
          currentFrontOffset: currentFrontOffset,
          neighborFrontOffset: currentFrontOffset,
          currentHeightExtension: currentHeight,
          neighborHeightExtension: currentHeight,
          currentGuarded: false,
        ),
        isFalse,
      );
      expect(
        TempleRunArt.fullBleedHeightSideCapNeededForTesting(
          currentFrontOffset: currentFrontOffset,
          neighborFrontOffset: neighborFrontOffset,
          currentHeightExtension: currentHeight,
          neighborHeightExtension: 0,
          currentGuarded: false,
        ),
        isTrue,
        reason: 'a guarded neighbor contributes zero extension height',
      );
      expect(
        TempleRunArt.fullBleedHeightSideCapNeededForTesting(
          currentFrontOffset: currentFrontOffset,
          neighborFrontOffset: neighborFrontOffset,
          currentHeightExtension: currentHeight,
          neighborHeightExtension: neighborHeight,
          currentGuarded: true,
        ),
        isFalse,
      );
    },
  );

  test('full-bleed prop UVs stay bounded and within the road envelope', () {
    for (final kind in [
      TempleRunWallTileKind.houseBrick,
      TempleRunWallTileKind.houseSage,
      TempleRunWallTileKind.houseGarden,
      TempleRunWallTileKind.shopfront,
    ]) {
      final rects = TempleRunArt.fullBleedPropSourceRectsForTesting(kind);
      final frontDepths = TempleRunArt.fullBleedPropDepthsForTesting(kind);
      expect(rects, isNotEmpty, reason: '$kind needs detached architecture');
      expect(rects, hasLength(frontDepths.length));
      for (final rect in rects) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(1));
        expect(rect.bottom, lessThanOrEqualTo(1));
        expect(rect.width, lessThan(.85));
        expect(rect.height, lessThan(.25));
      }
      expect(
        frontDepths.every((depth) => depth <= 1.2),
        isTrue,
        reason: '$kind must stay inside the roadward depth envelope',
      );
      expect(
        frontDepths.every((depth) => depth <= .45),
        isTrue,
        reason: '$kind architectural relief should stay shallow',
      );
    }
  });

  test('normalized feature crops stay inside the 1024x768 wall source', () {
    for (final kind in [
      TempleRunWallTileKind.window,
      TempleRunWallTileKind.door,
      TempleRunWallTileKind.mural,
    ]) {
      final rect = TempleRunArt.wallFeatureSourceRectForTesting(kind);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(TempleRunArt.wallSourceWidth));
      expect(rect.bottom, lessThanOrEqualTo(TempleRunArt.wallSourceHeight));
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    }
  });

  test('2x wall texture UVs preserve the same world projection', () {
    Offset projected(int scale) {
      final sourceWidth = 512.0 * scale;
      final sourceHeight = 384.0 * scale;
      final sourceU = 237.25 * scale;
      final sourceV = 181.75 * scale;
      final transform = TempleRunFacadeHomography.build(
        viewport: const Size(360, 640),
        horizonY: 160,
        cameraHeight: 5.1,
        focalLength: 420,
        cameraTargetDepth: 6.4,
        cameraBackDistance: 6,
        cameraHeading: .61,
        cameraOriginLateral: -1.3,
        cameraOriginDepth: 11.7,
        facadeHeading: 1.03,
        wallLength: TempleRunArt.wallTileLengthMeters,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        wallHeight: TempleRunArt.facadeHeightMeters,
      );
      final x = transform[0] * sourceU + transform[4] * sourceV + transform[12];
      final y = transform[1] * sourceU + transform[5] * sourceV + transform[13];
      final w = transform[3] * sourceU + transform[7] * sourceV + transform[15];
      return Offset(x / w, y / w);
    }

    final base = projected(1);
    final doubled = projected(2);
    expect(doubled.dx, closeTo(base.dx, 1e-8));
    expect(doubled.dy, closeTo(base.dy, 1e-8));
  });

  test('facade homography maps a tile midpoint to direct perspective', () {
    const viewport = Size(360, 640);
    const horizonY = 160.0;
    const cameraHeight = 5.1;
    const focalLength = 420.0;
    const cameraTargetDepth = 6.4;
    const cameraBackDistance = 6.0;
    const cameraHeading = .61;
    const cameraOriginLateral = -1.3;
    const cameraOriginDepth = 11.7;
    const facadeHeading = 1.03;
    const wallLength = TempleRunArt.wallTileLengthMeters;
    const sourceWidth = 512.0;
    const sourceHeight = 384.0;
    const wallHeight = TempleRunArt.facadeHeightMeters;
    const sourceU = 237.25;
    const sourceV = 181.75;
    final transform = TempleRunFacadeHomography.build(
      viewport: viewport,
      horizonY: horizonY,
      cameraHeight: cameraHeight,
      focalLength: focalLength,
      cameraTargetDepth: cameraTargetDepth,
      cameraBackDistance: cameraBackDistance,
      cameraHeading: cameraHeading,
      cameraOriginLateral: cameraOriginLateral,
      cameraOriginDepth: cameraOriginDepth,
      facadeHeading: facadeHeading,
      wallLength: wallLength,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      wallHeight: wallHeight,
    );
    final homogeneousX =
        transform[0] * sourceU + transform[4] * sourceV + transform[12];
    final homogeneousY =
        transform[1] * sourceU + transform[5] * sourceV + transform[13];
    final homogeneousW =
        transform[3] * sourceU + transform[7] * sourceV + transform[15];
    final matrixPoint = Offset(
      homogeneousX / homogeneousW,
      homogeneousY / homogeneousW,
    );

    final pixelsToMeters = wallLength / sourceWidth;
    final uMeters = sourceU * pixelsToMeters;
    final relativeHeading = facadeHeading - cameraHeading;
    final depth = cameraOriginDepth + uMeters * math.cos(relativeHeading);
    final lateral = cameraOriginLateral + uMeters * math.sin(relativeHeading);
    final worldHeight = wallHeight * (1 - sourceV / sourceHeight);
    final focal = focalLength * cameraTargetDepth / cameraBackDistance;
    final directPoint = Offset(
      viewport.width / 2 + focal * lateral / depth,
      horizonY + focal * (cameraHeight - worldHeight) / depth,
    );
    expect(matrixPoint.dx, closeTo(directPoint.dx, 1e-8));
    expect(matrixPoint.dy, closeTo(directPoint.dy, 1e-8));
  });

  test('settled perspective narrows toward the horizon', () {
    const viewport = Size(360, 640);
    final art = TempleRunArt(
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
    );
    art.updateScene(
      course: _emptyCourse(),
      distanceMeters: 0,
      lane: TempleRunRules.centerLane,
      visualLane: TempleRunRules.centerLane.toDouble(),
      jumpRemaining: 0,
      slideRemaining: 0,
      runnerFrame: 0,
      activeTurn: null,
      bendProgress: 0,
      bendDirection: null,
      completedTurnCount: 0,
      guardianVisible: false,
      failureVisible: false,
      shieldVisible: false,
      boostVisible: false,
    );
    final near = art.project(0);
    final far = art.project(100);
    expect(near.roadWidth, greaterThan(far.roadWidth));
    expect(near.center.dy, greaterThan(far.center.dy));
    for (final value in [
      near.center.dx,
      near.center.dy,
      near.scale,
      near.depth,
      near.roadWidth,
      far.center.dx,
      far.center.dy,
      far.scale,
      far.depth,
      far.roadWidth,
    ]) {
      expect(value.isFinite, isTrue, reason: 'projection value was $value');
    }
  });

  test('prototype captures render finite route geometry', () async {
    final captures = <({String name, Size size, _ArtState state})>[
      (
        name: 'straight_short',
        size: const Size(360, 640),
        state: _ArtState.straight,
      ),
      (
        name: 'approach_short',
        size: const Size(360, 640),
        state: _ArtState.leftApproach,
      ),
      (
        name: 'midturn_short',
        size: const Size(360, 640),
        state: _ArtState.leftMidturn,
      ),
      (
        name: 'afterturn_short',
        size: const Size(360, 640),
        state: _ArtState.leftAfterturn,
      ),
      (
        name: 'right_approach_short',
        size: const Size(360, 640),
        state: _ArtState.rightApproach,
      ),
      (
        name: 'right_midturn_short',
        size: const Size(360, 640),
        state: _ArtState.rightMidturn,
      ),
      (
        name: 'right_afterturn_short',
        size: const Size(360, 640),
        state: _ArtState.rightAfterturn,
      ),
      (
        name: 'straight_tall',
        size: const Size(360, 820),
        state: _ArtState.straight,
      ),
      (
        name: 'approach_tall',
        size: const Size(360, 820),
        state: _ArtState.leftApproach,
      ),
      (
        name: 'midturn_tall',
        size: const Size(360, 820),
        state: _ArtState.leftMidturn,
      ),
      (
        name: 'afterturn_tall',
        size: const Size(360, 820),
        state: _ArtState.leftAfterturn,
      ),
      (
        name: 'right_afterturn_tall',
        size: const Size(360, 820),
        state: _ArtState.rightAfterturn,
      ),
    ];

    for (final capture in captures) {
      final art = TempleRunArt(
        viewportWidth: capture.size.width,
        viewportHeight: capture.size.height,
      );
      final course = _captureCourse(capture.state);
      art.updateScene(
        course: course,
        distanceMeters: capture.state.distance,
        lane: TempleRunRules.centerLane,
        visualLane: TempleRunRules.centerLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 2,
        activeTurn: capture.state.activeTurn,
        bendProgress: capture.state.bendProgress,
        bendDirection: capture.state.direction,
        completedTurnCount: capture.state.completedTurns,
        cameraYaw: 0,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, capture.size.width, capture.size.height),
      );
      art.render(canvas);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        capture.size.width.toInt(),
        capture.size.height.toInt(),
      );
      expect(image.width, capture.size.width.toInt());
      expect(image.height, capture.size.height.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, greaterThan(100));
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rgba, isNotNull);
      final pixels = rgba!.buffer.asUint8List(
        rgba.offsetInBytes,
        rgba.offsetInBytes + rgba.lengthInBytes,
      );
      final opaquePixels = Iterable<int>.generate(
        image.width * image.height,
        (index) => pixels[index * 4 + 3],
      ).where((alpha) => alpha > 0).length;
      expect(
        opaquePixels,
        greaterThan(image.width * image.height ~/ 5),
        reason: 'capture ${capture.name} was unexpectedly empty',
      );
      _writeCapture(
        capture.name,
        bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.offsetInBytes + bytes.lengthInBytes,
        ),
      );
      image.dispose();
      picture.dispose();
    }
  });

  test('narrow terrain captures keep only the authored safe strip', () async {
    final captures = [
      (
        name: 'narrow_left_tilt_short',
        size: const Size(360, 640),
        state: _ArtState.straight,
        safeLane: 0,
        narrowStart: 0.0,
        visualLane: null,
        phoneTilt: -1.0,
      ),
      (
        name: 'narrow_right_turn_short',
        size: const Size(360, 640),
        state: _ArtState.leftApproach,
        safeLane: 2,
        narrowStart: 46.0,
        visualLane: 1.7,
        phoneTilt: .7,
      ),
    ];
    for (final capture in captures) {
      final art = TempleRunArt(
        viewportWidth: capture.size.width,
        viewportHeight: capture.size.height,
      );
      final state = capture.state;
      art.updateScene(
        course: _captureCourse(
          state,
          narrowLane: capture.safeLane,
          narrowStart: capture.narrowStart,
        ),
        distanceMeters: state.distance,
        lane: TempleRunRules.centerLane,
        visualLane: capture.visualLane,
        phoneTilt: capture.phoneTilt,
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 1,
        activeTurn: state.activeTurn,
        bendProgress: state.bendProgress,
        bendDirection: state.direction,
        completedTurnCount: state.completedTurns,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
      );
      final bytes = await _renderPng(art, capture.size);
      expect(bytes.length, greaterThan(100));
      _writeCapture(capture.name, bytes);
    }
  });

  test('turn branch keeps continuous road through narrow intervals', () async {
    const size = Size(360, 640);
    const turn = TempleRunTurn(
      distanceMeters: 20,
      direction: TempleRunTurnDirection.left,
      windowStartMeters: 10,
      windowEndMeters: 24,
    );
    final course = TempleRunCourse(
      obstacles: const [
        TempleRunObstacle(
          distanceMeters: 21.7,
          lane: TempleRunRules.firstLane,
          kind: TempleRunObstacleKind.narrowPath,
          lengthMeters: 1.5,
        ),
      ],
      coins: const [],
      powerUps: const [],
      turns: const [turn],
      totalDistanceMeters: 80,
    );
    final art = TempleRunArt(
      viewportWidth: size.width,
      viewportHeight: size.height,
    );
    art.updateScene(
      course: course,
      distanceMeters: 0,
      lane: TempleRunRules.centerLane,
      visualLane: TempleRunRules.centerLane.toDouble(),
      jumpRemaining: 0,
      slideRemaining: 0,
      runnerFrame: 0,
      activeTurn: turn,
      bendProgress: 0,
      bendDirection: null,
      completedTurnCount: 0,
      guardianVisible: false,
      failureVisible: false,
      shieldVisible: false,
      boostVisible: false,
    );
    final rgba = await _renderRgba(art, size);
    _writeCapture('branch_narrow_boundary_short', await _renderPng(art, size));

    // Sample the unsafe center lane 2.4m into the future outgoing branch while
    // the runner still faces the incoming leg. Project its world point
    // independently so the regression follows camera changes without relying
    // on the renderer's own projection helper.
    final focal = size.width * 1.23;
    final cameraHeight = math.min(
      (size.height * .884 - size.height * .29) * 6 / focal,
      5.0,
    );
    final horizon = size.height * .884 - cameraHeight * focal / 6;
    const worldLateral = -2.4;
    const worldForward = 20.0;
    const cameraForward = -6.0;
    final depth = worldForward - cameraForward;
    final sampleX = size.width / 2 + worldLateral * focal / depth;
    final sampleY = horizon + cameraHeight * focal / depth;
    final pixel = (sampleY.round() * size.width.toInt() + sampleX.round()) * 4;
    expect(rgba[pixel], greaterThan(200));
    expect(rgba[pixel + 1], greaterThan(200));
    expect(rgba[pixel + 2], greaterThan(200));
  });
}

enum _ArtState {
  straight(0, 0, null, 0),
  leftApproach(47, 1, TempleRunTurnDirection.left, 0),
  leftMidturn(54.2, .5, TempleRunTurnDirection.left, 1),
  leftAfterturn(62, 0, TempleRunTurnDirection.left, 1),
  rightApproach(47, 1, TempleRunTurnDirection.right, 0),
  rightMidturn(54.2, .5, TempleRunTurnDirection.right, 1),
  rightAfterturn(62, 0, TempleRunTurnDirection.right, 1);

  const _ArtState(
    this.distance,
    this.bendProgress,
    this.direction,
    this.completedTurns,
  );

  final double distance;
  final double bendProgress;
  final TempleRunTurnDirection? direction;
  final int completedTurns;

  TempleRunTurn? get activeTurn => switch (this) {
    _ArtState.straight => null,
    _ArtState.leftApproach ||
    _ArtState.leftMidturn ||
    _ArtState.leftAfterturn => _turn(TempleRunTurnDirection.left),
    _ArtState.rightApproach ||
    _ArtState.rightMidturn ||
    _ArtState.rightAfterturn => _turn(TempleRunTurnDirection.right),
  };

  TempleRunTurn get turn => _turn(direction ?? TempleRunTurnDirection.left);
}

TempleRunTurn _turn(TempleRunTurnDirection direction) => TempleRunTurn(
  distanceMeters: 54,
  direction: direction,
  windowStartMeters: 35,
  windowEndMeters: 58,
);

TempleRunCourse _geometryCourse(TempleRunTurnDirection firstDirection) {
  final secondDirection = firstDirection == TempleRunTurnDirection.left
      ? TempleRunTurnDirection.right
      : TempleRunTurnDirection.left;
  return TempleRunCourse(
    obstacles: const [],
    coins: const [],
    powerUps: const [],
    turns: [
      TempleRunTurn(
        distanceMeters: 20,
        direction: firstDirection,
        windowStartMeters: 10,
        windowEndMeters: 24,
      ),
      TempleRunTurn(
        distanceMeters: 40,
        direction: secondDirection,
        windowStartMeters: 30,
        windowEndMeters: 44,
      ),
    ],
    totalDistanceMeters: 100,
  );
}

TempleRunCourse _emptyCourse() => TempleRunCourse(
  obstacles: const [],
  coins: const [],
  powerUps: const [],
  turns: const [],
  totalDistanceMeters: 100,
);

void _updateGeometryScene(
  TempleRunArt art, {
  required TempleRunCourse course,
  required double distanceMeters,
  required int completedTurns,
  double bendProgress = 0,
  TempleRunTurnDirection? bendDirection,
  TempleRunTurn? activeTurn,
}) {
  art.updateScene(
    course: course,
    distanceMeters: distanceMeters,
    lane: TempleRunRules.centerLane,
    visualLane: TempleRunRules.centerLane.toDouble(),
    jumpRemaining: 0,
    slideRemaining: 0,
    runnerFrame: 0,
    activeTurn: activeTurn,
    bendProgress: bendProgress,
    bendDirection: bendDirection,
    completedTurnCount: completedTurns,
    guardianVisible: false,
    failureVisible: false,
    shieldVisible: false,
    boostVisible: false,
  );
}

double _crossForTest(Offset first, Offset second) =>
    first.dx * second.dy - first.dy * second.dx;

Offset _forwardForTest(double heading) =>
    Offset(math.sin(heading), math.cos(heading));

Offset _rightForTest(double heading) =>
    Offset(math.cos(heading), -math.sin(heading));

double _dotForTest(Offset first, Offset second) =>
    first.dx * second.dx + first.dy * second.dy;

double _turnRadiansForTest(TempleRunTurnDirection direction) =>
    direction == TempleRunTurnDirection.left ? -math.pi / 2 : math.pi / 2;

({Offset position, double heading}) _routeAtTurn(
  TempleRunCourse course,
  int turnIndex,
) {
  var position = Offset.zero;
  var heading = 0.0;
  var segmentStart = 0.0;
  for (var index = 0; index <= turnIndex; index++) {
    final turn = course.turns[index];
    position += _forwardForTest(heading) * (turn.distanceMeters - segmentStart);
    if (index == turnIndex) {
      return (position: position, heading: heading);
    }
    segmentStart = turn.distanceMeters;
    heading += _turnRadiansForTest(turn.direction);
  }
  throw StateError('Turn index $turnIndex was not found.');
}

bool _insideInsetLCorridor(
  Offset point,
  Offset junction,
  double incomingHeading,
  double outgoingHeading,
  double wallOffset,
) {
  final relative = point - junction;
  final incomingLateral = _dotForTest(
    relative,
    _rightForTest(incomingHeading),
  ).abs();
  final outgoingLateral = _dotForTest(
    relative,
    _rightForTest(outgoingHeading),
  ).abs();
  final incomingLongitudinal = _dotForTest(
    relative,
    _forwardForTest(incomingHeading),
  );
  final outgoingLongitudinal = _dotForTest(
    relative,
    _forwardForTest(outgoingHeading),
  );
  final insideIncomingLeg =
      incomingLateral <= wallOffset + .001 &&
      incomingLongitudinal <= wallOffset;
  final insideOutgoingLeg =
      outgoingLateral <= wallOffset + .001 &&
      outgoingLongitudinal >= -wallOffset;
  return insideIncomingLeg || insideOutgoingLeg;
}

bool _insideConvexPolygon(List<Offset> polygon, Offset point) {
  var hasPositive = false;
  var hasNegative = false;
  for (var index = 0; index < polygon.length; index++) {
    final first = polygon[index];
    final second = polygon[(index + 1) % polygon.length];
    final cross = _crossForTest(second - first, point - first);
    if (cross > .000001) hasPositive = true;
    if (cross < -.000001) hasNegative = true;
  }
  return !(hasPositive && hasNegative);
}

void _expectRunnerFoot(TempleRunProjection projection, Size viewport) {
  expect(projection.center.dx, closeTo(viewport.width / 2, .001));
  expect(projection.center.dy, closeTo(viewport.height * .884, .001));
}

void _expectFiniteProjection(TempleRunProjection projection) {
  for (final value in [
    projection.center.dx,
    projection.center.dy,
    projection.scale,
    projection.depth,
    projection.roadWidth,
  ]) {
    expect(value.isFinite, isTrue, reason: 'projection value was $value');
  }
}

TempleRunProjection _projectionFor({
  required TempleRunCourse course,
  required Size viewport,
  required double distanceMeters,
  required int completedTurnCount,
  double? visualLane,
  double phoneTilt = 0,
}) {
  final art = TempleRunArt(
    viewportWidth: viewport.width,
    viewportHeight: viewport.height,
  );
  art.updateScene(
    course: course,
    distanceMeters: distanceMeters,
    lane: TempleRunRules.centerLane,
    visualLane: visualLane,
    phoneTilt: phoneTilt,
    jumpRemaining: 0,
    slideRemaining: 0,
    runnerFrame: 0,
    activeTurn: null,
    bendProgress: 0,
    bendDirection: null,
    cameraYaw: .25,
    completedTurnCount: completedTurnCount,
    guardianVisible: false,
    failureVisible: false,
    shieldVisible: false,
    boostVisible: false,
  );
  return art.project(0);
}

TempleRunCourse _captureCourse(
  _ArtState state, {
  int? narrowLane,
  double narrowStart = 0,
}) {
  final obstacles = <TempleRunObstacle>[
    TempleRunObstacle(
      id: 1,
      distanceMeters: 18,
      lane: TempleRunRules.centerLane,
      kind: TempleRunObstacleKind.hurdle,
    ),
    TempleRunObstacle(
      id: 2,
      distanceMeters: 26,
      lane: TempleRunRules.centerLane,
      kind: TempleRunObstacleKind.arch,
    ),
    TempleRunObstacle(
      id: 3,
      distanceMeters: 34,
      lane: TempleRunRules.centerLane,
      kind: TempleRunObstacleKind.rubble,
    ),
    TempleRunObstacle(
      id: 4,
      distanceMeters: 42,
      lane: TempleRunRules.centerLane,
      kind: TempleRunObstacleKind.gap,
      span: TempleRunObstacleSpan.fullRoad,
    ),
  ];
  if (narrowLane != null) {
    obstacles.add(
      TempleRunObstacle(
        id: 5,
        distanceMeters: narrowStart,
        lane: narrowLane,
        kind: TempleRunObstacleKind.narrowPath,
        lengthMeters: TempleRunRules.narrowPathLengthMeters,
      ),
    );
  }
  return TempleRunCourse(
    obstacles: obstacles,
    coins: const [
      TempleRunCoin(distanceMeters: 10, lane: 1),
      TempleRunCoin(distanceMeters: 16, lane: 1),
      TempleRunCoin(distanceMeters: 22, lane: 1),
      TempleRunCoin(distanceMeters: 62, lane: 1),
    ],
    powerUps: const [
      TempleRunPowerUp(
        distanceMeters: 30,
        lane: TempleRunRules.centerLane,
        kind: TempleRunPowerUpKind.shield,
      ),
    ],
    turns: [state.turn],
    totalDistanceMeters: 120,
  );
}

Future<Uint8List> _renderPng(TempleRunArt art, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
  art.render(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.offsetInBytes + bytes.lengthInBytes,
  );
}

Future<Uint8List> _renderRgba(TempleRunArt art, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
  art.render(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.offsetInBytes + bytes.lengthInBytes,
  );
}

void _writeCapture(String name, Uint8List bytes) {
  final directory = Directory('artifacts/temple_run/prototype/geometry');
  directory.createSync(recursive: true);
  File('${directory.path}/$name.png').writeAsBytesSync(bytes);
}
