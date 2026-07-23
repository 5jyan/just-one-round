import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_motion.dart';

void main() {
  test('자연 낙하 중에는 스위치할 수 있지만 스위치 이동 중에는 연타가 막힌다', () {
    final gate = GravitySwitchGate();

    // Walking off a ledge does not touch the gate.
    expect(gate.isSwitching, isFalse);
    expect(gate.tryStartSwitch(), isTrue);
    expect(gate.tryStartSwitch(), isFalse);

    gate.landed();
    expect(gate.tryStartSwitch(), isTrue);
  });

  test('높은 발판에서 낮은 발판으로 넘어가면 계속 아래로 낙하한다', () {
    var state = const GravityMotionState(
      y: 432,
      verticalVelocity: 0,
      attached: true,
    );

    state = GravityMotion.step(
      y: state.y,
      verticalVelocity: state.verticalVelocity,
      targetY: 464,
      gravityDirection: 1,
      dt: 1 / 60,
    );
    expect(state.attached, isFalse);
    expect(state.y, greaterThan(432));

    for (var frame = 0; frame < 60 && !state.attached; frame++) {
      state = GravityMotion.step(
        y: state.y,
        verticalVelocity: state.verticalVelocity,
        targetY: 464,
        gravityDirection: 1,
        dt: 1 / 60,
      );
    }
    expect(state.attached, isTrue);
    expect(state.y, 464);
  });

  test('중력을 반전하면 천장 방향으로 가속한다', () {
    final state = GravityMotion.step(
      y: 480,
      verticalVelocity: 0,
      targetY: 160,
      gravityDirection: -1,
      dt: 1 / 60,
    );

    expect(state.attached, isFalse);
    expect(state.verticalVelocity, lessThan(0));
    expect(state.y, lessThan(480));
  });

  test('반대 표면까지 약 0.4초 안에 도달한다', () {
    var state = const GravityMotionState(
      y: 480,
      verticalVelocity: 0,
      attached: false,
    );
    var frames = 0;
    while (!state.attached && frames < 60) {
      state = GravityMotion.step(
        y: state.y,
        verticalVelocity: state.verticalVelocity,
        targetY: 160,
        gravityDirection: -1,
        dt: 1 / 60,
      );
      frames += 1;
    }

    expect(state.attached, isTrue);
    expect(frames, lessThanOrEqualTo(24));
  });
}
