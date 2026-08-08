import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/domain/dung_dodge_v2_rules.dart';

void main() {
  group('DungDodgeV2Rules', () {
    test('생존 시간을 0.01초 단위로 표시한다', () {
      expect(DungDodgeV2Rules.formatSurvival(12345), '12.35초');
      expect(DungDodgeV2Rules.formatHudTime(12345), '12.35');
    });

    test('시간이 지날수록 생성 간격은 짧고 낙하 속도는 빨라진다', () {
      expect(
        DungDodgeV2Rules.spawnInterval(1),
        lessThan(DungDodgeV2Rules.spawnInterval(0)),
      );
      expect(
        DungDodgeV2Rules.fallingSpeed(1),
        greaterThan(DungDodgeV2Rules.fallingSpeed(0)),
      );
    });

    test('난이도 시간을 0초에서 260초 사이로 제한한다', () {
      expect(
        DungDodgeV2Rules.spawnInterval(-10),
        DungDodgeV2Rules.spawnInterval(0),
      );
      expect(
        DungDodgeV2Rules.fallingSpeed(600),
        DungDodgeV2Rules.fallingSpeed(260),
      );
    });

    test('똥피하기 난이도 기준점을 40초씩 앞당겨 적용한다', () {
      const expectedMilestones = [
        (seconds: 0.0, interval: 0.62, speed: 170.0),
        (seconds: 20.0, interval: 0.38, speed: 297.5),
        (seconds: 80.0, interval: 0.14, speed: 680.0),
        (seconds: 140.0, interval: 0.12, speed: 760.0),
        (seconds: 200.0, interval: 0.10, speed: 840.0),
        (seconds: 260.0, interval: 0.08, speed: 920.0),
      ];

      for (final milestone in expectedMilestones) {
        expect(
          DungDodgeV2Rules.spawnInterval(milestone.seconds),
          closeTo(milestone.interval, 0.00001),
        );
        expect(
          DungDodgeV2Rules.fallingSpeed(milestone.seconds),
          closeTo(milestone.speed, 0.00001),
        );
      }
    });

    test('각 기준점 사이의 난이도를 선형 보간한다', () {
      expect(DungDodgeV2Rules.spawnInterval(10), closeTo(0.50, 0.00001));
      expect(DungDodgeV2Rules.fallingSpeed(10), closeTo(233.75, 0.00001));
      expect(DungDodgeV2Rules.spawnInterval(50), closeTo(0.26, 0.00001));
      expect(DungDodgeV2Rules.fallingSpeed(50), closeTo(488.75, 0.00001));
    });

    test('똥피하기 난이도는 260초 이후 최댓값으로 제한한다', () {
      expect(DungDodgeV2Rules.spawnInterval(600), closeTo(0.08, 0.00001));
      expect(DungDodgeV2Rules.fallingSpeed(600), 920);
    });
  });
}
