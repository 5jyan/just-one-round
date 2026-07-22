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
  static const ceilingY = 112.0;
  static const floorY = 560.0;
  static const playerX = 92.0;

  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _GravityPlayer _player;
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _spawnElapsed = 0.0;
  var _score = 0;
  var _lastDisplayedSecond = -1;
  var _lastSpawnSurface = GravitySurface.floor;
  var _hasFinished = false;

  @override
  Color backgroundColor() => AppColors.backgroundDeep;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    final loaded = await images.loadAll([
      'dodge_v2/player_run_sheet.png',
      'dodge_v2/background_map.png',
      'dodge_v2/ground_strip.png',
    ]);
    final runSheet = SpriteSheet(image: loaded[0], srcSize: Vector2.all(32));
    final background = _GravityBackground(
      size: logicalSize.clone(),
      background: Sprite(loaded[1]),
      ground: Sprite(loaded[2]),
    );
    await world.add(background);

    _player = _GravityPlayer(
      position: Vector2(playerX, floorY - 32),
      runSprites: _spritesFrom2x2(runSheet),
    );
    await world.add(_player);

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
    _spawnElapsed += dt;
    _score = (_playingElapsed * 1000).floor();

    final interval = GravitySwitchRules.spawnInterval(_playingElapsed);
    while (_spawnElapsed >= interval) {
      _spawnElapsed -= interval;
      _spawnObstacle();
    }

    final speed = GravitySwitchRules.scrollSpeed(_playingElapsed);
    for (final obstacle in world.children.whereType<_GravityObstacle>()) {
      obstacle.advance(dt, speed);
      if (!obstacle.removing && obstacle.collidesWith(_player)) {
        _finish();
        return;
      }
    }
    _publishHud();
  }

  void _spawnObstacle() {
    final alternate =
        _random.nextDouble() <
        GravitySwitchRules.alternatingPatternChance(_playingElapsed);
    final surface = alternate
        ? _opposite(_lastSpawnSurface)
        : (_random.nextBool() ? GravitySurface.floor : GravitySurface.ceiling);
    _lastSpawnSurface = surface;
    world.add(
      _GravityObstacle(
        surface: surface,
        position: Vector2(
          logicalSize.x + 36,
          surface == GravitySurface.floor ? floorY - 28 : ceilingY + 28,
        ),
      ),
    );
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

class _GravityPlayer extends PositionComponent {
  _GravityPlayer({required super.position, required this.runSprites})
    : super(size: Vector2.all(64), anchor: Anchor.center, priority: 10) {
    scale.x = -1;
  }

  final List<Sprite> runSprites;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  GravitySurface surface = GravitySurface.floor;
  GravitySurface? _targetSurface;
  var _switchElapsed = 0.0;
  var _animationElapsed = 0.0;

  Rect get hitbox => Rect.fromCenter(
    center: Offset(position.x, position.y),
    width: 34,
    height: 42,
  );

  void switchGravity() {
    if (_targetSurface != null) return;
    _targetSurface = _opposite(surface);
    _switchElapsed = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _animationElapsed += dt;
    final target = _targetSurface;
    if (target == null) return;

    _switchElapsed += dt;
    final progress = (_switchElapsed / GravitySwitchRules.switchDuration).clamp(
      0.0,
      1.0,
    );
    final eased = progress < 0.5
        ? 4 * progress * progress * progress
        : 1 - pow(-2 * progress + 2, 3) / 2;
    final startY = surface == GravitySurface.floor
        ? GravitySwitchGame.floorY - 32
        : GravitySwitchGame.ceilingY + 32;
    final endY = target == GravitySurface.floor
        ? GravitySwitchGame.floorY - 32
        : GravitySwitchGame.ceilingY + 32;
    position.y = startY + ((endY - startY) * eased);
    if (progress >= 0.5) scale.y = target == GravitySurface.floor ? 1 : -1;
    if (progress >= 1) {
      surface = target;
      _targetSurface = null;
      position.y = endY;
    }
  }

  @override
  void render(Canvas canvas) {
    if (runSprites.isEmpty) return;
    final index = (_animationElapsed / 0.09).floor() % runSprites.length;
    runSprites[index].render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _GravityObstacle extends PositionComponent {
  _GravityObstacle({required this.surface, required super.position})
    : super(size: Vector2(42, 56), anchor: Anchor.center, priority: 6);

  final GravitySurface surface;
  final Paint _bodyPaint = Paint()..color = AppColors.danger;
  final Paint _highlightPaint = Paint()..color = AppColors.primary;
  var removing = false;

  Rect get hitbox => Rect.fromCenter(
    center: Offset(position.x, position.y),
    width: 34,
    height: 48,
  );

  void advance(double dt, double speed) {
    position.x -= speed * dt;
    if (position.x + size.x < 0) {
      removing = true;
      removeFromParent();
    }
  }

  bool collidesWith(_GravityPlayer player) => hitbox.overlaps(player.hitbox);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.drawRect(const Rect.fromLTWH(6, 10, 30, 42), _bodyPaint);
    final path = Path()
      ..moveTo(3, surface == GravitySurface.floor ? 10 : 46)
      ..lineTo(12, surface == GravitySurface.floor ? 0 : 56)
      ..lineTo(21, surface == GravitySurface.floor ? 10 : 46)
      ..lineTo(30, surface == GravitySurface.floor ? 0 : 56)
      ..lineTo(39, surface == GravitySurface.floor ? 10 : 46)
      ..close();
    canvas.drawPath(path, _highlightPaint);
  }
}

class _GravityBackground extends PositionComponent {
  _GravityBackground({
    required super.size,
    required this.background,
    required this.ground,
  }) : super(priority: -10);

  final Sprite background;
  final Sprite ground;
  final Paint _paint = Paint()..filterQuality = FilterQuality.none;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    background.render(canvas, size: size, overridePaint: _paint);
    canvas.save();
    canvas.translate(0, GravitySwitchGame.ceilingY);
    canvas.scale(1, -1);
    ground.render(
      canvas,
      size: Vector2(size.x, 96),
      position: Vector2(0, 0),
      anchor: Anchor.bottomLeft,
      overridePaint: _paint,
    );
    canvas.restore();
    ground.render(
      canvas,
      size: Vector2(size.x, 96),
      position: Vector2(0, GravitySwitchGame.floorY),
      anchor: Anchor.topLeft,
      overridePaint: _paint,
    );
  }
}
