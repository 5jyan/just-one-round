import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_art.dart';

void main() {
  test('v2 runtime art contract loads the seven shared assets', () {
    expect(WindDartsArtAssets.assetPaths, hasLength(7));
    expect(WindDartsArtAssets.flameImagePaths, hasLength(7));
    expect(
      WindDartsArtAssets.assetPaths,
      containsAll(<String>[
        WindDartsArtAssets.scoreParchment,
        WindDartsArtAssets.aimGaugeFrame,
        WindDartsArtAssets.aimGaugeFill,
      ]),
    );
    expect(WindDartsArt.scoreParchmentSourceSize, const Size(240, 320));
    expect(WindDartsArt.aimGaugeFrameSourceSize, const Size(640, 72));
    expect(WindDartsArt.aimGaugeFillSourceSize, const Size(608, 24));
    expect(WindDartsArt.boardFaceSourceSize, 576);
    expect(WindDartsArt.boardFaceScoringRadius, 228);
    expect(WindDartsArt.boardFaceOuterRadius, 280);
    expect(WindDartsArt.boardNumberOrbitRadius, 260);
  });

  test('raster board alignment follows the scoring coordinate system', () {
    expect(WindDartsArt.visualRotation(0), closeTo(math.pi / 20, 0.000001));
    expect(
      WindDartsArt.visualRotation(WindDartsRules.boardAngle),
      closeTo(0, 0.000001),
    );
    expect(WindDartsArt.numberAngle(0), closeTo(-math.pi / 2, 0.000001));
    expect(
      WindDartsArt.boardNumberAtlasIndexForSector(0),
      19,
      reason: 'the top sector is 20, whose atlas cell is 19',
    );
    expect(WindDartsArt.boardNumberAtlasIndexForSector(1), 0);
    expect(WindDartsArt.boardNumberAtlasIndexForSector(19), 4);
  });

  test('dart atlas cells preserve their authored anchor contract', () {
    expect(WindDartsArt.dartTipAnchor, const Offset(48, 12));
    expect(WindDartsArt.dartSourceRect(0), const Rect.fromLTWH(0, 0, 96, 128));
    expect(WindDartsArt.dartSourceRect(1), const Rect.fromLTWH(96, 0, 96, 128));
    expect(WindDartsArt.dartScaleForBoardRadius(142), closeTo(0.72, 0.000001));
  });

  test(
    'world camera keeps the board fixed while the background reveals more',
    () {
      expect(WindDartsArt.worldBoardRadius, closeTo(63.9, 0.000001));
      final firstShotZoom = WindDartsArt.worldZoomForShotScale(1);
      final lastShotZoom = WindDartsArt.worldZoomForShotScale(0.45);
      final firstShotPoint = WindDartsArt.worldOffsetForZoom(
        const Offset(42, -19),
        firstShotZoom,
      );
      final lastShotPoint = WindDartsArt.worldOffsetForZoom(
        const Offset(42, -19),
        lastShotZoom,
      );
      expect(firstShotPoint.distance, lessThan(lastShotPoint.distance));

      const imageSize = Size(841, 1870);
      const viewportSize = Size(360, 640);
      final firstShotSource = WindDartsArt.backgroundSourceExtentForZoom(
        imageSize: imageSize,
        viewportSize: viewportSize,
        zoom: firstShotZoom,
      );
      final lastShotSource = WindDartsArt.backgroundSourceExtentForZoom(
        imageSize: imageSize,
        viewportSize: viewportSize,
        zoom: lastShotZoom,
      );
      expect(firstShotSource.width, lessThan(lastShotSource.width));
      expect(firstShotSource.height, lessThan(lastShotSource.height));
    },
  );

  test(
    'embedded dart tail keeps its noncentral direction through board rotation',
    () {
      const boardAngle = 0.37;
      const screenTail = Offset(49, -31);
      final localTail = WindDartsArt.toBoardLocalVector(
        WindDartsArt.worldOffsetForZoom(screenTail, 1.82),
        boardAngle,
      );
      expect(localTail.distance, greaterThan(0));
      expect(localTail.dx.abs(), greaterThan(0.1));
      expect(localTail.dy.abs(), greaterThan(0.1));

      final rotation = WindDartsArt.visualRotation(boardAngle);
      final screenTailAgain = Offset(
        localTail.dx * math.cos(rotation) - localTail.dy * math.sin(rotation),
        localTail.dx * math.sin(rotation) + localTail.dy * math.cos(rotation),
      );
      final expectedTail = screenTail / 1.82;
      expect(screenTailAgain.dx, closeTo(expectedTail.dx, 0.000001));
      expect(screenTailAgain.dy, closeTo(expectedTail.dy, 0.000001));
    },
  );
}
