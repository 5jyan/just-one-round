import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';

class GravityMotionState {
  const GravityMotionState({
    required this.y,
    required this.verticalVelocity,
    required this.attached,
  });

  final double y;
  final double verticalVelocity;
  final bool attached;
}

/// Blocks repeat taps only for the trip started by a gravity switch.
///
/// A normal ledge fall never locks this gate, so the player may still switch
/// gravity before landing.
class GravitySwitchGate {
  bool _isSwitching = false;

  bool get isSwitching => _isSwitching;

  bool tryStartSwitch() {
    if (_isSwitching) return false;
    _isSwitching = true;
    return true;
  }

  void landed() => _isSwitching = false;
}

abstract final class GravityMotion {
  static GravityMotionState step({
    required double y,
    required double verticalVelocity,
    required double targetY,
    required double gravityDirection,
    required double dt,
  }) {
    final velocity =
        (verticalVelocity +
                gravityDirection * GravitySwitchRules.gravityAcceleration * dt)
            .clamp(
              -GravitySwitchRules.maxVerticalSpeed,
              GravitySwitchRules.maxVerticalSpeed,
            );
    final nextY = y + velocity * dt;
    final closeEnough =
        (targetY - y).abs() <= GravitySwitchRules.surfaceSnapTolerance;
    final crossedSurface = gravityDirection > 0
        ? y <= targetY && nextY >= targetY
        : y >= targetY && nextY <= targetY;

    if (closeEnough || crossedSurface) {
      return GravityMotionState(
        y: targetY,
        verticalVelocity: 0,
        attached: true,
      );
    }
    return GravityMotionState(
      y: nextY,
      verticalVelocity: velocity,
      attached: false,
    );
  }
}
