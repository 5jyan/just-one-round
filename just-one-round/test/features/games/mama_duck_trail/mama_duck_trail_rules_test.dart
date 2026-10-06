import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/mama_duck_trail/domain/mama_duck_trail_rules.dart';

void main() {
  group('MamaDuckTrailRules', () {
    test('제한시간은 120초다', () {
      expect(MamaDuckTrailRules.gameDuration, const Duration(seconds: 120));
    });

    test('성공 이동 뒤 기쁨 연출이 1.5초 유지된다', () {
      expect(MamaDuckTrailRules.successTravelDurationSeconds, 0.58);
      expect(MamaDuckTrailRules.successCheerDurationSeconds, 1.5);
      expect(MamaDuckTrailRules.successDurationSeconds, 2.08);
    });

    test('성공 선두는 엄마 직전 칸에서 멈추고 후속 오리는 한 칸씩 뒤따른다', () {
      expect(MamaDuckTrailRules.successLeaderFinalDistance(4), 2);
      expect(MamaDuckTrailRules.successLeaderFinalDistance(8), 6);
      expect(
        MamaDuckTrailRules.travelingDuckDistance(
          leaderDistance: 6,
          followerIndex: 0,
        ),
        6,
      );
      expect(
        MamaDuckTrailRules.travelingDuckDistance(
          leaderDistance: 6,
          followerIndex: 3,
        ),
        3,
      );
    });

    test('동일 시드는 동일한 합법 경로를 만든다', () {
      final first = MamaDuckTrailRules.generatePath(Random(4729), 9);
      final second = MamaDuckTrailRules.generatePath(Random(4729), 9);

      expect(first, second);
      expect(MamaDuckTrailRules.isValidPath(first, expectedLength: 9), isTrue);
    });

    test('여러 시드와 7~35칸 길이에서 경로가 완주 가능하다', () {
      for (var seed = 0; seed < 12; seed++) {
        for (
          var length = MamaDuckTrailRules.initialPathLength;
          length <= MamaDuckTrailRules.maximumGeneratedPathLength;
          length++
        ) {
          final path = MamaDuckTrailRules.generatePath(Random(seed), length);
          expect(
            MamaDuckTrailRules.isValidPath(path, expectedLength: length),
            isTrue,
            reason: 'seed=$seed length=$length path=$path',
          );
          expect(
            MamaDuckTrailRules.maximumStraightRun(path),
            lessThanOrEqualTo(MamaDuckTrailRules.maximumStraightSteps),
            reason: 'seed=$seed length=$length path=$path',
          );
        }
      }
    });

    test('무작위 경로는 맨 아래에서 시작하고 상하좌우 이동을 모두 사용한다', () {
      final starts = <MamaDuckCell>{};
      final directions = <(int, int)>{};
      for (var seed = 0; seed < 200; seed++) {
        final path = MamaDuckTrailRules.generatePath(Random(seed), 12);
        starts.add(path.first);
        for (var index = 1; index < path.length; index++) {
          directions.add((
            path[index].row - path[index - 1].row,
            path[index].column - path[index - 1].column,
          ));
        }
      }

      expect(starts.map((cell) => cell.row).toSet(), {6});
      expect(starts.map((cell) => cell.column).toSet(), {0, 1, 2, 3, 4});
      expect(directions, containsAll(const [(-1, 0), (0, 1), (1, 0), (0, -1)]));
    });

    test('첫 경로는 7칸이고 성공할 때마다 1칸씩 늘어나 35칸에서 멈춘다', () {
      expect(MamaDuckTrailRules.pathLengthAfterSuccesses(0), 7);
      expect(MamaDuckTrailRules.pathLengthAfterSuccesses(1), 8);
      expect(MamaDuckTrailRules.pathLengthAfterSuccesses(5), 12);
      expect(MamaDuckTrailRules.pathLengthAfterSuccesses(28), 35);
      expect(MamaDuckTrailRules.pathLengthAfterSuccesses(100), 35);
      expect(MamaDuckTrailRules.pathLengthAfterSuccesses(-1), 7);
    });

    test('콤보 3, 5, 7에서 피버 단계가 상승하고 실패 콤보는 해제된다', () {
      expect(MamaDuckTrailRules.feverTierForCombo(0), MamaDuckFeverTier.none);
      expect(MamaDuckTrailRules.feverTierForCombo(2), MamaDuckFeverTier.none);
      expect(
        MamaDuckTrailRules.feverTierForCombo(3),
        MamaDuckFeverTier.goldenTrail,
      );
      expect(
        MamaDuckTrailRules.feverTierForCombo(5),
        MamaDuckFeverTier.sparkling,
      );
      expect(
        MamaDuckTrailRules.feverTierForCombo(7),
        MamaDuckFeverTier.radiant,
      );
      expect(
        MamaDuckTrailRules.feverTierForCombo(100),
        MamaDuckFeverTier.radiant,
      );
    });

    test('구조 오리는 최대 5마리까지 보이고 나머지는 숫자로 집계한다', () {
      expect(MamaDuckTrailRules.visibleRescuedDuckCount(-1), 0);
      expect(MamaDuckTrailRules.visibleRescuedDuckCount(3), 3);
      expect(MamaDuckTrailRules.visibleRescuedDuckCount(5), 5);
      expect(MamaDuckTrailRules.visibleRescuedDuckCount(8), 5);
      expect(MamaDuckTrailRules.hiddenRescuedDuckCount(5), 0);
      expect(MamaDuckTrailRules.hiddenRescuedDuckCount(8), 3);
    });

    test('대각선, 재방문, 보드 밖 경로를 거부한다', () {
      expect(
        MamaDuckTrailRules.isValidPath(const [
          MamaDuckCell(6, 0),
          MamaDuckCell(5, 1),
        ]),
        isFalse,
      );
      expect(
        MamaDuckTrailRules.isValidPath(const [
          MamaDuckCell(6, 0),
          MamaDuckCell(5, 0),
          MamaDuckCell(6, 0),
        ]),
        isFalse,
      );
      expect(
        MamaDuckTrailRules.isValidPath(const [
          MamaDuckCell(6, 0),
          MamaDuckCell(7, 0),
        ]),
        isFalse,
      );
    });

    test('시간에 따른 발자국 유지 시간은 기존 상한을 유지한다', () {
      expect(MamaDuckTrailRules.holdSecondsAt(0), 2);
      expect(MamaDuckTrailRules.holdSecondsAt(49.99), 2);
      expect(MamaDuckTrailRules.holdSecondsAt(50), 1.5);
      expect(MamaDuckTrailRules.holdSecondsAt(70), 1.1);
      expect(MamaDuckTrailRules.holdSecondsAt(200), 1.1);
    });

    test('경로 길이와 성공 후 콤보로 점수를 계산하고 상한을 둔다', () {
      expect(
        MamaDuckTrailRules.scoreForSuccess(pathLength: 7, comboAfterSuccess: 1),
        725,
      );
      expect(
        MamaDuckTrailRules.scoreForSuccess(
          pathLength: 9,
          comboAfterSuccess: 100,
        ),
        1150,
      );
    });

    test('점수를 천 단위 구분으로 표시한다', () {
      expect(MamaDuckTrailRules.formatScore(12345), '12,345점');
      expect(MamaDuckTrailRules.formatHudScore(12345), '12,345');
    });

    test('UTC 날짜와 규칙 버전으로 일일 시드를 고정한다', () {
      final morning = DateTime.utc(2026, 7, 29, 1);
      final evening = DateTime.utc(2026, 7, 29, 23);
      final nextDay = DateTime.utc(2026, 7, 30);

      expect(
        MamaDuckTrailRules.dailySeed(morning),
        MamaDuckTrailRules.dailySeed(evening),
      );
      expect(
        MamaDuckTrailRules.dailySeed(morning),
        isNot(MamaDuckTrailRules.dailySeed(nextDay)),
      );
    });
  });
}
