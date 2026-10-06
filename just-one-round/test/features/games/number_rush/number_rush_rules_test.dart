import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/number_rush/domain/number_rush_rules.dart';

void main() {
  test('초기 보드는 1부터 25까지 중복 없이 섞는다', () {
    final tiles = NumberRushRules.shuffledTiles(Random(7));

    expect(tiles, hasLength(25));
    expect(
      tiles.toSet(),
      Set<int>.from(List.generate(25, (index) => index + 1)),
    );
  });

  test('활성 숫자가 15개 아래가 되면 50까지 예비 숫자를 공급한다', () {
    expect(
      NumberRushRules.shouldRefill(activeCount: 14, nextReserveNumber: 26),
      isTrue,
    );
    expect(
      NumberRushRules.shouldRefill(activeCount: 15, nextReserveNumber: 26),
      isFalse,
    );
    expect(
      NumberRushRules.shouldRefill(activeCount: 14, nextReserveNumber: 51),
      isFalse,
    );
  });

  test('새 숫자는 0.5초에서 2초 사이의 랜덤 지연 뒤 공급된다', () {
    final random = Random(19);
    final delays = List.generate(
      100,
      (_) => NumberRushRules.refillDelaySeconds(random),
    );

    expect(
      delays,
      everyElement(
        inInclusiveRange(
          NumberRushRules.minimumRefillDelaySeconds,
          NumberRushRules.maximumRefillDelaySeconds,
        ),
      ),
    );
    expect(delays.toSet().length, greaterThan(90));
  });

  test('1부터 50까지 진행하며 중간 구간에는 활성 숫자 15개를 유지한다', () {
    var activeCount = NumberRushRules.boardSlotCount;
    var nextReserveNumber = NumberRushRules.firstReserveNumber;

    for (var tappedNumber = 1; tappedNumber <= 50; tappedNumber++) {
      activeCount--;
      if (NumberRushRules.shouldRefill(
        activeCount: activeCount,
        nextReserveNumber: nextReserveNumber,
      )) {
        activeCount++;
        nextReserveNumber++;
      }

      if (tappedNumber >= 11 && tappedNumber <= 35) {
        expect(activeCount, NumberRushRules.activeNumberTarget);
      }
    }

    expect(nextReserveNumber, 51);
    expect(activeCount, 0);
  });

  test('예상한 다음 숫자만 정답이다', () {
    expect(NumberRushRules.isCorrectTap(expected: 7, tapped: 7), isTrue);
    expect(NumberRushRules.isCorrectTap(expected: 7, tapped: 8), isFalse);
  });

  test('1과 10단위 숫자는 처음부터 특수 버튼으로 표시한다', () {
    expect(NumberRushRules.isMilestoneNumber(1), isTrue);
    for (final number in const [10, 20, 30, 40, 50]) {
      expect(NumberRushRules.isMilestoneNumber(number), isTrue);
    }
    for (final number in const [2, 9, 11, 25, 49, 51]) {
      expect(NumberRushRules.isMilestoneNumber(number), isFalse);
    }
  });

  test('보스 폭발은 10부터 50까지 10단위 정답에만 발생한다', () {
    for (final number in const [10, 20, 30, 40, 50]) {
      expect(NumberRushRules.isBossMilestoneNumber(number), isTrue);
    }
    for (final number in const [1, 9, 11, 25, 49, 51]) {
      expect(NumberRushRules.isBossMilestoneNumber(number), isFalse);
    }
  });

  test('압박 단계는 10단위 숫자를 정답으로 누른 직후 올라간다', () {
    expect(NumberRushRules.pressureStageForClearedNumber(0), 0);
    expect(NumberRushRules.pressureStageForClearedNumber(9), 0);
    expect(NumberRushRules.pressureStageForClearedNumber(10), 1);
    expect(NumberRushRules.pressureStageForClearedNumber(19), 1);
    expect(NumberRushRules.pressureStageForClearedNumber(20), 2);
    expect(NumberRushRules.pressureStageForClearedNumber(30), 3);
    expect(NumberRushRules.pressureStageForClearedNumber(40), 4);
    expect(NumberRushRules.pressureStageForClearedNumber(49), 4);
    expect(NumberRushRules.pressureStageForClearedNumber(50), 5);
    expect(NumberRushRules.pressureStageForClearedNumber(51), 5);
  });

  test('힌트는 플레이 중 보이는 현재 목표를 3초간 못 누른 후만 켜진다', () {
    expect(
      NumberRushRules.shouldRevealHint(
        secondsSinceProgress: 2.99,
        targetVisible: true,
        isPlaying: true,
      ),
      isFalse,
    );
    expect(
      NumberRushRules.shouldRevealHint(
        secondsSinceProgress: 3,
        targetVisible: true,
        isPlaying: true,
      ),
      isTrue,
    );
    expect(
      NumberRushRules.shouldRevealHint(
        secondsSinceProgress: 4,
        targetVisible: false,
        isPlaying: true,
      ),
      isFalse,
    );
    expect(
      NumberRushRules.shouldRevealHint(
        secondsSinceProgress: 4,
        targetVisible: true,
        isPlaying: false,
      ),
      isFalse,
    );
  });

  test('빠른 기록일수록 랭킹 점수가 높고 시간을 복원할 수 있다', () {
    final fast = NumberRushRules.rankingScoreFromElapsedMs(9870);
    final slow = NumberRushRules.rankingScoreFromElapsedMs(18240);

    expect(fast, greaterThan(slow));
    expect(NumberRushRules.elapsedMsFromRankingScore(fast), 9870);
    expect(NumberRushRules.formatRankingScore(fast), '9.87초');
  });

  test('3분 안에 완료하지 못한 결과는 0점이다', () {
    expect(
      NumberRushRules.rankingScoreForResult(
        elapsedMs: const Duration(minutes: 3).inMilliseconds,
        timedOut: true,
      ),
      0,
    );
    expect(
      NumberRushRules.rankingScoreForResult(elapsedMs: 12345, timedOut: false),
      NumberRushRules.rankingScoreFromElapsedMs(12345),
    );
    expect(NumberRushRules.formatRankingScore(0), '0점');
  });

  test('시간을 소수점 둘째 자리로 반올림해 표시한다', () {
    expect(NumberRushRules.formatElapsedMs(12344), '12.34초');
    expect(NumberRushRules.formatElapsedMs(12345), '12.35초');
  });
}
