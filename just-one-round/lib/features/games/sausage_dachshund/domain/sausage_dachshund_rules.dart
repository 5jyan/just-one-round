import 'dart:collection';
import 'dart:math';

enum DachshundDirection {
  up(-1, 0),
  right(0, 1),
  down(1, 0),
  left(0, -1);

  const DachshundDirection(this.rowDelta, this.columnDelta);

  final int rowDelta;
  final int columnDelta;

  DachshundDirection get opposite => switch (this) {
    DachshundDirection.up => DachshundDirection.down,
    DachshundDirection.right => DachshundDirection.left,
    DachshundDirection.down => DachshundDirection.up,
    DachshundDirection.left => DachshundDirection.right,
  };
}

class DachshundCell {
  const DachshundCell(this.row, this.column);

  final int row;
  final int column;

  DachshundCell moved(DachshundDirection direction) =>
      DachshundCell(row + direction.rowDelta, column + direction.columnDelta);

  int manhattanDistanceTo(DachshundCell other) =>
      (row - other.row).abs() + (column - other.column).abs();

  @override
  bool operator ==(Object other) =>
      other is DachshundCell && row == other.row && column == other.column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'DachshundCell($row, $column)';
}

enum DachshundFinishReason { wall, self, timeout, boardComplete }

class DachshundStepResult {
  const DachshundStepResult({
    required this.moved,
    required this.ateSausage,
    this.finishReason,
  });

  final bool moved;
  final bool ateSausage;
  final DachshundFinishReason? finishReason;

  bool get isFinished => finishReason != null;
}

class SausageDachshundState {
  SausageDachshundState._(
    this._body, {
    required this.direction,
    required this.sausage,
    required this.score,
  });

  factory SausageDachshundState.initial() => SausageDachshundState._(
    List<DachshundCell>.of(SausageDachshundRules.initialBody),
    direction: DachshundDirection.right,
    sausage: SausageDachshundRules.initialSausage,
    score: 0,
  );

  factory SausageDachshundState.forTesting({
    required List<DachshundCell> body,
    required DachshundDirection direction,
    required DachshundCell? sausage,
    int score = 0,
  }) {
    if (body.isEmpty || body.toSet().length != body.length) {
      throw ArgumentError.value(body, 'body', 'must be non-empty and unique');
    }
    return SausageDachshundState._(
      List<DachshundCell>.of(body),
      direction: direction,
      sausage: sausage,
      score: score,
    );
  }

  final List<DachshundCell> _body;
  DachshundDirection direction;
  DachshundDirection? _queuedDirection;
  DachshundCell? sausage;
  int score;
  DachshundFinishReason? finishReason;

  List<DachshundCell> get body => List.unmodifiable(_body);
  DachshundCell get head => _body.first;
  DachshundCell get tail => _body.last;
  DachshundDirection? get queuedDirection => _queuedDirection;
  bool get isFinished => finishReason != null;

  bool queueDirection(DachshundDirection candidate) {
    if (isFinished ||
        _queuedDirection != null ||
        candidate == direction ||
        candidate == direction.opposite) {
      return false;
    }
    _queuedDirection = candidate;
    return true;
  }

  DachshundStepResult step(Random random) {
    if (isFinished) {
      return DachshundStepResult(
        moved: false,
        ateSausage: false,
        finishReason: finishReason,
      );
    }

    direction = _queuedDirection ?? direction;
    _queuedDirection = null;
    final nextHead = head.moved(direction);
    if (!SausageDachshundRules.isInsideBoard(nextHead)) {
      finishReason = DachshundFinishReason.wall;
      return const DachshundStepResult(
        moved: false,
        ateSausage: false,
        finishReason: DachshundFinishReason.wall,
      );
    }

    final ate = nextHead == sausage;
    final collisionBody = ate ? _body : _body.take(_body.length - 1);
    if (collisionBody.contains(nextHead)) {
      finishReason = DachshundFinishReason.self;
      return const DachshundStepResult(
        moved: false,
        ateSausage: false,
        finishReason: DachshundFinishReason.self,
      );
    }

    _body.insert(0, nextHead);
    if (ate) {
      score = min(SausageDachshundRules.maximumScore, score + 1);
      sausage = SausageDachshundRules.chooseReachableSausage(
        body: _body,
        random: random,
      );
      if (sausage == null) {
        finishReason = DachshundFinishReason.boardComplete;
      }
    } else {
      _body.removeLast();
    }

    return DachshundStepResult(
      moved: true,
      ateSausage: ate,
      finishReason: finishReason,
    );
  }

  void finishForTimeout() {
    if (!isFinished) finishReason = DachshundFinishReason.timeout;
  }
}

abstract final class SausageDachshundRules {
  static const gameId = 'sausage_dachshund';
  static const rulesVersion = 1;
  static const rowCount = 15;
  static const columnCount = 9;
  static const boardCellCount = rowCount * columnCount;
  static const initialBodyLength = 4;
  static const maximumScore = boardCellCount - initialBodyLength;
  static const gameDuration = Duration(seconds: 150);
  static const swipeThreshold = 18.0;

  static const initialBody = <DachshundCell>[
    DachshundCell(7, 4),
    DachshundCell(7, 3),
    DachshundCell(7, 2),
    DachshundCell(7, 1),
  ];
  static const initialSausage = DachshundCell(7, 6);

  static bool isInsideBoard(DachshundCell cell) =>
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

  static DachshundDirection? directionForSwipe({
    required double deltaX,
    required double deltaY,
  }) {
    if (max(deltaX.abs(), deltaY.abs()) < swipeThreshold) return null;
    if (deltaX.abs() >= deltaY.abs()) {
      return deltaX >= 0 ? DachshundDirection.right : DachshundDirection.left;
    }
    return deltaY >= 0 ? DachshundDirection.down : DachshundDirection.up;
  }

  static List<DachshundCell> reachableEmptyCells({
    required List<DachshundCell> body,
  }) {
    if (body.isEmpty) return const [];
    final occupied = body.toSet();
    final start = body.first;
    final visited = <DachshundCell>{start};
    final queue = Queue<DachshundCell>()..add(start);
    final reachable = <DachshundCell>[];

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final direction in DachshundDirection.values) {
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

  static DachshundCell? chooseReachableSausage({
    required List<DachshundCell> body,
    required Random random,
  }) {
    final reachable = reachableEmptyCells(body: body);
    if (reachable.isEmpty) return null;
    final head = body.first;
    final preferred = reachable
        .where((cell) => head.manhattanDistanceTo(cell) >= 3)
        .toList(growable: false);
    final candidates = preferred.isNotEmpty ? preferred : reachable;
    return candidates[random.nextInt(candidates.length)];
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
