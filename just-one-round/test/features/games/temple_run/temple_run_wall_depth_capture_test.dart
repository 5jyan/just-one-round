import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('captures wall-depth review views with bundled facade art', () async {
    final images = await TempleRunArt.loadImageAssets();
    final captures = <_CaptureSpec>[
      const _CaptureSpec(
        'straight_plaster_tile_join_360x640',
        Size(360, 640),
        30,
        0,
        null,
      ),
      const _CaptureSpec(
        'straight_house_front_360x640',
        Size(360, 640),
        12,
        0,
        null,
      ),
      const _CaptureSpec(
        'straight_house_pair_360x640',
        Size(360, 640),
        7,
        0,
        null,
      ),
      const _CaptureSpec(
        'straight_shop_front_360x640',
        Size(360, 640),
        24,
        0,
        null,
      ),
      const _CaptureSpec(
        'straight_mixed_neighborhood_360x640',
        Size(360, 640),
        20,
        0,
        null,
      ),
      const _CaptureSpec(
        'straight_rare_front_360x640',
        Size(360, 640),
        63,
        0,
        null,
      ),
      const _CaptureSpec(
        'nearclip_left_relief_360x640',
        Size(360, 640),
        8.9,
        0,
        null,
        visualLane: 0,
      ),
      const _CaptureSpec(
        'nearclip_right_relief_360x640',
        Size(360, 640),
        8.9,
        0,
        null,
        visualLane: 2,
      ),
      const _CaptureSpec(
        'straight_window_feature_360x640',
        Size(360, 640),
        48,
        0,
        null,
      ),
      const _CaptureSpec(
        'straight_door_feature_360x640',
        Size(360, 640),
        62,
        0,
        null,
      ),
      const _CaptureSpec(
        'straight_mural_feature_360x640',
        Size(360, 640),
        90,
        0,
        null,
      ),
      const _CaptureSpec(
        'straight_blank_wall_360x820',
        Size(360, 820),
        30,
        0,
        null,
      ),
      const _CaptureSpec(
        'left_jminus6_360x640',
        Size(360, 640),
        48,
        0,
        TempleRunTurnDirection.left,
      ),
      const _CaptureSpec(
        'left_jminus2_outerlane_360x640',
        Size(360, 640),
        52,
        0,
        TempleRunTurnDirection.left,
        visualLane: 2,
      ),
      const _CaptureSpec(
        'left_jminus01_360x640',
        Size(360, 640),
        53.9,
        0,
        TempleRunTurnDirection.left,
      ),
      const _CaptureSpec(
        'left_commit_360x640',
        Size(360, 640),
        54,
        1,
        TempleRunTurnDirection.left,
        bendProgress: 1,
      ),
      const _CaptureSpec(
        'left_turn_0045_outerlane_360x640',
        Size(360, 640),
        54.45,
        1,
        TempleRunTurnDirection.left,
        bendProgress: .75,
        visualLane: 2,
      ),
      const _CaptureSpec(
        'left_turn_009_360x640',
        Size(360, 640),
        54.9,
        1,
        TempleRunTurnDirection.left,
        bendProgress: .5,
      ),
      const _CaptureSpec(
        'left_turn_018_360x640',
        Size(360, 640),
        55.8,
        1,
        TempleRunTurnDirection.left,
      ),
      const _CaptureSpec(
        'left_turn_018_outerlane_tall_360x820',
        Size(360, 820),
        55.8,
        1,
        TempleRunTurnDirection.left,
        visualLane: 2,
      ),
      const _CaptureSpec(
        'left_turn_035_360x640',
        Size(360, 640),
        57.5,
        1,
        TempleRunTurnDirection.left,
      ),
      const _CaptureSpec(
        'right_jminus6_360x640',
        Size(360, 640),
        48,
        0,
        TempleRunTurnDirection.right,
      ),
      const _CaptureSpec(
        'right_jminus2_outerlane_360x640',
        Size(360, 640),
        52,
        0,
        TempleRunTurnDirection.right,
        visualLane: 0,
      ),
      const _CaptureSpec(
        'right_jminus01_360x640',
        Size(360, 640),
        53.9,
        0,
        TempleRunTurnDirection.right,
      ),
      const _CaptureSpec(
        'right_commit_360x640',
        Size(360, 640),
        54,
        1,
        TempleRunTurnDirection.right,
        bendProgress: 1,
      ),
      const _CaptureSpec(
        'right_turn_0045_outerlane_360x640',
        Size(360, 640),
        54.45,
        1,
        TempleRunTurnDirection.right,
        bendProgress: .75,
        visualLane: 0,
      ),
      const _CaptureSpec(
        'right_turn_009_360x640',
        Size(360, 640),
        54.9,
        1,
        TempleRunTurnDirection.right,
        bendProgress: .5,
      ),
      const _CaptureSpec(
        'right_turn_018_360x640',
        Size(360, 640),
        55.8,
        1,
        TempleRunTurnDirection.right,
      ),
      const _CaptureSpec(
        'right_turn_018_outerlane_tall_360x820',
        Size(360, 820),
        55.8,
        1,
        TempleRunTurnDirection.right,
        visualLane: 0,
      ),
      const _CaptureSpec(
        'right_turn_035_360x640',
        Size(360, 640),
        57.5,
        1,
        TempleRunTurnDirection.right,
      ),
      const _CaptureSpec(
        'neighborhood_full_arc_left_360x820',
        Size(360, 820),
        160,
        0,
        null,
        visualLane: 0,
      ),
      const _CaptureSpec(
        'neighborhood_full_arc_right_360x820',
        Size(360, 820),
        160,
        0,
        null,
        visualLane: 2,
      ),
    ];

    try {
      for (final capture in captures) {
        final direction = capture.direction ?? TempleRunTurnDirection.left;
        final hasTurn = capture.direction != null;
        final turn = TempleRunTurn(
          distanceMeters: 54,
          direction: direction,
          windowStartMeters: 35,
          windowEndMeters: 58,
        );
        final course = TempleRunCourse(
          obstacles: const [],
          coins: const [],
          powerUps: const [],
          // Straight style captures must keep advancing on the authored
          // straight leg; a synthetic turn would trigger the renderer's
          // late-turn hold at J and show the school block again at 74–85m.
          turns: hasTurn ? [turn] : const [],
          totalDistanceMeters: 300,
        );
        final art = TempleRunArt(
          images: images,
          useImageAssets: true,
          viewportWidth: capture.size.width,
          viewportHeight: capture.size.height,
        );
        art.updateScene(
          course: course,
          distanceMeters: capture.distance,
          lane: TempleRunRules.centerLane,
          visualLane:
              capture.visualLane ?? TempleRunRules.centerLane.toDouble(),
          jumpRemaining: 0,
          slideRemaining: 0,
          runnerFrame: 1,
          activeTurn: hasTurn ? turn : null,
          bendProgress: capture.bendProgress,
          bendDirection: capture.direction,
          completedTurnCount: hasTurn ? capture.completedTurns : 0,
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
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(png, isNotNull);
        if (capture.name == 'straight_house_pair_360x640' ||
            capture.name == 'straight_shop_front_360x640') {
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(rgba, isNotNull);
          if (capture.name == 'straight_house_pair_360x640') {
            final leftWarm = _countPixels(
              rgba!,
              capture.size.width.toInt(),
              const Rect.fromLTRB(0, 200, 105, 430),
              (red, green, blue) =>
                  red > 110 && green > 45 && blue < 105 && red > green * 1.25,
            );
            final rightGreen = _countPixels(
              rgba,
              capture.size.width.toInt(),
              const Rect.fromLTRB(255, 200, 360, 430),
              (red, green, blue) =>
                  green > 75 && green > red * 1.15 && green > blue * 1.05,
            );
            expect(
              leftWarm,
              greaterThan(200),
              reason: 'left house mass must survive backing and face culling',
            );
            expect(
              rightGreen,
              greaterThan(200),
              reason: 'right house mass must survive backing and face culling',
            );
          } else {
            final leftWhiteFrame = _countPixels(
              rgba!,
              capture.size.width.toInt(),
              const Rect.fromLTRB(0, 180, 110, 260),
              (red, green, blue) =>
                  red > 210 &&
                  green > 200 &&
                  blue > 185 &&
                  red - green < 40 &&
                  green - blue < 45,
            );
            final rightWhiteFrame = _countPixels(
              rgba,
              capture.size.width.toInt(),
              const Rect.fromLTRB(250, 180, 360, 260),
              (red, green, blue) =>
                  red > 210 &&
                  green > 200 &&
                  blue > 185 &&
                  red - green < 40 &&
                  green - blue < 45,
            );
            expect(
              leftWhiteFrame,
              lessThan(5000),
              reason: 'full-bleed shop must not leave a white backing frame',
            );
            expect(
              rightWhiteFrame,
              lessThan(5000),
              reason: 'full-bleed shop must not leave a white backing frame',
            );
          }
        }
        final file = File(
          'artifacts/temple_run/wall_depth_candidates/${capture.name}.png',
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(
          png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
        image.dispose();
        picture.dispose();
      }
    } finally {
      for (final image in images.values) {
        image.dispose();
      }
    }
  });

  test(
    'captures long same-direction turns without future wall crossings',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      final turns = [
        for (final distance in const [40.0, 75.0, 110.0, 145.0])
          TempleRunTurn(
            distanceMeters: distance,
            direction: TempleRunTurnDirection.right,
            windowStartMeters: distance - 19,
            windowEndMeters: distance + 4,
          ),
      ];
      final course = TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: turns,
        totalDistanceMeters: 260,
      );
      final captures = [
        (
          name: 'rrrr_first_commit_lane0_360x640',
          distance: 41.0,
          completedTurns: 1,
          activeTurnIndex: 0,
          bendProgress: 1.0,
          lane: 0.0,
        ),
        (
          name: 'rrrr_first_commit_lane1_360x640',
          distance: 41.0,
          completedTurns: 1,
          activeTurnIndex: 0,
          bendProgress: 1.0,
          lane: 1.0,
        ),
        (
          name: 'rrrr_first_commit_lane2_360x640',
          distance: 41.0,
          completedTurns: 1,
          activeTurnIndex: 0,
          bendProgress: 1.0,
          lane: 2.0,
        ),
        (
          name: 'rrrr_first_outgoing_settled_lane0_after_filter_360x640',
          distance: 41.0,
          completedTurns: 1,
          activeTurnIndex: 1,
          bendProgress: 0.0,
          lane: 0.0,
        ),
        (
          name: 'rrrr_first_outgoing_settled_lane1_after_filter_360x640',
          distance: 41.0,
          completedTurns: 1,
          activeTurnIndex: 1,
          bendProgress: 0.0,
          lane: 1.0,
        ),
        (
          name: 'rrrr_first_outgoing_settled_lane2_after_filter_360x640',
          distance: 41.0,
          completedTurns: 1,
          activeTurnIndex: 1,
          bendProgress: 0.0,
          lane: 2.0,
        ),
        (
          name: 'rrrr_second_turn_0045_lane1_360x640',
          distance: 75.45,
          completedTurns: 2,
          activeTurnIndex: 1,
          bendProgress: .75,
          lane: 1.0,
        ),
        (
          name: 'rrrr_second_commit_lane1_360x640',
          distance: 76.0,
          completedTurns: 2,
          activeTurnIndex: 1,
          bendProgress: 1.0,
          lane: 1.0,
        ),
        (
          name: 'rrrr_late_hold_lane1_360x640',
          distance: 76.0,
          completedTurns: 1,
          activeTurnIndex: 1,
          bendProgress: 0.0,
          lane: 1.0,
        ),
        (
          name: 'rrrr_late_recovery_lane1_360x640',
          distance: 76.0,
          completedTurns: 2,
          activeTurnIndex: 1,
          bendProgress: .5,
          lane: 1.0,
        ),
      ];
      TempleRunArt? lateArt;
      try {
        for (final capture in captures) {
          final art = capture.name.startsWith('rrrr_late_')
              ? (lateArt ??= TempleRunArt(
                  images: images,
                  useImageAssets: true,
                  viewportWidth: 360,
                  viewportHeight: 640,
                ))
              : TempleRunArt(
                  images: images,
                  useImageAssets: true,
                  viewportWidth: 360,
                  viewportHeight: 640,
                );
          art.updateScene(
            course: course,
            distanceMeters: capture.distance,
            lane: TempleRunRules.centerLane,
            visualLane: capture.lane,
            jumpRemaining: 0,
            slideRemaining: 0,
            runnerFrame: 1,
            activeTurn: turns[capture.activeTurnIndex],
            bendProgress: capture.bendProgress,
            bendDirection: TempleRunTurnDirection.right,
            completedTurnCount: capture.completedTurns,
            guardianVisible: false,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
          );
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 360, 640));
          art.render(canvas);
          final picture = recorder.endRecording();
          final image = await picture.toImage(360, 640);
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(png, isNotNull);
            final file = File(
              'artifacts/temple_run/wall_depth_candidates/${capture.name}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(
              png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            );
          } finally {
            image.dispose();
            picture.dispose();
          }
        }

        // The first two turns are identical in both courses. A remote third
        // or fourth turn must not paint a wall across the active road before
        // the runner reaches it. Compare the long fixture with a prefix-only
        // course in the central road ROI so this regression checks rendered
        // pixels, including curb details, rather than only a filter predicate.
        final prefixCourse = TempleRunCourse(
          obstacles: const [],
          coins: const [],
          powerUps: const [],
          turns: turns.sublist(0, 2),
          totalDistanceMeters: 160,
        );
        final longRgba = await _renderRawRgba(
          images: images,
          course: course,
          activeTurn: turns[1],
          bendDirection: TempleRunTurnDirection.right,
          completedTurnCount: 1,
          distanceMeters: 41,
          visualLane: 1,
          bendProgress: 0,
        );
        final prefixRgba = await _renderRawRgba(
          images: images,
          course: prefixCourse,
          activeTurn: prefixCourse.turns[1],
          bendDirection: TempleRunTurnDirection.right,
          completedTurnCount: 1,
          distanceMeters: 41,
          visualLane: 1,
          bendProgress: 0,
        );
        const roadRoi = Rect.fromLTRB(150, 350, 210, 430);
        final roadPixels = _countPixels(
          longRgba,
          360,
          roadRoi,
          (red, green, blue) =>
              red > 35 &&
              red < 120 &&
              green > 40 &&
              green < 130 &&
              blue > 50 &&
              blue < 150 &&
              (red - green).abs() < 25 &&
              (green - blue).abs() < 35,
        );
        expect(
          roadPixels,
          greaterThan(4500),
          reason: 'settled outgoing road must remain open in the active ROI',
        );
        expect(
          _countMismatchedPixels(longRgba, prefixRgba, 360, roadRoi),
          lessThan(48),
          reason:
              'remote future turns must not alter the active central road pixels',
        );
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );
  test(
    'captures long same-direction left turns without future wall crossings',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      final turns = [
        for (final distance in const [40.0, 75.0, 110.0, 145.0])
          TempleRunTurn(
            distanceMeters: distance,
            direction: TempleRunTurnDirection.left,
            windowStartMeters: distance - 19,
            windowEndMeters: distance + 4,
          ),
      ];
      final course = TempleRunCourse(
        obstacles: const [],
        coins: const [],
        powerUps: const [],
        turns: turns,
        totalDistanceMeters: 260,
      );
      final captures = [
        (
          name: 'llll_first_commit_lane0_360x640',
          lane: 0.0,
          activeTurnIndex: 0,
          bendProgress: 1.0,
        ),
        (
          name: 'llll_first_commit_lane1_360x640',
          lane: 1.0,
          activeTurnIndex: 0,
          bendProgress: 1.0,
        ),
        (
          name: 'llll_first_commit_lane2_360x640',
          lane: 2.0,
          activeTurnIndex: 0,
          bendProgress: 1.0,
        ),
        (
          name: 'llll_first_outgoing_settled_lane0_after_filter_360x640',
          lane: 0.0,
          activeTurnIndex: 1,
          bendProgress: 0.0,
        ),
        (
          name: 'llll_first_outgoing_settled_lane1_after_filter_360x640',
          lane: 1.0,
          activeTurnIndex: 1,
          bendProgress: 0.0,
        ),
        (
          name: 'llll_first_outgoing_settled_lane2_after_filter_360x640',
          lane: 2.0,
          activeTurnIndex: 1,
          bendProgress: 0.0,
        ),
      ];
      try {
        for (final capture in captures) {
          final art = TempleRunArt(
            images: images,
            useImageAssets: true,
            viewportWidth: 360,
            viewportHeight: 640,
          );
          art.updateScene(
            course: course,
            distanceMeters: 41,
            lane: TempleRunRules.centerLane,
            visualLane: capture.lane,
            jumpRemaining: 0,
            slideRemaining: 0,
            runnerFrame: 1,
            activeTurn: turns[capture.activeTurnIndex],
            bendProgress: capture.bendProgress,
            bendDirection: TempleRunTurnDirection.left,
            completedTurnCount: 1,
            guardianVisible: false,
            failureVisible: false,
            shieldVisible: false,
            boostVisible: false,
          );
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 360, 640));
          art.render(canvas);
          final picture = recorder.endRecording();
          final image = await picture.toImage(360, 640);
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(png, isNotNull);
            final file = File(
              'artifacts/temple_run/wall_depth_candidates/${capture.name}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(
              png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            );
          } finally {
            image.dispose();
            picture.dispose();
          }
        }
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );

  test('captures generated high-speed wall joins around turn commits', () async {
    final images = await TempleRunArt.loadImageAssets();
    const seeds = [17, 20261015, 20261018, 314159];
    try {
      for (var seedIndex = 0; seedIndex < seeds.length; seedIndex++) {
        final seed = seeds[seedIndex];
        final course = TempleRunCourseGenerator(math.Random(seed)).generate();
        final turnIndex = course.turns.indexed.reduce((best, candidate) {
          final target = TempleRunRules.elapsedForGenerationDistance(
            course.turns[best.$1].distanceMeters,
          );
          final candidateTime = TempleRunRules.elapsedForGenerationDistance(
            candidate.$2.distanceMeters,
          );
          return (target - 250).abs() <= (candidateTime - 250).abs()
              ? best
              : candidate;
        }).$1;
        final turn = course.turns[turnIndex];
        final elapsed = TempleRunRules.elapsedForGenerationDistance(
          turn.distanceMeters,
        );
        final speed = TempleRunRules.speedForElapsed(elapsed);
        final height = seedIndex.isEven ? 640.0 : 820.0;
        final lane = (seedIndex % 3).toDouble();

        for (final side in [-1, 1]) {
          final spans = _sceneForCapture(
            images: images,
            course: course,
            distance: turn.distanceMeters - .01,
            completedTurns: turnIndex,
            activeTurn: turn,
            bendDirection: turnIndex == 0
                ? null
                : course.turns[turnIndex - 1].direction,
            bendProgress: 0,
            lane: lane,
            viewportHeight: height,
            deltaSeconds: .125,
          ).facadeWallSpansForTesting(side: side);
          final neighborhoodIndices = {
            for (final span in spans)
              if ((span.routeLegIndex - turnIndex).abs() <= 1)
                span.routeLegIndex,
          };
          expect(
            neighborhoodIndices,
            containsAll([turnIndex, turnIndex + 1]),
            reason: 'seed=$seed side=$side has wall spans across its turn',
          );
        }

        final poses = <({String tag, double? progress, bool before})>[
          (tag: 'before', progress: null, before: true),
          for (final progress in [1.0, .75, .5, .25, 0.0])
            (
              tag:
                  'bend_${(progress * 100).round().toString().padLeft(3, '0')}',
              progress: progress,
              before: false,
            ),
        ];
        for (final pose in poses) {
          final progress = pose.progress;
          final distance = pose.before
              ? turn.distanceMeters - .01
              : turn.distanceMeters + speed * .18 * (1 - progress!);
          final art = _sceneForCapture(
            images: images,
            course: course,
            distance: distance,
            completedTurns: pose.before ? turnIndex : turnIndex + 1,
            activeTurn: turn,
            bendDirection: pose.before
                ? (turnIndex == 0
                      ? null
                      : course.turns[turnIndex - 1].direction)
                : turn.direction,
            bendProgress: progress ?? 0,
            lane: lane,
            viewportHeight: height,
            deltaSeconds: .125,
          );
          final spans = art.facadeWallSpansForTesting(side: -1);
          expect(
            spans.map((span) => span.routeLegIndex),
            contains(turnIndex),
            reason: 'seed=$seed ${pose.tag} keeps the incoming wall span',
          );
          final picture = ui.PictureRecorder();
          final canvas = Canvas(picture, Rect.fromLTWH(0, 0, 360, height));
          art.render(canvas);
          final recorded = picture.endRecording();
          final image = await recorded.toImage(360, height.toInt());
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(png, isNotNull);
            final file = File(
              'artifacts/temple_run/wall_depth_candidates/generated_seed_${seed}_turn_${turnIndex}_${pose.tag}_lane_${lane.toInt()}_${height.toInt()}.png',
            )..createSync(recursive: true);
            file.writeAsBytesSync(
              png!.buffer.asUint8List(
                png.offsetInBytes,
                png.offsetInBytes + png.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
            recorded.dispose();
          }
        }
      }
    } finally {
      for (final image in images.values) {
        image.dispose();
      }
    }
  });

  test(
    'captures generated facade material seams across speeds and seeds',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      const seeds = [17, 20261015, 20261018, 314159];
      const targetTimes = [8.0, 90.0, 250.0];
      try {
        for (var seedIndex = 0; seedIndex < seeds.length; seedIndex++) {
          final seed = seeds[seedIndex];
          final course = TempleRunCourseGenerator(math.Random(seed)).generate();
          final spanScene = _sceneForCapture(
            images: images,
            course: course,
            distance: 0,
            completedTurns: 0,
            activeTurn: null,
            bendDirection: null,
            bendProgress: 0,
            lane: 1,
            viewportHeight: 640,
            deltaSeconds: 0,
            pursuersVisible: false,
          );

          for (var timeIndex = 0; timeIndex < targetTimes.length; timeIndex++) {
            final targetTime = targetTimes[timeIndex];
            final side = (seedIndex + timeIndex).isEven ? -1 : 1;
            final spans = spanScene.facadeWallSpansForTesting(side: side);
            final candidates = <_FacadeTileBoundary>[];
            for (final span in spans) {
              var boundary =
                  (span.wallArcStart / TempleRunArt.wallTileLengthMeters)
                          .floor() *
                      TempleRunArt.wallTileLengthMeters +
                  TempleRunArt.wallTileLengthMeters;
              while (boundary < span.wallArcEnd) {
                if (boundary > span.wallArcStart + .25 &&
                    boundary < span.wallArcEnd - .25) {
                  final beforeKind = TempleRunArt.wallTileKindForArc(
                    wallArc: boundary - .001,
                    side: side.toDouble(),
                  );
                  final afterKind = TempleRunArt.wallTileKindForArc(
                    wallArc: boundary + .001,
                    side: side.toDouble(),
                  );
                  final routeDistance =
                      span.wallStart + boundary - span.wallArcStart;
                  final isWellAwayFromTurns = course.turns.every(
                    (turn) => (turn.distanceMeters - routeDistance).abs() > 8,
                  );
                  if (beforeKind != afterKind && isWellAwayFromTurns) {
                    candidates.add(
                      _FacadeTileBoundary(
                        routeDistance: routeDistance,
                        beforeKind: beforeKind,
                        afterKind: afterKind,
                        elapsedSeconds:
                            TempleRunRules.elapsedForGenerationDistance(
                              routeDistance,
                            ),
                      ),
                    );
                  }
                }
                boundary += TempleRunArt.wallTileLengthMeters;
              }
            }
            expect(
              candidates,
              isNotEmpty,
              reason: 'seed=$seed has non-turn material tile seams',
            );
            candidates.sort(
              (a, b) => (a.elapsedSeconds - targetTime).abs().compareTo(
                (b.elapsedSeconds - targetTime).abs(),
              ),
            );
            final seam = candidates.first;
            expect(
              (seam.elapsedSeconds - targetTime).abs(),
              lessThan(2.0),
              reason: 'seed=$seed finds a seam near ${targetTime}s',
            );

            final captureDistance = seam.routeDistance - 8.5;
            final captureTime = TempleRunRules.elapsedForGenerationDistance(
              captureDistance,
            );
            final speed = TempleRunRules.speedForElapsed(captureTime);
            for (var frame = 0; frame < 3; frame++) {
              final distance = captureDistance + speed * frame / 60;
              final completed = course.turns
                  .where((turn) => turn.distanceMeters <= distance)
                  .length;
              final active =
                  completed < course.turns.length &&
                      course.turns[completed].contains(distance)
                  ? course.turns[completed]
                  : null;
              final art = _sceneForCapture(
                images: images,
                course: course,
                distance: distance,
                completedTurns: completed,
                activeTurn: active,
                bendDirection: completed == 0
                    ? null
                    : course.turns[completed - 1].direction,
                bendProgress: 0,
                lane: 1,
                viewportHeight: 640,
                deltaSeconds: 1 / 60,
                pursuersVisible: false,
              );
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(
                recorder,
                const Rect.fromLTWH(0, 0, 360, 640),
              );
              art.render(canvas);
              final picture = recorder.endRecording();
              final image = await picture.toImage(360, 640);
              try {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                expect(png, isNotNull);
                final name =
                    'generated_seed_${seed}_tile_${targetTime.toInt()}s_${side < 0 ? 'left' : 'right'}_${seam.beforeKind.name}_to_${seam.afterKind.name}_frame_$frame';
                final file = File(
                  'artifacts/temple_run/wall_depth_candidates/$name.png',
                )..createSync(recursive: true);
                file.writeAsBytesSync(
                  png!.buffer.asUint8List(
                    png.offsetInBytes,
                    png.offsetInBytes + png.lengthInBytes,
                  ),
                );
              } finally {
                image.dispose();
                picture.dispose();
              }
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

  test(
    'captures settled straight walls across generated routes and speeds',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      const seeds = [17, 20261015, 20261018, 314159, 424242, 8675309];
      const targetTimes = [8.0, 30.0, 60.0, 90.0, 120.0, 180.0, 240.0, 290.0];
      try {
        for (final seed in seeds) {
          final course = TempleRunCourseGenerator(math.Random(seed)).generate();
          for (
            var sampleIndex = 0;
            sampleIndex < targetTimes.length;
            sampleIndex++
          ) {
            final targetTime = targetTimes[sampleIndex];
            final targetDistance = TempleRunRules.distanceForGeneration(
              targetTime,
            );
            final straightSamples = <double>[];
            for (var leg = 0; leg <= course.turns.length; leg++) {
              final previousTurn = leg == 0 ? null : course.turns[leg - 1];
              final upcomingTurn = leg == course.turns.length
                  ? null
                  : course.turns[leg];
              final straightStart = (previousTurn?.windowEndMeters ?? 0) + 8;
              final straightEnd =
                  (upcomingTurn?.windowStartMeters ??
                      course.totalDistanceMeters) -
                  8;
              if (straightEnd > straightStart) {
                straightSamples.add(
                  targetDistance.clamp(straightStart, straightEnd).toDouble(),
                );
              }
            }
            expect(straightSamples, isNotEmpty);
            straightSamples.sort(
              (a, b) =>
                  (TempleRunRules.elapsedForGenerationDistance(a) - targetTime)
                      .abs()
                      .compareTo(
                        (TempleRunRules.elapsedForGenerationDistance(b) -
                                targetTime)
                            .abs(),
                      ),
            );
            final distance = straightSamples.first;
            final actualTime = TempleRunRules.elapsedForGenerationDistance(
              distance,
            );
            final completed = course.turns
                .where((turn) => turn.distanceMeters <= distance)
                .length;
            final previousTurn = completed == 0
                ? null
                : course.turns[completed - 1];
            expect(
              previousTurn == null || distance > previousTurn.windowEndMeters,
              isTrue,
              reason: 'seed=$seed target=${targetTime}s is clear of last turn',
            );
            final nextTurn = completed >= course.turns.length
                ? null
                : course.turns[completed];
            final distanceToNextTurn = nextTurn == null
                ? double.infinity
                : nextTurn.distanceMeters - distance;
            final sceneTurn =
                nextTurn != null &&
                    distanceToNextTurn >= 0 &&
                    distanceToNextTurn <= 80
                ? nextTurn
                : null;
            final lane = (sampleIndex % 3).toDouble();
            final art = _sceneForCapture(
              images: images,
              course: course,
              distance: distance,
              completedTurns: completed,
              activeTurn: sceneTurn,
              bendDirection: completed == 0
                  ? null
                  : course.turns[completed - 1].direction,
              bendProgress: 0,
              lane: lane,
              viewportHeight: 782,
              deltaSeconds: 1 / 60,
              pursuersVisible: false,
            );
            expect(
              art.cameraHeadingForTesting,
              closeTo(_expectedHeadingAfterTurns(course, completed), 1e-8),
              reason:
                  'seed=$seed ${actualTime.toStringAsFixed(1)}s uses settled heading',
            );
            expect(
              art
                  .facadeWallSpansForTesting(side: -1)
                  .map((span) => span.routeLegIndex),
              contains(completed),
              reason:
                  'seed=$seed ${actualTime.toStringAsFixed(1)}s keeps current wall leg',
            );

            final recorder = ui.PictureRecorder();
            final canvas = Canvas(
              recorder,
              const Rect.fromLTWH(0, 0, 360, 782),
            );
            art.render(canvas);
            final picture = recorder.endRecording();
            final image = await picture.toImage(360, 782);
            try {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              expect(png, isNotNull);
              final file = File(
                'artifacts/temple_run/wall_depth_candidates/straight_seed_${seed}_${targetTime.toInt()}s_at_${actualTime.toStringAsFixed(1)}s_lane_${lane.toInt()}_360x782.png',
              )..createSync(recursive: true);
              file.writeAsBytesSync(
                png!.buffer.asUint8List(
                  png.offsetInBytes,
                  png.offsetInBytes + png.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
              picture.dispose();
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

  test(
    'captures straight views where the second future facade leg reaches the viewport',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      const seeds = [17, 20261015, 20261018, 314159, 424242, 8675309];
      var candidateCount = 0;
      try {
        for (final seed in seeds) {
          final course = TempleRunCourseGenerator(math.Random(seed)).generate();
          final art = TempleRunArt(
            images: images,
            useImageAssets: true,
            viewportWidth: 360,
            viewportHeight: 782,
          );
          var capturesForSeed = 0;
          for (
            var completed = 0;
            completed + 2 < course.turns.length && capturesForSeed < 4;
            completed++
          ) {
            final previousTurn = completed == 0
                ? null
                : course.turns[completed - 1];
            final nextTurn = course.turns[completed];
            final straightStart = (previousTurn?.windowEndMeters ?? 0) + 3;
            final straightEnd = nextTurn.windowStartMeters - 3;
            if (straightEnd <= straightStart) continue;
            final distance = (straightStart + straightEnd) / 2;
            final actualTime = TempleRunRules.elapsedForGenerationDistance(
              distance,
            );
            final upcoming = distance <= nextTurn.distanceMeters
                ? nextTurn
                : null;
            art.updateScene(
              course: course,
              distanceMeters: distance,
              lane: TempleRunRules.centerLane,
              visualLane: 1,
              jumpRemaining: 0,
              slideRemaining: 0,
              runnerFrame: actualTime,
              activeTurn: upcoming,
              bendProgress: 0,
              bendDirection: previousTurn?.direction,
              completedTurnCount: completed,
              guardianVisible: false,
              pursuersVisible: false,
              failureVisible: false,
              shieldVisible: false,
              boostVisible: false,
            );
            final visibleWindow = art.facadeVisibleWindowForTesting;
            if (visibleWindow == null) continue;
            final futureLegIndex = completed + 2;
            TempleRunFacadeWallSpan? futureSpan;
            var side = -1;
            for (final candidateSide in const [-1, 1]) {
              for (final span in art.facadeWallSpansForTesting(
                side: candidateSide,
              )) {
                if (span.routeLegIndex != futureLegIndex) continue;
                final overlapStart = math.max(
                  span.wallStart,
                  visibleWindow.start,
                );
                final overlapEnd = math.min(span.wallEnd, visibleWindow.end);
                if (overlapEnd <= overlapStart) continue;
                if (!_wallSpanProjectsIntoViewport(
                  art: art,
                  span: span,
                  start: overlapStart,
                  end: overlapEnd,
                  width: 360,
                  height: 782,
                )) {
                  continue;
                }
                futureSpan = span;
                side = candidateSide;
                break;
              }
              if (futureSpan != null) break;
            }
            if (futureSpan == null) continue;

            final recorder = ui.PictureRecorder();
            final canvas = Canvas(
              recorder,
              const Rect.fromLTWH(0, 0, 360, 782),
            );
            art.render(canvas);
            final picture = recorder.endRecording();
            final image = await picture.toImage(360, 782);
            try {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              expect(png, isNotNull);
              final file = File(
                'artifacts/temple_run/wall_depth_candidates/future_facade_seed_${seed}_time_${actualTime.toStringAsFixed(1)}s_current_leg_${completed}_culled_leg_${futureLegIndex}_${side < 0 ? 'left' : 'right'}_360x782.png',
              )..createSync(recursive: true);
              file.writeAsBytesSync(
                png!.buffer.asUint8List(
                  png.offsetInBytes,
                  png.offsetInBytes + png.lengthInBytes,
                ),
              );
              candidateCount++;
              capturesForSeed++;
            } finally {
              image.dispose();
              picture.dispose();
            }
          }
        }
        expect(
          candidateCount,
          greaterThanOrEqualTo(4),
          reason:
              'the generated fixtures should include straight frames with a visible second-future wall leg',
        );
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );
}

bool _wallSpanProjectsIntoViewport({
  required TempleRunArt art,
  required TempleRunFacadeWallSpan span,
  required double start,
  required double end,
  required double width,
  required double height,
}) {
  final routeLength = span.wallEnd - span.wallStart;
  if (routeLength <= 0) return false;
  final firstAmount = ((start - span.wallStart) / routeLength).clamp(0.0, 1.0);
  final lastAmount = ((end - span.wallStart) / routeLength).clamp(0.0, 1.0);
  final steps = math.max(1, ((end - start) / .5).ceil());
  for (var index = 0; index <= steps; index++) {
    final routeAmount =
        firstAmount + (lastAmount - firstAmount) * index / steps;
    final world = Offset.lerp(span.frontStart, span.frontEnd, routeAmount)!;
    final ground = art.projectWorldPointForTesting(world);
    if (ground == null ||
        ground.dx < -1 ||
        ground.dx > width + 1 ||
        ground.dy < 0) {
      continue;
    }
    final scale =
        (ground.dy - art.horizonYForTesting) / art.cameraHeightForTesting;
    if (scale <= 0) continue;
    final facadeTop = ground.dy - TempleRunArt.facadeHeightMeters * scale;
    if (facadeTop <= height) return true;
  }
  return false;
}

double _expectedHeadingAfterTurns(TempleRunCourse course, int completed) {
  var heading = 0.0;
  for (var index = 0; index < completed; index++) {
    heading += course.turns[index].direction == TempleRunTurnDirection.right
        ? math.pi / 2
        : -math.pi / 2;
  }
  return heading;
}

TempleRunArt _sceneForCapture({
  required Map<String, ui.Image> images,
  required TempleRunCourse course,
  required double distance,
  required int completedTurns,
  required TempleRunTurn? activeTurn,
  required TempleRunTurnDirection? bendDirection,
  required double bendProgress,
  required double lane,
  required double viewportHeight,
  required double deltaSeconds,
  bool pursuersVisible = true,
}) {
  final art = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: 360,
    viewportHeight: viewportHeight,
  );
  art.updateScene(
    course: course,
    distanceMeters: distance,
    lane: TempleRunRules.centerLane,
    visualLane: lane,
    jumpRemaining: 0,
    slideRemaining: 0,
    runnerFrame: distance,
    activeTurn: activeTurn,
    bendProgress: bendProgress,
    bendDirection: bendDirection,
    completedTurnCount: completedTurns,
    guardianVisible: false,
    pursuersVisible: pursuersVisible,
    failureVisible: false,
    shieldVisible: false,
    boostVisible: false,
    deltaSeconds: deltaSeconds,
  );
  return art;
}

class _FacadeTileBoundary {
  const _FacadeTileBoundary({
    required this.routeDistance,
    required this.beforeKind,
    required this.afterKind,
    required this.elapsedSeconds,
  });

  final double routeDistance;
  final TempleRunWallTileKind beforeKind;
  final TempleRunWallTileKind afterKind;
  final double elapsedSeconds;
}

Future<ByteData> _renderRawRgba({
  required Map<String, ui.Image> images,
  required TempleRunCourse course,
  required TempleRunTurn activeTurn,
  required TempleRunTurnDirection bendDirection,
  required int completedTurnCount,
  required double distanceMeters,
  required double visualLane,
  required double bendProgress,
}) async {
  final art = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: 360,
    viewportHeight: 640,
  );
  art.updateScene(
    course: course,
    distanceMeters: distanceMeters,
    lane: TempleRunRules.centerLane,
    visualLane: visualLane,
    jumpRemaining: 0,
    slideRemaining: 0,
    runnerFrame: 1,
    activeTurn: activeTurn,
    bendProgress: bendProgress,
    bendDirection: bendDirection,
    completedTurnCount: completedTurnCount,
    guardianVisible: false,
    failureVisible: false,
    shieldVisible: false,
    boostVisible: false,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 360, 640));
  art.render(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 640);
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      throw StateError('Unable to read rendered RGBA bytes.');
    }
    return rgba;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _countPixels(
  ByteData rgba,
  int width,
  Rect region,
  bool Function(int red, int green, int blue) matches,
) {
  var count = 0;
  final left = region.left.floor().clamp(0, width).toInt();
  final right = region.right.ceil().clamp(0, width).toInt();
  final imageHeight = rgba.lengthInBytes ~/ (width * 4);
  final top = region.top.floor().clamp(0, imageHeight).toInt();
  final bottom = region.bottom.ceil().clamp(0, imageHeight).toInt();
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * width + x) * 4;
      if (matches(
        rgba.getUint8(offset),
        rgba.getUint8(offset + 1),
        rgba.getUint8(offset + 2),
      )) {
        count++;
      }
    }
  }
  return count;
}

int _countMismatchedPixels(
  ByteData first,
  ByteData second,
  int width,
  Rect region,
) {
  var count = 0;
  final left = region.left.floor().clamp(0, width).toInt();
  final right = region.right.ceil().clamp(0, width).toInt();
  final imageHeight = first.lengthInBytes ~/ (width * 4);
  final top = region.top.floor().clamp(0, imageHeight).toInt();
  final bottom = region.bottom.ceil().clamp(0, imageHeight).toInt();
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * width + x) * 4;
      var mismatch = false;
      for (var channel = 0; channel < 4; channel++) {
        if (first.getUint8(offset + channel) !=
            second.getUint8(offset + channel)) {
          mismatch = true;
          break;
        }
      }
      if (mismatch) count++;
    }
  }
  return count;
}

class _CaptureSpec {
  const _CaptureSpec(
    this.name,
    this.size,
    this.distance,
    this.completedTurns,
    this.direction, {
    this.bendProgress = 0,
    this.visualLane,
  });

  final String name;
  final Size size;
  final double distance;
  final int completedTurns;
  final TempleRunTurnDirection? direction;
  final double bendProgress;
  final double? visualLane;
}
