import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';

class MidnightSnakePathPoint {
  const MidnightSnakePathPoint(this.row, this.column);

  final double row;
  final double column;

  static MidnightSnakePathPoint fromCell(SnakeCell cell) =>
      MidnightSnakePathPoint(cell.row.toDouble(), cell.column.toDouble());

  static MidnightSnakePathPoint lerp(
    SnakeCell start,
    SnakeCell end,
    double progress,
  ) => MidnightSnakePathPoint(
    start.row + (end.row - start.row) * progress,
    start.column + (end.column - start.column) * progress,
  );
}

List<MidnightSnakePathPoint> buildMidnightSnakePath({
  required List<SnakeCell> body,
  required List<SnakeCell> previousBody,
  required double progress,
}) {
  if (body.isEmpty) return const [];
  final clampedProgress = progress.clamp(0.0, 1.0);
  if (previousBody.isEmpty ||
      clampedProgress >= 1 ||
      (body.length != previousBody.length &&
          body.length != previousBody.length + 1)) {
    return _simplify(
      body.map(MidnightSnakePathPoint.fromCell).toList(growable: false),
    );
  }

  final grew = body.length == previousBody.length + 1;
  final points = <MidnightSnakePathPoint>[
    MidnightSnakePathPoint.lerp(
      previousBody.first,
      body.first,
      clampedProgress,
    ),
  ];

  final retainedPreviousCount = grew
      ? previousBody.length
      : previousBody.length - 1;
  for (var index = 0; index < retainedPreviousCount; index++) {
    points.add(MidnightSnakePathPoint.fromCell(previousBody[index]));
  }

  if (!grew && previousBody.length > 1) {
    points.add(
      MidnightSnakePathPoint.lerp(
        previousBody.last,
        previousBody[previousBody.length - 2],
        clampedProgress,
      ),
    );
  }
  return _simplify(points);
}

List<MidnightSnakePathPoint> _simplify(List<MidnightSnakePathPoint> points) {
  const epsilon = 0.000001;
  final simplified = <MidnightSnakePathPoint>[];
  for (final point in points) {
    if (simplified.isNotEmpty &&
        (simplified.last.row - point.row).abs() < epsilon &&
        (simplified.last.column - point.column).abs() < epsilon) {
      continue;
    }
    while (simplified.length >= 2) {
      final before = simplified[simplified.length - 2];
      final last = simplified.last;
      final sameRow =
          (before.row - last.row).abs() < epsilon &&
          (last.row - point.row).abs() < epsilon;
      final sameColumn =
          (before.column - last.column).abs() < epsilon &&
          (last.column - point.column).abs() < epsilon;
      if (!sameRow && !sameColumn) break;
      simplified.removeLast();
    }
    simplified.add(point);
  }
  return List.unmodifiable(simplified);
}
