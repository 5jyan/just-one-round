import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:just_one_round/features/games/gravity_switch/gravity_switch_game.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';

void main() {
  test('생존 시간이 늘수록 이동 속도가 증가한다', () {
    expect(GravitySwitchRules.scrollSpeed(0), 160);
    expect(GravitySwitchRules.scrollSpeed(1), 161.5);
    expect(GravitySwitchRules.scrollSpeed(10), 175);
    expect(GravitySwitchRules.scrollSpeed(45), 227.5);
    expect(GravitySwitchRules.scrollSpeed(60), 250);
    expect(GravitySwitchRules.scrollSpeed(1000), 360);
  });

  test('긴 화면에서는 게임 코어를 움직이지 않고 세로 viewport만 확장한다', () {
    expect(
      GravitySwitchGame.viewportResolutionForCanvas(Vector2(360, 640)),
      Vector2(360, 640),
    );
    final tallResolution = GravitySwitchGame.viewportResolutionForCanvas(
      Vector2(402, 874),
    );
    expect(tallResolution.x, 360);
    expect(tallResolution.y, closeTo(782.686, 0.001));
    expect(
      GravitySwitchGame.viewportResolutionForCanvas(Vector2(360, 900)),
      Vector2(360, GravitySwitchGame.maxVisibleHeight),
    );
  });

  test('약 60초부터 기둥 사이 안전 구간이 최소화된다', () {
    expect(GravitySwitchRules.safeColumnCount(0), 4);
    expect(GravitySwitchRules.safeColumnCount(60), 1);
    expect(GravitySwitchRules.hazardHeight(60), 205);
    expect(
      GravitySwitchRules.alternatingPatternChance(60),
      closeTo(0.918, 0.001),
    );
  });

  test('난이도 값은 장시간 생존해도 안전 범위에 고정된다', () {
    expect(GravitySwitchRules.scrollSpeed(1000), 360);
    expect(GravitySwitchRules.safeColumnCount(1000), 1);
    expect(GravitySwitchRules.hazardHeight(1000), 205);
    expect(GravitySwitchRules.alternatingPatternChance(1000), 0.92);
  });

  test('활성 표면 방향으로 중력이 계속 가속된다', () {
    expect(GravitySwitchRules.columnWidth, 48);
    expect(GravitySwitchRules.gravityAcceleration, greaterThan(0));
    expect(GravitySwitchRules.maxVerticalSpeed, greaterThan(0));
    expect(GravitySwitchRules.surfaceSnapTolerance, lessThan(16));
  });

  test('플레이 HUD 시간에는 초 단위를 붙이지 않는다', () {
    expect(GravitySwitchRules.formatHudTime(0), '0.00');
    expect(GravitySwitchRules.formatHudTime(12340), '12.34');
    expect(GravitySwitchRules.formatSurvival(12340), '12.34초');
  });
}
