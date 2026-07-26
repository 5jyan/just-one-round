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
import 'package:just_one_round/features/games/failed_bakery/domain/failed_bakery_rules.dart';

class FailedBakeryGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  FailedBakeryGame({
    required this.onFinished,
    this.gameDuration = const Duration(seconds: 180),
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

  final Duration gameDuration;
  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _CakeTowerComponent _tower;
  late final _BakerReactionComponent _baker;
  late final List<Sprite> _burstSprites;
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _finishDelay = 0.0;
  var _finishStarted = false;
  var _resultSent = false;
  var _missed = false;
  var _endType = GameEndType.gameOver;
  var _score = 0;
  var _perfectCombo = 0;
  var _perfectTotal = 0;
  var _reactionElapsed = 0.0;
  var _lastPublishedSecond = -1;

  @override
  Color backgroundColor() => const Color(0xFF181024);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    final loaded = await images.loadAll([
      'failed_bakery_25d/bakery_background_3q.png',
      'failed_bakery_25d/cake_top_atlas.png',
      'failed_bakery_25d/cake_side_face_atlas.png',
      'failed_bakery_25d/cake_side_plain_atlas.png',
      'failed_bakery_25d/baker_reaction_sheet.png',
      'failed_bakery_25d/crumb_burst_sheet.png',
    ]);
    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );

    _tower = _CakeTowerComponent(
      topAtlas: loaded[1],
      faceSideAtlas: loaded[2],
      plainSideAtlas: loaded[3],
      random: _random,
    );
    await world.add(_tower);

    final bakerSheet = SpriteSheet(image: loaded[4], srcSize: Vector2.all(32));
    _baker = _BakerReactionComponent(
      sprites: _spritesFrom2x2(bakerSheet),
      position: Vector2(18, 538),
    );
    await world.add(_baker);

    _burstSprites = _spritesFrom2x2(
      SpriteSheet(image: loaded[5], srcSize: Vector2.all(16)),
    );
    _tower.spawnNext();

    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _publishHud(force: true);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _updateReaction(dt);

    switch (_phase) {
      case MiniGamePhase.countdown:
        _countdownElapsed += dt;
        final seconds =
            countdownDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_countdownElapsed >= seconds) {
          _phase = MiniGamePhase.playing;
          _publishHud(force: true);
        } else {
          _publishHud();
        }
      case MiniGamePhase.playing:
        _playingElapsed += dt;
        _tower.moveActive(dt);
        if (_playingElapsed >=
            gameDuration.inMicroseconds / Duration.microsecondsPerSecond) {
          _startFinish(endType: GameEndType.timeUp);
        } else {
          _publishHud();
        }
      case MiniGamePhase.finished:
        if (_resultSent) return;
        _finishDelay -= dt;
        if (_finishDelay <= 0) _sendResult();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (_phase != MiniGamePhase.playing || _finishStarted) return;
    final placement = _tower.placeActive();
    if (placement == null) {
      _perfectCombo = 0;
      _setBakerReaction(3, duration: 1);
      _startFinish(endType: GameEndType.gameOver);
      return;
    }

    _score += 1;
    if (placement.isPerfect) {
      _perfectCombo += 1;
      _perfectTotal += 1;
      _setBakerReaction(2);
      final burstPosition = _tower.screenTopCenter(placement.landed, _score);
      world.add(
        _OneShotBurst(
          position: Vector2(burstPosition.dx, burstPosition.dy - 8),
          sprites: _burstSprites,
        ),
      );
      if (_perfectCombo % FailedBakeryRules.perfectsForRecovery == 0) {
        _tower.recoverTop();
      }
    } else {
      _perfectCombo = 0;
      _setBakerReaction(1);
    }

    _tower.setLayerCount(_score);
    if (_score >= FailedBakeryRules.maximumLayers) {
      _startFinish(endType: GameEndType.clear);
      return;
    }
    _tower.spawnNext();
    _publishHud(force: true);
  }

  void _startFinish({required GameEndType endType}) {
    if (_finishStarted) return;
    _finishStarted = true;
    _endType = endType;
    _missed = endType == GameEndType.gameOver;
    _phase = MiniGamePhase.finished;
    if (_missed) _tower.dropActive();
    _finishDelay = _missed ? 0.72 : 0.25;
    _publishHud(force: true);
  }

  void _sendResult() {
    if (_resultSent) return;
    _resultSent = true;
    pauseEngine();
    onFinished(
      GameResult(
        score: _score,
        starsCollected: _perfectTotal,
        collisions: _missed ? 1 : 0,
        duration: Duration(
          milliseconds: (_playingElapsed * 1000).round().clamp(
            1,
            gameDuration.inMilliseconds,
          ),
        ),
        endType: _endType,
      ),
    );
  }

  void _setBakerReaction(int index, {double duration = 0.72}) {
    _baker.setReaction(index);
    _reactionElapsed = duration;
  }

  void _updateReaction(double dt) {
    if (_reactionElapsed <= 0) return;
    _reactionElapsed -= dt;
    if (_reactionElapsed <= 0 && !_missed) _baker.setReaction(0);
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
        elapsedSecond == _lastPublishedSecond &&
        hud.value.score == _score &&
        hud.value.combo == _perfectCombo &&
        hud.value.countdownNumber == countdown) {
      return;
    }
    _lastPublishedSecond = elapsedSecond;
    hud.value = MiniGameHudState(
      phase: _phase,
      score: _score,
      elapsedSeconds: elapsedSecond,
      remainingSeconds: null,
      countdownNumber: countdown,
      combo: _perfectCombo,
      perfects: _perfectTotal,
    );
  }

  @override
  void interrupt() {
    if (_resultSent) return;
    _finishStarted = true;
    _resultSent = true;
    _phase = MiniGamePhase.finished;
    _publishHud(force: true);
    pauseEngine();
  }

  @override
  void disposeController() => hud.dispose();
}

class _CakeTowerComponent extends Component {
  _CakeTowerComponent({
    required this.topAtlas,
    required this.faceSideAtlas,
    required this.plainSideAtlas,
    required this.random,
  }) : super(priority: 5) {
    _layers.add(
      const _CakeLayer(
        footprint: CakeFootprint(
          x: 0,
          z: 0,
          width: FailedBakeryRules.initialSize,
          depth: FailedBakeryRules.initialSize,
        ),
        level: 0,
        skin: 0,
      ),
    );
  }

  static const _centerX = 180.0;
  static const _baseY = 520.0;
  static const _isoX = 0.5;
  static const _isoY = 0.25;
  static const _layerHeight = 16.0;
  static const _travelLimit = 220.0;

  final ui.Image topAtlas;
  final ui.Image faceSideAtlas;
  final ui.Image plainSideAtlas;
  final Random random;
  final List<_CakeLayer> _layers = [];
  final List<_FallingCake> _falling = [];
  _MovingCake? _active;
  var _scrollOffset = 0.0;
  var _targetScrollOffset = 0.0;
  var _lastSkin = 0;

  void moveActive(double dt) {
    final active = _active;
    if (active == null) return;
    final delta = active.direction * active.speed * dt;
    var footprint = active.footprint;
    if (active.axis == CakeMoveAxis.x) {
      var next = footprint.x + delta;
      if (next.abs() >= _travelLimit) {
        next = next.clamp(-_travelLimit, _travelLimit).toDouble();
        active.direction *= -1;
      }
      footprint = footprint.copyWith(x: next);
    } else {
      var next = footprint.z + delta;
      if (next.abs() >= _travelLimit) {
        next = next.clamp(-_travelLimit, _travelLimit).toDouble();
        active.direction *= -1;
      }
      footprint = footprint.copyWith(z: next);
    }
    active.footprint = footprint;
  }

  CakePlacement? placeActive() {
    final active = _active;
    if (active == null) return null;
    final result = FailedBakeryRules.place(
      below: _layers.last.footprint,
      moving: active.footprint,
      axis: active.axis,
    );
    if (result == null) return null;

    final landed = _CakeLayer(
      footprint: result.landed,
      level: active.level,
      skin: active.skin,
    );
    _layers.add(landed);
    if (result.offcut case final offcut?) {
      _falling.add(
        _FallingCake(
          footprint: offcut,
          level: active.level,
          skin: active.skin,
          driftX: (offcut.x - result.landed.x).sign * 22,
          driftZ: (offcut.z - result.landed.z).sign * 22,
        ),
      );
    }
    _active = null;
    return CakePlacement(
      landed: landed.footprint,
      offcut: result.offcut,
      isPerfect: result.isPerfect,
    );
  }

  void recoverTop() {
    final top = _layers.removeLast();
    _layers.add(
      _CakeLayer(
        footprint: FailedBakeryRules.recover(top.footprint),
        level: top.level,
        skin: top.skin,
      ),
    );
  }

  void setLayerCount(int layers) {
    _targetScrollOffset = max(0, layers - 6) * _layerHeight;
  }

  void spawnNext() {
    final level = _layers.length;
    final below = _layers.last.footprint;
    final axis = FailedBakeryRules.axisForLayer(level);
    final startsNegative = level % 4 < 2;
    final start = startsNegative ? -_travelLimit : _travelLimit;
    final footprint = axis == CakeMoveAxis.x
        ? below.copyWith(x: start)
        : below.copyWith(z: start);
    final skinOffset = 1 + random.nextInt(5);
    _lastSkin = (_lastSkin + skinOffset) % 6;
    _active = _MovingCake(
      footprint: footprint,
      level: level,
      skin: _lastSkin,
      axis: axis,
      speed: FailedBakeryRules.speedForLayer(level),
      direction: startsNegative ? 1 : -1,
    );
  }

  void dropActive() {
    final active = _active;
    if (active == null) return;
    _falling.add(
      _FallingCake(
        footprint: active.footprint,
        level: active.level,
        skin: active.skin,
        driftX: active.axis == CakeMoveAxis.x ? active.direction * 28 : 0,
        driftZ: active.axis == CakeMoveAxis.z ? active.direction * 28 : 0,
      ),
    );
    _active = null;
  }

  Offset screenTopCenter(CakeFootprint footprint, int level) =>
      _project(footprint.x, footprint.z, level, extraDrop: 0);

  @override
  void update(double dt) {
    super.update(dt);
    final scrollDelta = _targetScrollOffset - _scrollOffset;
    _scrollOffset += scrollDelta * min(1, dt * 8);

    for (final cake in List<_FallingCake>.of(_falling)) {
      cake.elapsed += dt;
      cake.velocity += 620 * dt;
      cake.drop += cake.velocity * dt;
      cake.footprint = cake.footprint.copyWith(
        x: cake.footprint.x + cake.driftX * dt,
        z: cake.footprint.z + cake.driftZ * dt,
      );
      if (cake.elapsed >= 1.25) _falling.remove(cake);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (final layer in _layers) {
      _drawCake(canvas, layer.footprint, layer.level, layer.skin);
    }
    if (_active case final active?) {
      _drawCake(canvas, active.footprint, active.level, active.skin);
    }
    for (final cake in _falling) {
      _drawCake(
        canvas,
        cake.footprint,
        cake.level,
        cake.skin,
        extraDrop: cake.drop,
      );
    }
  }

  void _drawCake(
    Canvas canvas,
    CakeFootprint footprint,
    int level,
    int skin, {
    double extraDrop = 0,
  }) {
    final backLeft = _project(
      footprint.left,
      footprint.back,
      level,
      extraDrop: extraDrop,
    );
    final backRight = _project(
      footprint.right,
      footprint.back,
      level,
      extraDrop: extraDrop,
    );
    final frontRight = _project(
      footprint.right,
      footprint.front,
      level,
      extraDrop: extraDrop,
    );
    final frontLeft = _project(
      footprint.left,
      footprint.front,
      level,
      extraDrop: extraDrop,
    );
    const down = Offset(0, _layerHeight);

    final sideRow = skin ~/ 2;
    final sideColumn = skin % 2;
    final faceCell = Rect.fromLTWH(sideColumn * 40.0, sideRow * 8.0, 40, 8);
    final faceCropWidth =
        40 *
        (footprint.width / FailedBakeryRules.initialSize)
            .clamp(0.02, 1)
            .toDouble();
    final faceSource = Rect.fromCenter(
      center: faceCell.center,
      width: faceCropWidth,
      height: 8,
    );
    _drawImageParallelogram(
      canvas,
      image: faceSideAtlas,
      source: faceSource,
      origin: frontLeft,
      horizontal: frontRight - frontLeft,
      vertical: down,
    );

    final plainCropWidth =
        40 *
        (footprint.depth / FailedBakeryRules.initialSize)
            .clamp(0.02, 1)
            .toDouble();
    final plainSource = Rect.fromCenter(
      center: faceCell.center,
      width: plainCropWidth,
      height: 8,
    );
    _drawImageParallelogram(
      canvas,
      image: plainSideAtlas,
      source: plainSource,
      origin: frontRight,
      horizontal: backRight - frontRight,
      vertical: down,
    );

    final topRow = skin ~/ 3;
    final topColumn = skin % 3;
    final topCell = Rect.fromLTWH(topColumn * 40.0, topRow * 40.0, 40, 40);
    final topSource = Rect.fromCenter(
      center: topCell.center,
      width:
          40 *
          (footprint.width / FailedBakeryRules.initialSize)
              .clamp(0.02, 1)
              .toDouble(),
      height:
          40 *
          (footprint.depth / FailedBakeryRules.initialSize)
              .clamp(0.02, 1)
              .toDouble(),
    );
    _drawImageParallelogram(
      canvas,
      image: topAtlas,
      source: topSource,
      origin: backLeft,
      horizontal: backRight - backLeft,
      vertical: frontLeft - backLeft,
    );
  }

  Offset _project(double x, double z, int level, {required double extraDrop}) =>
      Offset(
        _centerX + (x - z) * _isoX,
        _baseY +
            _scrollOffset +
            (x + z) * _isoY -
            level * _layerHeight +
            extraDrop,
      );

  void _drawImageParallelogram(
    Canvas canvas, {
    required ui.Image image,
    required Rect source,
    required Offset origin,
    required Offset horizontal,
    required Offset vertical,
  }) {
    if (source.width <= 0 || source.height <= 0) return;
    final matrix = Float64List.fromList([
      horizontal.dx / source.width,
      horizontal.dy / source.width,
      0,
      0,
      vertical.dx / source.height,
      vertical.dy / source.height,
      0,
      0,
      0,
      0,
      1,
      0,
      origin.dx,
      origin.dy,
      0,
      1,
    ]);
    canvas
      ..save()
      ..transform(matrix)
      ..drawImageRect(
        image,
        source,
        Rect.fromLTWH(0, 0, source.width, source.height),
        _pixelPaint,
      )
      ..restore();
  }
}

final Paint _pixelPaint = Paint()
  ..filterQuality = FilterQuality.none
  ..isAntiAlias = false;

class _CakeLayer {
  const _CakeLayer({
    required this.footprint,
    required this.level,
    required this.skin,
  });

  final CakeFootprint footprint;
  final int level;
  final int skin;
}

class _MovingCake {
  _MovingCake({
    required this.footprint,
    required this.level,
    required this.skin,
    required this.axis,
    required this.speed,
    required this.direction,
  });

  CakeFootprint footprint;
  final int level;
  final int skin;
  final CakeMoveAxis axis;
  final double speed;
  double direction;
}

class _FallingCake {
  _FallingCake({
    required this.footprint,
    required this.level,
    required this.skin,
    required this.driftX,
    required this.driftZ,
  });

  CakeFootprint footprint;
  final int level;
  final int skin;
  final double driftX;
  final double driftZ;
  var elapsed = 0.0;
  var velocity = 20.0;
  var drop = 0.0;
}

class _BakerReactionComponent extends PositionComponent {
  _BakerReactionComponent({required this.sprites, required super.position})
    : super(size: Vector2.all(64), anchor: Anchor.bottomLeft, priority: 30);

  final List<Sprite> sprites;
  var _index = 0;

  void setReaction(int index) =>
      _index = index.clamp(0, sprites.length - 1).toInt();

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    sprites[_index].render(canvas, size: size, overridePaint: _pixelPaint);
  }
}

class _OneShotBurst extends PositionComponent {
  _OneShotBurst({required super.position, required this.sprites})
    : super(size: Vector2.all(32), anchor: Anchor.center, priority: 40);

  final List<Sprite> sprites;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= sprites.length * 0.08) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final index = min(sprites.length - 1, (_elapsed / 0.08).floor());
    sprites[index].render(canvas, size: size, overridePaint: _pixelPaint);
  }
}

List<Sprite> _spritesFrom2x2(SpriteSheet sheet) => [
  sheet.getSprite(0, 0),
  sheet.getSprite(0, 1),
  sheet.getSprite(1, 0),
  sheet.getSprite(1, 1),
];
