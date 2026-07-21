import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';

class PixelPanel extends StatelessWidget {
  const PixelPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = AppColors.surface,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(color: AppColors.backgroundDeep, offset: Offset(6, 6)),
        ],
      ),
      child: ClipPath(
        clipper: const PixelCornerClipper(corner: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class PixelCornerClipper extends CustomClipper<Path> {
  const PixelCornerClipper({required this.corner});

  final double corner;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(corner, 0)
      ..lineTo(size.width - corner, 0)
      ..lineTo(size.width - corner, corner / 2)
      ..lineTo(size.width, corner / 2)
      ..lineTo(size.width, size.height - corner)
      ..lineTo(size.width - corner, size.height - corner)
      ..lineTo(size.width - corner, size.height)
      ..lineTo(corner, size.height)
      ..lineTo(corner, size.height - corner / 2)
      ..lineTo(0, size.height - corner / 2)
      ..lineTo(0, corner)
      ..lineTo(corner, corner)
      ..close();
  }

  @override
  bool shouldReclip(PixelCornerClipper oldClipper) =>
      oldClipper.corner != corner;
}
