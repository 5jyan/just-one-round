import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/domain/dung_dodge_v2_rules.dart';

const _artPixel = 2.0;

double _snapToArtGrid(double value) => (value / _artPixel).round() * _artPixel;

class DungDodgeV2Game extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  DungDodgeV2Game({
    required this.onFinished,
    this.gameDuration = const Duration(minutes: 5),
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
           remainingSeconds: null,
           countdownNumber: countdownDuration.inSeconds,
         ),
       );

  static final logicalSize = Vector2(360, 640);
  static final overscanSize = Vector2(360, 960);
  static const overscanTop = 160.0;
  static const maxVisibleHeight = 800.0;
  static const groundY = 576.0;
  static const playerSize = 64.0;
  static const _assetDirectory = 'dung_dodge_v2';
  static const _playerSourceCellSize = 64.0;
  static const _poopSourceCellSize = 48.0;
  static const _dustSourceCellSize = 16.0;

  static ({double minimum, double maximum}) playerHorizontalBounds({
    required double displaySize,
    required double edgePadding,
  }) => (
    minimum: displaySize / 2 + edgePadding,
    maximum: logicalSize.x - displaySize / 2 - edgePadding,
  );

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
  var _poopMasks = <_PixelMask>[];
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
  int? _activeDragPointerId;
  double? _dragStartX;
  double? _lastDragX;
  var _dragActivated = false;

  static const dragActivationDistance = 6.0;

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
    final resolution = viewportResolutionForCanvas(canvasSize);
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
      groundY: groundY,
    );
    await world.add(ground);
    _player = _PlayerComponent(
      position: Vector2(logicalSize.x / 2, groundY - playerSize / 2),
      displaySize: playerSize,
      edgePadding: 0,
    );
    await world.add(_player);
    final loaded = await images.loadAll([
      '$_assetDirectory/player_idle_sheet.png',
      '$_assetDirectory/player_run_sheet.png',
      '$_assetDirectory/poop_fall_sheet.png',
      '$_assetDirectory/dust_sheet.png',
      '$_assetDirectory/background_map.png',
      '$_assetDirectory/ground_strip.png',
      '$_assetDirectory/poop_impact_sheet.png',
      '$_assetDirectory/player_game_over.png',
    ]);
    final idleSheet = SpriteSheet(
      image: loaded[0],
      srcSize: Vector2.all(_playerSourceCellSize),
    );
    final runSheet = SpriteSheet(
      image: loaded[1],
      srcSize: Vector2.all(_playerSourceCellSize),
    );
    final poopSheet = SpriteSheet(
      image: loaded[2],
      srcSize: Vector2.all(_poopSourceCellSize),
    );
    final dustSheet = SpriteSheet(
      image: loaded[3],
      srcSize: Vector2.all(_dustSourceCellSize),
    );
    _poopSprites = _spritesFrom2x2(poopSheet);
    final impactSheet = SpriteSheet(image: loaded[6], srcSize: Vector2.all(64));
    _poopImpactSprites = _spritesFrom2x2(impactSheet);
    _poopMasks = await _pixelMasksFromSheet(
      loaded[2],
      cellSize: _poopSourceCellSize.toInt(),
      inset: 3,
    );
    _player.setSprites(
      idleFrames: _spritesFrom2x2(idleSheet),
      walkFrames: _spritesFrom2x2(runSheet),
      dustFrames: _spritesFrom2x2(dustSheet),
      gameOverSprite: Sprite(loaded[7]),
      idleMasks: await _pixelMasksFromSheet(
        loaded[0],
        cellSize: _playerSourceCellSize.toInt(),
        inset: 3,
      ),
      walkMasks: await _pixelMasksFromSheet(
        loaded[1],
        cellSize: _playerSourceCellSize.toInt(),
        inset: 3,
      ),
    );
    ground.setSprites(background: Sprite(loaded[4]), ground: Sprite(loaded[5]));

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

    final interval = DungDodgeV2Rules.spawnInterval(_playingElapsed);
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
    final baseSpeed = DungDodgeV2Rules.fallingSpeed(_playingElapsed);
    final speed = baseSpeed * (0.88 + (_random.nextDouble() * 0.3));

    world.add(
      _FallingObjectComponent(
        speed: speed,
        position: Vector2(x, -48),
        sprites: _poopSprites,
        masks: _poopMasks,
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

      if (object.collidesDuringMovement(_player)) {
        object.removeFromParent();
        _handlePlayerCollision();
        return;
      }

      if (hasReachedGround(
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
    _resetRelativeDrag();
    _player.stopMoving();
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
    _resetRelativeDrag();
    if (isLoaded) {
      _player.stopMoving();
    }
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
      remainingSeconds: null,
      countdownNumber: countdown,
    );
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _handleDragStart(event.pointerId, _logicalDragX(event.canvasPosition));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    _handleDragUpdateDelta(event.pointerId, _logicalDragDeltaX(event));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _handleDragEnd(event.pointerId);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _handleDragEnd(event.pointerId);
  }

  double _logicalDragX(Vector2 canvasPosition) =>
      camera.viewport.globalToLocal(canvasPosition).x;

  double _logicalDragDeltaX(DragUpdateEvent event) {
    final start = event.canvasStartPosition;
    final end = start + event.canvasDelta;
    return _logicalDragX(end) - _logicalDragX(start);
  }

  void _handleDragStart(int pointerId, double logicalX) {
    if (_phase != MiniGamePhase.playing || _activeDragPointerId != null) {
      return;
    }
    _activeDragPointerId = pointerId;
    _beginRelativeDrag(logicalX);
  }

  void _handleDragUpdate(int pointerId, double logicalX) {
    if (_activeDragPointerId != pointerId || _phase != MiniGamePhase.playing) {
      return;
    }
    _updateRelativeDrag(logicalX);
  }

  void _handleDragUpdateDelta(int pointerId, double logicalDeltaX) {
    if (_activeDragPointerId != pointerId || _phase != MiniGamePhase.playing) {
      return;
    }
    final previousX = _lastDragX;
    if (previousX == null) {
      return;
    }
    _updateRelativeDrag(previousX + logicalDeltaX);
  }

  void _handleDragEnd(int pointerId) {
    if (_activeDragPointerId != pointerId) {
      return;
    }
    _resetRelativeDrag();
    if (isLoaded) {
      _player.stopMoving();
    }
  }

  void _beginRelativeDrag(double logicalX) {
    _dragStartX = logicalX;
    _lastDragX = logicalX;
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
      final dragStartX = _dragStartX ?? previousX;
      final totalDeltaX = logicalX - dragStartX;
      if (totalDeltaX.abs() < dragActivationDistance) {
        return;
      }
      _dragActivated = true;
      // Commit the complete displacement from the touch-down point when the
      // dead zone is crossed. This keeps the first threshold-sized movement
      // from being lost, while still keeping a tap from moving the player.
      _movePlayerBy(totalDeltaX);
      return;
    }
    _movePlayerBy(deltaX);
  }

  void _resetRelativeDrag() {
    _activeDragPointerId = null;
    _dragStartX = null;
    _lastDragX = null;
    _dragActivated = false;
  }

  bool _movePlayerBy(double deltaX) {
    if (_phase != MiniGamePhase.playing || _hasFinished) {
      return false;
    }

    final startX = _player.position.x;
    final appliedDeltaX = _player.moveBy(deltaX);
    if (appliedDeltaX == 0) {
      return false;
    }

    final endX = startX + appliedDeltaX;
    final objects = world.children
        .whereType<_FallingObjectComponent>()
        .toList();
    for (final object in objects) {
      if (object.isRemoving) {
        continue;
      }
      if (!object.collidesAlongHorizontalPath(
        _player,
        fromX: startX,
        toX: endX,
      )) {
        continue;
      }
      object.removeFromParent();
      _handlePlayerCollision();
      return true;
    }
    return true;
  }

  @visibleForTesting
  double get playerXForTesting => _player.position.x;

  @visibleForTesting
  void addHazardForTesting({
    required double x,
    required double y,
    double speed = 0,
  }) {
    world.add(
      _FallingObjectComponent(
        speed: speed,
        position: Vector2(x, y),
        sprites: _poopSprites,
        masks: _poopMasks,
      ),
    );
  }

  @visibleForTesting
  double logicalDragXForTesting(Vector2 canvasPosition) =>
      _logicalDragX(canvasPosition);

  @visibleForTesting
  void beginRelativeDragForTesting(double logicalX) {
    _activeDragPointerId = 0;
    _beginRelativeDrag(logicalX);
  }

  @visibleForTesting
  void updateRelativeDragForTesting(double logicalX) =>
      _updateRelativeDrag(logicalX);

  @visibleForTesting
  void beginPointerDragForTesting(int pointerId, double logicalX) =>
      _handleDragStart(pointerId, logicalX);

  @visibleForTesting
  void updatePointerDragForTesting(int pointerId, double logicalX) =>
      _handleDragUpdate(pointerId, logicalX);

  @visibleForTesting
  void endPointerDragForTesting(int pointerId) => _handleDragEnd(pointerId);

  @visibleForTesting
  bool get isShowingGameOverPoseForTesting => _player.isShowingGameOverPose;

  @visibleForTesting
  void handlePlayerCollisionForTesting() => _handlePlayerCollision();

  @override
  void disposeController() => hud.dispose();
}

Future<List<_PixelMask>> _pixelMasksFromSheet(
  ui.Image image, {
  required int cellSize,
  required int inset,
}) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return [];
  final rgba = bytes.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  return [
    for (var row = 0; row < 2; row++)
      for (var column = 0; column < 2; column++)
        _PixelMask.fromRgba(
          rgba,
          imageWidth: image.width,
          left: column * cellSize,
          top: row * cellSize,
          size: cellSize,
          inset: inset,
        ),
  ];
}

class _PixelMask {
  const _PixelMask(this.size, this.pixels);

  final int size;
  final Uint8List pixels;

  factory _PixelMask.fromRgba(
    Uint8List rgba, {
    required int imageWidth,
    required int left,
    required int top,
    required int size,
    required int inset,
  }) {
    final source = Uint8List(size * size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        source[y * size + x] =
            rgba[((top + y) * imageWidth + left + x) * 4 + 3] == 0 ? 0 : 1;
      }
    }
    final pixels = Uint8List(size * size);
    final insetSquared = inset * inset;
    for (var y = inset; y < size - inset; y++) {
      for (var x = inset; x < size - inset; x++) {
        if (source[y * size + x] == 0) continue;
        var inside = true;
        for (var dy = -inset; dy <= inset && inside; dy++) {
          for (var dx = -inset; dx <= inset; dx++) {
            if (dx * dx + dy * dy > insetSquared) continue;
            if (source[(y + dy) * size + x + dx] == 0) {
              inside = false;
              break;
            }
          }
        }
        if (inside) pixels[y * size + x] = 1;
      }
    }
    return _PixelMask(size, pixels);
  }

  bool overlaps(
    _PixelMask other, {
    required int left,
    required int top,
    required int otherLeft,
    required int otherTop,
    bool flipX = false,
  }) {
    final startX = max(left, otherLeft);
    final endX = min(left + size, otherLeft + other.size);
    final startY = max(top, otherTop);
    final endY = min(top + size, otherTop + other.size);
    for (var y = startY; y < endY; y++) {
      final localY = y - top;
      final otherY = y - otherTop;
      for (var x = startX; x < endX; x++) {
        final localX = x - left;
        final otherX = x - otherLeft;
        final playerX = flipX ? size - 1 - localX : localX;
        if (pixels[localY * size + playerX] == 1 &&
            other.pixels[otherY * other.size + otherX] == 1) {
          return true;
        }
      }
    }
    return false;
  }
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
  }) : _preciseX = position.x,
       super(
         position: position,
         size: Vector2.all(displaySize),
         anchor: Anchor.center,
         priority: 10,
       );

  final double edgePadding;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  var _idleSprites = <Sprite>[];
  var _walkSprites = <Sprite>[];
  var _idleMasks = <_PixelMask>[];
  var _walkMasks = <_PixelMask>[];
  var _dustSprites = <Sprite>[];
  Sprite? _gameOverSprite;
  double _preciseX;
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
    required List<_PixelMask> idleMasks,
    required List<_PixelMask> walkMasks,
  }) {
    _idleSprites = idleFrames;
    _walkSprites = walkFrames;
    _dustSprites = dustFrames;
    _gameOverSprite = gameOverSprite;
    _idleMasks = idleMasks;
    _walkMasks = walkMasks;
  }

  _PixelMask? get collisionMask {
    final masks = _isWalking ? _walkMasks : _idleMasks;
    if (masks.isEmpty) return null;
    final elapsed = _isWalking ? _walkElapsed : _idleElapsed;
    final frameDuration = _isWalking ? 0.15 : 0.28;
    return masks[(elapsed / frameDuration).floor() % masks.length];
  }

  void showGameOverPose() {
    stopMoving();
    _isShowingGameOverPose = _gameOverSprite != null;
    scale.x = 1;
  }

  double moveBy(double deltaX) {
    final bounds = DungDodgeV2Game.playerHorizontalBounds(
      displaySize: size.x,
      edgePadding: edgePadding,
    );
    final previousX = _preciseX;
    _preciseX = (_preciseX + deltaX)
        .clamp(bounds.minimum, bounds.maximum)
        .toDouble();
    position.x = _preciseX;
    final appliedDeltaX = _preciseX - previousX;
    if (appliedDeltaX != 0) {
      _facing = appliedDeltaX.sign;
      // The authored side sprite faces left, so mirror it while moving right.
      scale.x = -_facing;
      angle = 0;
      _isWalking = true;
    }
    return appliedDeltaX;
  }

  void stopMoving() {
    _isWalking = false;
    _dustElapsed = 0;
    scale.x = -_facing;
    angle = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_isWalking) {
      _settleAnimation(dt);
      return;
    }

    _walkElapsed += dt;
    angle = 0;

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
    required this.masks,
  }) : _preciseY = position.y,
       _previousY = position.y,
       super(
         position: position,
         size: Vector2.all(48),
         anchor: Anchor.center,
         priority: 5,
       );

  final double speed;
  final List<Sprite> sprites;
  final List<_PixelMask> masks;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  double _preciseY;
  double _previousY;
  var _animationElapsed = 0.0;

  _PixelMask? get collisionMask => masks.isEmpty
      ? null
      : masks[(_animationElapsed / 0.11).floor() % masks.length];

  @override
  void update(double dt) {
    super.update(dt);
    _previousY = _preciseY;
    _preciseY += speed * dt;
    _animationElapsed += dt;
    position.y = _snapToArtGrid(_preciseY);
  }

  bool collidesWith(_PlayerComponent player) {
    return _collidesAt(player, position.y);
  }

  bool collidesDuringMovement(_PlayerComponent player) {
    final distance = (position.y - _previousY).abs();
    final steps = max(1, distance.ceil());
    for (var step = 0; step <= steps; step++) {
      final y = _previousY + (position.y - _previousY) * step / steps;
      if (_collidesAt(player, y)) return true;
    }
    return false;
  }

  bool collidesAlongHorizontalPath(
    _PlayerComponent player, {
    required double fromX,
    required double toX,
  }) {
    final distance = (toX - fromX).abs();
    final steps = max(1, distance.ceil());
    for (var step = 0; step <= steps; step++) {
      final x = fromX + (toX - fromX) * step / steps;
      if (_collidesAt(player, position.y, playerX: x)) return true;
    }
    return false;
  }

  bool _collidesAt(_PlayerComponent player, double poopY, {double? playerX}) {
    final playerMask = player.collisionMask;
    final poopMask = collisionMask;
    if (playerMask == null || poopMask == null) {
      final dx = (position.x - (playerX ?? player.position.x)).abs();
      final dy = (poopY - player.position.y).abs();
      return dx < 18 + player.size.x / 4 && dy < 18 + player.size.y / 4;
    }
    return playerMask.overlaps(
      poopMask,
      left: ((playerX ?? player.position.x) - player.size.x / 2).round(),
      top: (player.position.y - player.size.y / 2).round(),
      otherLeft: (position.x - size.x / 2).round(),
      otherTop: (poopY - size.y / 2).round(),
      flipX: player.scale.x < 0,
    );
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
  _GroundComponent({required super.size, required this.groundY})
    : super(priority: -10);

  final Paint _pixelPaint = Paint()..filterQuality = FilterQuality.none;
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
      position: Vector2(0, -DungDodgeV2Game.overscanTop),
      size: DungDodgeV2Game.overscanSize,
      overridePaint: _pixelPaint,
    );
    _ground?.render(
      canvas,
      position: Vector2(0, groundY),
      size: Vector2(360, 208),
      overridePaint: _pixelPaint,
    );
  }
}
