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
  static const opponentVictory =
      'assets/images/western_duel/first_person/opponent_victory_v14/sheet-transparent.png';
  static const victorySmoke =
      'assets/images/western_duel/fx/victory_smoke_v14/sheet-transparent.png';

  static const assetPaths = <String>[
    pubInterior,
    boardFace,
    boardNumbers,
    dartAtlas,
    scoreParchment,
    aimGaugeFrame,
    aimGaugeFill,
    opponentVictory,
    victorySmoke,
  ];

  static const flameImagePaths = <String>[
    'wind_darts/pub_interior.png',
    'wind_darts/board_face.png',
    'wind_darts/board_numbers.png',
    'wind_darts/dart_atlas.png',
    'wind_darts/score_parchment.png',
    'wind_darts/aim_gauge_frame.png',
    'wind_darts/aim_gauge_fill.png',
    'western_duel/first_person/opponent_victory_v14/sheet-transparent.png',
    'western_duel/fx/victory_smoke_v14/sheet-transparent.png',
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
    required this.opponentVictory,
    required this.victorySmoke,
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
      opponentVictory: images[7],
      victorySmoke: images[8],
    );
  }

  final ui.Image pubInterior;
  final ui.Image boardFace;
  final ui.Image boardNumbers;
  final ui.Image dartAtlas;
  final ui.Image scoreParchment;
  final ui.Image aimGaugeFrame;
  final ui.Image aimGaugeFill;
  final ui.Image opponentVictory;
  final ui.Image victorySmoke;

  void dispose() {
    pubInterior.dispose();
    boardFace.dispose();
    boardNumbers.dispose();
    dartAtlas.dispose();
    scoreParchment.dispose();
    aimGaugeFrame.dispose();
    aimGaugeFill.dispose();
    opponentVictory.dispose();
    victorySmoke.dispose();
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
  static final Paint _goldDartPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none
    ..colorFilter = const ColorFilter.mode(
      Color(0x99FFD45A),
      BlendMode.srcATop,
    );

  static const _gold = Color(0xFFFFC84A);
  static const _goldLight = Color(0xFFFFF0A6);
  static const _impactAmber = Color(0xFFFFB52E);
  static const _impactOrangeRed = Color(0xFFE85B32);
  static const _impactTeal = Color(0xFF55D8C7);
  static const _impactCream = Color(0xFFFFE8B7);
  static const _impactRed = Color(0xFFD94332);

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
    bool embeddedGoldenDart = false,
    double embeddedImpactProgress = 0,
    WindDartsImpactKind? embeddedImpactKind,
    double embeddedImpactElapsed = 0,
    double embeddedImpactRadiusScale = 1,
    Rect? embeddedImpactClipRect,
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
    canvas.restore();

    if (dartAtlas == null || embeddedTip == null) return;

    final rotation = visualRotation(boardAngle);
    final rotatedTip = center + _rotateVector(embeddedTip, rotation);
    if (embeddedImpactKind != null) {
      drawImpactBurst(
        canvas,
        center: rotatedTip,
        kind: embeddedImpactKind,
        elapsed: embeddedImpactElapsed,
        radiusScale: embeddedImpactRadiusScale,
        golden: embeddedGoldenDart,
        clipRect: embeddedImpactClipRect,
      );
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
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
      golden: embeddedGoldenDart,
      goldenTrail: false,
    );
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
    bool golden = false,
    bool goldenTrail = true,
  }) {
    if (!scale.isFinite || scale <= 0) return;
    final direction = _unitVector(tailDirection);
    final rotation = math.atan2(direction.dy, direction.dx) - math.pi / 2;
    if (golden) {
      drawGoldenHalo(canvas, tip: tip, scale: scale, steady: !goldenTrail);
      drawGoldenTrail(
        canvas,
        tip: tip,
        tailDirection: direction,
        scale: scale,
        trailSegments: goldenTrail,
      );
    }
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
      golden ? _goldDartPaint : _imagePaint,
    );
    canvas.restore();
  }

  static void drawGoldenHalo(
    Canvas canvas, {
    required Offset tip,
    required double scale,
    bool steady = false,
  }) {
    final radius = scale * (steady ? 8.0 : 11.0);
    final outerPaint = Paint()
      ..isAntiAlias = true
      ..color = _gold.withAlpha(steady ? 80 : 105)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, scale * (steady ? 2.0 : 2.6));
    canvas.drawCircle(tip, radius * 1.65, outerPaint);
    canvas.drawCircle(
      tip,
      radius,
      Paint()
        ..isAntiAlias = true
        ..color = _goldLight.withAlpha(steady ? 85 : 125),
    );
  }

  static void drawGoldenTrail(
    Canvas canvas, {
    required Offset tip,
    required Offset tailDirection,
    required double scale,
    bool trailSegments = true,
  }) {
    final shaftEnd = tip + tailDirection * dartCellHeight * scale * 0.82;
    final shaftStart = tip + tailDirection * scale * 2.0;
    canvas.drawLine(
      shaftStart,
      shaftEnd,
      Paint()
        ..isAntiAlias = true
        ..color = _gold.withAlpha(130)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          math.max(1.0, scale * 2.5),
        )
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(2.0, scale * 8.0),
    );
    canvas.drawLine(
      shaftStart,
      shaftEnd,
      Paint()
        ..isAntiAlias = true
        ..color = _impactCream.withAlpha(220)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, scale * 1.7),
    );
    final glint = tip + tailDirection * dartCellHeight * scale * 0.4;
    final perpendicular = Offset(-tailDirection.dy, tailDirection.dx);
    final glintRadius = math.max(1.5, scale * 3.0);
    final glintPaint = Paint()
      ..isAntiAlias = true
      ..color = _goldLight.withAlpha(220)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, scale * 1.25);
    canvas.drawLine(
      glint - perpendicular * glintRadius,
      glint + perpendicular * glintRadius,
      glintPaint,
    );
    canvas.drawLine(
      glint - tailDirection * glintRadius * 0.72,
      glint + tailDirection * glintRadius * 0.72,
      glintPaint,
    );
    if (!trailSegments) return;

    final segmentLength = dartCellHeight * scale * 0.22;
    final trailOffset = dartCellHeight * scale * 0.82;
    const opacities = [150, 92, 42];
    for (var index = 0; index < 3; index++) {
      final startDistance = trailOffset + segmentLength * (index * 0.9 + 0.25);
      final endDistance = startDistance + segmentLength * 0.72;
      final start = tip + tailDirection * startDistance;
      final end = tip + tailDirection * endDistance;
      canvas.drawLine(
        start,
        end,
        Paint()
          ..isAntiAlias = true
          ..color = _gold.withAlpha(opacities[index])
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.0, scale * (5.0 - index * 1.2)),
      );
      final sparkle =
          tip + tailDirection * (startDistance + segmentLength * 0.35);
      final sparkleRadius = math.max(0.8, scale * (1.8 - index * 0.35));
      final sparklePaint = Paint()
        ..isAntiAlias = true
        ..color = _goldLight.withAlpha(opacities[index]);
      canvas.drawCircle(sparkle, sparkleRadius, sparklePaint);
      final glintPaint = Paint()
        ..isAntiAlias = true
        ..color = _impactCream.withAlpha((230 - index * 48).clamp(0, 255));
      canvas.save();
      canvas.translate(sparkle.dx, sparkle.dy);
      canvas.rotate(math.atan2(tailDirection.dy, tailDirection.dx));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: math.max(2.0, scale * (5.0 - index * 0.8)),
          height: math.max(1.0, scale * (1.8 - index * 0.25)),
        ),
        glintPaint,
      );
      canvas.restore();
      if (index == 0) {
        canvas.drawLine(
          sparkle - Offset(sparkleRadius * 2.4, 0),
          sparkle + Offset(sparkleRadius * 2.4, 0),
          sparklePaint,
        );
        canvas.drawLine(
          sparkle - Offset(0, sparkleRadius * 2.4),
          sparkle + Offset(0, sparkleRadius * 2.4),
          sparklePaint,
        );
      }
    }
  }

  static void drawImpactBurst(
    Canvas canvas, {
    required Offset center,
    required WindDartsImpactKind kind,
    required double elapsed,
    double radiusScale = 1,
    bool golden = false,
    Rect? clipRect,
  }) {
    if (!radiusScale.isFinite || radiusScale <= 0) return;
    final time = elapsed.clamp(0.0, 1.0);
    if (time >= 0.7) return;

    final ringCount = switch (kind) {
      WindDartsImpactKind.double => 2,
      WindDartsImpactKind.triple => 3,
      WindDartsImpactKind.singleBull => 1,
      WindDartsImpactKind.doubleBull => 2,
      _ => 0,
    };
    final sparkCount = switch (kind) {
      WindDartsImpactKind.double => 8,
      WindDartsImpactKind.triple => 12,
      WindDartsImpactKind.doubleBull => 16,
      _ => 0,
    };
    final maxRadius = switch (kind) {
      WindDartsImpactKind.double => 44.0,
      WindDartsImpactKind.triple => 58.0,
      WindDartsImpactKind.singleBull => 60.0,
      WindDartsImpactKind.doubleBull => 76.0,
      _ => 0.0,
    };
    if (ringCount == 0 || maxRadius == 0) return;

    final ringColor = switch (kind) {
      WindDartsImpactKind.double => _impactAmber,
      WindDartsImpactKind.triple => _impactOrangeRed,
      WindDartsImpactKind.singleBull => _impactTeal,
      WindDartsImpactKind.doubleBull => _impactRed,
      _ => _impactAmber,
    };
    final waveT = ((time - 0.08) / 0.27).clamp(0.0, 1.0);
    final waveProgress = 1 - math.pow(1 - waveT, 2).toDouble();
    final waveFade = (1 - waveT).clamp(0.0, 1.0);
    final shardT = ((time - 0.35) / 0.35).clamp(0.0, 1.0);
    final shardProgress = 1 - math.pow(1 - shardT, 2).toDouble();
    final shardFade = (1 - shardT).clamp(0.0, 1.0);
    final radius = maxRadius * radiusScale;

    canvas.save();
    if (clipRect != null) canvas.clipRect(clipRect);
    if (golden) {
      canvas.drawCircle(
        center,
        radius * 1.1,
        Paint()
          ..isAntiAlias = true
          ..color = _gold.withAlpha(
            ((time < 0.35 ? 155 * waveFade : 155 * shardFade)).round(),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, radiusScale * 2.2),
      );
    }

    if (time < 0.08) {
      final flashFade = (1 - time / 0.08).clamp(0.0, 1.0);
      final flashRadius = radius * (0.12 + flashFade * 0.08);
      final rayPaint = Paint()
        ..isAntiAlias = true
        ..color = _impactCream.withAlpha((245 * flashFade).round())
        ..strokeCap = StrokeCap.square
        ..strokeWidth = math.max(2.4, radiusScale * 4.0);
      canvas.drawCircle(
        center,
        radius * 0.1,
        Paint()
          ..isAntiAlias = true
          ..color = _impactCream.withAlpha((245 * flashFade).round()),
      );
      for (var index = 0; index < 4; index++) {
        final angle = index * math.pi / 2;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * radius * 0.03,
          center + direction * flashRadius,
          rayPaint,
        );
      }
    }

    if (time >= 0.08 && time < 0.35 && kind == WindDartsImpactKind.singleBull) {
      canvas.drawCircle(
        center,
        radius * 0.5 * waveProgress,
        Paint()
          ..isAntiAlias = true
          ..color = _impactTeal.withAlpha((235 * waveFade).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, radiusScale * 3.2),
      );
      final rayLength = radius * 0.95 * waveProgress;
      for (var index = 0; index < 4; index++) {
        final angle = index * math.pi / 2;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * radius * 0.35,
          center + direction * rayLength,
          Paint()
            ..isAntiAlias = true
            ..color = _impactTeal.withAlpha((235 * waveFade).round())
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(1.8, radiusScale * 3.4),
        );
      }
    } else if (time >= 0.08 && time < 0.35) {
      for (var index = 0; index < ringCount; index++) {
        final ringProgress = (index + 1) / (ringCount + 1);
        final ringRadius = radius * (0.32 + ringProgress * 0.58) * waveProgress;
        final ringPaint = Paint()
          ..isAntiAlias = true
          ..color =
              (kind == WindDartsImpactKind.doubleBull && index == 0
                      ? _impactCream
                      : ringColor)
                  .withAlpha((235 * waveFade).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, radiusScale * 3.2);
        if (kind == WindDartsImpactKind.triple) {
          final ringRect = Rect.fromCircle(center: center, radius: ringRadius);
          final startAngle = index * 0.65 + 0.18;
          canvas.drawArc(
            ringRect,
            startAngle,
            math.pi * 1.55,
            false,
            ringPaint,
          );
          canvas.drawArc(
            ringRect,
            startAngle + math.pi,
            math.pi * 0.42,
            false,
            ringPaint,
          );
        } else {
          canvas.drawCircle(center, ringRadius, ringPaint);
        }
      }
      if (kind == WindDartsImpactKind.doubleBull) {
        canvas.drawCircle(
          center,
          radius * 0.16 * waveProgress,
          Paint()
            ..isAntiAlias = true
            ..color = _impactCream.withAlpha((245 * waveFade).round()),
        );
        final rayLength = radius * 0.95 * waveProgress;
        for (var index = 0; index < sparkCount; index++) {
          final angle = index * math.pi * 2 / sparkCount + 0.08;
          final direction = Offset(math.cos(angle), math.sin(angle));
          canvas.drawLine(
            center + direction * radius * 0.22,
            center + direction * rayLength,
            Paint()
              ..isAntiAlias = true
              ..color = (index.isEven ? _impactRed : _impactCream).withAlpha(
                (235 * waveFade).round(),
              )
              ..strokeCap = StrokeCap.square
              ..strokeWidth = math.max(1.6, radiusScale * 2.4),
          );
        }
      }
    }

    if (time >= 0.35) {
      final shardCount = kind == WindDartsImpactKind.singleBull
          ? 4
          : sparkCount;
      for (var index = 0; index < shardCount; index++) {
        final angle =
            index * math.pi * 2 / shardCount +
            ((index * 17) % 7) * 0.035 +
            (kind == WindDartsImpactKind.triple ? 0.12 : 0.0);
        final radiusFactor =
            0.58 +
            ((index * 13) % math.max(1, shardCount)) /
                math.max(1, shardCount) *
                0.34;
        final direction = Offset(math.cos(angle), math.sin(angle));
        final endDistance =
            radius * radiusFactor * (0.52 + shardProgress * 0.48);
        final shardCenter = center + direction * endDistance;
        final shardSize = radiusScale * (2.0 + index % 3);
        final shardPaint = Paint()
          ..isAntiAlias = false
          ..color =
              (kind == WindDartsImpactKind.doubleBull && index.isEven
                      ? _impactCream
                      : ringColor)
                  .withAlpha((235 * shardFade).round());
        canvas.save();
        canvas.translate(shardCenter.dx, shardCenter.dy);
        canvas.rotate(angle);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: shardSize,
            height: math.max(1.0, shardSize * 0.7),
          ),
          shardPaint,
        );
        canvas.restore();
      }
    }
    canvas.restore();
  }

  static Offset _rotateVector(Offset vector, double angle) => Offset(
    vector.dx * math.cos(angle) - vector.dy * math.sin(angle),
    vector.dx * math.sin(angle) + vector.dy * math.cos(angle),
  );

  static Offset _unitVector(Offset vector) {
    final distance = vector.distance;
    if (!distance.isFinite || distance < 0.001) return const Offset(0, 1);
    return vector / distance;
  }
}
