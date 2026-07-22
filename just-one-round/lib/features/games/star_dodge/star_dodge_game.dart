import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/star_dodge/domain/star_dodge_rules.dart';

const _artPixel = 2.0;

double _snapToArtGrid(double value) => (value / _artPixel).round() * _artPixel;

class StarDodgeGame extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  StarDodgeGame({
    required this.onFinished,
    this.gameDuration = const Duration(seconds: 60),
    this.countdownDuration = const Duration(seconds: 3),
    Random? random,
  }) : _random = random ?? Random(),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: gameDuration.inSeconds,
           countdownNumber: countdownDuration.inSeconds,
         ),
       );

  static final logicalSize = Vector2(360, 640);

  final Duration gameDuration;
  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;
  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _PlayerComponent _player;
  var _poopSprites = <Sprite>[];
  var _phase = MiniGamePhase.countdown;
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

    final ground = _GroundComponent(size: logicalSize.clone());
    await world.add(ground);
    _player = _PlayerComponent(position: Vector2(logicalSize.x / 2, 512));
    await world.add(_player);
    images
        .loadAll([
          'dodge_v2/player_idle_sheet.png',
          'dodge_v2/player_run_sheet.png',
          'dodge_v2/poop_fall_sheet.png',
          'dodge_v2/dust_sheet.png',
          'dodge_v2/background_map.png',
          'dodge_v2/ground_strip.png',
        ])
        .then((loaded) {
          final idleSheet = SpriteSheet(
            image: loaded[0],
            srcSize: Vector2.all(32),
          );
          final runSheet = SpriteSheet(
            image: loaded[1],
            srcSize: Vector2.all(32),
          );
          final poopSheet = SpriteSheet(
            image: loaded[2],
            srcSize: Vector2.all(24),
          );
          final dustSheet = SpriteSheet(
            image: loaded[3],
            srcSize: Vector2.all(16),
          );
          _poopSprites = _spritesFrom2x2(poopSheet);
          _player.setSprites(
            idleFrames: _spritesFrom2x2(idleSheet),
            walkFrames: _spritesFrom2x2(runSheet),
            dustFrames: _spritesFrom2x2(dustSheet),
          );
          ground.setSprites(
            background: Sprite(loaded[4]),
            ground: Sprite(loaded[5]),
          );
        });

    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _publishHud(force: true);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    switch (_phase) {
      case MiniGamePhase.countdown:
        _updateCountdown(dt);
      case MiniGamePhase.playing:
        _updatePlaying(dt);
      case MiniGamePhase.finished:
        return;
    }
  }

  void _updateCountdown(double dt) {
    _countdownElapsed += dt;
    final countdownSeconds = countdownDuration.inMicroseconds / 1000000;
    if (_countdownElapsed >= countdownSeconds) {
      _phase = MiniGamePhase.playing;
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
    final x = _snapToArtGrid(
      24 + (_random.nextDouble() * (logicalSize.x - 48)),
    );
    final baseSpeed = StarDodgeRules.fallingSpeed(progress);
    final speed = baseSpeed * (0.88 + (_random.nextDouble() * 0.3));

    world.add(
      _FallingObjectComponent(
        speed: speed,
        position: Vector2(x, -48),
        sprites: _poopSprites,
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
    _phase = MiniGamePhase.finished;
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
        // Star Dodge's raw score is its actual survival time. Keep the
        // transport value in integer milliseconds as well, so the value shown
        // by the client and the value ranked by the server cannot diverge.
        duration: Duration(milliseconds: _score),
      ),
    );
  }

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    for (final object in world.children.whereType<_FallingObjectComponent>()) {
      object.removeFromParent();
    }
    _publishHud(force: true);
    pauseEngine();
  }

  void _recalculateScore() {
    final maximumMilliseconds = gameDuration.inMilliseconds;
    _score = (_playingElapsed * 1000).floor().clamp(0, maximumMilliseconds);
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
    hud.value = MiniGameHudState(
      phase: _phase,
      score: _score,
      elapsedSeconds: _playingElapsed.floor(),
      remainingSeconds: remaining,
      countdownNumber: countdown,
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

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _player.stopMoving();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _player.stopMoving();
  }

  void _movePlayerTo(Vector2 canvasPosition) {
    if (_phase != MiniGamePhase.playing) {
      return;
    }
    final viewportPosition = camera.viewport.globalToLocal(canvasPosition);
    _player.setTargetX(viewportPosition.x);
  }

  @override
  void disposeController() => hud.dispose();
}

List<Sprite> _spritesFrom2x2(SpriteSheet sheet) => [
  sheet.getSprite(0, 0),
  sheet.getSprite(0, 1),
  sheet.getSprite(1, 0),
  sheet.getSprite(1, 1),
];

class _PlayerComponent extends PositionComponent {
  _PlayerComponent({required Vector2 position})
    : _preciseX = position.x,
      super(
        position: position,
        size: Vector2.all(64),
        anchor: Anchor.center,
        priority: 10,
      );

  static const _moveSpeed = 355.0;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  var _idleSprites = <Sprite>[];
  var _walkSprites = <Sprite>[];
  var _dustSprites = <Sprite>[];
  double? _targetX;
  double _preciseX;
  var _velocityX = 0.0;
  var _walkElapsed = 0.0;
  var _idleElapsed = 0.0;
  var _dustElapsed = 0.0;
  var _facing = 1.0;
  var _isWalking = false;

  double get collisionRadius => 18;

  void setSprites({
    required List<Sprite> idleFrames,
    required List<Sprite> walkFrames,
    required List<Sprite> dustFrames,
  }) {
    _idleSprites = idleFrames;
    _walkSprites = walkFrames;
    _dustSprites = dustFrames;
  }

  void setTargetX(double x) {
    final clamped = x
        .clamp(size.x / 2 + 8, StarDodgeGame.logicalSize.x - size.x / 2 - 8)
        .toDouble();
    _targetX = _snapToArtGrid(clamped);
  }

  void stopMoving() {
    _targetX = null;
    _velocityX = 0;
    _isWalking = false;
    _dustElapsed = 0;
    scale.x = -_facing;
    angle = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final target = _targetX;
    if (target == null) {
      _velocityX = 0;
      _settleAnimation(dt);
      return;
    }

    final delta = target - _preciseX;
    final desiredVelocity = (delta * 11).clamp(-_moveSpeed, _moveSpeed);
    _velocityX += (desiredVelocity - _velocityX) * min(1, dt * 17);
    final step = _velocityX * dt;
    if (delta.abs() < 0.8 ||
        (step.abs() >= delta.abs() && step.sign == delta.sign)) {
      _preciseX = target;
      position.x = target;
      _targetX = null;
      _velocityX = 0;
      _settleAnimation(dt);
      return;
    }

    _preciseX += step;
    position.x = _snapToArtGrid(_preciseX);
    _facing = _velocityX.sign == 0 ? _facing : _velocityX.sign;
    // The authored side sprite faces left, so mirror it while moving right.
    scale.x = -_facing;
    _walkElapsed += dt;
    angle = 0;
    _isWalking = true;

    _dustElapsed += dt;
    if (_dustElapsed >= 0.13) {
      _dustElapsed = 0;
      parent?.add(
        _DustPuffComponent(
          position: Vector2(
            _snapToArtGrid(position.x - (_facing * 15)),
            _snapToArtGrid(position.y + 28),
          ),
          direction: _facing,
          sprites: _dustSprites,
        ),
      );
    }
  }

  void _settleAnimation(double dt) {
    _isWalking = false;
    _idleElapsed += dt;
    _dustElapsed = 0;
    scale.x = -_facing;
    angle = 0;
  }

  @override
  void render(Canvas canvas) {
    final sprite = _isWalking && _walkSprites.isNotEmpty
        ? _walkSprites[(_walkElapsed / 0.10).floor() % _walkSprites.length]
        : _idleSprites.isEmpty
        ? null
        : _idleSprites[(_idleElapsed / 0.18).floor() % _idleSprites.length];
    sprite?.render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _DustPuffComponent extends PositionComponent {
  _DustPuffComponent({
    required Vector2 position,
    required this.direction,
    required this.sprites,
  }) : _preciseX = position.x,
       _preciseY = position.y,
       super(
         position: position,
         size: Vector2.all(32),
         anchor: Anchor.center,
         priority: 8,
       );

  final double direction;
  final List<Sprite> sprites;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  double _preciseX;
  double _preciseY;
  var _age = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    _preciseX -= direction * 24 * dt;
    _preciseY -= 9 * dt;
    position.x = _snapToArtGrid(_preciseX);
    position.y = _snapToArtGrid(_preciseY);
    if (_age >= 0.34) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (sprites.isEmpty) return;
    final index = ((_age / 0.085).floor()).clamp(0, sprites.length - 1);
    sprites[index].render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _FallingObjectComponent extends PositionComponent {
  _FallingObjectComponent({
    required this.speed,
    required Vector2 position,
    required this.sprites,
  }) : _preciseY = position.y,
       super(
         position: position,
         size: Vector2.all(48),
         anchor: Anchor.center,
         priority: 5,
       );

  final double speed;
  final List<Sprite> sprites;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  double _preciseY;
  var _animationElapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _preciseY += speed * dt;
    _animationElapsed += dt;
    position.y = _snapToArtGrid(_preciseY);
    if (position.y - 24 > StarDodgeGame.logicalSize.y) {
      removeFromParent();
    }
  }

  bool collidesWith(_PlayerComponent player) {
    final dx = position.x - player.position.x;
    final dy = position.y - player.position.y;
    final combinedRadius = 18 + player.collisionRadius;
    return (dx * dx) + (dy * dy) <= combinedRadius * combinedRadius;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (sprites.isEmpty) return;
    final sprite = sprites[(_animationElapsed / 0.11).floor() % sprites.length];
    sprite.render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _GroundComponent extends PositionComponent {
  _GroundComponent({required super.size}) : super(priority: -10);

  final Paint _pixelPaint = Paint()..filterQuality = FilterQuality.none;
  Sprite? _background;
  Sprite? _ground;

  void setSprites({required Sprite background, required Sprite ground}) {
    _background = background;
    _ground = ground;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _background?.render(
      canvas,
      size: StarDodgeGame.logicalSize,
      overridePaint: _pixelPaint,
    );
    _ground?.render(
      canvas,
      position: Vector2(0, 544),
      size: Vector2(360, 96),
      overridePaint: _pixelPaint,
    );
  }
}
