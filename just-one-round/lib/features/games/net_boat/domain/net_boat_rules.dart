import 'dart:math';

enum NetBoatDirection { north, east, south, west }

enum NetBoatFailure { reef, creature }

enum NetBoatCreatureKind { sardine, piranha, marlin, shark, whale }

class NetBoatCreatureSpec {
  const NetBoatCreatureSpec({
    required this.points,
    required this.renderWidth,
    required this.renderHeight,
    required this.collisionHalfLength,
    required this.collisionHalfWidth,
    required this.netContactHalfLength,
    required this.netContactHalfWidth,
    required this.minimumSpeed,
    required this.maximumSpeed,
    required this.respawnSeconds,
  });

  final int points;
  final double renderWidth;
  final double renderHeight;
  final double collisionHalfLength;
  final double collisionHalfWidth;

  /// Capsule matching the visible, non-transparent creature silhouette.
  final double netContactHalfLength;
  final double netContactHalfWidth;
  final double minimumSpeed;
  final double maximumSpeed;

  /// Minimum delay between successful respawns of this creature kind.
  final double respawnSeconds;
}

class NetBoatRoster {
  const NetBoatRoster({
    required this.sardine,
    required this.piranha,
    required this.marlin,
    required this.shark,
    required this.whale,
  });

  final int sardine;
  final int piranha;
  final int marlin;
  final int shark;
  final int whale;

  int targetFor(NetBoatCreatureKind kind) => switch (kind) {
    NetBoatCreatureKind.sardine => sardine,
    NetBoatCreatureKind.piranha => piranha,
    NetBoatCreatureKind.marlin => marlin,
    NetBoatCreatureKind.shark => shark,
    NetBoatCreatureKind.whale => whale,
  };
}

class NetBoatDifficulty {
  const NetBoatDifficulty({required this.boatSpeed, required this.roster});

  final double boatSpeed;
  final NetBoatRoster roster;
}

class NetBoatSpriteTransform {
  const NetBoatSpriteTransform({
    required this.rotation,
    required this.flipHorizontally,
  });

  final double rotation;
  final bool flipHorizontally;
}

class NetLoop {
  const NetLoop({required this.intersection, required this.polygon});

  final Point<double> intersection;
  final List<Point<double>> polygon;
}

class NetBoatNetBounce {
  const NetBoatNetBounce({required this.position, required this.velocity});

  final Point<double> position;
  final Point<double> velocity;
}

/// One-slot input queue used by the runtime and unit tests.
class NetBoatTurnBuffer {
  double _cooldownRemaining = 0;
  bool _buffered = false;

  bool get hasBufferedTurn => _buffered;
  double get cooldownRemaining => _cooldownRemaining;

  /// Returns true when the turn should happen immediately.
  bool request() {
    if (_cooldownRemaining <= 0) {
      _cooldownRemaining = NetBoatRules.turnCooldownSeconds;
      return true;
    }
    if (!_buffered) _buffered = true;
    return false;
  }

  /// Advances the queue and returns true when the buffered turn becomes due.
  bool update(double dt) {
    _cooldownRemaining = max(0, _cooldownRemaining - max(0, dt));
    if (_cooldownRemaining > 0 || !_buffered) return false;
    _buffered = false;
    _cooldownRemaining = NetBoatRules.turnCooldownSeconds;
    return true;
  }

  void reset() {
    _cooldownRemaining = 0;
    _buffered = false;
  }
}

abstract final class NetBoatRules {
  static const rulesVersion = 3;
  static const gameDurationSeconds = 300;
  static const gameDuration = Duration(seconds: gameDurationSeconds);
  // The 5-minute extension does not add another difficulty stage. Once the
  // 150-second roster is active, it remains the cap through the end of play.
  static const difficultyCapSeconds = 180.0;
  static const maximumSubmittedScore = 1000000;
  static const safeOpeningSeconds = 3.0;
  static const whaleWarningSeconds = 2.0;
  static const whaleSpawnSeconds = <double>[60.0, 120.0, 180.0, 240.0];
  static const safeCreatureSpawnSeconds = 3.2;
  static const turnCooldownSeconds = 0.12;
  static const netMaximumLength = 1000.0;
  static const netWarningRatio = 0.8;
  static const netWarningMessage = '그물 길이 800부터 끊길 위험이 있어요!';
  static const netRecoverySeconds = 1.0;
  // The two outer rope shadows reach 7 logical pixels from the path center.
  // Contact is inclusive so even a visible edge touch catches the creature.
  static const netVisualHalfWidth = 7.0;
  static const netBounceSeparation = 0.25;
  // Both center lines can sit 7 px inside the visible outer edge. Add a small
  // 2 px input grace beyond the combined visible width so a visual near-touch
  // closes the loop without making unrelated parallel paths connect.
  static const netClosureTolerance = 16.0;
  static const boatCollisionHalfLength = 15.0;
  static const boatCollisionHalfWidth = 5.5;
  static const boatWallCollisionHalfLength = 10.0;
  static const boatWallCollisionHalfWidth = 4.0;
  // Let the boat visually brush the reef before its smaller wall-collision
  // core counts as outside the play area.
  static const horizontalWallForgiveness = 8.0;
  static const verticalWallForgiveness = 11.0;
  static const minimumCreatureBoatSpawnDistance = 110.0;
  // Inner faces of the visible 48 px rock walls. The top wall was moved up
  // to give the player more steering room without hiding the lethal edge.
  static const playLeft = 42.0;
  static const playTop = 106.0;
  static const playRight = 318.0;
  static const playBottom = 592.0;
  static const startX = 180.0;
  static const startY = 400.0;

  static const creatureSpecs = <NetBoatCreatureKind, NetBoatCreatureSpec>{
    NetBoatCreatureKind.sardine: NetBoatCreatureSpec(
      points: 10,
      renderWidth: 28,
      renderHeight: 28,
      collisionHalfLength: 4,
      collisionHalfWidth: 2,
      netContactHalfLength: 13,
      netContactHalfWidth: 5,
      minimumSpeed: 18,
      maximumSpeed: 24,
      respawnSeconds: 1,
    ),
    NetBoatCreatureKind.piranha: NetBoatCreatureSpec(
      points: 100,
      renderWidth: 28,
      renderHeight: 28,
      collisionHalfLength: 8,
      collisionHalfWidth: 5,
      netContactHalfLength: 12.5,
      netContactHalfWidth: 10,
      minimumSpeed: 24,
      maximumSpeed: 30,
      respawnSeconds: 5,
    ),
    NetBoatCreatureKind.marlin: NetBoatCreatureSpec(
      points: 300,
      renderWidth: 56,
      renderHeight: 38,
      collisionHalfLength: 20,
      collisionHalfWidth: 5,
      netContactHalfLength: 26,
      netContactHalfWidth: 11,
      minimumSpeed: 30,
      maximumSpeed: 40,
      respawnSeconds: 10,
    ),
    NetBoatCreatureKind.shark: NetBoatCreatureSpec(
      points: 700,
      renderWidth: 74,
      renderHeight: 38,
      // The shark is submerged; only the visible dorsal fin is lethal.
      collisionHalfLength: 10.5,
      collisionHalfWidth: 7,
      netContactHalfLength: 12,
      netContactHalfWidth: 7,
      minimumSpeed: 40,
      maximumSpeed: 50,
      respawnSeconds: 20,
    ),
    NetBoatCreatureKind.whale: NetBoatCreatureSpec(
      points: 2500,
      renderWidth: 129.6,
      renderHeight: 85.86,
      collisionHalfLength: 46.98,
      collisionHalfWidth: 19.44,
      netContactHalfLength: 59.94,
      netContactHalfWidth: 29.16,
      minimumSpeed: 15,
      maximumSpeed: 15,
      respawnSeconds: 5,
    ),
  };

  static NetBoatDirection turnRight(NetBoatDirection direction) =>
      NetBoatDirection.values[(direction.index + 1) % 4];

  static Point<double> directionVector(NetBoatDirection direction) =>
      switch (direction) {
        NetBoatDirection.north => const Point(0, -1),
        NetBoatDirection.east => const Point(1, 0),
        NetBoatDirection.south => const Point(0, 1),
        NetBoatDirection.west => const Point(-1, 0),
      };

  static NetBoatDifficulty difficultyAt(double elapsedSeconds) {
    final seconds = elapsedSeconds.clamp(0.0, difficultyCapSeconds);
    final sardine = sardineTargetAt(seconds);
    if (seconds >= 150) {
      return NetBoatDifficulty(
        boatSpeed: 120,
        roster: NetBoatRoster(
          sardine: sardine,
          piranha: 7,
          marlin: 3,
          shark: 3,
          whale: 1,
        ),
      );
    }
    if (seconds >= 90) {
      return NetBoatDifficulty(
        boatSpeed: 110.4,
        roster: NetBoatRoster(
          sardine: sardine,
          piranha: 6,
          marlin: 3,
          shark: 2,
          whale: 1,
        ),
      );
    }
    if (seconds >= 60) {
      return NetBoatDifficulty(
        boatSpeed: 100.8,
        roster: NetBoatRoster(
          sardine: sardine,
          piranha: 5,
          marlin: 2,
          shark: 1,
          whale: 1,
        ),
      );
    }
    if (seconds >= 30) {
      return NetBoatDifficulty(
        boatSpeed: 100.8,
        roster: NetBoatRoster(
          sardine: sardine,
          piranha: 4,
          marlin: 2,
          shark: 0,
          whale: 0,
        ),
      );
    }
    return NetBoatDifficulty(
      boatSpeed: 91.2,
      roster: NetBoatRoster(
        sardine: sardine,
        piranha: 3,
        marlin: 1,
        shark: 0,
        whale: 0,
      ),
    );
  }

  static int sardineTargetAt(double elapsedSeconds) {
    final activeSeconds = elapsedSeconds.clamp(
      0.0,
      difficultyCapSeconds - 0.000001,
    );
    return 15 + (activeSeconds ~/ 30) * 5;
  }

  static NetBoatCreatureSpec specFor(NetBoatCreatureKind kind) =>
      creatureSpecs[kind]!;

  static bool isLethalOnBoatContact(NetBoatCreatureKind kind) =>
      kind != NetBoatCreatureKind.sardine;

  /// Generated atlas direction before runtime rotation. Piranha faces left;
  /// marlin, the source shark, and whale all face right.
  static bool nativeSpriteFacesRight(NetBoatCreatureKind kind) =>
      kind != NetBoatCreatureKind.piranha;

  /// Creature sprites are authored on a +X local axis before being rotated to
  /// their velocity. Left-facing source sheets need correction.
  static bool spriteNeedsHorizontalFlipForVelocity(NetBoatCreatureKind kind) =>
      !nativeSpriteFacesRight(kind);

  /// Keeps side-view creatures visually upright. Leftward motion is rendered
  /// with a horizontal flip instead of rotating the belly above the back.
  static NetBoatSpriteTransform spriteTransformForVelocity(
    NetBoatCreatureKind kind,
    Point<double> velocity,
  ) {
    final movingLeft = velocity.x < 0;
    final rotation = movingLeft
        ? atan2(-velocity.y, -velocity.x)
        : atan2(velocity.y, velocity.x);
    return NetBoatSpriteTransform(
      rotation: rotation,
      flipHorizontally:
          spriteNeedsHorizontalFlipForVelocity(kind) != movingLeft,
    );
  }

  static int captureScore(Iterable<NetBoatCreatureKind> creatures) {
    final caught = creatures.toList(growable: false);
    if (caught.isEmpty) return 0;
    final base = caught.fold<int>(0, (sum, kind) => sum + specFor(kind).points);
    final bonusCreatureCount = caught
        .where((kind) => kind != NetBoatCreatureKind.sardine)
        .length;
    return base + 200 * max(0, bonusCreatureCount - 1);
  }

  static String capturePopupLabel(NetBoatCreatureKind kind) =>
      '+${formatHudScore(specFor(kind).points)}';

  static double netLength(Iterable<Point<double>> points) {
    final path = points.toList(growable: false);
    var length = 0.0;
    for (var index = 0; index < path.length - 1; index++) {
      final dx = path[index + 1].x - path[index].x;
      final dy = path[index + 1].y - path[index].y;
      length += sqrt(dx * dx + dy * dy);
    }
    return length;
  }

  static double netUsageRatio(double length) =>
      (length / netMaximumLength).clamp(0.0, 1.0);

  static bool isNetWarning(double length) =>
      length >= netMaximumLength * netWarningRatio;

  static bool isNetAtLimit(double length) => length >= netMaximumLength;

  static bool boatHitsCreature({
    required Point<double> boat,
    required Point<double> boatDirection,
    required Point<double> creature,
    required Point<double> direction,
    required NetBoatCreatureKind kind,
  }) {
    final spec = specFor(kind);
    final boatAxis = _unitVector(boatDirection);
    final creatureAxis = _unitVector(direction);
    final boatSegmentHalfLength =
        boatCollisionHalfLength - boatCollisionHalfWidth;
    final creatureSegmentHalfLength =
        spec.collisionHalfLength - spec.collisionHalfWidth;
    final boatStart = Point<double>(
      boat.x - boatAxis.x * boatSegmentHalfLength,
      boat.y - boatAxis.y * boatSegmentHalfLength,
    );
    final boatEnd = Point<double>(
      boat.x + boatAxis.x * boatSegmentHalfLength,
      boat.y + boatAxis.y * boatSegmentHalfLength,
    );
    final creatureStart = Point<double>(
      creature.x - creatureAxis.x * creatureSegmentHalfLength,
      creature.y - creatureAxis.y * creatureSegmentHalfLength,
    );
    final creatureEnd = Point<double>(
      creature.x + creatureAxis.x * creatureSegmentHalfLength,
      creature.y + creatureAxis.y * creatureSegmentHalfLength,
    );
    final contactRadius = boatCollisionHalfWidth + spec.collisionHalfWidth;
    return _segmentDistanceSquared(
          boatStart,
          boatEnd,
          creatureStart,
          creatureEnd,
        ) <=
        contactRadius * contactRadius + 1e-6;
  }

  /// Detects visible contact between a moving creature and the active net.
  ///
  /// Creature art faces its velocity, so sweeping the capsule's center line
  /// from [previousCreature] through [creature] covers the full opaque body
  /// without using transparent atlas padding as a hit target.
  static bool movingCreatureTouchesNet({
    required Point<double> previousCreature,
    required Point<double> creature,
    required Point<double> direction,
    required NetBoatCreatureKind kind,
    required List<Point<double>> net,
  }) {
    // The whale is large enough to pass through the open net. It can still be
    // captured after a loop closes and remains lethal on boat contact.
    if (kind == NetBoatCreatureKind.whale || net.length < 2) return false;
    final spec = specFor(kind);
    final axis = _unitVector(direction);
    final centerLineHalfLength =
        spec.netContactHalfLength - spec.netContactHalfWidth;
    final sweptStart = Point<double>(
      previousCreature.x - axis.x * centerLineHalfLength,
      previousCreature.y - axis.y * centerLineHalfLength,
    );
    final sweptEnd = Point<double>(
      creature.x + axis.x * centerLineHalfLength,
      creature.y + axis.y * centerLineHalfLength,
    );
    final contactRadius = spec.netContactHalfWidth + netVisualHalfWidth;
    final contactRadiusSquared = contactRadius * contactRadius + 1e-6;
    for (var index = 0; index < net.length - 1; index++) {
      if (_segmentDistanceSquared(
            sweptStart,
            sweptEnd,
            net[index],
            net[index + 1],
          ) <=
          contactRadiusSquared) {
        return true;
      }
    }
    return false;
  }

  /// Reflects a non-whale creature from the first visible net segment it swept
  /// across. Whales pass through an open net without a bounce.
  /// The corrected center stays on the side occupied before contact, keeping
  /// the creature from tunnelling through the net even at high speed.
  static NetBoatNetBounce? bounceCreatureOffNet({
    required Point<double> previousCreature,
    required Point<double> creature,
    required Point<double> velocity,
    required NetBoatCreatureKind kind,
    required List<Point<double>> net,
  }) {
    if (kind == NetBoatCreatureKind.whale || net.length < 2) return null;
    final spec = specFor(kind);
    final axis = _unitVector(velocity);
    for (var index = 0; index < net.length - 1; index++) {
      final start = net[index];
      final end = net[index + 1];
      if ((end.x - start.x).abs() <= 1e-9 && (end.y - start.y).abs() <= 1e-9) {
        continue;
      }
      if (!movingCreatureTouchesNet(
        previousCreature: previousCreature,
        creature: creature,
        direction: velocity,
        kind: kind,
        net: [start, end],
      )) {
        continue;
      }

      final segment = Point<double>(end.x - start.x, end.y - start.y);
      final tangent = _unitVector(segment);
      final normal = Point<double>(-tangent.y, tangent.x);
      final previousOffset =
          (previousCreature.x - start.x) * normal.x +
          (previousCreature.y - start.y) * normal.y;
      final velocityNormal = velocity.x * normal.x + velocity.y * normal.y;
      final side = previousOffset.abs() > 1e-6
          ? (previousOffset.isNegative ? -1.0 : 1.0)
          : (velocityNormal <= 0 ? 1.0 : -1.0);
      final centerLineHalfLength =
          spec.netContactHalfLength - spec.netContactHalfWidth;
      final clearance =
          netVisualHalfWidth +
          spec.netContactHalfWidth +
          centerLineHalfLength * (axis.x * normal.x + axis.y * normal.y).abs() +
          netBounceSeparation;
      final closest = _closestPointOnSegment(creature, start, end);
      final corrected = Point<double>(
        closest.x + normal.x * side * clearance,
        closest.y + normal.y * side * clearance,
      );
      final reflected = velocityNormal * side < 0
          ? Point<double>(
              velocity.x - 2 * velocityNormal * normal.x,
              velocity.y - 2 * velocityNormal * normal.y,
            )
          : velocity;
      return NetBoatNetBounce(position: corrected, velocity: reflected);
    }
    return null;
  }

  static int clampSubmittedScore(int score) =>
      score.clamp(0, maximumSubmittedScore);

  static String formatScore(int score) => '${formatHudScore(score)}점';

  static String formatHudScore(int score) {
    final digits = clampSubmittedScore(score).toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  static bool isBoatInsidePlayArea(
    Point<double> center, {
    required NetBoatDirection direction,
  }) {
    final vertical =
        direction == NetBoatDirection.north ||
        direction == NetBoatDirection.south;
    final halfX = vertical
        ? boatWallCollisionHalfWidth
        : boatWallCollisionHalfLength;
    final halfY = vertical
        ? boatWallCollisionHalfLength
        : boatWallCollisionHalfWidth;
    return center.x - halfX >= playLeft - horizontalWallForgiveness &&
        center.x + halfX <= playRight + horizontalWallForgiveness &&
        center.y - halfY >= playTop - verticalWallForgiveness &&
        center.y + halfY <= playBottom + verticalWallForgiveness;
  }

  static Point<double> _unitVector(Point<double> vector) {
    final length = sqrt(vector.x * vector.x + vector.y * vector.y);
    return length <= 1e-9
        ? const Point<double>(1, 0)
        : Point<double>(vector.x / length, vector.y / length);
  }

  static double _segmentDistanceSquared(
    Point<double> firstStart,
    Point<double> firstEnd,
    Point<double> secondStart,
    Point<double> secondEnd,
  ) {
    if (_segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd)) {
      return 0;
    }
    return min(
      min(
        _pointSegmentDistanceSquared(firstStart, secondStart, secondEnd),
        _pointSegmentDistanceSquared(firstEnd, secondStart, secondEnd),
      ),
      min(
        _pointSegmentDistanceSquared(secondStart, firstStart, firstEnd),
        _pointSegmentDistanceSquared(secondEnd, firstStart, firstEnd),
      ),
    );
  }

  static bool _segmentsIntersect(
    Point<double> a,
    Point<double> b,
    Point<double> c,
    Point<double> d,
  ) {
    final first = _cross(a, b, c);
    final second = _cross(a, b, d);
    final third = _cross(c, d, a);
    final fourth = _cross(c, d, b);
    if (first * second < 0 && third * fourth < 0) return true;
    return (first.abs() <= 1e-9 && _pointOnSegment(c, a, b)) ||
        (second.abs() <= 1e-9 && _pointOnSegment(d, a, b)) ||
        (third.abs() <= 1e-9 && _pointOnSegment(a, c, d)) ||
        (fourth.abs() <= 1e-9 && _pointOnSegment(b, c, d));
  }

  static bool _pointOnSegment(
    Point<double> point,
    Point<double> start,
    Point<double> end,
  ) =>
      point.x >= min(start.x, end.x) - 1e-9 &&
      point.x <= max(start.x, end.x) + 1e-9 &&
      point.y >= min(start.y, end.y) - 1e-9 &&
      point.y <= max(start.y, end.y) + 1e-9;

  static double _cross(
    Point<double> origin,
    Point<double> end,
    Point<double> point,
  ) =>
      (end.x - origin.x) * (point.y - origin.y) -
      (end.y - origin.y) * (point.x - origin.x);

  static double _pointSegmentDistanceSquared(
    Point<double> point,
    Point<double> start,
    Point<double> end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 1e-9) {
      final px = point.x - start.x;
      final py = point.y - start.y;
      return px * px + py * py;
    }
    final progress =
        (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
            .clamp(0.0, 1.0);
    final px = point.x - (start.x + dx * progress);
    final py = point.y - (start.y + dy * progress);
    return px * px + py * py;
  }

  static Point<double> _closestPointOnSegment(
    Point<double> point,
    Point<double> start,
    Point<double> end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 1e-9) return start;
    final progress =
        (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
            .clamp(0.0, 1.0);
    return Point(start.x + dx * progress, start.y + dy * progress);
  }

  /// Finds the loop closed by the newest segment in an orthogonal polyline.
  /// The most recently authored intersected segment wins. A visual near miss
  /// inside the rendered net thickness is snapped to the same intersection.
  static NetLoop? latestLoop(List<Point<double>> points) {
    if (points.length < 4) return null;
    final newestStart = points[points.length - 2];
    final newestEnd = points.last;
    _Intersection? selected;
    for (var index = 0; index <= points.length - 4; index++) {
      final hit = _orthogonalIntersection(
        points[index],
        points[index + 1],
        newestStart,
        newestEnd,
        tolerance: netClosureTolerance,
      );
      if (hit == null) continue;
      if (selected == null || index > selected.segmentIndex) {
        selected = _Intersection(index, hit);
      }
    }
    if (selected == null) return null;
    final polygon = <Point<double>>[
      selected.point,
      ...points.sublist(selected.segmentIndex + 1, points.length - 1),
    ];
    if (!_samePoint(polygon.first, polygon.last)) {
      polygon.add(polygon.first);
    }
    if (polygon.length < 4 || polygonArea(polygon).abs() <= 1e-6) return null;
    return NetLoop(intersection: selected.point, polygon: polygon);
  }

  static Point<double>? _orthogonalIntersection(
    Point<double> a,
    Point<double> b,
    Point<double> c,
    Point<double> d, {
    double tolerance = 0,
  }) {
    final firstVertical = (a.x - b.x).abs() <= 1e-6;
    final secondVertical = (c.x - d.x).abs() <= 1e-6;
    if (firstVertical == secondVertical) {
      // Collinear retracing is not a closed area by itself.
      return null;
    }
    final verticalA = firstVertical ? a : c;
    final verticalB = firstVertical ? b : d;
    final horizontalA = firstVertical ? c : a;
    final horizontalB = firstVertical ? d : b;
    final x = verticalA.x;
    final y = horizontalA.y;
    final horizontalGap = _rangeGap(x, horizontalA.x, horizontalB.x);
    final verticalGap = _rangeGap(y, verticalA.y, verticalB.y);
    if (sqrt(horizontalGap * horizontalGap + verticalGap * verticalGap) >
        tolerance + 1e-6) {
      return null;
    }
    return Point(x, y);
  }

  static double _rangeGap(double value, double a, double b) {
    final lower = min(a, b);
    final upper = max(a, b);
    if (value < lower) return lower - value;
    if (value > upper) return value - upper;
    return 0;
  }

  static bool pointInPolygonInclusive(
    Point<double> point,
    List<Point<double>> polygon,
  ) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[j];
      final b = polygon[i];
      if (distanceToSegment(point, a, b) <= 1e-6) return true;
      final crosses =
          ((a.y > point.y) != (b.y > point.y)) &&
          (point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x);
      if (crosses) inside = !inside;
    }
    return inside;
  }

  static double polygonArea(List<Point<double>> polygon) {
    var twiceArea = 0.0;
    for (var i = 0; i < polygon.length - 1; i++) {
      twiceArea +=
          polygon[i].x * polygon[i + 1].y - polygon[i + 1].x * polygon[i].y;
    }
    return twiceArea / 2;
  }

  static double distanceToPolyline(
    Point<double> point,
    List<Point<double>> polyline,
  ) {
    if (polyline.length < 2) return double.infinity;
    var closest = double.infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      closest = min(
        closest,
        distanceToSegment(point, polyline[i], polyline[i + 1]),
      );
    }
    return closest;
  }

  static double distanceToSegment(
    Point<double> point,
    Point<double> start,
    Point<double> end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared <= 1e-12) return _distance(point, start);
    final t =
        (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
            .clamp(0.0, 1.0);
    return _distance(point, Point(start.x + dx * t, start.y + dy * t));
  }

  static bool _samePoint(Point<double> a, Point<double> b) =>
      (a.x - b.x).abs() <= 1e-6 && (a.y - b.y).abs() <= 1e-6;

  static double _distance(Point<double> a, Point<double> b) =>
      sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
}

class _Intersection {
  const _Intersection(this.segmentIndex, this.point);

  final int segmentIndex;
  final Point<double> point;
}
