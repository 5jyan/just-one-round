import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'captures both generated narrow lengths and post-turn recovery scene',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      final turn = TempleRunTurn(
        distanceMeters: 40,
        direction: TempleRunTurnDirection.right,
        windowStartMeters: 31,
        windowEndMeters: 43,
      );
      final captures = <_CaptureSpec>[
        _CaptureSpec(
          name: 'narrow_half_3m_entrance_360x640',
          distance: 7.2,
          runnerLane: TempleRunRules.firstLane,
          obstacles: [
            TempleRunObstacle(
              id: 1,
              distanceMeters: 8,
              lane: TempleRunRules.firstLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathHalfLengthMeters,
            ),
          ],
        ),
        _CaptureSpec(
          name: 'narrow_quarter_1_5m_middle_360x640',
          distance: 9,
          runnerLane: TempleRunRules.lastLane,
          obstacles: [
            TempleRunObstacle(
              id: 2,
              distanceMeters: 8,
              lane: TempleRunRules.lastLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathQuarterLengthMeters,
            ),
          ],
        ),
        _CaptureSpec(
          name: 'post_turn_vertical_then_narrow_360x640',
          distance: 44.5,
          runnerLane: TempleRunRules.centerLane,
          completedTurns: 1,
          turn: turn,
          obstacles: [
            const TempleRunObstacle(
              id: 3,
              distanceMeters: 46,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.arch,
              span: TempleRunObstacleSpan.fullRoad,
            ),
            TempleRunObstacle(
              id: 4,
              distanceMeters: 53,
              lane: TempleRunRules.firstLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathQuarterLengthMeters,
            ),
          ],
        ),
        _CaptureSpec(
          name: 'post_turn_narrow_entrance_360x640',
          distance: 50.5,
          runnerLane: TempleRunRules.firstLane,
          completedTurns: 1,
          turn: turn,
          obstacles: [
            const TempleRunObstacle(
              id: 5,
              distanceMeters: 46,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.arch,
              span: TempleRunObstacleSpan.fullRoad,
            ),
            TempleRunObstacle(
              id: 6,
              distanceMeters: 53,
              lane: TempleRunRules.firstLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathQuarterLengthMeters,
            ),
          ],
        ),
      ];

      try {
        for (final capture in captures) {
          final art = TempleRunArt(
            images: images,
            useImageAssets: true,
            viewportWidth: capture.size.width,
            viewportHeight: capture.size.height,
          );
          final course = TempleRunCourse(
            obstacles: capture.obstacles,
            coins: const [],
            powerUps: const [],
            turns: capture.turn == null ? const [] : [capture.turn!],
            totalDistanceMeters: 120,
          );
          art.updateScene(
            course: course,
            distanceMeters: capture.distance,
            lane: capture.runnerLane,
            visualLane: capture.runnerLane.toDouble(),
            jumpRemaining: 0,
            slideRemaining: 0,
            runnerFrame: 1,
            activeTurn: null,
            bendProgress: 0,
            bendDirection: null,
            completedTurnCount: capture.completedTurns,
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
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(png, isNotNull);
            final bytes = png!.buffer.asUint8List(
              png.offsetInBytes,
              png.offsetInBytes + png.lengthInBytes,
            );
            expect(bytes, isNotEmpty);
            final file = File(
              'artifacts/temple_run/narrow_length_review/${capture.name}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes);
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
}

class _CaptureSpec {
  _CaptureSpec({
    required this.name,
    required this.distance,
    required this.runnerLane,
    required this.obstacles,
    this.turn,
    this.completedTurns = 0,
  });

  final String name;
  final double distance;
  final int runnerLane;
  final List<TempleRunObstacle> obstacles;
  final TempleRunTurn? turn;
  final int completedTurns;

  final Size size = const Size(360, 640);
}
