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

    test('난이도 시간을 0초에서 5분 사이로 제한한다', () {
      expect(
        DungDodgeV2Rules.spawnInterval(-10),
        DungDodgeV2Rules.spawnInterval(0),
      );
      expect(
        DungDodgeV2Rules.fallingSpeed(600),
        DungDodgeV2Rules.fallingSpeed(300),
      );
    });

    test('똥피하기는 5분까지 승인된 난이도로 계속 상승한다', () {
      const expectedMilestones = [
        (seconds: 0.0, interval: 0.62, speed: 170.0),
        (seconds: 60.0, interval: 0.38, speed: 297.5),
        (seconds: 120.0, interval: 0.14, speed: 680.0),
        (seconds: 180.0, interval: 0.12, speed: 760.0),
        (seconds: 240.0, interval: 0.10, speed: 840.0),
        (seconds: 300.0, interval: 0.08, speed: 920.0),
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

    test('똥피하기 난이도는 5분 이후 승인된 최댓값으로 제한한다', () {
      expect(DungDodgeV2Rules.spawnInterval(600), closeTo(0.08, 0.00001));
      expect(DungDodgeV2Rules.fallingSpeed(600), 920);
    });
  });
}
