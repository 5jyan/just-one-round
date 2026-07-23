import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/apple_game/apple_game.dart';
import 'package:just_one_round/features/games/apple_game/domain/apple_game_rules.dart';

void main() {
  test('게임 보드는 8열 14행이며 최대 112개 사과를 센다', () {
    expect(AppleGameRules.columnCount, 8);
    expect(AppleGameRules.rowCount, 14);
    expect(AppleGameRules.maximumScore, 112);
  });

  test('드래그 방향과 관계없이 직사각형 합계를 계산한다', () {
    final board = _emptyBoard();
    board[2][3] = 1;
    board[2][4] = 2;
    board[3][3] = 3;
    board[3][4] = 4;

    final sum = AppleGameRules.selectionSum(
      board,
      const AppleCellRange(
        startRow: 3,
        startColumn: 4,
        endRow: 2,
        endColumn: 3,
      ),
    );

    expect(sum, 10);
  });

  test('합이 10인 선택만 제거하고 제거한 사과 수를 반환한다', () {
    final board = _emptyBoard();
    board[0][0] = 4;
    board[0][1] = 6;
    final selection = const AppleCellRange(
      startRow: 0,
      startColumn: 0,
      endRow: 0,
      endColumn: 1,
    );

    expect(AppleGameRules.removeSelection(board, selection), 2);
    expect(board[0][0], isNull);
    expect(board[0][1], isNull);
    expect(AppleGameRules.removeSelection(board, selection), 0);
  });

  test('합이 10이 아니면 보드를 바꾸지 않는다', () {
    final board = _emptyBoard();
    board[0][0] = 4;
    board[0][1] = 5;

    final removed = AppleGameRules.removeSelection(
      board,
      const AppleCellRange(
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      ),
    );

    expect(removed, 0);
    expect(board[0], containsAllInOrder([4, 5]));
  });

  test('생성된 보드는 올바른 크기와 충분한 시작 조합을 가진다', () {
    final board = AppleGameRules.createBoard(Random(7));

    expect(board, hasLength(AppleGameRules.rowCount));
    expect(
      board.every((row) => row.length == AppleGameRules.columnCount),
      isTrue,
    );
    expect(
      AppleGameRules.countAvailableMoves(board, stopAfter: 12),
      greaterThanOrEqualTo(12),
    );
  });

  testWidgets('런타임 에셋을 불러와 게임 화면을 구성한다', (tester) async {
    final game = AppleGame(
      gameDuration: const Duration(seconds: 60),
      countdownDuration: Duration.zero,
      random: Random(3),
      onFinished: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

List<List<int?>> _emptyBoard() => List.generate(
  AppleGameRules.rowCount,
  (_) => List<int?>.filled(AppleGameRules.columnCount, null),
);
