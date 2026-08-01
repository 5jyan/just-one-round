import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/midnight_snake/domain/midnight_snake_rules.dart';
import 'package:just_one_round/features/games/midnight_snake/presentation/midnight_snake_path.dart';

class MidnightSnakeGame extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  MidnightSnakeGame({
    required this.onFinished,
    this.gameDuration = MidnightSnakeRules.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    Random? random,
  }) : _random =
           random ??
           Random(MidnightSnakeRules.dailySeed(DateTime.now().toUtc())),
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

  late final _MidnightSnakeBoard _board;
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _moveAccumulator = 0.0;
  var _lastPublishedSecond = -1;
  var _lastPublishedScore = -1;
  var _assetsReady = false;
  var _isTerminal = false;
  var _resultEmitted = false;
  var _finishDelay = 0.0;
  SnakeFinishReason? _finishReason;
  Vector2? _dragStart;
  Vector2? _dragCurrent;

  @override
  Color backgroundColor() => const Color(0xFF03121C);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    final loaded = await images.loadAll([
      'midnight_snake/apartment_background.png',
      'midnight_snake/snake_head_slither_atlas.png',
      'midnight_snake/snake_head_eat_atlas.png',
      'midnight_snake/midnight_food_atlas.png',
      'midnight_snake/crumb_burst_sheet.png',
      'midnight_snake/snake_scale_pattern.png',
      'midnight_snake/golden_sausage_sheet.png',
      'midnight_snake/mouse_walk_atlas.png',
    ]);
    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );
    final goldenSpawnAt = MidnightSnakeRules.spawnSecondInRange(
      random: _random,
      startInclusive: MidnightSnakeRules.goldenSausageSpawnStartSeconds.toInt(),
      endInclusive: MidnightSnakeRules.goldenSausageSpawnEndSeconds.toInt(),
    );
    final mouseSpawnAt = MidnightSnakeRules.spawnSecondInRange(
      random: _random,
      startInclusive: MidnightSnakeRules.mouseSpawnStartSeconds.toInt(),
      endInclusive: MidnightSnakeRules.mouseSpawnEndSeconds.toInt(),
    );
    _board = _MidnightSnakeBoard(
      state: MidnightSnakeState.initial(
        goldenSpawnAtSeconds: goldenSpawnAt,
        mouseSpawnAtSeconds: mouseSpawnAt,
      ),
      headSlither: _spritesFromGrid(loaded[1], rows: 4, columns: 4),
      headEat: _spritesFromGrid(loaded[2], rows: 4, columns: 4),
      foods: _spritesFromGrid(loaded[3], rows: 2, columns: 6),
      crumbBurst: _spritesFromGrid(loaded[4], rows: 2, columns: 2),
      bodyPattern: loaded[5],
      goldenSausage: _spritesFromGrid(loaded[6], rows: 2, columns: 1),
      mouseWalk: _spritesFromGrid(loaded[7], rows: 4, columns: 2),
    );
    await world.add(_board);
    _assetsReady = true;
    if (!_isTerminal && countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _board.isPlaying = true;
      _publishHud(force: true);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isTerminal) {
      if (_resultEmitted || _finishReason == null) return;
      _finishDelay -= dt;
      if (_finishDelay <= 0) _emitResult();
      return;
    }

    switch (_phase) {
      case MiniGamePhase.countdown:
        _countdownElapsed += dt;
        final seconds =
            countdownDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_countdownElapsed >= seconds && _assetsReady) {
          _phase = MiniGamePhase.playing;
          _board.isPlaying = true;
          _publishHud(force: true);
        } else {
          _publishHud();
        }
      case MiniGamePhase.playing:
        _playingElapsed += dt;
        final maximumSeconds =
            gameDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_playingElapsed >= maximumSeconds) {
          _playingElapsed = maximumSeconds;
          _board.state.finishForTimeout();
          _beginFinish(SnakeFinishReason.timeout);
          return;
        }
        _board.elapsedSeconds = _playingElapsed;
        _moveAccumulator += dt;
        var processedTicks = 0;
        while (processedTicks < 12) {
          final timeline = max(0.0, _playingElapsed - _moveAccumulator);
          final interval = MidnightSnakeRules.moveIntervalAt(timeline);
          if (_moveAccumulator < interval) break;
          _moveAccumulator -= interval;
          processedTicks++;
          final result = _board.advance(_random, transitionDuration: interval);
          if (result.ateAnyPickup) {
            unawaited(HapticFeedback.mediumImpact());
          }
          if (result.finishReason case final reason?) {
            unawaited(HapticFeedback.heavyImpact());
            _beginFinish(reason);
            return;
          }
        }
        _board.updateBonusEvents(_random);
        _publishHud();
      case MiniGamePhase.finished:
        return;
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_phase != MiniGamePhase.playing || _isTerminal) return;
    final point = camera.globalToLocal(event.canvasPosition);
    if (!_board.containsLogicalPoint(point)) return;
    _dragStart = point;
    _dragCurrent = point;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_dragStart == null || _phase != MiniGamePhase.playing) return;
    _dragCurrent = camera.globalToLocal(event.canvasEndPosition);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final start = _dragStart;
    final end = _dragCurrent;
    _dragStart = null;
    _dragCurrent = null;
    if (start != null && end != null) queueSwipeForTesting(end - start);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragStart = null;
    _dragCurrent = null;
  }

  @visibleForTesting
  bool queueSwipeForTesting(Vector2 delta) {
    if (_phase != MiniGamePhase.playing || _isTerminal || !_assetsReady) {
      return false;
    }
    final direction = MidnightSnakeRules.directionForSwipe(
      deltaX: delta.x,
      deltaY: delta.y,
    );
    if (direction == null) return false;
    return _queueDirection(direction);
  }

  bool _queueDirection(SnakeDirection direction) {
    final accepted = _board.state.queueDirection(direction);
    if (accepted) unawaited(HapticFeedback.selectionClick());
    return accepted;
  }

  void _beginFinish(SnakeFinishReason reason) {
    if (_isTerminal) return;
    _isTerminal = true;
    _finishReason = reason;
    _phase = MiniGamePhase.finished;
    _board
      ..isPlaying = false
      ..showFinish(reason);
    _finishDelay = switch (reason) {
      SnakeFinishReason.wall || SnakeFinishReason.self => 1.25,
      SnakeFinishReason.timeout || SnakeFinishReason.boardComplete => 0.25,
    };
    _publishHud(force: true);
  }

  void _emitResult() {
    if (_resultEmitted || _finishReason == null) return;
    _resultEmitted = true;
    pauseEngine();
    onFinished(
      GameResult(
        score: _board.state.score,
        starsCollected: 0,
        collisions:
            _finishReason == SnakeFinishReason.wall ||
                _finishReason == SnakeFinishReason.self
            ? 1
            : 0,
        duration: Duration(
          milliseconds: (_playingElapsed * 1000).round().clamp(
            1,
            gameDuration.inMilliseconds,
          ),
        ),
        endType: switch (_finishReason!) {
          SnakeFinishReason.wall ||
          SnakeFinishReason.self => GameEndType.gameOver,
          SnakeFinishReason.timeout => GameEndType.timeUp,
          SnakeFinishReason.boardComplete => GameEndType.clear,
        },
      ),
    );
  }

  void _publishHud({bool force = false}) {
    final elapsedSecond = _playingElapsed.floor();
    final countdown = max(
      0,
      (countdownDuration.inMicroseconds / Duration.microsecondsPerSecond -
              _countdownElapsed)
          .ceil(),
    );
    final score = _assetsReady ? _board.state.score : 0;
    if (!force &&
        elapsedSecond == _lastPublishedSecond &&
        score == _lastPublishedScore &&
        hud.value.countdownNumber == countdown) {
      return;
    }
    _lastPublishedSecond = elapsedSecond;
    _lastPublishedScore = score;
    hud.value = MiniGameHudState(
      phase: _phase,
      score: score,
      elapsedSeconds: elapsedSecond,
      remainingSeconds: max(0, gameDuration.inSeconds - elapsedSecond),
      countdownNumber: countdown,
      distance: _assetsReady ? _board.state.body.length : 0,
    );
  }

  @visibleForTesting
  MidnightSnakeState get stateForTesting => _board.state;

  @visibleForTesting
  Rect get boardRectForTesting => _MidnightSnakeBoard.boardRect;

  @visibleForTesting
  double get movementProgressForTesting => _board.movementProgress;

  @visibleForTesting
  String? get scorePopupForTesting => _board.scorePopupText;

  @visibleForTesting
  double get deathProgressForTesting => _board.deathProgress;

  @visibleForTesting
  SnakeStepResult advanceForTesting() {
    final result = _board.advance(
      _random,
      transitionDuration: MidnightSnakeRules.moveIntervalAt(_playingElapsed),
    );
    if (result.finishReason case final reason?) _beginFinish(reason);
    return result;
  }

  @visibleForTesting
  void finishForTesting(SnakeFinishReason reason) => _beginFinish(reason);

  @override
  void interrupt() {
    if (_isTerminal) return;
    _isTerminal = true;
    _phase = MiniGamePhase.finished;
    if (_assetsReady) _board.isPlaying = false;
    _publishHud(force: true);
    pauseEngine();
  }

  @override
  void disposeController() => hud.dispose();

  static List<Sprite> _spritesFromGrid(
    ui.Image image, {
    required int rows,
    required int columns,
  }) {
    final sheet = SpriteSheet(image: image, srcSize: Vector2.all(32));
    return [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          sheet.getSprite(row, column),
    ];
  }
}

class _MidnightSnakeBoard extends PositionComponent {
  _MidnightSnakeBoard({
    required this.state,
    required this.headSlither,
    required this.headEat,
    required this.foods,
    required this.crumbBurst,
    required this.goldenSausage,
    required this.mouseWalk,
    required ui.Image bodyPattern,
  }) : _bodyPatternPaint = Paint()
         ..shader = ui.ImageShader(
           bodyPattern,
           ui.TileMode.repeated,
           ui.TileMode.repeated,
           Float64List.fromList([
             1,
             0,
             0,
             0,
             0,
             1,
             0,
             0,
             0,
             0,
             1,
             0,
             0,
             0,
             0,
             1,
           ]),
         )
         ..strokeWidth = 18
         ..strokeCap = StrokeCap.round
         ..strokeJoin = StrokeJoin.round
         ..style = PaintingStyle.stroke
         ..isAntiAlias = false
         ..filterQuality = FilterQuality.none,
       super(size: MidnightSnakeGame.logicalSize.clone());

  static const cellSize = 32.0;
  static const boardLeft = 36.0;
  static const boardTop = 112.0;
  static const boardRect = Rect.fromLTWH(
    boardLeft,
    boardTop,
    cellSize * MidnightSnakeRules.columnCount,
    cellSize * MidnightSnakeRules.rowCount,
  );

  final MidnightSnakeState state;
  final List<Sprite> headSlither;
  final List<Sprite> headEat;
  final List<Sprite> foods;
  final List<Sprite> crumbBurst;
  final List<Sprite> goldenSausage;
  final List<Sprite> mouseWalk;
  final Paint _bodyPaint = Paint()
    ..color = const Color(0xFFDC9819)
    ..strokeWidth = 18
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = false;
  final Paint _bodyPatternPaint;
  final Paint _pixelPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;
  final Paint _overlayPaint = Paint()..isAntiAlias = false;

  bool isPlaying = false;
  double elapsedSeconds = 0;
  double _eatElapsed = 1;
  double _crumbElapsed = 1;
  double _scorePopupElapsed = 1;
  int _scorePopupValue = 0;
  SnakeCell? _scorePopupCell;
  double _movementElapsed = 1;
  double _movementDuration = 0.2;
  double _deathElapsed = 1;
  List<SnakeCell> _previousBody = const [];
  SnakeCell? _lastEatenCell;
  SnakeFinishReason? _finishReason;

  static const _scorePopupDuration = 0.8;
  static const _deathDuration = 1.05;

  bool containsLogicalPoint(Vector2 point) =>
      boardRect.contains(Offset(point.x, point.y));

  double get movementProgress {
    if (_previousBody.isEmpty || _movementDuration <= 0) return 1;
    return (_movementElapsed / _movementDuration).clamp(0, 1);
  }

  SnakeStepResult advance(Random random, {required double transitionDuration}) {
    if (!isPlaying) {
      return const SnakeStepResult(moved: false, ateFood: false);
    }
    final previousBody = List<SnakeCell>.of(state.body);
    final result = state.step(random);
    if (result.moved) {
      _previousBody = previousBody;
      _movementElapsed = 0;
      _movementDuration = transitionDuration;
    }
    if (result.ateAnyPickup) {
      _lastEatenCell = result.pickupCell;
      _eatElapsed = 0;
      _crumbElapsed = 0;
      _scorePopupCell = result.pickupCell;
      _scorePopupValue = result.scoreGained;
      _scorePopupElapsed = 0;
    }
    return result;
  }

  void updateBonusEvents(Random random) {
    state.updateBonusEvents(elapsedSeconds: elapsedSeconds, random: random);
  }

  void showFinish(SnakeFinishReason reason) {
    _finishReason = reason;
    if (reason == SnakeFinishReason.wall || reason == SnakeFinishReason.self) {
      _deathElapsed = 0;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _eatElapsed += dt;
    _crumbElapsed += dt;
    _scorePopupElapsed += dt;
    _movementElapsed += dt;
    _deathElapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderFood(canvas);
    _renderBonusPickups(canvas);
    _renderSnake(canvas);
    _renderCrumbs(canvas);
    _renderScorePopup(canvas);
    _renderFinishFeedback(canvas);
  }

  void _renderBonusPickups(Canvas canvas) {
    final golden = state.goldenSausage;
    if (golden != null) {
      final frame = ((elapsedSeconds / 0.18).floor()) % 2;
      goldenSausage[frame].render(
        canvas,
        position: _cellPosition(golden),
        size: Vector2.all(cellSize),
        overridePaint: _pixelPaint,
      );
    }

    final activeMouse = state.mouse;
    if (activeMouse != null) {
      final frame = ((elapsedSeconds / 0.5).floor()) % 2;
      mouseWalk[_directionRow(state.mouseDirection) * 2 + frame].render(
        canvas,
        position: _cellPosition(activeMouse),
        size: Vector2.all(cellSize),
        overridePaint: _pixelPaint,
      );
    }
  }

  void _renderFood(Canvas canvas) {
    final food = state.food;
    if (food == null) return;
    final animationRow = ((elapsedSeconds / 0.18).floor()) % 2;
    foods[animationRow * 6 + state.foodTypeIndex].render(
      canvas,
      position: _cellPosition(food),
      size: Vector2.all(cellSize),
      overridePaint: _pixelPaint,
    );
  }

  void _renderSnake(Canvas canvas) {
    final body = state.body;
    if (body.isEmpty) return;
    final pathPoints = buildMidnightSnakePath(
      body: body,
      previousBody: _previousBody,
      progress: movementProgress,
    );
    final path = Path();
    for (var index = 0; index < pathPoints.length; index++) {
      final center = _pathPointCenter(pathPoints[index]);
      if (index == 0) {
        path.moveTo(center.dx, center.dy);
      } else {
        path.lineTo(center.dx, center.dy);
      }
    }
    // The head overlaps this continuous path at its center, while the tail is
    // the path's own round cap. The transparent pattern shader is clipped by
    // the same stroke, so it cannot reopen seams between body sections.
    final dying = _hasCollisionFinish;
    final deathAmount = deathProgress;
    _bodyPaint.color = Color.lerp(
      const Color(0xFFDC9819),
      const Color(0xFF79644A),
      deathAmount,
    )!;
    _bodyPatternPaint.colorFilter = dying
        ? ColorFilter.mode(
            Color.lerp(
              const Color(0xFFFFFFFF),
              const Color(0xFF7D786F),
              deathAmount,
            )!,
            BlendMode.modulate,
          )
        : null;
    canvas.drawPath(path, _bodyPaint);
    canvas.drawPath(path, _bodyPatternPaint);

    final walkFrame = ((elapsedSeconds / 0.11).floor()) % 4;
    final heads = _eatElapsed < 0.28 ? headEat : headSlither;
    final frame = _eatElapsed < 0.28
        ? min(3, (_eatElapsed / 0.07).floor())
        : walkFrame;
    final headCenter = _pathPointCenter(pathPoints.first);
    final headSprite = heads[_directionRow(state.direction) * 4 + frame];
    if (dying) {
      final shake =
          sin(_deathElapsed * 48) * 2.5 * (1 - deathAmount).clamp(0, 1);
      final wobble =
          sin(_deathElapsed * 38) * 0.1 * (1 - deathAmount).clamp(0, 1);
      final deadHeadPaint = Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none
        ..colorFilter = ColorFilter.mode(
          Color.lerp(
            const Color(0xFFFFFFFF),
            const Color(0xFF9A6F65),
            deathAmount,
          )!,
          BlendMode.modulate,
        );
      canvas.save();
      canvas.translate(headCenter.dx + shake, headCenter.dy + deathAmount * 4);
      canvas.rotate(wobble + deathAmount * 0.32);
      canvas.scale(1 + deathAmount * 0.08, 1 - deathAmount * 0.32);
      headSprite.render(
        canvas,
        position: Vector2.all(-cellSize / 2),
        size: Vector2.all(cellSize),
        overridePaint: deadHeadPaint,
      );
      canvas.restore();
    } else {
      headSprite.render(
        canvas,
        position: Vector2(
          headCenter.dx - cellSize / 2,
          headCenter.dy - cellSize / 2,
        ),
        size: Vector2.all(cellSize),
        overridePaint: _pixelPaint,
      );
    }
  }

  void _renderCrumbs(Canvas canvas) {
    final cell = _lastEatenCell;
    if (cell == null || _crumbElapsed >= 0.32) return;
    final frame = min(3, (_crumbElapsed / 0.08).floor());
    crumbBurst[frame].render(
      canvas,
      position: _cellPosition(cell),
      size: Vector2.all(cellSize),
      overridePaint: _pixelPaint,
    );
  }

  void _renderScorePopup(Canvas canvas) {
    final cell = _scorePopupCell;
    if (cell == null ||
        _scorePopupValue <= 0 ||
        _scorePopupElapsed >= _scorePopupDuration) {
      return;
    }
    final progress = (_scorePopupElapsed / _scorePopupDuration).clamp(0.0, 1.0);
    final opacity = progress < 0.58
        ? 1.0
        : (1 - (progress - 0.58) / 0.42).clamp(0.0, 1.0);
    final popupColor = switch (_scorePopupValue) {
      3 => const Color(0xFFFFD84A),
      2 => const Color(0xFFD7EFF4),
      _ => const Color(0xFFFFE1A3),
    };
    final painter = TextPainter(
      text: TextSpan(
        text: '+$_scorePopupValue',
        style: TextStyle(
          color: popupColor.withValues(alpha: opacity),
          fontFamily: 'Galmuri',
          fontSize: 18,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: const Color(0xFF020A10).withValues(alpha: opacity),
              offset: const Offset(2, 2),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = _cellRect(cell).center;
    final scale = 0.82 + min(1.0, progress / 0.18) * 0.18;
    canvas.save();
    canvas.translate(
      center.dx,
      center.dy - 23 - Curves.easeOut.transform(progress) * 15,
    );
    canvas.scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  void _renderFinishFeedback(Canvas canvas) {
    final reason = _finishReason;
    if (reason == null) return;
    if (reason == SnakeFinishReason.timeout ||
        reason == SnakeFinishReason.boardComplete) {
      _overlayPaint.color = const Color(0x554ED8C7);
      canvas.drawRect(boardRect, _overlayPaint);
    }
  }

  bool get _hasCollisionFinish =>
      (_finishReason == SnakeFinishReason.wall ||
      _finishReason == SnakeFinishReason.self);

  double get deathProgress => _hasCollisionFinish
      ? Curves.easeOutCubic.transform(
          (_deathElapsed / _deathDuration).clamp(0.0, 1.0),
        )
      : 0;

  String? get scorePopupText =>
      _scorePopupCell != null && _scorePopupElapsed < _scorePopupDuration
      ? '+$_scorePopupValue'
      : null;

  Vector2 _cellPosition(SnakeCell cell) => Vector2(
    boardLeft + cell.column * cellSize,
    boardTop + cell.row * cellSize,
  );

  Offset _pathPointCenter(MidnightSnakePathPoint point) => Offset(
    boardLeft + (point.column + 0.5) * cellSize,
    boardTop + (point.row + 0.5) * cellSize,
  );

  Rect _cellRect(SnakeCell cell) => Rect.fromLTWH(
    boardLeft + cell.column * cellSize,
    boardTop + cell.row * cellSize,
    cellSize,
    cellSize,
  );

  static int _directionRow(SnakeDirection direction) => switch (direction) {
    SnakeDirection.down => 0,
    SnakeDirection.left => 1,
    SnakeDirection.right => 2,
    SnakeDirection.up => 3,
  };
}
