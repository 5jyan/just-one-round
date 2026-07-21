import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/star_dodge/domain/star_dodge_rules.dart';

void main() {
  group('StarDodgeRules', () {
    test('별 수집과 생존 시간으로 점수를 얻는다', () {
      final afterStar = StarDodgeRules.collectStar(20);
      final afterSurvival = StarDodgeRules.addSurvivalTime(afterStar, 3);

      expect(afterStar, 120);
      expect(afterSurvival, 150);
    });

    test('장애물 감점으로 점수가 음수가 되지 않는다', () {
      expect(StarDodgeRules.hitObstacle(120), 70);
      expect(StarDodgeRules.hitObstacle(20), 0);
      expect(StarDodgeRules.hitObstacle(0), 0);
    });

    test('서버와 같은 카운터 공식으로 최종 점수를 계산한다', () {
      expect(
        StarDodgeRules.calculateScore(
          starsCollected: 3,
          collisions: 2,
          survivalSeconds: 60,
        ),
        800,
      );
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
