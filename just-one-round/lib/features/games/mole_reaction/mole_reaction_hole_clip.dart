import 'package:flutter/rendering.dart';

/// Outer contour of the foreground dirt rim, in the 48px source-art space.
///
/// The foreground image is intentionally drawn after the mole. A rectangular
/// clip alone still lets the lower corners of a wide animation frame escape
/// through the transparent parts beside that rim, so the mole uses this same
/// contour as a reveal mask before the foreground is painted.
const _moleHoleContour = <_MoleHoleContourRow>[
  _MoleHoleContourRow(22, 6, 40),
  _MoleHoleContourRow(23, 6, 41),
  _MoleHoleContourRow(24, 5, 42),
  _MoleHoleContourRow(25, 4, 43),
  _MoleHoleContourRow(26, 3, 43),
  _MoleHoleContourRow(27, 3, 44),
  _MoleHoleContourRow(28, 3, 43),
  _MoleHoleContourRow(29, 4, 43),
  _MoleHoleContourRow(30, 4, 43),
  _MoleHoleContourRow(31, 5, 41),
  _MoleHoleContourRow(32, 6, 41),
  _MoleHoleContourRow(33, 7, 40),
  _MoleHoleContourRow(34, 9, 38),
  _MoleHoleContourRow(35, 13, 36),
  _MoleHoleContourRow(36, 16, 31),
];

/// Returns the pixel-aligned reveal area for a mole inside one hole cell.
///
/// Above the first foreground-rim row the full cell is allowed, which keeps
/// the head and whiskers natural. From the rim down, the mask follows the
/// outer dirt contour and closes exactly where the rim's final opaque row
/// begins, so there is no one-pixel gap below it.
Path moleReactionMoleClipPath(Rect rect) {
  final scaleX = rect.width / 48;
  final scaleY = rect.height / 48;
  final firstY = rect.top + _moleHoleContour.first.y * scaleY;
  final bottomY = rect.top + _moleHoleContour.last.y * scaleY;
  final path = Path()
    ..moveTo(rect.left, rect.top)
    ..lineTo(rect.right, rect.top)
    ..lineTo(rect.right, firstY);

  for (final row in _moleHoleContour) {
    path.lineTo(
      rect.left + (row.right + 1) * scaleX,
      rect.top + row.y * scaleY,
    );
  }
  path
    ..lineTo(rect.left + (_moleHoleContour.last.right + 1) * scaleX, bottomY)
    ..lineTo(rect.left + _moleHoleContour.last.left * scaleX, bottomY);
  for (final row in _moleHoleContour.reversed) {
    path.lineTo(rect.left + row.left * scaleX, rect.top + row.y * scaleY);
  }
  path
    ..lineTo(rect.left, firstY)
    ..close();
  return path;
}

/// Flutter clipper used by the home/guide preview so it shares the runtime
/// hole occlusion with the Flame scene.
class MoleReactionHoleClipper extends CustomClipper<Path> {
  const MoleReactionHoleClipper();

  @override
  Path getClip(Size size) => moleReactionMoleClipPath(Offset.zero & size);

  @override
  bool shouldReclip(covariant MoleReactionHoleClipper oldClipper) => false;
}

class _MoleHoleContourRow {
  const _MoleHoleContourRow(this.y, this.left, this.right);

  final double y;
  final double left;
  final double right;
}
