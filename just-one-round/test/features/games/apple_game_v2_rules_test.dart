import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/apple_game_v2/apple_game_v2.dart';
import 'package:just_one_round/features/games/apple_game_v2/domain/apple_game_v2_rules.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';

void main() {
  test('게임 보드는 8열 13행이며 최대 104개 사과를 센다', () {
    expect(AppleGameV2Rules.columnCount, 8);
    expect(AppleGameV2Rules.rowCount, 13);
    expect(AppleGameV2Rules.maximumScore, 104);
    expect(AppleGameV2Rules.gameDuration, const Duration(seconds: 140));
    expect(AppleGameV2Rules.rulesVersion, 2);
    expect(AppleGameV2Rules.maxBiasSwaps, 1);
    expect(AppleGameV2Rules.maxBiasSearchAttempts, 8);
    expect(AppleGameV2Rules.supportedRulesVersions, containsAll(<int>[1, 2]));
  });

  test('v1 보드는 기존 시드와 난수 소비를 그대로 유지한다', () {
    const goldenBoards = <int, String>{
      0: '41591887354166486138392514137742518817811298349498416258658414428226395119318743376527134445375239788896',
      1: '17946335172527493649873192621135821483328216783317256215167514219721541725919211111662628634835443363793',
      2: '61118257235475522161667721267229993519145566126426354324974424331525211545784712382221534531884113323114',
      3: '61531281156619171744334327115653624671855853154241842968644248351396162266617384648411425554692311513476',
      42: '74176137212422211383551338153531124126397121115131926521111915451824185965222188852447717126973665894266',
      12345:
          '29213813433842293432312842766892232294111197639232332742188116414212455375659643182593751117711535622753',
    };

    for (final entry in goldenBoards.entries) {
      final board = AppleGameV2Rules.createBoard(
        Random(entry.key),
        rulesVersion: AppleGameV2Rules.legacyRulesVersion,
      );
      expect(
        board.expand((row) => row).map((value) => value!).join(),
        entry.value,
        reason: 'seed ${entry.key}',
      );
    }

    final random = _RecordingRandom(Random(123));
    AppleGameV2Rules.createBoard(
      random,
      rulesVersion: AppleGameV2Rules.legacyRulesVersion,
    );
    expect(random.nextInt(100), 88);
  });

  test('v2 인접 보정은 보드 불변식과 단일 스왑 범위를 지킨다', () {
    var totalPairGain = 0;
    var changedBoards = 0;
    const complementFamilies = <(int, int)>[
      (1, 9),
      (2, 8),
      (3, 7),
      (4, 6),
      (5, 5),
    ];
    final legacyFamilyCounts = List<int>.filled(complementFamilies.length, 0);
    final biasedFamilyCounts = List<int>.filled(complementFamilies.length, 0);

    for (var seed = 0; seed < 1000; seed++) {
      final legacy = AppleGameV2Rules.createBoard(
        Random(seed),
        rulesVersion: AppleGameV2Rules.legacyRulesVersion,
      );
      final biased = AppleGameV2Rules.createBoard(Random(seed));
      final legacyValues = legacy.expand((row) => row).toList();
      final biasedValues = biased.expand((row) => row).toList();

      expect(biasedValues, hasLength(AppleGameV2Rules.maximumScore));
      expect(biasedValues, everyElement(inInclusiveRange(1, 9)));
      expect(
        biasedValues.fold<int>(0, (sum, value) => sum + value!) %
            AppleGameV2Rules.targetSum,
        0,
      );
      expect(_histogram(biasedValues), _histogram(legacyValues));

      final changed = [
        for (var index = 0; index < biasedValues.length; index++)
          if (biasedValues[index] != legacyValues[index]) index,
      ];
      expect(changed.length, lessThanOrEqualTo(2));
      if (changed.isNotEmpty) changedBoards++;

      final pairGain =
          AppleGameV2Rules.countAdjacentComplements(biased) -
          AppleGameV2Rules.countAdjacentComplements(legacy);
      expect(pairGain, inInclusiveRange(0, 2));
      totalPairGain += pairGain;
      for (var family = 0; family < complementFamilies.length; family++) {
        final (lower, upper) = complementFamilies[family];
        legacyFamilyCounts[family] += _countAdjacentPairFamily(
          legacy,
          lower,
          upper,
        );
        biasedFamilyCounts[family] += _countAdjacentPairFamily(
          biased,
          lower,
          upper,
        );
      }
      expect(
        AppleGameV2Rules.countAvailableMoves(
          biased,
          stopAfter: AppleGameV2Rules.minimumAvailableMoves,
        ),
        greaterThanOrEqualTo(AppleGameV2Rules.minimumAvailableMoves),
      );

      final repeated = AppleGameV2Rules.createBoard(Random(seed));
      expect(repeated, biased, reason: 'seed $seed must be deterministic');
    }

    expect(changedBoards, greaterThan(0));
    expect(totalPairGain, greaterThan(500));
    expect(totalPairGain, lessThan(2000));
    for (var family = 0; family < complementFamilies.length; family++) {
      expect(
        biasedFamilyCounts[family],
        greaterThan(legacyFamilyCounts[family]),
        reason: 'family ${complementFamilies[family]} should increase',
      );
    }
  });

  test('인접 보정은 직교 합 10만 세고 지원하지 않는 버전은 거부한다', () {
    final board = _emptyBoard();
    board[0][0] = 1;
    board[0][1] = 9;
    board[1][0] = 2;
    board[1][1] = 8;
    board[2][2] = 5;
    board[3][3] = 5;

    expect(AppleGameV2Rules.countAdjacentComplements(board), 2);
    expect(
      () => AppleGameV2Rules.createBoard(Random(1), rulesVersion: 3),
      throwsUnsupportedError,
    );
    expect(
      () => AppleGameV2(rulesVersion: 3, onFinished: (_) {}),
      throwsUnsupportedError,
    );
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

  test('모든 사과가 제거된 보드만 클리어로 판정한다', () {
    final board = _emptyBoard();

    expect(AppleGameV2Rules.isBoardCleared(board), isTrue);

    board[12][7] = 1;
    expect(AppleGameV2Rules.isBoardCleared(board), isFalse);
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
    final random = _AlwaysNineRandom();
    final board = AppleGameV2Rules.createBoard(
      random,
      rulesVersion: AppleGameV2Rules.legacyRulesVersion,
    );
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
    expect(random.calls, 10300);
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

  testWidgets('마지막 사과 제거 연출이 끝나면 클리어로 한 번만 종료한다', (tester) async {
    final results = <GameResult>[];
    final game = AppleGameV2(
      gameDuration: const Duration(seconds: 60),
      countdownDuration: Duration.zero,
      assetSet: AppleGameV2AssetSet.midnightOrchard,
      random: Random(3),
      onFinished: results.add,
    );

    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    for (var frame = 0; frame < 30 && !game.isLoaded; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(game.isLoaded, isTrue);

    final board = _emptyBoard();
    board[0][0] = 4;
    board[0][1] = 6;
    game.setBoardForTesting(board, score: 102);
    game.commitSelectionForTesting(
      const AppleCellRange(
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      ),
    );

    expect(results, isEmpty);
    expect(game.hud.value.score, 104);
    expect(game.hud.value.phase, MiniGamePhase.playing);

    game.update(0.2);

    expect(results, hasLength(1));
    expect(results.single.score, 104);
    expect(results.single.endType, GameEndType.clear);
    expect(game.hud.value.phase, MiniGamePhase.finished);

    game.update(60);
    game.interrupt();
    expect(results, hasLength(1));

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

List<int> _histogram(List<int?> values) {
  final histogram = List<int>.filled(10, 0);
  for (final value in values) {
    histogram[value ?? 0]++;
  }
  return histogram;
}

int _countAdjacentPairFamily(List<List<int?>> board, int lower, int upper) {
  var count = 0;
  for (var row = 0; row < AppleGameV2Rules.rowCount; row++) {
    for (var column = 0; column < AppleGameV2Rules.columnCount; column++) {
      final value = board[row][column];
      if (value == null) continue;
      if (column + 1 < AppleGameV2Rules.columnCount &&
          _isPair(value, board[row][column + 1], lower, upper)) {
        count++;
      }
      if (row + 1 < AppleGameV2Rules.rowCount &&
          _isPair(value, board[row + 1][column], lower, upper)) {
        count++;
      }
    }
  }
  return count;
}

bool _isPair(int? first, int? second, int lower, int upper) =>
    (first == lower && second == upper) || (first == upper && second == lower);

final class _AlwaysNineRandom implements Random {
  var calls = 0;

  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) {
    calls++;
    return max - 1;
  }
}

final class _RecordingRandom implements Random {
  _RecordingRandom(this._delegate);

  final Random _delegate;

  @override
  bool nextBool() => _delegate.nextBool();

  @override
  double nextDouble() => _delegate.nextDouble();

  @override
  int nextInt(int max) => _delegate.nextInt(max);
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
