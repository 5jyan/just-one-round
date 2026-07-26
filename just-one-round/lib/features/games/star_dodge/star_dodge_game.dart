import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/star_dodge/domain/star_dodge_rules.dart';

const _artPixel = 2.0;

double _snapToArtGrid(double value) => (value / _artPixel).round() * _artPixel;

class StarDodgeAssetSet {
  const StarDodgeAssetSet({
    required this.directory,
    required this.playerSourceCellSize,
    required this.poopSourceCellSize,
    required this.dustSourceCellSize,
    required this.renderBackgroundInWorld,
    required this.edgeToEdge,
  });

  static const uglyCute = StarDodgeAssetSet(
    directory: 'dung_dodge_v2',
    playerSourceCellSize: 64,
    poopSourceCellSize: 48,
    dustSourceCellSize: 16,
    renderBackgroundInWorld: true,
    edgeToEdge: true,
  );

  final String directory;
  final double playerSourceCellSize;
  final double poopSourceCellSize;
  final double dustSourceCellSize;
  final bool renderBackgroundInWorld;
  final bool edgeToEdge;
}

class StarDodgeGame extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  StarDodgeGame({
    required this.onFinished,
    this.gameDuration = const Duration(seconds: 60),
    this.countdownDuration = const Duration(seconds: 3),
    this.assetSet = StarDodgeAssetSet.uglyCute,
    Random? random,
  }) : _random = random ?? Random(),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: assetSet.edgeToEdge
               ? null
               : gameDuration.inSeconds,
           countdownNumber: countdownDuration.inSeconds,
         ),
       );

  static final logicalSize = Vector2(360, 640);
  static final overscanSize = Vector2(360, 960);
  static const overscanTop = 160.0;
  static const maxVisibleHeight = 800.0;
  static const classicGroundY = 544.0;
  static const uglyCuteGroundY = 576.0;
  static const classicPlayerSize = 64.0;
  static const uglyCutePlayerSize = 64.0;

  static ({double minimum, double maximum}) playerHorizontalBounds({
    required double displaySize,
    required double edgePadding,
  }) => (
    minimum: displaySize / 2 + edgePadding,
    maximum: logicalSize.x - displaySize / 2 - edgePadding,
  );

  final Duration gameDuration;
  final Duration countdownDuration;
  final StarDodgeAssetSet assetSet;
  final ValueChanged<GameResult> onFinished;
  final Random _random;
  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _PlayerComponent _player;
  var _poopSprites = <Sprite>[];
  var _poopImpactSprites = <Sprite>[];
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _spawnElapsed = 0.0;
  var _score = 0;
  var _collisions = 0;
  var _lastDisplayedSecond = -1;
  var _lastCountdownNumber = -1;
  var _hasFinished = false;
  double? _lastDragX;
  var _pendingDragDistance = 0.0;
  var _dragActivated = false;

  static const dragActivationDistance = 6.0;

  double get progress {
    final totalSeconds = gameDuration.inMicroseconds / 1000000;
    if (totalSeconds <= 0) {
      return 1;
    }
    return (_playingElapsed / totalSeconds).clamp(0.0, 1.0);
  }

  double get groundY => assetSet.edgeToEdge ? uglyCuteGroundY : classicGroundY;
  double get playerSize =>
      assetSet.edgeToEdge ? uglyCutePlayerSize : classicPlayerSize;

  static bool hasReachedGround({
    required double centerY,
    required double objectHeight,
    required double groundY,
  }) => centerY + objectHeight / 2 >= groundY;

  @override
  Color backgroundColor() => Colors.transparent;

  static Vector2 viewportResolutionForCanvas(Vector2 canvasSize) {
    if (canvasSize.x <= 0 || canvasSize.y <= 0) {
      return logicalSize.clone();
    }
    final visibleHeight = (canvasSize.y * logicalSize.x / canvasSize.x).clamp(
      logicalSize.y,
      maxVisibleHeight,
    );
    return Vector2(logicalSize.x, visibleHeight);
  }

  void _configureViewport(Vector2 canvasSize) {
    final resolution = assetSet.edgeToEdge
        ? viewportResolutionForCanvas(canvasSize)
        : logicalSize.clone();
    camera.viewport = FixedResolutionViewport(resolution: resolution);
    // Keep the original 360×640 gameplay core centered. Taller screens reveal
    // authored sky and soil overscan instead of stretching or color padding.
    camera.viewfinder.position = logicalSize / 2;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);

    final ground = _GroundComponent(
      size: logicalSize.clone(),
      usesOverscanArt: assetSet.edgeToEdge,
      groundY: groundY,
    );
    await world.add(ground);
    _player = _PlayerComponent(
      position: Vector2(logicalSize.x / 2, groundY - playerSize / 2),
      displaySize: playerSize,
      edgePadding: assetSet.edgeToEdge ? 0 : 8,
      collisionRadius: assetSet.edgeToEdge ? 16 : 18,
    );
    await world.add(_player);
    final loaded = await images.loadAll([
      '${assetSet.directory}/player_idle_sheet.png',
      '${assetSet.directory}/player_run_sheet.png',
      '${assetSet.directory}/poop_fall_sheet.png',
      '${assetSet.directory}/dust_sheet.png',
      '${assetSet.directory}/background_map.png',
      '${assetSet.directory}/ground_strip.png',
      if (assetSet.edgeToEdge) '${assetSet.directory}/poop_impact_sheet.png',
      if (assetSet.edgeToEdge) '${assetSet.directory}/player_game_over.png',
    ]);
    final idleSheet = SpriteSheet(
      image: loaded[0],
      srcSize: Vector2.all(assetSet.playerSourceCellSize),
    );
    final runSheet = SpriteSheet(
      image: loaded[1],
      srcSize: Vector2.all(assetSet.playerSourceCellSize),
    );
    final poopSheet = SpriteSheet(
      image: loaded[2],
      srcSize: Vector2.all(assetSet.poopSourceCellSize),
    );
    final dustSheet = SpriteSheet(
      image: loaded[3],
      srcSize: Vector2.all(assetSet.dustSourceCellSize),
    );
    _poopSprites = _spritesFrom2x2(poopSheet);
    if (assetSet.edgeToEdge) {
      final impactSheet = SpriteSheet(
        image: loaded[6],
        srcSize: Vector2.all(64),
      );
      _poopImpactSprites = _spritesFrom2x2(impactSheet);
    }
    _player.setSprites(
      idleFrames: _spritesFrom2x2(idleSheet),
      walkFrames: _spritesFrom2x2(runSheet),
      dustFrames: _spritesFrom2x2(dustSheet),
      gameOverSprite: assetSet.edgeToEdge ? Sprite(loaded[7]) : null,
    );
    ground.setSprites(
      background: assetSet.renderBackgroundInWorld ? Sprite(loaded[4]) : null,
      ground: Sprite(loaded[5]),
    );

    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _publishHud(force: true);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _configureViewport(size);
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

    final interval = assetSet.edgeToEdge
        ? StarDodgeRules.dungDodgeV2SpawnInterval(_playingElapsed)
        : StarDodgeRules.spawnInterval(progress);
    while (_spawnElapsed >= interval) {
      _spawnElapsed -= interval;
      _spawnFallingObject();
    }

    _checkCollisionsAndGroundImpacts();

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
    final baseSpeed = assetSet.edgeToEdge
        ? StarDodgeRules.dungDodgeV2FallingSpeed(_playingElapsed)
        : StarDodgeRules.fallingSpeed(progress);
    final speed = baseSpeed * (0.88 + (_random.nextDouble() * 0.3));

    world.add(
      _FallingObjectComponent(
        speed: speed,
        position: Vector2(x, -48),
        sprites: _poopSprites,
      ),
    );
  }

  void _checkCollisionsAndGroundImpacts() {
    final objects = world.children
        .whereType<_FallingObjectComponent>()
        .toList();
    for (final object in objects) {
      if (object.isRemoving) {
        continue;
      }

      if (object.collidesWith(_player)) {
        object.removeFromParent();
        _handlePlayerCollision();
        return;
      }

      if (assetSet.edgeToEdge &&
          hasReachedGround(
            centerY: object.position.y,
            objectHeight: object.size.y,
            groundY: groundY,
          )) {
        object.removeFromParent();
        if (_poopImpactSprites.isNotEmpty) {
          world.add(
            _PoopImpactComponent(
              position: Vector2(object.position.x, groundY),
              sprites: _poopImpactSprites,
            ),
          );
        }
      } else if (!assetSet.edgeToEdge &&
          object.position.y - object.size.y / 2 > logicalSize.y) {
        object.removeFromParent();
      }
    }
  }

  void _handlePlayerCollision() {
    _collisions = 1;
    _player.showGameOverPose();
    _finishGame();
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
        endType: _collisions > 0 ? GameEndType.gameOver : GameEndType.timeUp,
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
      remainingSeconds: assetSet.edgeToEdge ? null : remaining,
      countdownNumber: countdown,
    );
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_phase != MiniGamePhase.playing) return;
    final viewportPosition = camera.viewport.globalToLocal(
      event.canvasPosition,
    );
    _beginRelativeDrag(viewportPosition.x);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_phase != MiniGamePhase.playing) return;
    final viewportPosition = camera.viewport.globalToLocal(
      event.canvasEndPosition,
    );
    _updateRelativeDrag(viewportPosition.x);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _resetRelativeDrag();
    _player.stopMoving();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _resetRelativeDrag();
    _player.stopMoving();
  }

  void _beginRelativeDrag(double logicalX) {
    _lastDragX = logicalX;
    _pendingDragDistance = 0;
    _dragActivated = false;
  }

  void _updateRelativeDrag(double logicalX) {
    final previousX = _lastDragX;
    _lastDragX = logicalX;
    if (previousX == null) {
      _beginRelativeDrag(logicalX);
      return;
    }

    final deltaX = logicalX - previousX;
    if (!_dragActivated) {
      _pendingDragDistance += deltaX;
      if (_pendingDragDistance.abs() < dragActivationDistance) {
        return;
      }
      _dragActivated = true;
      _player.moveBy(_pendingDragDistance);
      _pendingDragDistance = 0;
      return;
    }
    _player.moveBy(deltaX);
  }

  void _resetRelativeDrag() {
    _lastDragX = null;
    _pendingDragDistance = 0;
    _dragActivated = false;
  }

  @visibleForTesting
  double get playerXForTesting => _player.position.x;

  @visibleForTesting
  void beginRelativeDragForTesting(double logicalX) =>
      _beginRelativeDrag(logicalX);

  @visibleForTesting
  void updateRelativeDragForTesting(double logicalX) =>
      _updateRelativeDrag(logicalX);

  @visibleForTesting
  bool get isShowingGameOverPoseForTesting => _player.isShowingGameOverPose;

  @visibleForTesting
  void handlePlayerCollisionForTesting() => _handlePlayerCollision();

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
  _PlayerComponent({
    required Vector2 position,
    required double displaySize,
    required this.edgePadding,
    required this.collisionRadius,
  }) : _preciseX = position.x,
       super(
         position: position,
         size: Vector2.all(displaySize),
         anchor: Anchor.center,
         priority: 10,
       );

  static const _moveSpeed = 355.0;
  final double edgePadding;
  final double collisionRadius;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  var _idleSprites = <Sprite>[];
  var _walkSprites = <Sprite>[];
  var _dustSprites = <Sprite>[];
  Sprite? _gameOverSprite;
  double? _targetX;
  double _preciseX;
  var _velocityX = 0.0;
  var _walkElapsed = 0.0;
  var _idleElapsed = 0.0;
  var _dustElapsed = 0.0;
  var _facing = 1.0;
  var _isWalking = false;
  var _isShowingGameOverPose = false;

  bool get isShowingGameOverPose => _isShowingGameOverPose;

  void setSprites({
    required List<Sprite> idleFrames,
    required List<Sprite> walkFrames,
    required List<Sprite> dustFrames,
    required Sprite? gameOverSprite,
  }) {
    _idleSprites = idleFrames;
    _walkSprites = walkFrames;
    _dustSprites = dustFrames;
    _gameOverSprite = gameOverSprite;
  }

  void showGameOverPose() {
    stopMoving();
    _isShowingGameOverPose = _gameOverSprite != null;
    scale.x = 1;
  }

  void setTargetX(double x) {
    final bounds = StarDodgeGame.playerHorizontalBounds(
      displaySize: size.x,
      edgePadding: edgePadding,
    );
    final clamped = x.clamp(bounds.minimum, bounds.maximum).toDouble();
    _targetX = _snapToArtGrid(clamped);
  }

  void moveBy(double deltaX) {
    setTargetX((_targetX ?? _preciseX) + deltaX);
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
            _snapToArtGrid(position.y + size.y / 2 - 4),
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
    if (_isShowingGameOverPose) {
      _gameOverSprite?.render(canvas, size: size, overridePaint: _spritePaint);
      return;
    }
    final sprite = _isWalking && _walkSprites.isNotEmpty
        ? _walkSprites[(_walkElapsed / 0.15).floor() % _walkSprites.length]
        : _idleSprites.isEmpty
        ? null
        : _idleSprites[(_idleElapsed / 0.28).floor() % _idleSprites.length];
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

class _PoopImpactComponent extends PositionComponent {
  _PoopImpactComponent({required Vector2 position, required this.sprites})
    : super(
        position: position,
        size: Vector2.all(64),
        anchor: Anchor.bottomCenter,
        priority: 7,
      );

  final List<Sprite> sprites;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= 0.3) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (sprites.isEmpty) return;
    final index = ((_elapsed / 0.075).floor()).clamp(0, sprites.length - 1);
    sprites[index].render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _GroundComponent extends PositionComponent {
  _GroundComponent({
    required super.size,
    required this.usesOverscanArt,
    required this.groundY,
  }) : super(priority: -10);

  final Paint _pixelPaint = Paint()..filterQuality = FilterQuality.none;
  final bool usesOverscanArt;
  final double groundY;
  Sprite? _background;
  Sprite? _ground;

  void setSprites({required Sprite? background, required Sprite ground}) {
    _background = background;
    _ground = ground;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _background?.render(
      canvas,
      position: usesOverscanArt
          ? Vector2(0, -StarDodgeGame.overscanTop)
          : Vector2.zero(),
      size: usesOverscanArt
          ? StarDodgeGame.overscanSize
          : StarDodgeGame.logicalSize,
      overridePaint: _pixelPaint,
    );
    _ground?.render(
      canvas,
      position: Vector2(0, groundY),
      size: Vector2(360, usesOverscanArt ? 208 : 96),
      overridePaint: _pixelPaint,
    );
  }
}
