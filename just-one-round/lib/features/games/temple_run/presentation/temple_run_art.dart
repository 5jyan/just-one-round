import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';

/// A small projection value kept public for the game/runtime tests and for a
/// future image reskin. The prototype renderer uses the same values for road,
/// objects, and the player so collision-facing positions never drift apart.
class TempleRunProjection {
  const TempleRunProjection({
    required this.center,
    required this.scale,
    required this.depth,
    required this.roadWidth,
  });

  final Offset center;
  final double scale;
  final double depth;
  final double roadWidth;
}

class _TempleRunRenderItem {
  const _TempleRunRenderItem({required this.depth, required this.draw});

  final double depth;
  final void Function(Canvas canvas) draw;
}

class _RouteState {
  const _RouteState(this.position, this.heading);

  /// Position in the authored X/Z plane. Offset.dx is X and Offset.dy is Z.
  final Offset position;
  final double heading;
}

class TempleRunFacadeHomography {
  const TempleRunFacadeHomography._();

  static Float64List build({
    required Size viewport,
    required double horizonY,
    required double cameraHeight,
    required double focalLength,
    required double cameraTargetDepth,
    required double cameraBackDistance,
    required double cameraHeading,
    required double cameraOriginLateral,
    required double cameraOriginDepth,
    required double facadeHeading,
    required double wallLength,
    required double sourceWidth,
    required double sourceHeight,
    required double wallHeight,
    double bottomHeight = 0,
  }) {
    final pixelsToMeters = wallLength / sourceWidth;
    final headingDelta = facadeHeading - cameraHeading;
    final du = math.sin(headingDelta) * pixelsToMeters;
    final dz = math.cos(headingDelta) * pixelsToMeters;
    final focal = focalLength * (cameraTargetDepth / cameraBackDistance);
    final centerX = viewport.width / 2;
    return Float64List.fromList(<double>[
      centerX * dz + focal * du,
      horizonY * dz,
      0,
      dz,
      0,
      focal * (wallHeight - bottomHeight) / sourceHeight,
      0,
      0,
      0,
      0,
      1,
      0,
      centerX * cameraOriginDepth + focal * cameraOriginLateral,
      horizonY * cameraOriginDepth + focal * (cameraHeight - wallHeight),
      0,
      cameraOriginDepth,
    ]);
  }
}

class _FacadeRouteLeg {
  const _FacadeRouteLeg({
    required this.start,
    required this.end,
    required this.origin,
    required this.heading,
  });

  final double start;
  final double end;
  final Offset origin;
  final double heading;

  Offset centerAt(double distance) =>
      origin + TempleRunArt._forward(heading) * (distance - start);
}

class TempleRunFacadeWallSpan {
  const TempleRunFacadeWallSpan({
    required this.routeLegIndex,
    required this.wallStart,
    required this.wallEnd,
    required this.wallArcStart,
    required this.frontStart,
    required this.frontEnd,
    required this.roofStart,
    required this.roofEnd,
    required this.roofStartPoint,
    required this.roofEndPoint,
  });

  final int routeLegIndex;
  final double wallStart;
  final double wallEnd;
  final double wallArcStart;
  final Offset frontStart;
  final Offset frontEnd;
  final double roofStart;
  final double roofEnd;
  final Offset roofStartPoint;
  final Offset roofEndPoint;

  double get wallArcEnd => wallArcStart + wallEnd - wallStart;
}

class _ProjectedWorldPoint {
  const _ProjectedWorldPoint({
    required this.point,
    required this.depth,
    required this.scale,
  });

  final Offset point;
  final double depth;
  final double scale;
}

class _TempleRunNarrowWorksiteBank {
  const _TempleRunNarrowWorksiteBank({
    required this.width,
    required this.startDistance,
    required this.endDistance,
    required this.innerOffset,
    required this.outerOffset,
  });

  final double width;
  final double startDistance;
  final double endDistance;
  final double innerOffset;
  final double outerOffset;
}

class _ProjectedFacadeOccluder {
  const _ProjectedFacadeOccluder({
    required this.path,
    required this.bounds,
    required this.nearDepth,
    required this.cameraPolygon,
  });

  final Path path;
  final Rect bounds;
  final double nearDepth;
  final List<_CameraPoint> cameraPolygon;
}

class _TempleRunPickupEffect {
  _TempleRunPickupEffect({required this.kind, required this.anchor});

  final _TempleRunCollectibleKind kind;
  final Offset anchor;
  double age = 0;
}

class _CameraPoint {
  const _CameraPoint({
    required this.lateral,
    required this.depth,
    required this.height,
    this.textureU = 0,
    this.textureV = 0,
  });

  final double lateral;
  final double depth;
  final double height;
  final double textureU;
  final double textureV;

  _CameraPoint withTexture(double u, double v) => _CameraPoint(
    lateral: lateral,
    depth: depth,
    height: height,
    textureU: u,
    textureV: v,
  );
}

class _ImageFootprint {
  const _ImageFootprint({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double canvasWidth;
  final double canvasHeight;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get visibleWidth => right - left;
  double get visibleHeight => bottom - top;
  double get bottomPadding => canvasHeight - bottom;

  Rect get sourceRect => Rect.fromLTRB(left, top, right, bottom);

  double heightForVisibleWidth(double widthPx) =>
      widthPx * visibleHeight / visibleWidth;
}

class _TempleRunWallReliefSpec {
  const _TempleRunWallReliefSpec({
    required this.source,
    required this.featureDepth,
    required this.capDepth,
    required this.sillDepth,
  });

  final Rect source;
  final double featureDepth;
  final double capDepth;
  final double sillDepth;
}

class _TempleRunWallVolumeSpec {
  const _TempleRunWallVolumeSpec({
    required this.source,
    required this.frontDepth,
    required this.maskColor,
    required this.sideColor,
    required this.capColor,
    this.usePlasterFront = false,
  });

  final Rect source;
  final double frontDepth;
  final Color maskColor;
  final Color sideColor;
  final Color capColor;
  final bool usePlasterFront;
}

class _TempleRunWallMassSpec {
  const _TempleRunWallMassSpec({
    required this.source,
    required this.depth,
    this.volumes = const <_TempleRunWallVolumeSpec>[],
  });

  final Rect source;
  final double depth;
  final List<_TempleRunWallVolumeSpec> volumes;
}

class _TempleRunFullBleedFacadeSpec {
  const _TempleRunFullBleedFacadeSpec({
    required this.asset,
    required this.setback,
    required this.materialSwatch,
    this.heightExtension = 0,
    this.topCapColor = const Color(0xFFD8CCBC),
  });

  final String asset;
  final double setback;
  final Rect materialSwatch;
  final double heightExtension;
  final Color topCapColor;
}

class _TempleRunFullBleedPropSpec {
  const _TempleRunFullBleedPropSpec({
    required this.source,
    required this.frontDepth,
    required this.sideColor,
    required this.capColor,
  });

  final Rect source;
  final double frontDepth;
  final Color sideColor;
  final Color capColor;
}

enum _TempleRunCollectibleKind { coin, magnet, shield, boost }

/// The authored side-wall schedule. Each entry is one 7.333m world tile; the
/// schedule is sampled from the cumulative wall arc so route turns cannot
/// restart a material block.
enum TempleRunWallTileKind {
  plasterA,
  plasterB,
  window,
  door,
  mural,
  houseBrick,
  houseSage,
  houseGarden,
  shopfront,
  schoolfront,
  constructionfront,
}

enum _TempleRunWallSlotCategory { actualWall, house, shop }

/// Shared projected renderer for 집에 좀 가자.
///
/// The explicit [useImageAssets] switch remains available for deterministic
/// geometry tests and debug captures. Production game and preview entry points
/// opt into the same preloaded image map.
class TempleRunArt extends PositionComponent {
  TempleRunArt({
    Map<String, ui.Image> images = const {},
    this.useImageAssets = false,
    double viewportWidth = TempleRunRules.logicalWidth,
    double viewportHeight = TempleRunRules.logicalHeight,
  }) : _images = Map.unmodifiable(images),
       super(size: Vector2(viewportWidth, viewportHeight), priority: -10);

  static const backgroundAsset = 'homebound_run/alley_background.png';
  static const asphaltAsset = 'homebound_run/asphalt.png';
  static const wallPlasterAAsset = 'homebound_run/wall_plaster_a.png';
  static const wallPlasterBAsset = 'homebound_run/wall_plaster_b.png';
  static const wallWindowAsset = 'homebound_run/wall_window.png';
  static const wallDoorAsset = 'homebound_run/wall_door.png';
  static const wallMuralAsset = 'homebound_run/wall_mural.png';
  static const wallHouseBrickAsset = 'homebound_run/wall_house_brick.png';
  static const wallHouseSageAsset = 'homebound_run/wall_house_sage.png';
  static const wallHouseGardenAsset = 'homebound_run/wall_house_garden.png';
  static const wallShopfrontAsset = 'homebound_run/wall_shopfront.png';
  static const streetHouseBrickAsset = 'homebound_run/street_house_brick.png';
  static const streetHouseSageAsset = 'homebound_run/street_house_sage.png';
  static const streetShopfrontAsset = 'homebound_run/street_shopfront.png';
  static const streetscapeBarricadeAsset =
      'homebound_run/streetscape_barricade.png';
  static const streetscapeScaffoldAsset =
      'homebound_run/streetscape_scaffold_crossbeam.png';
  static const streetscapePalletAsset =
      'homebound_run/streetscape_covered_pallet_materials.png';
  static const wallSchoolfrontAsset = 'homebound_run/wall_schoolfront.png';
  static const wallConstructionfrontAsset =
      'homebound_run/wall_constructionfront.png';

  // Kept for old debug fixtures and source provenance. They are not part of
  // the active image bundle or the production wall renderer.
  static const facadeSchoolAsset = 'homebound_run/facade_school.png';
  static const facadeShopsAsset = 'homebound_run/facade_shops.png';
  static const facadeHomesAsset = 'homebound_run/facade_homes.png';
  static const facadeConstructionAsset =
      'homebound_run/facade_construction.png';
  static const runnerRunAsset = 'homebound_run/student_run.png';
  static const runnerJumpAsset = 'homebound_run/student_jump.png';
  static const runnerSlideAsset = 'homebound_run/student_slide.png';
  static const pursuersAsset = 'homebound_run/pursuers.png';
  static const pursuersRunAsset = 'homebound_run/pursuers_run.png';
  static const hurdleAsset = 'homebound_run/obstacle_hurdle.png';
  static const jumpVariantAsset = 'homebound_run/obstacle_jump_variant.png';
  static const shutterAsset = 'homebound_run/obstacle_shutter.png';
  static const slideVariantAsset = 'homebound_run/obstacle_slide_variant.png';
  static const stackAsset = 'homebound_run/obstacle_stack.png';
  static const homeGateAsset = 'homebound_run/home_gate.png';
  static const coinAsset = 'homebound_run/coin.png';
  static const magnetAsset = 'homebound_run/magnet.png';
  static const shieldAsset = 'homebound_run/shield.png';
  static const boostAsset = 'homebound_run/boost.png';

  // Legacy paths stay named for old debug fixtures and are never loaded by
  // the approved image mode.
  static const legacyGuardianAsset = 'temple_run/guardian.png';
  static const legacyPathAsset = 'temple_run/temple_path.png';

  static const requiredImageAssets = <String>[
    backgroundAsset,
    asphaltAsset,
    wallPlasterAAsset,
    wallPlasterBAsset,
    wallWindowAsset,
    wallDoorAsset,
    wallMuralAsset,
    wallHouseBrickAsset,
    wallHouseSageAsset,
    wallHouseGardenAsset,
    wallShopfrontAsset,
    wallSchoolfrontAsset,
    wallConstructionfrontAsset,
    streetHouseBrickAsset,
    streetHouseSageAsset,
    streetShopfrontAsset,
    streetscapeBarricadeAsset,
    streetscapeScaffoldAsset,
    streetscapePalletAsset,
    runnerRunAsset,
    runnerJumpAsset,
    runnerSlideAsset,
    pursuersAsset,
    pursuersRunAsset,
    hurdleAsset,
    jumpVariantAsset,
    shutterAsset,
    slideVariantAsset,
    stackAsset,
    homeGateAsset,
    coinAsset,
    magnetAsset,
    shieldAsset,
    boostAsset,
  ];

  static const _runnerSourceFrameHeight = 288.0;
  // These are the measured alpha-bottom anchors from the final worker QC
  // reports. Every selected pose keeps the locked y272 contact line and its
  // authored 16px transparent bottom padding.
  static const _runnerRunSourceFeetBaselines = <double>[272, 272, 272, 272];
  static const _runnerJumpSourceFeetBaseline = 272.0;
  static const _runnerSlideSourceFeetBaseline = 272.0;

  // Environment transparent-fit keeps a small authored base-pixel margin
  // below each contact silhouette. Keep that margin in the source canvas,
  // then move the destination rect by the measured runtime padding so the
  // visible alpha footprint, rather than the canvas edge, meets the road.
  // Confirmed runtime alpha boxes from the environment worker QC report.
  // Values are in the final 4x runtime pixels.
  static const _hurdleFootprint = _ImageFootprint(
    canvasWidth: 512,
    canvasHeight: 256,
    left: 16,
    top: 168,
    right: 496,
    bottom: 240,
  );
  static const _jumpVariantFootprint = _ImageFootprint(
    canvasWidth: 512,
    canvasHeight: 256,
    left: 16,
    top: 100,
    right: 496,
    bottom: 240,
  );
  static const _streetscapeBarricadeFootprint = _ImageFootprint(
    canvasWidth: 512,
    canvasHeight: 256,
    left: 16,
    top: 152,
    right: 496,
    bottom: 240,
  );
  static const _streetscapeScaffoldFootprint = _ImageFootprint(
    canvasWidth: 512,
    canvasHeight: 512,
    left: 24,
    top: 92,
    right: 488,
    bottom: 488,
  );
  static const _streetscapePalletFrontSource = Rect.fromLTWH(0, 0, 256, 256);
  static const _streetscapePalletSideSource = Rect.fromLTWH(256, 0, 128, 256);
  static const _streetscapePalletTopSource = Rect.fromLTWH(0, 256, 256, 128);
  static const _shutterFootprint = _ImageFootprint(
    canvasWidth: 512,
    canvasHeight: 512,
    left: 24,
    top: 144,
    right: 488,
    bottom: 488,
  );
  static const _slideVariantFootprint = _ImageFootprint(
    canvasWidth: 512,
    canvasHeight: 512,
    left: 24,
    top: 160,
    right: 488,
    bottom: 488,
  );
  static const _homeGateFootprint = _ImageFootprint(
    canvasWidth: 512,
    canvasHeight: 512,
    left: 24,
    top: 116,
    right: 488,
    bottom: 488,
  );
  static const _leftPursuerSource = Rect.fromLTRB(40, 96, 296, 336);
  static const _rightPursuerSource = Rect.fromLTRB(270, 144, 480, 336);
  static const _leftPursuerRunSource = Rect.fromLTRB(48, 80, 264, 352);
  static const _rightPursuerRunSource = Rect.fromLTRB(264, 80, 480, 352);
  static const _pursuerRunFrameWidth = 512.0;
  static const _pursuerRunFrameHeight = 384.0;
  // The pursuit pair starts close to the runner during the countdown, then
  // falls back toward the horizon once the round begins. Keeping this as a
  // presentation-only timer lets the gameplay chase state and collision rules
  // stay unchanged while making the opening beat easy to read.
  static const _pursuerDepartureDurationSeconds = 1.6;
  static const _runnerDisplayWidth = 96.0;
  static const _runnerDisplayHeight = 144.0;

  static const _roadWorldWidth = 4.4;
  @visibleForTesting
  static const roadWidthForTesting = _roadWorldWidth;
  static const _cameraBackMeters = TempleRunRules.cameraBoomMaxMeters;
  static const _farClipMeters = 190.0;
  static const _facadeVisibleBehindMeters = 12.0;
  static const _nearClipMeters = .12;
  // Adjacent wall quads share a world boundary, but Canvas rasterizes their
  // separate homographies independently. A half source pixel of destination
  // overlap closes that seam without moving the authored wall or any feature
  // geometry.
  static const _wallTileBoundaryOverlapSourcePixels = .5;
  static const _asphaltPixelsPerMeter = 32.0;
  @visibleForTesting
  static const roadGutterInnerMeters = _roadWorldWidth / 2;
  @visibleForTesting
  static const roadGutterOuterMeters = roadGutterInnerMeters + .15;
  @visibleForTesting
  static const roadCurbOuterMeters = roadGutterOuterMeters + .30;
  @visibleForTesting
  static const roadSidewalkOuterMeters = _roadWorldWidth / 2 + 1.6;
  @visibleForTesting
  static const roadCurbHeightMeters = .08;
  @visibleForTesting
  static const facadeContactShadowWidthMeters = .12;
  static const _pickupEffectDurationSeconds = .50;
  static const _pickupEffectCap = 6;
  static const facadeHeightMeters = 5.5;
  @visibleForTesting
  static const obstacleBarricadeHeightMeters = .45;
  @visibleForTesting
  static const obstacleScaffoldHeightMeters = 2.9;
  @visibleForTesting
  static const obstacleScaffoldOpeningHeightMeters = 1.0;
  @visibleForTesting
  static const obstaclePalletHeightMeters = 1.25;
  @visibleForTesting
  static const obstaclePalletDepthMeters = .75;
  @visibleForTesting
  static const wallAuthoredWidth = 256;
  @visibleForTesting
  static const wallAuthoredHeight = 192;
  @visibleForTesting
  static const wallRuntimeScale = 4;
  @visibleForTesting
  static const double wallSourceWidth = 256.0 * 4.0;
  @visibleForTesting
  static const double wallSourceHeight = 192.0 * 4.0;
  @visibleForTesting
  static const wallTileLengthMeters =
      facadeHeightMeters * wallSourceWidth / wallSourceHeight;

  @visibleForTesting
  static const wallSlotCount = 20;

  // Feature rectangles come from the worker's authored 256x192 compositing
  // contract and stay resolution independent at the 1024x768 runtime scale.
  @visibleForTesting
  static const wallWindowNormalizedRect = Rect.fromLTRB(
    78 / 256,
    74 / 192,
    178 / 256,
    134 / 192,
  );
  @visibleForTesting
  static const wallDoorNormalizedRect = Rect.fromLTRB(
    92 / 256,
    111 / 192,
    160 / 256,
    190 / 192,
  );
  @visibleForTesting
  static const wallMuralNormalizedRect = Rect.fromLTRB(
    64 / 256,
    92 / 192,
    180 / 256,
    160 / 192,
  );

  // These are the worker's normalized UV bounds for the actual architectural
  // features in the opaque neighborhood plates. Only these bounded crops get
  // relief; the surrounding house/shop image remains on the wall plane.
  static const wallHouseBrickReliefSpecs = <_TempleRunWallReliefSpec>[
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(147 / 256, 91 / 192, 195 / 256, 175 / 192),
      featureDepth: .05,
      capDepth: .05,
      sillDepth: .04,
    ),
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(51 / 256, 13 / 192, 127 / 256, 63 / 192),
      featureDepth: .10,
      capDepth: .04,
      sillDepth: .14,
    ),
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(185 / 256, 9 / 192, 218 / 256, 57 / 192),
      featureDepth: .10,
      capDepth: .04,
      sillDepth: .14,
    ),
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(124 / 256, 69 / 192, 188 / 256, 94 / 192),
      featureDepth: .22,
      capDepth: .04,
      sillDepth: .03,
    ),
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(31 / 256, 0 / 192, 143 / 256, 22 / 192),
      featureDepth: .10,
      capDepth: .03,
      sillDepth: .02,
    ),
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(183 / 256, 6 / 192, 221 / 256, 20 / 192),
      featureDepth: .10,
      capDepth: .03,
      sillDepth: .02,
    ),
  ];

  static const wallHouseSageReliefSpecs = wallHouseBrickReliefSpecs;

  static const wallHouseGardenReliefSpecs = <_TempleRunWallReliefSpec>[
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(120 / 256, 104 / 192, 162 / 256, 177 / 192),
      featureDepth: .05,
      capDepth: .05,
      sillDepth: .04,
    ),
    _TempleRunWallReliefSpec(
      // The adapted garden plate's roof extends through the right third of
      // the crop; keep the relief bound on the actual authored roof pixels.
      source: Rect.fromLTRB(96 / 256, 77 / 192, 188 / 256, 100 / 192),
      featureDepth: .20,
      capDepth: .04,
      sillDepth: .03,
    ),
  ];

  static const wallShopfrontReliefSpecs = <_TempleRunWallReliefSpec>[
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(63 / 256, 87 / 192, 179 / 256, 188 / 192),
      featureDepth: .10,
      capDepth: .04,
      sillDepth: .06,
    ),
    _TempleRunWallReliefSpec(
      source: Rect.fromLTRB(62 / 256, 75 / 192, 179 / 256, 98 / 192),
      featureDepth: .30,
      capDepth: .05,
      sillDepth: .03,
    ),
  ];

  static const _wallMassSpecs = <TempleRunWallTileKind, _TempleRunWallMassSpec>{
    TempleRunWallTileKind.houseBrick: _TempleRunWallMassSpec(
      source: Rect.fromLTRB(16 / 256, 0, 240 / 256, 192 / 192),
      depth: .65,
      volumes: <_TempleRunWallVolumeSpec>[
        _TempleRunWallVolumeSpec(
          source: Rect.fromLTRB(124 / 256, 69 / 192, 188 / 256, 94 / 192),
          frontDepth: 1.05,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF6E4A3A),
          capColor: Color(0xFFD3A16D),
        ),
        _TempleRunWallVolumeSpec(
          // The meter is a separate box; cut this exact authored footprint
          // from the mass so its wiring and face are drawn only once.
          source: Rect.fromLTRB(209 / 256, 94 / 192, 229 / 256, 127 / 192),
          frontDepth: .90,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF53626A),
          capColor: Color(0xFF96A09A),
        ),
        _TempleRunWallVolumeSpec(
          // Quiet masonry under the upper flower bed; the foliage remains in
          // the house plate and is not copied onto this shallow ledge.
          source: Rect.fromLTRB(31 / 256, 72 / 192, 143 / 256, 78 / 192),
          frontDepth: .90,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF6E4A3A),
          capColor: Color(0xFFD3A16D),
          usePlasterFront: true,
        ),
        _TempleRunWallVolumeSpec(
          // Upper porch step: its top is 0.36m above the road.
          source: Rect.fromLTRB(
            147 / 256,
            1 - .36 / facadeHeightMeters,
            195 / 256,
            1 - .18 / facadeHeightMeters,
          ),
          frontDepth: .85,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF7A6E62),
          capColor: Color(0xFFD8CCBC),
          usePlasterFront: true,
        ),
        _TempleRunWallVolumeSpec(
          // Lower porch step: its top is 0.18m and its bottom contacts ground.
          source: Rect.fromLTRB(
            147 / 256,
            1 - .18 / facadeHeightMeters,
            195 / 256,
            1,
          ),
          frontDepth: .95,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF7A6E62),
          capColor: Color(0xFFD8CCBC),
          usePlasterFront: true,
        ),
      ],
    ),
    TempleRunWallTileKind.houseSage: _TempleRunWallMassSpec(
      source: Rect.fromLTRB(16 / 256, 0, 240 / 256, 192 / 192),
      depth: .65,
      volumes: <_TempleRunWallVolumeSpec>[
        _TempleRunWallVolumeSpec(
          source: Rect.fromLTRB(124 / 256, 69 / 192, 188 / 256, 94 / 192),
          frontDepth: 1.05,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF55676A),
          capColor: Color(0xFFBFC6B0),
        ),
        _TempleRunWallVolumeSpec(
          source: Rect.fromLTRB(209 / 256, 94 / 192, 229 / 256, 127 / 192),
          frontDepth: .90,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF55676A),
          capColor: Color(0xFFBFC6B0),
        ),
        _TempleRunWallVolumeSpec(
          source: Rect.fromLTRB(31 / 256, 72 / 192, 143 / 256, 78 / 192),
          frontDepth: .90,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF55676A),
          capColor: Color(0xFFBFC6B0),
          usePlasterFront: true,
        ),
        _TempleRunWallVolumeSpec(
          source: Rect.fromLTRB(
            147 / 256,
            1 - .36 / facadeHeightMeters,
            195 / 256,
            1 - .18 / facadeHeightMeters,
          ),
          frontDepth: .85,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF6E7A7C),
          capColor: Color(0xFFCBD0C2),
          usePlasterFront: true,
        ),
        _TempleRunWallVolumeSpec(
          source: Rect.fromLTRB(
            147 / 256,
            1 - .18 / facadeHeightMeters,
            195 / 256,
            1,
          ),
          frontDepth: .95,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF6E7A7C),
          capColor: Color(0xFFCBD0C2),
          usePlasterFront: true,
        ),
      ],
    ),
    TempleRunWallTileKind.houseGarden: _TempleRunWallMassSpec(
      source: Rect.fromLTRB(28 / 256, 72 / 192, 228 / 256, 192 / 192),
      depth: .40,
      volumes: <_TempleRunWallVolumeSpec>[
        _TempleRunWallVolumeSpec(
          source: Rect.fromLTRB(96 / 256, 77 / 192, 188 / 256, 100 / 192),
          frontDepth: .80,
          maskColor: Color(0xFFF1E6D0),
          sideColor: Color(0xFF687177),
          capColor: Color(0xFFB76B43),
        ),
      ],
    ),
    TempleRunWallTileKind.shopfront: _TempleRunWallMassSpec(
      source: Rect.fromLTRB(57 / 256, 72 / 192, 198 / 256, 192 / 192),
      depth: .65,
      volumes: <_TempleRunWallVolumeSpec>[
        _TempleRunWallVolumeSpec(
          source: Rect.fromLTRB(62 / 256, 75 / 192, 179 / 256, 98 / 192),
          frontDepth: 1.05,
          maskColor: Color(0xFFEDE2D0),
          sideColor: Color(0xFF52616B),
          capColor: Color(0xFF769FA1),
        ),
      ],
    ),
    TempleRunWallTileKind.schoolfront: _TempleRunWallMassSpec(
      source: Rect.fromLTRB(28 / 256, 72 / 192, 228 / 256, 192 / 192),
      depth: .40,
    ),
    TempleRunWallTileKind.constructionfront: _TempleRunWallMassSpec(
      source: Rect.fromLTRB(23 / 256, 88 / 192, 233 / 256, 192 / 192),
      depth: .40,
    ),
  };

  // Full-bleed neighborhood modules own their entire 7.333m x 5.5m tile.
  // The swatches are the worker-authored clean 32x32 logical-pixel masonry
  // patches, expressed at the 4x runtime scale for returned faces.
  static const _fullBleedFacadeSpecs =
      <TempleRunWallTileKind, _TempleRunFullBleedFacadeSpec>{
        TempleRunWallTileKind.houseBrick: _TempleRunFullBleedFacadeSpec(
          asset: streetHouseBrickAsset,
          setback: .35,
          materialSwatch: Rect.fromLTRB(32, 512, 160, 640),
          heightExtension: .42,
          topCapColor: Color(0xFFB86F48),
        ),
        TempleRunWallTileKind.houseSage: _TempleRunFullBleedFacadeSpec(
          asset: streetHouseSageAsset,
          setback: .55,
          materialSwatch: Rect.fromLTRB(32, 576, 160, 704),
          heightExtension: .20,
          topCapColor: Color(0xFFB8C1B1),
        ),
        TempleRunWallTileKind.houseGarden: _TempleRunFullBleedFacadeSpec(
          asset: streetHouseSageAsset,
          setback: .55,
          materialSwatch: Rect.fromLTRB(32, 576, 160, 704),
          heightExtension: .12,
          topCapColor: Color(0xFFB8C1B1),
        ),
        TempleRunWallTileKind.shopfront: _TempleRunFullBleedFacadeSpec(
          asset: streetShopfrontAsset,
          setback: .40,
          materialSwatch: Rect.fromLTRB(576, 0, 704, 128),
          heightExtension: .30,
          topCapColor: Color(0xFF6F8D8D),
        ),
        // Rare wall modules remain at the baseline plane, but still own the
        // whole tile instead of being partial inserts over a plaster backing.
        TempleRunWallTileKind.schoolfront: _TempleRunFullBleedFacadeSpec(
          asset: wallSchoolfrontAsset,
          setback: 0,
          materialSwatch: Rect.fromLTWH(0, 0, 128, 128),
        ),
        TempleRunWallTileKind.constructionfront: _TempleRunFullBleedFacadeSpec(
          asset: wallConstructionfrontAsset,
          setback: 0,
          materialSwatch: Rect.fromLTWH(0, 0, 128, 128),
        ),
      };

  static const _fullBleedPropSpecs =
      <TempleRunWallTileKind, List<_TempleRunFullBleedPropSpec>>{
        TempleRunWallTileKind.houseBrick: [
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(210 / 256, 106 / 192, 226 / 256, 127 / 192),
            frontDepth: .25,
            sideColor: Color(0xFF59666A),
            capColor: Color(0xFFB1B3A4),
          ),
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(123 / 256, 82 / 192, 206 / 256, 92 / 192),
            frontDepth: .40,
            sideColor: Color(0xFF6C4D3A),
            capColor: Color(0xFFD3A16D),
          ),
        ],
        TempleRunWallTileKind.houseSage: [
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(214 / 256, 102 / 192, 230 / 256, 123 / 192),
            frontDepth: .25,
            sideColor: Color(0xFF53676A),
            capColor: Color(0xFFBEC8B5),
          ),
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(134 / 256, 81 / 192, 211 / 256, 89 / 192),
            frontDepth: .40,
            sideColor: Color(0xFF596D68),
            capColor: Color(0xFFCBD0C2),
          ),
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(33 / 256, 139 / 192, 100 / 256, 145 / 192),
            frontDepth: .18,
            sideColor: Color(0xFF596D68),
            capColor: Color(0xFFCBD0C2),
          ),
        ],
        TempleRunWallTileKind.houseGarden: [
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(214 / 256, 102 / 192, 230 / 256, 123 / 192),
            frontDepth: .25,
            sideColor: Color(0xFF53676A),
            capColor: Color(0xFFBEC8B5),
          ),
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(134 / 256, 81 / 192, 211 / 256, 89 / 192),
            frontDepth: .40,
            sideColor: Color(0xFF596D68),
            capColor: Color(0xFFCBD0C2),
          ),
        ],
        TempleRunWallTileKind.shopfront: [
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(226 / 256, 108 / 192, 242 / 256, 127 / 192),
            frontDepth: .25,
            sideColor: Color(0xFF52616B),
            capColor: Color(0xFF769FA1),
          ),
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(11 / 256, 83 / 192, 179 / 256, 100 / 192),
            frontDepth: .45,
            sideColor: Color(0xFF52616B),
            capColor: Color(0xFF769FA1),
          ),
          _TempleRunFullBleedPropSpec(
            source: Rect.fromLTRB(79 / 256, 63 / 192, 164 / 256, 70 / 192),
            frontDepth: .18,
            sideColor: Color(0xFF52616B),
            capColor: Color(0xFF769FA1),
          ),
        ],
      };

  @visibleForTesting
  static double wallMassDepthForTesting(TempleRunWallTileKind kind) =>
      _wallMassSpecs[kind]?.depth ?? 0;

  @visibleForTesting
  static Rect wallMassSourceRectForTesting(TempleRunWallTileKind kind) =>
      _wallMassSpecs[kind]?.source ?? Rect.zero;

  @visibleForTesting
  static List<Rect> wallReliefSourceRectsForTesting(
    TempleRunWallTileKind kind,
  ) => [
    for (final volume
        in _wallMassSpecs[kind]?.volumes ?? const <_TempleRunWallVolumeSpec>[])
      volume.source,
  ];

  @visibleForTesting
  static List<double> wallReliefFrontDepthsForTesting(
    TempleRunWallTileKind kind,
  ) => [
    for (final volume
        in _wallMassSpecs[kind]?.volumes ?? const <_TempleRunWallVolumeSpec>[])
      volume.frontDepth,
  ];

  @visibleForTesting
  static bool isFullBleedFacadeKindForTesting(TempleRunWallTileKind kind) =>
      _fullBleedFacadeSpecs.containsKey(kind);

  @visibleForTesting
  static double fullBleedSetbackForTesting(TempleRunWallTileKind kind) =>
      _fullBleedFacadeSpecs[kind]?.setback ?? 0;

  @visibleForTesting
  static Rect fullBleedMaterialSwatchForTesting(TempleRunWallTileKind kind) =>
      _fullBleedFacadeSpecs[kind]?.materialSwatch ?? Rect.zero;

  @visibleForTesting
  static double fullBleedHeightExtensionForTesting(
    TempleRunWallTileKind kind,
  ) => _fullBleedFacadeSpecs[kind]?.heightExtension ?? 0;

  @visibleForTesting
  static bool fullBleedHeightSideCapNeededForTesting({
    required double currentFrontOffset,
    required double neighborFrontOffset,
    required double currentHeightExtension,
    required double neighborHeightExtension,
    required bool currentGuarded,
  }) => _needsFullBleedHeightSideCap(
    currentFrontOffset: currentFrontOffset,
    neighborFrontOffset: neighborFrontOffset,
    currentHeightExtension: currentHeightExtension,
    neighborHeightExtension: neighborHeightExtension,
    currentGuarded: currentGuarded,
  );

  @visibleForTesting
  static List<Rect> fullBleedPropSourceRectsForTesting(
    TempleRunWallTileKind kind,
  ) => [
    for (final prop
        in _fullBleedPropSpecs[kind] ?? const <_TempleRunFullBleedPropSpec>[])
      prop.source,
  ];

  @visibleForTesting
  static List<double> fullBleedPropDepthsForTesting(
    TempleRunWallTileKind kind,
  ) => [
    for (final prop
        in _fullBleedPropSpecs[kind] ?? const <_TempleRunFullBleedPropSpec>[])
      prop.frontDepth,
  ];

  static const _wallSlotSchedule = <_TempleRunWallSlotCategory>[
    _TempleRunWallSlotCategory.actualWall,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.shop,
    _TempleRunWallSlotCategory.actualWall,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.shop,
    _TempleRunWallSlotCategory.actualWall,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.shop,
    _TempleRunWallSlotCategory.actualWall,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.shop,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.house,
    _TempleRunWallSlotCategory.house,
  ];

  static const _plasterKindBySlot = <TempleRunWallTileKind?>[
    TempleRunWallTileKind.mural,
    null,
    null,
    null,
    TempleRunWallTileKind.schoolfront,
    null,
    null,
    null,
    TempleRunWallTileKind.constructionfront,
    null,
    null,
    null,
    TempleRunWallTileKind.plasterA,
    null,
    null,
    null,
    null,
    null,
    null,
  ];

  static const _houseKindBySlot = <int, TempleRunWallTileKind>{
    1: TempleRunWallTileKind.houseBrick,
    2: TempleRunWallTileKind.houseBrick,
    5: TempleRunWallTileKind.houseSage,
    6: TempleRunWallTileKind.houseSage,
    9: TempleRunWallTileKind.houseGarden,
    10: TempleRunWallTileKind.houseGarden,
    13: TempleRunWallTileKind.houseBrick,
    14: TempleRunWallTileKind.houseBrick,
    16: TempleRunWallTileKind.houseSage,
    17: TempleRunWallTileKind.houseSage,
    18: TempleRunWallTileKind.houseGarden,
    19: TempleRunWallTileKind.houseGarden,
  };

  @visibleForTesting
  static int wallTileIndexForArc(double wallArc) =>
      (wallArc / wallTileLengthMeters).floor();

  @visibleForTesting
  static int wallSlotIndexForArc(double wallArc) {
    final tileIndex = wallTileIndexForArc(wallArc);
    return ((tileIndex % wallSlotCount) + wallSlotCount) % wallSlotCount;
  }

  @visibleForTesting
  static int wallBlockIndexForArc(double wallArc) =>
      (wallTileIndexForArc(wallArc) / wallSlotCount).floor();

  @visibleForTesting
  static TempleRunWallTileKind wallTileKindForArc({
    required double wallArc,
    required double side,
  }) {
    final slot = wallSlotIndexForArc(wallArc);
    switch (_wallSlotSchedule[slot]) {
      case _TempleRunWallSlotCategory.actualWall:
        final kind = _plasterKindBySlot[slot]!;
        if (kind == TempleRunWallTileKind.plasterA ||
            kind == TempleRunWallTileKind.plasterB) {
          // Keep the category schedule global on both sides while allowing a
          // small finish variation between the two property rows.
          if (side >= 0) {
            return kind == TempleRunWallTileKind.plasterA
                ? TempleRunWallTileKind.plasterB
                : TempleRunWallTileKind.plasterA;
          }
        }
        return kind;
      case _TempleRunWallSlotCategory.house:
        final base = _houseKindBySlot[slot]!;
        if (side < 0) return base;
        const variants = <TempleRunWallTileKind>[
          TempleRunWallTileKind.houseBrick,
          TempleRunWallTileKind.houseSage,
          TempleRunWallTileKind.houseGarden,
        ];
        final index = variants.indexOf(base);
        return variants[(index + 1) % variants.length];
      case _TempleRunWallSlotCategory.shop:
        return TempleRunWallTileKind.shopfront;
    }
  }

  @visibleForTesting
  static TempleRunWallTileKind wallBaseKindForArc({
    required double wallArc,
    required double side,
  }) {
    final kind = wallTileKindForArc(wallArc: wallArc, side: side);
    return kind;
  }

  @visibleForTesting
  static Rect wallFeatureSourceRectForTesting(
    TempleRunWallTileKind kind, {
    double sourceWidth = wallSourceWidth,
    double sourceHeight = wallSourceHeight,
  }) {
    final normalized = switch (kind) {
      TempleRunWallTileKind.window => wallWindowNormalizedRect,
      TempleRunWallTileKind.door => wallDoorNormalizedRect,
      TempleRunWallTileKind.mural => wallMuralNormalizedRect,
      _ => Rect.zero,
    };
    return Rect.fromLTRB(
      normalized.left * sourceWidth,
      normalized.top * sourceHeight,
      normalized.right * sourceWidth,
      normalized.bottom * sourceHeight,
    );
  }

  @visibleForTesting
  static const facadePierWidthMeters = .12;
  @visibleForTesting
  static const facadePierDepthMeters = .12;
  @visibleForTesting
  static const facadeCorniceDepthMeters = .10;
  @visibleForTesting
  static const facadeCorniceBottomMeters = 5.32;
  @visibleForTesting
  static const facadeCorniceTopMeters = 5.42;
  @visibleForTesting
  static const facadeFootShadowDepthMeters = .10;
  @visibleForTesting
  static const facadeBaseLedgeDepthMeters = .06;
  @visibleForTesting
  static const facadeBaseLedgeHeightMeters = .18;

  @visibleForTesting
  static double get facadePierInnerEdgeMeters =>
      _roadWorldWidth / 2 + 1.6 - facadePierDepthMeters;

  static double facadeTileOriginForArc(double wallArc, double tileLength) =>
      (wallArc / tileLength).floor() * tileLength;

  static int facadeStyleIndexForArc(
    double wallArc,
    double styleLength,
    int styleCount,
  ) {
    final block = (wallArc / styleLength).floor();
    return ((block % styleCount) + styleCount) % styleCount;
  }

  static double facadeSourceXForArc({
    required double wallArc,
    required double tileOrigin,
    required double tileLength,
    required double sourceWidth,
  }) => sourceWidth * (wallArc - tileOrigin) / tileLength;

  static Offset? facadeMiterCorner({
    required Offset junction,
    required double incomingHeading,
    required double outgoingHeading,
    required double side,
    required double offset,
  }) {
    final incomingForward = _forward(incomingHeading);
    final outgoingForward = _forward(outgoingHeading);
    final incomingOffset = junction + _right(incomingHeading) * side * offset;
    final outgoingOffset = junction + _right(outgoingHeading) * side * offset;
    final denominator = _cross(incomingForward, outgoingForward);
    if (denominator.abs() < .001) return null;
    final distance =
        _cross(outgoingOffset - incomingOffset, outgoingForward) / denominator;
    return incomingOffset + incomingForward * distance;
  }

  final Map<String, ui.Image> _images;
  final bool useImageAssets;
  TempleRunCourse? _course;
  List<_FacadeRouteLeg> _plannedFacadeLegs = const <_FacadeRouteLeg>[];
  List<TempleRunFacadeWallSpan> _safeCameraWallSpansLeft =
      const <TempleRunFacadeWallSpan>[];
  List<TempleRunFacadeWallSpan> _safeCameraWallSpansRight =
      const <TempleRunFacadeWallSpan>[];
  List<TempleRunFacadeWallSpan> _facadeWallSpansLeft =
      const <TempleRunFacadeWallSpan>[];
  List<TempleRunFacadeWallSpan> _facadeWallSpansRight =
      const <TempleRunFacadeWallSpan>[];
  List<TempleRunFacadeWallSpan> _facadeShadowWallSpansLeft =
      const <TempleRunFacadeWallSpan>[];
  List<TempleRunFacadeWallSpan> _facadeShadowWallSpansRight =
      const <TempleRunFacadeWallSpan>[];
  List<List<_CameraPoint>>? _facadeOccluderCollector;
  List<_ProjectedFacadeOccluder> _renderedFacadeOccluders =
      const <_ProjectedFacadeOccluder>[];
  // Gameplay distance may continue through the inclusive late-turn grace
  // while the rendered chase camera waits at the junction. The renderer's
  // distance is kept separate so gameplay and HUD timing remain untouched.
  double _distanceMeters = 0;
  double _actualDistanceMeters = 0;
  int? _lateHeldTurnIndex;
  double _lateCatchUpDebtMeters = 0;
  int? _lateCatchUpTurnIndex;
  double _bendProgress = 0;
  double _jumpRemaining = 0;
  double _slideRemaining = 0;
  double _runnerFrame = 0;
  double _visualLane = TempleRunRules.centerLane.toDouble();
  double _phoneTilt = 0;
  TempleRunTurnDirection? _bendDirection;
  TempleRunTurn? _activeTurn;
  int _completedTurnCount = 0;
  double _cameraHeading = 0;
  Offset _cameraPosition = Offset.zero;
  double _cameraTargetDepth = _cameraBackMeters;
  double _cameraBoomDistance = _cameraBackMeters;
  double _pursuerRunPhase = 0;
  double _pursuerDepartureProgress = 0;
  final _pursuerScreenBounds = <Rect>[];
  bool _pursuersVisible = true;
  bool _guardianVisible = true;
  bool _failureVisible = false;
  bool _arrivalVisible = false;
  bool _shieldVisible = false;
  bool _boostVisible = false;
  bool _magnetVisible = false;
  Set<int> _consumedCoinIndices = const <int>{};
  Set<int> _consumedPowerUpIndices = const <int>{};
  Set<int> _knownCollectedCoinIndices = <int>{};
  Set<int> _knownCollectedPowerUpIndices = <int>{};
  final List<_TempleRunPickupEffect> _pickupEffects =
      <_TempleRunPickupEffect>[];

  double get renderedDistanceForTesting => _distanceMeters;

  @visibleForTesting
  double get actualDistanceForTesting => _actualDistanceMeters;

  @visibleForTesting
  Offset get runnerWorldPositionForTesting => _runnerWorldPosition();

  @visibleForTesting
  Offset get cameraPositionForTesting => _cameraPosition;

  @visibleForTesting
  double get cameraBoomDistanceForTesting => _cameraBoomDistance;

  @visibleForTesting
  double get cameraHeadingForTesting => _cameraHeading;

  @visibleForTesting
  List<Rect> get pursuerBoundsForTesting =>
      List.unmodifiable(_pursuerScreenBounds);

  @visibleForTesting
  double get pursuerDepartureProgressForTesting => _pursuerDepartureProgress;

  @visibleForTesting
  int get activePickupEffectCountForTesting => _pickupEffects.length;

  @visibleForTesting
  List<String> get activePickupEffectLabelsForTesting => [
    for (final effect in _pickupEffects) _pickupEffectLabel(effect.kind),
  ];

  @visibleForTesting
  double get cameraHeightForTesting => _cameraHeightMeters;

  @visibleForTesting
  double get horizonYForTesting => _horizonY;

  @visibleForTesting
  double get cameraTargetDepthForTesting => _cameraTargetDepth;

  @visibleForTesting
  double get focalLengthForTesting => _focalLength;

  @visibleForTesting
  Float64List get groundHomographyForTesting => _groundHomography();

  @visibleForTesting
  Offset? projectWorldPointForTesting(Offset world) =>
      _projectWorld(world)?.point;

  @visibleForTesting
  ({double start, double end})? get facadeVisibleWindowForTesting =>
      _visibleFacadeRouteWindow();

  @visibleForTesting
  void renderFacadeOcclusionFixtureForTesting(
    Canvas canvas, {
    required double wallLeftDepth,
    required double wallRightDepth,
    required double wallLateralStart,
    required double wallLateralEnd,
    required double wallHeight,
    required double billboardDepth,
    required double billboardLateral,
    required double billboardWidth,
    required double billboardHeight,
    required Color billboardColor,
  }) {
    final wall = <_CameraPoint>[
      _CameraPoint(lateral: wallLateralStart, depth: wallLeftDepth, height: 0),
      _CameraPoint(lateral: wallLateralEnd, depth: wallRightDepth, height: 0),
      _CameraPoint(
        lateral: wallLateralEnd,
        depth: wallRightDepth,
        height: wallHeight,
      ),
      _CameraPoint(
        lateral: wallLateralStart,
        depth: wallLeftDepth,
        height: wallHeight,
      ),
    ];
    final clippedWall = _clipCameraPolygonToDepth(wall, billboardDepth - .035);
    final occluders = <_ProjectedFacadeOccluder>[];
    if (clippedWall.length >= 3) {
      final projectedWall = clippedWall
          .map(_projectCameraPoint)
          .toList(growable: false);
      final wallPath = Path()
        ..moveTo(projectedWall.first.point.dx, projectedWall.first.point.dy);
      for (final point in projectedWall.skip(1)) {
        wallPath.lineTo(point.point.dx, point.point.dy);
      }
      wallPath.close();
      occluders.add(
        _ProjectedFacadeOccluder(
          path: wallPath,
          bounds: wallPath.getBounds(),
          nearDepth: clippedWall.fold<double>(
            double.infinity,
            (minimum, point) => math.min(minimum, point.depth),
          ),
          cameraPolygon: wall,
        ),
      );
    }

    final halfWidth = billboardWidth / 2;
    final billboard = <_ProjectedWorldPoint>[
      _projectCameraPoint(
        _CameraPoint(
          lateral: billboardLateral - halfWidth,
          depth: billboardDepth,
          height: 0,
        ),
      ),
      _projectCameraPoint(
        _CameraPoint(
          lateral: billboardLateral + halfWidth,
          depth: billboardDepth,
          height: 0,
        ),
      ),
      _projectCameraPoint(
        _CameraPoint(
          lateral: billboardLateral + halfWidth,
          depth: billboardDepth,
          height: billboardHeight,
        ),
      ),
      _projectCameraPoint(
        _CameraPoint(
          lateral: billboardLateral - halfWidth,
          depth: billboardDepth,
          height: billboardHeight,
        ),
      ),
    ];
    final billboardPath = Path()
      ..moveTo(billboard.first.point.dx, billboard.first.point.dy);
    for (final point in billboard.skip(1)) {
      billboardPath.lineTo(point.point.dx, point.point.dy);
    }
    billboardPath.close();
    _drawWithFacadeOcclusion(
      canvas,
      occluders,
      (target) =>
          target.drawPath(billboardPath, Paint()..color = billboardColor),
    );
  }

  @visibleForTesting
  double get backgroundParallaxForTesting =>
      _backgroundParallaxPixels(_cameraHeading);

  @visibleForTesting
  double get backgroundParallaxPhaseForTesting =>
      _wrapBackgroundOffset(backgroundParallaxForTesting, size.x * 2);

  ui.Image? _imageFor(String asset) => useImageAssets ? _images[asset] : null;

  /// Decodes the production image bundle for home and guide previews. The
  /// caller owns the returned images and keeps them alive for the preview.
  static Future<Map<String, ui.Image>> loadImageAssets({
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final loaded = <String, ui.Image>{};
    try {
      await Future.wait(
        requiredImageAssets.map((asset) async {
          final data = await assetBundle.load('assets/images/$asset');
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          try {
            final frame = await codec.getNextFrame();
            loaded[asset] = frame.image;
          } finally {
            codec.dispose();
          }
        }),
        eagerError: false,
      );
    } on Object {
      for (final image in loaded.values) {
        image.dispose();
      }
      rethrow;
    }
    return Map.unmodifiable(loaded);
  }

  void resizeToViewport(Vector2 viewportSize) {
    if (viewportSize.x <= 0 || viewportSize.y <= 0) return;
    size.setFrom(viewportSize);
    _refreshCamera();
  }

  /// Projection used by the existing runtime tests and by legacy integrations.
  /// It is route-aware when a scene has been supplied and remains centered for
  /// a newly constructed adapter.
  TempleRunProjection project(double distanceMeters) {
    final routeDistance = _distanceMeters + distanceMeters;
    final route = _visualRouteStateAt(routeDistance, _completedTurnCount);
    final world = distanceMeters.abs() < .0001
        ? _runnerWorldPosition(route)
        : route.position;
    final projected = _projectWorld(world);
    final depth =
        projected?.depth ??
        (distanceMeters + _cameraBackMeters).clamp(
          _nearClipMeters,
          _farClipMeters,
        );
    final scale = _screenScale(depth);
    final center = projected?.point ?? Offset(size.x / 2, _groundY(depth));
    return TempleRunProjection(
      center: center,
      scale: scale / 70,
      depth: depth,
      roadWidth: _roadWorldWidth * scale,
    );
  }

  void updateScene({
    required TempleRunCourse course,
    required double distanceMeters,
    required int lane,
    double? visualLane,
    required double jumpRemaining,
    required double slideRemaining,
    required double runnerFrame,
    required TempleRunTurn? activeTurn,
    required double bendProgress,
    required TempleRunTurnDirection? bendDirection,
    double cameraYaw = 0,
    int? completedTurnCount,
    double phoneTilt = 0,
    required bool guardianVisible,
    bool pursuersVisible = true,
    required bool failureVisible,
    bool arrivalVisible = false,
    required bool shieldVisible,
    required bool boostVisible,
    bool magnetVisible = false,
    Set<int> consumedCoinIndices = const <int>{},
    Set<int> consumedPowerUpIndices = const <int>{},
    Set<int> collectedCoinIndices = const <int>{},
    Set<int> collectedPowerUpIndices = const <int>{},
    double deltaSeconds = 0,
  }) {
    final courseChanged = !identical(_course, course);
    var pickupBaselineReset = courseChanged;
    if (courseChanged) {
      _course = course;
      _plannedFacadeLegs = _buildPlannedFacadeLegs(course);
      final safeOffset = _cameraSafeWallOffset;
      _safeCameraWallSpansLeft = _buildFacadeWallSpans(
        side: -1,
        wallOffset: safeOffset,
        roofOffset: safeOffset,
      );
      _safeCameraWallSpansRight = _buildFacadeWallSpans(
        side: 1,
        wallOffset: safeOffset,
        roofOffset: safeOffset,
      );
      final facadeOffset = _roadWorldWidth / 2 + 1.6;
      _facadeWallSpansLeft = _buildFacadeWallSpans(
        side: -1,
        wallOffset: facadeOffset,
        roofOffset: facadeOffset - facadeCorniceDepthMeters,
      );
      _facadeWallSpansRight = _buildFacadeWallSpans(
        side: 1,
        wallOffset: facadeOffset,
        roofOffset: facadeOffset - facadeCorniceDepthMeters,
      );
      final shadowOffset = facadeOffset - facadeFootShadowDepthMeters;
      _facadeShadowWallSpansLeft = _buildFacadeWallSpans(
        side: -1,
        wallOffset: facadeOffset,
        roofOffset: shadowOffset,
      );
      _facadeShadowWallSpansRight = _buildFacadeWallSpans(
        side: 1,
        wallOffset: facadeOffset,
        roofOffset: shadowOffset,
      );
      _resetLateTurnRenderState();
      _resetPickupFeedback();
      _pursuerDepartureProgress = 0;
    }
    final actualDistance = math.max(0.0, distanceMeters);
    if (!courseChanged && actualDistance < _actualDistanceMeters) {
      _resetLateTurnRenderState();
      _resetPickupFeedback();
      pickupBaselineReset = true;
    }
    _actualDistanceMeters = actualDistance;
    assert(lane >= TempleRunRules.firstLane && lane <= TempleRunRules.lastLane);
    assert(
      visualLane == null ||
          visualLane >= TempleRunRules.firstLane &&
              visualLane <= TempleRunRules.lastLane,
    );
    _phoneTilt = phoneTilt.clamp(-1.0, 1.0);
    _visualLane =
        (visualLane ?? TempleRunRules.centerLane.toDouble() + _phoneTilt).clamp(
          TempleRunRules.firstLane.toDouble(),
          TempleRunRules.lastLane.toDouble(),
        );
    _pursuersVisible = pursuersVisible;
    _jumpRemaining = jumpRemaining;
    _slideRemaining = slideRemaining;
    _runnerFrame = runnerFrame;
    _activeTurn = activeTurn;
    _bendDirection = bendDirection;
    _completedTurnCount = _resolveCompletedTurnCount(completedTurnCount);
    _bendProgress = bendProgress.clamp(0.0, 1.0);
    _distanceMeters = _resolveRenderedDistance(actualDistance);
    _guardianVisible = guardianVisible;
    _failureVisible = failureVisible;
    _arrivalVisible = arrivalVisible;
    _shieldVisible = shieldVisible;
    _boostVisible = boostVisible;
    _magnetVisible = magnetVisible;
    if (guardianVisible) {
      // The countdown is always the close-up reveal, even when the first
      // frame arrives with no elapsed delta (as in an initial widget build).
      _pursuerDepartureProgress = 0;
    }
    if (deltaSeconds > 0) {
      _pursuerRunPhase += deltaSeconds * 8;
      if (!guardianVisible && pursuersVisible) {
        _pursuerDepartureProgress =
            (_pursuerDepartureProgress +
                    deltaSeconds / _pursuerDepartureDurationSeconds)
                .clamp(0.0, 1.0);
      }
      for (final effect in _pickupEffects) {
        effect.age += deltaSeconds;
      }
      _pickupEffects.removeWhere(
        (effect) => effect.age >= _pickupEffectDurationSeconds,
      );
    }
    final newlyCollectedCoins = pickupBaselineReset
        ? const <int>{}
        : collectedCoinIndices.difference(_knownCollectedCoinIndices);
    final newlyCollectedPowerUps = pickupBaselineReset
        ? const <int>{}
        : collectedPowerUpIndices.difference(_knownCollectedPowerUpIndices);
    _knownCollectedCoinIndices = collectedCoinIndices.toSet();
    _knownCollectedPowerUpIndices = collectedPowerUpIndices.toSet();
    _consumedCoinIndices = consumedCoinIndices;
    _consumedPowerUpIndices = consumedPowerUpIndices;
    // Once the route prefix is explicit, its bend state is the single source
    // of camera heading. The yaw argument remains only for older integrations
    // that have not adopted [completedTurnCount] yet.
    _refreshCamera(cameraYaw: cameraYaw);
    _spawnPickupEffects(
      coinIndices: newlyCollectedCoins,
      powerUpIndices: newlyCollectedPowerUps,
    );
  }

  void _resetLateTurnRenderState() {
    _lateHeldTurnIndex = null;
    _lateCatchUpDebtMeters = 0;
    _lateCatchUpTurnIndex = null;
  }

  void _resetPickupFeedback() {
    _pickupEffects.clear();
    _knownCollectedCoinIndices = <int>{};
    _knownCollectedPowerUpIndices = <int>{};
  }

  double _resolveRenderedDistance(double actualDistance) {
    final turns = _course?.turns ?? const <TempleRunTurn>[];
    final heldIndex = _lateHeldTurnIndex;
    if (heldIndex != null && _completedTurnCount > heldIndex) {
      final heldTurn = turns[heldIndex];
      _lateCatchUpTurnIndex = heldIndex;
      _lateCatchUpDebtMeters = math.max(
        0.0,
        actualDistance - heldTurn.distanceMeters,
      );
      _lateHeldTurnIndex = null;
    }

    final catchUpIndex = _lateCatchUpTurnIndex;
    if (catchUpIndex != null) {
      if (_bendProgress > 0 && _lateCatchUpDebtMeters > 0) {
        return actualDistance - _lateCatchUpDebtMeters * _bendProgress;
      }
      _lateCatchUpDebtMeters = 0;
      _lateCatchUpTurnIndex = null;
    }

    final nextTurnIndex = _completedTurnCount;
    if (nextTurnIndex < turns.length) {
      final nextTurn = turns[nextTurnIndex];
      if (actualDistance > nextTurn.distanceMeters) {
        _lateHeldTurnIndex = nextTurnIndex;
        return nextTurn.distanceMeters;
      }
    }
    _lateHeldTurnIndex = null;
    return actualDistance;
  }

  int _resolveCompletedTurnCount(int? explicit) {
    final count =
        explicit ?? ((_activeTurn == null && _bendDirection != null) ? 1 : 0);
    return count.clamp(0, _course?.turns.length ?? 0);
  }

  @visibleForTesting
  List<TempleRunFacadeWallSpan> facadeWallSpansForTesting({required int side}) {
    if (side != -1 && side != 1) {
      throw ArgumentError.value(side, 'side', 'Expected -1 or 1.');
    }
    return _buildFacadeWallSpans(
      side: side.toDouble(),
      wallOffset: _roadWorldWidth / 2 + 1.6,
      roofOffset: _roadWorldWidth / 2 + 1.6 + 6,
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    _pursuerScreenBounds.clear();
    _drawBackground(canvas);
    _drawGroundPlane(canvas);
    _drawRoadEdgeDetails(canvas);
    // Image mode uses the single world-space asphalt plane above. Drawing
    // every road strip and junction again would introduce a second raster UV
    // path at bends; the fallback renderer still draws its solid road and
    // rails through [_drawRoad].
    if (!useImageAssets) _drawRoad(canvas);
    _drawFacadeWalls(canvas);
    _drawObjects(canvas, _buildVisibleFacadeOccluders());
    final pursuersDeparted = _pursuerDepartureProgress >= 1 - 1e-6;
    final showPursuers =
        !_arrivalVisible &&
        (_failureVisible ||
            _guardianVisible ||
            (_pursuersVisible && !pursuersDeparted));
    // Keep the screen-space pursuit group visible over ground overlays such
    // as a narrow path. The runner remains above it, and gameplay objects are
    // normally projected well above this lower chase foreground.
    if (showPursuers) {
      _drawPursuers(canvas, departureProgress: _pursuerDepartureProgress);
    }
    if (_arrivalVisible) _drawHomeGate(canvas);
    _drawRunner(canvas);
    _drawPickupEffects(canvas);
    canvas.restore();
  }

  void _refreshCamera({double cameraYaw = 0}) {
    final route = _visualRouteStateAt(_distanceMeters, _completedTurnCount);
    _cameraBoomDistance = _cameraBoomForDistance(route);
    // Orbit around the rendered centerline, rather than sampling the route at
    // distance minus the boom. During a bend that historical sample remains on
    // the incoming leg and makes the camera visually turn late. The centerline
    // and the interpolated heading are now the single source for camera,
    // runner, road, and facade projection.
    _cameraHeading = route.heading;
    _cameraPosition =
        route.position - _forward(_cameraHeading) * _cameraBoomDistance;
    final laneOffset =
        (_visualLane - TempleRunRules.centerLane) * (_roadWorldWidth / 3);
    // Keep the target-depth normalization tied to the actual boom. The lane
    // target is exactly forward*boom + right*laneOffset, so this heading stays
    // equal to the eased route heading for every lane.
    final target = route.position + _right(route.heading) * laneOffset;
    final targetVector = target - _cameraPosition;
    final targetDistance = math.max(.001, targetVector.distance);
    _cameraTargetDepth = math.max(
      _nearClipMeters,
      math.sqrt(
        math.max(
          0.0,
          targetDistance * targetDistance - laneOffset * laneOffset,
        ),
      ),
    );
    // The argument remains for older callers and is asserted so a stale
    // adapter cannot inject a non-finite heading.
    assert(cameraYaw.isFinite);
  }

  Offset _runnerWorldPosition([_RouteState? route]) {
    final state =
        route ?? _visualRouteStateAt(_distanceMeters, _completedTurnCount);
    final laneOffset =
        (_visualLane - TempleRunRules.centerLane) * (_roadWorldWidth / 3);
    return state.position + _right(state.heading) * laneOffset;
  }

  _RouteState _visualRouteStateAt(double routeDistance, int completedTurns) {
    final outgoing = _routeStateAt(routeDistance, completedTurns);
    final transitionIndex = completedTurns - 1;
    final turns = _course?.turns ?? const <TempleRunTurn>[];
    if (transitionIndex < 0 || transitionIndex >= turns.length) {
      return outgoing;
    }
    final turn = turns[transitionIndex];
    if (_bendDirection != turn.direction) return outgoing;
    // At the exact junction _routeStateAt(J, completedTurns) intentionally
    // returns the incoming leg. Resolve the junction from the prior leg and
    // continue the canonical outgoing centerline from there instead.
    final incoming = _routeStateAt(turn.distanceMeters, transitionIndex);
    final outgoingHeading = incoming.heading + _turnRadians(turn.direction);
    final postTurnDistance = math.max(0.0, routeDistance - turn.distanceMeters);
    final position =
        incoming.position + _forward(outgoingHeading) * postTurnDistance;
    final amount = _turnEaseAmount;
    final heading = incoming.heading + _turnRadians(turn.direction) * amount;
    return _RouteState(position, heading);
  }

  double get _turnEaseAmount =>
      1.0 - math.pow(_bendProgress.clamp(0.0, 1.0), 3).toDouble();

  double _cameraBoomForDistance(_RouteState route) {
    final turns = _course?.turns ?? const <TempleRunTurn>[];
    if (_completedTurnCount <= 0 || _completedTurnCount > turns.length) {
      return _cameraBackMeters;
    }
    final turn = turns[_completedTurnCount - 1];
    if (_distanceMeters < turn.distanceMeters) return _cameraBackMeters;

    // Use the same inset wall spans as the facade renderer. The backward ray
    // stops at the first local wall hit, leaving the relief depth and the
    // requested sightline clearance between the camera and the facade.
    final transitionIndex = _completedTurnCount - 1;
    var boom = _cameraBackMeters;
    for (final spans in [_safeCameraWallSpansLeft, _safeCameraWallSpansRight]) {
      for (final span in spans) {
        if (span.routeLegIndex != transitionIndex &&
            span.routeLegIndex != transitionIndex + 1) {
          continue;
        }
        boom = math.min(
          boom,
          _backwardRaySegmentHit(
            origin: route.position,
            direction: -_forward(route.heading),
            start: span.frontStart,
            end: span.frontEnd,
          ),
        );
      }
    }
    // A valid local wall hit is always beyond the near clip for a runner on
    // the road. Keep the fallback finite if a malformed route has no segment.
    return boom.clamp(_nearClipMeters, _cameraBackMeters).toDouble();
  }

  double get _cameraSafeWallOffset =>
      _roadWorldWidth / 2 +
      1.6 -
      TempleRunRules.maximumFacadeReliefDepthMeters -
      TempleRunRules.cameraCornerClearanceMeters;

  double _backwardRaySegmentHit({
    required Offset origin,
    required Offset direction,
    required Offset start,
    required Offset end,
  }) {
    final edge = end - start;
    final denominator = _cross(direction, edge);
    if (denominator.abs() < .000001) return _cameraBackMeters;
    final startToOrigin = start - origin;
    final distance = _cross(startToOrigin, edge) / denominator;
    final segment = _cross(startToOrigin, direction) / denominator;
    if (distance <= .000001 || segment < -.000001 || segment > 1.000001) {
      return _cameraBackMeters;
    }
    return distance;
  }

  _RouteState _routeStateAt(double routeDistance, int completedTurns) {
    final turns = _course?.turns ?? const <TempleRunTurn>[];
    final distance = math.max(0, routeDistance);
    final allowedTurns = completedTurns.clamp(0, turns.length);
    var position = Offset.zero;
    var heading = 0.0;
    var segmentStart = 0.0;
    for (var index = 0; index < turns.length; index++) {
      final junction = turns[index].distanceMeters;
      if (junction <= segmentStart) continue;
      final segmentEnd = math.min(distance, junction);
      if (segmentEnd > segmentStart) {
        position += _forward(heading) * (segmentEnd - segmentStart);
      }
      if (distance <= junction) return _RouteState(position, heading);
      segmentStart = junction;
      if (index < allowedTurns) {
        heading += _turnRadians(turns[index].direction);
      }
    }
    if (distance > segmentStart) {
      position += _forward(heading) * (distance - segmentStart);
    }
    return _RouteState(position, heading);
  }

  List<_FacadeRouteLeg> _buildPlannedFacadeLegs(TempleRunCourse course) {
    final firstDistance = -_cameraBackMeters - 2;
    final lastTurnDistance = course.turns.isEmpty
        ? 0.0
        : course.turns.last.distanceMeters;
    final finalDistance =
        math.max(course.totalDistanceMeters, lastTurnDistance) + _farClipMeters;
    final boundaries = <double>[firstDistance];
    for (final turn in course.turns) {
      if (turn.distanceMeters > firstDistance &&
          turn.distanceMeters < finalDistance) {
        boundaries.add(turn.distanceMeters);
      }
    }
    boundaries.add(finalDistance);

    return List<_FacadeRouteLeg>.generate(boundaries.length - 1, (index) {
      final start = boundaries[index];
      final end = boundaries[index + 1];
      final origin = _plannedRouteStateAt(start).position;
      final heading = _plannedRouteStateAt((start + end) / 2).heading;
      return _FacadeRouteLeg(
        start: start,
        end: end,
        origin: origin,
        heading: heading,
      );
    }, growable: false);
  }

  _RouteState _plannedRouteStateAt(double routeDistance) {
    if (routeDistance < 0) {
      return _RouteState(_forward(0) * routeDistance, 0);
    }
    final turns = _course?.turns ?? const <TempleRunTurn>[];
    var position = Offset.zero;
    var heading = 0.0;
    var segmentStart = 0.0;
    for (final turn in turns) {
      if (routeDistance <= turn.distanceMeters) break;
      position += _forward(heading) * (turn.distanceMeters - segmentStart);
      segmentStart = turn.distanceMeters;
      heading += _turnRadians(turn.direction);
    }
    if (routeDistance > segmentStart) {
      position += _forward(heading) * (routeDistance - segmentStart);
    }
    return _RouteState(position, heading);
  }

  static Offset _forward(double heading) =>
      Offset(math.sin(heading), math.cos(heading));

  static Offset _right(double heading) =>
      Offset(math.cos(heading), -math.sin(heading));

  static double _turnRadians(TempleRunTurnDirection direction) =>
      direction == TempleRunTurnDirection.left ? -math.pi / 2 : math.pi / 2;

  void _drawBackground(Canvas canvas) {
    final background = _imageFor(backgroundAsset);
    if (background != null) {
      // The authored skyline sits at source row 940 (the former 470px world
      // horizon at 0.5x). Scale uniformly when a tall viewport's lower camera
      // moves that horizon below the base-size background.
      const sourceHorizon = 940.0;
      final sourceCropLeft = math
          .min(background.width * .22, background.width - 1)
          .toDouble();
      final source = Rect.fromLTWH(
        sourceCropLeft,
        0,
        background.width.toDouble() - sourceCropLeft,
        background.height.toDouble(),
      );
      var scale = .5;
      final widthScale = size.x / source.width;
      final horizonScale = _horizonY / sourceHorizon;
      if (widthScale > scale) scale = widthScale;
      if (horizonScale > scale) scale = horizonScale;
      // Keep a wide angular runway for the accumulated heading. The source
      // artwork is a single city view rather than a seamless panorama. Its
      // first quarter contains the clock tower cut by the source edge, so
      // crop that edge before repeating the remaining skyline. Mirroring the
      // clean crop makes both repeat joins share the same source edge and
      // avoids the full-height ghost seam produced by blending unrelated
      // source edges.
      final destinationHeight = background.height * scale;
      final destinationTop = _horizonY - sourceHorizon * scale;
      final destinationWidth = source.width * scale;
      final destinationLeft = (size.x - destinationWidth) / 2;
      final cycleWidth = destinationWidth * 2;
      final phase = _wrapBackgroundOffset(
        _backgroundParallaxPixels(_cameraHeading, destinationWidth),
        cycleWidth,
      );
      final firstLeft = destinationLeft + phase - cycleWidth;
      final destination = Rect.fromLTWH(
        0,
        destinationTop,
        destinationWidth,
        destinationHeight,
      );
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.x, size.y));
      final firstTile = ((-destinationWidth - firstLeft) / destinationWidth)
          .floor();
      final lastTile =
          ((size.x + destinationWidth - firstLeft) / destinationWidth).ceil();
      for (var tile = firstTile; tile <= lastTile; tile++) {
        final left = firstLeft + tile * destinationWidth;
        _drawBackgroundTile(
          canvas,
          background,
          source,
          destination,
          left,
          mirrored: tile.isOdd,
        );
      }
      canvas.restore();
      return;
    }

    final sky = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF173745), Color(0xFF608C77), Color(0xFF1B352B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.x, size.y));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), sky);
    final horizon = _horizonY;
    final center = size.x / 2;
    final mountain = Paint()..color = const Color(0x66547569);
    canvas.drawPath(
      Path()
        ..moveTo(0, horizon + 20)
        ..lineTo(size.x * .2, horizon - size.y * .13)
        ..lineTo(size.x * .42, horizon + 6)
        ..lineTo(size.x * .63, horizon - size.y * .16)
        ..lineTo(size.x, horizon - size.y * .08)
        ..lineTo(size.x, horizon + 45)
        ..lineTo(0, horizon + 45)
        ..close(),
      mountain,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center, horizon + size.y * .08),
        width: size.x * .9,
        height: size.y * .16,
      ),
      Paint()..color = const Color(0x5AB8D1B6),
    );
    final gate = Paint()..color = const Color(0xD08C795A);
    final gateWidth = size.x * .22;
    final gateTop = horizon - size.y * .08;
    final gateHeight = size.y * .12;
    canvas.drawRect(
      Rect.fromLTWH(
        center - gateWidth / 2,
        gateTop,
        gateWidth * .18,
        gateHeight,
      ),
      gate,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center + gateWidth * .32,
        gateTop,
        gateWidth * .18,
        gateHeight,
      ),
      gate,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center - gateWidth / 2,
        gateTop,
        gateWidth,
        gateHeight * .2,
      ),
      gate,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center - gateWidth * .32,
        gateTop + gateHeight * .2,
        gateWidth * .64,
        gateHeight * .8,
      ),
      Paint()..color = const Color(0xCC24423B),
    );
    final foliage = Paint()..color = const Color(0xC21D3B30);
    canvas.drawOval(
      Rect.fromLTWH(-size.x * .24, size.y * .57, size.x * .54, size.y * .5),
      foliage,
    );
    canvas.drawOval(
      Rect.fromLTWH(size.x * .7, size.y * .54, size.x * .54, size.y * .54),
      foliage,
    );
  }

  double _backgroundParallaxPixels(double heading, [double? tileWidth]) {
    // A right turn rotates the camera toward +X, so a stationary world
    // landmark drifts left in screen space. Tying the phase to 2*pi makes four
    // quarter-turns land on the same panorama instead of accumulating an
    // arbitrary pixel period.
    final cycleWidth = (tileWidth ?? size.x) * 2;
    return -heading / (2 * math.pi) * cycleWidth;
  }

  static double _wrapBackgroundOffset(double value, double period) {
    if (!value.isFinite || period <= 0) return 0;
    final wrapped = value % period;
    return wrapped < 0 ? wrapped + period : wrapped;
  }

  void _drawBackgroundTile(
    Canvas canvas,
    ui.Image image,
    Rect source,
    Rect destination,
    double left, {
    required bool mirrored,
  }) {
    final target = destination.shift(Offset(left, 0));
    final paint = Paint()..filterQuality = FilterQuality.none;
    if (!mirrored) {
      canvas.drawImageRect(image, source, target, paint);
      return;
    }
    canvas.save();
    canvas.translate(target.left + target.width, 0);
    canvas.scale(-1, 1);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(0, target.top, target.width, target.height),
      paint,
    );
    canvas.restore();
  }

  void _drawGroundPlane(Canvas canvas) {
    if (!useImageAssets) return;
    final top = _horizonY.clamp(0.0, size.y);
    final asphalt = _imageFor(asphaltAsset);
    if (asphalt == null) {
      return;
    }
    // Keep the asphalt on the same world X/Z plane as the authored route. A
    // single perspective homography means a fixed world point keeps the same
    // texture coordinate through a turn and across a strip/junction boundary.
    final fade = Rect.fromLTWH(0, top, size.x, size.y - top);
    canvas.saveLayer(fade, Paint());
    final forward = _forward(_cameraHeading);
    final right = _right(_cameraHeading);
    const halfWidth = 140.0;
    final near = _nearClipMeters;
    final far = _farClipMeters;
    final nearCenter = _cameraPosition + forward * near;
    final farCenter = _cameraPosition + forward * far;
    final worldPlane = Path()
      ..moveTo(
        (nearCenter - right * halfWidth).dx,
        (nearCenter - right * halfWidth).dy,
      )
      ..lineTo(
        (nearCenter + right * halfWidth).dx,
        (nearCenter + right * halfWidth).dy,
      )
      ..lineTo(
        (farCenter + right * halfWidth).dx,
        (farCenter + right * halfWidth).dy,
      )
      ..lineTo(
        (farCenter - right * halfWidth).dx,
        (farCenter - right * halfWidth).dy,
      )
      ..close();
    canvas.save();
    canvas.clipRect(fade);
    canvas.transform(_groundHomography());
    canvas.drawPath(
      worldPlane,
      Paint()
        ..filterQuality = FilterQuality.none
        ..shader = ui.ImageShader(
          asphalt,
          TileMode.repeated,
          TileMode.repeated,
          _worldTextureMatrix(),
        ),
    );
    canvas.restore();
    if (fade.height > 0) {
      final fadeHeight = math.min(8.0, fade.height);
      final fadeRect = Rect.fromLTWH(0, top, size.x, fadeHeight);
      canvas.drawRect(
        fadeRect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xFFFFFFFF)],
          ).createShader(fadeRect),
      );
    }
    canvas.restore();
  }

  void _drawRoadEdgeDetails(Canvas canvas) {
    if (!useImageAssets) return;
    final window = _visibleFacadeRouteWindow();
    if (window == null || _plannedFacadeLegs.isEmpty) return;
    const gutterColor = Color(0xFF605B58);
    const curbTopColor = Color(0xFF9B8A76);
    const curbSideColor = Color(0xFF665449);
    const sidewalkColor = Color(0xFF857E78);
    for (var legIndex = 0; legIndex < _plannedFacadeLegs.length; legIndex++) {
      if (!_isFacadeLegInDisplayNeighborhood(legIndex)) continue;
      final leg = _plannedFacadeLegs[legIndex];
      final start = math.max(leg.start, window.start);
      final end = math.min(leg.end, window.end);
      if (end <= start + .001) continue;
      final startTurn = (start - leg.start).abs() <= .001
          ? _roadEdgeTurnAt(leg.start)
          : null;
      final endTurn = (end - leg.end).abs() <= .001
          ? _roadEdgeTurnAt(leg.end)
          : null;
      for (final side in const [-1.0, 1.0]) {
        _drawRoadEdgeStrip(
          canvas,
          leg: leg,
          start: start,
          end: end,
          side: side,
          innerOffset: roadGutterInnerMeters,
          outerOffset: roadGutterOuterMeters,
          color: gutterColor,
          startTurn: startTurn,
          endTurn: endTurn,
        );
        _drawRoadEdgeStrip(
          canvas,
          leg: leg,
          start: start,
          end: end,
          side: side,
          innerOffset: roadGutterOuterMeters,
          outerOffset: roadCurbOuterMeters,
          color: curbTopColor,
          height: roadCurbHeightMeters,
          startTurn: startTurn,
          endTurn: endTurn,
        );
        final firstOuter = _roadEdgeEndpoint(
          leg: leg,
          distance: start,
          side: side,
          offset: roadCurbOuterMeters,
          turn: startTurn,
          outgoingLeg: true,
        );
        final secondOuter = _roadEdgeEndpoint(
          leg: leg,
          distance: end,
          side: side,
          offset: roadCurbOuterMeters,
          turn: endTurn,
          outgoingLeg: false,
        );
        _drawRoadEdgeVerticalFace(
          canvas,
          first: firstOuter,
          second: secondOuter,
          height: roadCurbHeightMeters,
          color: curbSideColor,
        );
        _drawRoadEdgeStrip(
          canvas,
          leg: leg,
          start: start,
          end: end,
          side: side,
          innerOffset: roadCurbOuterMeters,
          outerOffset: roadSidewalkOuterMeters,
          color: sidewalkColor,
          startTurn: startTurn,
          endTurn: endTurn,
        );
      }
    }
    // Each leg already terminates at the offset-line miter. A second filled
    // junction band would repaint a detached curb/sidewalk wedge at the turn.
  }

  TempleRunTurn? _roadEdgeTurnAt(double routeDistance) {
    for (final turn in _course?.turns ?? const <TempleRunTurn>[]) {
      if ((turn.distanceMeters - routeDistance).abs() <= .001) return turn;
    }
    return null;
  }

  void _drawRoadEdgeStrip(
    Canvas canvas, {
    required _FacadeRouteLeg leg,
    required double start,
    required double end,
    required double side,
    required double innerOffset,
    required double outerOffset,
    required Color color,
    required TempleRunTurn? startTurn,
    required TempleRunTurn? endTurn,
    double height = 0,
  }) {
    if (end <= start + .001) return;
    final firstInner = _roadEdgeEndpoint(
      leg: leg,
      distance: start,
      side: side,
      offset: innerOffset,
      turn: startTurn,
      outgoingLeg: true,
    );
    final firstOuter = _roadEdgeEndpoint(
      leg: leg,
      distance: start,
      side: side,
      offset: outerOffset,
      turn: startTurn,
      outgoingLeg: true,
    );
    final secondOuter = _roadEdgeEndpoint(
      leg: leg,
      distance: end,
      side: side,
      offset: outerOffset,
      turn: endTurn,
      outgoingLeg: false,
    );
    final secondInner = _roadEdgeEndpoint(
      leg: leg,
      distance: end,
      side: side,
      offset: innerOffset,
      turn: endTurn,
      outgoingLeg: false,
    );
    _drawWorldSolidPolygon(
      canvas,
      [firstInner, firstOuter, secondOuter, secondInner],
      color,
      height: height,
    );
  }

  Offset _roadEdgeEndpoint({
    required _FacadeRouteLeg leg,
    required double distance,
    required double side,
    required double offset,
    required TempleRunTurn? turn,
    required bool outgoingLeg,
  }) {
    final base = leg.centerAt(distance) + _right(leg.heading) * side * offset;
    if (turn == null) return base;
    final incomingHeading = _plannedRouteStateAt(
      math.max(0, turn.distanceMeters - .001),
    ).heading;
    final outgoingHeading = incomingHeading + _turnRadians(turn.direction);
    return roadEdgeTrimmedEndpointForTesting(
      junction: _plannedRouteStateAt(turn.distanceMeters).position,
      incomingHeading: incomingHeading,
      outgoingHeading: outgoingHeading,
      side: side,
      offset: offset,
      outgoingLeg: outgoingLeg,
    );
  }

  void _drawRoadEdgeVerticalFace(
    Canvas canvas, {
    required Offset first,
    required Offset second,
    required double height,
    required Color color,
  }) {
    final polygon = <_CameraPoint>[
      _cameraPoint(first),
      _cameraPoint(second),
      _cameraPoint(second, height: height),
      _cameraPoint(first, height: height),
    ];
    _drawProjectedSolidPolygon(canvas, polygon, color);
  }

  /// Returns the ordered miter join for one road-edge strip. A convex hull of
  /// the four offset endpoints fills the diagonal between the two legs and
  /// can cross the playable opening at a turn. Walking both offset boundaries
  /// through their line intersections preserves the narrow L-shaped gutter.
  @visibleForTesting
  static List<Offset> roadEdgeJunctionBandForTesting({
    required Offset junction,
    required double incomingHeading,
    required double outgoingHeading,
    required double side,
    required double innerOffset,
    required double outerOffset,
  }) {
    final incomingRight = _right(incomingHeading);
    final outgoingRight = _right(outgoingHeading);
    final incomingInner = junction + incomingRight * side * innerOffset;
    final incomingOuter = junction + incomingRight * side * outerOffset;
    final outgoingInner = junction + outgoingRight * side * innerOffset;
    final outgoingOuter = junction + outgoingRight * side * outerOffset;
    final outerMiter = facadeMiterCorner(
      junction: junction,
      incomingHeading: incomingHeading,
      outgoingHeading: outgoingHeading,
      side: side,
      offset: outerOffset,
    );
    final innerMiter = facadeMiterCorner(
      junction: junction,
      incomingHeading: incomingHeading,
      outgoingHeading: outgoingHeading,
      side: side,
      offset: innerOffset,
    );
    return <Offset>[
      incomingInner,
      incomingOuter,
      outerMiter ?? incomingOuter,
      outgoingOuter,
      outgoingInner,
      innerMiter ?? outgoingInner,
    ];
  }

  /// Endpoint of an edge strip at a 90° turn. The inner side must stop at
  /// the offset-line miter; extending the straight leg to the centerline
  /// junction creates an L-shaped curb inside the road opening.
  @visibleForTesting
  static Offset roadEdgeTrimmedEndpointForTesting({
    required Offset junction,
    required double incomingHeading,
    required double outgoingHeading,
    required double side,
    required double offset,
    required bool outgoingLeg,
  }) {
    final heading = outgoingLeg ? outgoingHeading : incomingHeading;
    final offsetPoint = junction + _right(heading) * side * offset;
    final innerSide = outgoingHeading > incomingHeading ? 1.0 : -1.0;
    if ((side - innerSide).abs() > .001) return offsetPoint;
    return facadeMiterCorner(
          junction: junction,
          incomingHeading: incomingHeading,
          outgoingHeading: outgoingHeading,
          side: side,
          offset: offset,
        ) ??
        offsetPoint;
  }

  void _drawWorldSolidPolygon(
    Canvas canvas,
    List<Offset> world,
    Color color, {
    double height = 0,
  }) {
    final camera = [
      for (final point in world) _cameraPoint(point, height: height),
    ];
    _drawProjectedSolidPolygon(canvas, camera, color);
  }

  void _drawProjectedSolidPolygon(
    Canvas canvas,
    List<_CameraPoint> camera,
    Color color,
  ) {
    final clipped = _clipCameraPolygon(camera);
    if (clipped.length < 3) return;
    final projected = clipped.map(_projectCameraPoint).toList(growable: false);
    final path = Path()
      ..moveTo(projected.first.point.dx, projected.first.point.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.point.dx, point.point.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = false
        ..color = color,
    );
  }

  Float64List _groundHomography() {
    final sine = math.sin(_cameraHeading);
    final cosine = math.cos(_cameraHeading);
    final focal = _focalLength * (_cameraTargetDepth / _cameraBackMeters);
    final centerX = size.x / 2;
    final cameraX = _cameraPosition.dx;
    final cameraZ = _cameraPosition.dy;
    final lateralOrigin = -cosine * cameraX + sine * cameraZ;
    final depthOrigin = -sine * cameraX - cosine * cameraZ;
    // Column-major 4x4 matrix. Offset.dx/Offset.dy are world X/Z, while the
    // homogeneous W row is camera depth. This is the same projection used by
    // [_cameraPoint] and [_projectCameraPoint], expressed for Canvas paths.
    return Float64List.fromList(<double>[
      centerX * sine + focal * cosine,
      _horizonY * sine,
      0,
      sine,
      centerX * cosine - focal * sine,
      _horizonY * cosine,
      0,
      cosine,
      0,
      0,
      1,
      0,
      centerX * depthOrigin + focal * lateralOrigin,
      _horizonY * depthOrigin + focal * _cameraHeightMeters,
      0,
      depthOrigin,
    ]);
  }

  static Float64List _worldTextureMatrix() => Float64List.fromList(<double>[
    1 / _asphaltPixelsPerMeter,
    0,
    0,
    0,
    0,
    1 / _asphaltPixelsPerMeter,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  TempleRunTurn? get _upcomingTurn {
    final turns = _course?.turns ?? const <TempleRunTurn>[];
    if (_completedTurnCount >= turns.length) return null;
    final planned = turns[_completedTurnCount];
    final active = _activeTurn;
    if (active != null &&
        active.distanceMeters <= planned.distanceMeters + .01) {
      return active;
    }
    return planned;
  }

  List<TempleRunFacadeWallSpan> _buildFacadeWallSpans({
    required double side,
    required double wallOffset,
    required double roofOffset,
  }) {
    final legs = _plannedFacadeLegs;
    if (legs.isEmpty) return const <TempleRunFacadeWallSpan>[];

    Offset? cornerPoint(int incomingIndex, int outgoingIndex, double offset) {
      final incoming = legs[incomingIndex];
      final outgoing = legs[outgoingIndex];
      final junction = incoming.centerAt(incoming.end);
      return facadeMiterCorner(
        junction: junction,
        incomingHeading: incoming.heading,
        outgoingHeading: outgoing.heading,
        side: side,
        offset: offset,
      );
    }

    double legDistanceAtCorner(
      Offset corner,
      _FacadeRouteLeg leg,
      double routeDistance,
      double offset,
    ) {
      final unextended =
          leg.centerAt(routeDistance) + _right(leg.heading) * side * offset;
      return routeDistance + _dot(corner - unextended, _forward(leg.heading));
    }

    Offset offsetPoint(_FacadeRouteLeg leg, double distance, double offset) =>
        leg.centerAt(distance) + _right(leg.heading) * side * offset;

    final spans = <TempleRunFacadeWallSpan>[];
    var accumulatedArc = legs.first.start;
    for (var legIndex = 0; legIndex < legs.length; legIndex++) {
      final leg = legs[legIndex];
      final startCorner = legIndex == 0
          ? null
          : cornerPoint(legIndex - 1, legIndex, wallOffset);
      final endCorner = legIndex == legs.length - 1
          ? null
          : cornerPoint(legIndex, legIndex + 1, wallOffset);
      final wallStart = startCorner == null
          ? leg.start
          : legDistanceAtCorner(startCorner, leg, leg.start, wallOffset);
      final wallEnd = endCorner == null
          ? leg.end
          : legDistanceAtCorner(endCorner, leg, leg.end, wallOffset);
      if (wallEnd <= wallStart) continue;

      final outerStartCorner = legIndex == 0
          ? null
          : cornerPoint(legIndex - 1, legIndex, roofOffset);
      final outerEndCorner = legIndex == legs.length - 1
          ? null
          : cornerPoint(legIndex, legIndex + 1, roofOffset);
      final roofStart = outerStartCorner == null
          ? leg.start
          : legDistanceAtCorner(outerStartCorner, leg, leg.start, roofOffset);
      final roofEnd = outerEndCorner == null
          ? leg.end
          : legDistanceAtCorner(outerEndCorner, leg, leg.end, roofOffset);
      final span = TempleRunFacadeWallSpan(
        routeLegIndex: legIndex,
        wallStart: wallStart,
        wallEnd: wallEnd,
        wallArcStart: accumulatedArc,
        frontStart: startCorner ?? offsetPoint(leg, wallStart, wallOffset),
        frontEnd: endCorner ?? offsetPoint(leg, wallEnd, wallOffset),
        roofStart: roofStart,
        roofEnd: roofEnd,
        roofStartPoint:
            outerStartCorner ?? offsetPoint(leg, roofStart, roofOffset),
        roofEndPoint: outerEndCorner ?? offsetPoint(leg, roofEnd, roofOffset),
      );
      spans.add(span);
      accumulatedArc = span.wallArcEnd;
    }
    return spans;
  }

  bool _tileTouchesCornerGuard({
    required TempleRunFacadeWallSpan wallLeg,
    required double tileOrigin,
    required double tileLength,
  }) {
    const guard = 1.2;
    final tileStart = wallLeg.wallStart + tileOrigin - wallLeg.wallArcStart;
    final tileEnd = tileStart + tileLength;
    return tileStart < wallLeg.wallStart + guard ||
        tileEnd > wallLeg.wallEnd - guard;
  }

  void _drawFacadeWalls(Canvas canvas) {
    _renderedFacadeOccluders = const <_ProjectedFacadeOccluder>[];
    if (!useImageAssets) return;
    final wallImages = <TempleRunWallTileKind, ui.Image?>{
      TempleRunWallTileKind.plasterA: _imageFor(wallPlasterAAsset),
      TempleRunWallTileKind.plasterB: _imageFor(wallPlasterBAsset),
      TempleRunWallTileKind.window: _imageFor(wallWindowAsset),
      TempleRunWallTileKind.door: _imageFor(wallDoorAsset),
      TempleRunWallTileKind.mural: _imageFor(wallMuralAsset),
      TempleRunWallTileKind.houseBrick: _imageFor(wallHouseBrickAsset),
      TempleRunWallTileKind.houseSage: _imageFor(wallHouseSageAsset),
      TempleRunWallTileKind.houseGarden: _imageFor(wallHouseGardenAsset),
      TempleRunWallTileKind.shopfront: _imageFor(wallShopfrontAsset),
      TempleRunWallTileKind.schoolfront: _imageFor(wallSchoolfrontAsset),
      TempleRunWallTileKind.constructionfront: _imageFor(
        wallConstructionfrontAsset,
      ),
    };
    final fullBleedImages = <String, ui.Image?>{
      streetHouseBrickAsset: _imageFor(streetHouseBrickAsset),
      streetHouseSageAsset: _imageFor(streetHouseSageAsset),
      streetShopfrontAsset: _imageFor(streetShopfrontAsset),
      wallSchoolfrontAsset: _imageFor(wallSchoolfrontAsset),
      wallConstructionfrontAsset: _imageFor(wallConstructionfrontAsset),
    };
    if (wallImages.values.any((image) => image == null) ||
        fullBleedImages.values.any((image) => image == null)) {
      return;
    }
    final plasterA = wallImages[TempleRunWallTileKind.plasterA]!;
    final legs = _plannedFacadeLegs;
    if (legs.isEmpty) return;

    final wallOffset = _roadWorldWidth / 2 + 1.6;
    const wallHeight = facadeHeightMeters;
    final wallLength = wallHeight * plasterA.width / plasterA.height;
    final visibleWindow = _visibleFacadeRouteWindow();
    if (visibleWindow == null) return;
    final visibleStart = visibleWindow.start;
    final visibleEnd = visibleWindow.end;
    final wallItems = <_TempleRunRenderItem>[];
    final occluderPolygons = <List<_CameraPoint>>[];
    _facadeOccluderCollector = occluderPolygons;

    try {
      for (final side in const [-1.0, 1.0]) {
        final wallSpans = side < 0
            ? _facadeWallSpansLeft
            : _facadeWallSpansRight;
        final shadowSpans = side < 0
            ? _facadeShadowWallSpansLeft
            : _facadeShadowWallSpansRight;
        final shadowSpanByLeg = <int, TempleRunFacadeWallSpan>{
          for (final span in shadowSpans) span.routeLegIndex: span,
        };
        for (final wallLeg in wallSpans) {
          if (!_isFacadeLegInDisplayNeighborhood(wallLeg.routeLegIndex)) {
            continue;
          }
          final leg = legs[wallLeg.routeLegIndex];
          final shadowLeg = shadowSpanByLeg[wallLeg.routeLegIndex];
          if (shadowLeg == null) continue;
          final wallStart = wallLeg.wallStart;
          final wallEnd = wallLeg.wallEnd;
          if (wallEnd <= visibleStart || wallStart >= visibleEnd) continue;

          final windowWallStart = math.max(wallStart, visibleStart);
          final windowWallEnd = math.min(wallEnd, visibleEnd);
          final windowArcStart =
              wallLeg.wallArcStart + windowWallStart - wallStart;
          final windowArcEnd = wallLeg.wallArcStart + windowWallEnd - wallStart;
          var tileOrigin = facadeTileOriginForArc(windowArcStart, wallLength);
          while (tileOrigin < windowArcEnd - .001) {
            final tileArcStart = math.max(windowArcStart, tileOrigin);
            final tileArcEnd = math.min(windowArcEnd, tileOrigin + wallLength);
            if (tileArcEnd > tileArcStart) {
              final tileRouteCenter =
                  wallLeg.wallStart +
                  (tileArcStart + tileArcEnd) / 2 -
                  wallLeg.wallArcStart;
              final opacity = _wallWindowOpacity(
                tileRouteCenter,
                visibleStart,
                visibleEnd,
              );
              final tileKind = wallTileKindForArc(
                wallArc: tileOrigin + .001,
                side: side,
              );
              final fullBleedSpec = _fullBleedFacadeSpecs[tileKind];
              if (fullBleedSpec != null) {
                final guarded = _tileTouchesCornerGuard(
                  wallLeg: wallLeg,
                  tileOrigin: tileOrigin,
                  tileLength: wallLength,
                );
                _addFullBleedFacadeTile(
                  items: wallItems,
                  facadeImage: fullBleedImages[fullBleedSpec.asset]!,
                  materialSwatch: fullBleedSpec.materialSwatch,
                  tileKind: tileKind,
                  leg: leg,
                  wallSpan: wallLeg,
                  side: side,
                  wallOffset: wallOffset,
                  tileLength: wallLength,
                  tileArcStart: tileArcStart,
                  tileArcEnd: tileArcEnd,
                  tileOrigin: tileOrigin,
                  opacity: opacity,
                  guarded: guarded,
                );
                tileOrigin += wallLength;
                continue;
              }
              final massSpec = _wallMassSpecs[tileKind];
              final guarded =
                  massSpec != null &&
                  _tileTouchesCornerGuard(
                    wallLeg: wallLeg,
                    tileOrigin: tileOrigin,
                    tileLength: wallLength,
                  );
              final placed = massSpec != null && !guarded;
              final baseKind = placed
                  ? TempleRunWallTileKind.plasterA
                  : (massSpec != null
                        ? tileKind
                        : wallBaseKindForArc(
                            wallArc: tileOrigin + .001,
                            side: side,
                          ));
              final facade = wallImages[baseKind]!;
              final sourceLeft = facadeSourceXForArc(
                wallArc: tileArcStart,
                tileOrigin: tileOrigin,
                tileLength: wallLength,
                sourceWidth: facade.width.toDouble(),
              );
              final sourceRight = facadeSourceXForArc(
                wallArc: tileArcEnd,
                tileOrigin: tileOrigin,
                tileLength: wallLength,
                sourceWidth: facade.width.toDouble(),
              );
              final tileRouteOrigin =
                  wallLeg.wallStart + (tileOrigin - wallLeg.wallArcStart);
              final cameraOrigin = _cameraPoint(
                leg.centerAt(tileRouteOrigin) +
                    _right(leg.heading) * side * wallOffset,
              );
              final matrix = _wallHomography(
                leg: leg,
                cameraOrigin: cameraOrigin,
                wallLength: wallLength,
                sourceWidth: facade.width.toDouble(),
                sourceHeight: facade.height.toDouble(),
                height: wallHeight,
              );
              final visibleSource = _visibleWallSourceU(
                cameraOrigin: cameraOrigin,
                leg: leg,
                sourceWidth: facade.width.toDouble(),
                wallLength: wallLength,
              );
              double? baseTileDepth;
              if (visibleSource != null) {
                final sourceRanges =
                    <
                      ({double left, double right, double top, double bottom})
                    >[];
                void addSourceRange({
                  required double left,
                  required double right,
                  required double top,
                  required double bottom,
                }) {
                  final clippedLeft = math.max(sourceLeft, left);
                  final clippedRight = math.min(sourceRight, right);
                  if (clippedRight <= clippedLeft + .001 ||
                      bottom <= top + .001) {
                    return;
                  }
                  sourceRanges.add((
                    left: clippedLeft,
                    right: clippedRight,
                    top: top,
                    bottom: bottom,
                  ));
                }

                if (placed) {
                  // Cut the original wall in two dimensions around the moved
                  // module. Its lower footprint is drawn once at the shifted
                  // mass depth; retaining the top strip keeps the continuous
                  // 5.5m skyline behind short shop/garden fronts.
                  final massLeft = massSpec.source.left * facade.width;
                  final massRight = massSpec.source.right * facade.width;
                  final massTop = massSpec.source.top * facade.height;
                  final massBottom = massSpec.source.bottom * facade.height;
                  addSourceRange(
                    left: double.negativeInfinity,
                    right: massLeft,
                    top: 0,
                    bottom: facade.height.toDouble(),
                  );
                  addSourceRange(
                    left: massRight,
                    right: double.infinity,
                    top: 0,
                    bottom: facade.height.toDouble(),
                  );
                  addSourceRange(
                    left: massLeft,
                    right: massRight,
                    top: 0,
                    bottom: massTop,
                  );
                  addSourceRange(
                    left: massLeft,
                    right: massRight,
                    top: massBottom,
                    bottom: facade.height.toDouble(),
                  );
                } else {
                  addSourceRange(
                    left: sourceLeft,
                    right: sourceRight,
                    top: 0,
                    bottom: facade.height.toDouble(),
                  );
                }
                final unitDepth =
                    _dot(_forward(leg.heading), _forward(_cameraHeading)) *
                    wallLength /
                    facade.width;
                for (final range in sourceRanges) {
                  final cropLeft = math.max(range.left, visibleSource.start);
                  final cropRight = math.min(range.right, visibleSource.end);
                  if (cropRight <= cropLeft + .001) continue;
                  final depth =
                      cameraOrigin.depth +
                      unitDepth * (cropLeft + cropRight) / 2;
                  baseTileDepth ??= depth;
                  final sourceRect = Rect.fromLTRB(
                    cropLeft,
                    range.top,
                    cropRight,
                    range.bottom,
                  );
                  final destinationRect = Rect.fromLTRB(
                    range.left <= .001
                        ? cropLeft - _wallTileBoundaryOverlapSourcePixels
                        : cropLeft,
                    range.top,
                    range.right >= facade.width - .001
                        ? cropRight + _wallTileBoundaryOverlapSourcePixels
                        : cropRight,
                    range.bottom,
                  );
                  wallItems.add(
                    _TempleRunRenderItem(
                      depth: depth,
                      draw: (canvas) => _drawHomographicWallTile(
                        canvas,
                        facade,
                        sourceRect,
                        matrix,
                        opacity,
                        destinationRect: destinationRect,
                      ),
                    ),
                  );
                  final backingArcStart =
                      tileOrigin + cropLeft / facade.width * wallLength;
                  final backingArcEnd =
                      tileOrigin + cropRight / facade.width * wallLength;
                  final backingBottomHeight =
                      wallHeight * (1 - range.bottom / facade.height);
                  final backingTopHeight =
                      wallHeight * (1 - range.top / facade.height);
                  _recordFacadePolygon(<_CameraPoint>[
                    _cameraPoint(
                      leg.centerAt(
                            wallLeg.wallStart +
                                (backingArcStart - wallLeg.wallArcStart),
                          ) +
                          _right(leg.heading) * side * wallOffset,
                    ),
                    _cameraPoint(
                      leg.centerAt(
                            wallLeg.wallStart +
                                (backingArcEnd - wallLeg.wallArcStart),
                          ) +
                          _right(leg.heading) * side * wallOffset,
                    ),
                    _cameraPoint(
                      leg.centerAt(
                            wallLeg.wallStart +
                                (backingArcEnd - wallLeg.wallArcStart),
                          ) +
                          _right(leg.heading) * side * wallOffset,
                      height: backingBottomHeight,
                    ),
                    _cameraPoint(
                      leg.centerAt(
                            wallLeg.wallStart +
                                (backingArcStart - wallLeg.wallArcStart),
                          ) +
                          _right(leg.heading) * side * wallOffset,
                      height: backingTopHeight,
                    ),
                  ]);
                }
              }
              if (!placed) {
                _addFacadeContactShadow(
                  items: wallItems,
                  leg: leg,
                  wallSpan: wallLeg,
                  side: side,
                  frontOffset: wallOffset,
                  tileArcStart: tileArcStart,
                  tileArcEnd: tileArcEnd,
                  opacity: opacity,
                );
              }
              if (placed) {
                _addFacadeMassModule(
                  items: wallItems,
                  massImage: wallImages[tileKind]!,
                  plasterImage: plasterA,
                  spec: massSpec,
                  leg: leg,
                  wallSpan: wallLeg,
                  side: side,
                  wallOffset: wallOffset,
                  tileLength: wallLength,
                  tileArcStart: tileArcStart,
                  tileArcEnd: tileArcEnd,
                  tileOrigin: tileOrigin,
                  opacity: opacity,
                );
                final massDetailArcStart = math.max(
                  tileArcStart,
                  tileOrigin + massSpec.source.left * wallLength,
                );
                final massDetailArcEnd = math.min(
                  tileArcEnd,
                  tileOrigin + massSpec.source.right * wallLength,
                );
                _addFacadeDepthDetails(
                  items: wallItems,
                  tileKind: tileKind,
                  leg: leg,
                  wallSpan: wallLeg,
                  shadowSpan: shadowLeg,
                  side: side,
                  wallOffset: wallOffset - massSpec.depth,
                  tileLength: wallLength,
                  tileArcStart: massDetailArcStart,
                  tileArcEnd: massDetailArcEnd,
                  tileOrigin: tileOrigin,
                  opacity: opacity,
                  tileDepth: baseTileDepth,
                  featureImage: null,
                  drawCornice: false,
                );
              } else {
                _addFacadeDepthDetails(
                  items: wallItems,
                  tileKind: tileKind,
                  leg: leg,
                  wallSpan: wallLeg,
                  shadowSpan: shadowLeg,
                  side: side,
                  wallOffset: wallOffset,
                  tileLength: wallLength,
                  tileArcStart: tileArcStart,
                  tileArcEnd: tileArcEnd,
                  tileOrigin: tileOrigin,
                  opacity: opacity,
                  tileDepth: baseTileDepth,
                  featureImage: switch (tileKind) {
                    TempleRunWallTileKind.window =>
                      wallImages[TempleRunWallTileKind.window],
                    TempleRunWallTileKind.door =>
                      wallImages[TempleRunWallTileKind.door],
                    TempleRunWallTileKind.mural =>
                      wallImages[TempleRunWallTileKind.mural],
                    _ => null,
                  },
                );
              }
            }
            tileOrigin += wallLength;
          }
        }
      }
    } finally {
      _facadeOccluderCollector = null;
    }
    _renderedFacadeOccluders = _projectedFacadeOccludersFromPolygons(
      occluderPolygons,
    );
    wallItems.sort((a, b) => b.depth.compareTo(a.depth));
    for (final item in wallItems) {
      item.draw(canvas);
    }
  }

  void _addFullBleedFacadeTile({
    required List<_TempleRunRenderItem> items,
    required ui.Image facadeImage,
    required Rect materialSwatch,
    required TempleRunWallTileKind tileKind,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double wallOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
    required bool guarded,
  }) {
    if (opacity <= .01 || tileArcEnd <= tileArcStart) return;
    final planeWidth = facadeImage.width.toDouble();
    final planeHeight = facadeImage.height.toDouble();
    final facadeSpec = _fullBleedFacadeSpecs[tileKind];
    final setback = facadeSpec?.setback ?? 0;
    final frontOffset = wallOffset - (guarded ? 0 : setback);
    final activeProps = guarded
        ? const <_TempleRunFullBleedPropSpec>[]
        : (_fullBleedPropSpecs[tileKind] ??
              const <_TempleRunFullBleedPropSpec>[]);
    _addFacadeContactShadow(
      items: items,
      leg: leg,
      wallSpan: wallSpan,
      side: side,
      frontOffset: frontOffset,
      tileArcStart: tileArcStart,
      tileArcEnd: tileArcEnd,
      opacity: opacity,
    );
    var bodyRects = <Rect>[Rect.fromLTWH(0, 0, planeWidth, planeHeight)];
    for (final prop in activeProps) {
      final propRect = Rect.fromLTRB(
        prop.source.left * planeWidth,
        prop.source.top * planeHeight,
        prop.source.right * planeWidth,
        prop.source.bottom * planeHeight,
      );
      final nextRects = <Rect>[];
      for (final bodyRect in bodyRects) {
        final cut = Rect.fromLTRB(
          math.max(bodyRect.left, propRect.left),
          math.max(bodyRect.top, propRect.top),
          math.min(bodyRect.right, propRect.right),
          math.min(bodyRect.bottom, propRect.bottom),
        );
        if (cut.right <= cut.left || cut.bottom <= cut.top) {
          nextRects.add(bodyRect);
          continue;
        }
        if (bodyRect.top < cut.top) {
          nextRects.add(
            Rect.fromLTRB(bodyRect.left, bodyRect.top, bodyRect.right, cut.top),
          );
        }
        if (cut.bottom < bodyRect.bottom) {
          nextRects.add(
            Rect.fromLTRB(
              bodyRect.left,
              cut.bottom,
              bodyRect.right,
              bodyRect.bottom,
            ),
          );
        }
        if (bodyRect.left < cut.left) {
          nextRects.add(
            Rect.fromLTRB(bodyRect.left, cut.top, cut.left, cut.bottom),
          );
        }
        if (cut.right < bodyRect.right) {
          nextRects.add(
            Rect.fromLTRB(cut.right, cut.top, bodyRect.right, cut.bottom),
          );
        }
      }
      bodyRects = nextRects;
    }
    for (final bodyRect in bodyRects) {
      _addFacadeTexturedPlaneBands(
        items: items,
        materialImage: facadeImage,
        planeWidth: planeWidth,
        planeHeight: planeHeight,
        planeRect: bodyRect,
        materialRect: bodyRect,
        leg: leg,
        wallSpan: wallSpan,
        side: side,
        planeOffset: frontOffset,
        tileLength: tileLength,
        tileArcStart: tileArcStart,
        tileArcEnd: tileArcEnd,
        tileOrigin: tileOrigin,
        opacity: opacity,
        cullBackFace: true,
        spanStartPoint: guarded ? wallSpan.frontStart : null,
        spanEndPoint: guarded ? wallSpan.frontEnd : null,
      );
    }
    for (final prop in activeProps) {
      final propRect = Rect.fromLTRB(
        prop.source.left * planeWidth,
        prop.source.top * planeHeight,
        prop.source.right * planeWidth,
        prop.source.bottom * planeHeight,
      );
      final volume = _TempleRunWallVolumeSpec(
        source: prop.source,
        frontDepth: prop.frontDepth,
        maskColor: Colors.transparent,
        sideColor: prop.sideColor,
        capColor: prop.capColor,
      );
      _addFacadeVolume(
        items: items,
        materialImage: facadeImage,
        sideImage: facadeImage,
        volume: volume,
        planeRect: propRect,
        backOffset: frontOffset,
        frontOffset: frontOffset - prop.frontDepth,
        leg: leg,
        wallSpan: wallSpan,
        side: side,
        tileLength: tileLength,
        tileArcStart: tileArcStart,
        tileArcEnd: tileArcEnd,
        tileOrigin: tileOrigin,
        opacity: opacity,
      );
    }
    if (!guarded && (facadeSpec?.heightExtension ?? 0) > .001) {
      _addFullBleedHeightExtension(
        items: items,
        materialImage: facadeImage,
        materialSwatch: materialSwatch,
        topCapColor: facadeSpec!.topCapColor,
        extensionHeight: facadeSpec.heightExtension,
        leg: leg,
        wallSpan: wallSpan,
        side: side,
        backOffset: wallOffset,
        frontOffset: frontOffset,
        tileLength: tileLength,
        tileArcStart: tileArcStart,
        tileArcEnd: tileArcEnd,
        tileOrigin: tileOrigin,
        opacity: opacity,
      );
    }

    void addReturnAt(double boundaryArc, {required bool atStart}) {
      if (boundaryArc <= wallSpan.wallArcStart + .001 ||
          boundaryArc >= wallSpan.wallArcEnd - .001) {
        return;
      }
      final neighborArc = atStart ? boundaryArc - .001 : boundaryArc + .001;
      final neighborKind = wallTileKindForArc(wallArc: neighborArc, side: side);
      final neighborSpec = _fullBleedFacadeSpecs[neighborKind];
      final neighborTileOrigin = facadeTileOriginForArc(
        neighborArc,
        tileLength,
      );
      final neighborGuarded =
          neighborSpec != null &&
          _tileTouchesCornerGuard(
            wallLeg: wallSpan,
            tileOrigin: neighborTileOrigin,
            tileLength: tileLength,
          );
      final sameProperty =
          facadeSpec != null &&
          neighborSpec != null &&
          neighborKind == tileKind;
      if (sameProperty) return;
      final neighborOffset = neighborSpec == null
          ? wallOffset
          : wallOffset - (neighborGuarded ? 0 : neighborSpec.setback);
      final extension = facadeSpec?.heightExtension ?? 0;
      final neighborExtension = neighborGuarded
          ? 0.0
          : (neighborSpec?.heightExtension ?? 0);
      final boundaryRoute =
          wallSpan.wallStart + boundaryArc - wallSpan.wallArcStart;
      if (frontOffset < neighborOffset - .001) {
        _addFullBleedMaterialReturn(
          items: items,
          materialImage: facadeImage,
          materialSwatch: materialSwatch,
          leg: leg,
          wallSpan: wallSpan,
          side: side,
          route: boundaryRoute,
          backOffset: neighborOffset,
          frontOffset: frontOffset,
          atStart: atStart,
          opacity: opacity,
        );
      }
      if (_needsFullBleedHeightSideCap(
        currentFrontOffset: frontOffset,
        neighborFrontOffset: neighborOffset,
        currentHeightExtension: extension,
        neighborHeightExtension: neighborExtension,
        currentGuarded: guarded,
      )) {
        _addFullBleedMaterialReturn(
          items: items,
          materialImage: facadeImage,
          materialSwatch: materialSwatch,
          leg: leg,
          wallSpan: wallSpan,
          side: side,
          route: boundaryRoute,
          backOffset: wallOffset,
          frontOffset: frontOffset,
          atStart: atStart,
          opacity: opacity,
          bottomHeight: facadeHeightMeters,
          topHeight: facadeHeightMeters + extension,
        );
      }
      if (facadeSpec != null && (!atStart || neighborSpec == null)) {
        final seamOffset = neighborSpec == null
            ? frontOffset + .015
            : math.max(frontOffset, neighborOffset) + .015;
        _addFullBleedPropertySeam(
          items: items,
          leg: leg,
          side: side,
          route: boundaryRoute,
          offset: seamOffset,
          height: facadeHeightMeters + extension,
          atStart: atStart,
          color: _fullBleedPropertySeamColor(tileKind),
          opacity: opacity,
        );
      }
    }

    addReturnAt(tileOrigin, atStart: true);
    addReturnAt(tileOrigin + tileLength, atStart: false);
  }

  void _addFacadeContactShadow({
    required List<_TempleRunRenderItem> items,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double frontOffset,
    required double tileArcStart,
    required double tileArcEnd,
    required double opacity,
  }) {
    if (opacity <= .01 || tileArcEnd <= tileArcStart) return;
    const shadowColor = Color(0x5A342C2A);
    var arcStart = tileArcStart;
    while (arcStart < tileArcEnd - .001) {
      final arcEnd = math.min(tileArcEnd, arcStart + 1.0);
      final routeStart = wallSpan.wallStart + arcStart - wallSpan.wallArcStart;
      final routeEnd = wallSpan.wallStart + arcEnd - wallSpan.wallArcStart;
      Offset point(double route, double offset) =>
          leg.centerAt(route) + _right(leg.heading) * side * offset;
      final polygon = <_CameraPoint>[
        _cameraPoint(point(routeStart, frontOffset)),
        _cameraPoint(point(routeEnd, frontOffset)),
        _cameraPoint(
          point(routeEnd, frontOffset + facadeContactShadowWidthMeters),
        ),
        _cameraPoint(
          point(routeStart, frontOffset + facadeContactShadowWidthMeters),
        ),
      ];
      _addFacadeSolid(
        items,
        polygon,
        color: shadowColor,
        opacity: opacity,
        depthBias: .001,
        cullBackFace: false,
      );
      if (arcEnd <= arcStart + .001) break;
      arcStart = arcEnd;
    }
  }

  static bool _needsFullBleedHeightSideCap({
    required double currentFrontOffset,
    required double neighborFrontOffset,
    required double currentHeightExtension,
    required double neighborHeightExtension,
    required bool currentGuarded,
  }) {
    if (currentGuarded || currentHeightExtension <= .001) return false;
    final sameFootprint =
        (neighborFrontOffset - currentFrontOffset).abs() < .001 &&
        (neighborHeightExtension - currentHeightExtension).abs() < .001;
    return !sameFootprint;
  }

  static Color _fullBleedPropertySeamColor(TempleRunWallTileKind kind) =>
      switch (kind) {
        TempleRunWallTileKind.houseBrick => const Color(0xFF684338),
        TempleRunWallTileKind.houseSage ||
        TempleRunWallTileKind.houseGarden => const Color(0xFF56645F),
        TempleRunWallTileKind.shopfront => const Color(0xFF4D5A60),
        _ => const Color(0xFF6E5A4A),
      };

  void _addFullBleedPropertySeam({
    required List<_TempleRunRenderItem> items,
    required _FacadeRouteLeg leg,
    required double side,
    required double route,
    required double offset,
    required double height,
    required bool atStart,
    required Color color,
    required double opacity,
  }) {
    if (opacity <= .01 || height <= .001) return;
    const seamWidth = .08;
    final startRoute = route - seamWidth / 2;
    final endRoute = route + seamWidth / 2;
    Offset point(double routeDistance) =>
        leg.centerAt(routeDistance) + _right(leg.heading) * side * offset;
    final polygon = <_CameraPoint>[
      _cameraPoint(point(startRoute)),
      _cameraPoint(point(endRoute)),
      _cameraPoint(point(endRoute), height: height),
      _cameraPoint(point(startRoute), height: height),
    ];
    if (side < 0) {
      final first = polygon.first;
      polygon
        ..clear()
        ..addAll(<_CameraPoint>[
          first,
          _cameraPoint(point(startRoute), height: height),
          _cameraPoint(point(endRoute), height: height),
          _cameraPoint(point(endRoute)),
        ]);
    }
    _addFacadeSolid(
      items,
      polygon,
      color: color,
      opacity: opacity,
      depthBias: 0,
      cullBackFace: true,
    );
  }

  void _addFullBleedHeightExtension({
    required List<_TempleRunRenderItem> items,
    required ui.Image materialImage,
    required Rect materialSwatch,
    required Color topCapColor,
    required double extensionHeight,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double backOffset,
    required double frontOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
  }) {
    if (opacity <= .01 || extensionHeight <= .001) return;
    final imageWidth = materialImage.width.toDouble();
    final imageHeight = materialImage.height.toDouble();
    final swatchWorldWidth = tileLength * materialSwatch.width / imageWidth;
    final swatchWorldHeight =
        facadeHeightMeters * materialSwatch.height / imageHeight;
    if (swatchWorldWidth <= .001 || swatchWorldHeight <= .001) return;
    final sourceHeight = math.max(
      1.0,
      math.min(
        materialSwatch.height,
        materialSwatch.height * extensionHeight / swatchWorldHeight,
      ),
    );
    final topHeight = facadeHeightMeters + extensionHeight;
    final tileEnd = tileOrigin + tileLength;

    for (
      var segmentStart = tileOrigin;
      segmentStart < tileEnd - .001;
      segmentStart += swatchWorldWidth
    ) {
      final segmentEnd = math.min(tileEnd, segmentStart + swatchWorldWidth);
      final arcStart = math.max(tileArcStart, segmentStart);
      final arcEnd = math.min(tileArcEnd, segmentEnd);
      if (arcEnd <= arcStart + .001) continue;
      final segmentLength = segmentEnd - segmentStart;
      final sourceWidth = math.max(
        1.0,
        materialSwatch.width * segmentLength / swatchWorldWidth,
      );
      final fullRouteStart =
          wallSpan.wallStart + segmentStart - wallSpan.wallArcStart;
      final routeStart = wallSpan.wallStart + arcStart - wallSpan.wallArcStart;
      final routeEnd = wallSpan.wallStart + arcEnd - wallSpan.wallArcStart;
      Offset point(double route) =>
          leg.centerAt(route) + _right(leg.heading) * side * frontOffset;
      final polygon = <_CameraPoint>[
        _cameraPoint(point(routeStart), height: facadeHeightMeters),
        _cameraPoint(point(routeEnd), height: facadeHeightMeters),
        _cameraPoint(point(routeEnd), height: topHeight),
        _cameraPoint(point(routeStart), height: topHeight),
      ];
      if (side < 0) {
        final first = polygon.first;
        polygon
          ..clear()
          ..addAll(<_CameraPoint>[
            first,
            _cameraPoint(point(routeStart), height: topHeight),
            _cameraPoint(point(routeEnd), height: topHeight),
            _cameraPoint(point(routeEnd), height: facadeHeightMeters),
          ]);
      }
      final clipped = _clipCameraPolygon(polygon);
      if (clipped.length >= 3 && _isCameraFaceVisible(clipped)) {
        _recordFacadePolygon(clipped);
        final projected = clipped
            .map(_projectCameraPoint)
            .toList(growable: false);
        final depth =
            projected.fold<double>(0, (sum, point) => sum + point.depth) /
            projected.length;
        final matrix = _wallHomography(
          leg: leg,
          cameraOrigin: _cameraPoint(point(fullRouteStart)),
          wallLength: segmentLength,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          height: topHeight,
          bottomHeight: facadeHeightMeters,
        );
        final projectedPath = Path()
          ..moveTo(projected.first.point.dx, projected.first.point.dy);
        for (final projectedPoint in projected.skip(1)) {
          projectedPath.lineTo(
            projectedPoint.point.dx,
            projectedPoint.point.dy,
          );
        }
        projectedPath.close();
        items.add(
          _TempleRunRenderItem(
            depth: depth,
            draw: (canvas) {
              canvas.save();
              canvas.clipPath(projectedPath);
              _drawHomographicWallTile(
                canvas,
                materialImage,
                Rect.fromLTWH(
                  materialSwatch.left,
                  materialSwatch.top,
                  sourceWidth,
                  sourceHeight,
                ),
                matrix,
                opacity,
                destinationRect: Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
              );
              canvas.restore();
            },
          ),
        );
      }
    }

    for (
      var bandStart = tileArcStart;
      bandStart < tileArcEnd - .001;
      bandStart = math.min(tileArcEnd, bandStart + 1.0)
    ) {
      final bandEnd = math.min(tileArcEnd, bandStart + 1.0);
      final routeStart = wallSpan.wallStart + bandStart - wallSpan.wallArcStart;
      final routeEnd = wallSpan.wallStart + bandEnd - wallSpan.wallArcStart;
      Offset point(double route, double offset) =>
          leg.centerAt(route) + _right(leg.heading) * side * offset;
      final polygon = <_CameraPoint>[
        _cameraPoint(point(routeStart, backOffset), height: topHeight),
        _cameraPoint(point(routeEnd, backOffset), height: topHeight),
        _cameraPoint(point(routeEnd, frontOffset), height: topHeight),
        _cameraPoint(point(routeStart, frontOffset), height: topHeight),
      ];
      if (side > 0) {
        final first = polygon.first;
        final second = polygon[1];
        final third = polygon[2];
        final fourth = polygon[3];
        polygon
          ..clear()
          ..addAll(<_CameraPoint>[first, fourth, third, second]);
      }
      _addFacadeSolid(
        items,
        polygon,
        color: topCapColor,
        opacity: opacity,
        depthBias: 0,
        cullBackFace: true,
      );
    }
  }

  void _addFullBleedMaterialReturn({
    required List<_TempleRunRenderItem> items,
    required ui.Image materialImage,
    required Rect materialSwatch,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double route,
    required double backOffset,
    required double frontOffset,
    required bool atStart,
    required double opacity,
    double bottomHeight = 0,
    double? topHeight,
  }) {
    final returnLength = backOffset - frontOffset;
    if (opacity <= .01 || returnLength <= .001) return;
    final resolvedTopHeight = topHeight ?? facadeHeightMeters;
    if (resolvedTopHeight <= bottomHeight + .001) return;
    final returnHeading = leg.heading - side * math.pi / 2;
    final returnLeg = _FacadeRouteLeg(
      start: 0,
      end: returnLength,
      origin: Offset.zero,
      heading: returnHeading,
    );
    final swatchWorldHeight =
        facadeHeightMeters * materialSwatch.height / materialImage.height;
    final sourceWidth = math.max(
      1.0,
      math.min(
        materialSwatch.width,
        materialSwatch.width * returnLength / swatchWorldHeight,
      ),
    );
    for (var bottom = bottomHeight; bottom < resolvedTopHeight - .001;) {
      final top = math.min(resolvedTopHeight, bottom + swatchWorldHeight);
      final sourceHeight =
          materialSwatch.height * (top - bottom) / swatchWorldHeight;
      final backPoint =
          leg.centerAt(route) + _right(leg.heading) * side * backOffset;
      final frontPoint =
          leg.centerAt(route) + _right(leg.heading) * side * frontOffset;
      final polygon = <_CameraPoint>[
        _cameraPoint(backPoint, height: bottom),
        _cameraPoint(frontPoint, height: bottom),
        _cameraPoint(frontPoint, height: top),
        _cameraPoint(backPoint, height: top),
      ];
      final preserveWinding = (side > 0 && atStart) || (side < 0 && !atStart);
      if (!preserveWinding) {
        final first = polygon.first;
        final second = polygon[1];
        final third = polygon[2];
        final fourth = polygon[3];
        polygon
          ..clear()
          ..addAll(<_CameraPoint>[first, fourth, third, second]);
      }
      final clipped = _clipCameraPolygon(polygon);
      if (clipped.length >= 3 && _isCameraFaceVisible(clipped)) {
        _recordFacadePolygon(clipped);
        final projected = clipped
            .map(_projectCameraPoint)
            .toList(growable: false);
        final depth =
            projected.fold<double>(0, (sum, point) => sum + point.depth) /
            projected.length;
        final matrix = _wallHomography(
          leg: returnLeg,
          cameraOrigin: _cameraPoint(backPoint),
          wallLength: returnLength,
          sourceWidth: sourceWidth,
          sourceHeight: sourceHeight,
          height: top,
          bottomHeight: bottom,
        );
        final projectedPath = Path()
          ..moveTo(projected.first.point.dx, projected.first.point.dy);
        for (final point in projected.skip(1)) {
          projectedPath.lineTo(point.point.dx, point.point.dy);
        }
        projectedPath.close();
        items.add(
          _TempleRunRenderItem(
            depth: depth,
            draw: (canvas) {
              canvas.save();
              canvas.clipPath(projectedPath);
              _drawHomographicWallTile(
                canvas,
                materialImage,
                Rect.fromLTWH(
                  materialSwatch.left,
                  materialSwatch.top,
                  sourceWidth,
                  sourceHeight,
                ),
                matrix,
                opacity,
                destinationRect: Rect.fromLTWH(0, 0, sourceWidth, sourceHeight),
              );
              canvas.restore();
            },
          ),
        );
      }
      if (top <= bottom + .001) break;
      bottom = top;
    }
  }

  void _addFacadeDepthDetails({
    required List<_TempleRunRenderItem> items,
    required TempleRunWallTileKind tileKind,
    required ui.Image? featureImage,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required TempleRunFacadeWallSpan shadowSpan,
    required double side,
    required double wallOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
    required double? tileDepth,
    bool drawCornice = true,
  }) {
    if (opacity <= .01 || tileArcEnd <= tileArcStart || tileDepth == null) {
      return;
    }

    // Keep every ordinary wall on the same warm plaster palette. The texture
    // carries the small A/B variation; geometry only supplies shared depth.
    const frontColor = Color(0xFFF0E8D8);
    const sideColor = Color(0xFF9AA3A6);
    const capColor = Color(0xFFE4D8C7);
    final routeStart =
        wallSpan.wallStart + tileArcStart - wallSpan.wallArcStart;
    final routeEnd = wallSpan.wallStart + tileArcEnd - wallSpan.wallArcStart;
    final atSpanStart = (tileArcStart - wallSpan.wallArcStart).abs() < .001;
    final atSpanEnd = (tileArcEnd - wallSpan.wallArcEnd).abs() < .001;

    Offset wallPoint(
      double routeDistance, {
      required bool start,
      required bool end,
    }) {
      if (start && atSpanStart) return wallSpan.frontStart;
      if (end && atSpanEnd) return wallSpan.frontEnd;
      return leg.centerAt(routeDistance) +
          _right(leg.heading) * side * wallOffset;
    }

    Offset cornicePoint(
      double routeDistance, {
      required bool start,
      required bool end,
    }) {
      if (start && atSpanStart) return wallSpan.roofStartPoint;
      if (end && atSpanEnd) return wallSpan.roofEndPoint;
      return leg.centerAt(routeDistance) +
          _right(leg.heading) * side * (wallOffset - facadeCorniceDepthMeters);
    }

    Offset shadowPoint(
      double routeDistance, {
      required bool start,
      required bool end,
    }) {
      if (start && atSpanStart) return shadowSpan.roofStartPoint;
      if (end && atSpanEnd) return shadowSpan.roofEndPoint;
      return leg.centerAt(routeDistance) +
          _right(leg.heading) *
              side *
              (wallOffset - facadeFootShadowDepthMeters);
    }

    final wallStart = wallPoint(routeStart, start: true, end: false);
    final wallEnd = wallPoint(routeEnd, start: false, end: true);
    final corniceStart = cornicePoint(routeStart, start: true, end: false);
    final corniceEnd = cornicePoint(routeEnd, start: false, end: true);
    final shadowStart = shadowPoint(routeStart, start: true, end: false);
    final shadowEnd = shadowPoint(routeEnd, start: false, end: true);

    final baseOffset = wallOffset - facadeBaseLedgeDepthMeters;
    Offset basePoint(
      double routeDistance, {
      required bool start,
      required bool end,
    }) {
      if (start && atSpanStart) {
        final junction = leg.centerAt(routeDistance);
        return junction +
            (wallSpan.frontStart - junction) * (baseOffset / wallOffset);
      }
      if (end && atSpanEnd) {
        final junction = leg.centerAt(routeDistance);
        return junction +
            (wallSpan.frontEnd - junction) * (baseOffset / wallOffset);
      }
      return leg.centerAt(routeDistance) +
          _right(leg.heading) * side * baseOffset;
    }

    final baseStart = basePoint(routeStart, start: true, end: false);
    final baseEnd = basePoint(routeEnd, start: false, end: true);
    final baseGroundStart =
        leg.centerAt(routeStart) +
        _right(leg.heading) * side * (baseOffset - .035);
    final baseGroundEnd =
        leg.centerAt(routeEnd) +
        _right(leg.heading) * side * (baseOffset - .035);

    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(baseStart, height: .02),
        _cameraPoint(baseEnd, height: .02),
        _cameraPoint(baseEnd, height: facadeBaseLedgeHeightMeters),
        _cameraPoint(baseStart, height: facadeBaseLedgeHeightMeters),
      ],
      color: frontColor,
      opacity: opacity,
      depthBias: -.033,
    );
    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(baseStart, height: facadeBaseLedgeHeightMeters),
        _cameraPoint(baseEnd, height: facadeBaseLedgeHeightMeters),
        _cameraPoint(wallEnd, height: facadeBaseLedgeHeightMeters),
        _cameraPoint(wallStart, height: facadeBaseLedgeHeightMeters),
      ],
      color: sideColor.withValues(alpha: .72),
      opacity: opacity,
      depthBias: -.034,
    );
    if (atSpanStart) {
      _addFacadeSolid(
        items,
        <_CameraPoint>[
          _cameraPoint(wallStart, height: .02),
          _cameraPoint(baseStart, height: .02),
          _cameraPoint(baseStart, height: facadeBaseLedgeHeightMeters),
          _cameraPoint(wallStart, height: facadeBaseLedgeHeightMeters),
        ],
        color: sideColor,
        opacity: opacity,
        depthBias: -.035,
      );
    }
    if (atSpanEnd) {
      _addFacadeSolid(
        items,
        <_CameraPoint>[
          _cameraPoint(baseEnd, height: .02),
          _cameraPoint(wallEnd, height: .02),
          _cameraPoint(wallEnd, height: facadeBaseLedgeHeightMeters),
          _cameraPoint(baseEnd, height: facadeBaseLedgeHeightMeters),
        ],
        color: sideColor,
        opacity: opacity,
        depthBias: -.036,
      );
    }
    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(baseStart, height: .01),
        _cameraPoint(baseEnd, height: .01),
        _cameraPoint(baseGroundEnd, height: .01),
        _cameraPoint(baseGroundStart, height: .01),
      ],
      color: const Color(0x553D4547),
      opacity: opacity,
      depthBias: .03,
    );

    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(wallStart, height: .01),
        _cameraPoint(wallEnd, height: .01),
        _cameraPoint(shadowEnd, height: .01),
        _cameraPoint(shadowStart, height: .01),
      ],
      color: const Color(0x553D4547),
      opacity: opacity,
      depthBias: .025,
    );

    if (drawCornice) {
      _addFacadeSolid(
        items,
        <_CameraPoint>[
          _cameraPoint(corniceStart, height: facadeCorniceBottomMeters),
          _cameraPoint(corniceEnd, height: facadeCorniceBottomMeters),
          _cameraPoint(corniceEnd, height: facadeCorniceTopMeters),
          _cameraPoint(corniceStart, height: facadeCorniceTopMeters),
        ],
        color: frontColor,
        opacity: opacity,
        depthBias: -.018,
      );
      _addFacadeSolid(
        items,
        <_CameraPoint>[
          _cameraPoint(wallStart, height: facadeCorniceBottomMeters),
          _cameraPoint(wallEnd, height: facadeCorniceBottomMeters),
          _cameraPoint(corniceEnd, height: facadeCorniceBottomMeters),
          _cameraPoint(corniceStart, height: facadeCorniceBottomMeters),
        ],
        color: sideColor,
        opacity: opacity,
        depthBias: -.02,
      );
      _addFacadeSolid(
        items,
        <_CameraPoint>[
          _cameraPoint(wallStart, height: facadeCorniceTopMeters),
          _cameraPoint(wallEnd, height: facadeCorniceTopMeters),
          _cameraPoint(corniceEnd, height: facadeCorniceTopMeters),
          _cameraPoint(corniceStart, height: facadeCorniceTopMeters),
        ],
        color: capColor,
        opacity: opacity,
        depthBias: -.019,
      );
    }

    if (featureImage != null) {
      switch (tileKind) {
        case TempleRunWallTileKind.window:
        case TempleRunWallTileKind.door:
          _addFacadeRelief(
            items: items,
            tileKind: tileKind,
            featureImage: featureImage,
            leg: leg,
            wallSpan: wallSpan,
            side: side,
            wallOffset: wallOffset,
            tileLength: tileLength,
            tileArcStart: tileArcStart,
            tileArcEnd: tileArcEnd,
            tileOrigin: tileOrigin,
            opacity: opacity,
            tileDepth: tileDepth,
            sideColor: sideColor,
            capColor: capColor,
          );
        case TempleRunWallTileKind.mural:
          _addFlatFacadeFeature(
            items: items,
            featureImage: featureImage,
            leg: leg,
            wallSpan: wallSpan,
            side: side,
            wallOffset: wallOffset,
            tileLength: tileLength,
            tileArcStart: tileArcStart,
            tileArcEnd: tileArcEnd,
            tileOrigin: tileOrigin,
            opacity: opacity,
            tileDepth: tileDepth,
          );
        case TempleRunWallTileKind.plasterA:
        case TempleRunWallTileKind.plasterB:
        case TempleRunWallTileKind.houseBrick:
        case TempleRunWallTileKind.houseSage:
        case TempleRunWallTileKind.houseGarden:
        case TempleRunWallTileKind.shopfront:
        case TempleRunWallTileKind.schoolfront:
        case TempleRunWallTileKind.constructionfront:
          break;
      }
    }
  }

  void _addFacadeMassModule({
    required List<_TempleRunRenderItem> items,
    required ui.Image massImage,
    required ui.Image plasterImage,
    required _TempleRunWallMassSpec spec,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double wallOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
  }) {
    if (opacity <= .01 || tileArcEnd <= tileArcStart) return;
    final planeRect = Rect.fromLTRB(
      spec.source.left * massImage.width,
      spec.source.top * massImage.height,
      spec.source.right * massImage.width,
      spec.source.bottom * massImage.height,
    );
    final planeOffset = wallOffset - spec.depth;
    var bodyRects = <Rect>[planeRect];
    for (final volume in spec.volumes) {
      final volumeRect = Rect.fromLTRB(
        volume.source.left * massImage.width,
        volume.source.top * massImage.height,
        volume.source.right * massImage.width,
        volume.source.bottom * massImage.height,
      );
      final nextRects = <Rect>[];
      for (final bodyRect in bodyRects) {
        final cut = Rect.fromLTRB(
          math.max(bodyRect.left, volumeRect.left),
          math.max(bodyRect.top, volumeRect.top),
          math.min(bodyRect.right, volumeRect.right),
          math.min(bodyRect.bottom, volumeRect.bottom),
        );
        if (cut.right <= cut.left || cut.bottom <= cut.top) {
          nextRects.add(bodyRect);
          continue;
        }
        if (bodyRect.top < cut.top) {
          nextRects.add(
            Rect.fromLTRB(bodyRect.left, bodyRect.top, bodyRect.right, cut.top),
          );
        }
        if (cut.bottom < bodyRect.bottom) {
          nextRects.add(
            Rect.fromLTRB(
              bodyRect.left,
              cut.bottom,
              bodyRect.right,
              bodyRect.bottom,
            ),
          );
        }
        if (bodyRect.left < cut.left) {
          nextRects.add(
            Rect.fromLTRB(bodyRect.left, cut.top, cut.left, cut.bottom),
          );
        }
        if (cut.right < bodyRect.right) {
          nextRects.add(
            Rect.fromLTRB(cut.right, cut.top, bodyRect.right, cut.bottom),
          );
        }
      }
      bodyRects = nextRects;
    }
    for (final bodyRect in bodyRects) {
      _addFacadeTexturedPlaneBands(
        items: items,
        materialImage: massImage,
        planeWidth: massImage.width.toDouble(),
        planeHeight: massImage.height.toDouble(),
        planeRect: bodyRect,
        materialRect: bodyRect,
        leg: leg,
        wallSpan: wallSpan,
        side: side,
        planeOffset: planeOffset,
        tileLength: tileLength,
        tileArcStart: tileArcStart,
        tileArcEnd: tileArcEnd,
        tileOrigin: tileOrigin,
        opacity: opacity,
        cullBackFace: true,
      );
    }
    _addFacadeTexturedReturnFaces(
      items: items,
      materialImage: plasterImage,
      planeWidth: massImage.width.toDouble(),
      planeHeight: massImage.height.toDouble(),
      planeRect: planeRect,
      leg: leg,
      wallSpan: wallSpan,
      side: side,
      backOffset: wallOffset,
      frontOffset: planeOffset,
      tileLength: tileLength,
      tileArcStart: tileArcStart,
      tileArcEnd: tileArcEnd,
      tileOrigin: tileOrigin,
      opacity: opacity,
      cullBackFace: true,
    );
    _addFacadeMassTopCap(
      items: items,
      planeRect: planeRect,
      planeWidth: massImage.width.toDouble(),
      planeHeight: massImage.height.toDouble(),
      leg: leg,
      wallSpan: wallSpan,
      side: side,
      backOffset: wallOffset,
      frontOffset: planeOffset,
      tileLength: tileLength,
      tileArcStart: tileArcStart,
      tileArcEnd: tileArcEnd,
      tileOrigin: tileOrigin,
      opacity: opacity,
    );
    for (final volume in spec.volumes) {
      final volumeRect = Rect.fromLTRB(
        volume.source.left * massImage.width,
        volume.source.top * massImage.height,
        volume.source.right * massImage.width,
        volume.source.bottom * massImage.height,
      );
      _addFacadeTexturedPlaneBands(
        items: items,
        materialImage: plasterImage,
        planeWidth: massImage.width.toDouble(),
        planeHeight: massImage.height.toDouble(),
        planeRect: volumeRect,
        materialRect: Rect.fromLTWH(0, 0, volumeRect.width, volumeRect.height),
        leg: leg,
        wallSpan: wallSpan,
        side: side,
        planeOffset: planeOffset,
        tileLength: tileLength,
        tileArcStart: tileArcStart,
        tileArcEnd: tileArcEnd,
        tileOrigin: tileOrigin,
        opacity: opacity,
        cullBackFace: false,
        sortBias: -.0005,
      );
      _addFacadeVolume(
        items: items,
        materialImage: volume.usePlasterFront ? plasterImage : massImage,
        sideImage: plasterImage,
        volume: volume,
        planeRect: volumeRect,
        backOffset: planeOffset,
        frontOffset: wallOffset - volume.frontDepth,
        leg: leg,
        wallSpan: wallSpan,
        side: side,
        tileLength: tileLength,
        tileArcStart: tileArcStart,
        tileArcEnd: tileArcEnd,
        tileOrigin: tileOrigin,
        opacity: opacity,
      );
    }
  }

  void _addFacadeMassTopCap({
    required List<_TempleRunRenderItem> items,
    required Rect planeRect,
    required double planeWidth,
    required double planeHeight,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double backOffset,
    required double frontOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
  }) {
    if (opacity <= .01 || planeRect.isEmpty || backOffset <= frontOffset) {
      return;
    }
    final planeStartArc = tileOrigin + planeRect.left / planeWidth * tileLength;
    final planeEndArc = tileOrigin + planeRect.right / planeWidth * tileLength;
    final arcStart = math.max(tileArcStart, planeStartArc);
    final arcEnd = math.min(tileArcEnd, planeEndArc);
    if (arcEnd <= arcStart + .001) return;
    final routeStart = wallSpan.wallStart + arcStart - wallSpan.wallArcStart;
    final routeEnd = wallSpan.wallStart + arcEnd - wallSpan.wallArcStart;
    final top = facadeHeightMeters * (1 - planeRect.top / planeHeight);
    Offset point(double route, double offset) =>
        leg.centerAt(route) + _right(leg.heading) * side * offset;
    for (
      var bandStart = routeStart;
      bandStart < routeEnd - .001;
      bandStart = math.min(routeEnd, bandStart + 1.0)
    ) {
      final bandEnd = math.min(routeEnd, bandStart + 1.0);
      final polygon = <_CameraPoint>[
        _cameraPoint(point(bandStart, backOffset), height: top),
        _cameraPoint(point(bandEnd, backOffset), height: top),
        _cameraPoint(point(bandEnd, frontOffset), height: top),
        _cameraPoint(point(bandStart, frontOffset), height: top),
      ];
      if (side > 0) {
        final first = polygon.first;
        final second = polygon[1];
        final third = polygon[2];
        final fourth = polygon[3];
        polygon
          ..clear()
          ..addAll(<_CameraPoint>[first, fourth, third, second]);
      }
      _addFacadeSolid(
        items,
        polygon,
        color: const Color(0xFFD8CCBC),
        opacity: opacity,
        depthBias: 0,
        cullBackFace: true,
      );
    }
  }

  void _addFacadeTexturedPlaneBands({
    required List<_TempleRunRenderItem> items,
    required ui.Image materialImage,
    required double planeWidth,
    required double planeHeight,
    required Rect planeRect,
    required Rect materialRect,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double planeOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
    required bool cullBackFace,
    double sortBias = 0,
    Offset? spanStartPoint,
    Offset? spanEndPoint,
  }) {
    if (opacity <= .01 || planeRect.isEmpty) return;
    final planeStartArc = tileOrigin + planeRect.left / planeWidth * tileLength;
    final planeEndArc = tileOrigin + planeRect.right / planeWidth * tileLength;
    final arcStart = math.max(tileArcStart, planeStartArc);
    final arcEnd = math.min(tileArcEnd, planeEndArc);
    if (arcEnd <= arcStart + .001) return;
    final totalArc = planeEndArc - planeStartArc;
    final totalMaterialWidth = materialRect.width;
    final totalPlaneWidth = planeRect.width;
    for (var bandStart = arcStart; bandStart < arcEnd - .001;) {
      final bandEnd = math.min(arcEnd, bandStart + 1.0);
      final startRatio = (bandStart - planeStartArc) / totalArc;
      final endRatio = (bandEnd - planeStartArc) / totalArc;
      final initialRouteStart =
          wallSpan.wallStart + bandStart - wallSpan.wallArcStart;
      final initialRouteEnd =
          wallSpan.wallStart + bandEnd - wallSpan.wallArcStart;
      var routeStart = initialRouteStart;
      var routeEnd = initialRouteEnd;
      Offset point(double route, double offset) {
        if (spanStartPoint != null &&
            (route - wallSpan.wallStart).abs() < .001) {
          return spanStartPoint;
        }
        if (spanEndPoint != null && (route - wallSpan.wallEnd).abs() < .001) {
          return spanEndPoint;
        }
        return leg.centerAt(route) + _right(leg.heading) * side * offset;
      }

      final clipped = _clipReliefRouteToDepth(
        routeStart: routeStart,
        routeEnd: routeEnd,
        startDepth: _cameraPoint(point(routeStart, planeOffset)).depth,
        endDepth: _cameraPoint(point(routeEnd, planeOffset)).depth,
      );
      if (clipped != null) {
        routeStart = clipped.start;
        routeEnd = clipped.end;
        final clippedStartRatio =
            (routeStart - initialRouteStart) /
            (initialRouteEnd - initialRouteStart);
        final clippedEndRatio =
            (routeEnd - initialRouteStart) /
            (initialRouteEnd - initialRouteStart);
        final sourceLeft =
            materialRect.left +
            totalMaterialWidth *
                (startRatio + (endRatio - startRatio) * clippedStartRatio);
        final sourceRight =
            materialRect.left +
            totalMaterialWidth *
                (startRatio + (endRatio - startRatio) * clippedEndRatio);
        final destinationLeft =
            planeRect.left +
            totalPlaneWidth *
                (startRatio + (endRatio - startRatio) * clippedStartRatio);
        final destinationRight =
            planeRect.left +
            totalPlaneWidth *
                (startRatio + (endRatio - startRatio) * clippedEndRatio);
        final top = facadeHeightMeters * (1 - planeRect.top / planeHeight);
        final bottom =
            facadeHeightMeters * (1 - planeRect.bottom / planeHeight);
        final polygon = <_CameraPoint>[
          _cameraPoint(point(routeStart, planeOffset), height: bottom),
          _cameraPoint(point(routeEnd, planeOffset), height: bottom),
          _cameraPoint(point(routeEnd, planeOffset), height: top),
          _cameraPoint(point(routeStart, planeOffset), height: top),
        ];
        if (side < 0) {
          final first = polygon.first;
          polygon
            ..clear()
            ..addAll(<_CameraPoint>[
              first,
              // Reverse the winding for the left wall so its outward normal
              // faces the camera instead of being culled as a back face.
              _cameraPoint(point(routeStart, planeOffset), height: top),
              _cameraPoint(point(routeEnd, planeOffset), height: top),
              _cameraPoint(point(routeEnd, planeOffset), height: bottom),
            ]);
        }
        final clippedPolygon = _clipCameraPolygon(polygon);
        if (clippedPolygon.length >= 3 &&
            (!cullBackFace || _isCameraFaceVisible(clippedPolygon))) {
          _recordFacadePolygon(clippedPolygon);
          final projected = clippedPolygon
              .map(_projectCameraPoint)
              .toList(growable: false);
          final depth =
              projected.fold<double>(0, (sum, point) => sum + point.depth) /
              projected.length;
          final tileRouteOrigin =
              wallSpan.wallStart + tileOrigin - wallSpan.wallArcStart;
          final matrix = _wallHomography(
            leg: leg,
            cameraOrigin: _cameraPoint(point(tileRouteOrigin, planeOffset)),
            wallLength: tileLength,
            sourceWidth: planeWidth,
            sourceHeight: planeHeight,
            height: facadeHeightMeters,
          );
          items.add(
            _TempleRunRenderItem(
              depth: depth + sortBias,
              draw: (canvas) => _drawHomographicWallTile(
                canvas,
                materialImage,
                Rect.fromLTRB(
                  sourceLeft,
                  materialRect.top,
                  sourceRight,
                  materialRect.bottom,
                ),
                matrix,
                opacity,
                destinationRect: Rect.fromLTRB(
                  destinationLeft,
                  planeRect.top,
                  destinationRight,
                  planeRect.bottom,
                ),
              ),
            ),
          );
        }
      }
      if (bandEnd <= bandStart + .001) break;
      bandStart = bandEnd;
    }
  }

  void _addFacadeTexturedReturnFaces({
    required List<_TempleRunRenderItem> items,
    required ui.Image materialImage,
    required double planeWidth,
    required double planeHeight,
    required Rect planeRect,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double backOffset,
    required double frontOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
    required bool cullBackFace,
    Color? solidColor,
  }) {
    if (opacity <= .01 || planeRect.isEmpty || backOffset <= frontOffset) {
      return;
    }
    final planeStartArc = tileOrigin + planeRect.left / planeWidth * tileLength;
    final planeEndArc = tileOrigin + planeRect.right / planeWidth * tileLength;
    final arcStart = math.max(tileArcStart, planeStartArc);
    final arcEnd = math.min(tileArcEnd, planeEndArc);
    if (arcEnd <= arcStart + .001) return;
    final routeStart = wallSpan.wallStart + arcStart - wallSpan.wallArcStart;
    final routeEnd = wallSpan.wallStart + arcEnd - wallSpan.wallArcStart;
    final top = facadeHeightMeters * (1 - planeRect.top / planeHeight);
    final bottom = facadeHeightMeters * (1 - planeRect.bottom / planeHeight);
    // Keep source texels at the authored world scale on returns. A tiny
    // four-pixel edge strip stretched over a .4-.8m side reads as a blurred
    // copy of the entire facade; a meter-matched strip keeps it quiet.
    final returnLength = backOffset - frontOffset;
    final stripWidth = math.max(
      4.0,
      math.min(planeRect.width, returnLength / tileLength * planeWidth),
    );
    for (final atStart in [true, false]) {
      final route = atStart ? routeStart : routeEnd;
      final sourceRect = atStart
          ? Rect.fromLTRB(
              planeRect.left,
              planeRect.top,
              planeRect.left + stripWidth,
              planeRect.bottom,
            )
          : Rect.fromLTRB(
              planeRect.right - stripWidth,
              planeRect.top,
              planeRect.right,
              planeRect.bottom,
            );
      final polygon = <_CameraPoint>[
        _cameraPoint(
          leg.centerAt(route) + _right(leg.heading) * side * backOffset,
          height: bottom,
        ),
        _cameraPoint(
          leg.centerAt(route) + _right(leg.heading) * side * frontOffset,
          height: bottom,
        ),
        _cameraPoint(
          leg.centerAt(route) + _right(leg.heading) * side * frontOffset,
          height: top,
        ),
        _cameraPoint(
          leg.centerAt(route) + _right(leg.heading) * side * backOffset,
          height: top,
        ),
      ];
      final preserveWinding = (side > 0 && atStart) || (side < 0 && !atStart);
      if (!preserveWinding) {
        final first = polygon.first;
        final second = polygon[1];
        final third = polygon[2];
        final fourth = polygon[3];
        polygon
          ..clear()
          ..addAll(<_CameraPoint>[first, fourth, third, second]);
      }
      if (solidColor != null) {
        _addFacadeSolid(
          items,
          polygon,
          color: solidColor,
          opacity: opacity,
          depthBias: 0,
          cullBackFace: cullBackFace,
        );
        continue;
      }
      final clipped = _clipCameraPolygon(polygon);
      if (clipped.length < 3 ||
          (cullBackFace && !_isCameraFaceVisible(clipped))) {
        continue;
      }
      _recordFacadePolygon(clipped);
      final projected = clipped
          .map(_projectCameraPoint)
          .toList(growable: false);
      final depth =
          projected.fold<double>(0, (sum, point) => sum + point.depth) /
          projected.length;
      final returnHeading = leg.heading - side * math.pi / 2;
      final returnLength = backOffset - frontOffset;
      final matrix = _wallHomography(
        leg: _FacadeRouteLeg(
          start: 0,
          end: returnLength,
          origin: Offset.zero,
          heading: returnHeading,
        ),
        cameraOrigin: _cameraPoint(
          leg.centerAt(route) + _right(leg.heading) * side * backOffset,
        ),
        wallLength: returnLength,
        sourceWidth: stripWidth,
        sourceHeight: planeHeight,
        height: facadeHeightMeters,
      );
      final projectedPath = Path()
        ..moveTo(projected.first.point.dx, projected.first.point.dy);
      for (final point in projected.skip(1)) {
        projectedPath.lineTo(point.point.dx, point.point.dy);
      }
      projectedPath.close();
      final destinationRect = Rect.fromLTRB(
        0,
        planeRect.top,
        stripWidth,
        planeRect.bottom,
      );
      items.add(
        _TempleRunRenderItem(
          depth: depth,
          draw: (canvas) {
            canvas.save();
            canvas.clipPath(projectedPath);
            _drawHomographicWallTile(
              canvas,
              materialImage,
              sourceRect,
              matrix,
              opacity,
              destinationRect: destinationRect,
            );
            canvas.restore();
          },
        ),
      );
    }
  }

  void _addFacadeVolume({
    required List<_TempleRunRenderItem> items,
    required ui.Image materialImage,
    required ui.Image sideImage,
    required _TempleRunWallVolumeSpec volume,
    required Rect planeRect,
    required double backOffset,
    required double frontOffset,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
  }) {
    if (opacity <= .01 || planeRect.isEmpty || backOffset <= frontOffset) {
      return;
    }

    // The front is the authored feature crop on a real, roadward plane. The
    // crop is deliberately bounded to the feature; the full facade image is
    // never copied onto this volume.
    _addFacadeTexturedPlaneBands(
      items: items,
      materialImage: materialImage,
      planeWidth: materialImage.width.toDouble(),
      planeHeight: materialImage.height.toDouble(),
      planeRect: planeRect,
      materialRect: planeRect,
      leg: leg,
      wallSpan: wallSpan,
      side: side,
      planeOffset: frontOffset,
      tileLength: tileLength,
      tileArcStart: tileArcStart,
      tileArcEnd: tileArcEnd,
      tileOrigin: tileOrigin,
      opacity: opacity,
      cullBackFace: true,
      sortBias: -.0008,
    );

    // Returns are independently clipped and sorted by their actual camera
    // depth. This is what makes the projection read as a building edge at a
    // turn instead of as a second flat sticker.
    _addFacadeTexturedReturnFaces(
      items: items,
      materialImage: sideImage,
      planeWidth: materialImage.width.toDouble(),
      planeHeight: materialImage.height.toDouble(),
      planeRect: planeRect,
      leg: leg,
      wallSpan: wallSpan,
      side: side,
      backOffset: backOffset,
      frontOffset: frontOffset,
      tileLength: tileLength,
      tileArcStart: tileArcStart,
      tileArcEnd: tileArcEnd,
      tileOrigin: tileOrigin,
      opacity: opacity,
      cullBackFace: true,
      solidColor: volume.sideColor,
    );

    final planeStartArc =
        tileOrigin + planeRect.left / materialImage.width * tileLength;
    final planeEndArc =
        tileOrigin + planeRect.right / materialImage.width * tileLength;
    final arcStart = math.max(tileArcStart, planeStartArc);
    final arcEnd = math.min(tileArcEnd, planeEndArc);
    if (arcEnd <= arcStart + .001) return;
    final routeStart = wallSpan.wallStart + arcStart - wallSpan.wallArcStart;
    final routeEnd = wallSpan.wallStart + arcEnd - wallSpan.wallArcStart;
    Offset point(double route, double offset) =>
        leg.centerAt(route) + _right(leg.heading) * side * offset;
    final top = facadeHeightMeters * (1 - planeRect.top / materialImage.height);
    void addHorizontalBand({
      required double bandHeight,
      required Color color,
      required double bandOpacity,
      required double depthBias,
      required bool reverseWinding,
    }) {
      for (
        var bandStart = routeStart;
        bandStart < routeEnd - .001;
        bandStart = math.min(routeEnd, bandStart + 1.0)
      ) {
        final bandEnd = math.min(routeEnd, bandStart + 1.0);
        final polygon = <_CameraPoint>[
          _cameraPoint(point(bandStart, backOffset), height: bandHeight),
          _cameraPoint(point(bandEnd, backOffset), height: bandHeight),
          _cameraPoint(point(bandEnd, frontOffset), height: bandHeight),
          _cameraPoint(point(bandStart, frontOffset), height: bandHeight),
        ];
        if (reverseWinding) {
          final first = polygon.first;
          final second = polygon[1];
          final third = polygon[2];
          final fourth = polygon[3];
          polygon
            ..clear()
            ..addAll(<_CameraPoint>[first, fourth, third, second]);
        }
        _addFacadeSolid(
          items,
          polygon,
          color: color,
          opacity: bandOpacity,
          depthBias: depthBias,
          cullBackFace: true,
        );
      }
    }

    addHorizontalBand(
      bandHeight: top,
      color: volume.capColor,
      bandOpacity: opacity,
      depthBias: 0,
      reverseWinding: side > 0,
    );

    // A narrow dark underside keeps the volume grounded at shallow viewing
    // angles without adding a new prop or changing gameplay geometry.
    addHorizontalBand(
      bandHeight: math.max(
        .02,
        facadeHeightMeters * (1 - planeRect.bottom / materialImage.height),
      ),
      color: volume.sideColor,
      bandOpacity: opacity * .72,
      depthBias: .001,
      reverseWinding: side < 0,
    );
  }

  void _addFacadeRelief({
    required List<_TempleRunRenderItem> items,
    required TempleRunWallTileKind tileKind,
    required ui.Image featureImage,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double wallOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
    required double tileDepth,
    required Color sideColor,
    required Color capColor,
  }) {
    final source = wallFeatureSourceRectForTesting(
      tileKind,
      sourceWidth: featureImage.width.toDouble(),
      sourceHeight: featureImage.height.toDouble(),
    );
    _addBoundedFacadeRelief(
      items: items,
      featureImage: featureImage,
      source: source,
      leg: leg,
      wallSpan: wallSpan,
      side: side,
      wallOffset: wallOffset,
      tileLength: tileLength,
      tileArcStart: tileArcStart,
      tileArcEnd: tileArcEnd,
      tileOrigin: tileOrigin,
      opacity: opacity,
      tileDepth: tileDepth,
      sideColor: sideColor,
      capColor: capColor,
      featureDepth: tileKind == TempleRunWallTileKind.window ? .10 : .05,
      capDepth: tileKind == TempleRunWallTileKind.window ? .04 : .05,
      sillDepth: tileKind == TempleRunWallTileKind.window ? .14 : .04,
    );
  }

  void _addBoundedFacadeRelief({
    required List<_TempleRunRenderItem> items,
    required ui.Image featureImage,
    required Rect source,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double wallOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
    required double tileDepth,
    required Color sideColor,
    required Color capColor,
    required double featureDepth,
    required double capDepth,
    required double sillDepth,
  }) {
    if (opacity <= .01 || tileArcEnd <= tileArcStart) return;
    if (source.isEmpty) return;

    final featureStartArc =
        tileOrigin + source.left / featureImage.width * tileLength;
    final featureEndArc =
        tileOrigin + source.right / featureImage.width * tileLength;
    final arcStart = math.max(tileArcStart, featureStartArc);
    final arcEnd = math.min(tileArcEnd, featureEndArc);
    if (arcEnd <= arcStart + .001) return;
    final cropLeft =
        source.left +
        (arcStart - featureStartArc) / tileLength * featureImage.width;
    final cropRight =
        source.left +
        (arcEnd - featureStartArc) / tileLength * featureImage.width;
    final initialRouteStart =
        wallSpan.wallStart + arcStart - wallSpan.wallArcStart;
    final initialRouteEnd = wallSpan.wallStart + arcEnd - wallSpan.wallArcStart;
    var routeStart = initialRouteStart;
    var routeEnd = initialRouteEnd;
    final top = facadeHeightMeters * (1 - source.top / featureImage.height);
    final bottom =
        facadeHeightMeters * (1 - source.bottom / featureImage.height);
    Offset point(double routeDistance, double offset) =>
        leg.centerAt(routeDistance) + _right(leg.heading) * side * offset;
    final initialFrontStart = point(routeStart, wallOffset - featureDepth);
    final initialFrontEnd = point(routeEnd, wallOffset - featureDepth);
    final clipped = _clipReliefRouteToDepth(
      routeStart: routeStart,
      routeEnd: routeEnd,
      startDepth: _cameraPoint(initialFrontStart).depth,
      endDepth: _cameraPoint(initialFrontEnd).depth,
    );
    if (clipped == null) return;
    routeStart = clipped.start;
    routeEnd = clipped.end;
    final clippedStartRatio =
        (routeStart - initialRouteStart) /
        (initialRouteEnd - initialRouteStart);
    final clippedEndRatio =
        (routeEnd - initialRouteStart) / (initialRouteEnd - initialRouteStart);
    final clippedCropLeft =
        cropLeft + (cropRight - cropLeft) * clippedStartRatio;
    final clippedCropRight =
        cropLeft + (cropRight - cropLeft) * clippedEndRatio;
    final backStart = point(routeStart, wallOffset);
    final backEnd = point(routeEnd, wallOffset);
    final frontStart = point(routeStart, wallOffset - featureDepth);
    final frontEnd = point(routeEnd, wallOffset - featureDepth);
    final sourceRect = Rect.fromLTRB(
      clippedCropLeft,
      source.top,
      clippedCropRight,
      source.bottom,
    );
    final tileRouteOrigin =
        wallSpan.wallStart + tileOrigin - wallSpan.wallArcStart;
    final frontMatrix = _wallHomography(
      leg: leg,
      cameraOrigin: _cameraPoint(
        point(tileRouteOrigin, wallOffset - featureDepth),
      ),
      wallLength: tileLength,
      sourceWidth: featureImage.width.toDouble(),
      sourceHeight: featureImage.height.toDouble(),
      height: facadeHeightMeters,
    );
    items.add(
      _TempleRunRenderItem(
        // The opaque feature plate must follow its parent plaster tile even
        // when the visible crop shifts the feature's own midpoint. Keep the
        // actual tile depth for occlusion, then use a small ordered bias for
        // the relief face and its trim.
        depth: tileDepth - .010,
        draw: (canvas) => _drawHomographicWallTile(
          canvas,
          featureImage,
          sourceRect,
          frontMatrix,
          opacity,
        ),
      ),
    );
    final dark = sideColor.withValues(alpha: .92 * opacity);
    final cap = capColor.withValues(alpha: opacity);
    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(backStart, height: bottom),
        _cameraPoint(frontStart, height: bottom),
        _cameraPoint(frontStart, height: top),
        _cameraPoint(backStart, height: top),
      ],
      color: dark,
      opacity: 1,
      depthBias: -.045,
      depthOverride: tileDepth - .015,
    );
    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(frontEnd, height: bottom),
        _cameraPoint(backEnd, height: bottom),
        _cameraPoint(backEnd, height: top),
        _cameraPoint(frontEnd, height: top),
      ],
      color: dark,
      opacity: 1,
      depthBias: -.046,
      depthOverride: tileDepth - .016,
    );
    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(frontStart, height: top),
        _cameraPoint(frontEnd, height: top),
        _cameraPoint(backEnd, height: top + capDepth),
        _cameraPoint(backStart, height: top + capDepth),
      ],
      color: cap,
      opacity: 1,
      depthBias: -.047,
      depthOverride: tileDepth - .017,
    );
    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(frontStart, height: math.max(.02, bottom - sillDepth)),
        _cameraPoint(frontEnd, height: math.max(.02, bottom - sillDepth)),
        _cameraPoint(backEnd, height: bottom),
        _cameraPoint(backStart, height: bottom),
      ],
      color: cap,
      opacity: 1,
      depthBias: -.048,
      depthOverride: tileDepth - .018,
    );
    _addFacadeSolid(
      items,
      <_CameraPoint>[
        _cameraPoint(frontStart, height: math.max(.02, bottom - .02)),
        _cameraPoint(frontEnd, height: math.max(.02, bottom - .02)),
        _cameraPoint(frontEnd, height: math.max(.02, bottom - .07)),
        _cameraPoint(frontStart, height: math.max(.02, bottom - .07)),
      ],
      color: const Color(0x993D4547),
      opacity: opacity,
      depthBias: -.049,
      depthOverride: tileDepth - .019,
    );
  }

  void _addFlatFacadeFeature({
    required List<_TempleRunRenderItem> items,
    required ui.Image featureImage,
    required _FacadeRouteLeg leg,
    required TempleRunFacadeWallSpan wallSpan,
    required double side,
    required double wallOffset,
    required double tileLength,
    required double tileArcStart,
    required double tileArcEnd,
    required double tileOrigin,
    required double opacity,
    required double tileDepth,
  }) {
    if (opacity <= .01 || tileArcEnd <= tileArcStart) return;
    final source = wallFeatureSourceRectForTesting(
      TempleRunWallTileKind.mural,
      sourceWidth: featureImage.width.toDouble(),
      sourceHeight: featureImage.height.toDouble(),
    );
    if (source.isEmpty) return;
    final featureStartArc =
        tileOrigin + source.left / featureImage.width * tileLength;
    final featureEndArc =
        tileOrigin + source.right / featureImage.width * tileLength;
    final arcStart = math.max(tileArcStart, featureStartArc);
    final arcEnd = math.min(tileArcEnd, featureEndArc);
    if (arcEnd <= arcStart + .001) return;
    final cropLeft =
        source.left +
        (arcStart - featureStartArc) / tileLength * featureImage.width;
    final cropRight =
        source.left +
        (arcEnd - featureStartArc) / tileLength * featureImage.width;
    final initialRouteStart =
        wallSpan.wallStart + arcStart - wallSpan.wallArcStart;
    final initialRouteEnd = wallSpan.wallStart + arcEnd - wallSpan.wallArcStart;
    Offset point(double routeDistance) =>
        leg.centerAt(routeDistance) + _right(leg.heading) * side * wallOffset;
    var routeStart = initialRouteStart;
    var routeEnd = initialRouteEnd;
    final clipped = _clipReliefRouteToDepth(
      routeStart: routeStart,
      routeEnd: routeEnd,
      startDepth: _cameraPoint(point(routeStart)).depth,
      endDepth: _cameraPoint(point(routeEnd)).depth,
    );
    if (clipped == null) return;
    routeStart = clipped.start;
    routeEnd = clipped.end;
    final clippedStartRatio =
        (routeStart - initialRouteStart) /
        (initialRouteEnd - initialRouteStart);
    final clippedEndRatio =
        (routeEnd - initialRouteStart) / (initialRouteEnd - initialRouteStart);
    final clippedCropLeft =
        cropLeft + (cropRight - cropLeft) * clippedStartRatio;
    final clippedCropRight =
        cropLeft + (cropRight - cropLeft) * clippedEndRatio;
    final tileRouteOrigin =
        wallSpan.wallStart + tileOrigin - wallSpan.wallArcStart;
    final matrix = _wallHomography(
      leg: leg,
      cameraOrigin: _cameraPoint(point(tileRouteOrigin)),
      wallLength: tileLength,
      sourceWidth: featureImage.width.toDouble(),
      sourceHeight: featureImage.height.toDouble(),
      height: facadeHeightMeters,
    );
    final sourceRect = Rect.fromLTRB(
      clippedCropLeft,
      source.top,
      clippedCropRight,
      source.bottom,
    );
    items.add(
      _TempleRunRenderItem(
        // Keep the opaque mural crop attached to the parent tile's sort
        // group so its slightly off-centre authored bounds cannot be painted
        // underneath the plaster base.
        depth: tileDepth - .010,
        draw: (canvas) => _drawHomographicWallTile(
          canvas,
          featureImage,
          sourceRect,
          matrix,
          opacity,
        ),
      ),
    );
  }

  void _recordFacadePolygon(List<_CameraPoint> polygon) {
    final collector = _facadeOccluderCollector;
    if (collector == null) return;
    final clipped = _clipCameraPolygon(polygon);
    if (clipped.length >= 3) {
      collector.add(List<_CameraPoint>.unmodifiable(clipped));
    }
  }

  List<_ProjectedFacadeOccluder> _projectedFacadeOccludersFromPolygons(
    List<List<_CameraPoint>> polygons,
  ) {
    final result = <_ProjectedFacadeOccluder>[];
    for (final polygon in polygons) {
      final clipped = _clipCameraPolygon(polygon);
      if (clipped.length < 3) continue;
      final projected = clipped
          .map(_projectCameraPoint)
          .toList(growable: false);
      final path = Path()
        ..moveTo(projected.first.point.dx, projected.first.point.dy);
      for (final point in projected.skip(1)) {
        path.lineTo(point.point.dx, point.point.dy);
      }
      path.close();
      final bounds = path.getBounds();
      if (bounds.isEmpty || !bounds.left.isFinite || !bounds.top.isFinite) {
        continue;
      }
      final nearDepth = clipped.fold<double>(
        double.infinity,
        (minimum, point) => math.min(minimum, point.depth),
      );
      result.add(
        _ProjectedFacadeOccluder(
          path: path,
          bounds: bounds,
          nearDepth: nearDepth,
          cameraPolygon: clipped,
        ),
      );
    }
    return result;
  }

  void _addFacadeSolid(
    List<_TempleRunRenderItem> items,
    List<_CameraPoint> polygon, {
    required Color color,
    required double opacity,
    required double depthBias,
    double? depthOverride,
    bool cullBackFace = false,
  }) {
    if (opacity <= .01) return;
    final clipped = _clipCameraPolygon(polygon);
    if (clipped.length < 3) return;
    if (cullBackFace && !_isCameraFaceVisible(clipped)) return;
    _recordFacadePolygon(clipped);
    final projected = clipped.map(_projectCameraPoint).toList(growable: false);
    final path = Path()
      ..moveTo(projected.first.point.dx, projected.first.point.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.point.dx, point.point.dy);
    }
    path.close();
    final depth =
        depthOverride ??
        (projected.fold<double>(0, (sum, point) => sum + point.depth) /
                projected.length +
            depthBias);
    final paintColor = color.withValues(alpha: color.a * opacity);
    items.add(
      _TempleRunRenderItem(
        depth: depth,
        draw: (canvas) => canvas.drawPath(
          path,
          Paint()
            ..isAntiAlias = false
            ..color = paintColor,
        ),
      ),
    );
  }

  bool _isCameraFaceVisible(List<_CameraPoint> polygon) {
    if (polygon.length < 3) return false;
    final first = polygon.first;
    final second = polygon[1];
    final third = polygon[2];
    final ax = second.lateral - first.lateral;
    final ay = second.height - first.height;
    final az = second.depth - first.depth;
    final bx = third.lateral - first.lateral;
    final by = third.height - first.height;
    final bz = third.depth - first.depth;
    final nx = ay * bz - az * by;
    final ny = az * bx - ax * bz;
    final nz = ax * by - ay * bx;
    final center = polygon.fold<_CameraPoint>(
      const _CameraPoint(lateral: 0, depth: 0, height: 0),
      (sum, point) => _CameraPoint(
        lateral: sum.lateral + point.lateral,
        depth: sum.depth + point.depth,
        height: sum.height + point.height,
      ),
    );
    final count = polygon.length.toDouble();
    final toCameraX = -center.lateral / count;
    final toCameraY = _cameraHeightMeters - center.height / count;
    final toCameraZ = -center.depth / count;
    return nx * toCameraX + ny * toCameraY + nz * toCameraZ > .000001;
  }

  Float64List _wallHomography({
    required _FacadeRouteLeg leg,
    required _CameraPoint cameraOrigin,
    required double wallLength,
    required double sourceWidth,
    required double sourceHeight,
    required double height,
    double bottomHeight = 0,
  }) {
    return TempleRunFacadeHomography.build(
      viewport: Size(size.x, size.y),
      horizonY: _horizonY,
      cameraHeight: _cameraHeightMeters,
      focalLength: _focalLength,
      cameraTargetDepth: _cameraTargetDepth,
      cameraBackDistance: _cameraBackMeters,
      cameraHeading: _cameraHeading,
      cameraOriginLateral: cameraOrigin.lateral,
      cameraOriginDepth: cameraOrigin.depth,
      facadeHeading: leg.heading,
      wallLength: wallLength,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      wallHeight: height,
      bottomHeight: bottomHeight,
    );
  }

  ({double start, double end})? _visibleWallSourceU({
    required _CameraPoint cameraOrigin,
    required _FacadeRouteLeg leg,
    required double sourceWidth,
    required double wallLength,
  }) {
    final unitDepth =
        _dot(_forward(leg.heading), _forward(_cameraHeading)) *
        wallLength /
        sourceWidth;
    if (unitDepth.abs() < .000001) {
      if (cameraOrigin.depth < _nearClipMeters ||
          cameraOrigin.depth > _farClipMeters) {
        return null;
      }
      return (start: 0, end: sourceWidth);
    }
    final nearU = (_nearClipMeters - cameraOrigin.depth) / unitDepth;
    final farU = (_farClipMeters - cameraOrigin.depth) / unitDepth;
    final start = math.max(0.0, math.min(nearU, farU));
    final end = math.min(sourceWidth, math.max(nearU, farU));
    if (end <= start) return null;
    return (start: start, end: end);
  }

  ({double start, double end})? _clipReliefRouteToDepth({
    required double routeStart,
    required double routeEnd,
    required double startDepth,
    required double endDepth,
  }) {
    final depthDelta = endDepth - startDepth;
    if (depthDelta.abs() < .000001) {
      if (startDepth < _nearClipMeters || startDepth > _farClipMeters) {
        return null;
      }
      return (start: routeStart, end: routeEnd);
    }
    final nearT = (_nearClipMeters - startDepth) / depthDelta;
    final farT = (_farClipMeters - startDepth) / depthDelta;
    final startT = math.max(0.0, math.min(nearT, farT));
    final endT = math.min(1.0, math.max(nearT, farT));
    if (endT <= startT + .000001) return null;
    final routeDelta = routeEnd - routeStart;
    return (
      start: routeStart + routeDelta * startT,
      end: routeStart + routeDelta * endT,
    );
  }

  void _drawHomographicWallTile(
    Canvas canvas,
    ui.Image image,
    Rect sourceRect,
    Float64List transform,
    double opacity, {
    Rect? destinationRect,
  }) {
    canvas.save();
    canvas.transform(transform);
    canvas.drawImageRect(
      image,
      sourceRect,
      destinationRect ?? sourceRect,
      Paint()
        ..color = Color.fromARGB((opacity * 255).round(), 255, 255, 255)
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  double _wallWindowOpacity(
    double routeDistance,
    double windowStart,
    double windowEnd,
  ) {
    const fadeDistance = 12.0;
    final entering = ((routeDistance - windowStart) / fadeDistance).clamp(
      0.0,
      1.0,
    );
    final leaving = ((windowEnd - routeDistance) / fadeDistance).clamp(
      0.0,
      1.0,
    );
    return math.min(entering, leaving);
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  static double _asphaltTextureU(Offset world) =>
      world.dx * _asphaltPixelsPerMeter;

  static double _asphaltTextureV(Offset world) =>
      world.dy * _asphaltPixelsPerMeter;

  void _drawImageQuad(
    Canvas canvas,
    ui.Image image,
    List<Offset> points, {
    double sourceBottomPadding = 0,
    Rect? sourceRect,
  }) {
    if (points.length != 4) return;
    final adjustedPoints = sourceBottomPadding <= 0 || image.height == 0
        ? points
        : _bottomAnchoredQuad(points, image, sourceBottomPadding);
    final source =
        sourceRect ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    // Perspective interpolation across a tall quad can visibly bow the
    // facade's horizontal trims. Keep one draw call per longitudinal strip,
    // but subdivide its vertical axis so the source-V coordinate follows the
    // projected wall in short bands.
    const verticalBands = 8;
    final positions = <Offset>[];
    final textureCoordinates = <Offset>[];
    for (var band = 0; band <= verticalBands; band++) {
      final amount = band / verticalBands;
      positions
        ..add(Offset.lerp(adjustedPoints[0], adjustedPoints[3], amount)!)
        ..add(Offset.lerp(adjustedPoints[1], adjustedPoints[2], amount)!);
      final sourceY = source.top + source.height * amount;
      textureCoordinates
        ..add(Offset(source.left, sourceY))
        ..add(Offset(source.right, sourceY));
    }
    final indices = <int>[];
    for (var band = 0; band < verticalBands; band++) {
      final topLeft = band * 2;
      final topRight = topLeft + 1;
      final bottomLeft = topLeft + 2;
      final bottomRight = topLeft + 3;
      indices.addAll(<int>[
        topLeft,
        topRight,
        bottomLeft,
        topRight,
        bottomRight,
        bottomLeft,
      ]);
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _vertexCoordinates(positions),
      textureCoordinates: _vertexCoordinates(textureCoordinates),
      indices: Uint16List.fromList(indices),
    );
    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()
        ..filterQuality = FilterQuality.none
        ..shader = ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          _identityMatrix(),
        ),
    );
  }

  static List<Offset> _bottomAnchoredQuad(
    List<Offset> points,
    ui.Image image,
    double sourcePadding,
  ) {
    final fraction = (sourcePadding / image.height).clamp(0.0, 1.0);
    final leftShift = (points[3] - points[0]) * fraction;
    final rightShift = (points[2] - points[1]) * fraction;
    return <Offset>[
      points[0] + leftShift,
      points[1] + rightShift,
      points[2] + rightShift,
      points[3] + leftShift,
    ];
  }

  static Float64List _identityMatrix() => Float64List.fromList(const [
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  static Float32List _vertexCoordinates(Iterable<Offset> points) {
    final values = <double>[];
    for (final point in points) {
      values
        ..add(point.dx)
        ..add(point.dy);
    }
    return Float32List.fromList(values);
  }

  void _drawRoad(Canvas canvas) {
    final upcoming = _upcomingTurn;
    final start = math.max(0.0, _distanceMeters - _cameraBackMeters);
    final missedTurn =
        upcoming != null && _distanceMeters > upcoming.distanceMeters;
    if (missedTurn) {
      // The runtime gives an unarmed runner the short inclusive tail before
      // ending the run. Keep the incoming heading under that grace window so
      // the runner does not float at a junction whose branch is already lost.
      final tailEnd = math.min(
        _distanceMeters + 8,
        upcoming.windowEndMeters + 1,
      );
      _drawRoadRange(canvas, start, tailEnd, _completedTurnCount);
      return;
    }
    _drawPlannedRoadRange(canvas, start, _distanceMeters + _farClipMeters);
  }

  void _drawPlannedRoadRange(Canvas canvas, double start, double end) {
    if (end <= start) return;
    final boundaries = <double>[start, end];
    for (final turn in _course?.turns ?? const <TempleRunTurn>[]) {
      if (turn.distanceMeters > start && turn.distanceMeters < end) {
        boundaries.add(turn.distanceMeters);
      }
    }
    boundaries.sort();
    for (var index = 0; index < boundaries.length - 1; index++) {
      final segmentStart = boundaries[index];
      final segmentEnd = boundaries[index + 1];
      if (segmentEnd <= segmentStart) continue;
      final heading = _plannedRouteStateAt(
        (segmentStart + segmentEnd) / 2,
      ).heading;
      var cursor = segmentStart;
      while (cursor < segmentEnd - .001) {
        final next = math.min(segmentEnd, cursor + 3.2);
        final first = _plannedRouteStateAt(cursor).position;
        final second = _plannedRouteStateAt(next).position;
        _drawWorldRoadSegment(
          canvas,
          first,
          second,
          heading,
          const Color(0xFFFFFFFF),
          textureVStart: cursor,
          textureVEnd: next,
        );
        cursor = next;
      }
    }
    for (final turn in _course?.turns ?? const <TempleRunTurn>[]) {
      if (turn.distanceMeters < start || turn.distanceMeters > end) continue;
      final junction = _plannedRouteStateAt(turn.distanceMeters);
      _drawRoadJunctionFill(
        canvas,
        junction: junction.position,
        incomingHeading: _plannedRouteStateAt(
          math.max(0, turn.distanceMeters - .001),
        ).heading,
        outgoingHeading: junction.heading + _turnRadians(turn.direction),
        routeDistance: turn.distanceMeters,
      );
    }
  }

  void _drawRoadRange(
    Canvas canvas,
    double start,
    double end,
    int completedTurns,
  ) {
    if (end <= start) return;
    final boundaries = <double>[start, end];
    final turns = _course?.turns ?? const <TempleRunTurn>[];
    for (
      var index = 0;
      index < completedTurns && index < turns.length;
      index++
    ) {
      final distance = turns[index].distanceMeters;
      if (distance > start && distance < end) boundaries.add(distance);
    }
    boundaries.sort();
    for (var index = 0; index < boundaries.length - 1; index++) {
      final segmentStart = boundaries[index];
      final segmentEnd = boundaries[index + 1];
      if (segmentEnd <= segmentStart) continue;
      final heading = _routeStateAt(
        (segmentStart + segmentEnd) / 2,
        completedTurns,
      ).heading;
      _drawDistanceSegment(
        canvas,
        segmentStart,
        segmentEnd,
        completedTurns,
        heading,
      );
    }
    for (
      var index = 0;
      index < completedTurns && index < turns.length;
      index++
    ) {
      final turn = turns[index];
      if (turn.distanceMeters < start || turn.distanceMeters > end) continue;
      final junction = _routeStateAt(turn.distanceMeters, completedTurns);
      _drawRoadJunctionFill(
        canvas,
        junction: junction.position,
        incomingHeading: _routeStateAt(
          math.max(0, turn.distanceMeters - .001),
          completedTurns,
        ).heading,
        outgoingHeading: _routeStateAt(
          turn.distanceMeters + .001,
          completedTurns,
        ).heading,
        routeDistance: turn.distanceMeters,
      );
    }
  }

  void _drawDistanceSegment(
    Canvas canvas,
    double start,
    double end,
    int completedTurns,
    double heading,
  ) {
    const step = 3.2;
    var cursor = start;
    while (cursor < end - .001) {
      final next = math.min(end, cursor + step);
      final first = _routeStateAt(cursor, completedTurns).position;
      final second = _routeStateAt(next, completedTurns).position;
      _drawWorldRoadSegment(
        canvas,
        first,
        second,
        heading,
        const Color(0xFFFFFFFF),
        textureVStart: cursor,
        textureVEnd: next,
      );
      cursor = next;
    }
  }

  void _drawWorldRoadSegment(
    Canvas canvas,
    Offset first,
    Offset second,
    double heading,
    Color color, {
    double? textureVStart,
    double? textureVEnd,
  }) {
    _drawWorldRoadQuad(
      canvas,
      first,
      second,
      heading,
      color,
      textureVStart: textureVStart,
      textureVEnd: textureVEnd,
    );
    if (!useImageAssets) {
      final half = _roadWorldWidth / 2;
      _drawRailWorldSegment(
        canvas,
        first,
        second,
        heading,
        side: -1,
        roadHalfWidth: half,
      );
      _drawRailWorldSegment(
        canvas,
        first,
        second,
        heading,
        side: 1,
        roadHalfWidth: half,
      );
    }
  }

  /// Fills the square/miter footprint at a 90° junction. Butt-ended strips
  /// leave the outer lane quadrant unpaved, which becomes visible when the
  /// camera shortens its boom and the runner takes the outside lane.
  void _drawRoadJunctionFill(
    Canvas canvas, {
    required Offset junction,
    required double incomingHeading,
    required double outgoingHeading,
    required double routeDistance,
  }) {
    final polygon = roadJunctionPolygonForTesting(
      junction: junction,
      incomingHeading: incomingHeading,
      outgoingHeading: outgoingHeading,
      roadWidth: _roadWorldWidth,
    );
    _drawWorldRoadPolygon(
      canvas,
      polygon,
      incomingHeading,
      routeDistance: routeDistance,
    );
  }

  @visibleForTesting
  static List<Offset> roadJunctionPolygonForTesting({
    required Offset junction,
    required double incomingHeading,
    required double outgoingHeading,
    double roadWidth = _roadWorldWidth,
  }) {
    final half = roadWidth / 2;
    final points = <Offset>[];
    for (final heading in [incomingHeading, outgoingHeading]) {
      final forward = _forward(heading);
      final right = _right(heading);
      for (final forwardSign in [-1.0, 1.0]) {
        for (final sideSign in [-1.0, 1.0]) {
          points.add(
            junction +
                forward * (forwardSign * half) +
                right * (sideSign * half),
          );
        }
      }
    }
    return _convexHull(points);
  }

  static List<Offset> _convexHull(List<Offset> points) {
    final sorted = [...points]
      ..sort((first, second) {
        final x = first.dx.compareTo(second.dx);
        return x == 0 ? first.dy.compareTo(second.dy) : x;
      });
    if (sorted.length <= 1) return sorted;
    final lower = <Offset>[];
    for (final point in sorted) {
      while (lower.length >= 2 &&
          _cross(lower.last - lower[lower.length - 2], point - lower.last) <=
              0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <Offset>[];
    for (final point in sorted.reversed) {
      while (upper.length >= 2 &&
          _cross(upper.last - upper[upper.length - 2], point - upper.last) <=
              0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
  }

  void _drawWorldRoadPolygon(
    Canvas canvas,
    List<Offset> world,
    double heading, {
    required double routeDistance,
  }) {
    final asphalt = _imageFor(asphaltAsset);
    final cameraPoints = <_CameraPoint>[];
    for (final point in world) {
      final camera = _cameraPoint(point);
      cameraPoints.add(
        _CameraPoint(
          lateral: camera.lateral,
          depth: camera.depth,
          height: camera.height,
          textureU: asphalt == null ? 0 : _asphaltTextureU(point),
          textureV: asphalt == null ? 0 : _asphaltTextureV(point),
        ),
      );
    }
    final clipped = _clipCameraPolygon(cameraPoints);
    if (clipped.length < 3) return;
    final projected = clipped.map(_projectCameraPoint).toList(growable: false);
    final path = Path()
      ..moveTo(projected.first.point.dx, projected.first.point.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.point.dx, point.point.dy);
    }
    path.close();
    if (asphalt == null) {
      canvas.drawPath(path, Paint()..color = Colors.white);
      return;
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangleFan,
      _vertexCoordinates(projected.map((point) => point.point)),
      textureCoordinates: _vertexCoordinates(
        clipped.map((point) => Offset(point.textureU, point.textureV)),
      ),
    );
    canvas.drawVertices(
      vertices,
      BlendMode.modulate,
      Paint()
        ..filterQuality = FilterQuality.none
        ..color = Colors.white
        ..shader = ui.ImageShader(
          asphalt,
          TileMode.repeated,
          TileMode.repeated,
          _identityMatrix(),
        ),
    );
  }

  void _drawWorldRoadQuad(
    Canvas canvas,
    Offset first,
    Offset second,
    double heading,
    Color color, {
    double roadCenterOffset = 0,
    double roadWidth = _roadWorldWidth,
    bool textured = true,
    double? textureVStart,
    double? textureVEnd,
    double height = 0,
  }) {
    final half = roadWidth / 2;
    final right = _right(heading);
    final center = right * roadCenterOffset;
    final world = <Offset>[
      first + center - right * half,
      second + center - right * half,
      second + center + right * half,
      first + center + right * half,
    ];
    final asphalt = textured ? _imageFor(asphaltAsset) : null;
    final cameraPoints = <_CameraPoint>[];
    for (var index = 0; index < world.length; index++) {
      final point = _cameraPoint(world[index], height: height);
      cameraPoints.add(
        _CameraPoint(
          lateral: point.lateral,
          depth: point.depth,
          height: point.height,
          // World X/Z coordinates keep every road strip and junction fill on
          // the same asphalt texture plane as the ground.
          textureU: asphalt == null ? 0 : _asphaltTextureU(world[index]),
          textureV: asphalt == null ? 0 : _asphaltTextureV(world[index]),
        ),
      );
    }
    final clipped = _clipCameraPolygon(cameraPoints);
    if (clipped.length < 3) return;
    final projected = clipped.map(_projectCameraPoint).toList(growable: false);
    final road = Path()
      ..moveTo(projected.first.point.dx, projected.first.point.dy);
    for (final point in projected.skip(1)) {
      road.lineTo(point.point.dx, point.point.dy);
    }
    road.close();
    if (asphalt == null) {
      canvas.drawPath(road, Paint()..color = color);
    } else {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangleFan,
        _vertexCoordinates(projected.map((point) => point.point)),
        textureCoordinates: _vertexCoordinates(
          clipped.map((point) => Offset(point.textureU, point.textureV)),
        ),
      );
      canvas.drawVertices(
        vertices,
        BlendMode.modulate,
        Paint()
          ..filterQuality = FilterQuality.none
          ..color = color
          ..shader = ui.ImageShader(
            asphalt,
            TileMode.repeated,
            TileMode.repeated,
            _identityMatrix(),
          ),
      );
    }
  }

  void _drawRailWorldSegment(
    Canvas canvas,
    Offset first,
    Offset second,
    double heading, {
    required int side,
    double roadCenterOffset = 0,
    double roadHalfWidth = _roadWorldWidth / 2,
  }) {
    final right = _right(heading);
    final offset = roadCenterOffset + side * (roadHalfWidth + .18);
    final firstCamera = _cameraPoint(first + right * offset);
    final secondCamera = _cameraPoint(second + right * offset);
    final clipped = _clipCameraLine(firstCamera, secondCamera);
    if (clipped != null) {
      final firstProjected = _projectCameraPoint(clipped.first);
      final secondProjected = _projectCameraPoint(clipped.last);
      final rail = Paint()
        ..color = const Color(0xD0B39361)
        ..strokeWidth = math.max(1.2, firstProjected.scale * .035)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(firstProjected.point, secondProjected.point, rail);
      final postHeight = math.max(3.0, firstProjected.scale * .11);
      canvas.drawLine(
        firstProjected.point,
        firstProjected.point - Offset(0, postHeight),
        rail,
      );
    }
  }

  List<_CameraPoint> _clipCameraPolygon(List<_CameraPoint> points) {
    var clipped = _clipCameraPlane(
      points,
      boundary: _nearClipMeters,
      keepAbove: true,
    );
    clipped = _clipCameraPlane(
      clipped,
      boundary: _farClipMeters,
      keepAbove: false,
    );
    return clipped;
  }

  List<_CameraPoint> _clipCameraPolygonToDepth(
    List<_CameraPoint> points,
    double maximumDepth,
  ) {
    if (maximumDepth <= _nearClipMeters) return const <_CameraPoint>[];
    var clipped = _clipCameraPlane(
      points,
      boundary: _nearClipMeters,
      keepAbove: true,
    );
    clipped = _clipCameraPlane(
      clipped,
      boundary: math.min(_farClipMeters, maximumDepth),
      keepAbove: false,
    );
    return clipped;
  }

  List<_CameraPoint> _clipCameraPlane(
    List<_CameraPoint> points, {
    required double boundary,
    required bool keepAbove,
  }) {
    if (points.isEmpty) return const <_CameraPoint>[];
    final result = <_CameraPoint>[];
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final previous = points[(index + points.length - 1) % points.length];
      final currentVisible = keepAbove
          ? current.depth >= boundary
          : current.depth <= boundary;
      final previousVisible = keepAbove
          ? previous.depth >= boundary
          : previous.depth <= boundary;
      if (currentVisible != previousVisible) {
        final outside = currentVisible ? previous : current;
        final inside = currentVisible ? current : previous;
        result.add(_interpolateCameraPoint(outside, inside, boundary));
      }
      if (currentVisible) result.add(current);
    }
    return result;
  }

  List<_CameraPoint>? _clipCameraLine(_CameraPoint first, _CameraPoint second) {
    final clipped = <_CameraPoint>[first, second];
    final near = _clipCameraPlane(
      clipped,
      boundary: _nearClipMeters,
      keepAbove: true,
    );
    final far = _clipCameraPlane(
      near,
      boundary: _farClipMeters,
      keepAbove: false,
    );
    if (far.length < 2) return null;
    return [far.first, far.last];
  }

  _CameraPoint _interpolateCameraPoint(
    _CameraPoint outside,
    _CameraPoint inside,
    double boundary,
  ) {
    final denominator = inside.depth - outside.depth;
    final amount = denominator.abs() < .0001
        ? 0.0
        : ((boundary - outside.depth) / denominator).clamp(0.0, 1.0);
    return _CameraPoint(
      lateral: outside.lateral + (inside.lateral - outside.lateral) * amount,
      depth: boundary,
      height: outside.height + (inside.height - outside.height) * amount,
      textureU:
          outside.textureU + (inside.textureU - outside.textureU) * amount,
      textureV:
          outside.textureV + (inside.textureV - outside.textureV) * amount,
    );
  }

  void _drawObjects(
    Canvas canvas,
    List<_ProjectedFacadeOccluder> facadeOccluders,
  ) {
    final course = _course;
    if (course == null) return;
    final upcoming = _upcomingTurn;
    final items = <_TempleRunRenderItem>[];
    for (final obstacle in course.obstacles) {
      if (obstacle.isNarrowPath) {
        if (upcoming != null &&
            obstacle.distanceMeters > upcoming.distanceMeters + 1.5) {
          // Until the runner executes the junction, do not project a future
          // narrow interval on the incoming heading as a phantom straight
          // obstacle. The branch stack row appears after the turn is real.
          continue;
        }
        if (!useImageAssets ||
            // Retain the interval until its far end is beyond the maximum
            // camera boom. Projection and near clipping remove it once no
            // part of the bank can reach the viewport; culling it sooner
            // makes the visible tail pop while it is still behind the runner.
            obstacle.endDistanceMeters < _distanceMeters - _cameraBackMeters ||
            obstacle.distanceMeters > _distanceMeters + _farClipMeters) {
          continue;
        }
        // A narrow path is a short construction squeeze (1.5m or 3m).
        // Continuous worksite banks occupy the unsafe world ranges for the
        // authored interval, leaving the safe strip visible and aligned with
        // the rules.
        for (final bank in _narrowWorksiteBanks(obstacle)) {
          final startState = _routeStateAt(
            bank.startDistance,
            _completedTurnCount,
          );
          final endState = _routeStateAt(bank.endDistance, _completedTurnCount);
          final startWorld =
              startState.position +
              _right(startState.heading) *
                  ((bank.innerOffset + bank.outerOffset) / 2);
          final endWorld =
              endState.position +
              _right(endState.heading) *
                  ((bank.innerOffset + bank.outerOffset) / 2);
          final startPoint = _projectWorld(startWorld);
          final endPoint = _projectWorld(endWorld);
          if (startPoint == null && endPoint == null) continue;
          final bankPoint = startPoint ?? endPoint!;
          final bankWorld = startPoint == null ? endWorld : startWorld;
          final bankOccluders = _facadeOccludersForEvent(
            world: bankWorld,
            point: bankPoint,
            widthWorld: bank.width,
            heightWorld: obstaclePalletHeightMeters,
            all: facadeOccluders,
          );
          items.add(
            _TempleRunRenderItem(
              depth: math.min(
                startPoint?.depth ?? double.infinity,
                endPoint?.depth ?? double.infinity,
              ),
              draw: (canvas) => _drawWithFacadeOcclusion(
                canvas,
                bankOccluders,
                (target) => _drawNarrowWorksiteBank(target, bank: bank),
              ),
            ),
          );
        }
        continue;
      }
      if (upcoming != null &&
          obstacle.distanceMeters > upcoming.distanceMeters + 1.5) {
        continue;
      }
      final relative = obstacle.distanceMeters - _distanceMeters;
      if (relative < -TempleRunRules.collisionWindowMeters ||
          relative > _farClipMeters) {
        continue;
      }
      final point = _projectEvent(
        obstacle.distanceMeters,
        obstacle.lane,
        fullRoad: obstacle.spansFullRoad || _isFullRoadLane(obstacle.lane),
      );
      if (point == null) continue;
      final fullRoad = obstacle.spansFullRoad || _isFullRoadLane(obstacle.lane);
      final obstacleWorld = _eventWorld(
        obstacle.distanceMeters,
        obstacle.lane,
        fullRoad: fullRoad,
      );
      final obstacleOccluders = _facadeOccludersForEvent(
        world: obstacleWorld,
        point: point,
        widthWorld: _obstacleWidthWorld(obstacle, fullRoad: fullRoad),
        heightWorld: _obstacleHeightWorld(obstacle),
        all: facadeOccluders,
      );
      items.add(
        _TempleRunRenderItem(
          depth: point.depth,
          draw: (canvas) => _drawWithFacadeOcclusion(
            canvas,
            obstacleOccluders,
            (target) =>
                _drawObstacle(target, point, obstacle, fullRoad: fullRoad),
          ),
        ),
      );
    }
    for (var coinIndex = 0; coinIndex < course.coins.length; coinIndex++) {
      if (_consumedCoinIndices.contains(coinIndex)) continue;
      final coin = course.coins[coinIndex];
      if (upcoming != null &&
          coin.distanceMeters > upcoming.distanceMeters + 1.5) {
        continue;
      }
      final relative = coin.distanceMeters - _distanceMeters;
      if (relative < -TempleRunRules.coinPickupWindowMeters ||
          relative > _farClipMeters) {
        continue;
      }
      final point = _projectEvent(coin.distanceMeters, coin.lane);
      if (point == null) continue;
      final coinWorld = _eventWorld(coin.distanceMeters, coin.lane);
      final coinOccluders = _facadeOccludersForEvent(
        world: coinWorld,
        point: point,
        widthWorld: .8,
        heightWorld: 1.2,
        all: facadeOccluders,
      );
      items.add(
        _TempleRunRenderItem(
          depth: point.depth,
          draw: (canvas) => _drawWithFacadeOcclusion(
            canvas,
            coinOccluders,
            (target) =>
                _drawCollectible(target, point, _TempleRunCollectibleKind.coin),
          ),
        ),
      );
    }
    for (
      var powerUpIndex = 0;
      powerUpIndex < course.powerUps.length;
      powerUpIndex++
    ) {
      if (_consumedPowerUpIndices.contains(powerUpIndex)) continue;
      final powerUp = course.powerUps[powerUpIndex];
      if (upcoming != null &&
          powerUp.distanceMeters > upcoming.distanceMeters + 1.5) {
        continue;
      }
      final relative = powerUp.distanceMeters - _distanceMeters;
      if (relative < -TempleRunRules.powerUpPickupWindowMeters ||
          relative > _farClipMeters) {
        continue;
      }
      final point = _projectEvent(powerUp.distanceMeters, powerUp.lane);
      if (point == null) continue;
      final kind = switch (powerUp.kind) {
        TempleRunPowerUpKind.magnet => _TempleRunCollectibleKind.magnet,
        TempleRunPowerUpKind.shield => _TempleRunCollectibleKind.shield,
        TempleRunPowerUpKind.boost => _TempleRunCollectibleKind.boost,
      };
      final powerUpWorld = _eventWorld(powerUp.distanceMeters, powerUp.lane);
      final powerUpOccluders = _facadeOccludersForEvent(
        world: powerUpWorld,
        point: point,
        widthWorld: .9,
        heightWorld: 1.3,
        all: facadeOccluders,
      );
      items.add(
        _TempleRunRenderItem(
          depth: point.depth,
          draw: (canvas) => _drawWithFacadeOcclusion(
            canvas,
            powerUpOccluders,
            (target) => _drawCollectible(target, point, kind),
          ),
        ),
      );
    }
    items.sort((a, b) => b.depth.compareTo(a.depth));
    for (final item in items) {
      item.draw(canvas);
    }
  }

  static double _obstacleWidthWorld(
    TempleRunObstacle obstacle, {
    required bool fullRoad,
  }) => fullRoad
      ? _roadWorldWidth
      : obstacle.widthInLanes * _roadWorldWidth / TempleRunRules.laneCount;

  static double _obstacleHeightWorld(TempleRunObstacle obstacle) =>
      switch (obstacle.kind) {
        TempleRunObstacleKind.hurdle => obstacleBarricadeHeightMeters,
        TempleRunObstacleKind.arch => obstacleScaffoldHeightMeters,
        TempleRunObstacleKind.rubble => obstaclePalletHeightMeters,
        TempleRunObstacleKind.gap => .34,
        TempleRunObstacleKind.narrowPath => obstaclePalletHeightMeters,
      };

  @visibleForTesting
  static double obstacleWidthForTesting({
    required double widthInLanes,
    required bool fullRoad,
  }) => fullRoad
      ? _roadWorldWidth
      : widthInLanes * _roadWorldWidth / TempleRunRules.laneCount;

  @visibleForTesting
  static double obstacleHeightForTesting(TempleRunObstacleKind kind) =>
      _obstacleHeightWorld(
        TempleRunObstacle(
          distanceMeters: 0,
          lane: TempleRunRules.centerLane,
          kind: kind,
        ),
      );

  @visibleForTesting
  static List<({double innerOffset, double outerOffset})>
  narrowBankOffsetsForTesting(int lane) => List.unmodifiable(
    _narrowBankOffsets(lane).map(
      (bank) => (innerOffset: bank.innerOffset, outerOffset: bank.outerOffset),
    ),
  );

  static List<({double innerOffset, double outerOffset})> _narrowBankOffsets(
    int lane,
  ) {
    final roadHalf = _roadWorldWidth / 2;
    final safeCenter =
        (lane - TempleRunRules.centerLane) *
        (_roadWorldWidth / TempleRunRules.laneCount);
    final safeHalf =
        TempleRunRules.narrowPathSafeWidthInLanes *
        (_roadWorldWidth / TempleRunRules.laneCount) /
        2;
    final safeStart = safeCenter - safeHalf;
    final safeEnd = safeCenter + safeHalf;
    final banks = <({double innerOffset, double outerOffset})>[];

    // Lane 0/2's outside bank sits wholly beyond legal player-center motion.
    // Keep the thick unsafe bank and retain both sides for a center-lane
    // manual course, where both unsafe regions remain reachable.
    if (lane > TempleRunRules.firstLane && safeStart > -roadHalf + .001) {
      banks.add((innerOffset: safeStart, outerOffset: -roadHalf));
    }
    if (lane < TempleRunRules.lastLane && safeEnd < roadHalf - .001) {
      banks.add((innerOffset: safeEnd, outerOffset: roadHalf));
    }
    return banks;
  }

  List<_TempleRunNarrowWorksiteBank> _narrowWorksiteBanks(
    TempleRunObstacle obstacle,
  ) {
    return [
      for (final bank in _narrowBankOffsets(obstacle.lane))
        _TempleRunNarrowWorksiteBank(
          width: (bank.outerOffset - bank.innerOffset).abs(),
          startDistance: obstacle.distanceMeters,
          endDistance: obstacle.endDistanceMeters,
          innerOffset: bank.innerOffset,
          outerOffset: bank.outerOffset,
        ),
    ];
  }

  _ProjectedWorldPoint? _projectEvent(
    double distance,
    int lane, {
    bool fullRoad = false,
  }) {
    // Static world events stay on the authored route while the runner/camera
    // eases through a corner. Applying the runner's visual turn basis here
    // would rotate future coins and obstacles through the world during the
    // 180ms animation.
    return _projectWorld(_eventWorld(distance, lane, fullRoad: fullRoad));
  }

  bool _isFullRoadLane(int lane) =>
      lane < TempleRunRules.firstLane || lane > TempleRunRules.lastLane;

  List<_ProjectedFacadeOccluder> _buildVisibleFacadeOccluders() {
    // Image-backed facades record the exact clipped module and volume faces
    // while they are drawn. Reuse those polygons for gameplay occlusion so a
    // projected house cannot reveal coins through its returns (and so the
    // old baseline mask cannot hide objects in the setback gap).
    if (useImageAssets) return _renderedFacadeOccluders;

    final legs = _plannedFacadeLegs;
    if (legs.isEmpty) return const <_ProjectedFacadeOccluder>[];
    final visibleWindow = _visibleFacadeRouteWindow();
    if (visibleWindow == null) return const <_ProjectedFacadeOccluder>[];
    final visibleStart = visibleWindow.start;
    final visibleEnd = visibleWindow.end;
    final result = <_ProjectedFacadeOccluder>[];
    final sides = <List<TempleRunFacadeWallSpan>>[
      _facadeWallSpansLeft,
      _facadeWallSpansRight,
    ];
    for (final spans in sides) {
      var firstIndex = 0;
      var lastIndex = spans.length;
      // Spans are authored in route order, so skip the far prefix with a
      // binary search and only build masks from the same visible route window
      // as the facade renderer.
      while (firstIndex < lastIndex) {
        final middle = (firstIndex + lastIndex) ~/ 2;
        if (spans[middle].wallEnd <= visibleStart) {
          firstIndex = middle + 1;
        } else {
          lastIndex = middle;
        }
      }
      for (var index = firstIndex; index < spans.length; index++) {
        final span = spans[index];
        if (!_isFacadeLegInDisplayNeighborhood(span.routeLegIndex)) continue;
        if (span.wallStart >= visibleEnd) break;
        final start = math.max(span.wallStart, visibleStart);
        final end = math.min(span.wallEnd, visibleEnd);
        if (end <= start + .001) continue;
        final amountStart =
            (start - span.wallStart) / (span.wallEnd - span.wallStart);
        final amountEnd =
            (end - span.wallStart) / (span.wallEnd - span.wallStart);
        final frontStart = Offset.lerp(
          span.frontStart,
          span.frontEnd,
          amountStart,
        )!;
        final frontEnd = Offset.lerp(
          span.frontStart,
          span.frontEnd,
          amountEnd,
        )!;
        final cameraPolygon = <_CameraPoint>[
          _cameraPoint(frontStart),
          _cameraPoint(frontEnd),
          _cameraPoint(frontEnd, height: facadeHeightMeters),
          _cameraPoint(frontStart, height: facadeHeightMeters),
        ];
        final clipped = _clipCameraPolygon(cameraPolygon);
        if (clipped.length < 3) continue;
        final projected = clipped
            .map(_projectCameraPoint)
            .toList(growable: false);
        final path = Path()
          ..moveTo(projected.first.point.dx, projected.first.point.dy);
        for (final point in projected.skip(1)) {
          path.lineTo(point.point.dx, point.point.dy);
        }
        path.close();
        final bounds = path.getBounds();
        if (bounds.isEmpty || !bounds.left.isFinite || !bounds.top.isFinite) {
          continue;
        }
        final nearDepth = clipped.fold<double>(
          double.infinity,
          (minimum, point) => math.min(minimum, point.depth),
        );
        result.add(
          _ProjectedFacadeOccluder(
            path: path,
            bounds: bounds,
            nearDepth: nearDepth,
            cameraPolygon: cameraPolygon,
          ),
        );
      }
    }
    return result;
  }

  ({double start, double end})? _visibleFacadeRouteWindow() {
    final legs = _plannedFacadeLegs;
    if (legs.isEmpty) return null;
    final start = math.max(
      legs.first.start,
      _distanceMeters - _cameraBackMeters - _facadeVisibleBehindMeters,
    );
    final end = math.min(legs.last.end, _distanceMeters + _farClipMeters);
    if (end <= start) return null;
    return (start: start, end: end);
  }

  /// Keep display-only facade geometry local to the runner's current route
  /// neighborhood. The distance window intentionally looks far ahead for
  /// scenery, but a winding route can put a later leg across the active road
  /// before the camera has reached its turn. Retain the previous, current,
  /// and next legs so the junction remains closed and the next end wall is
  /// still visible without allowing remote future walls or curbs to cross the
  /// playable lane.
  bool _isFacadeLegInDisplayNeighborhood(int routeLegIndex) {
    if (routeLegIndex < 0 || routeLegIndex >= _plannedFacadeLegs.length) {
      return false;
    }
    final current = _completedTurnCount.clamp(
      0,
      math.max(0, _plannedFacadeLegs.length - 1),
    );
    return routeLegIndex >= current - 1 && routeLegIndex <= current + 1;
  }

  Offset _eventWorld(double distance, int lane, {bool fullRoad = false}) {
    final state = _routeStateAt(distance, _completedTurnCount);
    if (fullRoad) return state.position;
    return state.position +
        _right(state.heading) *
            ((lane - TempleRunRules.centerLane) * (_roadWorldWidth / 3));
  }

  List<_ProjectedFacadeOccluder> _facadeOccludersForEvent({
    required Offset world,
    required _ProjectedWorldPoint point,
    required double widthWorld,
    required double heightWorld,
    required List<_ProjectedFacadeOccluder> all,
  }) {
    if (all.isEmpty) return const <_ProjectedFacadeOccluder>[];
    final width = math.max(1.0, point.scale * widthWorld);
    final height = math.max(1.0, point.scale * heightWorld);
    final eventBounds = Rect.fromLTRB(
      point.point.dx - width / 2,
      point.point.dy - height,
      point.point.dx + width / 2,
      point.point.dy + point.scale * .12,
    );
    final targetDepth = _cameraPoint(world).depth;
    if (targetDepth <= _nearClipMeters + .01) {
      return const <_ProjectedFacadeOccluder>[];
    }
    final result = <_ProjectedFacadeOccluder>[];
    for (final occluder in all) {
      if (occluder.nearDepth + .05 >= targetDepth ||
          !occluder.bounds
              .inflate(math.max(2.0, width * .18))
              .overlaps(eventBounds)) {
        continue;
      }
      // A long facade span may cross in front of and behind the event. Clip
      // the camera-space wall quad to the event's depth before projecting it,
      // so only the nearer portion subtracts from the billboard. This keeps a
      // large shutter or stack partially visible as it emerges around a
      // corner instead of center-culling the entire prop.
      final clipped = _clipCameraPolygonToDepth(
        occluder.cameraPolygon,
        targetDepth - .035,
      );
      if (clipped.length < 3) continue;
      final projected = clipped
          .map(_projectCameraPoint)
          .toList(growable: false);
      final path = Path()
        ..moveTo(projected.first.point.dx, projected.first.point.dy);
      for (final projectedPoint in projected.skip(1)) {
        path.lineTo(projectedPoint.point.dx, projectedPoint.point.dy);
      }
      path.close();
      final bounds = path.getBounds();
      if (bounds.isEmpty || !bounds.overlaps(eventBounds)) continue;
      final nearDepth = clipped.fold<double>(
        double.infinity,
        (minimum, cameraPoint) => math.min(minimum, cameraPoint.depth),
      );
      result.add(
        _ProjectedFacadeOccluder(
          path: path,
          bounds: bounds,
          nearDepth: nearDepth,
          cameraPolygon: occluder.cameraPolygon,
        ),
      );
    }
    return result;
  }

  void _drawWithFacadeOcclusion(
    Canvas canvas,
    List<_ProjectedFacadeOccluder> occluders,
    void Function(Canvas canvas) draw,
  ) {
    if (occluders.isEmpty) {
      draw(canvas);
      return;
    }
    canvas.save();
    for (final occluder in occluders) {
      final viewport = Path()..addRect(Rect.fromLTWH(0, 0, size.x, size.y));
      final difference = Path.combine(
        PathOperation.difference,
        viewport,
        occluder.path,
      );
      canvas.clipPath(difference, doAntiAlias: false);
    }
    draw(canvas);
    canvas.restore();
  }

  void _drawObstacle(
    Canvas canvas,
    _ProjectedWorldPoint point,
    TempleRunObstacle obstacle, {
    required bool fullRoad,
  }) {
    final kind = obstacle.kind;
    if (kind == TempleRunObstacleKind.narrowPath) return;
    if (kind == TempleRunObstacleKind.gap) {
      _drawConstructionTrench(canvas, obstacle, fullRoad: fullRoad);
      return;
    }
    final state = _routeStateAt(obstacle.distanceMeters, _completedTurnCount);
    final center = fullRoad
        ? state.position
        : state.position +
              _right(state.heading) *
                  ((obstacle.lane - TempleRunRules.centerLane) *
                      (_roadWorldWidth / TempleRunRules.laneCount));
    final width = _obstacleWidthWorld(obstacle, fullRoad: fullRoad);
    switch (kind) {
      case TempleRunObstacleKind.hurdle:
        final useVariant = _usesJumpObstacleVariant(obstacle);
        final variantImage = _imageFor(jumpVariantAsset);
        final image = useVariant
            ? variantImage ??
                  _imageFor(streetscapeBarricadeAsset) ??
                  _imageFor(hurdleAsset)
            : _imageFor(streetscapeBarricadeAsset) ?? _imageFor(hurdleAsset);
        if (image != null) {
          _drawWorldSpritePlane(
            canvas,
            image: image,
            center: center,
            heading: state.heading,
            width: width,
            height: obstacleBarricadeHeightMeters,
            sourceRect: useVariant && image == variantImage
                ? _jumpVariantFootprint.sourceRect
                : image == _imageFor(streetscapeBarricadeAsset)
                ? _streetscapeBarricadeFootprint.sourceRect
                : _hurdleFootprint.sourceRect,
          );
        } else {
          _drawObstacleSolidBox(
            canvas,
            center: center,
            heading: state.heading,
            width: width,
            height: obstacleBarricadeHeightMeters,
            depth: .12,
            color: const Color(0xFF806342),
          );
        }
      case TempleRunObstacleKind.arch:
        final useVariant = _usesSlideObstacleVariant(obstacle);
        final variantImage = _imageFor(slideVariantAsset);
        final image = useVariant
            ? variantImage ??
                  _imageFor(streetscapeScaffoldAsset) ??
                  _imageFor(shutterAsset)
            : _imageFor(streetscapeScaffoldAsset) ?? _imageFor(shutterAsset);
        if (image != null && image == _imageFor(streetscapeScaffoldAsset)) {
          _drawScaffoldSprite(canvas, image, center, state.heading, width);
        } else if (image != null) {
          _drawWorldSpritePlane(
            canvas,
            image: image,
            center: center,
            heading: state.heading,
            width: width,
            height: obstacleScaffoldHeightMeters,
            sourceRect: useVariant && image == variantImage
                ? _slideVariantFootprint.sourceRect
                : _shutterFootprint.sourceRect,
          );
        } else {
          _drawObstacleSolidBox(
            canvas,
            center: center,
            heading: state.heading,
            width: width,
            height: obstacleScaffoldHeightMeters,
            depth: .18,
            color: const Color(0xFF657277),
          );
        }
      case TempleRunObstacleKind.rubble:
        _drawPalletCuboid(canvas, center, state.heading, width);
      case TempleRunObstacleKind.gap:
      case TempleRunObstacleKind.narrowPath:
        return;
    }
  }

  // Generated courses keep the existing collision kinds. Every fourth
  // authored vertical hazard receives the new silhouette, while id 0 remains
  // reserved for hand-authored fixtures and the original asset contract.
  // The domain worker can later replace this deterministic routing with an
  // explicit variant field without changing any collision or projection code.
  static bool _usesJumpObstacleVariant(TempleRunObstacle obstacle) =>
      obstacle.kind == TempleRunObstacleKind.hurdle &&
      obstacle.id > 0 &&
      obstacle.id % 4 == 0;

  static bool _usesSlideObstacleVariant(TempleRunObstacle obstacle) =>
      obstacle.kind == TempleRunObstacleKind.arch &&
      obstacle.id > 0 &&
      obstacle.id % 4 == 2;

  void _drawWorldSpritePlane(
    Canvas canvas, {
    required ui.Image image,
    required Offset center,
    required double heading,
    required double width,
    required double height,
    required Rect sourceRect,
  }) {
    _drawWorldImageQuad(
      canvas,
      image: image,
      sourceRect: sourceRect,
      world: _verticalWorldQuad(center: center, heading: heading, width: width),
      heights: [height, height, 0, 0],
    );
  }

  void _drawScaffoldSprite(
    Canvas canvas,
    ui.Image image,
    Offset center,
    double heading,
    double width,
  ) {
    final footprint = _streetscapeScaffoldFootprint;
    final splitY = 352.0;
    // The lower opening is mapped to a 1.0m crawl clearance while the solid
    // hoarding and grounded posts retain the fixed 2.9m authored height.
    _drawWorldImageQuad(
      canvas,
      image: image,
      sourceRect: Rect.fromLTRB(
        footprint.left,
        splitY,
        footprint.right,
        footprint.bottom,
      ),
      world: _verticalWorldQuad(center: center, heading: heading, width: width),
      heights: [
        obstacleScaffoldOpeningHeightMeters,
        obstacleScaffoldOpeningHeightMeters,
        0,
        0,
      ],
    );
    _drawWorldImageQuad(
      canvas,
      image: image,
      sourceRect: Rect.fromLTRB(
        footprint.left,
        footprint.top,
        footprint.right,
        splitY,
      ),
      world: _verticalWorldQuad(center: center, heading: heading, width: width),
      heights: [
        obstacleScaffoldHeightMeters,
        obstacleScaffoldHeightMeters,
        obstacleScaffoldOpeningHeightMeters,
        obstacleScaffoldOpeningHeightMeters,
      ],
    );
  }

  List<Offset> _verticalWorldQuad({
    required Offset center,
    required double heading,
    required double width,
  }) {
    final right = _right(heading);
    final left = center - right * width / 2;
    final farRight = center + right * width / 2;
    // World points are ordered top-left, top-right, bottom-right,
    // bottom-left to match _drawImageQuad's texture winding.
    return <Offset>[left, farRight, farRight, left];
  }

  void _drawPalletCuboid(
    Canvas canvas,
    Offset center,
    double heading,
    double width,
  ) {
    final forward = _forward(heading);
    final right = _right(heading);
    final halfWidth = width / 2;
    final halfDepth = obstaclePalletDepthMeters / 2;
    final near = center - forward * halfDepth;
    final far = center + forward * halfDepth;
    final nearLeft = near - right * halfWidth;
    final nearRight = near + right * halfWidth;
    final farLeft = far - right * halfWidth;
    final farRight = far + right * halfWidth;
    final image = _imageFor(streetscapePalletAsset);
    if (image != null) {
      _drawWorldImageQuad(
        canvas,
        image: image,
        sourceRect: _streetscapePalletFrontSource,
        world: [nearLeft, nearRight, nearRight, nearLeft],
        heights: [obstaclePalletHeightMeters, obstaclePalletHeightMeters, 0, 0],
        cullBackFace: true,
      );
      _drawWorldImageQuad(
        canvas,
        image: image,
        sourceRect: _streetscapePalletSideSource,
        world: [farLeft, nearLeft, nearLeft, farLeft],
        heights: [obstaclePalletHeightMeters, obstaclePalletHeightMeters, 0, 0],
        cullBackFace: true,
      );
      _drawWorldImageQuad(
        canvas,
        image: image,
        sourceRect: _streetscapePalletSideSource,
        world: [nearRight, farRight, farRight, nearRight],
        heights: [obstaclePalletHeightMeters, obstaclePalletHeightMeters, 0, 0],
        cullBackFace: true,
      );
      _drawWorldImageQuad(
        canvas,
        image: image,
        sourceRect: _streetscapePalletTopSource,
        world: [nearLeft, farLeft, farRight, nearRight],
        heights: [
          obstaclePalletHeightMeters,
          obstaclePalletHeightMeters,
          obstaclePalletHeightMeters,
          obstaclePalletHeightMeters,
        ],
        cullBackFace: true,
      );
      return;
    }
    _drawWorldSolidQuad(
      canvas,
      world: [nearLeft, nearRight, nearRight, nearLeft],
      heights: [obstaclePalletHeightMeters, obstaclePalletHeightMeters, 0, 0],
      color: const Color(0xFF8B5C3C),
    );
    _drawWorldSolidQuad(
      canvas,
      world: [farLeft, nearLeft, nearLeft, farLeft],
      heights: [obstaclePalletHeightMeters, obstaclePalletHeightMeters, 0, 0],
      color: const Color(0xFF62432F),
    );
    _drawWorldSolidQuad(
      canvas,
      world: [nearLeft, nearRight, farRight, farLeft],
      heights: [
        obstaclePalletHeightMeters,
        obstaclePalletHeightMeters,
        obstaclePalletHeightMeters,
        obstaclePalletHeightMeters,
      ],
      color: const Color(0xFFB47C4E),
    );
  }

  void _drawWorldImageQuad(
    Canvas canvas, {
    required ui.Image image,
    required Rect sourceRect,
    required List<Offset> world,
    required List<double> heights,
    bool cullBackFace = false,
  }) {
    if (world.length != 4 || heights.length != 4) return;
    // A single screen-affine quad visibly shears a long world face at a turn.
    // Subdivide every face into small world patches so each patch stays close
    // to one route leg; each planar patch is then drawn with a projective
    // homography and the source UVs remain correct through near clipping.
    final horizontalLength = math.max(
      (world[1] - world[0]).distance,
      (world[2] - world[3]).distance,
    );
    final verticalRange = heights.reduce(math.max) - heights.reduce(math.min);
    final columns = math.max(1, (horizontalLength / .5).ceil());
    final rows = math.max(1, (verticalRange / .5).ceil());
    Offset bilinearOffset(double u, double v) {
      final top = Offset.lerp(world[0], world[1], u)!;
      final bottom = Offset.lerp(world[3], world[2], u)!;
      return Offset.lerp(top, bottom, v)!;
    }

    double bilinearHeight(double u, double v) {
      final top = heights[0] + (heights[1] - heights[0]) * u;
      final bottom = heights[3] + (heights[2] - heights[3]) * u;
      return top + (bottom - top) * v;
    }

    for (var row = 0; row < rows; row++) {
      final v0 = row / rows;
      final v1 = (row + 1) / rows;
      for (var column = 0; column < columns; column++) {
        final u0 = column / columns;
        final u1 = (column + 1) / columns;
        _drawWorldImageQuadPiece(
          canvas,
          image: image,
          sourceRect: Rect.fromLTRB(
            sourceRect.left + sourceRect.width * u0,
            sourceRect.top + sourceRect.height * v0,
            sourceRect.left + sourceRect.width * u1,
            sourceRect.top + sourceRect.height * v1,
          ),
          world: [
            bilinearOffset(u0, v0),
            bilinearOffset(u1, v0),
            bilinearOffset(u1, v1),
            bilinearOffset(u0, v1),
          ],
          heights: [
            bilinearHeight(u0, v0),
            bilinearHeight(u1, v0),
            bilinearHeight(u1, v1),
            bilinearHeight(u0, v1),
          ],
          cullBackFace: cullBackFace,
        );
      }
    }
  }

  void _drawWorldImageQuadPiece(
    Canvas canvas, {
    required ui.Image image,
    required Rect sourceRect,
    required List<Offset> world,
    required List<double> heights,
    required bool cullBackFace,
  }) {
    final sourcePoints = <Offset>[
      Offset(sourceRect.left, sourceRect.top),
      Offset(sourceRect.right, sourceRect.top),
      Offset(sourceRect.right, sourceRect.bottom),
      Offset(sourceRect.left, sourceRect.bottom),
    ];
    final camera = <_CameraPoint>[];
    for (var index = 0; index < 4; index++) {
      final point = _cameraPoint(world[index], height: heights[index]);
      camera.add(
        point.withTexture(sourcePoints[index].dx, sourcePoints[index].dy),
      );
    }
    final clipped = _clipCameraPolygon(camera);
    if (clipped.length < 3) return;
    if (cullBackFace && !_isCameraFaceVisible(clipped)) return;
    final projected = clipped.map(_projectCameraPoint).toList(growable: false);
    final path = Path()
      ..moveTo(projected.first.point.dx, projected.first.point.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.point.dx, point.point.dy);
    }
    path.close();
    final matrix = _worldQuadHomography(
      camera,
      sourceWidth: sourceRect.width,
      sourceHeight: sourceRect.height,
    );
    canvas.save();
    canvas.clipPath(path, doAntiAlias: false);
    canvas.transform(matrix);
    canvas.drawImageRect(
      image,
      sourceRect,
      Rect.fromLTWH(0, 0, sourceRect.width, sourceRect.height),
      Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  Float64List _worldQuadHomography(
    List<_CameraPoint> camera, {
    required double sourceWidth,
    required double sourceHeight,
  }) {
    final first = camera[0];
    final horizontal = camera[1];
    final vertical = camera[3];
    final dU = (horizontal.depth - first.depth) / sourceWidth;
    final dV = (vertical.depth - first.depth) / sourceHeight;
    final lU = (horizontal.lateral - first.lateral) / sourceWidth;
    final lV = (vertical.lateral - first.lateral) / sourceHeight;
    final hU = (horizontal.height - first.height) / sourceWidth;
    final hV = (vertical.height - first.height) / sourceHeight;
    final focal = _focalLength * (_cameraTargetDepth / _cameraBackMeters);
    final centerX = size.x / 2;
    return Float64List.fromList(<double>[
      centerX * dU + focal * lU,
      _horizonY * dU - focal * hU,
      0,
      dU,
      centerX * dV + focal * lV,
      _horizonY * dV - focal * hV,
      0,
      dV,
      0,
      0,
      1,
      0,
      centerX * first.depth + focal * first.lateral,
      _horizonY * first.depth + focal * (_cameraHeightMeters - first.height),
      0,
      first.depth,
    ]);
  }

  void _drawWorldSolidQuad(
    Canvas canvas, {
    required List<Offset> world,
    required List<double> heights,
    required Color color,
  }) {
    if (world.length != 4 || heights.length != 4) return;
    final camera = <_CameraPoint>[];
    for (var index = 0; index < 4; index++) {
      camera.add(_cameraPoint(world[index], height: heights[index]));
    }
    final clipped = _clipCameraPolygon(camera);
    if (clipped.length < 3) return;
    final projected = clipped.map(_projectCameraPoint).toList(growable: false);
    final path = Path()
      ..moveTo(projected.first.point.dx, projected.first.point.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.point.dx, point.point.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = false
        ..color = color,
    );
  }

  void _drawNarrowWorksiteBank(
    Canvas canvas, {
    required _TempleRunNarrowWorksiteBank bank,
  }) {
    final image = _imageFor(streetscapePalletAsset);
    final frontSource = image == null ? null : _streetscapePalletFrontSource;
    final sideSource = image == null ? null : _streetscapePalletSideSource;
    final topSource = image == null ? null : _streetscapePalletTopSource;
    const sectionLength = 2.0;

    void drawEndCap({required bool farEnd}) {
      final distance = farEnd ? bank.endDistance : bank.startDistance;
      final state = _routeStateAt(distance, _completedTurnCount);
      final right = _right(state.heading);
      final inner = state.position + right * bank.innerOffset;
      final outer = state.position + right * bank.outerOffset;
      final top = obstaclePalletHeightMeters;
      final world = farEnd
          ? [outer, inner, inner, outer]
          : [inner, outer, outer, inner];
      if (image != null) {
        _drawWorldImageQuad(
          canvas,
          image: image,
          sourceRect: sideSource!,
          world: world,
          heights: [top, top, 0, 0],
        );
      } else {
        _drawWorldSolidQuad(
          canvas,
          world: world,
          heights: [top, top, 0, 0],
          color: const Color(0xFF62432F),
        );
      }
    }

    // Painter order is far to near; the near cap is added last so it cannot
    // repaint a visible section of the bank.
    drawEndCap(farEnd: true);
    for (
      var distance = bank.endDistance;
      distance > bank.startDistance + .001;
      distance = math.max(bank.startDistance, distance - sectionLength)
    ) {
      final endDistance = distance;
      final startDistance = math.max(
        bank.startDistance,
        distance - sectionLength,
      );
      final startState = _routeStateAt(startDistance, _completedTurnCount);
      final endState = _routeStateAt(endDistance, _completedTurnCount);
      final startRight = _right(startState.heading);
      final endRight = _right(endState.heading);
      final innerStart = startState.position + startRight * bank.innerOffset;
      final innerEnd = endState.position + endRight * bank.innerOffset;
      final outerStart = startState.position + startRight * bank.outerOffset;
      final outerEnd = endState.position + endRight * bank.outerOffset;
      final top = obstaclePalletHeightMeters;
      final innerFace = bank.outerOffset < 0
          ? [innerStart, innerEnd, innerEnd, innerStart]
          : [innerEnd, innerStart, innerStart, innerEnd];
      final outerFace = bank.outerOffset < 0
          ? [outerEnd, outerStart, outerStart, outerEnd]
          : [outerStart, outerEnd, outerEnd, outerStart];
      final topFace = bank.outerOffset < 0
          ? [innerStart, outerStart, outerEnd, innerEnd]
          : [innerEnd, outerEnd, outerStart, innerStart];
      if (image != null) {
        _drawWorldImageQuad(
          canvas,
          image: image,
          sourceRect: frontSource!,
          world: innerFace,
          heights: [top, top, 0, 0],
          cullBackFace: true,
        );
        _drawWorldImageQuad(
          canvas,
          image: image,
          sourceRect: sideSource!,
          world: outerFace,
          heights: [top, top, 0, 0],
          cullBackFace: true,
        );
        _drawWorldImageQuad(
          canvas,
          image: image,
          sourceRect: topSource!,
          world: topFace,
          heights: [top, top, top, top],
          cullBackFace: true,
        );
      } else {
        _drawWorldSolidQuad(
          canvas,
          world: innerFace,
          heights: [top, top, 0, 0],
          color: const Color(0xFF8B5C3C),
        );
        _drawWorldSolidQuad(
          canvas,
          world: outerFace,
          heights: [top, top, 0, 0],
          color: const Color(0xFF62432F),
        );
        _drawWorldSolidQuad(
          canvas,
          world: topFace,
          heights: [top, top, top, top],
          color: const Color(0xFFB47C4E),
        );
      }
      if (startDistance >= distance - .001) break;
    }
    drawEndCap(farEnd: false);
  }

  void _drawObstacleSolidBox(
    Canvas canvas, {
    required Offset center,
    required double heading,
    required double width,
    required double height,
    required double depth,
    required Color color,
  }) {
    final forward = _forward(heading);
    final right = _right(heading);
    final near = center - forward * depth / 2;
    final far = center + forward * depth / 2;
    final nearLeft = near - right * width / 2;
    final nearRight = near + right * width / 2;
    final farLeft = far - right * width / 2;
    final farRight = far + right * width / 2;
    _drawWorldSolidQuad(
      canvas,
      world: [nearLeft, nearRight, nearRight, nearLeft],
      heights: [height, height, 0, 0],
      color: color,
    );
    _drawWorldSolidQuad(
      canvas,
      world: [nearLeft, farLeft, farLeft, nearLeft],
      heights: [height, height, 0, 0],
      color: color.withValues(alpha: .82),
    );
    _drawWorldSolidQuad(
      canvas,
      world: [nearLeft, nearRight, farRight, farLeft],
      heights: [height, height, height, height],
      color: color.withValues(alpha: .92),
    );
  }

  void _drawConstructionTrench(
    Canvas canvas,
    TempleRunObstacle obstacle, {
    required bool fullRoad,
  }) {
    final startState = _routeStateAt(
      obstacle.distanceMeters,
      _completedTurnCount,
    );
    final length = TempleRunRules.fullRoadGapWidthMeters;
    final endState = _routeStateAt(
      obstacle.distanceMeters + length,
      _completedTurnCount,
    );
    final right = _right(startState.heading);
    final centerOffset = obstacle.spansFullRoad
        ? 0.0
        : (obstacle.lane - TempleRunRules.centerLane) * (_roadWorldWidth / 3);
    final trenchWidth = _obstacleWidthWorld(obstacle, fullRoad: fullRoad);
    final first = startState.position + right * centerOffset;
    final second = endState.position + right * centerOffset;
    const depthMeters = .34;
    _drawWorldRoadQuad(
      canvas,
      first,
      second,
      startState.heading,
      const Color(0xFF382B2E),
      roadCenterOffset: 0,
      roadWidth: trenchWidth,
      textured: false,
      height: -depthMeters,
    );
    final half = trenchWidth / 2;
    final leftStart = first - right * half;
    final rightStart = first + right * half;
    final leftEnd = second - right * half;
    final rightEnd = second + right * half;

    // A narrow asphalt lip keeps the opening grounded without painting
    // warning stripes across the jumpable gap.
    final lip = .05;
    _drawWorldRoadQuad(
      canvas,
      first,
      second,
      startState.heading,
      const Color(0xFF4A4642),
      roadCenterOffset: -half - lip / 2,
      roadWidth: lip,
      textured: false,
    );
    _drawWorldRoadQuad(
      canvas,
      first,
      second,
      startState.heading,
      const Color(0xFF4A4642),
      roadCenterOffset: half + lip / 2,
      roadWidth: lip,
      textured: false,
    );

    void drawProjectedQuad(List<_ProjectedWorldPoint?> points, Color color) {
      if (points.any((point) => point == null)) return;
      final resolved = points.cast<_ProjectedWorldPoint>();
      final path = Path()
        ..moveTo(resolved.first.point.dx, resolved.first.point.dy);
      for (final point in resolved.skip(1)) {
        path.lineTo(point.point.dx, point.point.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    // Give the opening an actual lip and inner walls. The dark floor remains
    // on the route plane for collision alignment, while these lowered faces
    // make the break read as a shallow trench instead of a painted rectangle.
    final leftStartBottom = _projectWorld(leftStart, height: -depthMeters);
    final rightStartBottom = _projectWorld(rightStart, height: -depthMeters);
    final leftEndBottom = _projectWorld(leftEnd, height: -depthMeters);
    final rightEndBottom = _projectWorld(rightEnd, height: -depthMeters);
    drawProjectedQuad(<_ProjectedWorldPoint?>[
      _projectWorld(leftStart),
      _projectWorld(rightStart),
      rightStartBottom,
      leftStartBottom,
    ], const Color(0xFF6B4D3A));
    drawProjectedQuad(<_ProjectedWorldPoint?>[
      _projectWorld(leftEnd),
      leftEndBottom,
      rightEndBottom,
      _projectWorld(rightEnd),
    ], const Color(0xFF80604A));
    drawProjectedQuad(<_ProjectedWorldPoint?>[
      _projectWorld(leftStart),
      _projectWorld(leftEnd),
      leftEndBottom,
      leftStartBottom,
    ], const Color(0xFF292125));
    drawProjectedQuad(<_ProjectedWorldPoint?>[
      _projectWorld(rightStart),
      rightStartBottom,
      rightEndBottom,
      _projectWorld(rightEnd),
    ], const Color(0xFF211B20));
  }

  static double _snapLogicalPixel(double value) => value.roundToDouble();

  void _drawCollectible(
    Canvas canvas,
    _ProjectedWorldPoint point,
    _TempleRunCollectibleKind kind,
  ) {
    final image = _imageFor(switch (kind) {
      _TempleRunCollectibleKind.coin => coinAsset,
      _TempleRunCollectibleKind.magnet => magnetAsset,
      _TempleRunCollectibleKind.shield => shieldAsset,
      _TempleRunCollectibleKind.boost => boostAsset,
    });
    final sizePx = math.max(7.0, point.scale * .58);
    if (image != null) {
      final rect = Rect.fromCenter(
        center: point.point - Offset(0, sizePx * .6),
        width: sizePx,
        height: sizePx,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.none,
      );
      return;
    }
    final center = point.point - Offset(0, sizePx * .62);
    switch (kind) {
      case _TempleRunCollectibleKind.coin:
        final diamond = Path()
          ..moveTo(center.dx, center.dy - sizePx * .48)
          ..lineTo(center.dx + sizePx * .32, center.dy)
          ..lineTo(center.dx, center.dy + sizePx * .48)
          ..lineTo(center.dx - sizePx * .32, center.dy)
          ..close();
        canvas.drawPath(diamond, Paint()..color = const Color(0xFFF1C84B));
        canvas.drawPath(
          diamond,
          Paint()
            ..color = const Color(0xD7794D1C)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, sizePx * .08),
        );
      case _TempleRunCollectibleKind.magnet:
        final paint = Paint()
          ..color = const Color(0xFF46C2B9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, sizePx * .16)
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
          Rect.fromCenter(
            center: center,
            width: sizePx * .72,
            height: sizePx * .72,
          ),
          math.pi,
          math.pi,
          false,
          paint,
        );
      case _TempleRunCollectibleKind.shield:
        final shield = Path()
          ..moveTo(center.dx, center.dy - sizePx * .48)
          ..lineTo(center.dx + sizePx * .34, center.dy - sizePx * .25)
          ..lineTo(center.dx + sizePx * .26, center.dy + sizePx * .25)
          ..lineTo(center.dx, center.dy + sizePx * .46)
          ..lineTo(center.dx - sizePx * .26, center.dy + sizePx * .25)
          ..lineTo(center.dx - sizePx * .34, center.dy - sizePx * .25)
          ..close();
        canvas.drawPath(shield, Paint()..color = const Color(0xFF4AB2A7));
        canvas.drawPath(
          shield,
          Paint()
            ..color = const Color(0xFFF4CD61)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, sizePx * .08),
        );
      case _TempleRunCollectibleKind.boost:
        final boost = Paint()
          ..color = const Color(0xFFF0AF48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, sizePx * .18)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(center.dx - sizePx * .36, center.dy + sizePx * .2),
          Offset(center.dx + sizePx * .28, center.dy - sizePx * .2),
          boost,
        );
        canvas.drawLine(
          Offset(center.dx - sizePx * .28, center.dy + sizePx * .4),
          Offset(center.dx + sizePx * .36, center.dy),
          boost,
        );
    }
  }

  void _spawnPickupEffects({
    required Set<int> coinIndices,
    required Set<int> powerUpIndices,
  }) {
    if (coinIndices.isEmpty && powerUpIndices.isEmpty) return;
    final anchor = _pickupFeedbackAnchor();
    for (final _ in coinIndices) {
      _pickupEffects.add(
        _TempleRunPickupEffect(
          kind: _TempleRunCollectibleKind.coin,
          anchor: anchor,
        ),
      );
    }
    final powerUps = _course?.powerUps ?? const <TempleRunPowerUp>[];
    for (final index in powerUpIndices) {
      if (index < 0 || index >= powerUps.length) continue;
      final kind = switch (powerUps[index].kind) {
        TempleRunPowerUpKind.magnet => _TempleRunCollectibleKind.magnet,
        TempleRunPowerUpKind.shield => _TempleRunCollectibleKind.shield,
        TempleRunPowerUpKind.boost => _TempleRunCollectibleKind.boost,
      };
      _pickupEffects.add(_TempleRunPickupEffect(kind: kind, anchor: anchor));
    }
    if (_pickupEffects.length > _pickupEffectCap) {
      _pickupEffects.removeRange(0, _pickupEffects.length - _pickupEffectCap);
    }
  }

  Offset _pickupFeedbackAnchor() {
    final runner = _projectWorld(_runnerWorldPosition(), height: 1.0);
    if (runner == null) {
      return Offset(size.x / 2, _collisionY - size.y * .18);
    }
    return runner.point - Offset(0, size.x * .07);
  }

  void _drawPickupEffects(Canvas canvas) {
    for (
      var effectIndex = 0;
      effectIndex < _pickupEffects.length;
      effectIndex++
    ) {
      final effect = _pickupEffects[effectIndex];
      final progress = (effect.age / _pickupEffectDurationSeconds).clamp(
        0.0,
        1.0,
      );
      final alpha = (1 - progress * progress).clamp(0.0, 1.0);
      final eased = 1 - math.pow(1 - progress, 3).toDouble();
      final anchor = effect.anchor - Offset(0, size.y * .035 * eased);
      final color = switch (effect.kind) {
        _TempleRunCollectibleKind.coin => const Color(0xFFFFD05C),
        _TempleRunCollectibleKind.magnet => const Color(0xFF55D5CC),
        _TempleRunCollectibleKind.shield => const Color(0xFF74C9FF),
        _TempleRunCollectibleKind.boost => const Color(0xFFFFA848),
      };
      final radius =
          size.x *
          (effect.kind == _TempleRunCollectibleKind.coin ? .055 : .078) *
          (1 + eased * 1.15);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha * .95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size.x * .009)
        ..strokeCap = StrokeCap.square;
      canvas.drawCircle(
        anchor,
        radius * (.68 + eased * .3),
        Paint()
          ..color = color.withValues(alpha: alpha * .2)
          ..style = PaintingStyle.fill,
      );
      for (var rayIndex = 0; rayIndex < 8; rayIndex++) {
        final angle = rayIndex * math.pi / 4 + effectIndex * .13;
        final inner =
            anchor + Offset(math.cos(angle), math.sin(angle)) * radius * 1.15;
        final outer =
            anchor +
            Offset(math.cos(angle), math.sin(angle)) *
                radius *
                (1.55 + eased * .35);
        canvas.drawLine(inner, outer, paint);
      }
      if (effect.kind == _TempleRunCollectibleKind.coin) {
        final coin = Path()
          ..moveTo(anchor.dx, anchor.dy - radius * .72)
          ..lineTo(anchor.dx + radius * .48, anchor.dy)
          ..lineTo(anchor.dx, anchor.dy + radius * .72)
          ..lineTo(anchor.dx - radius * .48, anchor.dy)
          ..close();
        canvas.drawPath(
          coin,
          Paint()..color = color.withValues(alpha: alpha * .85),
        );
        canvas.drawPath(coin, paint);
        _drawPickupLabel(
          canvas,
          '+10',
          anchor - Offset(0, radius * 1.8 + effectIndex * size.y * .055),
          color.withValues(alpha: alpha),
        );
      } else {
        canvas.drawCircle(anchor, radius, paint);
        canvas.drawCircle(
          anchor,
          radius * (.45 + eased * .25),
          Paint()
            ..color = color.withValues(alpha: alpha * .45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, size.x * .006),
        );
        _drawPickupGlyph(
          canvas,
          anchor: anchor,
          radius: radius * .62,
          kind: effect.kind,
          color: color.withValues(alpha: alpha),
        );
        _drawPickupLabel(
          canvas,
          _pickupEffectLabel(effect.kind),
          anchor - Offset(0, radius * 1.55 + effectIndex * size.y * .055),
          color.withValues(alpha: alpha),
        );
      }
    }
  }

  void _drawPickupGlyph(
    Canvas canvas, {
    required Offset anchor,
    required double radius,
    required _TempleRunCollectibleKind kind,
    required Color color,
  }) {
    final glyph = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, size.x * .012)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case _TempleRunCollectibleKind.magnet:
        canvas.drawArc(
          Rect.fromCenter(
            center: anchor,
            width: radius * 1.45,
            height: radius * 1.45,
          ),
          math.pi,
          math.pi,
          false,
          glyph,
        );
        canvas.drawLine(
          anchor + Offset(-radius * .72, 0),
          anchor + Offset(-radius * .72, radius * .35),
          glyph,
        );
        canvas.drawLine(
          anchor + Offset(radius * .72, 0),
          anchor + Offset(radius * .72, radius * .35),
          glyph,
        );
      case _TempleRunCollectibleKind.shield:
        final shield = Path()
          ..moveTo(anchor.dx, anchor.dy - radius)
          ..lineTo(anchor.dx + radius * .72, anchor.dy - radius * .45)
          ..lineTo(anchor.dx + radius * .56, anchor.dy + radius * .55)
          ..lineTo(anchor.dx, anchor.dy + radius)
          ..lineTo(anchor.dx - radius * .56, anchor.dy + radius * .55)
          ..lineTo(anchor.dx - radius * .72, anchor.dy - radius * .45)
          ..close();
        canvas.drawPath(shield, glyph);
        canvas.drawLine(
          anchor + Offset(-radius * .42, 0),
          anchor + Offset(radius * .42, 0),
          glyph,
        );
        canvas.drawLine(
          anchor + Offset(0, -radius * .42),
          anchor + Offset(0, radius * .42),
          glyph,
        );
      case _TempleRunCollectibleKind.boost:
        final bolt = Path()
          ..moveTo(anchor.dx + radius * .18, anchor.dy - radius)
          ..lineTo(anchor.dx - radius * .46, anchor.dy + radius * .04)
          ..lineTo(anchor.dx - radius * .03, anchor.dy + radius * .04)
          ..lineTo(anchor.dx - radius * .24, anchor.dy + radius)
          ..lineTo(anchor.dx + radius * .52, anchor.dy - radius * .18)
          ..lineTo(anchor.dx + radius * .08, anchor.dy - radius * .18)
          ..close();
        canvas.drawPath(bolt, glyph);
      case _TempleRunCollectibleKind.coin:
        break;
    }
  }

  static String _pickupEffectLabel(_TempleRunCollectibleKind kind) =>
      switch (kind) {
        _TempleRunCollectibleKind.coin => '+10',
        _TempleRunCollectibleKind.magnet => 'MAGNET',
        _TempleRunCollectibleKind.shield => 'SHIELD',
        _TempleRunCollectibleKind.boost => 'BOOST',
      };

  void _drawPickupLabel(
    Canvas canvas,
    String label,
    Offset center,
    Color color,
  ) {
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontFamily: 'Galmuri',
          fontSize: math.max(12, size.x * .045),
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
          shadows: const [
            Shadow(
              color: Color(0xFF101B1B),
              blurRadius: 1,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final rect = Rect.fromCenter(
      center: center,
      width: text.width + size.x * .055,
      height: text.height + size.x * .025,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.x * .012)),
      Paint()..color = const Color(0xD51B2722),
    );
    text.paint(
      canvas,
      Offset(rect.left + (rect.width - text.width) / 2, rect.top + .5),
    );
  }

  void _drawRunner(Canvas canvas) {
    final jumping = TempleRunRules.isJumpActive(_jumpRemaining);
    final sliding = TempleRunRules.isSlideActive(_slideRemaining);
    final jumpProgress = jumping
        ? (1 - (_jumpRemaining / TempleRunRules.jumpDurationSeconds)).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final jumpLift = jumping
        ? math.sin(jumpProgress * math.pi) * size.y * .075
        : 0;
    final runnerProjection = _projectWorld(_runnerWorldPosition());
    final runnerX = runnerProjection?.point.dx ?? size.x / 2;
    final runnerGroundY = runnerProjection?.point.dy ?? _collisionY;
    final runnerBottom = runnerGroundY - jumpLift + (sliding ? 3 : 0);
    final width = size.x * (_runnerDisplayWidth / TempleRunRules.logicalWidth);
    final height = width * (_runnerDisplayHeight / _runnerDisplayWidth);
    final image = jumping
        ? _imageFor(runnerJumpAsset)
        : sliding
        ? _imageFor(runnerSlideAsset)
        : _imageFor(runnerRunAsset);
    final jumpArc = jumping ? math.sin(jumpProgress * math.pi) : 0.0;
    final shadowScale = 1 - .38 * jumpArc;
    final shadowCenter = Offset(
      _snapLogicalPixel(runnerX),
      _snapLogicalPixel(runnerGroundY + 2),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: shadowCenter,
        width: math.max(1.0, (width * .48 * shadowScale).roundToDouble()),
        height: math.max(1.0, (width * .13 * shadowScale).roundToDouble()),
      ),
      Paint()
        ..color = Color.fromARGB(
          (0x58 * (1 - .46 * jumpArc)).round(),
          18,
          22,
          24,
        ),
    );
    if (image != null) {
      final sourceFrameWidth = image == _imageFor(runnerRunAsset)
          ? image.width / 4.0
          : image.width.toDouble();
      final sourceFrameHeight = image.height.toDouble();
      final frame = _runnerFrame.floor() % 4;
      final sourceBaseline = math.min(
        image == _imageFor(runnerRunAsset)
            ? _runnerRunSourceFeetBaselines[frame]
            : jumping
            ? _runnerJumpSourceFeetBaseline
            : _runnerSlideSourceFeetBaseline,
        sourceFrameHeight,
      );
      final baselineGap =
          height * (1 - sourceBaseline / _runnerSourceFrameHeight);
      final snappedX = _snapLogicalPixel(runnerX);
      final snappedBottom = _snapLogicalPixel(runnerBottom + baselineGap);
      final rect = Rect.fromLTWH(
        snappedX - width / 2,
        snappedBottom - height,
        width,
        height,
      );
      if (image == _imageFor(runnerRunAsset)) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(
            frame * sourceFrameWidth,
            0,
            sourceFrameWidth,
            sourceFrameHeight,
          ),
          rect,
          Paint()..filterQuality = FilterQuality.none,
        );
      } else {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          Paint()..filterQuality = FilterQuality.none,
        );
      }
      _drawRunnerEffects(
        canvas,
        center: Offset(runnerX, runnerBottom - height * .45),
        width: width,
        height: height,
      );
      return;
    }
    _drawPrototypeRunner(
      canvas,
      centerX: runnerX,
      bottom: runnerBottom,
      groundY: runnerGroundY,
      width: width,
      height: height,
      jumping: jumping,
      sliding: sliding,
      jumpProgress: jumpProgress,
    );
    _drawRunnerEffects(
      canvas,
      center: Offset(runnerX, runnerBottom - height * .45),
      width: width,
      height: height,
    );
  }

  void _drawRunnerEffects(
    Canvas canvas, {
    required Offset center,
    required double width,
    required double height,
  }) {
    if (_magnetVisible) {
      canvas.drawCircle(
        center,
        width * .9,
        Paint()
          ..color = const Color(0xB8F0AA46)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, width * .035),
      );
    }
    if (_shieldVisible) {
      canvas.drawCircle(
        center,
        width * .68,
        Paint()
          ..color = const Color(0xB84AC6C0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, width * .045),
      );
    }
    if (_boostVisible) {
      final trail = Paint()
        ..color = const Color(0xD8F2B652)
        ..strokeWidth = math.max(2, width * .065)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center + Offset(-width * .2, height * .3),
        center + Offset(-width * .2, height * .72),
        trail,
      );
      canvas.drawLine(
        center + Offset(width * .2, height * .3),
        center + Offset(width * .2, height * .72),
        trail,
      );
    }
  }

  void _drawPrototypeRunner(
    Canvas canvas, {
    required double centerX,
    required double bottom,
    required double groundY,
    required double width,
    required double height,
    required bool jumping,
    required bool sliding,
    required double jumpProgress,
  }) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, groundY + 3),
        width: width * .7,
        height: jumping ? 4 : 7,
      ),
      Paint()
        ..color = jumping ? const Color(0x55201916) : const Color(0x8A201916),
    );
    if (sliding) {
      final body = Paint()..color = const Color(0xFFE0C18D);
      final skin = Paint()..color = const Color(0xFFC88755);
      final limb = Paint()
        ..color = const Color(0xFF3C4D3C)
        ..strokeWidth = math.max(4, width * .09)
        ..strokeCap = StrokeCap.round;
      final y = bottom - height * .28;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(centerX, y),
          width: width * .78,
          height: height * .24,
        ),
        body,
      );
      canvas.drawCircle(
        Offset(centerX + width * .3, y - width * .1),
        width * .14,
        skin,
      );
      canvas.drawCircle(
        Offset(centerX + width * .3, y - width * .18),
        width * .15,
        Paint()..color = const Color(0xFF2A211C),
      );
      canvas.drawLine(
        Offset(centerX - width * .18, y + 5),
        Offset(centerX - width * .4, bottom - 7),
        limb,
      );
      canvas.drawLine(
        Offset(centerX + width * .05, y + 5),
        Offset(centerX + width * .35, bottom - 7),
        limb,
      );
      _drawScarf(canvas, Offset(centerX + width * .05, y - 5), width);
      return;
    }
    final shoulderY = bottom - height * .55;
    final hipY = bottom - height * .22;
    final head = Offset(centerX, bottom - height * .83);
    final skin = Paint()..color = const Color(0xFFC88755);
    final shirt = Paint()..color = const Color(0xFFE0C18D);
    final backpack = Paint()..color = const Color(0xFF805A3B);
    final hair = Paint()..color = const Color(0xFF2A211C);
    final pants = Paint()
      ..color = const Color(0xFF3C4D3C)
      ..strokeWidth = math.max(5, width * .1)
      ..strokeCap = StrokeCap.round;
    final limbs = Paint()
      ..color = skin.color
      ..strokeWidth = math.max(3, width * .07)
      ..strokeCap = StrokeCap.round;
    final shoes = Paint()
      ..color = const Color(0xFF2C251F)
      ..strokeWidth = math.max(4, width * .08)
      ..strokeCap = StrokeCap.round;
    final torso = Path()
      ..moveTo(centerX - width * .22, shoulderY)
      ..lineTo(centerX + width * .22, shoulderY)
      ..lineTo(centerX + width * .15, hipY)
      ..lineTo(centerX - width * .15, hipY)
      ..close();
    canvas.drawPath(torso, shirt);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, shoulderY + height * .13),
          width: width * .3,
          height: height * .26,
        ),
        const Radius.circular(3),
      ),
      backpack,
    );
    canvas.drawCircle(head, width * .14, skin);
    canvas.drawCircle(
      Offset(head.dx, head.dy - width * .05),
      width * .15,
      hair,
    );
    _drawScarf(canvas, Offset(centerX - width * .08, shoulderY + 1), width);
    final phase = _runnerFrame.floor() % 4;
    final stride = phase == 0
        ? -1.0
        : phase == 1
        ? -.3
        : phase == 2
        ? 1.0
        : .3;
    if (jumping) {
      final tuck = .5 + .2 * math.sin(jumpProgress * math.pi);
      final leftKnee = Offset(
        centerX - width * (.16 + tuck * .1),
        hipY + height * .16,
      );
      final rightKnee = Offset(
        centerX + width * (.16 + tuck * .1),
        hipY + height * .12,
      );
      canvas.drawLine(Offset(centerX - width * .08, hipY), leftKnee, pants);
      canvas.drawLine(leftKnee, leftKnee + Offset(-width * .12, 0), shoes);
      canvas.drawLine(Offset(centerX + width * .08, hipY), rightKnee, pants);
      canvas.drawLine(rightKnee, rightKnee + Offset(width * .12, 0), shoes);
    } else {
      final leftKnee = Offset(
        centerX - width * (.07 + stride * .08),
        hipY + height * .2,
      );
      final rightKnee = Offset(
        centerX + width * (.07 - stride * .08),
        hipY + height * .2,
      );
      final leftFoot = Offset(
        centerX - width * (.1 + stride * .22),
        bottom - 2,
      );
      final rightFoot = Offset(
        centerX + width * (.1 - stride * .22),
        bottom - 2,
      );
      canvas.drawLine(Offset(centerX - width * .08, hipY), leftKnee, pants);
      canvas.drawLine(leftKnee, leftFoot, pants);
      canvas.drawLine(Offset(centerX + width * .08, hipY), rightKnee, pants);
      canvas.drawLine(rightKnee, rightFoot, pants);
      canvas.drawLine(leftFoot, leftFoot + Offset(-width * .08, 0), shoes);
      canvas.drawLine(rightFoot, rightFoot + Offset(width * .08, 0), shoes);
    }
    final swing = stride * width * .14;
    canvas.drawLine(
      Offset(centerX - width * .2, shoulderY + 2),
      Offset(centerX - width * .3 - swing, shoulderY + height * .2),
      limbs,
    );
    canvas.drawLine(
      Offset(centerX + width * .2, shoulderY + 2),
      Offset(centerX + width * .3 + swing, shoulderY + height * .16),
      limbs,
    );
  }

  void _drawScarf(Canvas canvas, Offset origin, double width) {
    final scarf = Paint()..color = const Color(0xFF2B9B96);
    canvas.drawRect(
      Rect.fromLTWH(
        origin.dx - width * .035,
        origin.dy,
        width * .07,
        width * .22,
      ),
      scarf,
    );
    canvas.drawPath(
      Path()
        ..moveTo(origin.dx, origin.dy + width * .06)
        ..quadraticBezierTo(
          origin.dx + width * .25,
          origin.dy,
          origin.dx + width * .34,
          origin.dy + width * .14,
        )
        ..lineTo(origin.dx + width * .16, origin.dy + width * .12)
        ..close(),
      scarf,
    );
  }

  void _drawHomeGate(Canvas canvas) {
    final image = _imageFor(homeGateAsset);
    if (image == null) return;
    final state = _routeStateAt(_distanceMeters + 8, _completedTurnCount);
    final right = _right(state.heading);
    final center = state.position;
    final halfWidth = 2.5;
    final height = 4.8;
    final bottomLeft = _projectWorld(center - right * halfWidth);
    final bottomRight = _projectWorld(center + right * halfWidth);
    final topLeft = _projectWorld(center - right * halfWidth, height: height);
    final topRight = _projectWorld(center + right * halfWidth, height: height);
    if (bottomLeft == null ||
        bottomRight == null ||
        topLeft == null ||
        topRight == null) {
      return;
    }
    _drawImageQuad(canvas, image, [
      topLeft.point,
      topRight.point,
      bottomRight.point,
      bottomLeft.point,
    ], sourceBottomPadding: _homeGateFootprint.bottomPadding);
  }

  void _drawPursuers(Canvas canvas, {required double departureProgress}) {
    _pursuerScreenBounds.clear();
    final runAtlas = _imageFor(pursuersRunAsset);
    final image = runAtlas ?? _imageFor(pursuersAsset);
    if (image == null) return;
    final frame = runAtlas == null ? 0 : _pursuerRunPhase.floor() % 6;
    final frameOffset = Offset(
      frame % 3 * _pursuerRunFrameWidth,
      frame ~/ 3 * _pursuerRunFrameHeight,
    );
    final leftSource = runAtlas == null
        ? _leftPursuerSource
        : _leftPursuerRunSource.shift(frameOffset);
    final rightSource = runAtlas == null
        ? _rightPursuerSource
        : _rightPursuerRunSource.shift(frameOffset);
    // Ease the pair back behind the camera as soon as the round starts. The
    // countdown still uses the full authored size; after departure the pair
    // becomes a smaller, fading silhouette below the viewport instead of
    // colliding visually with the runner.
    final retreat = departureProgress.clamp(0.0, 1.0);
    final easedRetreat = retreat * retreat * (3 - 2 * retreat);
    final closeDisplayHeight = math.min(size.y * .16, size.x * .58 * 272 / 432);
    final displayHeight =
        closeDisplayHeight * ui.lerpDouble(1.0, .76, easedRetreat)!;
    final scale = displayHeight / 272;
    final pairWidth = (leftSource.width + rightSource.width) * scale;
    final pairLeft = (size.x - pairWidth) / 2;
    final feetY = ui.lerpDouble(size.y * .978, size.y * 1.24, easedRetreat)!;
    final bottomPadding = runAtlas == null ? 0.0 : 8.0;
    final leftDestination = Rect.fromLTWH(
      pairLeft,
      feetY + bottomPadding * scale - leftSource.height * scale,
      leftSource.width * scale,
      leftSource.height * scale,
    );
    final rightDestination = Rect.fromLTWH(
      pairLeft + leftDestination.width,
      feetY + bottomPadding * scale - rightSource.height * scale,
      rightSource.width * scale,
      rightSource.height * scale,
    );
    final viewport = Rect.fromLTWH(0, 0, size.x, size.y);
    final alpha = ((1 - easedRetreat) * 255).round().clamp(0, 255);
    final shadowPaint = Paint()
      ..color = Color.fromARGB((alpha * .31).round(), 34, 27, 22);
    for (final destination in [leftDestination, rightDestination]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(destination.center.dx, feetY + scale * 3),
          width: destination.width * .48,
          height: math.max(2.0, displayHeight * .035),
        ),
        shadowPaint,
      );
    }
    for (final destination in [leftDestination, rightDestination]) {
      final bounds = destination.intersect(viewport);
      if (!bounds.isEmpty) _pursuerScreenBounds.add(bounds);
    }
    canvas.save();
    canvas.clipRect(viewport);
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..colorFilter = ColorFilter.mode(
        Color.fromARGB(alpha, 255, 255, 255),
        BlendMode.modulate,
      );
    canvas.drawImageRect(image, leftSource, leftDestination, paint);
    canvas.drawImageRect(image, rightSource, rightDestination, paint);
    canvas.restore();
  }

  _ProjectedWorldPoint? _projectWorld(Offset world, {double height = 0}) {
    final camera = _cameraPoint(world, height: height);
    if (camera.depth < _nearClipMeters || camera.depth > _farClipMeters) {
      return null;
    }
    return _projectCameraPoint(camera);
  }

  _CameraPoint _cameraPoint(Offset world, {double height = 0}) {
    final relative = world - _cameraPosition;
    final forward = _forward(_cameraHeading);
    final right = _right(_cameraHeading);
    final depth = relative.dx * forward.dx + relative.dy * forward.dy;
    final lateral = relative.dx * right.dx + relative.dy * right.dy;
    return _CameraPoint(lateral: lateral, depth: depth, height: height);
  }

  _ProjectedWorldPoint _projectCameraPoint(_CameraPoint camera) {
    final scale = _screenScale(camera.depth);
    final groundY = _groundY(camera.depth);
    return _ProjectedWorldPoint(
      point: Offset(
        size.x / 2 + camera.lateral * scale,
        groundY - camera.height * scale,
      ),
      depth: camera.depth,
      scale: scale,
    );
  }

  double _screenScale(double depth) {
    final focal = _focalLength * (_cameraTargetDepth / _cameraBackMeters);
    return focal / depth.clamp(_nearClipMeters, _farClipMeters);
  }

  double _groundY(double depth) {
    return _horizonY + _cameraHeightMeters * _screenScale(depth);
  }

  double get _focalLength => size.x * 1.23;

  double get _cameraHeightMeters {
    final previousNaturalHeight =
        (_collisionY - size.y * .29) * _cameraBackMeters / _focalLength;
    return previousNaturalHeight < 5.0 ? previousNaturalHeight : 5.0;
  }

  double get _horizonY =>
      _collisionY - _cameraHeightMeters * _focalLength / _cameraBackMeters;

  double get _collisionY => size.y * .884;
}
