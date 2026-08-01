import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/sausage_dachshund/domain/sausage_dachshund_rules.dart';

void main() {
  group('SausageDachshundRules', () {
    test('초기 상태는 중앙에서 오른쪽을 보고 첫 소시지를 안전하게 둔다', () {
      final state = SausageDachshundState.initial();

      expect(state.body, SausageDachshundRules.initialBody);
      expect(state.direction, DachshundDirection.right);
      expect(state.sausage, const DachshundCell(7, 6));
      expect(state.score, 0);
    });

    test('스와이프는 우세 축과 임계값으로 한 방향만 고른다', () {
      expect(
        SausageDachshundRules.directionForSwipe(deltaX: 30, deltaY: 12),
        DachshundDirection.right,
      );
      expect(
        SausageDachshundRules.directionForSwipe(deltaX: -12, deltaY: -30),
        DachshundDirection.up,
      );
      expect(
        SausageDachshundRules.directionForSwipe(deltaX: 17.9, deltaY: 0),
        isNull,
      );
    });

    test('반대 방향과 같은 틱의 두 번째 입력을 거부한다', () {
      final state = SausageDachshundState.initial();

      expect(state.queueDirection(DachshundDirection.left), isFalse);
      expect(state.queueDirection(DachshundDirection.up), isTrue);
      expect(state.queueDirection(DachshundDirection.down), isFalse);

      state.step(Random(1));
      expect(state.direction, DachshundDirection.up);
      expect(state.queuedDirection, isNull);
    });

    test('첫 소시지를 먹으면 점수와 몸길이가 각각 하나 증가한다', () {
      final state = SausageDachshundState.initial();
      final random = Random(3);

      final first = state.step(random);
      final second = state.step(random);

      expect(first.ateSausage, isFalse);
      expect(second.ateSausage, isTrue);
      expect(state.score, 1);
      expect(state.body, hasLength(5));
      expect(state.sausage, isNotNull);
      expect(state.body, isNot(contains(state.sausage)));
    });

    test('성장하지 않는 틱에는 빠져나가는 꼬리 칸으로 이동할 수 있다', () {
      final state = SausageDachshundState.forTesting(
        body: const [
          DachshundCell(2, 2),
          DachshundCell(2, 1),
          DachshundCell(1, 1),
          DachshundCell(1, 2),
        ],
        direction: DachshundDirection.up,
        sausage: const DachshundCell(8, 8),
      );

      final result = state.step(Random(1));

      expect(result.finishReason, isNull);
      expect(state.head, const DachshundCell(1, 2));
      expect(state.body, hasLength(4));
    });

    test('성장하는 틱에는 빠지지 않는 꼬리 칸도 자기 충돌이다', () {
      final state = SausageDachshundState.forTesting(
        body: const [
          DachshundCell(2, 2),
          DachshundCell(2, 1),
          DachshundCell(1, 1),
          DachshundCell(1, 2),
        ],
        direction: DachshundDirection.up,
        sausage: const DachshundCell(1, 2),
      );

      final result = state.step(Random(1));

      expect(result.finishReason, DachshundFinishReason.self);
      expect(result.moved, isFalse);
    });

    test('벽과 자기 몸 충돌을 구분한다', () {
      final wall = SausageDachshundState.forTesting(
        body: const [
          DachshundCell(0, 2),
          DachshundCell(1, 2),
          DachshundCell(2, 2),
        ],
        direction: DachshundDirection.up,
        sausage: const DachshundCell(8, 8),
      );
      final self = SausageDachshundState.forTesting(
        body: const [
          DachshundCell(2, 2),
          DachshundCell(1, 2),
          DachshundCell(1, 1),
          DachshundCell(2, 1),
          DachshundCell(3, 1),
        ],
        direction: DachshundDirection.left,
        sausage: const DachshundCell(8, 8),
      );

      expect(wall.step(Random(1)).finishReason, DachshundFinishReason.wall);
      expect(self.step(Random(1)).finishReason, DachshundFinishReason.self);
    });

    test('동일 시드와 몸 상태는 동일한 도달 가능 소시지를 고른다', () {
      final first = SausageDachshundRules.chooseReachableSausage(
        body: SausageDachshundRules.initialBody,
        random: Random(4729),
      );
      final second = SausageDachshundRules.chooseReachableSausage(
        body: SausageDachshundRules.initialBody,
        random: Random(4729),
      );

      expect(first, second);
      expect(
        SausageDachshundRules.reachableEmptyCells(
          body: SausageDachshundRules.initialBody,
        ),
        contains(first),
      );
    });

    test('여러 시드의 소시지가 항상 현재 도달 가능 영역에 생성된다', () {
      final reachable = SausageDachshundRules.reachableEmptyCells(
        body: SausageDachshundRules.initialBody,
      );
      for (var seed = 0; seed < 100; seed++) {
        final sausage = SausageDachshundRules.chooseReachableSausage(
          body: SausageDachshundRules.initialBody,
          random: Random(seed),
        );
        expect(reachable, contains(sausage), reason: 'seed=$seed');
      }
    });

    test('몸으로 봉쇄된 주머니에는 소시지를 만들지 않는다', () {
      const body = [
        DachshundCell(0, 0),
        DachshundCell(0, 1),
        DachshundCell(0, 2),
        DachshundCell(1, 2),
        DachshundCell(2, 2),
        DachshundCell(2, 1),
        DachshundCell(2, 0),
        DachshundCell(1, 0),
      ];

      final reachable = SausageDachshundRules.reachableEmptyCells(body: body);

      expect(reachable, isNot(contains(const DachshundCell(1, 1))));
    });

    test('시간 마일스톤과 최저 이동 간격을 정확히 적용한다', () {
      expect(SausageDachshundRules.moveIntervalAt(0), 0.60);
      expect(SausageDachshundRules.moveIntervalAt(3), 0.50);
      expect(SausageDachshundRules.moveIntervalAt(30), 0.42);
      expect(SausageDachshundRules.moveIntervalAt(50), 0.35);
      expect(SausageDachshundRules.moveIntervalAt(90), 0.29);
      expect(SausageDachshundRules.moveIntervalAt(120), 0.25);
      expect(SausageDachshundRules.moveIntervalAt(999), 0.25);
    });

    test('점수 표시는 자연수 소시지 개수다', () {
      expect(SausageDachshundRules.maximumScore, 131);
      expect(SausageDachshundRules.formatScore(12), '12개');
      expect(SausageDachshundRules.formatHudScore(12), '12');
    });

    test('날짜 시드는 한국시간 오전 6시 일일 리셋을 따른다', () {
      final beforeReset = DateTime.utc(2026, 7, 28, 20, 59);
      final atReset = DateTime.utc(2026, 7, 28, 21);
      final samePlayDate = DateTime.utc(2026, 7, 29, 20, 59);
      final nextReset = DateTime.utc(2026, 7, 29, 21);

      expect(
        SausageDachshundRules.dailySeed(atReset),
        SausageDachshundRules.dailySeed(samePlayDate),
      );
      expect(
        SausageDachshundRules.dailySeed(beforeReset),
        isNot(SausageDachshundRules.dailySeed(atReset)),
      );
      expect(
        SausageDachshundRules.dailySeed(samePlayDate),
        isNot(SausageDachshundRules.dailySeed(nextReset)),
      );
    });

    test('마지막 빈칸의 소시지를 먹으면 보드 완료와 최대 점수가 된다', () {
      const food = DachshundCell(0, 1);
      final body = <DachshundCell>[
        const DachshundCell(0, 0),
        for (var row = 0; row < SausageDachshundRules.rowCount; row++)
          for (
            var column = 0;
            column < SausageDachshundRules.columnCount;
            column++
          )
            if (!(row == 0 && (column == 0 || column == 1)))
              DachshundCell(row, column),
      ];
      final state = SausageDachshundState.forTesting(
        body: body,
        direction: DachshundDirection.right,
        sausage: food,
        score: 130,
      );

      final result = state.step(Random(1));

      expect(result.ateSausage, isTrue);
      expect(result.finishReason, DachshundFinishReason.boardComplete);
      expect(state.score, SausageDachshundRules.maximumScore);
      expect(state.body, hasLength(SausageDachshundRules.boardCellCount));
    });
  });
}
