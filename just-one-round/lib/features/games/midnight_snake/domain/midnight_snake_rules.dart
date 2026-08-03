import 'dart:collection';
import 'dart:math';

enum SnakeDirection {
  up(-1, 0),
  right(0, 1),
  down(1, 0),
  left(0, -1);

  const SnakeDirection(this.rowDelta, this.columnDelta);

  final int rowDelta;
  final int columnDelta;

  SnakeDirection get opposite => switch (this) {
    SnakeDirection.up => SnakeDirection.down,
    SnakeDirection.right => SnakeDirection.left,
    SnakeDirection.down => SnakeDirection.up,
    SnakeDirection.left => SnakeDirection.right,
  };
}

class SnakeCell {
  const SnakeCell(this.row, this.column);

  final int row;
  final int column;

  SnakeCell moved(SnakeDirection direction) =>
      SnakeCell(row + direction.rowDelta, column + direction.columnDelta);

  int manhattanDistanceTo(SnakeCell other) =>
      (row - other.row).abs() + (column - other.column).abs();

  @override
  bool operator ==(Object other) =>
      other is SnakeCell && row == other.row && column == other.column;

  @override
  int get hashCode => Object.hash(row, column);
}

enum SnakeFinishReason { wall, self, timeout, boardComplete }

class SnakeStepResult {
  const SnakeStepResult({
    required this.moved,
    required this.ateFood,
    this.ateGoldenSausage = false,
    this.caughtMouse = false,
    this.scoreGained = 0,
    this.pickupCell,
    this.finishReason,
  });

  final bool moved;
  final bool ateFood;
  final bool ateGoldenSausage;
  final bool caughtMouse;
  final int scoreGained;
  final SnakeCell? pickupCell;
  final SnakeFinishReason? finishReason;

  bool get ateAnyPickup => ateFood || ateGoldenSausage || caughtMouse;
}

class MidnightSnakeState {
  MidnightSnakeState._(
    this._body, {
    required this.direction,
    required this.food,
    required this.foodTypeIndex,
    required this.score,
    required this.goldenSpawnAtSeconds,
    required this.mouseSpawnAtSeconds,
    this.goldenSausage,
    this.mouse,
    this.mouseDirection = SnakeDirection.down,
    this._goldenAppeared = false,
    this._goldenResolved = false,
    this._goldenExpiresAt,
    this._mouseAppeared = false,
    this._mouseResolved = false,
    this._mouseExpiresAt,
    this._mouseNextMoveAt,
  });

  factory MidnightSnakeState.initial({
    double goldenSpawnAtSeconds =
        MidnightSnakeRules.goldenSausageSpawnStartSeconds,
    double mouseSpawnAtSeconds = MidnightSnakeRules.mouseSpawnStartSeconds,
  }) => MidnightSnakeState._(
    List<SnakeCell>.of(MidnightSnakeRules.initialBody),
    direction: SnakeDirection.right,
    food: MidnightSnakeRules.initialFood,
    foodTypeIndex: 0,
    score: 0,
    goldenSpawnAtSeconds: goldenSpawnAtSeconds,
    mouseSpawnAtSeconds: mouseSpawnAtSeconds,
  );

  factory MidnightSnakeState.forTesting({
    required List<SnakeCell> body,
    required SnakeDirection direction,
    required SnakeCell? food,
    int foodTypeIndex = 0,
    int score = 0,
    double goldenSpawnAtSeconds =
        MidnightSnakeRules.goldenSausageSpawnStartSeconds,
    double mouseSpawnAtSeconds = MidnightSnakeRules.mouseSpawnStartSeconds,
    SnakeCell? goldenSausage,
    SnakeCell? mouse,
    SnakeDirection mouseDirection = SnakeDirection.down,
    bool goldenAppeared = false,
    bool goldenResolved = false,
    double? goldenExpiresAt,
    bool mouseAppeared = false,
    bool mouseResolved = false,
    double? mouseExpiresAt,
    double? mouseNextMoveAt,
  }) {
    if (body.isEmpty || body.toSet().length != body.length) {
      throw ArgumentError.value(body, 'body', 'must be non-empty and unique');
    }
    final occupied = body.toSet();
    if ([
      food,
      goldenSausage,
      mouse,
    ].whereType<SnakeCell>().any(occupied.contains)) {
      throw ArgumentError('pickups must not overlap the snake');
    }
    if (food != null && (food == goldenSausage || food == mouse) ||
        goldenSausage != null && goldenSausage == mouse) {
      throw ArgumentError('pickups must occupy distinct cells');
    }
    return MidnightSnakeState._(
      List<SnakeCell>.of(body),
      direction: direction,
      food: food,
      foodTypeIndex: foodTypeIndex,
      score: score,
      goldenSpawnAtSeconds: goldenSpawnAtSeconds,
      mouseSpawnAtSeconds: mouseSpawnAtSeconds,
      goldenSausage: goldenSausage,
      mouse: mouse,
      mouseDirection: mouseDirection,
      goldenAppeared: goldenAppeared || goldenSausage != null,
      goldenResolved: goldenResolved,
      goldenExpiresAt: goldenExpiresAt,
      mouseAppeared: mouseAppeared || mouse != null,
      mouseResolved: mouseResolved,
      mouseExpiresAt: mouseExpiresAt,
      mouseNextMoveAt: mouseNextMoveAt,
    );
  }

  final List<SnakeCell> _body;
  final Queue<SnakeDirection> _queuedDirections = Queue<SnakeDirection>();
  SnakeDirection direction;
  SnakeCell? food;
  int foodTypeIndex;
  int score;
  final double goldenSpawnAtSeconds;
  final double mouseSpawnAtSeconds;
  SnakeCell? goldenSausage;
  SnakeCell? mouse;
  SnakeDirection mouseDirection;
  SnakeFinishReason? finishReason;
  bool _goldenAppeared;
  bool _goldenResolved;
  double? _goldenExpiresAt;
  bool _mouseAppeared;
  bool _mouseResolved;
  double? _mouseExpiresAt;
  double? _mouseNextMoveAt;

  List<SnakeCell> get body => List.unmodifiable(_body);
  SnakeCell get head => _body.first;
  bool get isFinished => finishReason != null;
  bool get goldenHasAppeared => _goldenAppeared;
  bool get goldenIsResolved => _goldenResolved;
  bool get mouseHasAppeared => _mouseAppeared;
  bool get mouseIsResolved => _mouseResolved;

  bool queueDirection(SnakeDirection candidate) {
    if (isFinished ||
        _queuedDirections.length >=
            MidnightSnakeRules.maximumQueuedDirections) {
      return false;
    }
    final previous = _queuedDirections.isEmpty
        ? direction
        : _queuedDirections.last;
    if (candidate == previous || candidate == previous.opposite) return false;
    _queuedDirections.addLast(candidate);
    return true;
  }

  SnakeStepResult step(Random random) {
    if (isFinished) {
      return SnakeStepResult(
        moved: false,
        ateFood: false,
        finishReason: finishReason,
      );
    }

    if (_queuedDirections.isNotEmpty) {
      direction = _queuedDirections.removeFirst();
    }
    final nextHead = head.moved(direction);
    if (!MidnightSnakeRules.isInsideBoard(nextHead)) {
      finishReason = SnakeFinishReason.wall;
      return const SnakeStepResult(
        moved: false,
        ateFood: false,
        finishReason: SnakeFinishReason.wall,
      );
    }

    final ateFood = nextHead == food;
    final ateGoldenSausage = nextHead == goldenSausage;
    final caughtMouse = nextHead == mouse;
    final ateAnyPickup = ateFood || ateGoldenSausage || caughtMouse;
    final collisionBody = ateAnyPickup ? _body : _body.take(_body.length - 1);
    if (collisionBody.contains(nextHead)) {
      finishReason = SnakeFinishReason.self;
      return const SnakeStepResult(
        moved: false,
        ateFood: false,
        finishReason: SnakeFinishReason.self,
      );
    }

    _body.insert(0, nextHead);
    var scoreGained = 0;
    if (ateAnyPickup) {
      scoreGained = switch ((ateFood, ateGoldenSausage, caughtMouse)) {
        (true, _, _) => MidnightSnakeRules.regularFoodScore,
        (_, true, _) => MidnightSnakeRules.goldenSausageScore,
        (_, _, true) => MidnightSnakeRules.mouseScore,
        _ => 0,
      };
      score = min(MidnightSnakeRules.maximumScore, score + scoreGained);
    } else {
      _body.removeLast();
    }

    if (ateFood) {
      food = MidnightSnakeRules.chooseReachableFood(
        body: _body,
        random: random,
        blockedCells: {?goldenSausage, ?mouse},
      );
      foodTypeIndex = random.nextInt(MidnightSnakeRules.foodTypeCount);
      if (food == null) finishReason = SnakeFinishReason.boardComplete;
    }
    if (ateGoldenSausage) {
      goldenSausage = null;
      _goldenResolved = true;
      _goldenExpiresAt = null;
    }
    if (caughtMouse) {
      mouse = null;
      _mouseResolved = true;
      _mouseExpiresAt = null;
      _mouseNextMoveAt = null;
    }

    return SnakeStepResult(
      moved: true,
      ateFood: ateFood,
      ateGoldenSausage: ateGoldenSausage,
      caughtMouse: caughtMouse,
      scoreGained: scoreGained,
      pickupCell: ateAnyPickup ? nextHead : null,
      finishReason: finishReason,
    );
  }

  void updateBonusEvents({
    required double elapsedSeconds,
    required Random random,
  }) {
    if (isFinished) return;

    _expireGoldenSausage(elapsedSeconds);
    _trySpawnGoldenSausage(elapsedSeconds, random);
    _expireMouse(elapsedSeconds);
    _trySpawnMouse(elapsedSeconds, random);
    _moveMouse(elapsedSeconds, random);
  }

  void _expireGoldenSausage(double elapsedSeconds) {
    final expiresAt = _goldenExpiresAt;
    if (goldenSausage != null &&
        expiresAt != null &&
        elapsedSeconds >= expiresAt) {
      goldenSausage = null;
      _goldenResolved = true;
      _goldenExpiresAt = null;
    }
  }

  void _trySpawnGoldenSausage(double elapsedSeconds, Random random) {
    if (_goldenAppeared || _goldenResolved) return;
    if (elapsedSeconds <
        goldenSpawnAtSeconds.clamp(
          MidnightSnakeRules.goldenSausageSpawnStartSeconds,
          MidnightSnakeRules.goldenSausageSpawnEndSeconds,
        )) {
      return;
    }
    if (elapsedSeconds > MidnightSnakeRules.goldenSausageSpawnEndSeconds) {
      _goldenResolved = true;
      return;
    }

    final selected = MidnightSnakeRules.chooseReachableCorner(
      body: _body,
      random: random,
      blockedCells: {?food, ?mouse},
    );
    if (selected == null) return;
    goldenSausage = selected;
    _goldenAppeared = true;
    _goldenExpiresAt =
        elapsedSeconds + MidnightSnakeRules.goldenSausageLifetimeSeconds;
  }

  void _expireMouse(double elapsedSeconds) {
    final expiresAt = _mouseExpiresAt;
    if (mouse != null && expiresAt != null && elapsedSeconds >= expiresAt) {
      mouse = null;
      _mouseResolved = true;
      _mouseExpiresAt = null;
      _mouseNextMoveAt = null;
    }
  }

  void _trySpawnMouse(double elapsedSeconds, Random random) {
    if (_mouseAppeared || _mouseResolved || !_goldenResolved) return;
    if (elapsedSeconds <
        mouseSpawnAtSeconds.clamp(
          MidnightSnakeRules.mouseSpawnStartSeconds,
          MidnightSnakeRules.mouseSpawnEndSeconds,
        )) {
      return;
    }
    if (elapsedSeconds > MidnightSnakeRules.mouseSpawnEndSeconds) {
      _mouseResolved = true;
      return;
    }

    final selected = MidnightSnakeRules.chooseMouseSpawn(
      body: _body,
      random: random,
      blockedCells: {?food, ?goldenSausage},
    );
    if (selected == null) return;
    mouse = selected;
    _mouseAppeared = true;
    _mouseExpiresAt = elapsedSeconds + MidnightSnakeRules.mouseLifetimeSeconds;
    _mouseNextMoveAt =
        elapsedSeconds + MidnightSnakeRules.mouseMoveIntervalSeconds;
  }

  void _moveMouse(double elapsedSeconds, Random random) {
    final activeMouse = mouse;
    final nextMoveAt = _mouseNextMoveAt;
    if (activeMouse == null ||
        nextMoveAt == null ||
        elapsedSeconds < nextMoveAt) {
      return;
    }

    final movement = MidnightSnakeRules.chooseMouseMovement(
      mouse: activeMouse,
      currentDirection: mouseDirection,
      body: _body,
      food: food,
      goldenSausage: goldenSausage,
      random: random,
    );
    if (movement case (final direction, final destination)) {
      mouseDirection = direction;
      mouse = destination;
    }
    _mouseNextMoveAt = nextMoveAt + MidnightSnakeRules.mouseMoveIntervalSeconds;
    if (_mouseNextMoveAt! <= elapsedSeconds) {
      _mouseNextMoveAt =
          elapsedSeconds + MidnightSnakeRules.mouseMoveIntervalSeconds;
    }
  }

  void finishForTimeout() {
    if (!isFinished) finishReason = SnakeFinishReason.timeout;
  }
}

abstract final class MidnightSnakeRules {
  static const gameId = 'midnight_snake';
  static const rulesVersion = 2;
  static const rowCount = 15;
  static const columnCount = 9;
  static const initialBodyLength = 4;
  static const maximumQueuedDirections = 3;
  static const regularFoodScore = 1;
  static const goldenSausageScore = 3;
  static const mouseScore = 2;
  static const maximumBaseScore = rowCount * columnCount - initialBodyLength;
  static const maximumScore =
      maximumBaseScore +
      goldenSausageScore -
      regularFoodScore +
      mouseScore -
      regularFoodScore;
  static const foodTypeCount = 6;
  static const gameDuration = Duration(minutes: 5);
  static const swipeThreshold = 6.0;
  static const goldenSausageSpawnStartSeconds = 30.0;
  static const goldenSausageSpawnEndSeconds = 60.0;
  static const goldenSausageLifetimeSeconds = 10.0;
  static const mouseSpawnStartSeconds = 60.0;
  static const mouseSpawnEndSeconds = 90.0;
  static const mouseLifetimeSeconds = 15.0;
  static const mouseMoveIntervalSeconds = 1.0;

  static const initialBody = <SnakeCell>[
    SnakeCell(7, 4),
    SnakeCell(7, 3),
    SnakeCell(7, 2),
    SnakeCell(7, 1),
  ];
  static const initialFood = SnakeCell(7, 6);
  static const cornerCells = <SnakeCell>[
    SnakeCell(0, 0),
    SnakeCell(0, columnCount - 1),
    SnakeCell(rowCount - 1, 0),
    SnakeCell(rowCount - 1, columnCount - 1),
  ];

  static bool isInsideBoard(SnakeCell cell) =>
      cell.row >= 0 &&
      cell.row < rowCount &&
      cell.column >= 0 &&
      cell.column < columnCount;

  static double moveIntervalAt(double elapsedSeconds) {
    final elapsed = elapsedSeconds.clamp(0, gameDuration.inSeconds);
    if (elapsed < 3) return 0.60;
    if (elapsed < 30) return 0.50;
    if (elapsed < 50) return 0.42;
    if (elapsed < 90) return 0.35;
    if (elapsed < 120) return 0.29;
    return 0.25;
  }

  static SnakeDirection? directionForSwipe({
    required double deltaX,
    required double deltaY,
  }) {
    if (max(deltaX.abs(), deltaY.abs()) < swipeThreshold) return null;
    if (deltaX.abs() >= deltaY.abs()) {
      return deltaX >= 0 ? SnakeDirection.right : SnakeDirection.left;
    }
    return deltaY >= 0 ? SnakeDirection.down : SnakeDirection.up;
  }

  static List<SnakeCell> reachableEmptyCells({required List<SnakeCell> body}) {
    if (body.isEmpty) return const [];
    final occupied = body.toSet();
    final visited = <SnakeCell>{body.first};
    final queue = Queue<SnakeCell>()..add(body.first);
    final reachable = <SnakeCell>[];
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final direction in SnakeDirection.values) {
        final next = current.moved(direction);
        if (!isInsideBoard(next) ||
            occupied.contains(next) ||
            !visited.add(next)) {
          continue;
        }
        reachable.add(next);
        queue.add(next);
      }
    }
    reachable.sort(
      (a, b) => a.row != b.row
          ? a.row.compareTo(b.row)
          : a.column.compareTo(b.column),
    );
    return List.unmodifiable(reachable);
  }

  static SnakeCell? chooseReachableFood({
    required List<SnakeCell> body,
    required Random random,
    Set<SnakeCell> blockedCells = const {},
  }) {
    final reachable = reachableEmptyCells(
      body: body,
    ).where((cell) => !blockedCells.contains(cell)).toList(growable: false);
    if (reachable.isEmpty) return null;
    final head = body.first;
    final preferred = reachable
        .where((cell) => head.manhattanDistanceTo(cell) >= 3)
        .toList(growable: false);
    final candidates = preferred.isNotEmpty ? preferred : reachable;
    return candidates[random.nextInt(candidates.length)];
  }

  static SnakeCell? chooseReachableCorner({
    required List<SnakeCell> body,
    required Random random,
    Set<SnakeCell> blockedCells = const {},
  }) {
    final reachable = reachableEmptyCells(body: body).toSet();
    final candidates = cornerCells
        .where(
          (corner) =>
              reachable.contains(corner) && !blockedCells.contains(corner),
        )
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return candidates[random.nextInt(candidates.length)];
  }

  static SnakeCell? chooseMouseSpawn({
    required List<SnakeCell> body,
    required Random random,
    Set<SnakeCell> blockedCells = const {},
  }) {
    final head = body.first;
    final reachable = reachableEmptyCells(
      body: body,
    ).where((cell) => !blockedCells.contains(cell)).toList(growable: false);
    if (reachable.isEmpty) return null;
    final preferred = reachable
        .where((cell) => head.manhattanDistanceTo(cell) >= 4)
        .toList(growable: false);
    final candidates = preferred.isNotEmpty ? preferred : reachable;
    return candidates[random.nextInt(candidates.length)];
  }

  static (SnakeDirection, SnakeCell)? chooseMouseMovement({
    required SnakeCell mouse,
    required SnakeDirection currentDirection,
    required List<SnakeCell> body,
    required SnakeCell? food,
    required SnakeCell? goldenSausage,
    required Random random,
  }) {
    final blocked = <SnakeCell>{...body, ?food, ?goldenSausage};
    var candidates = [
      for (final direction in SnakeDirection.values)
        if (mouse.moved(direction) case final destination
            when isInsideBoard(destination) && !blocked.contains(destination))
          (direction, destination),
    ];
    if (candidates.isEmpty) return null;

    final forward = candidates
        .where((candidate) => candidate.$1 == currentDirection)
        .firstOrNull;
    if (forward != null && random.nextDouble() < 0.65) return forward;

    if (candidates.length > 1) {
      final withoutReverse = candidates
          .where((candidate) => candidate.$1 != currentDirection.opposite)
          .toList(growable: false);
      if (withoutReverse.isNotEmpty) candidates = withoutReverse;
    }
    return candidates[random.nextInt(candidates.length)];
  }

  static double spawnSecondInRange({
    required Random random,
    required int startInclusive,
    required int endInclusive,
  }) {
    if (endInclusive < startInclusive) {
      throw ArgumentError('endInclusive must not precede startInclusive');
    }
    return (startInclusive + random.nextInt(endInclusive - startInclusive + 1))
        .toDouble();
  }

  static int dailySeed(DateTime instant) {
    final koreaTime = instant.toUtc().add(const Duration(hours: 9));
    final playDate = koreaTime.hour < 6
        ? koreaTime.subtract(const Duration(days: 1))
        : koreaTime;
    final day = playDate.year * 10000 + playDate.month * 100 + playDate.day;
    return day * 31 + rulesVersion;
  }

  static String formatScore(int score) => '${max(0, score)}개';
  static String formatHudScore(int score) => max(0, score).toString();
}
