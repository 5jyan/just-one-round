import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('집에 좀 가자 런타임 에셋은 계약된 크기로 패키징된다', () async {
    const contract = {
      'assets/images/homebound_run/alley_background.png': (864, 1920),
      'assets/images/homebound_run/asphalt.png': (512, 512),
      'assets/images/homebound_run/wall_plaster_a.png': (1024, 768),
      'assets/images/homebound_run/wall_plaster_b.png': (1024, 768),
      'assets/images/homebound_run/wall_window.png': (1024, 768),
      'assets/images/homebound_run/wall_door.png': (1024, 768),
      'assets/images/homebound_run/wall_mural.png': (1024, 768),
      'assets/images/homebound_run/wall_house_brick.png': (1024, 768),
      'assets/images/homebound_run/wall_house_sage.png': (1024, 768),
      'assets/images/homebound_run/wall_house_garden.png': (1024, 768),
      'assets/images/homebound_run/wall_shopfront.png': (1024, 768),
      'assets/images/homebound_run/street_house_brick.png': (1024, 768),
      'assets/images/homebound_run/street_house_sage.png': (1024, 768),
      'assets/images/homebound_run/street_shopfront.png': (1024, 768),
      'assets/images/homebound_run/streetscape_barricade.png': (512, 256),
      'assets/images/homebound_run/streetscape_scaffold_crossbeam.png': (
        512,
        512,
      ),
      'assets/images/homebound_run/streetscape_covered_pallet_materials.png': (
        512,
        384,
      ),
      'assets/images/homebound_run/wall_schoolfront.png': (1024, 768),
      'assets/images/homebound_run/wall_constructionfront.png': (1024, 768),
      'assets/images/homebound_run/student_run.png': (768, 288),
      'assets/images/homebound_run/student_jump.png': (192, 288),
      'assets/images/homebound_run/student_slide.png': (192, 288),
      'assets/images/homebound_run/pursuers.png': (512, 384),
      'assets/images/homebound_run/pursuers_run.png': (1536, 768),
      'assets/images/homebound_run/obstacle_hurdle.png': (512, 256),
      'assets/images/homebound_run/obstacle_jump_variant.png': (512, 256),
      'assets/images/homebound_run/obstacle_shutter.png': (512, 512),
      'assets/images/homebound_run/obstacle_slide_variant.png': (512, 512),
      'assets/images/homebound_run/obstacle_stack.png': (256, 384),
      'assets/images/homebound_run/home_gate.png': (512, 512),
      'assets/images/homebound_run/coin.png': (64, 64),
      'assets/images/homebound_run/magnet.png': (64, 64),
      'assets/images/homebound_run/shield.png': (64, 64),
      'assets/images/homebound_run/boost.png': (64, 64),
    };

    for (final entry in contract.entries) {
      final data = await rootBundle.load(entry.key);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      addTearDown(codec.dispose);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      expect(
        (frame.image.width, frame.image.height),
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      TempleRunArt.requiredImageAssets,
      containsAll(
        contract.keys.map((path) => path.substring('assets/images/'.length)),
      ),
    );
    expect(
      TempleRunArt.requiredImageAssets,
      isNot(
        anyOf(
          contains(TempleRunArt.facadeSchoolAsset),
          contains(TempleRunArt.facadeShopsAsset),
          contains(TempleRunArt.facadeHomesAsset),
          contains(TempleRunArt.facadeConstructionAsset),
        ),
      ),
    );
  });

  test(
    'wall art keeps the authored 256x192 grid at a crisp 4x runtime size',
    () async {
      expect(TempleRunArt.wallRuntimeScale, 4);
      expect(
        (TempleRunArt.wallAuthoredWidth, TempleRunArt.wallAuthoredHeight),
        (256, 192),
      );
      expect(
        (TempleRunArt.wallSourceWidth, TempleRunArt.wallSourceHeight),
        (1024, 768),
      );

      final images = await TempleRunArt.loadImageAssets();
      addTearDown(() {
        for (final image in images.values) {
          image.dispose();
        }
      });
      for (final asset in [
        TempleRunArt.wallPlasterAAsset,
        TempleRunArt.wallPlasterBAsset,
        TempleRunArt.wallWindowAsset,
        TempleRunArt.wallDoorAsset,
        TempleRunArt.wallMuralAsset,
        TempleRunArt.wallHouseBrickAsset,
        TempleRunArt.wallHouseSageAsset,
        TempleRunArt.wallHouseGardenAsset,
        TempleRunArt.wallShopfrontAsset,
        TempleRunArt.streetHouseBrickAsset,
        TempleRunArt.streetHouseSageAsset,
        TempleRunArt.streetShopfrontAsset,
        TempleRunArt.wallSchoolfrontAsset,
        TempleRunArt.wallConstructionfrontAsset,
      ]) {
        final rgba = await images[asset]!.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(rgba, isNotNull, reason: asset);
        final bytes = rgba!.buffer.asUint8List(
          rgba.offsetInBytes,
          rgba.offsetInBytes + rgba.lengthInBytes,
        );
        for (var index = 3; index < bytes.length; index += 4) {
          expect(bytes[index], 255, reason: '$asset must be opaque');
        }
      }
    },
  );

  test(
    'image preview loader decodes the same production bundle used by the game',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      expect(images.keys, containsAll(TempleRunArt.requiredImageAssets));
      expect(images[TempleRunArt.runnerRunAsset]!.width, 768);
      expect(images[TempleRunArt.runnerRunAsset]!.height, 288);
      for (final image in images.values) {
        addTearDown(image.dispose);
      }
    },
  );

  test(
    'final alpha footprints retain pose and obstacle contact anchors',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      addTearDown(() {
        for (final image in images.values) {
          image.dispose();
        }
      });

      const expected = {
        TempleRunArt.runnerRunAsset: (
          left: 44,
          top: 34,
          right: 730,
          bottom: 272,
        ),
        TempleRunArt.runnerJumpAsset: (
          left: 15,
          top: 70,
          right: 177,
          bottom: 272,
        ),
        TempleRunArt.runnerSlideAsset: (
          left: 10,
          top: 147,
          right: 182,
          bottom: 272,
        ),
        TempleRunArt.hurdleAsset: (left: 16, top: 168, right: 496, bottom: 240),
        TempleRunArt.jumpVariantAsset: (
          left: 16,
          top: 100,
          right: 496,
          bottom: 240,
        ),
        TempleRunArt.streetscapeBarricadeAsset: (
          left: 16,
          top: 152,
          right: 496,
          bottom: 240,
        ),
        TempleRunArt.shutterAsset: (
          left: 24,
          top: 144,
          right: 488,
          bottom: 488,
        ),
        TempleRunArt.streetscapeScaffoldAsset: (
          left: 24,
          top: 92,
          right: 488,
          bottom: 488,
        ),
        TempleRunArt.slideVariantAsset: (
          left: 24,
          top: 160,
          right: 488,
          bottom: 488,
        ),
        TempleRunArt.stackAsset: (left: 16, top: 144, right: 240, bottom: 368),
        TempleRunArt.homeGateAsset: (
          left: 24,
          top: 116,
          right: 488,
          bottom: 488,
        ),
      };
      for (final entry in expected.entries) {
        expect(
          await _alphaBounds(images[entry.key]!),
          entry.value,
          reason: entry.key,
        );
      }
    },
  );

  test(
    'image mode renders the production bundle on short and tall routes',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      addTearDown(() {
        for (final image in images.values) {
          image.dispose();
        }
      });
      final course = TempleRunCourse(
        obstacles: const [
          TempleRunObstacle(
            distanceMeters: 8,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.hurdle,
            span: TempleRunObstacleSpan.fullRoad,
          ),
          TempleRunObstacle(
            distanceMeters: 13,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.arch,
          ),
          TempleRunObstacle(
            distanceMeters: 18,
            lane: TempleRunRules.firstLane,
            kind: TempleRunObstacleKind.narrowPath,
            lengthMeters: TempleRunRules.narrowPathLengthMeters,
          ),
          TempleRunObstacle(
            distanceMeters: 26,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.gap,
            span: TempleRunObstacleSpan.fullRoad,
          ),
        ],
        coins: const [TempleRunCoin(distanceMeters: 10, lane: 1)],
        powerUps: const [],
        turns: const [
          TempleRunTurn(
            distanceMeters: 36,
            direction: TempleRunTurnDirection.left,
            windowStartMeters: 27,
            windowEndMeters: 40,
          ),
        ],
        totalDistanceMeters: 80,
      );

      Uint8List? primitiveBytes;
      for (final size in const [Size(360, 640), Size(360, 820)]) {
        final imageArt = TempleRunArt(
          images: images,
          useImageAssets: true,
          viewportWidth: size.width,
          viewportHeight: size.height,
        );
        imageArt.updateScene(
          course: course,
          distanceMeters: 0,
          lane: TempleRunRules.centerLane,
          visualLane: TempleRunRules.centerLane.toDouble(),
          jumpRemaining: 0,
          slideRemaining: 0,
          runnerFrame: 1,
          activeTurn: null,
          bendProgress: 0,
          bendDirection: null,
          completedTurnCount: 0,
          guardianVisible: true,
          failureVisible: false,
          arrivalVisible: true,
          shieldVisible: false,
          boostVisible: false,
        );
        final imageBytes = await _renderPng(imageArt, size);
        expect(imageBytes, isNotEmpty);
        expect(imageBytes.length, greaterThan(1000));

        final primitiveArt = TempleRunArt(
          viewportWidth: size.width,
          viewportHeight: size.height,
        );
        primitiveArt.updateScene(
          course: course,
          distanceMeters: 0,
          lane: TempleRunRules.centerLane,
          visualLane: TempleRunRules.centerLane.toDouble(),
          jumpRemaining: 0,
          slideRemaining: 0,
          runnerFrame: 1,
          activeTurn: null,
          bendProgress: 0,
          bendDirection: null,
          completedTurnCount: 0,
          guardianVisible: true,
          failureVisible: false,
          arrivalVisible: true,
          shieldVisible: false,
          boostVisible: false,
        );
        primitiveBytes = await _renderPng(primitiveArt, size);
        expect(imageBytes, isNot(equals(primitiveBytes)));
      }
    },
  );

  test(
    'variant jump and slide hazards render their generated silhouettes',
    () async {
      final images = await TempleRunArt.loadImageAssets();
      addTearDown(() {
        for (final image in images.values) {
          image.dispose();
        }
      });
      final course = TempleRunCourse(
        obstacles: [
          TempleRunObstacle(
            id: 4,
            distanceMeters: 9,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.hurdle,
            span: TempleRunObstacleSpan.fullRoad,
          ),
          TempleRunObstacle(
            id: 6,
            distanceMeters: 17,
            lane: TempleRunRules.centerLane,
            kind: TempleRunObstacleKind.arch,
            span: TempleRunObstacleSpan.fullRoad,
          ),
        ],
        coins: [],
        powerUps: [],
        turns: [],
        totalDistanceMeters: 40,
      );
      final art = TempleRunArt(
        images: images,
        useImageAssets: true,
        viewportWidth: TempleRunRules.logicalWidth,
        viewportHeight: TempleRunRules.logicalHeight,
      );
      art.updateScene(
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
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
      );
      final bytes = await _renderPng(art, const Size(360, 640));
      expect(bytes.length, greaterThan(1000));
      File('artifacts/temple_run/hazard_variant_capture.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    },
  );
}

Future<({int left, int top, int right, int bottom})> _alphaBounds(
  ui.Image image,
) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  final bytes = data!.buffer.asUint8List(
    data.offsetInBytes,
    data.offsetInBytes + data.lengthInBytes,
  );
  var left = image.width;
  var top = image.height;
  var right = 0;
  var bottom = 0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (bytes[(y * image.width + x) * 4 + 3] == 0) continue;
      if (x < left) left = x;
      if (y < top) top = y;
      if (x + 1 > right) right = x + 1;
      if (y + 1 > bottom) bottom = y + 1;
    }
  }
  return (left: left, top: top, right: right, bottom: bottom);
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
