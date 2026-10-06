import 'package:flame/components.dart' show Vector2;
import 'package:flutter/material.dart';
import 'package:just_one_round/features/games/wind_darts/wind_darts_game.dart';

/// Routes raw pointer input so moving a held finger continues aiming until up.
class WindDartsInputSurface extends StatelessWidget {
  const WindDartsInputSurface({
    super.key,
    required this.game,
    required this.child,
  });

  final WindDartsGame game;
  final Widget child;

  Offset _gamePosition(Offset globalPosition) {
    final position = game.camera.globalToLocal(
      Vector2(globalPosition.dx, globalPosition.dy),
    );
    return Offset(position.x, position.y);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) =>
          game.pointerDown(event.pointer, _gamePosition(event.position)),
      onPointerMove: (event) =>
          game.pointerMove(event.pointer, _gamePosition(event.position)),
      onPointerUp: (event) => game.pointerUp(event.pointer),
      onPointerCancel: (event) => game.pointerCancel(event.pointer),
      child: child,
    );
  }
}
