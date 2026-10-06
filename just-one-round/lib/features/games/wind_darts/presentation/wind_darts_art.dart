import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';

abstract final class WindDartsArtAssets {
  static const pubInterior = 'assets/images/wind_darts/pub_interior.png';
  static const boardFace = 'assets/images/wind_darts/board_face.png';
  static const boardNumbers = 'assets/images/wind_darts/board_numbers.png';
  static const dartAtlas = 'assets/images/wind_darts/dart_atlas.png';
  static const scoreParchment = 'assets/images/wind_darts/score_parchment.png';
  static const aimGaugeFrame = 'assets/images/wind_darts/aim_gauge_frame.png';
  static const aimGaugeFill = 'assets/images/wind_darts/aim_gauge_fill.png';

  static const assetPaths = <String>[
    pubInterior,
    boardFace,
    boardNumbers,
    dartAtlas,
    scoreParchment,
    aimGaugeFrame,
    aimGaugeFill,
  ];

  static const flameImagePaths = <String>[
    'wind_darts/pub_interior.png',
    'wind_darts/board_face.png',
    'wind_darts/board_numbers.png',
    'wind_darts/dart_atlas.png',
    'wind_darts/score_parchment.png',
    'wind_darts/aim_gauge_frame.png',
    'wind_darts/aim_gauge_fill.png',
  ];
}

class WindDartsArtImages {
  const WindDartsArtImages({
    required this.pubInterior,
    required this.boardFace,
    required this.boardNumbers,
    required this.dartAtlas,
    required this.scoreParchment,
    required this.aimGaugeFrame,
    required this.aimGaugeFill,
  });

  factory WindDartsArtImages.fromList(List<ui.Image> images) {
    if (images.length != WindDartsArtAssets.assetPaths.length) {
      throw ArgumentError.value(
        images.length,
        'images',
        'expected ${WindDartsArtAssets.assetPaths.length} images',
      );
    }
    return WindDartsArtImages(
      pubInterior: images[0],
      boardFace: images[1],
      boardNumbers: images[2],
      dartAtlas: images[3],
      scoreParchment: images[4],
      aimGaugeFrame: images[5],
      aimGaugeFill: images[6],
    );
  }

  final ui.Image pubInterior;
  final ui.Image boardFace;
  final ui.Image boardNumbers;
  final ui.Image dartAtlas;
  final ui.Image scoreParchment;
  final ui.Image aimGaugeFrame;
  final ui.Image aimGaugeFill;

  void dispose() {
    pubInterior.dispose();
    boardFace.dispose();
    boardNumbers.dispose();
    dartAtlas.dispose();
    scoreParchment.dispose();
    aimGaugeFrame.dispose();
    aimGaugeFill.dispose();
  }
}

abstract final class WindDartsArt {
  static const worldBoardScale = 0.45;
  static const worldBoardRadius =
      WindDartsRules.baseBoardRadius * worldBoardScale;
  static const boardFaceSourceSize = 576.0;
  static const boardFaceScoringRadius = 228.0;
  static const boardFaceOuterRadius = 280.0;
  static const boardNumberCellSize = 64.0;
  static const boardNumberOrbitRadius = 260.0;
  static const dartCellWidth = 96.0;
  static const dartCellHeight = 128.0;
  static const dartTipAnchor = Offset(48, 12);
  static const dartImageScale = 0.72;
  static const scoreParchmentSourceSize = Size(240, 320);
  static const aimGaugeFrameSourceSize = Size(640, 72);
  static const aimGaugeFillSourceSize = Size(608, 24);

  static final Paint _imagePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  static Future<WindDartsArtImages> loadFromBundle() async {
    final loaded = <ui.Image>[];
    try {
      for (final path in WindDartsArtAssets.assetPaths) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        loaded.add(frame.image);
      }
      return WindDartsArtImages.fromList(loaded);
    } catch (_) {
      for (final image in loaded) {
        image.dispose();
      }
      rethrow;
    }
  }

  static double boardScaleForRadius(double logicalBoardRadius) =>
      logicalBoardRadius / boardFaceScoringRadius;

  static double dartScaleForBoardRadius(double logicalBoardRadius) =>
      dartImageScale * logicalBoardRadius / WindDartsRules.baseBoardRadius;

  static double worldZoomForShotScale(double displayedShotScale) =>
      displayedShotScale / worldBoardScale;

  static double visualRotation(double boardAngle) => boardAngle + math.pi / 20;

  static double numberAngle(int index) => -math.pi / 2 + index * math.pi / 10;

  static Rect boardDestinationRect(Offset center, double logicalBoardRadius) {
    final side = boardFaceSourceSize * boardScaleForRadius(logicalBoardRadius);
    return Rect.fromCenter(center: center, width: side, height: side);
  }

  static Rect boardNumberSourceRect(int index) {
    if (index < 0 || index >= 20) {
      throw RangeError.range(index, 0, 19, 'index');
    }
    return Rect.fromLTWH(
      (index % 5) * boardNumberCellSize,
      (index ~/ 5) * boardNumberCellSize,
      boardNumberCellSize,
      boardNumberCellSize,
    );
  }

  static int boardNumberAtlasIndexForSector(int sectorIndex) {
    if (sectorIndex < 0 || sectorIndex >= WindDartsRules.sectorOrder.length) {
      throw RangeError.range(
        sectorIndex,
        0,
        WindDartsRules.sectorOrder.length - 1,
        'sectorIndex',
      );
    }
    return WindDartsRules.sectorOrder[sectorIndex] - 1;
  }

  static Rect boardNumberSourceRectForSector(int sectorIndex) =>
      boardNumberSourceRect(boardNumberAtlasIndexForSector(sectorIndex));

  static Rect dartSourceRect(int cell) {
    if (cell < 0 || cell > 1) {
      throw RangeError.range(cell, 0, 1, 'cell');
    }
    return Rect.fromLTWH(
      cell * dartCellWidth,
      0,
      dartCellWidth,
      dartCellHeight,
    );
  }

  static Offset toBoardLocal(Offset point, Offset center, double boardAngle) {
    return toBoardLocalVector(point - center, boardAngle);
  }

  static Offset toBoardLocalVector(Offset vector, double boardAngle) {
    final angle = -visualRotation(boardAngle);
    return Offset(
      vector.dx * math.cos(angle) - vector.dy * math.sin(angle),
      vector.dx * math.sin(angle) + vector.dy * math.cos(angle),
    );
  }

  static Offset worldOffsetForZoom(Offset screenOffset, double zoom) =>
      screenOffset / zoom;

  static Size backgroundSourceExtentForZoom({
    required Size imageSize,
    required Size viewportSize,
    required double zoom,
  }) {
    final coverScale = math.max(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    return Size(
      viewportSize.width / coverScale / zoom,
      viewportSize.height / coverScale / zoom,
    );
  }

  static void drawWorld(
    Canvas canvas, {
    required Offset pivot,
    required double zoom,
    Offset focusOffset = Offset.zero,
    required VoidCallback draw,
  }) {
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.scale(zoom);
    canvas.translate(-pivot.dx + focusOffset.dx, -pivot.dy + focusOffset.dy);
    draw();
    canvas.restore();
  }

  static void drawPubBackground(Canvas canvas, ui.Image image, Size size) {
    final scale = math.max(
      size.width / image.width,
      size.height / image.height,
    );
    final sourceWidth = size.width / scale;
    final sourceHeight = size.height / scale;
    final source = Rect.fromLTWH(
      (image.width - sourceWidth) / 2,
      (image.height - sourceHeight) / 2,
      sourceWidth,
      sourceHeight,
    );
    canvas.drawImageRect(image, source, Offset.zero & size, _imagePaint);
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = const Color(0x66140D07));
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.15),
          radius: 0.9,
          colors: [Color(0x00000000), Color(0xA4000000)],
          stops: [0.48, 1],
        ).createShader(bounds),
    );
  }

  static void drawScoreParchment(
    Canvas canvas,
    ui.Image image, {
    Offset offset = const Offset(10, 414),
    Size size = const Size(120, 160),
  }) {
    canvas.drawImageRect(
      image,
      Offset.zero & scoreParchmentSourceSize,
      offset & size,
      _imagePaint,
    );
  }

  static void drawAimGauge(
    Canvas canvas, {
    required ui.Image frame,
    required ui.Image fill,
    required double fraction,
    Offset offset = const Offset(20, 580),
    Size size = const Size(320, 36),
  }) {
    final clampedFraction = fraction.clamp(0.0, 1.0);
    canvas.drawImageRect(
      frame,
      Offset.zero & aimGaugeFrameSourceSize,
      offset & size,
      _imagePaint,
    );
    final fillSize = Size(size.width * 0.95, size.height / 3);
    final fillOffset = offset + Offset(size.width * 0.025, size.height / 3);
    final visibleWidth = fillSize.width * clampedFraction;
    if (visibleWidth <= 0) return;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        fillOffset.dx,
        fillOffset.dy,
        visibleWidth,
        fillSize.height,
      ),
    );
    canvas.drawImageRect(
      fill,
      Rect.fromLTWH(
        0,
        0,
        aimGaugeFillSourceSize.width * clampedFraction,
        aimGaugeFillSourceSize.height,
      ),
      Rect.fromLTWH(
        fillOffset.dx,
        fillOffset.dy,
        visibleWidth,
        fillSize.height,
      ),
      _imagePaint,
    );
    canvas.restore();
  }

  static void drawBoard({
    required Canvas canvas,
    required ui.Image boardFace,
    required ui.Image boardNumbers,
    required Offset center,
    required double logicalBoardRadius,
    required double boardAngle,
    ui.Image? dartAtlas,
    Offset? embeddedTip,
    Offset? embeddedTailDirection,
    double embeddedImpactProgress = 0,
  }) {
    final scale = boardScaleForRadius(logicalBoardRadius);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.drawCircle(
      Offset(0, 3 * scale),
      boardFaceOuterRadius * scale + 2,
      Paint()..color = const Color(0x660B0806),
    );
    canvas.rotate(visualRotation(boardAngle));
    canvas.drawImageRect(
      boardFace,
      const Rect.fromLTWH(0, 0, boardFaceSourceSize, boardFaceSourceSize),
      Rect.fromCenter(
        center: Offset.zero,
        width: boardFaceSourceSize * scale,
        height: boardFaceSourceSize * scale,
      ),
      _imagePaint,
    );
    for (var index = 0; index < 20; index++) {
      final angle = numberAngle(index);
      final numberCenter = Offset(
        math.cos(angle) * boardNumberOrbitRadius * scale,
        math.sin(angle) * boardNumberOrbitRadius * scale,
      );
      final cellSize = boardNumberCellSize * scale;
      canvas.drawImageRect(
        boardNumbers,
        boardNumberSourceRectForSector(index),
        Rect.fromCenter(
          center: numberCenter,
          width: cellSize,
          height: cellSize,
        ),
        _imagePaint,
      );
    }
    if (dartAtlas != null && embeddedTip != null) {
      drawImpactContact(
        canvas,
        tip: embeddedTip,
        boardScale: scale,
        progress: embeddedImpactProgress,
      );
      drawDart(
        canvas,
        atlas: dartAtlas,
        cell: 1,
        tip: embeddedTip,
        tailDirection: embeddedTailDirection ?? embeddedTip,
        scale: dartScaleForBoardRadius(logicalBoardRadius),
      );
    }
    canvas.restore();
  }

  /// A small puncture shadow and warm metal glint make the true dart tip
  /// readable without obscuring the standard scoring rings.
  static void drawImpactContact(
    Canvas canvas, {
    required Offset tip,
    required double boardScale,
    double progress = 0,
  }) {
    final t = progress.clamp(0.0, 1.0);
    final fade = 1 - t;
    final pulse = 1 + math.sin(t * math.pi * 3) * 0.12 * fade;
    final markerRadius = 14 * boardScale * pulse;
    canvas.drawCircle(
      tip + Offset(0, boardScale * 1.1),
      3.2 * boardScale,
      Paint()..color = const Color(0xA0180D07).withAlpha((190 * fade).round()),
    );
    canvas.drawCircle(
      tip,
      markerRadius,
      Paint()
        ..color = const Color(0xD6E5B46B).withAlpha((214 * fade).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, boardScale * 2.0),
    );
  }

  static void drawDart(
    Canvas canvas, {
    required ui.Image atlas,
    required int cell,
    required Offset tip,
    required Offset tailDirection,
    required double scale,
  }) {
    if (!scale.isFinite || scale <= 0) return;
    final direction = _unitVector(tailDirection);
    final rotation = math.atan2(direction.dy, direction.dx) - math.pi / 2;
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(rotation);
    canvas.drawImageRect(
      atlas,
      dartSourceRect(cell),
      Rect.fromLTWH(
        -dartTipAnchor.dx * scale,
        -dartTipAnchor.dy * scale,
        dartCellWidth * scale,
        dartCellHeight * scale,
      ),
      _imagePaint,
    );
    canvas.restore();
  }

  static Offset _unitVector(Offset vector) {
    final distance = vector.distance;
    if (!distance.isFinite || distance < 0.001) return const Offset(0, 1);
    return vector / distance;
  }
}
