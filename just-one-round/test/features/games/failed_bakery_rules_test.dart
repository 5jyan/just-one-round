import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/failed_bakery/domain/failed_bakery_rules.dart';

void main() {
  const base = CakeFootprint(x: 0, z: 0, width: 160, depth: 160);

  test('이동 축은 층마다 X와 Z를 번갈아 사용한다', () {
    expect(FailedBakeryRules.axisForLayer(1), CakeMoveAxis.x);
    expect(FailedBakeryRules.axisForLayer(2), CakeMoveAxis.z);
    expect(FailedBakeryRules.axisForLayer(3), CakeMoveAxis.x);
  });

  test('X축에서 겹친 부분과 잘린 조각을 정확히 계산한다', () {
    const moving = CakeFootprint(x: 20, z: 0, width: 160, depth: 160);
    final result = FailedBakeryRules.place(
      below: base,
      moving: moving,
      axis: CakeMoveAxis.x,
    )!;

    expect(result.isPerfect, isFalse);
    expect(result.landed.x, 10);
    expect(result.landed.width, 140);
    expect(result.landed.depth, 160);
    expect(result.offcut!.x, 90);
    expect(result.offcut!.width, 20);
  });

  test('Z축에서 겹친 깊이만 남긴다', () {
    const moving = CakeFootprint(x: 0, z: -30, width: 160, depth: 160);
    final result = FailedBakeryRules.place(
      below: base,
      moving: moving,
      axis: CakeMoveAxis.z,
    )!;

    expect(result.landed.z, -15);
    expect(result.landed.depth, 130);
    expect(result.offcut!.depth, 30);
  });

  test('허용 오차 안에서는 아래 케이크에 퍼펙트 스냅한다', () {
    const moving = CakeFootprint(x: 3.9, z: 0, width: 160, depth: 160);
    final result = FailedBakeryRules.place(
      below: base,
      moving: moving,
      axis: CakeMoveAxis.x,
    )!;

    expect(result.isPerfect, isTrue);
    expect(result.landed.x, 0);
    expect(result.landed.width, 160);
    expect(result.offcut, isNull);
  });

  test('전혀 겹치지 않으면 실패한다', () {
    const moving = CakeFootprint(x: 160, z: 0, width: 160, depth: 160);
    expect(
      FailedBakeryRules.place(
        below: base,
        moving: moving,
        axis: CakeMoveAxis.x,
      ),
      isNull,
    );
  });

  test('연속 퍼펙트 보상은 최초 크기를 넘지 않는다', () {
    const narrow = CakeFootprint(x: 0, z: 0, width: 100, depth: 156);
    final recovered = FailedBakeryRules.recover(narrow);
    expect(recovered.width, 108);
    expect(recovered.depth, 160);
  });

  test('층수가 높아질수록 빨라지되 최대 속도를 넘지 않는다', () {
    expect(FailedBakeryRules.speedForLayer(1), 120);
    expect(FailedBakeryRules.speedForLayer(10), 183);
    expect(FailedBakeryRules.speedForLayer(100), 330);
    expect(FailedBakeryRules.formatLayers(27), '27층');
  });
}
