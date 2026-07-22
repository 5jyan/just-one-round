import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
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
  static const playerX = 92.0;
  static const playerSize = 44.0;
  static const initialFloorTop = 500.0;
  static const initialCeilingBottom = 140.0;

  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _PrismRunner _player;
  final List<_MazeColumn> _columns = [];
  final List<GravitySurface?> _patternQueue = [];
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _score = 0;
  var _distance = 0;
  var _lastDisplayedSecond = -1;
  var _nextSequence = 0;
  var _safeColumnsRemaining = 8;
  var _lastHazardSurface = GravitySurface.ceiling;
  var _floorTop = initialFloorTop;
  var _ceilingBottom = initialCeilingBottom;
  var _hasFinished = false;

  @override
  Color backgroundColor() => const Color(0xFF020617);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    final loaded = await images.loadAll([
      'gravity_switch_v2/space_background.png',
      'gravity_switch_v2/player_sheet.png',
    ]);
    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );

    final playerSheet = SpriteSheet(image: loaded[1], srcSize: Vector2.all(96));
    _player = _PrismRunner(
      position: Vector2(playerX, initialFloorTop - playerSize / 2),
      sprites: _spritesFrom2x2(playerSheet),
    );

    for (
      var x = -GravitySwitchRules.columnWidth;
      x < logicalSize.x + GravitySwitchRules.columnWidth * 3;
      x += GravitySwitchRules.columnWidth
    ) {
      _appendColumn(x, forceSafe: true);
    }
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
    _score = (_playingElapsed * 1000).floor();
    final speed = GravitySwitchRules.scrollSpeed(_playingElapsed);

    for (final column in List<_MazeColumn>.of(_columns)) {
      column.position.x -= speed * dt;
      if (!column.wasPassed &&
          column.position.x + GravitySwitchRules.columnWidth < playerX) {
        column.wasPassed = true;
        _distance += 1;
      }
      if (column.position.x + GravitySwitchRules.columnWidth < 0) {
        _columns.remove(column);
        column.removeFromParent();
      }
    }

    while (_columns.isEmpty ||
        _columns.last.position.x <
            logicalSize.x + GravitySwitchRules.columnWidth * 2) {
      final x = _columns.isEmpty
          ? logicalSize.x
          : _columns.last.position.x + GravitySwitchRules.columnWidth;
      _appendColumn(x);
    }

    final support = _columnAtPlayer();
    if (support != null) {
      _player.updateSurface(dt, support);
    }
    for (final column in _columns) {
      if (column.collidesWith(_player)) {
        _finish();
        return;
      }
    }
    _publishHud();
  }

  _MazeColumn? _columnAtPlayer() {
    for (final column in _columns) {
      if (playerX >= column.position.x &&
          playerX < column.position.x + GravitySwitchRules.columnWidth) {
        return column;
      }
    }
    return null;
  }

  void _appendColumn(double x, {bool forceSafe = false}) {
    final hazard = forceSafe ? null : _nextHazard();
    if (hazard == null) {
      _floorTop = (_floorTop + (_random.nextInt(3) - 1) * 8).clamp(
        474.0,
        518.0,
      );
      _ceilingBottom = (_ceilingBottom + (_random.nextInt(3) - 1) * 8).clamp(
        118.0,
        162.0,
      );
    }

    final height = GravitySwitchRules.hazardHeight(_playingElapsed);
    final floorTop = hazard == GravitySurface.floor
        ? min(_floorTop, initialFloorTop - height)
        : _floorTop;
    final ceilingBottom = hazard == GravitySurface.ceiling
        ? max(_ceilingBottom, initialCeilingBottom + height)
        : _ceilingBottom;
    final column = _MazeColumn(
      sequence: _nextSequence++,
      floorTop: floorTop,
      ceilingBottom: ceilingBottom,
      position: Vector2(x, 0),
      palette: _paletteForTime(_playingElapsed),
    );
    _columns.add(column);
    world.add(column);
  }

  GravitySurface? _nextHazard() {
    if (_patternQueue.isNotEmpty) return _patternQueue.removeAt(0);
    if (_safeColumnsRemaining > 0) {
      _safeColumnsRemaining -= 1;
      return null;
    }

    final alternate =
        _random.nextDouble() <
        GravitySwitchRules.alternatingPatternChance(_playingElapsed);
    final surface = alternate
        ? _opposite(_lastHazardSurface)
        : (_random.nextBool() ? GravitySurface.floor : GravitySurface.ceiling);
    _lastHazardSurface = surface;
    final hazardWidth = _playingElapsed >= 35 && _random.nextDouble() < 0.32
        ? 2
        : 1;
    for (var i = 1; i < hazardWidth; i++) {
      _patternQueue.add(surface);
    }
    _safeColumnsRemaining = GravitySwitchRules.safeColumnCount(_playingElapsed);
    return surface;
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
  _PrismRunner({required super.position, required this.sprites})
    : super(
        size: Vector2.all(GravitySwitchGame.playerSize),
        anchor: Anchor.center,
        priority: 20,
      );

  final List<Sprite> sprites;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.high;
  GravitySurface surface = GravitySurface.floor;
  GravitySurface? _targetSurface;
  var _switchElapsed = 0.0;
  var _animationElapsed = 0.0;
  var _switchStartY = 0.0;

  Rect get hitbox => Rect.fromCenter(
    center: Offset(position.x, position.y),
    width: 30,
    height: 30,
  );

  void switchGravity() {
    if (_targetSurface != null) return;
    _targetSurface = _opposite(surface);
    _switchElapsed = 0;
    _switchStartY = position.y;
  }

  void updateSurface(double dt, _MazeColumn column) {
    _animationElapsed += dt;
    final target = _targetSurface;
    if (target == null) {
      final desiredY = surface == GravitySurface.floor
          ? column.floorTop - size.y / 2
          : column.ceilingBottom + size.y / 2;
      if ((desiredY - position.y).abs() <= 26) {
        position.y = desiredY;
      }
      return;
    }

    _switchElapsed += dt;
    final progress = (_switchElapsed / GravitySwitchRules.switchDuration).clamp(
      0.0,
      1.0,
    );
    final eased = Curves.easeIn.transform(progress);
    final targetY = target == GravitySurface.floor
        ? column.floorTop - size.y / 2
        : column.ceilingBottom + size.y / 2;
    position.y = _switchStartY + ((targetY - _switchStartY) * eased);
    angle = (target == GravitySurface.floor ? 1 : -1) * pi * progress;
    if (progress >= 1) {
      surface = target;
      _targetSurface = null;
      position.y = targetY;
      angle = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    if (sprites.isEmpty) return;
    final index = (_animationElapsed / 0.09).floor() % sprites.length;
    sprites[index].render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _MazeColumn extends PositionComponent {
  _MazeColumn({
    required this.sequence,
    required this.floorTop,
    required this.ceilingBottom,
    required this.palette,
    required super.position,
  }) : super(
         size: Vector2(
           GravitySwitchRules.columnWidth,
           GravitySwitchGame.logicalSize.y,
         ),
         priority: 5,
       );

  final int sequence;
  final double floorTop;
  final double ceilingBottom;
  final _PrismPalette palette;
  bool wasPassed = false;

  bool collidesWith(_PrismRunner player) {
    final x = position.x;
    final width = GravitySwitchRules.columnWidth;
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
    final colors = palette.colors[sequence % palette.colors.length];
    _drawFloorPrism(canvas, floorTop, colors);
    _drawCeilingPrism(canvas, ceilingBottom, colors);
  }

  void _drawFloorPrism(Canvas canvas, double top, _PrismColor colors) {
    const depth = 7.0;
    final width = size.x;
    canvas.drawRect(
      Rect.fromLTWH(0, top, width, size.y - top),
      Paint()..color = colors.face,
    );
    canvas.drawRect(
      Rect.fromLTWH(width - depth, top, depth, size.y - top),
      Paint()..color = colors.side,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, top)
        ..lineTo(width - depth, top)
        ..lineTo(width, top - depth)
        ..lineTo(depth, top - depth)
        ..close(),
      Paint()..color = colors.cap,
    );
    canvas.drawLine(
      Offset(0, top),
      Offset(0, size.y),
      Paint()
        ..color = const Color(0x55020817)
        ..strokeWidth = 1.4,
    );
  }

  void _drawCeilingPrism(Canvas canvas, double bottom, _PrismColor colors) {
    const depth = 7.0;
    final width = size.x;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, bottom),
      Paint()..color = colors.face,
    );
    canvas.drawRect(
      Rect.fromLTWH(width - depth, 0, depth, bottom),
      Paint()..color = colors.side,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, bottom)
        ..lineTo(width - depth, bottom)
        ..lineTo(width, bottom + depth)
        ..lineTo(depth, bottom + depth)
        ..close(),
      Paint()..color = colors.cap,
    );
    canvas.drawLine(
      Offset(0, 0),
      Offset(0, bottom),
      Paint()
        ..color = const Color(0x55020817)
        ..strokeWidth = 1.4,
    );
  }
}

class _PrismColor {
  const _PrismColor(this.face, this.side, this.cap);

  final Color face;
  final Color side;
  final Color cap;
}

class _PrismPalette {
  const _PrismPalette(this.colors);

  final List<_PrismColor> colors;
}

const _palettes = [
  _PrismPalette([
    _PrismColor(Color(0xFF0FC9CE), Color(0xFF08737D), Color(0xFF57FFF2)),
    _PrismColor(Color(0xFFFF6B4A), Color(0xFF9E2F3D), Color(0xFFFFA06F)),
    _PrismColor(Color(0xFF8B5CF6), Color(0xFF4C2B9B), Color(0xFFC4A1FF)),
  ]),
  _PrismPalette([
    _PrismColor(Color(0xFFFFC857), Color(0xFFB0602F), Color(0xFFFFE58F)),
    _PrismColor(Color(0xFF4ADE80), Color(0xFF18794E), Color(0xFF9DFFB8)),
    _PrismColor(Color(0xFF38BDF8), Color(0xFF155E9A), Color(0xFF9FE8FF)),
  ]),
  _PrismPalette([
    _PrismColor(Color(0xFFF43F8C), Color(0xFF8F245B), Color(0xFFFF8EC1)),
    _PrismColor(Color(0xFF22D3EE), Color(0xFF0B7189), Color(0xFF8AF5FF)),
    _PrismColor(Color(0xFFA3E635), Color(0xFF4D7C0F), Color(0xFFD7FF87)),
  ]),
];

_PrismPalette _paletteForTime(double seconds) =>
    _palettes[(seconds / 18).floor() % _palettes.length];
