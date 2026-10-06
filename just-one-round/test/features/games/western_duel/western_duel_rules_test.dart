import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/western_duel/domain/western_duel_rules.dart';

void main() {
  test(
    'reaction score ranks only own milliseconds, independent of outcome',
    () {
      expect(WesternDuelRules.scoreForReaction(123), 999877);
      expect(WesternDuelRules.formatRankingScore(999877), '0.123초');
      expect(WesternDuelRules.responseDeadlineMs, 1000);
      expect(WesternDuelRules.scoreForReaction(1000), 999000);
      expect(WesternDuelRules.isValidReaction(1000), isTrue);
      expect(WesternDuelRules.isValidReaction(1500), isTrue);
      expect(WesternDuelRules.formatRankingScore(998500), '1.500초');
      expect(
        WesternDuelRules.scoreForReaction(100),
        greaterThan(WesternDuelRules.scoreForReaction(200)),
      );
      expect(WesternDuelRules.compare(123, 300), WesternDuelOutcome.win);
      expect(WesternDuelRules.compare(300, 123), WesternDuelOutcome.lose);
      expect(WesternDuelRules.compare(123, 123), WesternDuelOutcome.draw);
      expect(() => WesternDuelRules.scoreForReaction(0), throwsRangeError);
      expect(() => WesternDuelRules.scoreForReaction(1501), throwsRangeError);
    },
  );

  test('standoff and bot timings stay in fair contract bounds', () {
    final random = Random(42);
    for (var i = 0; i < 1000; i++) {
      expect(
        WesternDuelRules.standoffMilliseconds(random),
        inInclusiveRange(3000, 8000),
      );
      expect(
        WesternDuelRules.botReactionMilliseconds(random),
        inInclusiveRange(350, 550),
      );
    }
  });
}
