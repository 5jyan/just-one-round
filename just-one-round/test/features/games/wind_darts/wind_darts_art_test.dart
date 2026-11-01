import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_art.dart';

void main() {
  test('v4 runtime art contract loads the nine shared assets', () {
    expect(WindDartsArtAssets.assetPaths, hasLength(9));
    expect(WindDartsArtAssets.flameImagePaths, hasLength(9));
    expect(
      WindDartsArtAssets.assetPaths,
      containsAll(<String>[
        WindDartsArtAssets.scoreParchment,
        WindDartsArtAssets.aimGaugeFrame,
        WindDartsArtAssets.aimGaugeFill,
        WindDartsArtAssets.opponentVictory,
        WindDartsArtAssets.victorySmoke,
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

  test('impact bursts render deterministic bounded hit-kind samples', () async {
    Future<List<int>> raster(
      WindDartsImpactKind kind,
      double elapsed, {
      bool golden = false,
    }) async {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 160, 160));
      WindDartsArt.drawImpactBurst(
        canvas,
        center: const Offset(80, 80),
        kind: kind,
        elapsed: elapsed,
        golden: golden,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(160, 160);
      final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
      image.dispose();
      return List<int>.from(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }

    int activePixels(List<int> rgba) {
      var active = 0;
      for (var index = 3; index < rgba.length; index += 4) {
        if (rgba[index] != 0) active++;
      }
      return active;
    }

    const kinds = [
      WindDartsImpactKind.double,
      WindDartsImpactKind.triple,
      WindDartsImpactKind.singleBull,
      WindDartsImpactKind.doubleBull,
    ];
    final midSamples = <WindDartsImpactKind, List<int>>{};
    for (final kind in kinds) {
      final early = await raster(kind, 0.05);
      final mid = await raster(kind, 0.25);
      final shards = await raster(kind, 0.5);
      final expired = await raster(kind, 0.71);
      expect(activePixels(early), greaterThan(0), reason: '$kind early');
      expect(activePixels(mid), greaterThan(0), reason: '$kind mid');
      expect(activePixels(shards), greaterThan(0), reason: '$kind shards');
      expect(activePixels(expired), 0, reason: '$kind expired');
      midSamples[kind] = mid;
    }
    expect(
      activePixels(midSamples[WindDartsImpactKind.doubleBull]!),
      greaterThan(activePixels(midSamples[WindDartsImpactKind.double]!)),
    );

    final goldenTriple = await raster(
      WindDartsImpactKind.triple,
      0.25,
      golden: true,
    );
    expect(
      activePixels(goldenTriple),
      greaterThan(activePixels(midSamples[WindDartsImpactKind.triple]!)),
    );
    expect(
      goldenTriple,
      equals(await raster(WindDartsImpactKind.triple, 0.25, golden: true)),
    );
  });
}
