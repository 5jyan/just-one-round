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

abstract final class AppleGameRules {
  static const rowCount = 13;
  static const columnCount = 8;
  static const targetSum = 10;
  static const gameDuration = Duration(seconds: 140);
  static const maximumScore = rowCount * columnCount;

  static List<List<int?>> createBoard(Random random) {
    for (var attempt = 0; attempt < 100; attempt++) {
      var sum = 0;
      final board = List.generate(
        rowCount,
        (row) => List<int?>.generate(columnCount, (column) {
          if (row == rowCount - 1 && column == columnCount - 1) {
            return 1;
          }
          final value = 1 + random.nextInt(9);
          sum += value;
          return value;
        }, growable: false),
        growable: false,
      );
      final balancingValue = targetSum - (sum % targetSum);
      if (balancingValue == targetSum) continue;
      board[rowCount - 1][columnCount - 1] = balancingValue;
      if (countAvailableMoves(board, stopAfter: 12) >= 12) return board;
    }

    final fallback = List.generate(
      rowCount,
      (row) => List<int?>.generate(
        columnCount,
        (column) => 1 + ((row * 3 + column * 7) % 9),
        growable: false,
      ),
      growable: false,
    );
    fallback[0][0] = 4;
    fallback[0][1] = 6;
    var sumWithoutLast = 0;
    for (var row = 0; row < rowCount; row++) {
      for (var column = 0; column < columnCount; column++) {
        if (row == rowCount - 1 && column == columnCount - 1) continue;
        sumWithoutLast += fallback[row][column]!;
      }
    }
    var balancingValue = targetSum - (sumWithoutLast % targetSum);
    if (balancingValue == targetSum) {
      final previousValue = fallback[0][2]!;
      fallback[0][2] = previousValue == 9 ? 8 : previousValue + 1;
      sumWithoutLast += fallback[0][2]! - previousValue;
      balancingValue = targetSum - (sumWithoutLast % targetSum);
    }
    fallback[rowCount - 1][columnCount - 1] = balancingValue;
    return fallback;
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
