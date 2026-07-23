import 'dart:math';

enum CakeMoveAxis { x, z }

class CakeFootprint {
  const CakeFootprint({
    required this.x,
    required this.z,
    required this.width,
    required this.depth,
  });

  final double x;
  final double z;
  final double width;
  final double depth;

  double get left => x - width / 2;
  double get right => x + width / 2;
  double get back => z - depth / 2;
  double get front => z + depth / 2;

  CakeFootprint copyWith({
    double? x,
    double? z,
    double? width,
    double? depth,
  }) => CakeFootprint(
    x: x ?? this.x,
    z: z ?? this.z,
    width: width ?? this.width,
    depth: depth ?? this.depth,
  );
}

class CakePlacement {
  const CakePlacement({
    required this.landed,
    required this.offcut,
    required this.isPerfect,
  });

  final CakeFootprint landed;
  final CakeFootprint? offcut;
  final bool isPerfect;
}

abstract final class FailedBakeryRules {
  static const initialSize = 160.0;
  static const perfectTolerance = 4.0;
  static const perfectsForRecovery = 3;
  static const recoverySize = 8.0;
  static const maximumLayers = 999;

  static CakeMoveAxis axisForLayer(int layer) =>
      layer.isOdd ? CakeMoveAxis.x : CakeMoveAxis.z;

  static double speedForLayer(int layer) =>
      min(330, 120 + max(0, layer - 1) * 7);

  static CakePlacement? place({
    required CakeFootprint below,
    required CakeFootprint moving,
    required CakeMoveAxis axis,
  }) {
    final offset = axis == CakeMoveAxis.x
        ? (moving.x - below.x).abs()
        : (moving.z - below.z).abs();
    if (offset <= perfectTolerance) {
      return CakePlacement(landed: below, offcut: null, isPerfect: true);
    }

    if (axis == CakeMoveAxis.x) {
      final overlapLeft = max(below.left, moving.left);
      final overlapRight = min(below.right, moving.right);
      if (overlapRight <= overlapLeft) return null;
      final landed = moving.copyWith(
        x: (overlapLeft + overlapRight) / 2,
        width: overlapRight - overlapLeft,
      );
      return CakePlacement(
        landed: landed,
        offcut: _xOffcut(moving, overlapLeft, overlapRight),
        isPerfect: false,
      );
    }

    final overlapBack = max(below.back, moving.back);
    final overlapFront = min(below.front, moving.front);
    if (overlapFront <= overlapBack) return null;
    final landed = moving.copyWith(
      z: (overlapBack + overlapFront) / 2,
      depth: overlapFront - overlapBack,
    );
    return CakePlacement(
      landed: landed,
      offcut: _zOffcut(moving, overlapBack, overlapFront),
      isPerfect: false,
    );
  }

  static CakeFootprint recover(CakeFootprint footprint) => footprint.copyWith(
    width: min(initialSize, footprint.width + recoverySize),
    depth: min(initialSize, footprint.depth + recoverySize),
  );

  static String formatLayers(int layers) => '$layers층';

  static CakeFootprint _xOffcut(
    CakeFootprint moving,
    double overlapLeft,
    double overlapRight,
  ) {
    if (moving.left < overlapLeft) {
      final width = overlapLeft - moving.left;
      return moving.copyWith(x: moving.left + width / 2, width: width);
    }
    final width = moving.right - overlapRight;
    return moving.copyWith(x: overlapRight + width / 2, width: width);
  }

  static CakeFootprint _zOffcut(
    CakeFootprint moving,
    double overlapBack,
    double overlapFront,
  ) {
    if (moving.back < overlapBack) {
      final depth = overlapBack - moving.back;
      return moving.copyWith(z: moving.back + depth / 2, depth: depth);
    }
    final depth = moving.front - overlapFront;
    return moving.copyWith(z: overlapFront + depth / 2, depth: depth);
  }
}
