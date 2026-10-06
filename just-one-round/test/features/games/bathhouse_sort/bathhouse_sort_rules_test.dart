import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/bathhouse_sort/domain/bathhouse_sort_rules.dart';

void main() {
  test('동물 종이 가리키는 탕과 선택한 탕이 같을 때만 정답이다', () {
    expect(
      BathhouseSortRules.isCorrect(
        guestEntrance: BathEntrance.mens,
        tappedEntrance: BathEntrance.mens,
      ),
      isTrue,
    );
    expect(
      BathhouseSortRules.isCorrect(
        guestEntrance: BathEntrance.womens,
        tappedEntrance: BathEntrance.mens,
      ),
      isFalse,
    );
  });

  test('탭 전용 게임의 큐와 판정 잠금 시간을 고정한다', () {
    expect(BathhouseSortRules.rulesVersion, 11);
    expect(BathhouseSortRules.queueSize, 7);
    expect(BathhouseSortRules.maximumCombo, 50);
    expect(
      BathhouseSortRules.queueAdvanceDuration,
      const Duration(milliseconds: 70),
    );
    expect(
      BathhouseSortRules.wrongInputLock,
      const Duration(milliseconds: 250),
    );
    expect(BathhouseSortRules.inputBufferCapacity, 32);
    expect(
      BathhouseSortRules.inputCommitInterval,
      const Duration(milliseconds: 20),
    );
    expect(
      BathhouseSortRules.inputReservationLifetime,
      const Duration(milliseconds: 800),
    );
    expect(
      BathhouseSortRules.rosterRevealDuration,
      const Duration(milliseconds: 800),
    );
  });

  test('플레이 영역의 왼쪽과 오른쪽 탭을 해당 탕으로 판정한다', () {
    expect(BathhouseSortRules.entranceForTap(x: 0, y: 590), BathEntrance.mens);
    expect(
      BathhouseSortRules.entranceForTap(x: 179.9, y: 590),
      BathEntrance.mens,
    );
    expect(
      BathhouseSortRules.entranceForTap(x: 180, y: 590),
      BathEntrance.womens,
    );
    expect(
      BathhouseSortRules.entranceForTap(x: 360, y: 590),
      BathEntrance.womens,
    );
    expect(BathhouseSortRules.entranceForTap(x: 80, y: 100), isNull);
    expect(BathhouseSortRules.entranceForTap(x: 80, y: 542.9), isNull);
    expect(BathhouseSortRules.entranceForTap(x: 80, y: 543), BathEntrance.mens);
    expect(
      BathhouseSortRules.entranceForTap(x: 280, y: 617),
      BathEntrance.womens,
    );
    expect(BathhouseSortRules.entranceForTap(x: 280, y: 617.1), isNull);
  });

  test('콤보 구간마다 보너스가 올라간다', () {
    expect(BathhouseSortRules.pointsForCorrect(1), 100);
    expect(BathhouseSortRules.pointsForCorrect(2), 110);
    expect(BathhouseSortRules.pointsForCorrect(10), 190);
    expect(BathhouseSortRules.pointsForCorrect(25), 340);
    expect(BathhouseSortRules.pointsForCorrect(27), 360);
    expect(BathhouseSortRules.pointsForCorrect(50), 360);
    expect(BathhouseSortRules.comboAfterCorrect(49), 50);
    expect(BathhouseSortRules.comboAfterCorrect(50), 50);
    expect(BathhouseSortRules.comboTier(9), 0);
    expect(BathhouseSortRules.comboTier(10), 1);
    expect(BathhouseSortRules.comboTier(20), 2);
    expect(BathhouseSortRules.comboTier(27), 3);
    expect(BathhouseSortRules.successEffectScale(1), 1);
    expect(BathhouseSortRules.successEffectScale(27), 3.2);
    expect(BathhouseSortRules.successEffectScale(50), 3.2);
  });

  test('점수는 안전한 최댓값을 넘지 않고 천 단위로 표시한다', () {
    expect(
      BathhouseSortRules.addCorrectScore(
        score: BathhouseSortRules.maximumScore - 10,
        combo: 50,
      ),
      BathhouseSortRules.maximumScore,
    );
    expect(BathhouseSortRules.formatScore(12340), '12,340점');
    expect(BathhouseSortRules.formatHudScore(12340), '12,340');
  });

  test('난이도와 동물 추가 경계가 15초, 30초, 45초에 바뀐다', () {
    expect(
      BathhouseSortRules.difficultyForElapsed(
        const Duration(milliseconds: 14999),
      ),
      BathhouseDifficulty.learn,
    );
    expect(
      BathhouseSortRules.difficultyForElapsed(const Duration(seconds: 15)),
      BathhouseDifficulty.establish,
    );
    expect(
      BathhouseSortRules.difficultyForElapsed(const Duration(seconds: 30)),
      BathhouseDifficulty.combine,
    );
    expect(
      BathhouseSortRules.difficultyForElapsed(const Duration(seconds: 45)),
      BathhouseDifficulty.mastery,
    );
  });

  test('같은 시드는 같은 손님 순서를 만들고 같은 탕은 4번까지만 이어진다', () {
    final first = BathhouseGuestGenerator(Random(20260815));
    final second = BathhouseGuestGenerator(Random(20260815));
    final firstGuests = List.generate(
      500,
      (_) => first.next(activePairCount: 4),
    );
    final secondGuests = List.generate(
      500,
      (_) => second.next(activePairCount: 4),
    );

    expect(firstGuests, secondGuests);
    var run = 0;
    BathEntrance? previous;
    for (final guest in firstGuests) {
      run = guest.entrance == previous ? run + 1 : 1;
      expect(run, lessThanOrEqualTo(4));
      previous = guest.entrance;
    }
    expect(firstGuests.map((guest) => guest.species).toSet().length, 8);
  });

  test('동물 8종은 네 쌍으로 나뉘며 처음에는 흑곰과 흰토끼만 나온다', () {
    expect(BathhouseSortRules.speciesPairs, hasLength(4));
    expect(BathhouseSortRules.activeSpecies(1), [
      BathhouseSpecies.blackBear,
      BathhouseSpecies.whiteRabbit,
    ]);
    expect(BathhouseSpecies.grayBrownTanuki.entrance, BathEntrance.mens);
    expect(BathhouseSpecies.whiteCheeseCat.entrance, BathEntrance.womens);
  });
}
