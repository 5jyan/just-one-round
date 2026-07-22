import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/star_dodge/domain/star_dodge_rules.dart';

enum StarDodgePhase { countdown, playing, finished }

class StarDodgeHudState {
  const StarDodgeHudState({
    required this.phase,
    required this.score,
    required this.remainingSeconds,
    required this.countdownNumber,
    required this.starsCollected,
    required this.collisions,
  });

  factory StarDodgeHudState.initial({
    required Duration duration,
    required Duration countdownDuration,
  }) {
    return StarDodgeHudState(
      phase: countdownDuration == Duration.zero
          ? StarDodgePhase.playing
          : StarDodgePhase.countdown,
      score: 0,
      remainingSeconds: duration.inSeconds,
      countdownNumber: countdownDuration.inSeconds,
      starsCollected: 0,
      collisions: 0,
    );
  }

  final StarDodgePhase phase;
  final int score;
  final int remainingSeconds;
  final int countdownNumber;
  final int starsCollected;
  final int collisions;
}

class StarDodgeGame extends FlameGame with DragCallbacks {
  StarDodgeGame({
    required this.onFinished,
    this.gameDuration = const Duration(seconds: 60),
    this.countdownDuration = const Duration(seconds: 3),
    Random? random,
  }) : _random = random ?? Random(),
       hud = ValueNotifier(
         StarDodgeHudState.initial(
           duration: gameDuration,
           countdownDuration: countdownDuration,
         ),
       );

  static final logicalSize = Vector2(360, 640);

  final Duration gameDuration;
  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;
  final ValueNotifier<StarDodgeHudState> hud;

  late final _PlayerComponent _player;
  var _phase = StarDodgePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _spawnElapsed = 0.0;
  var _score = 0;
  var _collisions = 0;
  var _lastDisplayedSecond = -1;
  var _lastCountdownNumber = -1;
  var _hasFinished = false;

  double get progress {
    final totalSeconds = gameDuration.inMicroseconds / 1000000;
    if (totalSeconds <= 0) {
      return 1;
    }
    return (_playingElapsed / totalSeconds).clamp(0.0, 1.0);
  }

  @override
  Color backgroundColor() => AppColors.backgroundDeep;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    await world.add(_GroundComponent(size: logicalSize.clone()));
    _player = _PlayerComponent(
      position: Vector2(logicalSize.x / 2, logicalSize.y - 92),
    );
    world.add(_player);

    if (countdownDuration == Duration.zero) {
      _phase = StarDodgePhase.playing;
      _publishHud(force: true);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    switch (_phase) {
      case StarDodgePhase.countdown:
        _updateCountdown(dt);
      case StarDodgePhase.playing:
        _updatePlaying(dt);
      case StarDodgePhase.finished:
        return;
    }
  }

  void _updateCountdown(double dt) {
    _countdownElapsed += dt;
    final countdownSeconds = countdownDuration.inMicroseconds / 1000000;
    if (_countdownElapsed >= countdownSeconds) {
      _phase = StarDodgePhase.playing;
      _publishHud(force: true);
      return;
    }
    _publishHud();
  }

  void _updatePlaying(double dt) {
    _playingElapsed += dt;
    _spawnElapsed += dt;
    _recalculateScore();

    final interval = StarDodgeRules.spawnInterval(progress);
    while (_spawnElapsed >= interval) {
      _spawnElapsed -= interval;
      _spawnFallingObject();
    }

    _checkCollisions();

    final durationSeconds = gameDuration.inMicroseconds / 1000000;
    if (_playingElapsed >= durationSeconds) {
      _finishGame();
      return;
    }

    _publishHud();
  }

  void _spawnFallingObject() {
    final radius = 15.0 + (_random.nextDouble() * 9);
    final x = 24 + (_random.nextDouble() * (logicalSize.x - 48));
    final baseSpeed = StarDodgeRules.fallingSpeed(progress);
    final speed = baseSpeed * (0.88 + (_random.nextDouble() * 0.3));

    world.add(
      _FallingObjectComponent(
        radius: radius,
        speed: speed,
        position: Vector2(x, -radius * 2),
      ),
    );
  }

  void _checkCollisions() {
    final objects = world.children
        .whereType<_FallingObjectComponent>()
        .toList();
    for (final object in objects) {
      if (object.isRemoving || !object.collidesWith(_player)) {
        continue;
      }

      object.removeFromParent();
      _collisions = 1;
      _finishGame();
      return;
    }
  }

  void _finishGame() {
    if (_hasFinished) {
      return;
    }
    _hasFinished = true;
    _phase = StarDodgePhase.finished;
    for (final object in world.children.whereType<_FallingObjectComponent>()) {
      object.removeFromParent();
    }
    _publishHud(force: true);
    pauseEngine();
    onFinished(
      GameResult(
        score: _score,
        starsCollected: 0,
        collisions: _collisions,
        duration: gameDuration,
      ),
    );
  }

  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = StarDodgePhase.finished;
    for (final object in world.children.whereType<_FallingObjectComponent>()) {
      object.removeFromParent();
    }
    _publishHud(force: true);
    pauseEngine();
  }

  void _recalculateScore() {
    _score = (_playingElapsed * 1000).floor();
  }

  void _publishHud({bool force = false}) {
    final remaining = max(
      0,
      (gameDuration.inMicroseconds / 1000000 - _playingElapsed).ceil(),
    );
    final countdown = max(
      0,
      (countdownDuration.inMicroseconds / 1000000 - _countdownElapsed).ceil(),
    );

    if (!force &&
        remaining == _lastDisplayedSecond &&
        countdown == _lastCountdownNumber &&
        hud.value.score == _score) {
      return;
    }

    _lastDisplayedSecond = remaining;
    _lastCountdownNumber = countdown;
    hud.value = StarDodgeHudState(
      phase: _phase,
      score: _score,
      remainingSeconds: remaining,
      countdownNumber: countdown,
      starsCollected: 0,
      collisions: _collisions,
    );
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _movePlayerTo(event.canvasPosition);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    _movePlayerTo(event.canvasEndPosition);
  }

  void _movePlayerTo(Vector2 canvasPosition) {
    if (_phase != StarDodgePhase.playing) {
      return;
    }
    final viewportPosition = camera.viewport.globalToLocal(canvasPosition);
    _player.setTargetX(viewportPosition.x);
  }
}

class _PlayerComponent extends SpriteComponent {
  _PlayerComponent({required super.position})
    : super(size: Vector2(78, 96), anchor: Anchor.center, priority: 10);

  static const _moveSpeed = 320.0;
  double? _targetX;
  var _walkElapsed = 0.0;

  double get collisionRadius => 24;

  @override
  Future<void> onLoad() async {
    sprite = await Sprite.load('dodge_hero.png');
  }

  void setTargetX(double x) {
    _targetX = x.clamp(
      size.x / 2 + 8,
      StarDodgeGame.logicalSize.x - size.x / 2 - 8,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    final target = _targetX;
    if (target == null) return;
    final delta = target - position.x;
    if (delta.abs() < 1) {
      position.x = target;
      _targetX = null;
      angle = 0;
      return;
    }
    final direction = delta.sign;
    position.x += direction * min(_moveSpeed * dt, delta.abs());
    _walkElapsed += dt * 13;
    angle = sin(_walkElapsed) * 0.045;
    scale.x = direction;
  }
}

class _FallingObjectComponent extends PositionComponent {
  _FallingObjectComponent({
    required this.radius,
    required this.speed,
    required super.position,
  }) : super(size: Vector2.all(radius * 2), anchor: Anchor.center, priority: 5);

  final double radius;
  final double speed;

  @override
  void update(double dt) {
    super.update(dt);
    position.y += speed * dt;
    if (position.y - radius > StarDodgeGame.logicalSize.y) {
      removeFromParent();
    }
  }

  bool collidesWith(_PlayerComponent player) {
    final dx = position.x - player.position.x;
    final dy = position.y - player.position.y;
    final combinedRadius = radius * 0.72 + player.collisionRadius;
    return (dx * dx) + (dy * dy) <= combinedRadius * combinedRadius;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderObstacle(canvas);
  }

  void _renderObstacle(Canvas canvas) {
    final fill = Paint()..color = const Color(0xFF9C572B);
    final shadow = Paint()..color = const Color(0xFF5A2E19);
    final dark = Paint()..color = AppColors.backgroundDeep;
    canvas.drawCircle(Offset(radius, radius * 1.25), radius * .72, fill);
    canvas.drawCircle(Offset(radius * .82, radius * .75), radius * .52, fill);
    canvas.drawCircle(Offset(radius * 1.1, radius * .36), radius * .33, fill);
    canvas.drawRect(
      Rect.fromLTWH(radius * .75, radius * 1.65, radius * .7, 5),
      shadow,
    );
    canvas.drawRect(Rect.fromLTWH(radius * .65, radius * .9, 4, 4), dark);
    canvas.drawRect(Rect.fromLTWH(radius * 1.2, radius * .9, 4, 4), dark);
  }
}

class _GroundComponent extends PositionComponent {
  _GroundComponent({required super.size}) : super(priority: -10);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final sky = Paint()..color = const Color(0xFF8DD8F8);
    final cloud = Paint()..color = const Color(0xFFF6F0D2);
    final grass = Paint()..color = const Color(0xFF3B9B55);
    final soil = Paint()..color = const Color(0xFF89502B);
    canvas.drawRect(Offset.zero & Size(size.x, size.y), sky);
    canvas.drawRect(Rect.fromLTWH(0, 540, size.x, 100), soil);
    canvas.drawRect(Rect.fromLTWH(0, 532, size.x, 12), grass);
    for (final x in [40.0, 188.0, 292.0]) {
      canvas.drawRect(Rect.fromLTWH(x, 92 + (x % 3) * 18, 48, 15), cloud);
      canvas.drawRect(Rect.fromLTWH(x + 10, 77 + (x % 3) * 18, 28, 16), cloud);
    }
    for (var x = 0.0; x < size.x; x += 28) {
      canvas.drawRect(Rect.fromLTWH(x, 570 + (x % 2) * 15, 7, 5), grass);
    }
  }
}
