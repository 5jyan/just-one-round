import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared composition for the hitter-facing camera.
///
/// Field markings pass through one calibrated ground-plane projection. The
/// mound and rubber use regulation geometry. The foreground plate, batter
/// boxes, and dirt-only foul guides use documented player-scale allowances so
/// the chunky rear-view sprite reads cleanly at the canonical viewport.
abstract final class TenPitchSluggerScene {
  static const logicalSize = Size(360, 640);

  // Regulation field coordinates use the rear point of home plate as (0, 0),
  // +x toward first base, and +y toward the pitcher. The projection is
  // calibrated to the fixed 360x640 hitter camera and its authored mound.
  static const _fieldOrigin = Offset(180, 565);
  static const _fieldScaleX = 1.783;
  static const _fieldScaleY = 1.489;
  static const _fieldPerspective = 0.00487;

  static const _regulationHomeHalfWidthInches = 8.5;
  static const _regulationHomeFrontInches = 17.0;
  static const _homePlateVisualScale = 1.6;
  static const _homeHalfWidthInches =
      _regulationHomeHalfWidthInches * _homePlateVisualScale;
  static const _homeFrontInches =
      _regulationHomeFrontInches * _homePlateVisualScale;
  // The regulation 48-inch box looked undersized against the authored batter.
  // This 63-inch visual box sits four inches outside the enlarged plate. The
  // batter and its presentation-only contact point move together so all six
  // idle stance frames remain inside the chalk and bat/ball contact stays exact.
  static const _boxInnerEdgeInches = 17.6;
  static const _boxOuterEdgeInches = 80.6;
  static const _boxHalfLengthInches = 36.0;
  static const _chalkStampCells = 2;
  static const _foulLineDirtExitY = 454.0;
  static const _moundCenterInches = 59 * 12.0;
  static const _moundRadiusInches = 9 * 12.0;
  static const _rubberFrontInches = 60 * 12.0 + 6.0;
  static const _rubberDepthInches = 6.0;
  static const _rubberHalfWidthInches = 12.0;

  /// The authored V4 swing frame that reaches the ball at 0.12 seconds.
  static const batterContactFrame = 8;
  static const batterContactTipInCell = Offset(215, 136);
  static const _batterSpriteLogicalBounds = Rect.fromLTWH(-33, 338, 240, 240);

  static Offset releaseFor(Size size) =>
      _project(const Offset(180, 275.2), size);

  static Offset contactFor(Size size) => _project(const Offset(182, 474), size);

  static Rect strikeZoneFor(Size size) => _projectRect(
    Rect.fromCenter(center: const Offset(182, 438), width: 72, height: 80),
    size,
  );

  static Offset homePlateCenterFor(Size size) =>
      _project(_fieldToLogical(0, _homeHalfWidthInches), size);

  @visibleForTesting
  static Offset fieldToLogicalForTest(double xInches, double yInches) =>
      _fieldToLogical(xInches, yInches);

  @visibleForTesting
  static List<Offset> homePlateLogicalPointsForTest() =>
      _homePlateLogicalPoints;

  @visibleForTesting
  static List<Offset> leftBatterBoxLogicalPointsForTest() =>
      _batterBoxLogicalPoints(left: true);

  @visibleForTesting
  static List<Offset> rightBatterBoxLogicalPointsForTest() =>
      _batterBoxLogicalPoints(left: false);

  @visibleForTesting
  static List<Offset> leftFoulLineLogicalPointsForTest() => [
    _foulLineStart(left: true),
    _foulLineViewportExit(left: true),
  ];

  @visibleForTesting
  static List<Offset> rightFoulLineLogicalPointsForTest() => [
    _foulLineStart(left: false),
    _foulLineViewportExit(left: false),
  ];

  @visibleForTesting
  static double chalkThicknessLogicalPixelsForTest() => _chalkStampCells * 2.0;

  @visibleForTesting
  static Rect moundLogicalBoundsForTest() => _moundLogicalBounds;

  @visibleForTesting
  static Rect pitchingRubberLogicalBoundsForTest() =>
      _pitchingRubberLogicalBounds;

  static Rect pitcherBoundsFor(Size size) {
    final scale = _scaleFor(size);
    final center = releaseFor(size).translate(0, -14 * scale);
    return Rect.fromCenter(
      center: center,
      width: 48 * scale,
      height: 70 * scale,
    );
  }

  static Rect pitcherSpriteBoundsFor(Size size) {
    return _projectRect(const Rect.fromLTWH(132, 240, 96, 96), size);
  }

  static Rect batterBoundsFor(Size size) {
    return _projectRect(const Rect.fromLTWH(-7, 360, 136, 242), size);
  }

  static Rect batterSpriteBoundsFor(Size size) {
    return _projectRect(_batterSpriteLogicalBounds, size);
  }

  static Offset batterContactTipFor(Size size) {
    final bounds = batterSpriteBoundsFor(size);
    return Offset(
      bounds.left + batterContactTipInCell.dx / 240 * bounds.width,
      bounds.top + batterContactTipInCell.dy / 240 * bounds.height,
    );
  }

  static double _scaleFor(Size size) => size.width / logicalSize.width;

  // The 360x460 preview is a vertical crop of the 360x640 gameplay camera.
  // Projecting through this crop keeps character scale identical in both.
  static double _verticalCropFor(Size size, double scale) {
    final centeredCrop = (logicalSize.height * scale - size.height) / 2;
    if (centeredCrop <= 0) return 0;
    // Bias the short home/guide crop downward so the lowered batter's shoes
    // and the home plate remain visible without changing gameplay geometry.
    return centeredCrop + 15 * scale;
  }

  static Offset _project(Offset point, Size size) {
    final scale = _scaleFor(size);
    return Offset(
      point.dx * scale,
      point.dy * scale - _verticalCropFor(size, scale),
    );
  }

  static Rect _projectRect(Rect rect, Size size) {
    final origin = _project(rect.topLeft, size);
    final scale = _scaleFor(size);
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      rect.width * scale,
      rect.height * scale,
    );
  }

  static Paint _paint(
    Color color, {
    PaintingStyle style = PaintingStyle.fill,
  }) => Paint()
    ..isAntiAlias = false
    ..style = style
    ..color = color;

  static void drawEnvironment(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final horizon = height * 0.35;
    final scale = _scaleFor(size);

    canvas.drawRect(Offset.zero & size, _paint(const Color(0xFF101B33)));
    canvas.drawRect(
      Rect.fromLTWH(0, horizon * 0.58, width, horizon * 0.42),
      _paint(const Color(0xFF243A55)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, horizon * 0.69, width, horizon * 0.08),
      _paint(const Color(0xFF516477)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, horizon * 0.79, width, horizon * 0.21),
      _paint(const Color(0xFF17263B)),
    );

    for (final star in const [
      Offset(34, 102),
      Offset(88, 74),
      Offset(132, 128),
      Offset(224, 84),
      Offset(282, 116),
      Offset(326, 64),
    ]) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(star.dx / 360 * width, star.dy / 640 * height),
          width: math.max(2, 2 * scale),
          height: math.max(2, 2 * scale),
        ),
        _paint(const Color(0xFFE9D39B)),
      );
    }

    _drawLightTower(canvas, size, left: true);
    _drawLightTower(canvas, size, left: false);

    canvas.drawRect(
      Rect.fromLTWH(0, horizon, width, height - horizon),
      _paint(const Color(0xFF386E4C)),
    );
    for (var band = 0; band < 5; band++) {
      final top = horizon + (height - horizon) * band / 5;
      canvas.drawRect(
        Rect.fromLTWH(0, top, width, (height - horizon) / 10),
        _paint(band.isEven ? const Color(0xFF3E7752) : const Color(0xFF356847)),
      );
    }

    final moundBounds = _projectRect(_moundLogicalBounds, size);
    final mound = moundBounds.center;
    final infield = Path()
      ..moveTo(mound.dx - 40 * scale, mound.dy)
      ..lineTo(mound.dx + 40 * scale, mound.dy)
      ..lineTo(width * 0.94, height)
      ..lineTo(width * 0.06, height)
      ..close();
    canvas.drawPath(infield, _paint(const Color(0xFF9A6547)));
    canvas.drawOval(moundBounds, _paint(const Color(0xFFB47A55)));

    drawFieldGuides(canvas, size);
  }

  /// Exact gameplay geometry layered over the generated ballpark art.
  static void drawFieldGuides(Canvas canvas, Size size, {bool magic = false}) {
    const chalkShadow = Color(0x8A76583F);
    const foulChalk = Color(0xFFE5D7B3);
    const boxChalk = Color(0xFFD8C9A7);

    final leftShoulder = _foulLineStart(left: true);
    final rightShoulder = _foulLineStart(left: false);
    final leftExit = _foulLineViewportExit(left: true);
    final rightExit = _foulLineViewportExit(left: false);

    _drawPixelSegment(
      canvas,
      size,
      leftShoulder,
      leftExit,
      color: chalkShadow,
      logicalOffset: const Offset(0, 2),
      stampCells: _chalkStampCells,
    );
    _drawPixelSegment(
      canvas,
      size,
      rightShoulder,
      rightExit,
      color: chalkShadow,
      logicalOffset: const Offset(0, 2),
      stampCells: _chalkStampCells,
    );
    _drawPixelSegment(
      canvas,
      size,
      leftShoulder,
      leftExit,
      color: foulChalk,
      stampCells: _chalkStampCells,
    );
    _drawPixelSegment(
      canvas,
      size,
      rightShoulder,
      rightExit,
      color: foulChalk,
      stampCells: _chalkStampCells,
    );

    _drawPixelPolygonOutline(
      canvas,
      size,
      _batterBoxLogicalPoints(left: true),
      color: chalkShadow,
      logicalOffset: const Offset(0, 2),
      stampCells: _chalkStampCells,
    );
    _drawPixelPolygonOutline(
      canvas,
      size,
      _batterBoxLogicalPoints(left: false),
      color: chalkShadow,
      logicalOffset: const Offset(0, 2),
      stampCells: _chalkStampCells,
    );
    _drawPixelPolygonOutline(
      canvas,
      size,
      _batterBoxLogicalPoints(left: true),
      color: boxChalk,
      stampCells: _chalkStampCells,
    );
    _drawPixelPolygonOutline(
      canvas,
      size,
      _batterBoxLogicalPoints(left: false),
      color: boxChalk,
      stampCells: _chalkStampCells,
    );

    _fillPixelPolygon(
      canvas,
      size,
      _homePlateLogicalPoints,
      color: const Color(0xFF5E3D2D),
      logicalOffset: const Offset(0, 4),
    );
    _fillPixelPolygon(
      canvas,
      size,
      _homePlateLogicalPoints,
      color: const Color(0xFFB59A6F),
      logicalOffset: const Offset(0, 2),
    );
    _fillPixelPolygon(
      canvas,
      size,
      _homePlateLogicalPoints,
      color: const Color(0xFFECE2C8),
    );
    _drawPixelSegment(
      canvas,
      size,
      _homePlateLogicalPoints[0],
      _homePlateLogicalPoints[1],
      color: const Color(0xFFFFF6DC),
    );
    _drawPixelSegment(
      canvas,
      size,
      _homePlateLogicalPoints[2],
      _homePlateLogicalPoints[3],
      color: const Color(0xFFC3AD80),
    );
    _drawPixelSegment(
      canvas,
      size,
      _homePlateLogicalPoints[3],
      _homePlateLogicalPoints[4],
      color: const Color(0xFFC3AD80),
    );

    final rubber = _projectRect(_pitchingRubberLogicalBounds, size);
    final pixel = 2 * _scaleFor(size);
    final snappedRubber = Rect.fromLTWH(
      (rubber.left / pixel).round() * pixel,
      (rubber.top / pixel).round() * pixel,
      math.max(pixel * 5, (rubber.width / pixel).round() * pixel),
      pixel,
    );
    canvas.drawRect(
      snappedRubber.translate(0, pixel),
      _paint(const Color(0xFF6F573F)),
    );
    canvas.drawRect(snappedRubber, _paint(const Color(0xFFE4D7B7)));
  }

  static Offset _fieldToLogical(double xInches, double yInches) {
    final denominator = 1 + _fieldPerspective * yInches;
    return Offset(
      _fieldOrigin.dx + _fieldScaleX * xInches / denominator,
      _fieldOrigin.dy - _fieldScaleY * yInches / denominator,
    );
  }

  static List<Offset> get _homePlateLogicalPoints => [
    _fieldToLogical(-_homeHalfWidthInches, _homeFrontInches),
    _fieldToLogical(_homeHalfWidthInches, _homeFrontInches),
    _fieldToLogical(_homeHalfWidthInches, _homeHalfWidthInches),
    _fieldToLogical(0, 0),
    _fieldToLogical(-_homeHalfWidthInches, _homeHalfWidthInches),
  ];

  static List<Offset> _batterBoxLogicalPoints({required bool left}) {
    final inner = left ? -_boxInnerEdgeInches : _boxInnerEdgeInches;
    final outer = left ? -_boxOuterEdgeInches : _boxOuterEdgeInches;
    return [
      _fieldToLogical(outer, _boxHalfLengthInches),
      _fieldToLogical(inner, _boxHalfLengthInches),
      _fieldToLogical(inner, -_boxHalfLengthInches),
      _fieldToLogical(outer, -_boxHalfLengthInches),
    ];
  }

  static Rect get _moundLogicalBounds {
    final left = _fieldToLogical(-_moundRadiusInches, _moundCenterInches);
    final right = _fieldToLogical(_moundRadiusInches, _moundCenterInches);
    final far = _fieldToLogical(0, _moundCenterInches + _moundRadiusInches);
    final near = _fieldToLogical(0, _moundCenterInches - _moundRadiusInches);
    return Rect.fromLTRB(left.dx, far.dy, right.dx, near.dy);
  }

  static Rect get _pitchingRubberLogicalBounds {
    final frontLeft = _fieldToLogical(
      -_rubberHalfWidthInches,
      _rubberFrontInches,
    );
    final frontRight = _fieldToLogical(
      _rubberHalfWidthInches,
      _rubberFrontInches,
    );
    final rear = _fieldToLogical(0, _rubberFrontInches + _rubberDepthInches);
    return Rect.fromLTRB(frontLeft.dx, rear.dy, frontRight.dx, frontLeft.dy);
  }

  static Offset _foulLineViewportExit({required bool left}) {
    return Offset(left ? 0 : logicalSize.width, _foulLineDirtExitY);
  }

  static Offset _foulLineStart({required bool left}) {
    final box = _batterBoxLogicalPoints(left: left);
    return Offset((box[0].dx + box[1].dx) / 2, (box[0].dy + box[1].dy) / 2);
  }

  static void _drawPixelPolygonOutline(
    Canvas canvas,
    Size size,
    List<Offset> logicalPoints, {
    required Color color,
    Offset logicalOffset = Offset.zero,
    int stampCells = 1,
  }) {
    for (var index = 0; index < logicalPoints.length; index++) {
      _drawPixelSegment(
        canvas,
        size,
        logicalPoints[index],
        logicalPoints[(index + 1) % logicalPoints.length],
        color: color,
        logicalOffset: logicalOffset,
        stampCells: stampCells,
      );
    }
  }

  static void _drawPixelSegment(
    Canvas canvas,
    Size size,
    Offset logicalStart,
    Offset logicalEnd, {
    required Color color,
    Offset logicalOffset = Offset.zero,
    int stampCells = 1,
  }) {
    final scale = _scaleFor(size);
    final crop = _verticalCropFor(size, scale);
    final pixel = 2 * scale;
    final start = Offset(
      (logicalStart.dx + logicalOffset.dx) * scale,
      (logicalStart.dy + logicalOffset.dy) * scale - crop,
    );
    final end = Offset(
      (logicalEnd.dx + logicalOffset.dx) * scale,
      (logicalEnd.dy + logicalOffset.dy) * scale - crop,
    );
    var x0 = (start.dx / pixel).round();
    var y0 = (start.dy / pixel).round();
    final x1 = (end.dx / pixel).round();
    final y1 = (end.dy / pixel).round();
    final dx = (x1 - x0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final dy = -(y1 - y0).abs();
    final sy = y0 < y1 ? 1 : -1;
    var error = dx + dy;
    final paint = _paint(color);
    final stampSize = pixel * stampCells;

    while (true) {
      final center = Offset(x0 * pixel, y0 * pixel);
      canvas.drawRect(
        stampCells == 1
            ? Rect.fromLTWH(center.dx, center.dy, pixel, pixel)
            : Rect.fromCenter(
                center: center,
                width: stampSize,
                height: stampSize,
              ),
        paint,
      );
      if (x0 == x1 && y0 == y1) break;
      final doubledError = 2 * error;
      if (doubledError >= dy) {
        error += dy;
        x0 += sx;
      }
      if (doubledError <= dx) {
        error += dx;
        y0 += sy;
      }
    }
  }

  static void _fillPixelPolygon(
    Canvas canvas,
    Size size,
    List<Offset> logicalPoints, {
    required Color color,
    Offset logicalOffset = Offset.zero,
  }) {
    final scale = _scaleFor(size);
    final crop = _verticalCropFor(size, scale);
    final pixel = 2 * scale;
    final points = [
      for (final point in logicalPoints)
        Offset(
          (point.dx + logicalOffset.dx) * scale,
          (point.dy + logicalOffset.dy) * scale - crop,
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    final bounds = path.getBounds();
    final startX = (bounds.left / pixel).floor();
    final endX = (bounds.right / pixel).ceil();
    final startY = (bounds.top / pixel).floor();
    final endY = (bounds.bottom / pixel).ceil();
    final paint = _paint(color);
    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        final rect = Rect.fromLTWH(x * pixel, y * pixel, pixel, pixel);
        if (path.contains(rect.center)) canvas.drawRect(rect, paint);
      }
    }
  }

  static void _drawLightTower(Canvas canvas, Size size, {required bool left}) {
    final scale = _scaleFor(size);
    final x = left ? size.width * 0.065 : size.width * 0.935;
    final top = size.height * 0.105;
    final towerPaint = _paint(
      const Color(0xFF627080),
      style: PaintingStyle.stroke,
    )..strokeWidth = math.max(2, 3 * scale);
    canvas.drawLine(
      Offset(x, top + 40 * scale),
      Offset(x, size.height * 0.35),
      towerPaint,
    );
    final bank = Rect.fromCenter(
      center: Offset(x, top),
      width: 42 * scale,
      height: 26 * scale,
    );
    canvas.drawRect(bank, _paint(const Color(0xFF29384A)));
    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 4; column++) {
        canvas.drawRect(
          Rect.fromLTWH(
            bank.left + (5 + column * 9) * scale,
            bank.top + (5 + row * 10) * scale,
            5 * scale,
            5 * scale,
          ),
          _paint(const Color(0xFFFFE8A6)),
        );
      }
    }
  }

  /// Retained as guide geometry only. Runtime field guides intentionally do
  /// not draw this floating box.
  static void drawStrikeZone(Canvas canvas, Size size, {bool magic = false}) {
    final zone = strikeZoneFor(size);
    final color = magic ? const Color(0xFFC28BFF) : const Color(0xFFF3E9D0);
    canvas.drawRect(zone, _paint(color.withValues(alpha: 0.09)));
    final outline = _paint(
      color.withValues(alpha: 0.9),
      style: PaintingStyle.stroke,
    )..strokeWidth = math.max(2, 3 * _scaleFor(size));
    canvas.drawRect(zone, outline);
  }

  static void drawPitcher(
    Canvas canvas,
    Size size, {
    double actionProgress = 0,
    bool magic = false,
  }) {
    final scale = _scaleFor(size);
    final bounds = pitcherBoundsFor(size);
    final center = bounds.center;
    final lean = math.sin(actionProgress * math.pi) * 4 * scale;
    final outline = _paint(const Color(0xFF18243A));
    final uniform = _paint(const Color(0xFFE7DFC8));
    final accent = _paint(
      magic ? const Color(0xFF9D65D8) : const Color(0xFF2D6D65),
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, bounds.bottom - 2 * scale),
        width: 38 * scale,
        height: 8 * scale,
      ),
      _paint(const Color(0x66000000)),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - 14 * scale + lean,
        center.dy - 2 * scale,
        28 * scale,
        30 * scale,
      ),
      outline,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - 11 * scale + lean,
        center.dy,
        22 * scale,
        25 * scale,
      ),
      uniform,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - 11 * scale + lean,
        center.dy + 10 * scale,
        22 * scale,
        6 * scale,
      ),
      accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - 12 * scale,
        center.dy + 27 * scale,
        8 * scale,
        20 * scale,
      ),
      outline,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx + 4 * scale,
        center.dy + 27 * scale,
        8 * scale,
        20 * scale,
      ),
      outline,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + lean, center.dy - 17 * scale),
        width: 30 * scale,
        height: 30 * scale,
      ),
      _paint(const Color(0xFFCB8B62)),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - 17 * scale + lean,
        center.dy - 34 * scale,
        34 * scale,
        11 * scale,
      ),
      accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - 13 * scale + lean,
        center.dy - 38 * scale,
        26 * scale,
        7 * scale,
      ),
      accent,
    );

    final gloveY =
        center.dy - 2 * scale - 15 * scale * math.sin(actionProgress * math.pi);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 18 * scale + lean, gloveY),
        width: 17 * scale,
        height: 19 * scale,
      ),
      _paint(const Color(0xFF735036)),
    );
    final throwingHand = Offset(
      center.dx + (18 - 25 * actionProgress) * scale + lean,
      center.dy + (-4 + 13 * actionProgress) * scale,
    );
    final armPaint =
        _paint(const Color(0xFFCB8B62), style: PaintingStyle.stroke)
          ..strokeWidth = math.max(3, 6 * scale)
          ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(center.dx + 9 * scale + lean, center.dy),
      throwingHand,
      armPaint,
    );
  }

  static void drawBatter(
    Canvas canvas,
    Size size, {
    double swingProgress = 0,
    bool result = false,
    bool whiff = false,
  }) {
    final scale = _scaleFor(size);
    final bounds = batterBoundsFor(size);
    final origin = Offset(bounds.left + 70 * scale, bounds.top + 166 * scale);
    final swing = swingProgress.clamp(0.0, 1.0);
    final bodyTurn = math.sin(swing * math.pi) * 9 * scale;

    canvas.save();
    canvas.translate(origin.dx + bodyTurn, origin.dy);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, 68 * scale),
        width: 104 * scale,
        height: 18 * scale,
      ),
      _paint(const Color(0x66000000)),
    );
    final outline = _paint(const Color(0xFF172238));
    final uniform = _paint(
      result ? const Color(0xFFFFE28A) : const Color(0xFFE9E0C5),
    );
    final accent = _paint(const Color(0xFF2A6C62));

    canvas.drawRect(
      Rect.fromLTWH(-30 * scale, 24 * scale, 20 * scale, 48 * scale),
      outline,
    );
    canvas.drawRect(
      Rect.fromLTWH(10 * scale, 24 * scale, 20 * scale, 48 * scale),
      outline,
    );
    canvas.drawRect(
      Rect.fromLTWH(-36 * scale, 62 * scale, 28 * scale, 13 * scale),
      accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(8 * scale, 62 * scale, 28 * scale, 13 * scale),
      accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(-41 * scale, -35 * scale, 82 * scale, 70 * scale),
      outline,
    );
    canvas.drawRect(
      Rect.fromLTWH(-37 * scale, -31 * scale, 74 * scale, 62 * scale),
      uniform,
    );
    canvas.drawRect(
      Rect.fromLTWH(-8 * scale, -22 * scale, 16 * scale, 22 * scale),
      accent,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-4 * scale, -68 * scale),
        width: 67 * scale,
        height: 64 * scale,
      ),
      _paint(const Color(0xFFC9855E)),
    );
    canvas.drawRect(
      Rect.fromLTWH(-43 * scale, -106 * scale, 79 * scale, 35 * scale),
      _paint(const Color(0xFF172238)),
    );
    canvas.drawRect(
      Rect.fromLTWH(-46 * scale, -76 * scale, 74 * scale, 12 * scale),
      _paint(const Color(0xFF172238)),
    );
    canvas.drawRect(
      Rect.fromLTWH(-31 * scale, -16 * scale, 13 * scale, 25 * scale),
      _paint(const Color(0xFFC9855E)),
    );
    canvas.drawRect(
      Rect.fromLTWH(18 * scale, -17 * scale, 13 * scale, 25 * scale),
      _paint(const Color(0xFFC9855E)),
    );

    final hands = Offset(24 * scale, -4 * scale);
    final idleEnd = Offset(-62 * scale, -112 * scale);
    final swingEnd = Offset(92 * scale, whiff ? 27 * scale : -4 * scale);
    final batEnd = Offset.lerp(
      idleEnd,
      swingEnd,
      Curves.easeOut.transform(swing),
    )!;
    final batPaint =
        _paint(const Color(0xFFD9A64F), style: PaintingStyle.stroke)
          ..strokeWidth = math.max(5, 10 * scale)
          ..strokeCap = StrokeCap.square;
    final batOutline =
        _paint(const Color(0xFF5C432A), style: PaintingStyle.stroke)
          ..strokeWidth = math.max(7, 14 * scale)
          ..strokeCap = StrokeCap.square;
    canvas.drawLine(hands, batEnd, batOutline);
    canvas.drawLine(hands, batEnd, batPaint);
    canvas.drawRect(
      Rect.fromCenter(center: hands, width: 18 * scale, height: 17 * scale),
      _paint(const Color(0xFF26364A)),
    );

    canvas.restore();
  }
}
