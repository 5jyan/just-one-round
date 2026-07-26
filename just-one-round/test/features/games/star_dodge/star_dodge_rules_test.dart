import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/star_dodge/domain/star_dodge_rules.dart';

void main() {
  group('StarDodgeRules', () {
    test('생존 시간을 0.01초 단위로 표시한다', () {
      expect(StarDodgeRules.formatSurvival(12345), '12.35초');
    });

    test('시간이 지날수록 생성 간격은 짧고 낙하 속도는 빨라진다', () {
      expect(
        StarDodgeRules.spawnInterval(1),
        lessThan(StarDodgeRules.spawnInterval(0)),
      );
      expect(
        StarDodgeRules.fallingSpeed(1),
        greaterThan(StarDodgeRules.fallingSpeed(0)),
      );
    });

    test('난이도 진행률을 0에서 1 사이로 제한한다', () {
      expect(
        StarDodgeRules.spawnInterval(-10),
        StarDodgeRules.spawnInterval(0),
      );
      expect(StarDodgeRules.fallingSpeed(10), StarDodgeRules.fallingSpeed(1));
    });

    test('똥피하기 2는 5분까지 승인된 난이도로 계속 상승한다', () {
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
          StarDodgeRules.dungDodgeV2SpawnInterval(milestone.seconds),
          closeTo(milestone.interval, 0.00001),
        );
        expect(
          StarDodgeRules.dungDodgeV2FallingSpeed(milestone.seconds),
          closeTo(milestone.speed, 0.00001),
        );
      }
    });

    test('똥피하기 2 난이도는 5분 이후 승인된 최댓값으로 제한한다', () {
      expect(
        StarDodgeRules.dungDodgeV2SpawnInterval(600),
        closeTo(0.08, 0.00001),
      );
      expect(StarDodgeRules.dungDodgeV2FallingSpeed(600), 920);
    });
  });
}
