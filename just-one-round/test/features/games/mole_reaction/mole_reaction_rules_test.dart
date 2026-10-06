import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/mole_reaction/domain/mole_reaction_rules.dart';

void main() {
  test('시드가 같으면 준비 1회와 골든 실전 1회가 재현된다', () {
    final first = MoleReactionRules.challengeForSeed(20260910);
    final second = MoleReactionRules.challengeForSeed(20260910);

    expect(first.events, second.events);
    expect(first.events, hasLength(MoleReactionRules.eventCount));
    expect(first.goldenEventIndex, MoleReactionRules.eventCount - 1);
    expect(first.events.where((event) => event.isGolden), hasLength(1));
    expect(first.events.first.isPreparation, isTrue);
    expect(first.events.last.isScored, isTrue);
    expect(
      first.events.where((event) => !event.isGolden),
      hasLength(MoleReactionRules.normalEventCount),
    );
  });

  test('대기시간은 3~8초 범위이고 준비·실전 구멍은 분리된다', () {
    for (final seed in List.generate(10, (index) => index + 1)) {
      final challenge = MoleReactionRules.challengeForSeed(seed);
      final waits = challenge.events.map((event) => event.waitSeconds).toList();
      final holeCounts = <int, int>{};
      for (final event in challenge.events) {
        holeCounts.update(
          event.holeIndex,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }

      expect(waits, everyElement(inInclusiveRange(3, 8)));
      expect(waits, hasLength(MoleReactionRules.eventCount));
      expect(waits.toSet(), hasLength(MoleReactionRules.eventCount));
      expect(
        holeCounts.values,
        everyElement(lessThanOrEqualTo(MoleReactionRules.maxHoleUsesPerRun)),
      );
    }
  });

  test('2x2 보드와 준비 1회·실전 1회 범위가 고정된다', () {
    expect(MoleReactionRules.rulesVersion, 2);
    expect(MoleReactionRules.columnCount, 2);
    expect(MoleReactionRules.rowCount, 2);
    expect(MoleReactionRules.holeCount, 4);
    expect(MoleReactionRules.preparationEventCount, 1);
    expect(MoleReactionRules.normalEventCount, 1);
    expect(MoleReactionRules.goldenEventCount, 1);
    expect(MoleReactionRules.eventCount, 2);
    expect(MoleReactionRules.minimumValidTotalMilliseconds, 2);
    expect(MoleReactionRules.rankingScoreForTotal(2), 999_998);
    expect(MoleReactionRules.isValidHoleIndex(0), isTrue);
    expect(MoleReactionRules.isValidHoleIndex(3), isTrue);
    expect(MoleReactionRules.isValidHoleIndex(-1), isFalse);
    expect(MoleReactionRules.isValidHoleIndex(4), isFalse);
  });

  test('일반 반응은 그대로, 황금 반응은 2배로 합산된다', () {
    expect(
      MoleReactionRules.weightedReactionMilliseconds(
        reactionMilliseconds: 247,
        golden: false,
      ),
      247,
    );
    expect(
      MoleReactionRules.weightedReactionMilliseconds(
        reactionMilliseconds: 247,
        golden: true,
      ),
      494,
    );
    expect(
      MoleReactionRules.weightedReactionMilliseconds(
        reactionMilliseconds: 0,
        golden: true,
      ),
      2,
    );
  });

  test('반응속도 이펙트는 150·300·450·600ms 경계로 나뉜다', () {
    expect(
      MoleReactionRules.speedTierForMilliseconds(150),
      MoleReactionSpeedTier.perfect,
    );
    expect(
      MoleReactionRules.speedTierForMilliseconds(151),
      MoleReactionSpeedTier.lightning,
    );
    expect(
      MoleReactionRules.speedTierForMilliseconds(300),
      MoleReactionSpeedTier.lightning,
    );
    expect(
      MoleReactionRules.speedTierForMilliseconds(301),
      MoleReactionSpeedTier.great,
    );
    expect(
      MoleReactionRules.speedTierForMilliseconds(450),
      MoleReactionSpeedTier.great,
    );
    expect(
      MoleReactionRules.speedTierForMilliseconds(451),
      MoleReactionSpeedTier.steady,
    );
    expect(
      MoleReactionRules.speedTierForMilliseconds(600),
      MoleReactionSpeedTier.steady,
    );
    expect(
      MoleReactionRules.speedTierForMilliseconds(601),
      MoleReactionSpeedTier.late,
    );
  });

  test('반응·오답·놓침 벌점이 계약대로 합산된다', () {
    final total = MoleReactionRules.totalMilliseconds(
      weightedReactionTotalMilliseconds: 1_250,
      invalidTapCount: 2,
      normalMissCount: 1,
      goldenMissCount: 1,
    );
    expect(total, 1_250 + 2_000 + 2_000 + 4_000);
    expect(MoleReactionRules.missPenalty(golden: false), 2_000);
    expect(MoleReactionRules.missPenalty(golden: true), 4_000);
  });

  test('낮은 총 시간이 높은 랭킹 점수로 변환되고 왕복된다', () {
    final fast = MoleReactionRules.rankingScoreForTotal(2_345);
    final slow = MoleReactionRules.rankingScoreForTotal(8_765);

    expect(fast, greaterThan(slow));
    expect(MoleReactionRules.totalFromRankingScore(fast), 2_345);
    expect(MoleReactionRules.formatTotalMs(2_345), '2,345ms');
    expect(MoleReactionRules.formatRankingScore(fast), '2,345ms');
  });

  test('랭킹 범위를 벗어난 총 시간은 억지로 clamp하지 않는다', () {
    expect(
      () => MoleReactionRules.rankingScoreForTotal(
        MoleReactionRules.minimumValidTotalMilliseconds - 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => MoleReactionRules.rankingScoreForTotal(
        MoleReactionRules.rankingCeiling,
      ),
      throwsArgumentError,
    );
    expect(MoleReactionRules.formatRankingScore(0), '시간 초과');
  });

  test('모든 시드에서 황금 슬롯은 두 번째이자 마지막 이벤트다', () {
    final random = Random(91);
    for (var count = 0; count < 30; count++) {
      final challenge = MoleReactionRules.challengeForSeed(
        random.nextInt(1 << 30),
      );
      expect(challenge.goldenEventIndex, MoleReactionRules.eventCount - 1);
      expect(
        challenge.events
            .take(MoleReactionRules.normalEventCount)
            .any((event) => event.isGolden),
        isFalse,
      );
    }
  });
}
