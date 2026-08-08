import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/ramen_timer/domain/ramen_timer_rules.dart';

void main() {
  group('RamenTimerRules', () {
    test('10ms 단위로 반올림한다', () {
      expect(RamenTimerRules.quantizeMilliseconds(9824), 9820);
      expect(RamenTimerRules.quantizeMilliseconds(9825), 9830);
      expect(RamenTimerRules.quantizeMicroseconds(20004999), 20000);
      expect(RamenTimerRules.quantizeMicroseconds(20005000), 20010);
    });

    test('완벽한 세 탭은 최고 점수를 만든다', () {
      const taps = [10000, 20000, 30000];

      expect(RamenTimerRules.signedErrorsMilliseconds(taps), [0, 0, 0]);
      expect(RamenTimerRules.totalErrorMilliseconds(taps), 0);
      expect(
        RamenTimerRules.rankingScore(taps),
        RamenTimerRules.rankingCeilingMilliseconds,
      );
      expect(RamenTimerRules.verdict(taps), RamenTimerVerdict.perfect);
    });

    test('승인된 예시의 총 오차와 제출 점수를 재현한다', () {
      const taps = [9820, 20310, 29900];

      expect(RamenTimerRules.signedErrorsMilliseconds(taps), [-180, 310, -100]);
      expect(RamenTimerRules.totalErrorMilliseconds(taps), 590);
      expect(RamenTimerRules.rankingScore(taps), 3599410);
      expect(RamenTimerRules.errorMillisecondsFromRankingScore(3599410), 590);
      expect(RamenTimerRules.formatRankingScore(3599410), '총 오차 0.59초');
    });

    test('빠름과 느림은 같은 절대 오차를 만든다', () {
      expect(
        RamenTimerRules.totalErrorMilliseconds(const [9900, 19900, 29900]),
        300,
      );
      expect(
        RamenTimerRules.totalErrorMilliseconds(const [10100, 20100, 30100]),
        300,
      );
    });

    test('250ms 잠금과 45초 상한을 만족하는 순서만 허용한다', () {
      expect(
        RamenTimerRules.isValidTapSequence(
          RamenTimerRules.earliestTapMilliseconds,
        ),
        isTrue,
      );
      expect(
        RamenTimerRules.isValidTapSequence(
          RamenTimerRules.latestTapMilliseconds,
        ),
        isTrue,
      );
      expect(
        RamenTimerRules.isValidTapSequence(const [3199, 10000, 30000]),
        isFalse,
      );
      expect(
        RamenTimerRules.isValidTapSequence(const [10000, 10249, 30000]),
        isFalse,
      );
      expect(
        RamenTimerRules.isValidTapSequence(const [10000, 20000, 45001]),
        isFalse,
      );
    });

    test('정상 서버 점수 하한을 정확히 계산한다', () {
      expect(RamenTimerRules.maximumNormalErrorMilliseconds, 74250);
      expect(RamenTimerRules.minimumNormalRankingScore, 3525750);
      expect(
        RamenTimerRules.rankingScore(RamenTimerRules.latestTapMilliseconds),
        RamenTimerRules.minimumNormalRankingScore,
      );
      expect(
        RamenTimerRules.isNormalRankingScore(
          RamenTimerRules.minimumNormalRankingScore,
        ),
        isTrue,
      );
      expect(
        RamenTimerRules.isNormalRankingScore(
          RamenTimerRules.minimumNormalRankingScore - 10,
        ),
        isFalse,
      );
    });

    test('결과 포맷과 방향을 표시한다', () {
      expect(RamenTimerRules.formatRankingScore(0), '시간 초과');
      expect(RamenTimerRules.formatSignedError(-180), '0.18초 빠름');
      expect(RamenTimerRules.formatSignedError(310), '0.31초 느림');
      expect(RamenTimerRules.formatSignedError(0), '정확');
    });

    test('12~13초와 22~23초에만 시계가 부드럽게 희미해진다', () {
      expect(RamenTimerRules.clockPeekStrength(11999), 0);
      expect(RamenTimerRules.clockPeekStrength(12000), 0);
      expect(RamenTimerRules.clockPeekStrength(12250), closeTo(0.5, 0.001));
      expect(RamenTimerRules.clockPeekStrength(12500), 1);
      expect(RamenTimerRules.clockPeekStrength(12750), closeTo(0.5, 0.001));
      expect(RamenTimerRules.clockPeekStrength(13000), 0);
      expect(RamenTimerRules.clockPeekStrength(22500), 1);
      expect(RamenTimerRules.clockPeekStrength(23000), 0);
      expect(RamenTimerRules.clockPeekStrength(30000), 0);
    });

    test('완벽 범위를 벗어나면 최종 탭 방향으로 면 상태를 고른다', () {
      expect(
        RamenTimerRules.verdict(const [9900, 19900, 29900]),
        RamenTimerVerdict.tooEarly,
      );
      expect(
        RamenTimerRules.verdict(const [10100, 20100, 30200]),
        RamenTimerVerdict.tooLate,
      );
      expect(RamenTimerRules.largestErrorIndex(const [9820, 20310, 29900]), 1);
    });
  });
}
