import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/number_rush/domain/number_rush_rules.dart';

void main() {
  test('1부터 25까지 중복 없이 섞는다', () {
    final tiles = NumberRushRules.shuffledTiles(Random(7));

    expect(tiles, hasLength(25));
    expect(
      tiles.toSet(),
      Set<int>.from(List.generate(25, (index) => index + 1)),
    );
  });

  test('예상한 다음 숫자만 정답이다', () {
    expect(NumberRushRules.isCorrectTap(expected: 7, tapped: 7), isTrue);
    expect(NumberRushRules.isCorrectTap(expected: 7, tapped: 8), isFalse);
  });

  test('빠른 기록일수록 랭킹 점수가 높고 시간을 복원할 수 있다', () {
    final fast = NumberRushRules.rankingScoreFromElapsedMs(9870);
    final slow = NumberRushRules.rankingScoreFromElapsedMs(18240);

    expect(fast, greaterThan(slow));
    expect(NumberRushRules.elapsedMsFromRankingScore(fast), 9870);
    expect(NumberRushRules.formatRankingScore(fast), '9.87초');
  });

  test('시간을 소수점 둘째 자리로 반올림해 표시한다', () {
    expect(NumberRushRules.formatElapsedMs(12344), '12.34초');
    expect(NumberRushRules.formatElapsedMs(12345), '12.35초');
  });
}
