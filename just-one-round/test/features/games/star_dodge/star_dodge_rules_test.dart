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
  });
}
