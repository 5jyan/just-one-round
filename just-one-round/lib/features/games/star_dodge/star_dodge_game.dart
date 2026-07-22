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

    await world.add(_StarfieldComponent(size: logicalSize.clone()));
    _player = _PlayerComponent(
      position: Vector2(logicalSize.x / 2, logicalSize.y - 66),
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
    if (_spawnElapsed >= interval) {
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
    _player.moveToX(viewportPosition.x);
  }
}

class _PlayerComponent extends SpriteComponent {
  _PlayerComponent({required super.position})
    : super(size: Vector2(34, 42), anchor: Anchor.center, priority: 10);

  double get collisionRadius => 13;

  @override
  Future<void> onLoad() async {
    sprite = await Sprite.load('dodge_hero.png');
  }

  void moveToX(double x) {
    position.x = x.clamp(
      size.x / 2 + 8,
      StarDodgeGame.logicalSize.x - size.x / 2 - 8,
    );
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
    final fill = Paint()..color = const Color(0xFF91522C);
    final shadow = Paint()..color = const Color(0xFF56301F);
    final dark = Paint()..color = AppColors.backgroundDeep;
    final diameter = radius * 2;

    canvas.drawRect(Rect.fromLTWH(4, 0, diameter - 8, diameter), fill);
    canvas.drawRect(Rect.fromLTWH(0, 5, diameter, diameter - 10), fill);
    canvas.drawRect(Rect.fromLTWH(4, diameter - 6, diameter - 8, 6), shadow);
    canvas.drawRect(Rect.fromLTWH(radius * 0.35, radius * 0.45, 6, 6), dark);
    canvas.drawRect(Rect.fromLTWH(radius * 1.15, radius * 1.05, 5, 5), dark);
  }
}

class _StarfieldComponent extends PositionComponent {
  _StarfieldComponent({required super.size}) : super(priority: -10);

  final _stars = List.generate(54, (index) {
    final random = Random(index * 7919);
    return Offset(
      random.nextDouble() * StarDodgeGame.logicalSize.x,
      random.nextDouble() * StarDodgeGame.logicalSize.y,
    );
  });

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final dimPaint = Paint()
      ..color = AppColors.surfaceLight.withValues(alpha: 0.45);
    final brightPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.65);

    for (var index = 0; index < _stars.length; index++) {
      final star = _stars[index];
      final paint = index % 7 == 0 ? brightPaint : dimPaint;
      final side = index % 7 == 0 ? 2.0 : 1.0;
      canvas.drawRect(Rect.fromLTWH(star.dx, star.dy, side, side), paint);
    }
  }
}
