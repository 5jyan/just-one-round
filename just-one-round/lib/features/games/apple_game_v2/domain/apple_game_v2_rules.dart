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
  static const legacyRulesVersion = 1;
  static const rulesVersion = 2;
  static const maxBiasSwaps = 1;
  static const maxBiasSearchAttempts = 8;
  static const minimumAvailableMoves = 12;
  static const gameDuration = Duration(seconds: 140);
  static const maximumScore = rowCount * columnCount;
  static const appleValueWeights = <int>[19, 16, 14, 12, 10, 9, 8, 7, 5];
  static const _totalAppleValueWeight = 100;
  static const supportedRulesVersions = <int>{legacyRulesVersion, rulesVersion};

  static List<List<int?>> createBoard(
    Random random, {
    int rulesVersion = AppleGameV2Rules.rulesVersion,
  }) {
    _requireSupportedRulesVersion(rulesVersion);
    final board = _createLegacyValidBoard(random);
    if (rulesVersion == legacyRulesVersion) return board;

    _applyAdjacencyBias(board, random);
    return board;
  }

  static void _requireSupportedRulesVersion(int version) {
    if (!supportedRulesVersions.contains(version)) {
      throw UnsupportedError('Unsupported apple game rules version: $version');
    }
  }

  static int validateRulesVersion(int version) {
    _requireSupportedRulesVersion(version);
    return version;
  }

  static List<List<int?>> _createLegacyValidBoard(Random random) {
    for (var attempt = 0; attempt < 100; attempt++) {
      final board = _createCandidateBoard(random);
      if (board == null) continue;
      if (countAvailableMoves(board, stopAfter: minimumAvailableMoves) >=
          minimumAvailableMoves) {
        return board;
      }
    }

    final fallbackRandom = Random(0xA991E);
    for (var attempt = 0; attempt < 100; attempt++) {
      final board = _createCandidateBoard(fallbackRandom);
      if (board != null &&
          countAvailableMoves(board, stopAfter: minimumAvailableMoves) >=
              minimumAvailableMoves) {
        return board;
      }
    }
    throw StateError('Unable to create a valid apple board.');
  }

  static void _applyAdjacencyBias(List<List<int?>> board, Random random) {
    for (var attempt = 0; attempt < maxBiasSearchAttempts; attempt++) {
      final cellIndex = random.nextInt(maximumScore);
      final direction = random.nextInt(4);
      final neighbor = _orthogonalNeighbor(cellIndex, direction);
      if (neighbor == null) continue;

      final cellRow = cellIndex ~/ columnCount;
      final cellColumn = cellIndex % columnCount;
      final neighborValue = board[neighbor.$1][neighbor.$2];
      if (neighborValue == null) continue;
      final complement = targetSum - neighborValue;
      if (complement < 1 || complement > 9) continue;

      final complementCells = <(int, int)>[];
      for (var row = 0; row < rowCount; row++) {
        for (var column = 0; column < columnCount; column++) {
          if ((row == cellRow && column == cellColumn) ||
              (row == neighbor.$1 && column == neighbor.$2)) {
            continue;
          }
          if (board[row][column] == complement) {
            complementCells.add((row, column));
          }
        }
      }
      if (complementCells.isEmpty) continue;

      final other = complementCells[random.nextInt(complementCells.length)];
      final before = countAdjacentComplements(board);
      final originalCellValue = board[cellRow][cellColumn];
      board[cellRow][cellColumn] = board[other.$1][other.$2];
      board[other.$1][other.$2] = originalCellValue;

      final gain = countAdjacentComplements(board) - before;
      final stillPlayable =
          countAvailableMoves(board, stopAfter: minimumAvailableMoves) >=
          minimumAvailableMoves;
      if (gain >= 1 && gain <= 2 && stillPlayable) return;

      board[other.$1][other.$2] = board[cellRow][cellColumn];
      board[cellRow][cellColumn] = originalCellValue;
    }
  }

  static (int, int)? _orthogonalNeighbor(int cellIndex, int direction) {
    final row = cellIndex ~/ columnCount;
    final column = cellIndex % columnCount;
    final neighborRow = switch (direction) {
      0 => row - 1,
      1 => row + 1,
      _ => row,
    };
    final neighborColumn = switch (direction) {
      2 => column - 1,
      3 => column + 1,
      _ => column,
    };
    if (neighborRow < 0 ||
        neighborRow >= rowCount ||
        neighborColumn < 0 ||
        neighborColumn >= columnCount) {
      return null;
    }
    return (neighborRow, neighborColumn);
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

  static int countAdjacentComplements(List<List<int?>> board) {
    var count = 0;
    for (var row = 0; row < rowCount; row++) {
      for (var column = 0; column < columnCount; column++) {
        final value = board[row][column];
        if (value == null) continue;
        final right = column + 1 < columnCount ? board[row][column + 1] : null;
        if (right != null && value + right == targetSum) {
          count++;
        }
        final below = row + 1 < rowCount ? board[row + 1][column] : null;
        if (below != null && value + below == targetSum) {
          count++;
        }
      }
    }
    return count;
  }

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
