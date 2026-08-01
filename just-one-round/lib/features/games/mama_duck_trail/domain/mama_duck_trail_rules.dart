import 'dart:math';

enum MamaDuckFeverTier { none, goldenTrail, sparkling, radiant }

class MamaDuckCell {
  const MamaDuckCell(this.row, this.column);

  final int row;
  final int column;

  int get index => row * MamaDuckTrailRules.columnCount + column;

  int manhattanDistanceTo(MamaDuckCell other) =>
      (row - other.row).abs() + (column - other.column).abs();

  @override
  bool operator ==(Object other) =>
      other is MamaDuckCell && row == other.row && column == other.column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'MamaDuckCell($row, $column)';
}

abstract final class MamaDuckTrailRules {
  static const gameId = 'mama_duck_trail';
  static const successTravelDurationSeconds = 0.58;
  static const successCheerDurationSeconds = 1.5;
  static const successFollowerSpacingCells = 1.0;
  static const successDurationSeconds =
      successTravelDurationSeconds + successCheerDurationSeconds;
  static const rulesVersion = 1;
  static const rowCount = 7;
  static const columnCount = 5;
  static const boardCellCount = rowCount * columnCount;
  static const gameDuration = Duration(seconds: 120);
  static const startingLives = 3;
  static const initialPathLength = 4;
  static const pathStepSeconds = 0.22;
  static const recallReadyDelaySeconds = 0.35;
  static const failureDurationSeconds = 1.0;
  static const maximumCombo = 10;
  static const pathPointValue = 100;
  static const comboPointValue = 25;
  static const maximumSubmittedScore = 100000;
  static const maximumStraightSteps = 2;
  static const maximumGeneratedPathLength = boardCellCount;
  static const maximumVisibleRescuedDucks = 5;
  static const goldenTrailCombo = 3;
  static const sparklingFeverCombo = 5;
  static const radiantFeverCombo = 7;

  static int pathLengthAfterSuccesses(int successfulRounds) => min(
    initialPathLength + max(0, successfulRounds),
    maximumGeneratedPathLength,
  );

  static MamaDuckFeverTier feverTierForCombo(int combo) {
    if (combo >= radiantFeverCombo) return MamaDuckFeverTier.radiant;
    if (combo >= sparklingFeverCombo) return MamaDuckFeverTier.sparkling;
    if (combo >= goldenTrailCombo) return MamaDuckFeverTier.goldenTrail;
    return MamaDuckFeverTier.none;
  }

  static int visibleRescuedDuckCount(int successfulRounds) =>
      min(max(0, successfulRounds), maximumVisibleRescuedDucks);

  static int hiddenRescuedDuckCount(int successfulRounds) =>
      max(0, successfulRounds - maximumVisibleRescuedDucks);

  static double successLeaderFinalDistance(int pathLength) =>
      max(0, pathLength - 2).toDouble();

  static double travelingDuckDistance({
    required double leaderDistance,
    required int followerIndex,
  }) => leaderDistance - max(0, followerIndex) * successFollowerSpacingCells;

  static double holdSecondsAt(double elapsedSeconds) {
    final elapsed = elapsedSeconds.clamp(0, gameDuration.inSeconds);
    if (elapsed < 50) {
      return 2;
    }
    if (elapsed < 70) {
      return 1.5;
    }
    return 1.1;
  }

  static int dailySeed(DateTime utcDate) {
    final utc = utcDate.toUtc();
    final day = utc.year * 10000 + utc.month * 100 + utc.day;
    return day * 31 + rulesVersion;
  }

  static List<MamaDuckCell> generatePath(Random random, int length) {
    if (length < 2 || length > maximumGeneratedPathLength) {
      throw RangeError.range(length, 2, maximumGeneratedPathLength, 'length');
    }

    for (var attempt = 0; attempt < 32; attempt++) {
      final start = MamaDuckCell(rowCount - 1, random.nextInt(columnCount));
      final path = <MamaDuckCell>[start];
      final visited = <MamaDuckCell>{start};
      final searchBudget = <int>[5000];
      if (_extendPath(random, path, visited, length, searchBudget)) {
        return List.unmodifiable(path);
      }
    }

    return List.unmodifiable(_randomizedFallbackPath(random).take(length));
  }

  static bool _extendPath(
    Random random,
    List<MamaDuckCell> path,
    Set<MamaDuckCell> visited,
    int targetLength,
    List<int> searchBudget,
  ) {
    if (path.length == targetLength) return true;
    if (--searchBudget[0] <= 0) return false;

    final current = path.last;
    final previousDirection = path.length < 2
        ? null
        : _directionBetween(path[path.length - 2], current);
    final straightSteps = _trailingStraightSteps(path);
    final candidates = _neighbors(current)
        .where((cell) => !visited.contains(cell))
        .where(
          (cell) =>
              previousDirection == null ||
              _directionBetween(current, cell) != previousDirection ||
              straightSteps < maximumStraightSteps,
        )
        .toList();
    candidates.shuffle(random);

    for (final candidate in candidates) {
      path.add(candidate);
      visited.add(candidate);
      if (_extendPath(random, path, visited, targetLength, searchBudget)) {
        return true;
      }
      visited.remove(candidate);
      path.removeLast();
    }
    return false;
  }

  static Iterable<MamaDuckCell> _neighbors(MamaDuckCell cell) sync* {
    const offsets = <(int, int)>[(-1, 0), (0, 1), (1, 0), (0, -1)];
    for (final (rowOffset, columnOffset) in offsets) {
      final next = MamaDuckCell(
        cell.row + rowOffset,
        cell.column + columnOffset,
      );
      if (isInsideBoard(next)) yield next;
    }
  }

  static bool isInsideBoard(MamaDuckCell cell) =>
      cell.row >= 0 &&
      cell.row < rowCount &&
      cell.column >= 0 &&
      cell.column < columnCount;

  static bool isValidPath(List<MamaDuckCell> path, {int? expectedLength}) {
    if (path.length < 2 ||
        (expectedLength != null && path.length != expectedLength)) {
      return false;
    }
    final visited = <MamaDuckCell>{};
    for (var index = 0; index < path.length; index++) {
      final cell = path[index];
      if (!isInsideBoard(cell) || !visited.add(cell)) return false;
      if (index > 0 && path[index - 1].manhattanDistanceTo(cell) != 1) {
        return false;
      }
    }
    return true;
  }

  static int turnCount(List<MamaDuckCell> path) {
    if (path.length < 3) return 0;
    var turns = 0;
    var previousDirection = _directionBetween(path[0], path[1]);
    for (var index = 2; index < path.length; index++) {
      final direction = _directionBetween(path[index - 1], path[index]);
      if (direction != previousDirection) turns++;
      previousDirection = direction;
    }
    return turns;
  }

  static int maximumStraightRun(List<MamaDuckCell> path) {
    if (path.length < 2) return 0;
    var maximum = 1;
    var current = 1;
    var previousDirection = _directionBetween(path[0], path[1]);
    for (var index = 2; index < path.length; index++) {
      final direction = _directionBetween(path[index - 1], path[index]);
      if (direction == previousDirection) {
        current++;
        maximum = max(maximum, current);
      } else {
        current = 1;
        previousDirection = direction;
      }
    }
    return maximum;
  }

  static int _trailingStraightSteps(List<MamaDuckCell> path) {
    if (path.length < 2) return 0;
    final direction = _directionBetween(path[path.length - 2], path.last);
    var steps = 1;
    for (var index = path.length - 2; index > 0; index--) {
      if (_directionBetween(path[index - 1], path[index]) != direction) break;
      steps++;
    }
    return steps;
  }

  static int _directionBetween(MamaDuckCell from, MamaDuckCell to) {
    if (to.row < from.row) return 0;
    if (to.column > from.column) return 1;
    if (to.row > from.row) return 2;
    return 3;
  }

  static bool isExpectedStep({
    required List<MamaDuckCell> target,
    required int enteredCount,
    required MamaDuckCell candidate,
  }) =>
      enteredCount >= 0 &&
      enteredCount < target.length &&
      target[enteredCount] == candidate;

  static int scoreForSuccess({
    required int pathLength,
    required int comboAfterSuccess,
  }) {
    final combo = comboAfterSuccess.clamp(1, maximumCombo);
    return pathLength * pathPointValue + combo * comboPointValue;
  }

  static String formatScore(int score) => '${_withThousands(score)}점';

  static String formatHudScore(int score) => _withThousands(score);

  static String _withThousands(int value) {
    final digits = max(0, value).toString();
    final output = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        output.write(',');
      }
      output.write(digits[index]);
    }
    return output.toString();
  }

  static List<MamaDuckCell> _randomizedFallbackPath(Random random) {
    final flipColumns = random.nextBool();
    return _fallbackFullBoardPath
        .map(
          (cell) => MamaDuckCell(
            cell.row,
            flipColumns ? columnCount - 1 - cell.column : cell.column,
          ),
        )
        .toList();
  }

  static const _fallbackFullBoardPath = <MamaDuckCell>[
    MamaDuckCell(6, 0),
    MamaDuckCell(5, 0),
    MamaDuckCell(4, 0),
    MamaDuckCell(4, 1),
    MamaDuckCell(5, 1),
    MamaDuckCell(6, 1),
    MamaDuckCell(6, 2),
    MamaDuckCell(5, 2),
    MamaDuckCell(5, 3),
    MamaDuckCell(6, 3),
    MamaDuckCell(6, 4),
    MamaDuckCell(5, 4),
    MamaDuckCell(4, 4),
    MamaDuckCell(4, 3),
    MamaDuckCell(4, 2),
    MamaDuckCell(3, 2),
    MamaDuckCell(3, 1),
    MamaDuckCell(3, 0),
    MamaDuckCell(2, 0),
    MamaDuckCell(2, 1),
    MamaDuckCell(1, 1),
    MamaDuckCell(1, 0),
    MamaDuckCell(0, 0),
    MamaDuckCell(0, 1),
    MamaDuckCell(0, 2),
    MamaDuckCell(1, 2),
    MamaDuckCell(2, 2),
    MamaDuckCell(2, 3),
    MamaDuckCell(3, 3),
    MamaDuckCell(3, 4),
    MamaDuckCell(2, 4),
    MamaDuckCell(1, 4),
    MamaDuckCell(1, 3),
    MamaDuckCell(0, 3),
    MamaDuckCell(0, 4),
  ];
}
