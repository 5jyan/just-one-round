import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_map_layout.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_motion.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';

enum GravitySurface { ceiling, floor }

class GravitySwitchGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  GravitySwitchGame({
    required this.onFinished,
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
  static const playerX = 92.0;
  static const playerSize = 48.0;

  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _PrismRunner _player;
  late final Sprite _platformSurface;
  late final Sprite _platformFill;
  late final List<Sprite> _landingSprites;
  late final GravityMapLayout _map;
  final List<_MazeColumn> _columns = [];
  final List<GravityMapProfile> _patternQueue = [];
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _score = 0;
  var _distance = 0;
  var _lastDisplayedSecond = -1;
  String? _lastPatternId;
  var _hasFinished = false;

  @override
  Color backgroundColor() => const Color(0xFF020617);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;
    _map = await GravityMapLayout.load();

    final loaded = await images.loadAll([
      'gravity_switch_v2/space_background.png',
      'gravity_switch_v2/player_sheet.png',
      'gravity_switch_v2/platform_surface.png',
      'gravity_switch_v2/platform_fill.png',
      'gravity_switch_v2/landing_impact_sheet.png',
    ]);
    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );

    final playerSheet = SpriteSheet(image: loaded[1], srcSize: Vector2.all(24));
    _platformSurface = Sprite(loaded[2]);
    _platformFill = Sprite(loaded[3]);
    _landingSprites = _spritesFrom2x2(
      SpriteSheet(image: loaded[4], srcSize: Vector2.all(16)),
    );
    _player = _PrismRunner(
      position: Vector2(playerX, _map.initialProfile.floorTop - playerSize / 2),
      sprites: _spritesFrom2x2(playerSheet),
      onLanded: _showLandingImpact,
    );

    for (var index = 0; index < _map.initialColumnCount; index++) {
      _appendColumn(
        -_map.columnWidth + (index * _map.columnWidth),
        forceSafe: true,
      );
    }
    await world.add(_player);

    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _publishHud(force: true);
    }
  }

  void _showLandingImpact(GravitySurface surface, Vector2 position) {
    world.add(
      _LandingImpact(
        position: position,
        sprites: _landingSprites,
        ceiling: surface == GravitySurface.ceiling,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    switch (_phase) {
      case MiniGamePhase.countdown:
        _countdownElapsed += dt;
        if (_countdownElapsed >=
            countdownDuration.inMicroseconds / Duration.microsecondsPerSecond) {
          _phase = MiniGamePhase.playing;
          _publishHud(force: true);
        } else {
          _publishHud();
        }
      case MiniGamePhase.playing:
        _updatePlaying(dt);
      case MiniGamePhase.finished:
        return;
    }
  }

  void _updatePlaying(double dt) {
    _playingElapsed += dt;
    _score = (_playingElapsed * 1000).floor();
    final speed = GravitySwitchRules.scrollSpeed(_playingElapsed);

    for (final column in List<_MazeColumn>.of(_columns)) {
      column.position.x -= speed * dt;
      if (!column.wasPassed && column.position.x + _map.columnWidth < playerX) {
        column.wasPassed = true;
        _distance += 1;
      }
      if (column.position.x + _map.columnWidth < 0) {
        _columns.remove(column);
        column.removeFromParent();
      }
    }

    while (_columns.isEmpty ||
        _columns.last.position.x < logicalSize.x + _map.columnWidth * 2) {
      final x = _columns.isEmpty
          ? logicalSize.x
          : _columns.last.position.x + _map.columnWidth;
      _appendColumn(x);
    }

    final support = _supportAtPlayer();
    if (support != null) {
      _player.updateSurface(
        dt,
        floorTop: support.floorTop,
        ceilingBottom: support.ceilingBottom,
      );
    }
    for (final column in _columns) {
      if (column.collidesWith(_player)) {
        _finish();
        return;
      }
    }
    _publishHud();
  }

  ({double floorTop, double ceilingBottom})? _supportAtPlayer() {
    final left = playerX - _player.hitbox.width / 2;
    final right = playerX + _player.hitbox.width / 2;
    final supporting = _columns.where(
      (column) =>
          column.position.x < right &&
          column.position.x + _map.columnWidth > left,
    );
    if (supporting.isEmpty) return null;
    return (
      floorTop: supporting.map((column) => column.floorTop).reduce(min),
      ceilingBottom: supporting
          .map((column) => column.ceilingBottom)
          .reduce(max),
    );
  }

  void _appendColumn(double x, {bool forceSafe = false}) {
    final profile = forceSafe ? _map.initialProfile : _nextProfile();
    final column = _MazeColumn(
      floorTop: profile.floorTop,
      ceilingBottom: profile.ceilingBottom,
      columnWidth: _map.columnWidth,
      position: Vector2(x, 0),
      surface: _platformSurface,
      fill: _platformFill,
    );
    _columns.add(column);
    world.add(column);
  }

  GravityMapProfile _nextProfile() {
    if (_patternQueue.isEmpty) _queueNextPattern();
    return _patternQueue.removeAt(0);
  }

  void _queueNextPattern() {
    final available = _map.patterns
        .where((pattern) => pattern.unlockAfterSeconds <= _playingElapsed)
        .toList(growable: false);
    var next = available[_random.nextInt(available.length)];
    if (available.length > 1 && next.id == _lastPatternId) {
      next = available[(available.indexOf(next) + 1) % available.length];
    }
    _lastPatternId = next.id;
    _patternQueue.addAll(next.columns);
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (_phase == MiniGamePhase.playing) _player.switchGravity();
  }

  void _finish() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _publishHud(force: true);
    pauseEngine();
    onFinished(
      GameResult(
        score: _score,
        starsCollected: 0,
        collisions: 1,
        duration: Duration(milliseconds: _score),
      ),
    );
  }

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _publishHud(force: true);
    pauseEngine();
  }

  void _publishHud({bool force = false}) {
    final elapsedSecond = _playingElapsed.floor();
    final countdown = max(
      0,
      (countdownDuration.inMicroseconds / Duration.microsecondsPerSecond -
              _countdownElapsed)
          .ceil(),
    );
    if (!force &&
        elapsedSecond == _lastDisplayedSecond &&
        hud.value.score == _score &&
        hud.value.distance == _distance &&
        hud.value.countdownNumber == countdown) {
      return;
    }
    _lastDisplayedSecond = elapsedSecond;
    hud.value = MiniGameHudState(
      phase: _phase,
      score: _score,
      elapsedSeconds: elapsedSecond,
      remainingSeconds: null,
      countdownNumber: countdown,
      distance: _distance,
    );
  }

  @override
  void disposeController() => hud.dispose();
}

GravitySurface _opposite(GravitySurface surface) =>
    surface == GravitySurface.floor
    ? GravitySurface.ceiling
    : GravitySurface.floor;

List<Sprite> _spritesFrom2x2(SpriteSheet sheet) => [
  sheet.getSprite(0, 0),
  sheet.getSprite(0, 1),
  sheet.getSprite(1, 0),
  sheet.getSprite(1, 1),
];

class _PrismRunner extends PositionComponent {
  _PrismRunner({
    required super.position,
    required this.sprites,
    required this.onLanded,
  }) : super(
         size: Vector2.all(GravitySwitchGame.playerSize),
         anchor: Anchor.center,
         priority: 20,
       );

  final List<Sprite> sprites;
  final void Function(GravitySurface surface, Vector2 position) onLanded;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  final GravitySwitchGate _switchGate = GravitySwitchGate();
  GravitySurface surface = GravitySurface.floor;
  var _animationElapsed = 0.0;
  var _verticalVelocity = 0.0;
  var _isAttached = true;

  Rect get hitbox => Rect.fromCenter(
    center: Offset(position.x, position.y),
    width: 26,
    height: 26,
  );

  void switchGravity() {
    if (!_switchGate.tryStartSwitch()) return;
    surface = _opposite(surface);
    _verticalVelocity = 0;
    _isAttached = false;
  }

  void updateSurface(
    double dt, {
    required double floorTop,
    required double ceilingBottom,
  }) {
    _animationElapsed += dt;
    final wasAttached = _isAttached;
    final direction = surface == GravitySurface.floor ? 1.0 : -1.0;
    final targetY = surface == GravitySurface.floor
        ? floorTop - size.y / 2
        : ceilingBottom + size.y / 2;
    final motion = GravityMotion.step(
      y: position.y,
      verticalVelocity: _verticalVelocity,
      targetY: targetY,
      gravityDirection: direction,
      dt: dt,
    );
    position.y = motion.y;
    _verticalVelocity = motion.verticalVelocity;
    _isAttached = motion.attached;
    if (motion.attached) {
      if (!wasAttached) {
        _switchGate.landed();
        onLanded(
          surface,
          Vector2(
            position.x,
            surface == GravitySurface.floor ? floorTop : ceilingBottom,
          ),
        );
      }
      angle = 0;
      return;
    }
    angle += direction * dt * 8.5;
  }

  @override
  void render(Canvas canvas) {
    if (sprites.isEmpty) return;
    final index = _isAttached
        ? (_animationElapsed / 0.09).floor() % 2
        : 2 + ((_animationElapsed / 0.09).floor() % 2);
    sprites[index].render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _LandingImpact extends PositionComponent {
  _LandingImpact({
    required super.position,
    required this.sprites,
    required this.ceiling,
  }) : super(
         size: Vector2.all(48),
         anchor: ceiling ? Anchor.topCenter : Anchor.bottomCenter,
         priority: 21,
       );

  static const _frameTime = 0.055;
  final List<Sprite> sprites;
  final bool ceiling;
  final Paint _pixelPaint = Paint()..filterQuality = FilterQuality.none;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _frameTime * sprites.length) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (sprites.isEmpty) return;
    final index = min(sprites.length - 1, (_elapsed / _frameTime).floor());
    canvas.save();
    if (ceiling) {
      canvas.translate(0, size.y);
      canvas.scale(1, -1);
    }
    sprites[index].render(canvas, size: size, overridePaint: _pixelPaint);
    canvas.restore();
  }
}

class _MazeColumn extends PositionComponent {
  _MazeColumn({
    required this.floorTop,
    required this.ceilingBottom,
    required this.columnWidth,
    required this.surface,
    required this.fill,
    required super.position,
  }) : super(
         size: Vector2(columnWidth, GravitySwitchGame.logicalSize.y),
         priority: 5,
       );

  final double floorTop;
  final double ceilingBottom;
  final double columnWidth;
  final Sprite surface;
  final Sprite fill;
  final Paint _pixelPaint = Paint()..filterQuality = FilterQuality.none;
  bool wasPassed = false;

  bool collidesWith(_PrismRunner player) {
    final x = position.x;
    final width = columnWidth;
    final floorRect = Rect.fromLTWH(
      x,
      floorTop,
      width,
      GravitySwitchGame.logicalSize.y - floorTop,
    );
    final ceilingRect = Rect.fromLTWH(x, 0, width, ceilingBottom);
    return floorRect.overlaps(player.hitbox) ||
        ceilingRect.overlaps(player.hitbox);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _drawPlatform(
      canvas,
      Rect.fromLTWH(0, floorTop, size.x, size.y - floorTop),
    );
    _drawPlatform(
      canvas,
      Rect.fromLTWH(0, 0, size.x, ceilingBottom),
      ceiling: true,
    );
  }

  void _drawPlatform(Canvas canvas, Rect bounds, {bool ceiling = false}) {
    if (bounds.isEmpty) return;
    canvas.save();
    canvas.clipRect(bounds);
    for (var x = bounds.left; x < bounds.right; x += 24) {
      for (var y = bounds.top; y < bounds.bottom; y += 24) {
        fill.render(
          canvas,
          position: Vector2(x, y),
          size: Vector2(24, 24),
          overridePaint: _pixelPaint,
        );
      }
    }

    if (ceiling) {
      canvas.save();
      canvas.translate(0, bounds.bottom);
      canvas.scale(1, -1);
      surface.render(
        canvas,
        position: Vector2(0, 0),
        size: Vector2(48, 12),
        overridePaint: _pixelPaint,
      );
      canvas.restore();
    } else {
      surface.render(
        canvas,
        position: Vector2(0, bounds.top),
        size: Vector2(48, 12),
        overridePaint: _pixelPaint,
      );
    }
    canvas.restore();
  }
}
