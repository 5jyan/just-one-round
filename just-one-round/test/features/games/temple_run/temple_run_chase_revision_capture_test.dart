import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'starts with the normal camera and keeps pursuit centered through turns',
    () async {
      final fontLoader = FontLoader('Galmuri')
        ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
      await fontLoader.load();
      final images = await TempleRunArt.loadImageAssets();
      final course = _course();
      try {
        final countdown = _art(images)
          ..updateScene(
            course: course,
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
            guardianVisible: true,
            pursuersVisible: false,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
          );
        final normal = _art(images)
          ..updateScene(
            course: course,
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
            pursuersVisible: false,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
          );
        expect(countdown.cameraHeadingForTesting, closeTo(0, 1e-8));
        expect(
          countdown.cameraPositionForTesting,
          normal.cameraPositionForTesting,
          reason: 'countdown uses the normal chase camera from its first frame',
        );
        final countdownImage = await _render(
          countdown,
          TempleRunRules.logicalHeight,
        );
        expect(
          countdown.pursuerBoundsForTesting,
          hasLength(2),
          reason: 'the countdown reveals the centered pursuit pair',
        );
        await _writeCapture(
          countdownImage,
          'chase_countdown_normal_camera',
          TempleRunRules.logicalHeight,
        );

        final departing = _art(images)
          ..updateScene(
            course: course,
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
            pursuersVisible: true,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
            deltaSeconds: .4,
          );
        expect(
          departing.pursuerDepartureProgressForTesting,
          closeTo(.25, .0001),
        );
        final departingImage = await _render(
          departing,
          TempleRunRules.logicalHeight,
        );
        expect(departing.pursuerBoundsForTesting, hasLength(2));
        await _writeCapture(
          departingImage,
          'chase_departing_400ms',
          TempleRunRules.logicalHeight,
        );

        departing.updateScene(
          course: course,
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
          pursuersVisible: true,
          failureVisible: false,
          shieldVisible: false,
          boostVisible: false,
          deltaSeconds: 1.2,
        );
        expect(
          departing.pursuerDepartureProgressForTesting,
          closeTo(1, .0001),
        );
        final departedImage = await _render(
          departing,
          TempleRunRules.logicalHeight,
        );
        expect(departing.pursuerBoundsForTesting, isEmpty);
        await _writeCapture(
          departedImage,
          'chase_departed_1600ms',
          TempleRunRules.logicalHeight,
        );

        final scenarios = <_ChaseFrame>[
          const _ChaseFrame('chase_left_normal_short_outer', 10, 0, 800),
          const _ChaseFrame('chase_right_normal_tall_outer', 10, 2, 980),
          const _ChaseFrame(
            'chase_left_midturn_short_outer',
            22,
            0,
            800,
            activeTurnIndex: 0,
            bendProgress: .5,
            bendDirection: TempleRunTurnDirection.left,
            completedTurnCount: 1,
          ),
          const _ChaseFrame(
            'chase_right_midturn_tall_outer',
            52,
            2,
            980,
            activeTurnIndex: 1,
            bendProgress: .5,
            bendDirection: TempleRunTurnDirection.right,
            completedTurnCount: 2,
          ),
          const _ChaseFrame(
            'chase_left_postturn_tall_outer',
            24,
            0,
            980,
            bendDirection: TempleRunTurnDirection.left,
            completedTurnCount: 1,
          ),
          const _ChaseFrame(
            'chase_right_postturn_short_outer',
            54,
            2,
            800,
            bendDirection: TempleRunTurnDirection.right,
            completedTurnCount: 2,
          ),
        ];
        for (final frame in scenarios) {
          final art = _art(images, height: frame.viewportHeight);
          final activeTurn = frame.activeTurnIndex == null
              ? null
              : course.turns[frame.activeTurnIndex!];
          art.updateScene(
            course: course,
            distanceMeters: frame.distance,
            lane: frame.lane,
            visualLane: frame.lane.toDouble(),
            jumpRemaining: 0,
            slideRemaining: 0,
            runnerFrame: frame.distance,
            activeTurn: activeTurn,
            bendProgress: frame.bendProgress,
            bendDirection: frame.bendDirection,
            completedTurnCount: frame.completedTurnCount,
            guardianVisible: false,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
            deltaSeconds: .2,
          );
          expect(
            art.cameraHeadingForTesting,
            closeTo(_expectedHeading(course, frame), 1e-8),
            reason: '${frame.name} camera follows the actual route turn',
          );
          final image = await _render(art, frame.viewportHeight);
          final bounds = art.pursuerBoundsForTesting;
          expect(bounds, isNotEmpty, reason: frame.name);
          expect(
            bounds.every(
              (rect) =>
                  rect.left >= 0 &&
                  rect.right <= TempleRunRules.logicalWidth &&
                  rect.bottom <= frame.viewportHeight &&
                  rect.height > 0,
            ),
            isTrue,
            reason: '${frame.name} bounds stay in the viewport',
          );
          expect(
            (bounds.map((rect) => rect.left).reduce(math.min) +
                    bounds.map((rect) => rect.right).reduce(math.max)) /
                2,
            closeTo(TempleRunRules.logicalWidth / 2, .01),
            reason: '${frame.name} keeps the pursuer pair centered on screen',
          );
          if (frame.activeTurnIndex == null) {
            final hiddenArt = _art(images, height: frame.viewportHeight);
            hiddenArt.updateScene(
              course: course,
              distanceMeters: frame.distance,
              lane: frame.lane,
              visualLane: frame.lane.toDouble(),
              jumpRemaining: 0,
              slideRemaining: 0,
              runnerFrame: frame.distance,
              activeTurn: null,
              bendProgress: frame.bendProgress,
              bendDirection: frame.bendDirection,
              completedTurnCount: frame.completedTurnCount,
              guardianVisible: false,
              pursuersVisible: false,
              failureVisible: false,
              shieldVisible: false,
              boostVisible: false,
              deltaSeconds: .2,
            );
            final hiddenImage = await _render(hiddenArt, frame.viewportHeight);
            try {
              expect(
                await _countLowerDifference(image, hiddenImage),
                greaterThan(0),
                reason: '${frame.name} draws pursuer pixels after turns settle',
              );
            } finally {
              hiddenImage.dispose();
            }
          }
          await _writeCapture(image, frame.name, frame.viewportHeight);
        }

        final generated = TempleRunCourseGenerator(math.Random(17)).generate();
        const timeViews = [
          (seconds: 0.0, lane: 1.0),
          (seconds: 8.0, lane: 0.0),
          (seconds: 90.0, lane: 2.0),
          (seconds: 250.0, lane: 1.0),
        ];
        for (final view in timeViews) {
          final seconds = view.seconds;
          final distance = TempleRunRules.distanceForGeneration(seconds);
          final completed = generated.turns
              .where((turn) => turn.distanceMeters <= distance)
              .length;
          final active =
              completed < generated.turns.length &&
                  generated.turns[completed].contains(distance)
              ? generated.turns[completed]
              : null;
          final heading = completed == 0
              ? null
              : generated.turns[completed - 1].direction;
          final art = _art(images);
          art.updateScene(
            course: generated,
            distanceMeters: distance,
            lane: TempleRunRules.centerLane,
            visualLane: view.lane,
            jumpRemaining: 0,
            slideRemaining: 0,
            runnerFrame: seconds * 8,
            activeTurn: active,
            bendProgress: 0,
            bendDirection: heading,
            completedTurnCount: completed,
            guardianVisible: seconds == 0,
            pursuersVisible: seconds > 0,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
            deltaSeconds: seconds,
          );
          final image = await _render(art, TempleRunRules.logicalHeight);
          if (seconds == 0) {
            expect(art.pursuerBoundsForTesting, hasLength(2));
          } else if (seconds >= 2) {
            expect(
              art.pursuerBoundsForTesting,
              isEmpty,
              reason: 'the pursuit pair has receded after the opening beat',
            );
          } else {
            final bounds = art.pursuerBoundsForTesting;
            expect(bounds, isNotEmpty);
            expect(
              (bounds.map((rect) => rect.left).reduce(math.min) +
                      bounds.map((rect) => rect.right).reduce(math.max)) /
                  2,
              closeTo(TempleRunRules.logicalWidth / 2, .01),
              reason: 'generated ${seconds}s view keeps the group centered',
            );
          }
          final hiddenArt = _art(images)
            ..updateScene(
              course: generated,
              distanceMeters: distance,
              lane: TempleRunRules.centerLane,
              visualLane: view.lane,
              jumpRemaining: 0,
              slideRemaining: 0,
              runnerFrame: seconds * 8,
              activeTurn: active,
              bendProgress: 0,
              bendDirection: heading,
              completedTurnCount: completed,
              guardianVisible: seconds == 0,
              pursuersVisible: false,
              failureVisible: false,
              shieldVisible: false,
              boostVisible: false,
              deltaSeconds: seconds,
            );
          if (seconds > 0 && seconds < 2) {
            final hiddenImage = await _render(
              hiddenArt,
              TempleRunRules.logicalHeight,
            );
            try {
              expect(
                await _countLowerDifference(image, hiddenImage),
                greaterThan(0),
                reason: 'generated route at ${seconds}s draws chasers',
              );
            } finally {
              hiddenImage.dispose();
            }
          } else if (seconds >= 2) {
            final hiddenImage = await _render(
              hiddenArt,
              TempleRunRules.logicalHeight,
            );
            try {
              expect(
                await _countLowerDifference(image, hiddenImage),
                0,
                reason: 'the receded pursuit pair leaves no lower-screen mark',
              );
            } finally {
              hiddenImage.dispose();
            }
          }
          await _writeCapture(
            image,
            'chase_generated_${seconds.toInt()}s_lane_${view.lane.toInt()}',
            TempleRunRules.logicalHeight,
          );
        }

        for (final direction in TempleRunTurnDirection.values) {
          final turnIndex = generated.turns.indexWhere(
            (turn) => turn.direction == direction,
          );
          expect(turnIndex, greaterThanOrEqualTo(0));
          final turn = generated.turns[turnIndex];
          final elapsed = TempleRunRules.elapsedForGenerationDistance(
            turn.distanceMeters,
          );
          final speed = TempleRunRules.speedForElapsed(elapsed);
          const lane = 1.0;
          final art = _art(images);
          ui.Image? previousFrame;
          for (final progress in [1.0, .75, .5, .25, 0.0]) {
            final distance = turn.distanceMeters + speed * .18 * (1 - progress);
            art.updateScene(
              course: generated,
              distanceMeters: distance,
              lane: TempleRunRules.centerLane,
              visualLane: lane,
              jumpRemaining: 0,
              slideRemaining: 0,
              runnerFrame: 0,
              activeTurn: turn,
              bendProgress: progress,
              bendDirection: direction,
              completedTurnCount: turnIndex + 1,
              guardianVisible: false,
              pursuersVisible: true,
              failureVisible: false,
              shieldVisible: false,
              boostVisible: false,
              deltaSeconds: .125,
            );
            final image = await _render(art, TempleRunRules.logicalHeight);
            expect(art.pursuerBoundsForTesting, hasLength(2));
            if (previousFrame != null) {
              expect(
                await _countLowerDifference(image, previousFrame),
                greaterThan(0),
                reason: '${direction.name} advances one 125ms running frame',
              );
              previousFrame.dispose();
            }
            await _writeCaptureWithoutDisposing(
              image,
              'generated_${direction.name}_turn_frame_${(progress * 100).round().toString().padLeft(3, '0')}_lane_${lane.toInt()}',
            );
            previousFrame = image;
          }
          previousFrame?.dispose();
        }

        final arrived = _art(images)
          ..updateScene(
            course: course,
            distanceMeters: course.totalDistanceMeters,
            lane: TempleRunRules.centerLane,
            visualLane: TempleRunRules.centerLane.toDouble(),
            jumpRemaining: 0,
            slideRemaining: 0,
            runnerFrame: 0,
            activeTurn: null,
            bendProgress: 0,
            bendDirection: null,
            completedTurnCount: course.turns.length,
            guardianVisible: false,
            failureVisible: false,
            arrivalVisible: true,
            shieldVisible: false,
            boostVisible: false,
          );
        final arrivalImage = await _render(
          arrived,
          TempleRunRules.logicalHeight,
        );
        await _writeCapture(
          arrivalImage,
          'chase_arrival_hidden',
          TempleRunRules.logicalHeight,
        );
        expect(arrived.pursuerBoundsForTesting, isEmpty);
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );

  test(
    'captures center-lane chase over near obstacles and all six run frames',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      const obstacleCases = [
        (
          name: 'near_hurdle',
          obstacle: TempleRunObstacle(
            distanceMeters: 7,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.hurdle,
          ),
        ),
        (
          name: 'near_scaffold',
          obstacle: TempleRunObstacle(
            distanceMeters: 7,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.arch,
          ),
        ),
        (
          name: 'near_narrow_bank',
          obstacle: TempleRunObstacle(
            distanceMeters: 4,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.narrowPath,
          ),
        ),
      ];
      try {
        for (final capture in obstacleCases) {
          final course = TempleRunCourse(
            obstacles: [capture.obstacle],
            coins: const [],
            powerUps: const [],
            turns: const [],
            totalDistanceMeters: 60,
          );
          final art = _art(images)
            ..updateScene(
              course: course,
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
              pursuersVisible: true,
              failureVisible: false,
              shieldVisible: false,
              boostVisible: false,
              deltaSeconds: .125,
            );
          final image = await _render(art, TempleRunRules.logicalHeight);
          expect(art.pursuerBoundsForTesting, hasLength(2));
          await _writeCapture(
            image,
            'center_${capture.name}',
            TempleRunRules.logicalHeight,
          );
        }

        // The generated course alternates narrow strips between the legal
        // outer lanes. Capture each real layout with the runner in its safe
        // lane so the omitted unreachable outside sliver and retained thick
        // unsafe bank can be reviewed against the production obstacle path.
        final generated = TempleRunCourseGenerator(math.Random(17)).generate();
        for (final lane in [
          TempleRunRules.firstLane,
          TempleRunRules.lastLane,
        ]) {
          final obstacle = generated.obstacles.firstWhere(
            (candidate) =>
                candidate.kind == TempleRunObstacleKind.narrowPath &&
                candidate.lane == lane,
          );
          final distance = obstacle.distanceMeters - 2.5;
          final completed = generated.turns
              .where((turn) => turn.distanceMeters <= distance)
              .length;
          final active =
              completed < generated.turns.length &&
                  generated.turns[completed].contains(distance)
              ? generated.turns[completed]
              : null;
          final heading = completed == 0
              ? null
              : generated.turns[completed - 1].direction;
          final art = _art(images)
            ..updateScene(
              course: generated,
              distanceMeters: distance,
              lane: lane,
              visualLane: lane.toDouble(),
              jumpRemaining: 0,
              slideRemaining: 0,
              runnerFrame: distance,
              activeTurn: active,
              bendProgress: 0,
              bendDirection: heading,
              completedTurnCount: completed,
              guardianVisible: false,
              pursuersVisible: true,
              failureVisible: false,
              shieldVisible: false,
              boostVisible: false,
              deltaSeconds: .125,
            );
          final image = await _render(art, TempleRunRules.logicalHeight);
          expect(art.pursuerBoundsForTesting, hasLength(2));
          await _writeCapture(
            image,
            'generated_lane_${lane}_narrow_bank_safe_player',
            TempleRunRules.logicalHeight,
          );
        }

        final course = _course();
        final runningArt = _art(images);
        final frames = <ui.Image>[];
        for (var frame = 0; frame < 6; frame++) {
          runningArt.updateScene(
            course: course,
            distanceMeters: 10,
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
            pursuersVisible: true,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
            deltaSeconds: .125,
          );
          final image = await _render(runningArt, TempleRunRules.logicalHeight);
          expect(runningArt.pursuerBoundsForTesting, hasLength(2));
          frames.add(image);
          await _writeCaptureWithoutDisposing(
            image,
            'center_pursuers_running_frame_${frame.toString().padLeft(2, '0')}',
          );
        }
        for (var index = 1; index < frames.length; index++) {
          expect(
            await _countLowerDifference(frames[index - 1], frames[index]),
            greaterThan(0),
            reason: 'the six-cell atlas changes at 8 frames per second',
          );
        }
        for (final image in frames) {
          image.dispose();
        }
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );
}

double _expectedHeading(TempleRunCourse course, _ChaseFrame frame) {
  var heading = 0.0;
  for (var index = 0; index < frame.completedTurnCount; index++) {
    heading += course.turns[index].direction == TempleRunTurnDirection.right
        ? math.pi / 2
        : -math.pi / 2;
  }
  if (frame.activeTurnIndex == null) return heading;
  final index = frame.activeTurnIndex!;
  heading = 0;
  for (var prior = 0; prior < index; prior++) {
    heading += course.turns[prior].direction == TempleRunTurnDirection.right
        ? math.pi / 2
        : -math.pi / 2;
  }
  final direction = course.turns[index].direction;
  final turn = direction == TempleRunTurnDirection.right
      ? math.pi / 2
      : -math.pi / 2;
  final ease = 1 - math.pow(frame.bendProgress.clamp(0.0, 1.0), 3).toDouble();
  return heading + turn * ease;
}

Future<int> _countLowerDifference(ui.Image visible, ui.Image hidden) async {
  final visibleData = await visible.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  final hiddenData = await hidden.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  expect(visibleData, isNotNull);
  expect(hiddenData, isNotNull);
  final visibleBytes = visibleData!.buffer.asUint8List(
    visibleData.offsetInBytes,
    visibleData.offsetInBytes + visibleData.lengthInBytes,
  );
  final hiddenBytes = hiddenData!.buffer.asUint8List(
    hiddenData.offsetInBytes,
    hiddenData.offsetInBytes + hiddenData.lengthInBytes,
  );
  final width = visible.width;
  final startY = (visible.height * .7).floor();
  var changedPixels = 0;
  for (var y = startY; y < visible.height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      if (visibleBytes[offset] != hiddenBytes[offset] ||
          visibleBytes[offset + 1] != hiddenBytes[offset + 1] ||
          visibleBytes[offset + 2] != hiddenBytes[offset + 2]) {
        changedPixels++;
      }
    }
  }
  return changedPixels;
}

class _ChaseFrame {
  const _ChaseFrame(
    this.name,
    this.distance,
    this.lane,
    this.viewportHeight, {
    this.activeTurnIndex,
    this.bendProgress = 0,
    this.bendDirection,
    this.completedTurnCount = 0,
  });

  final String name;
  final double distance;
  final int lane;
  final double viewportHeight;
  final int? activeTurnIndex;
  final double bendProgress;
  final TempleRunTurnDirection? bendDirection;
  final int completedTurnCount;
}

TempleRunArt _art(
  Map<String, ui.Image> images, {
  double height = TempleRunRules.logicalHeight,
}) => TempleRunArt(
  images: images,
  useImageAssets: true,
  viewportWidth: TempleRunRules.logicalWidth,
  viewportHeight: height,
);

TempleRunCourse _course() => TempleRunCourse(
  obstacles: const [],
  coins: const [],
  powerUps: const [],
  turns: const [
    TempleRunTurn(
      distanceMeters: 20,
      direction: TempleRunTurnDirection.left,
      windowStartMeters: 10,
      windowEndMeters: 24,
    ),
    TempleRunTurn(
      distanceMeters: 50,
      direction: TempleRunTurnDirection.right,
      windowStartMeters: 40,
      windowEndMeters: 54,
    ),
  ],
  totalDistanceMeters: 100,
);

Future<ui.Image> _render(TempleRunArt art, double viewportHeight) async {
  final size = Size(TempleRunRules.logicalWidth, viewportHeight);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  art.render(canvas);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size.width.toInt(), size.height.toInt());
  } finally {
    picture.dispose();
  }
}

Future<void> _writeCapture(
  ui.Image image,
  String name,
  double viewportHeight,
) async {
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(bytes, isNotNull);
    final file = File(
      'artifacts/temple_run/chase_revision/${name}_${viewportHeight.toInt()}.png',
    )..createSync(recursive: true);
    file.writeAsBytesSync(
      bytes!.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.offsetInBytes + bytes.lengthInBytes,
      ),
    );
  } finally {
    image.dispose();
  }
}

Future<void> _writeCaptureWithoutDisposing(ui.Image image, String name) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  expect(bytes, isNotNull);
  final file = File(
    'artifacts/temple_run/chase_revision/${name}_${TempleRunRules.logicalHeight.toInt()}.png',
  )..createSync(recursive: true);
  file.writeAsBytesSync(
    bytes!.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.offsetInBytes + bytes.lengthInBytes,
    ),
  );
}
