import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';

void main() {
  test('생존 시간이 늘수록 이동 속도가 증가한다', () {
    expect(
      GravitySwitchRules.scrollSpeed(60),
      greaterThan(GravitySwitchRules.scrollSpeed(0)),
    );
    expect(GravitySwitchRules.scrollSpeed(1000), 680);
  });

  test('약 60초부터 연속 중력 전환이 매우 어려워진다', () {
    expect(GravitySwitchRules.spawnInterval(0), closeTo(1.24, 0.001));
    expect(GravitySwitchRules.spawnInterval(60), closeTo(0.34, 0.001));
    expect(GravitySwitchRules.alternatingPatternChance(60), 0.95);
  });

  test('난이도 값은 장시간 생존해도 안전 범위에 고정된다', () {
    expect(GravitySwitchRules.spawnInterval(1000), 0.34);
    expect(GravitySwitchRules.alternatingPatternChance(1000), 0.95);
  });
}
