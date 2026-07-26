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

  test('선택한 사과를 드래그한 방향대로 정렬한다', () {
    final board = _emptyBoard();
    board[1][1] = 1;
    board[1][2] = 2;
    board[2][1] = 3;
    board[2][2] = 4;

    expect(
      AppleGameRules.orderedSelectedCells(
        board,
        const AppleCellRange(
          startRow: 2,
          startColumn: 2,
          endRow: 1,
          endColumn: 1,
        ),
      ),
      [(2, 2), (2, 1), (1, 2), (1, 1)],
    );
  });

  test('가장 많이 남은 숫자들의 모든 사과를 낙하 후보로 고른다', () {
    final board = _emptyBoard();
    board[0][0] = 2;
    board[0][1] = 2;
    board[1][0] = 7;
    board[1][1] = 7;
    board[2][0] = 4;

    expect(AppleGameRules.mostFrequentAppleCells(board), [
      (0, 0),
      (0, 1),
      (1, 0),
      (1, 1),
    ]);
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

  testWidgets('사과게임 2의 42픽셀 에셋으로 게임 화면을 구성한다', (tester) async {
    final game = AppleGame(
      gameDuration: const Duration(seconds: 60),
      countdownDuration: Duration.zero,
      assetSet: AppleGameAssetSet.midnightOrchard,
      random: Random(3),
      onFinished: (_) {},
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump(const Duration(milliseconds: 500));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    game.pauseEngine();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('사과게임 2의 일반 폰 뷰포트가 배경 오버스캔 안에서 반응한다', () {
    expect(
      AppleGame.viewportResolutionForCanvas(Vector2(360, 640)),
      closeToVector(Vector2(405, 720)),
    );
    expect(
      AppleGame.viewportResolutionForCanvas(Vector2(393, 852)),
      closeToVector(Vector2(360, 780.4580152671756)),
    );
    expect(
      AppleGame.viewportResolutionForCanvas(Vector2(1080, 2520)),
      closeToVector(Vector2(360, 840)),
    );
  });

  test('총 제거 개수와 무관하게 폭발 순번으로 콤보 단계와 크기를 고른다', () {
    expect(AppleGame.comboEffectTierForOrdinal(1), isNull);
    expect(AppleGame.comboEffectTierForOrdinal(2), 0);
    expect(AppleGame.comboEffectTierForOrdinal(3), 1);
    expect(AppleGame.comboEffectTierForOrdinal(4), 2);
    expect(AppleGame.comboEffectTierForOrdinal(12), 2);

    expect(AppleGame.comboEffectDisplaySizeForOrdinal(1), isNull);
    expect(AppleGame.comboEffectDisplaySizeForOrdinal(2), 64);
    expect(AppleGame.comboEffectDisplaySizeForOrdinal(3), 96);
    expect(AppleGame.comboEffectDisplaySizeForOrdinal(4), 128);
    expect(AppleGame.comboEffectDisplaySizeForOrdinal(12), 128);
  });

  test('남은 60초부터 10초 간격으로 자동 낙하한다', () {
    expect(AppleGame.timedDropRemainingSeconds, [60, 50, 40, 30, 20, 10]);
  });
}

Matcher closeToVector(Vector2 expected) => predicate<Vector2>(
  (actual) =>
      (actual.x - expected.x).abs() < 0.001 &&
      (actual.y - expected.y).abs() < 0.001,
  'Vector2 close to $expected',
);

List<List<int?>> _emptyBoard() => List.generate(
  AppleGameRules.rowCount,
  (_) => List<int?>.filled(AppleGameRules.columnCount, null),
);
