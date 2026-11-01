import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'captures image-backed streetscape hazards in connected alley views',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      expect(images.keys, containsAll(TempleRunArt.requiredImageAssets));

      final captures = <_CaptureSpec>[
        const _CaptureSpec(
          name: 'hurdle_near_single_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 1,
              distanceMeters: 6,
              lane: TempleRunRules.firstLane,
              kind: TempleRunObstacleKind.hurdle,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'hurdle_far_fullroad_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 2,
              distanceMeters: 36,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.hurdle,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'arch_near_single_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 3,
              distanceMeters: 6,
              lane: TempleRunRules.lastLane,
              kind: TempleRunObstacleKind.arch,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'arch_far_fullroad_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 4,
              distanceMeters: 36,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.arch,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'arch_hoarding_32m_fullroad_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 31,
              distanceMeters: 32,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.arch,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'arch_hoarding_12m_fullroad_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 32,
              distanceMeters: 12,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.arch,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'arch_hoarding_4m_fullroad_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 33,
              distanceMeters: 4,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.arch,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'arch_hoarding_contact_run_360x640',
          size: Size(360, 640),
          distance: 2.6,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 34,
              distanceMeters: 2.6,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.arch,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'arch_hoarding_contact_slide_360x640',
          size: Size(360, 640),
          distance: 2.6,
          slideRemaining: .36,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 35,
              distanceMeters: 2.6,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.arch,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'rubble_near_single_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 5,
              distanceMeters: 6,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.rubble,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'rubble_far_fullroad_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 6,
              distanceMeters: 36,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.rubble,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'gap_near_single_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 7,
              distanceMeters: 6,
              lane: TempleRunRules.firstLane,
              kind: TempleRunObstacleKind.gap,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'gap_far_fullroad_360x640',
          size: Size(360, 640),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 8,
              distanceMeters: 36,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.gap,
              span: TempleRunObstacleSpan.fullRoad,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'narrow_safe0_bank_entrance_360x640',
          size: Size(360, 640),
          distance: 6.5,
          runnerLane: TempleRunRules.firstLane,
          visualLane: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 9,
              distanceMeters: 8,
              lane: TempleRunRules.firstLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathLengthMeters,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'narrow_safe1_middle_360x640',
          size: Size(360, 640),
          distance: 10,
          runnerLane: TempleRunRules.centerLane,
          visualLane: 1,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 10,
              distanceMeters: 8,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathLengthMeters,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'narrow_safe2_bank_exit_360x640',
          size: Size(360, 640),
          distance: 13.5,
          runnerLane: TempleRunRules.lastLane,
          visualLane: 2,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 11,
              distanceMeters: 8,
              lane: TempleRunRules.lastLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathLengthMeters,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'narrow_bank_passed_360x640',
          size: Size(360, 640),
          distance: 14.75,
          runnerLane: TempleRunRules.lastLane,
          visualLane: 2,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 12,
              distanceMeters: 8,
              lane: TempleRunRules.lastLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathLengthMeters,
            ),
          ],
        ),
        _CaptureSpec(
          name: 'narrow_turn_context_360x640',
          size: const Size(360, 640),
          distance: 60.5,
          runnerLane: TempleRunRules.firstLane,
          visualLane: 0,
          completedTurns: 1,
          bendDirection: TempleRunTurnDirection.left,
          activeTurn: _leftTurn,
          turn: _leftTurn,
          obstacles: const <TempleRunObstacle>[
            TempleRunObstacle(
              id: 13,
              distanceMeters: 60,
              lane: TempleRunRules.firstLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathLengthMeters,
            ),
          ],
        ),
        const _CaptureSpec(
          name: 'mixed_streetscape_row_360x820',
          size: Size(360, 820),
          distance: 0,
          obstacles: <TempleRunObstacle>[
            TempleRunObstacle(
              id: 14,
              distanceMeters: 8,
              lane: TempleRunRules.firstLane,
              kind: TempleRunObstacleKind.hurdle,
            ),
            TempleRunObstacle(
              id: 15,
              distanceMeters: 20,
              lane: TempleRunRules.lastLane,
              kind: TempleRunObstacleKind.arch,
            ),
            TempleRunObstacle(
              id: 16,
              distanceMeters: 32,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.rubble,
            ),
            TempleRunObstacle(
              id: 17,
              distanceMeters: 44,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.gap,
              span: TempleRunObstacleSpan.fullRoad,
            ),
            TempleRunObstacle(
              id: 18,
              distanceMeters: 56,
              lane: TempleRunRules.centerLane,
              kind: TempleRunObstacleKind.narrowPath,
              lengthMeters: TempleRunRules.narrowPathLengthMeters,
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
            turns: capture.turn == null
                ? const <TempleRunTurn>[]
                : <TempleRunTurn>[capture.turn!],
            totalDistanceMeters: 180,
          );
          art.updateScene(
            course: course,
            distanceMeters: capture.distance,
            lane: capture.runnerLane,
            visualLane: capture.visualLane,
            jumpRemaining: 0,
            slideRemaining: capture.slideRemaining,
            runnerFrame: 1,
            activeTurn: capture.activeTurn,
            bendProgress: 0,
            bendDirection: capture.bendDirection,
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
            expect(image.width, capture.size.width.toInt());
            expect(image.height, capture.size.height.toInt());
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(png, isNotNull);
            final pngBytes = png!;
            expect(pngBytes.lengthInBytes, greaterThan(100));

            final rgba = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(rgba, isNotNull);
            final opaquePixels = _countOpaquePixels(
              rgba!,
              capture.size.width.toInt(),
            );
            expect(
              opaquePixels,
              greaterThan(image.width * image.height ~/ 5),
              reason: 'capture ${capture.name} was unexpectedly empty',
            );

            final bytes = pngBytes.buffer.asUint8List(
              pngBytes.offsetInBytes,
              pngBytes.offsetInBytes + pngBytes.lengthInBytes,
            );
            final file = File(
              'artifacts/temple_run/streetscape_review/${capture.name}.png',
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

int _countOpaquePixels(ByteData rgba, int width) {
  var count = 0;
  final height = rgba.lengthInBytes ~/ (width * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (rgba.getUint8((y * width + x) * 4 + 3) > 0) count++;
    }
  }
  return count;
}

const _leftTurn = TempleRunTurn(
  distanceMeters: 54,
  direction: TempleRunTurnDirection.left,
  windowStartMeters: 35,
  windowEndMeters: 58,
);

class _CaptureSpec {
  const _CaptureSpec({
    required this.name,
    required this.size,
    required this.distance,
    required this.obstacles,
    this.runnerLane = TempleRunRules.centerLane,
    this.visualLane,
    this.turn,
    this.activeTurn,
    this.bendDirection,
    this.completedTurns = 0,
    this.slideRemaining = 0,
  });

  final String name;
  final Size size;
  final double distance;
  final List<TempleRunObstacle> obstacles;
  final int runnerLane;
  final double? visualLane;
  final TempleRunTurn? turn;
  final TempleRunTurn? activeTurn;
  final TempleRunTurnDirection? bendDirection;
  final int completedTurns;
  final double slideRemaining;
}
