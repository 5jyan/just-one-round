import 'dart:ui';

/// Shared procedural net renderer for gameplay, the home preview, and guides.
///
/// The outer edge remains inside the existing seven-pixel contact band. Only
/// the rope, mesh, and knot treatment live here; collision rules stay in the
/// domain layer.
class NetBoatNetPainter {
  NetBoatNetPainter()
    : _shadowPaint = Paint()
        ..color = const Color(0xE6163E48)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = false,
      _ropePaint = Paint()
        ..color = const Color(0xFFFFE7A3)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = false,
      _ropeHighlightPaint = Paint()
        ..color = const Color(0xFFFFF6D3)
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = false,
      _meshShadowPaint = Paint()
        ..color = const Color(0x99163E48)
        ..strokeWidth = 2.3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true,
      _meshPaint = Paint()
        ..color = const Color(0xB8FFF0BE)
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true,
      _fillPaint = Paint()
        ..color = const Color(0x2E51DED3)
        ..style = PaintingStyle.fill
        ..isAntiAlias = false,
      _knotShadowPaint = Paint()
        ..color = const Color(0xD9163E48)
        ..style = PaintingStyle.fill
        ..isAntiAlias = false,
      _knotPaint = Paint()
        ..color = const Color(0xFFF09A3E)
        ..style = PaintingStyle.fill
        ..isAntiAlias = false,
      _knotHighlightPaint = Paint()
        ..color = const Color(0xFFFFD16A)
        ..style = PaintingStyle.fill
        ..isAntiAlias = false;

  static const _railOffset = 5.0;
  static const _meshOrigin = 4.0;
  static const _meshSpacing = 12.0;
  static const _meshRun = 10.0;
  static const _knotOrigin = 12.0;
  static const _knotSpacing = 24.0;

  final Paint _shadowPaint;
  final Paint _ropePaint;
  final Paint _ropeHighlightPaint;
  final Paint _meshShadowPaint;
  final Paint _meshPaint;
  final Paint _fillPaint;
  final Paint _knotShadowPaint;
  final Paint _knotPaint;
  final Paint _knotHighlightPaint;

  void draw(
    Canvas canvas,
    List<Offset> points, {
    bool closed = false,
    bool warning = false,
  }) {
    if (points.length < 2) return;
    _configurePalette(warning);

    if (closed) _drawClosedMesh(canvas, points);
    var pathDistance = 0.0;
    for (var index = 0; index < points.length - 1; index++) {
      final length = _drawSegment(
        canvas,
        points[index],
        points[index + 1],
        index,
        pathDistance,
      );
      pathDistance += length;
    }
    for (final point in points.take(points.length - 1)) {
      _drawKnot(canvas, point);
    }
  }

  void _configurePalette(bool warning) {
    _ropePaint.color = warning
        ? const Color(0xFFFFC04A)
        : const Color(0xFFFFE7A3);
    _ropeHighlightPaint.color = warning
        ? const Color(0xFFFFF0B0)
        : const Color(0xFFFFF6D3);
    _meshPaint.color = warning
        ? const Color(0xFFF6D46A)
        : const Color(0xB8FFF0BE);
    _fillPaint.color = warning
        ? const Color(0x3DFFC04A)
        : const Color(0x2E51DED3);
    _knotPaint.color = warning
        ? const Color(0xFFFFA84A)
        : const Color(0xFFF09A3E);
    _knotHighlightPaint.color = warning
        ? const Color(0xFFFFE08A)
        : const Color(0xFFFFD16A);
  }

  double _drawSegment(
    Canvas canvas,
    Offset start,
    Offset end,
    int segmentIndex,
    double pathDistance,
  ) {
    final delta = end - start;
    final length = delta.distance;
    if (length <= 1) return 0;
    final unit = delta / length;
    final perpendicular = Offset(-unit.dy, unit.dx) * _railOffset;
    final railA = Path()
      ..moveTo((start + perpendicular).dx, (start + perpendicular).dy)
      ..lineTo((end + perpendicular).dx, (end + perpendicular).dy);
    final railB = Path()
      ..moveTo((start - perpendicular).dx, (start - perpendicular).dy)
      ..lineTo((end - perpendicular).dx, (end - perpendicular).dy);

    canvas
      ..drawPath(railA, _shadowPaint)
      ..drawPath(railB, _shadowPaint)
      ..drawPath(railA, _ropePaint)
      ..drawPath(railB, _ropePaint)
      ..drawPath(railA, _ropeHighlightPaint)
      ..drawPath(railB, _ropeHighlightPaint);

    var meshDistance = _firstGridDistance(
      pathDistance,
      origin: _meshOrigin,
      spacing: _meshSpacing,
    );
    while (meshDistance + _meshRun < pathDistance + length) {
      final localDistance = meshDistance - pathDistance;
      if (localDistance >= 0) {
        final center = start + unit * localDistance;
        final next = center + unit * _meshRun;
        _drawMeshLine(canvas, center + perpendicular, next - perpendicular);
        _drawMeshLine(canvas, center - perpendicular, next + perpendicular);
      }
      meshDistance += _meshSpacing;
    }

    var knotDistance = _firstGridDistance(
      pathDistance,
      origin: _knotOrigin,
      spacing: _knotSpacing,
    );
    while (knotDistance < pathDistance + length - 5) {
      final localDistance = knotDistance - pathDistance;
      if (localDistance >= 0) {
        final side =
            ((knotDistance / _knotSpacing).floor() + segmentIndex).isEven
            ? 1.0
            : -1.0;
        _drawKnot(canvas, start + unit * localDistance + perpendicular * side);
      }
      knotDistance += _knotSpacing;
    }
    return length;
  }

  double _firstGridDistance(
    double pathDistance, {
    required double origin,
    required double spacing,
  }) {
    if (pathDistance <= origin) return origin;
    final steps = ((pathDistance - origin) / spacing).ceil();
    return origin + steps * spacing;
  }

  void _drawMeshLine(Canvas canvas, Offset start, Offset end) {
    canvas
      ..drawLine(start, end, _meshShadowPaint)
      ..drawLine(start, end, _meshPaint);
  }

  void _drawKnot(Canvas canvas, Offset point) {
    canvas
      ..drawCircle(point, 3.0, _knotShadowPaint)
      ..drawCircle(point, 2.5, _knotPaint)
      ..drawCircle(point + const Offset(-0.7, -0.7), 0.65, _knotHighlightPaint);
  }

  void _drawClosedMesh(Canvas canvas, List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, _fillPaint);

    canvas
      ..save()
      ..clipPath(path);
    final bounds = path.getBounds();
    for (
      var x = bounds.left - bounds.height;
      x < bounds.right + bounds.height;
      x += 18
    ) {
      _drawMeshLine(
        canvas,
        Offset(x, bounds.top),
        Offset(x + bounds.height, bounds.bottom),
      );
      _drawMeshLine(
        canvas,
        Offset(x, bounds.bottom),
        Offset(x + bounds.height, bounds.top),
      );
    }
    canvas.restore();
  }
}
