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
    'captures production temporal route with turns, props, and feedback',
    () async {
      final fontLoader = FontLoader('Galmuri')
        ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
      await fontLoader.load();
      final images = await TempleRunArt.loadImageAssets();
      final course = _temporalCourse();
      final frames = _temporalFrames();
      try {
        for (final frame in frames) {
          final art = TempleRunArt(
            images: images,
            useImageAssets: true,
            viewportWidth: TempleRunRules.logicalWidth,
            viewportHeight: frame.viewportHeight,
          );
          final activeTurn = frame.activeTurnIndex == null
              ? null
              : course.turns[frame.activeTurnIndex!];
          final collectedCoins = frame.collectedCoinIndex == null
              ? const <int>{}
              : {frame.collectedCoinIndex!};
          final collectedPowerUps = frame.collectedPowerUpIndex == null
              ? const <int>{}
              : {frame.collectedPowerUpIndex!};
          art.updateScene(
            course: course,
            distanceMeters: frame.distanceMeters,
            lane: frame.lane,
            visualLane: frame.visualLane,
            jumpRemaining: frame.jumpRemaining,
            slideRemaining: frame.slideRemaining,
            runnerFrame: frame.runnerFrame,
            activeTurn: activeTurn,
            bendProgress: frame.bendProgress,
            bendDirection: activeTurn?.direction,
            completedTurnCount: frame.completedTurnCount,
            guardianVisible: false,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: frame.boostVisible,
          );
          if (frame.collectedCoinIndex != null ||
              frame.collectedPowerUpIndex != null) {
            // Prime the known sets, then capture a real collection update with
            // matching consumed sets. The rendered item disappears while its
            // feedback burst remains on the runner.
            art.updateScene(
              course: course,
              distanceMeters: frame.distanceMeters,
              lane: frame.lane,
              visualLane: frame.visualLane,
              jumpRemaining: frame.jumpRemaining,
              slideRemaining: frame.slideRemaining,
              runnerFrame: frame.runnerFrame,
              activeTurn: activeTurn,
              bendProgress: frame.bendProgress,
              bendDirection: activeTurn?.direction,
              completedTurnCount: frame.completedTurnCount,
              guardianVisible: false,
              failureVisible: false,
              shieldVisible: false,
              boostVisible: frame.boostVisible,
              collectedCoinIndices: collectedCoins,
              consumedCoinIndices: collectedCoins,
              collectedPowerUpIndices: collectedPowerUps,
              consumedPowerUpIndices: collectedPowerUps,
            );
          }
          if (frame.collectedCoinIndex != null) {
            expect(art.activePickupEffectLabelsForTesting, contains('+10'));
          }
          if (frame.collectedPowerUpIndex != null) {
            expect(art.activePickupEffectLabelsForTesting, contains('BOOST'));
          }
          await _writeCapture(art, frame.name, frame.viewportHeight);
        }
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );

  test(
    'captures the normal facade transition around an outgoing prop',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      final course = _occlusionCourse();
      final turn = course.turns.single;
      final frames = <({String name, double progress, double distance})>[
        (name: 'occlusion_left_before_clear', progress: .95, distance: 30.05),
        (name: 'occlusion_left_emerging', progress: .5, distance: 30.25),
        (name: 'occlusion_left_after_clear', progress: 0, distance: 35.5),
      ];
      try {
        for (final frame in frames) {
          final art = TempleRunArt(
            images: images,
            useImageAssets: true,
            viewportWidth: TempleRunRules.logicalWidth,
            viewportHeight: TempleRunRules.logicalHeight,
          );
          art.updateScene(
            course: course,
            distanceMeters: frame.distance,
            lane: TempleRunRules.firstLane,
            visualLane: TempleRunRules.firstLane.toDouble(),
            jumpRemaining: 0,
            slideRemaining: 0,
            runnerFrame: 0,
            activeTurn: turn,
            bendProgress: frame.progress,
            bendDirection: turn.direction,
            completedTurnCount: 1,
            guardianVisible: false,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
          );
          await _writeCapture(art, frame.name, TempleRunRules.logicalHeight);
        }
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );

  test('captures dense generated course snapshots at 20s and 90s', () async {
    final images = await TempleRunArt.loadImageAssets();
    final course = TempleRunCourseGenerator(math.Random(17)).generate();
    const targetSeconds = <({String name, double seconds})>[
      // Keep the snapshot in the requested ~20s review band. The added
      // post-turn recovery can move which turn reservation falls here.
      (name: 'generated_dense_20s_seed17', seconds: 20.5),
      (name: 'generated_dense_90s_seed17', seconds: 90),
    ];
    try {
      for (final target in targetSeconds) {
        final distance = TempleRunRules.distanceForGeneration(target.seconds);
        final completedTurns = course.turns
            .where((turn) => turn.distanceMeters <= distance)
            .length;
        final nextTurn = completedTurns < course.turns.length
            ? course.turns[completedTurns]
            : null;
        expect(nextTurn, isNotNull, reason: target.name);
        expect(
          nextTurn!.distanceMeters - distance,
          lessThanOrEqualTo(80),
          reason: '${target.name} keeps the next turn in the look-ahead',
        );
        final activeNarrow = course.obstacles.where(
          (obstacle) =>
              obstacle.kind == TempleRunObstacleKind.narrowPath &&
              obstacle.distanceMeters <= distance &&
              distance <= obstacle.endDistanceMeters,
        );
        final runnerLane = activeNarrow.isEmpty
            ? TempleRunRules.centerLane
            : activeNarrow.first.lane;
        final previousDirection = completedTurns == 0
            ? null
            : course.turns[completedTurns - 1].direction;
        if (activeNarrow.isNotEmpty) {
          expect(
            activeNarrow.every(
              (obstacle) => !obstacle.blocksPosition(runnerLane.toDouble()),
            ),
            isTrue,
            reason: '${target.name} runner lane left the active narrow path',
          );
        }

        final art = TempleRunArt(
          images: images,
          useImageAssets: true,
          viewportWidth: TempleRunRules.logicalWidth,
          viewportHeight: TempleRunRules.logicalHeight,
        );
        art.updateScene(
          course: course,
          distanceMeters: distance,
          lane: runnerLane,
          visualLane: runnerLane.toDouble(),
          jumpRemaining: 0,
          slideRemaining: 0,
          runnerFrame: target.seconds * 8,
          activeTurn: nextTurn,
          bendProgress: 0,
          bendDirection: previousDirection,
          completedTurnCount: completedTurns,
          guardianVisible: false,
          failureVisible: false,
          shieldVisible: false,
          boostVisible: target.seconds >= 89,
        );
        var expectedHeading = 0.0;
        for (var index = 0; index < completedTurns; index++) {
          expectedHeading +=
              course.turns[index].direction == TempleRunTurnDirection.right
              ? math.pi / 2
              : -math.pi / 2;
        }
        expect(
          art.cameraHeadingForTesting,
          closeTo(expectedHeading, 1e-8),
          reason: '${target.name} settled bend direction',
        );
        await _writeCapture(art, target.name, TempleRunRules.logicalHeight);
      }
    } finally {
      for (final image in images.values) {
        image.dispose();
      }
    }
  });

  test(
    'facade occlusion clips billboard pixels instead of center-culling',
    () async {
      final art = TempleRunArt(
        viewportWidth: TempleRunRules.logicalWidth,
        viewportHeight: TempleRunRules.logicalHeight,
      );
      art.updateScene(
        course: TempleRunCourse(
          obstacles: const [],
          coins: const [],
          powerUps: const [],
          turns: const [],
          totalDistanceMeters: 40,
        ),
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

      const billboardColor = Color(0xFFFF00FF);
      Future<int> countPixels({
        required double wallLeftDepth,
        required double wallRightDepth,
        required double wallLateralStart,
        required double wallLateralEnd,
      }) async {
        final size = const Size(
          TempleRunRules.logicalWidth,
          TempleRunRules.logicalHeight,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, Offset.zero & size);
        art.renderFacadeOcclusionFixtureForTesting(
          canvas,
          wallLeftDepth: wallLeftDepth,
          wallRightDepth: wallRightDepth,
          wallLateralStart: wallLateralStart,
          wallLateralEnd: wallLateralEnd,
          wallHeight: 5.5,
          billboardDepth: 10,
          billboardLateral: 0,
          billboardWidth: 2,
          billboardHeight: 2,
          billboardColor: billboardColor,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        try {
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(rgba, isNotNull);
          final bytes = rgba!.buffer.asUint8List(
            rgba.offsetInBytes,
            rgba.lengthInBytes,
          );
          var count = 0;
          for (var index = 0; index < bytes.length; index += 4) {
            if (bytes[index] == 255 &&
                bytes[index + 1] == 0 &&
                bytes[index + 2] == 255 &&
                bytes[index + 3] > 200) {
              count++;
            }
          }
          return count;
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      final exposed = await countPixels(
        wallLeftDepth: 20,
        wallRightDepth: 20,
        wallLateralStart: -1,
        wallLateralEnd: 1,
      );
      final hidden = await countPixels(
        wallLeftDepth: 5,
        wallRightDepth: 5,
        wallLateralStart: -1,
        wallLateralEnd: 1,
      );
      final partial = await countPixels(
        wallLeftDepth: 5,
        wallRightDepth: 5,
        wallLateralStart: 0,
        wallLateralEnd: 1,
      );
      final depthClipped = await countPixels(
        wallLeftDepth: 5,
        wallRightDepth: 12,
        wallLateralStart: -1,
        wallLateralEnd: 1,
      );

      expect(exposed, greaterThan(1000));
      expect(hidden, lessThan(2));
      expect(partial, greaterThan(exposed * .35));
      expect(partial, lessThan(exposed * .65));
      expect(depthClipped, greaterThan(0));
      expect(depthClipped, lessThan(exposed));
    },
  );

  test(
    'production background stays opaque at repeat and full-turn phases',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      final size = const Size(
        TempleRunRules.logicalWidth,
        TempleRunRules.logicalHeight,
      );
      final cases =
          <
            ({
              String name,
              TempleRunTurnDirection direction,
              double distance,
              int completed,
            })
          >[
            (
              name: 'zero',
              direction: TempleRunTurnDirection.right,
              distance: 0,
              completed: 0,
            ),
            (
              name: 'quarter_right',
              direction: TempleRunTurnDirection.right,
              distance: 20,
              completed: 1,
            ),
            (
              name: 'quarter_left',
              direction: TempleRunTurnDirection.left,
              distance: 20,
              completed: 1,
            ),
            (
              name: 'full_right',
              direction: TempleRunTurnDirection.right,
              distance: 80,
              completed: 4,
            ),
            (
              name: 'full_left',
              direction: TempleRunTurnDirection.left,
              distance: 80,
              completed: 4,
            ),
          ];
      try {
        for (final capture in cases) {
          final art = TempleRunArt(
            images: images,
            useImageAssets: true,
            viewportWidth: size.width,
            viewportHeight: size.height,
          );
          art.updateScene(
            course: _backgroundCourse(capture.direction),
            distanceMeters: capture.distance,
            lane: TempleRunRules.centerLane,
            visualLane: TempleRunRules.centerLane.toDouble(),
            jumpRemaining: 0,
            slideRemaining: 0,
            runnerFrame: 0,
            activeTurn: null,
            bendProgress: 0,
            bendDirection: capture.completed > 0 ? capture.direction : null,
            completedTurnCount: capture.completed,
            guardianVisible: false,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
          );
          final turnRadians = capture.direction == TempleRunTurnDirection.right
              ? math.pi / 2
              : -math.pi / 2;
          expect(
            art.cameraHeadingForTesting,
            closeTo(turnRadians * capture.completed, 1e-8),
            reason: 'background phase fixture ${capture.name}',
          );
          final rgba = await _renderRgba(art, size);
          for (final y in [0, 100, 180]) {
            for (final x in [0, size.width.toInt() - 1]) {
              final alpha = rgba[(y * size.width.toInt() + x) * 4 + 3];
              expect(
                alpha,
                greaterThan(200),
                reason: 'background gap at ${capture.name} x=$x y=$y',
              );
            }
          }
        }
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );
}

TempleRunCourse _backgroundCourse(TempleRunTurnDirection direction) =>
    TempleRunCourse(
      obstacles: const [],
      coins: const [],
      powerUps: const [],
      turns: [
        for (var index = 0; index < 4; index++)
          TempleRunTurn(
            distanceMeters: 20.0 + index * 20,
            direction: direction,
            windowStartMeters: 10.0 + index * 20,
            windowEndMeters: 24.0 + index * 20,
          ),
      ],
      totalDistanceMeters: 110,
    );

TempleRunCourse _occlusionCourse() => TempleRunCourse(
  obstacles: [
    TempleRunObstacle(
      id: 20,
      distanceMeters: 36.4,
      lane: 0,
      kind: TempleRunObstacleKind.arch,
    ),
  ],
  coins: [TempleRunCoin(distanceMeters: 36.2, lane: 0)],
  powerUps: [],
  turns: [
    TempleRunTurn(
      distanceMeters: 30,
      direction: TempleRunTurnDirection.left,
      windowStartMeters: 20,
      windowEndMeters: 34,
    ),
  ],
  totalDistanceMeters: 70,
);

TempleRunCourse _temporalCourse() => TempleRunCourse(
  obstacles: const [
    TempleRunObstacle(
      id: 1,
      distanceMeters: 50,
      lane: 0,
      kind: TempleRunObstacleKind.hurdle,
    ),
    TempleRunObstacle(
      id: 2,
      distanceMeters: 55.2,
      lane: 2,
      kind: TempleRunObstacleKind.arch,
    ),
    TempleRunObstacle(
      id: 3,
      distanceMeters: 105.2,
      lane: 1,
      kind: TempleRunObstacleKind.rubble,
    ),
    TempleRunObstacle(
      id: 4,
      distanceMeters: 111.5,
      lane: 0,
      kind: TempleRunObstacleKind.gap,
      span: TempleRunObstacleSpan.fullRoad,
    ),
  ],
  coins: const [
    TempleRunCoin(distanceMeters: 50.8, lane: 2),
    TempleRunCoin(distanceMeters: 55.0, lane: 1),
    TempleRunCoin(distanceMeters: 104.6, lane: 0),
    TempleRunCoin(distanceMeters: 111.3, lane: 2),
  ],
  powerUps: const [
    TempleRunPowerUp(
      distanceMeters: 57.0,
      lane: 2,
      kind: TempleRunPowerUpKind.shield,
    ),
    TempleRunPowerUp(
      distanceMeters: 112.0,
      lane: 1,
      kind: TempleRunPowerUpKind.boost,
    ),
  ],
  turns: const [
    TempleRunTurn(
      distanceMeters: 54,
      direction: TempleRunTurnDirection.left,
      windowStartMeters: 35,
      windowEndMeters: 58,
    ),
    TempleRunTurn(
      distanceMeters: 110,
      direction: TempleRunTurnDirection.right,
      windowStartMeters: 91,
      windowEndMeters: 114,
    ),
  ],
  totalDistanceMeters: 180,
);

List<_TemporalFrame> _temporalFrames() => const [
  _TemporalFrame(
    'left_pre_outerlane',
    48,
    completedTurnCount: 0,
    activeTurnIndex: 0,
    bendProgress: 1,
    lane: 2,
    visualLane: 2,
  ),
  _TemporalFrame(
    'left_jminus2_outerlane',
    52,
    completedTurnCount: 0,
    activeTurnIndex: 0,
    bendProgress: 1,
    lane: 2,
    visualLane: 2,
  ),
  _TemporalFrame(
    'left_jminus01_nearwall',
    53.9,
    completedTurnCount: 0,
    activeTurnIndex: 0,
    bendProgress: 1,
    lane: 0,
    visualLane: 0,
  ),
  _TemporalFrame(
    'left_commit',
    54,
    completedTurnCount: 1,
    activeTurnIndex: 0,
    bendProgress: 1,
  ),
  _TemporalFrame(
    'left_turn_0045_outerlane',
    54.36,
    completedTurnCount: 1,
    activeTurnIndex: 0,
    bendProgress: .75,
    lane: 2,
    visualLane: 2,
  ),
  _TemporalFrame(
    'left_turn_009_coin_fx',
    54.72,
    completedTurnCount: 1,
    activeTurnIndex: 0,
    bendProgress: .5,
    lane: 1,
    visualLane: 1,
    collectedCoinIndex: 1,
  ),
  _TemporalFrame(
    'left_turn_018_jump',
    55.44,
    completedTurnCount: 1,
    activeTurnIndex: 0,
    bendProgress: 0,
    jumpRemaining: .39,
  ),
  _TemporalFrame(
    'left_settled_tall',
    58,
    completedTurnCount: 1,
    activeTurnIndex: 1,
    bendProgress: 0,
    viewportHeight: 820,
  ),
  _TemporalFrame(
    'right_pre_outerlane',
    104,
    completedTurnCount: 1,
    activeTurnIndex: 1,
    bendProgress: 1,
    lane: 0,
    visualLane: 0,
  ),
  _TemporalFrame(
    'right_commit',
    110,
    completedTurnCount: 2,
    activeTurnIndex: 1,
    bendProgress: 1,
  ),
  _TemporalFrame(
    'right_turn_0045_outerlane',
    110.36,
    completedTurnCount: 2,
    activeTurnIndex: 1,
    bendProgress: .75,
    lane: 0,
    visualLane: 0,
  ),
  _TemporalFrame(
    'right_turn_009_boost_fx',
    110.72,
    completedTurnCount: 2,
    activeTurnIndex: 1,
    bendProgress: .5,
    collectedPowerUpIndex: 1,
  ),
  _TemporalFrame(
    'right_max_boost_mid_39_6',
    110 + TempleRunRules.maximumBoostedSpeedMetersPerSecond * .09,
    completedTurnCount: 2,
    activeTurnIndex: 1,
    bendProgress: .5,
    lane: 0,
    visualLane: 0,
    boostVisible: true,
  ),
  _TemporalFrame(
    'right_max_boost_settled_39_6',
    110 + TempleRunRules.maximumBoostedSpeedMetersPerSecond * .18,
    completedTurnCount: 2,
    lane: 0,
    visualLane: 0,
    boostVisible: true,
  ),
  _TemporalFrame(
    'right_turn_018_slide',
    111.44,
    completedTurnCount: 2,
    activeTurnIndex: 1,
    bendProgress: 0,
    slideRemaining: .36,
  ),
  _TemporalFrame(
    'right_settled_tall',
    116,
    completedTurnCount: 2,
    bendProgress: 0,
    viewportHeight: 820,
  ),
];

class _TemporalFrame {
  const _TemporalFrame(
    this.name,
    this.distanceMeters, {
    this.completedTurnCount = 0,
    this.activeTurnIndex,
    this.bendProgress = 0,
    this.lane = TempleRunRules.centerLane,
    this.visualLane = 1.0,
    this.jumpRemaining = 0,
    this.slideRemaining = 0,
    this.collectedCoinIndex,
    this.collectedPowerUpIndex,
    this.boostVisible = false,
    this.viewportHeight = TempleRunRules.logicalHeight,
  }) : runnerFrame = 1.0;

  final String name;
  final double distanceMeters;
  final int completedTurnCount;
  final int? activeTurnIndex;
  final double bendProgress;
  final int lane;
  final double visualLane;
  final double jumpRemaining;
  final double slideRemaining;
  final double runnerFrame;
  final int? collectedCoinIndex;
  final int? collectedPowerUpIndex;
  final bool boostVisible;
  final double viewportHeight;
}

Future<Uint8List> _renderRgba(TempleRunArt art, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  art.render(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);
    return bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _writeCapture(
  TempleRunArt art,
  String name,
  double viewportHeight,
) async {
  final size = Size(TempleRunRules.logicalWidth, viewportHeight);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  art.render(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(bytes, isNotNull);
    final file = File(
      'artifacts/temple_run/temporal_candidates/${name}_${size.height.toInt()}.png',
    )..createSync(recursive: true);
    file.writeAsBytesSync(
      bytes!.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.offsetInBytes + bytes.lengthInBytes,
      ),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}
