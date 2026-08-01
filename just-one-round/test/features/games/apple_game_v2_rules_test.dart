import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/apple_game_v2/apple_game_v2.dart';
import 'package:just_one_round/features/games/apple_game_v2/domain/apple_game_v2_rules.dart';

void main() {
  test('게임 보드는 8열 13행이며 최대 104개 사과를 센다', () {
    expect(AppleGameV2Rules.columnCount, 8);
    expect(AppleGameV2Rules.rowCount, 13);
    expect(AppleGameV2Rules.maximumScore, 104);
    expect(AppleGameV2Rules.gameDuration, const Duration(seconds: 140));
  });

  test('드래그 방향과 관계없이 직사각형 합계를 계산한다', () {
    final board = _emptyBoard();
    board[2][3] = 1;
    board[2][4] = 2;
    board[3][3] = 3;
    board[3][4] = 4;

    final sum = AppleGameV2Rules.selectionSum(
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

    expect(AppleGameV2Rules.removeSelection(board, selection), 2);
    expect(board[0][0], isNull);
    expect(board[0][1], isNull);
    expect(AppleGameV2Rules.removeSelection(board, selection), 0);
  });

  test('합이 10이 아니면 보드를 바꾸지 않는다', () {
    final board = _emptyBoard();
    board[0][0] = 4;
    board[0][1] = 5;

    final removed = AppleGameV2Rules.removeSelection(
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
      AppleGameV2Rules.orderedSelectedCells(
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

  test('생성된 보드는 합이 10의 배수이며 충분한 시작 조합을 가진다', () {
    for (var seed = 0; seed < 100; seed++) {
      final board = AppleGameV2Rules.createBoard(Random(seed));

      expect(board, hasLength(AppleGameV2Rules.rowCount));
      expect(
        board.every((row) => row.length == AppleGameV2Rules.columnCount),
        isTrue,
      );
      expect(board.expand((row) => row), everyElement(inInclusiveRange(1, 9)));
      expect(
        board.expand((row) => row).fold<int>(0, (sum, value) => sum + value!) %
            AppleGameV2Rules.targetSum,
        0,
      );
      expect(
        AppleGameV2Rules.countAvailableMoves(board, stopAfter: 12),
        greaterThanOrEqualTo(12),
      );
    }
  });

  test('낮은 숫자를 완만하게 더 자주 생성한다', () {
    expect(AppleGameV2Rules.appleValueWeights, [
      19,
      16,
      14,
      12,
      10,
      9,
      8,
      7,
      5,
    ]);
    expect(
      AppleGameV2Rules.appleValueWeights.reduce((sum, value) => sum + value),
      100,
    );

    final random = _CyclingHundredRandom();
    final counts = List<int>.filled(9, 0);
    for (var draw = 0; draw < 100; draw++) {
      counts[AppleGameV2Rules.randomAppleValue(random) - 1]++;
    }

    expect(counts, AppleGameV2Rules.appleValueWeights);
  });

  test('랜덤 후보가 조건을 충족하지 못해도 보정된 대체 보드를 만든다', () {
    final board = AppleGameV2Rules.createBoard(_AlwaysNineRandom());
    final values = board.expand((row) => row);

    expect(values, everyElement(inInclusiveRange(1, 9)));
    expect(
      values.fold<int>(0, (sum, value) => sum + value!) %
          AppleGameV2Rules.targetSum,
      0,
    );
    expect(
      AppleGameV2Rules.countAvailableMoves(board, stopAfter: 12),
      greaterThanOrEqualTo(12),
    );
  });

  testWidgets('사과게임의 42픽셀 에셋으로 게임 화면을 구성한다', (tester) async {
    final game = AppleGameV2(
      gameDuration: const Duration(seconds: 60),
      countdownDuration: Duration.zero,
      assetSet: AppleGameV2AssetSet.midnightOrchard,
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

  test('사과게임의 일반 폰 뷰포트가 배경 오버스캔 안에서 반응한다', () {
    expect(
      AppleGameV2.viewportResolutionForCanvas(Vector2(360, 640)),
      closeToVector(Vector2(405, 720)),
    );
    expect(
      AppleGameV2.viewportResolutionForCanvas(Vector2(393, 852)),
      closeToVector(Vector2(360, 780.4580152671756)),
    );
    expect(
      AppleGameV2.viewportResolutionForCanvas(Vector2(1080, 2520)),
      closeToVector(Vector2(360, 840)),
    );
  });

  test('총 제거 개수와 무관하게 폭발 순번으로 콤보 단계와 크기를 고른다', () {
    expect(AppleGameV2.comboEffectTierForOrdinal(1), isNull);
    expect(AppleGameV2.comboEffectTierForOrdinal(2), 0);
    expect(AppleGameV2.comboEffectTierForOrdinal(3), 1);
    expect(AppleGameV2.comboEffectTierForOrdinal(4), 2);
    expect(AppleGameV2.comboEffectTierForOrdinal(12), 2);

    expect(AppleGameV2.comboEffectDisplaySizeForOrdinal(1), isNull);
    expect(AppleGameV2.comboEffectDisplaySizeForOrdinal(2), 64);
    expect(AppleGameV2.comboEffectDisplaySizeForOrdinal(3), 96);
    expect(AppleGameV2.comboEffectDisplaySizeForOrdinal(4), 128);
    expect(AppleGameV2.comboEffectDisplaySizeForOrdinal(12), 128);
  });
}

Matcher closeToVector(Vector2 expected) => predicate<Vector2>(
  (actual) =>
      (actual.x - expected.x).abs() < 0.001 &&
      (actual.y - expected.y).abs() < 0.001,
  'Vector2 close to $expected',
);

List<List<int?>> _emptyBoard() => List.generate(
  AppleGameV2Rules.rowCount,
  (_) => List<int?>.filled(AppleGameV2Rules.columnCount, null),
);

final class _AlwaysNineRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) => max - 1;
}

final class _CyclingHundredRandom implements Random {
  var _next = 0;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1 << 26) / (1 << 26);

  @override
  int nextInt(int max) {
    final value = _next % max;
    _next++;
    return value;
  }
}
