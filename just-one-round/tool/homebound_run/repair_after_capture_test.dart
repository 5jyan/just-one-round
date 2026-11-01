import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

const _outputPath = 'artifacts/homebound_run/repair_after/renderer';
const _viewport = Size(360, 640);
const _turnDistance = 50.0;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('capture complete image-mode straight and route-distance strips', () async {
    final directory = Directory(_outputPath)..createSync(recursive: true);
    final images = await TempleRunArt.loadImageAssets();
    final manifests = <String, Object?>{};
    try {
      final straightCourse = _course();
      final straight = await _render(images, straightCourse, distance: 20);
      await _write(directory, 'straight_360x640.png', straight);

      Future<void> captureCase(
        String name,
        TempleRunCourse course, {
        double distance = 0,
        int lane = TempleRunRules.centerLane,
        double jumpRemaining = 0,
        double slideRemaining = 0,
        bool guardianVisible = false,
        bool failureVisible = false,
        bool arrivalVisible = false,
        bool shieldVisible = false,
        bool boostVisible = false,
        double runnerFrame = 0,
        Size viewport = _viewport,
      }) async {
        await _write(
          directory,
          '$name.png',
          await _render(
            images,
            course,
            distance: distance,
            lane: lane,
            jumpRemaining: jumpRemaining,
            slideRemaining: slideRemaining,
            guardianVisible: guardianVisible,
            failureVisible: failureVisible,
            arrivalVisible: arrivalVisible,
            shieldVisible: shieldVisible,
            boostVisible: boostVisible,
            runnerFrame: runnerFrame,
            viewport: viewport,
          ),
        );
      }

      for (final lane in [TempleRunRules.firstLane, TempleRunRules.lastLane]) {
        final narrowCourse = _course(
          obstacles: [
            TempleRunObstacle(
              distanceMeters: 8,
              lane: lane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathLengthMeters,
            ),
          ],
        );
        for (final point in [
          (name: 'before', distance: 7.8),
          (name: 'inside', distance: 11.0),
          (name: 'exit', distance: 14.2),
        ]) {
          await captureCase(
            'narrow_lane_${lane}_${point.name}',
            narrowCourse,
            distance: point.distance,
            lane: lane,
          );
        }
      }

      final hurdleCourse = _course(
        obstacles: [
          TempleRunObstacle(
            distanceMeters: 8,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.hurdle,
            span: TempleRunObstacleSpan.fullRoad,
          ),
        ],
      );
      await captureCase(
        'hurdle_jump_approach',
        hurdleCourse,
        distance: 6.4,
        jumpRemaining: .24,
      );
      await captureCase(
        'hurdle_jump_contact',
        hurdleCourse,
        distance: 8,
        jumpRemaining: .18,
      );

      final gapCourse = _course(
        obstacles: [
          TempleRunObstacle(
            distanceMeters: 8,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.gap,
            span: TempleRunObstacleSpan.fullRoad,
          ),
        ],
      );
      await captureCase(
        'gap_jump_contact',
        gapCourse,
        distance: 8,
        jumpRemaining: .18,
      );

      final rubbleCourse = _course(
        obstacles: [
          TempleRunObstacle(
            distanceMeters: 8,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.rubble,
          ),
        ],
      );
      await captureCase('rubble_approach', rubbleCourse, distance: 6.4);
      await captureCase('rubble_contact', rubbleCourse, distance: 8);

      final shutterCourse = _course(
        obstacles: [
          TempleRunObstacle(
            distanceMeters: 8,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.arch,
            span: TempleRunObstacleSpan.fullRoad,
          ),
        ],
      );
      await captureCase(
        'shutter_slide_contact',
        shutterCourse,
        distance: 8,
        slideRemaining: .2,
      );

      final pickupCourse = _course(
        coins: const [
          TempleRunCoin(distanceMeters: 8, lane: 0),
          TempleRunCoin(distanceMeters: 9, lane: 1),
          TempleRunCoin(distanceMeters: 10, lane: 2),
        ],
        powerUps: const [
          TempleRunPowerUp(
            distanceMeters: 6,
            lane: 1,
            kind: TempleRunPowerUpKind.magnet,
          ),
          TempleRunPowerUp(
            distanceMeters: 12,
            lane: 1,
            kind: TempleRunPowerUpKind.shield,
          ),
        ],
      );
      await captureCase(
        'pickups',
        pickupCourse,
        shieldVisible: true,
        boostVisible: true,
      );
      await captureCase('failure', _course(), failureVisible: true);
      await captureCase(
        'arrival',
        _course(totalDistance: 8),
        arrivalVisible: true,
      );

      final runFrames = <Uint8List>[];
      for (var frame = 0; frame < 4; frame++) {
        runFrames.add(
          await _render(
            images,
            _course(),
            distance: 20,
            runnerFrame: frame.toDouble(),
          ),
        );
      }
      await _write(
        directory,
        'runner_run_loop_4frames.png',
        await _filmstrip(runFrames),
      );

      final jumpFrames = <Uint8List>[];
      for (final fraction in [0.0, .25, .5, .75, .95]) {
        jumpFrames.add(
          await _render(
            images,
            _course(),
            distance: 20,
            jumpRemaining: TempleRunRules.jumpDurationSeconds * (1 - fraction),
          ),
        );
      }
      await _write(
        directory,
        'runner_jump_5moments.png',
        await _filmstrip(jumpFrames),
      );

      final slideFrames = <Uint8List>[];
      for (final fraction in [0.0, .25, .5, .75, .95]) {
        slideFrames.add(
          await _render(
            images,
            _course(),
            distance: 20,
            slideRemaining:
                TempleRunRules.slideDurationSeconds * (1 - fraction),
          ),
        );
      }
      await _write(
        directory,
        'runner_slide_5moments.png',
        await _filmstrip(slideFrames),
      );

      final distances = [46.0, 49.5, 50.1, 51.5, 53.0, 56.0, 59.0];
      for (final direction in TempleRunTurnDirection.values) {
        final turn = TempleRunTurn(
          distanceMeters: _turnDistance,
          direction: direction,
          windowStartMeters: _turnDistance - 8,
          windowEndMeters: _turnDistance + 4,
        );
        final course = _course(turns: [turn]);
        for (final lane in [
          TempleRunRules.centerLane,
          TempleRunRules.firstLane,
          TempleRunRules.lastLane,
        ]) {
          final frames = <Uint8List>[];
          final states = <Map<String, Object?>>[];
          for (final distance in distances) {
            final hasTurned = distance > _turnDistance;
            final turnProgress = hasTurned
                ? (1 - (distance - _turnDistance) / (8 * .35))
                      .clamp(0.0, 1.0)
                      .toDouble()
                : 0.0;
            final bytes = await _render(
              images,
              course,
              distance: distance,
              lane: lane,
              completedTurns: hasTurned ? 1 : 0,
              activeTurn: hasTurned ? null : turn,
              bendProgress: turnProgress,
              bendDirection: hasTurned ? direction : null,
              runnerFrame: distance,
            );
            frames.add(bytes);
            final name =
                'turn_${direction.name}_lane_${lane}_d${distance.toStringAsFixed(1)}.png';
            await _write(directory, name, bytes);
            states.add({
              'distanceMeters': distance,
              'completedTurns': hasTurned ? 1 : 0,
              'visualLane': lane,
              'bendProgress': turnProgress,
            });
          }
          final stripName = 'turn_${direction.name}_lane_${lane}_route.png';
          await _write(directory, stripName, await _filmstrip(frames));
          manifests[stripName] = {
            'lane': lane,
            'direction': direction.name,
            'states': states,
          };
        }
      }

      const tallViewport = Size(360, 820);
      final tallStraight = await _render(
        images,
        straightCourse,
        distance: 20,
        viewport: tallViewport,
      );
      await _write(directory, 'tall_straight_360x820.png', tallStraight);

      for (final lane in [TempleRunRules.firstLane, TempleRunRules.lastLane]) {
        for (final point in [
          (name: 'before', distance: 7.8),
          (name: 'inside', distance: 11.0),
          (name: 'exit', distance: 14.2),
        ]) {
          final narrowCourse = _course(
            obstacles: [
              TempleRunObstacle(
                distanceMeters: 8,
                lane: lane,
                kind: TempleRunObstacleKind.narrowPath,
                lengthMeters: TempleRunRules.narrowPathLengthMeters,
              ),
            ],
          );
          await captureCase(
            'tall_narrow_lane_${lane}_${point.name}',
            narrowCourse,
            distance: point.distance,
            lane: lane,
            viewport: tallViewport,
          );
        }
      }

      for (final direction in TempleRunTurnDirection.values) {
        final turn = TempleRunTurn(
          distanceMeters: _turnDistance,
          direction: direction,
          windowStartMeters: _turnDistance - 8,
          windowEndMeters: _turnDistance + 4,
        );
        final course = _course(turns: [turn]);
        for (final lane in [
          TempleRunRules.firstLane,
          TempleRunRules.lastLane,
        ]) {
          final frames = <Uint8List>[];
          for (final distance in distances) {
            final hasTurned = distance > _turnDistance;
            final turnProgress = hasTurned
                ? (1 - (distance - _turnDistance) / (8 * .35))
                      .clamp(0.0, 1.0)
                      .toDouble()
                : 0.0;
            final bytes = await _render(
              images,
              course,
              distance: distance,
              lane: lane,
              completedTurns: hasTurned ? 1 : 0,
              activeTurn: hasTurned ? null : turn,
              bendProgress: turnProgress,
              bendDirection: hasTurned ? direction : null,
              runnerFrame: distance,
              viewport: tallViewport,
            );
            frames.add(bytes);
            final name =
                'tall_turn_${direction.name}_lane_${lane}_d${distance.toStringAsFixed(1)}.png';
            await _write(directory, name, bytes);
          }
          await _write(
            directory,
            'tall_turn_${direction.name}_lane_${lane}_route.png',
            await _filmstrip(frames),
          );
        }
      }

      final tallHurdle = _course(
        obstacles: [
          TempleRunObstacle(
            distanceMeters: 8,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.hurdle,
            span: TempleRunObstacleSpan.fullRoad,
          ),
        ],
      );
      await captureCase(
        'tall_hurdle_jump_contact',
        tallHurdle,
        distance: 8,
        jumpRemaining: .18,
        viewport: tallViewport,
      );
      final tallShutter = _course(
        obstacles: [
          TempleRunObstacle(
            distanceMeters: 8,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.arch,
            span: TempleRunObstacleSpan.fullRoad,
          ),
        ],
      );
      await captureCase(
        'tall_shutter_slide_contact',
        tallShutter,
        distance: 8,
        slideRemaining: .2,
        viewport: tallViewport,
      );
      await captureCase(
        'tall_failure',
        _course(),
        failureVisible: true,
        viewport: tallViewport,
      );
      await captureCase(
        'tall_arrival',
        _course(totalDistance: 8),
        arrivalVisible: true,
        viewport: tallViewport,
      );
      await File('${directory.path}/manifest.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'source':
              'TempleRunArt image mode using TempleRunArt.loadImageAssets()',
          'viewport': {'width': _viewport.width, 'height': _viewport.height},
          'turnDistanceMeters': _turnDistance,
          'turnFrameOrder': distances,
          'singleCases': [
            'straight_360x640.png',
            'narrow_lane_0_before.png',
            'narrow_lane_0_inside.png',
            'narrow_lane_0_exit.png',
            'narrow_lane_2_before.png',
            'narrow_lane_2_inside.png',
            'narrow_lane_2_exit.png',
            'hurdle_jump_approach.png',
            'hurdle_jump_contact.png',
            'gap_jump_contact.png',
            'rubble_approach.png',
            'rubble_contact.png',
            'shutter_slide_contact.png',
            'pickups.png',
            'failure.png',
            'arrival.png',
          ],
          'animationStrips': [
            'runner_run_loop_4frames.png',
            'runner_jump_5moments.png',
            'runner_slide_5moments.png',
          ],
          'filmstrips': manifests,
        }),
        flush: true,
      );
    } finally {
      for (final image in images.values) {
        image.dispose();
      }
    }
  });
}

TempleRunCourse _course({
  Iterable<TempleRunTurn> turns = const [],
  Iterable<TempleRunObstacle> obstacles = const [],
  Iterable<TempleRunCoin> coins = const [],
  Iterable<TempleRunPowerUp> powerUps = const [],
  double totalDistance = 200,
}) => TempleRunCourse(
  obstacles: obstacles,
  coins: coins,
  powerUps: powerUps,
  turns: turns,
  totalDistanceMeters: totalDistance,
);

Future<Uint8List> _render(
  Map<String, ui.Image> images,
  TempleRunCourse course, {
  required double distance,
  int lane = TempleRunRules.centerLane,
  int completedTurns = 0,
  TempleRunTurn? activeTurn,
  double bendProgress = 0,
  TempleRunTurnDirection? bendDirection,
  double jumpRemaining = 0,
  double slideRemaining = 0,
  double runnerFrame = 0,
  bool guardianVisible = false,
  bool failureVisible = false,
  bool arrivalVisible = false,
  bool shieldVisible = false,
  bool boostVisible = false,
  Size viewport = _viewport,
}) async {
  final art = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: viewport.width,
    viewportHeight: viewport.height,
  );
  art.updateScene(
    course: course,
    distanceMeters: distance,
    lane: lane,
    visualLane: lane.toDouble(),
    phoneTilt: (lane - TempleRunRules.centerLane).toDouble(),
    jumpRemaining: jumpRemaining,
    slideRemaining: slideRemaining,
    runnerFrame: runnerFrame,
    activeTurn: activeTurn,
    bendProgress: bendProgress,
    bendDirection: bendDirection,
    completedTurnCount: completedTurns,
    guardianVisible: guardianVisible,
    failureVisible: failureVisible,
    arrivalVisible: arrivalVisible,
    shieldVisible: shieldVisible,
    boostVisible: boostVisible,
  );
  final recorder = ui.PictureRecorder();
  art.render(
    Canvas(recorder, Rect.fromLTWH(0, 0, viewport.width, viewport.height)),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    viewport.width.toInt(),
    viewport.height.toInt(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode renderer capture');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Uint8List> _filmstrip(List<Uint8List> frames) async {
  final decoded = <ui.Image>[];
  try {
    for (final bytes in frames) {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        decoded.add((await codec.getNextFrame()).image);
      } finally {
        codec.dispose();
      }
    }
    final width = decoded.first.width;
    final height = decoded.first.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var index = 0; index < decoded.length; index++) {
      canvas.drawImage(
        decoded[index],
        Offset(index * width.toDouble(), 0),
        Paint(),
      );
    }
    final picture = recorder.endRecording();
    final strip = await picture.toImage(width * decoded.length, height);
    try {
      final data = await strip.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode turn filmstrip');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      strip.dispose();
      picture.dispose();
    }
  } finally {
    for (final image in decoded) {
      image.dispose();
    }
  }
}

Future<void> _write(Directory directory, String name, Uint8List bytes) async {
  await File('${directory.path}/$name').writeAsBytes(bytes, flush: true);
}
