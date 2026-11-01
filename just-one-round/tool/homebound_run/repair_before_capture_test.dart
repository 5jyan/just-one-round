import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';
import 'package:just_one_round/features/games/temple_run/temple_run_game.dart';

const _outputPath = 'artifacts/homebound_run/repair_before';
const _short = Size(360, 640);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('capture image-mode renderer repair baseline and animation strips', () async {
    final directory = Directory('$_outputPath/renderer')
      ..createSync(recursive: true);
    final images = await TempleRunArt.loadImageAssets();
    try {
      final turnCourse = _course(
        turns: [_turn(50, TempleRunTurnDirection.left)],
      );

      await _writeArt(
        directory,
        'straight_360x640',
        images,
        _Scene(turnCourse),
      );

      for (final direction in TempleRunTurnDirection.values) {
        final frames = <Uint8List>[];
        for (final progress in [1.0, .75, .5, .25, 0.0]) {
          frames.add(
            await _renderArt(
              images,
              _Scene(
                _course(turns: [_turn(50, direction)]),
                distance: 50.2,
                completedTurns: 1,
                activeTurn: _turn(50, direction),
                bendProgress: progress,
                bendDirection: direction,
              ),
            ),
          );
        }
        await _writeBytes(
          File('${directory.path}/turn_${direction.name}_5phase.png'),
          await _filmstrip(frames),
        );
        for (final lane in [
          TempleRunRules.firstLane,
          TempleRunRules.lastLane,
        ]) {
          await _writeArt(
            directory,
            'turn_${direction.name}_mid_outer_lane_$lane',
            images,
            _Scene(
              _course(turns: [_turn(50, direction)]),
              distance: 50.2,
              visualLane: lane.toDouble(),
              completedTurns: 1,
              activeTurn: _turn(50, direction),
              bendProgress: .5,
              bendDirection: direction,
            ),
          );
        }
        await _writeArt(
          directory,
          'turn_${direction.name}_settled',
          images,
          _Scene(
            _course(turns: [_turn(50, direction)]),
            distance: 63,
            completedTurns: 1,
          ),
        );
      }

      for (final lane in [TempleRunRules.firstLane, TempleRunRules.lastLane]) {
        final course = _course(
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
          await _writeArt(
            directory,
            'narrow_lane_${lane}_${point.name}',
            images,
            _Scene(
              course,
              distance: point.distance,
              lane: lane,
              visualLane: lane.toDouble(),
            ),
          );
        }
      }

      final hurdle = TempleRunObstacle(
        distanceMeters: 8,
        lane: TempleRunRules.centerLane,
        kind: TempleRunObstacleKind.hurdle,
        span: TempleRunObstacleSpan.fullRoad,
      );
      final hurdleCourse = _course(obstacles: [hurdle]);
      await _writeArt(
        directory,
        'hurdle_jump_approach',
        images,
        _Scene(hurdleCourse, distance: 6.4, jumpRemaining: .24),
      );
      await _writeArt(
        directory,
        'hurdle_jump_contact',
        images,
        _Scene(hurdleCourse, distance: 8, jumpRemaining: .18),
      );

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
      await _writeArt(
        directory,
        'shutter_slide_contact',
        images,
        _Scene(shutterCourse, distance: 8, slideRemaining: .2),
      );

      await _writeArt(
        directory,
        'pickups',
        images,
        _Scene(
          _course(
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
          ),
          distance: 0,
          guardianVisible: false,
          shieldVisible: true,
          boostVisible: true,
        ),
      );

      await _writeArt(
        directory,
        'failure',
        images,
        _Scene(_course(), guardianVisible: false, failureVisible: true),
      );
      await _writeArt(
        directory,
        'arrival',
        images,
        _Scene(_course(totalDistance: 8), arrivalVisible: true),
      );

      final runFrames = <Uint8List>[];
      for (var frame = 0; frame < 4; frame++) {
        runFrames.add(
          await _renderArt(
            images,
            _Scene(_course(), runnerFrame: frame.toDouble()),
          ),
        );
      }
      await _writeBytes(
        File('${directory.path}/runner_run_loop_4frames.png'),
        await _filmstrip(runFrames),
      );

      final jumpFrames = <Uint8List>[];
      for (final fraction in [0.0, .25, .5, .75, .95]) {
        jumpFrames.add(
          await _renderArt(
            images,
            _Scene(
              _course(),
              jumpRemaining:
                  TempleRunRules.jumpDurationSeconds * (1 - fraction),
            ),
          ),
        );
      }
      await _writeBytes(
        File('${directory.path}/runner_jump_5moments.png'),
        await _filmstrip(jumpFrames),
      );

      final slideFrames = <Uint8List>[];
      for (final fraction in [0.0, .25, .5, .75, .95]) {
        slideFrames.add(
          await _renderArt(
            images,
            _Scene(
              _course(),
              slideRemaining:
                  TempleRunRules.slideDurationSeconds * (1 - fraction),
            ),
          ),
        );
      }
      await _writeBytes(
        File('${directory.path}/runner_slide_5moments.png'),
        await _filmstrip(slideFrames),
      );

      File('${directory.path}/manifest.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'source':
              'TempleRunArt image mode using TempleRunArt.loadImageAssets()',
          'viewport': {'width': _short.width, 'height': _short.height},
          'filmstripFrameOrder': {
            'turn_*_5phase.png': [
              'incoming view',
              '25%',
              '50%',
              '75%',
              'settled view',
            ],
            'runner_run_loop_4frames.png': [
              'run frame 0',
              'run frame 1',
              'run frame 2',
              'run frame 3',
            ],
            'runner_jump_5moments.png': ['0%', '25%', '50%', '75%', '95%'],
            'runner_slide_5moments.png': ['0%', '25%', '50%', '75%', '95%'],
          },
          'individualCases': [
            'straight_360x640.png',
            'turn_left_mid_outer_lane_0.png',
            'turn_left_mid_outer_lane_2.png',
            'turn_left_settled.png',
            'turn_right_mid_outer_lane_0.png',
            'turn_right_mid_outer_lane_2.png',
            'turn_right_settled.png',
            'narrow_lane_0_before.png',
            'narrow_lane_0_inside.png',
            'narrow_lane_0_exit.png',
            'narrow_lane_2_before.png',
            'narrow_lane_2_inside.png',
            'narrow_lane_2_exit.png',
            'hurdle_jump_approach.png',
            'hurdle_jump_contact.png',
            'shutter_slide_contact.png',
            'pickups.png',
            'failure.png',
            'arrival.png',
          ],
          'reusedExistingActualCaptures': {
            'shortStraight':
                'artifacts/homebound_run/visual_review/straight_360x640.png',
            'leftApproach':
                'artifacts/homebound_run/visual_review/left_approach_360x640.png',
            'leftMidturn':
                'artifacts/homebound_run/visual_review/left_midturn_360x640.png',
            'leftAfterturn':
                'artifacts/homebound_run/visual_review/left_afterturn_360x640.png',
            'rightApproach':
                'artifacts/homebound_run/visual_review/right_approach_360x640.png',
            'rightMidturn':
                'artifacts/homebound_run/visual_review/right_midturn_360x640.png',
            'rightAfterturn':
                'artifacts/homebound_run/visual_review/right_afterturn_360x640.png',
            'hurdle':
                'artifacts/homebound_run/visual_review/jump_at_pallet_contact_360x640.png',
            'shutter':
                'artifacts/homebound_run/visual_review/slide_at_shutter_contact_360x640.png',
            'narrowPassages':
                'artifacts/homebound_run/visual_review/narrow_*_midinterval_360x640.png',
            'arrival':
                'artifacts/homebound_run/visual_review/arrival_360x640.png',
          },
        }),
        flush: true,
      );
    } finally {
      for (final image in images.values) {
        image.dispose();
      }
    }
  });

  testWidgets('capture actual GameWidget live, failure, and arrival states', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = _short;
    await tester.binding.setSurfaceSize(_short);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final directory = Directory('$_outputPath/game_widget')
      ..createSync(recursive: true);

    Future<TempleRunGame> mountGame({
      required TempleRunCourse course,
      Duration duration = const Duration(seconds: 20),
    }) async {
      final game = TempleRunGame(
        gameDuration: duration,
        countdownDuration: Duration.zero,
        random: Random(9001),
        course: course,
        useImageAssets: true,
        enableTiltInput: false,
        onFinished: (_) {},
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: _short.width,
              height: _short.height,
              child: RepaintBoundary(
                key: const Key('capture-game'),
                child: GameWidget(game: game),
              ),
            ),
          ),
        ),
      );
      for (var attempt = 0; attempt < 100 && !game.isLoaded; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(game.isLoaded, isTrue);
      game.pauseEngine();
      return game;
    }

    final live = await mountGame(course: _course(totalDistance: 200));
    live.advanceTimeForTesting(const Duration(seconds: 2));
    await tester.pump();
    await _captureWidget(tester, File('${directory.path}/live.png'));
    live.forceFinishForTesting(GameEndType.gameOver);
    await tester.pump();
    await _captureWidget(tester, File('${directory.path}/failure.png'));
    live.disposeController();

    final arrival = await mountGame(
      course: _course(totalDistance: 16),
      duration: const Duration(seconds: 2),
    );
    arrival.advanceTimeForTesting(const Duration(seconds: 2));
    await tester.pump();
    expect(arrival.gamePhase, MiniGamePhase.finished);
    await _captureWidget(tester, File('${directory.path}/arrival.png'));
    arrival.disposeController();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _Scene {
  const _Scene(
    this.course, {
    this.distance = 0,
    this.lane = TempleRunRules.centerLane,
    this.visualLane = 1.0,
    this.jumpRemaining = 0,
    this.slideRemaining = 0,
    this.runnerFrame = 0,
    this.activeTurn,
    this.completedTurns = 0,
    this.bendProgress = 0,
    this.bendDirection,
    this.guardianVisible = true,
    this.failureVisible = false,
    this.arrivalVisible = false,
    this.shieldVisible = false,
    this.boostVisible = false,
  });

  final TempleRunCourse course;
  final double distance;
  final int lane;
  final double visualLane;
  final double jumpRemaining;
  final double slideRemaining;
  final double runnerFrame;
  final TempleRunTurn? activeTurn;
  final int completedTurns;
  final double bendProgress;
  final TempleRunTurnDirection? bendDirection;
  final bool guardianVisible;
  final bool failureVisible;
  final bool arrivalVisible;
  final bool shieldVisible;
  final bool boostVisible;
}

TempleRunCourse _course({
  Iterable<TempleRunObstacle> obstacles = const [],
  Iterable<TempleRunCoin> coins = const [],
  Iterable<TempleRunPowerUp> powerUps = const [],
  Iterable<TempleRunTurn> turns = const [],
  double totalDistance = 200,
}) => TempleRunCourse(
  obstacles: obstacles,
  coins: coins,
  powerUps: powerUps,
  turns: turns,
  totalDistanceMeters: totalDistance,
);

TempleRunTurn _turn(double distance, TempleRunTurnDirection direction) =>
    TempleRunTurn(
      distanceMeters: distance,
      direction: direction,
      windowStartMeters: distance - 8,
      windowEndMeters: distance + 4,
    );

Future<void> _writeArt(
  Directory directory,
  String name,
  Map<String, ui.Image> images,
  _Scene scene,
) async => _writeBytes(
  File('${directory.path}/$name.png'),
  await _renderArt(images, scene),
);

Future<Uint8List> _renderArt(Map<String, ui.Image> images, _Scene scene) async {
  final art = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: _short.width,
    viewportHeight: _short.height,
  );
  art.updateScene(
    course: scene.course,
    distanceMeters: scene.distance,
    lane: scene.lane,
    visualLane: scene.visualLane,
    jumpRemaining: scene.jumpRemaining,
    slideRemaining: scene.slideRemaining,
    runnerFrame: scene.runnerFrame,
    activeTurn: scene.activeTurn,
    bendProgress: scene.bendProgress,
    bendDirection: scene.bendDirection,
    completedTurnCount: scene.completedTurns,
    guardianVisible: scene.guardianVisible,
    failureVisible: scene.failureVisible,
    arrivalVisible: scene.arrivalVisible,
    shieldVisible: scene.shieldVisible,
    boostVisible: scene.boostVisible,
  );
  final recorder = ui.PictureRecorder();
  art.render(
    Canvas(recorder, Rect.fromLTWH(0, 0, _short.width, _short.height)),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _short.width.toInt(),
    _short.height.toInt(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode image-mode capture');
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
    final filmstrip = await picture.toImage(width * decoded.length, height);
    try {
      final data = await filmstrip.toByteData(format: ui.ImageByteFormat.png);
      if (data == null)
        throw StateError('Could not encode animation filmstrip');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      filmstrip.dispose();
      picture.dispose();
    }
  } finally {
    for (final image in decoded) {
      image.dispose();
    }
  }
}

Future<void> _writeBytes(File file, Uint8List bytes) async {
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> _captureWidget(WidgetTester tester, File file) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('capture-game')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode ${file.path}');
      await _writeBytes(
        file,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}
