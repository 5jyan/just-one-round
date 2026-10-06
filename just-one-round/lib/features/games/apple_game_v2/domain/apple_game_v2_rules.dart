import 'dart:math';

class AppleCellRange {
  const AppleCellRange({
    required this.startRow,
    required this.startColumn,
    required this.endRow,
    required this.endColumn,
  });

  final int startRow;
  final int startColumn;
  final int endRow;
  final int endColumn;

  int get top => min(startRow, endRow);
  int get bottom => max(startRow, endRow);
  int get left => min(startColumn, endColumn);
  int get right => max(startColumn, endColumn);
}

abstract final class AppleGameV2Rules {
  static const rowCount = 13;
  static const columnCount = 8;
  static const targetSum = 10;
  static const gameDuration = Duration(seconds: 140);
  static const maximumScore = rowCount * columnCount;
  static const appleValueWeights = <int>[19, 16, 14, 12, 10, 9, 8, 7, 5];
  static const _totalAppleValueWeight = 100;

  static List<List<int?>> createBoard(Random random) {
    for (var attempt = 0; attempt < 100; attempt++) {
      final board = _createCandidateBoard(random);
      if (board == null) continue;
      if (countAvailableMoves(board, stopAfter: 12) >= 12) return board;
    }

    final fallbackRandom = Random(0xA991E);
    for (var attempt = 0; attempt < 100; attempt++) {
      final board = _createCandidateBoard(fallbackRandom);
      if (board != null && countAvailableMoves(board, stopAfter: 12) >= 12) {
        return board;
      }
    }
    throw StateError('Unable to create a valid apple board.');
  }

  static int randomAppleValue(Random random) {
    final ticket = random.nextInt(_totalAppleValueWeight);
    var cumulativeWeight = 0;
    for (var index = 0; index < appleValueWeights.length; index++) {
      cumulativeWeight += appleValueWeights[index];
      if (ticket < cumulativeWeight) return index + 1;
    }
    return appleValueWeights.length;
  }

  static List<List<int?>>? _createCandidateBoard(Random random) {
    var sum = 0;
    final board = List.generate(
      rowCount,
      (row) => List<int?>.generate(columnCount, (column) {
        if (row == rowCount - 1 && column == columnCount - 1) {
          return 1;
        }
        final value = randomAppleValue(random);
        sum += value;
        return value;
      }, growable: false),
      growable: false,
    );
    final balancingValue = targetSum - (sum % targetSum);
    if (balancingValue == targetSum) return null;
    board[rowCount - 1][columnCount - 1] = balancingValue;
    return board;
  }

  static int selectionSum(List<List<int?>> board, AppleCellRange range) {
    var sum = 0;
    for (var row = range.top; row <= range.bottom; row++) {
      for (var column = range.left; column <= range.right; column++) {
        sum += board[row][column] ?? 0;
      }
    }
    return sum;
  }

  static int selectedAppleCount(List<List<int?>> board, AppleCellRange range) {
    var count = 0;
    for (var row = range.top; row <= range.bottom; row++) {
      for (var column = range.left; column <= range.right; column++) {
        if (board[row][column] != null) count++;
      }
    }
    return count;
  }

  static List<(int, int)> orderedSelectedCells(
    List<List<int?>> board,
    AppleCellRange range,
  ) {
    final rowStep = range.endRow >= range.startRow ? 1 : -1;
    final columnStep = range.endColumn >= range.startColumn ? 1 : -1;
    final cells = <(int, int)>[];

    for (
      var row = range.startRow;
      row != range.endRow + rowStep;
      row += rowStep
    ) {
      for (
        var column = range.startColumn;
        column != range.endColumn + columnStep;
        column += columnStep
      ) {
        if (board[row][column] != null) cells.add((row, column));
      }
    }
    return cells;
  }

  static int removeSelection(List<List<int?>> board, AppleCellRange range) {
    if (selectionSum(board, range) != targetSum) return 0;
    final removed = selectedAppleCount(board, range);
    if (removed == 0) return 0;
    for (var row = range.top; row <= range.bottom; row++) {
      for (var column = range.left; column <= range.right; column++) {
        board[row][column] = null;
      }
    }
    return removed;
  }

  static bool hasAnyMove(List<List<int?>> board) =>
      countAvailableMoves(board, stopAfter: 1) > 0;

  static bool isBoardCleared(List<List<int?>> board) =>
      board.every((row) => row.every((apple) => apple == null));

  static int countAvailableMoves(List<List<int?>> board, {int? stopAfter}) {
    var count = 0;
    for (var top = 0; top < rowCount; top++) {
      final columnSums = List<int>.filled(columnCount, 0);
      for (var bottom = top; bottom < rowCount; bottom++) {
        for (var column = 0; column < columnCount; column++) {
          columnSums[column] += board[bottom][column] ?? 0;
        }
        for (var left = 0; left < columnCount; left++) {
          var sum = 0;
          for (var right = left; right < columnCount; right++) {
            sum += columnSums[right];
            if (sum == targetSum) {
              count++;
              if (stopAfter != null && count >= stopAfter) return count;
            }
            if (sum >= targetSum) break;
          }
        }
      }
    }
    return count;
  }

  static String formatApples(int score) => '$score개';
}
