import 'dart:async';
import 'dart:math';
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
import 'package:just_one_round/features/games/sausage_dachshund/domain/sausage_dachshund_rules.dart';

class SausageDachshundGame extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  SausageDachshundGame({
    required this.onFinished,
    this.gameDuration = SausageDachshundRules.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    Random? random,
  }) : _random =
           random ??
           Random(SausageDachshundRules.dailySeed(DateTime.now().toUtc())),
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

  late final _SausageDachshundBoard _board;
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
  DachshundFinishReason? _finishReason;
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
      'sausage_dachshund/kitchen_background_v3.png',
      'sausage_dachshund/dog_head_walk_atlas_v4.png',
      'sausage_dachshund/dog_head_eat_atlas_v4.png',
      'sausage_dachshund/dog_body_atlas_v4.png',
      'sausage_dachshund/dog_tail_walk_atlas_v4.png',
      'sausage_dachshund/sausage_idle_sheet.png',
      'sausage_dachshund/bite_fx_sheet.png',
    ]);

    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );
    _board = _SausageDachshundBoard(
      state: SausageDachshundState.initial(),
      headWalk: _spritesFromGrid(loaded[1], rows: 4, columns: 4, frameSize: 32),
      headEat: _spritesFromGrid(loaded[2], rows: 4, columns: 4, frameSize: 32),
      bodySprites: _spritesFromGrid(
        loaded[3],
        rows: 3,
        columns: 2,
        frameSize: 32,
      ),
      tailWalk: _spritesFromGrid(loaded[4], rows: 4, columns: 4, frameSize: 32),
      sausageIdle: _spritesFromGrid(
        loaded[5],
        rows: 2,
        columns: 2,
        frameSize: 32,
      ),
      biteFx: _spritesFromGrid(loaded[6], rows: 2, columns: 2, frameSize: 32),
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
        final countdownSeconds =
            countdownDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_countdownElapsed >= countdownSeconds && _assetsReady) {
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
          _beginFinish(DachshundFinishReason.timeout);
          return;
        }

        _board.elapsedSeconds = _playingElapsed;
        _moveAccumulator += dt;
        var processedTicks = 0;
        while (processedTicks < 12) {
          final tickTimeline = max(0.0, _playingElapsed - _moveAccumulator);
          final interval = SausageDachshundRules.moveIntervalAt(tickTimeline);
          if (_moveAccumulator < interval) break;
          _moveAccumulator -= interval;
          processedTicks++;
          final result = _board.advance(
            _random,
            transitionDuration: min(0.18, interval * 0.45),
          );
          if (result.ateSausage) {
            unawaited(HapticFeedback.mediumImpact());
          }
          if (result.finishReason case final reason?) {
            unawaited(HapticFeedback.heavyImpact());
            _beginFinish(reason);
            return;
          }
        }
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
    _finishDrag();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragStart = null;
    _dragCurrent = null;
  }

  void _finishDrag() {
    final start = _dragStart;
    final end = _dragCurrent;
    _dragStart = null;
    _dragCurrent = null;
    if (start == null ||
        end == null ||
        _phase != MiniGamePhase.playing ||
        _isTerminal) {
      return;
    }
    queueSwipeForTesting(end - start);
  }

  @visibleForTesting
  bool queueSwipeForTesting(Vector2 delta) {
    if (_phase != MiniGamePhase.playing || _isTerminal || !_assetsReady) {
      return false;
    }
    final direction = SausageDachshundRules.directionForSwipe(
      deltaX: delta.x,
      deltaY: delta.y,
    );
    if (direction == null) return false;
    final accepted = _board.state.queueDirection(direction);
    if (accepted) unawaited(HapticFeedback.selectionClick());
    return accepted;
  }

  void _beginFinish(DachshundFinishReason reason) {
    if (_isTerminal) return;
    _isTerminal = true;
    _finishReason = reason;
    _phase = MiniGamePhase.finished;
    _board
      ..isPlaying = false
      ..showFinish(reason);
    _finishDelay = switch (reason) {
      DachshundFinishReason.wall || DachshundFinishReason.self => 0.5,
      DachshundFinishReason.timeout ||
      DachshundFinishReason.boardComplete => 0.25,
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
            _finishReason == DachshundFinishReason.wall ||
                _finishReason == DachshundFinishReason.self
            ? 1
            : 0,
        duration: Duration(
          milliseconds: (_playingElapsed * 1000).round().clamp(
            1,
            gameDuration.inMilliseconds,
          ),
        ),
        endType: switch (_finishReason!) {
          DachshundFinishReason.wall ||
          DachshundFinishReason.self => GameEndType.gameOver,
          DachshundFinishReason.timeout => GameEndType.timeUp,
          DachshundFinishReason.boardComplete => GameEndType.clear,
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
  SausageDachshundState get stateForTesting => _board.state;

  @visibleForTesting
  Rect get boardRectForTesting => _SausageDachshundBoard.boardRect;

  @visibleForTesting
  double get playingElapsedForTesting => _playingElapsed;

  @visibleForTesting
  bool get isTerminalForTesting => _isTerminal;

  @visibleForTesting
  List<int> get bodySpriteIndicesForTesting => _board.bodySpriteIndices;

  @visibleForTesting
  double get movementProgressForTesting => _board.movementProgress;

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
    required double frameSize,
  }) {
    final sheet = SpriteSheet(image: image, srcSize: Vector2.all(frameSize));
    return [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          sheet.getSprite(row, column),
    ];
  }
}

class _SausageDachshundBoard extends PositionComponent {
  _SausageDachshundBoard({
    required this.state,
    required this.headWalk,
    required this.headEat,
    required this.bodySprites,
    required this.tailWalk,
    required this.sausageIdle,
    required this.biteFx,
  }) : assert(headWalk.length == 16),
       assert(headEat.length == 16),
       assert(bodySprites.length == 6),
       assert(tailWalk.length == 16),
       assert(sausageIdle.length == 4),
       assert(biteFx.length == 4),
       super(size: SausageDachshundGame.logicalSize.clone());

  static const cellSize = 32.0;
  static const boardLeft = 36.0;
  static const boardTop = 112.0;
  static const boardWidth = cellSize * SausageDachshundRules.columnCount;
  static const boardHeight = cellSize * SausageDachshundRules.rowCount;
  static const boardRect = Rect.fromLTWH(
    boardLeft,
    boardTop,
    boardWidth,
    boardHeight,
  );

  final SausageDachshundState state;
  final List<Sprite> headWalk;
  final List<Sprite> headEat;
  final List<Sprite> bodySprites;
  final List<Sprite> tailWalk;
  final List<Sprite> sausageIdle;
  final List<Sprite> biteFx;

  final Paint _pixelPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;
  final Paint _dogPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;
  final Paint _seamOutlinePaint = Paint()
    ..color = const Color(0xFF252824)
    ..strokeWidth = 18
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final Paint _seamCoatPaint = Paint()
    ..color = const Color(0xFF4F594B)
    ..strokeWidth = 14
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final Paint _overlayPaint = Paint()..isAntiAlias = false;

  bool isPlaying = false;
  double elapsedSeconds = 0;
  double _eatElapsed = 1;
  double _biteElapsed = 1;
  double _movementElapsed = 1;
  double _movementDuration = 0.16;
  List<DachshundCell> _previousBody = const [];
  DachshundCell? _lastEatenCell;
  DachshundFinishReason? _finishReason;

  bool containsLogicalPoint(Vector2 point) =>
      boardRect.contains(Offset(point.x, point.y));

  List<int> get bodySpriteIndices => [
    for (var index = 1; index < state.body.length - 1; index++)
      _bodySpriteIndex(
        previous: state.body[index - 1],
        current: state.body[index],
        next: state.body[index + 1],
      ),
  ];

  double get movementProgress {
    if (_previousBody.isEmpty || _movementDuration <= 0) return 1;
    return (_movementElapsed / _movementDuration).clamp(0, 1);
  }

  DachshundStepResult advance(
    Random random, {
    required double transitionDuration,
  }) {
    if (!isPlaying) {
      return const DachshundStepResult(moved: false, ateSausage: false);
    }
    final eatenCell = state.sausage;
    final previousBody = List<DachshundCell>.of(state.body);
    final result = state.step(random);
    if (result.moved) {
      _previousBody = previousBody;
      _movementElapsed = 0;
      _movementDuration = transitionDuration;
    }
    if (result.ateSausage) {
      _lastEatenCell = eatenCell;
      _eatElapsed = 0;
      _biteElapsed = 0;
    }
    return result;
  }

  void showFinish(DachshundFinishReason reason) {
    _finishReason = reason;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _eatElapsed += dt;
    _biteElapsed += dt;
    _movementElapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderSausage(canvas);
    _renderDog(canvas);
    _renderBiteFx(canvas);
    _renderFinishFeedback(canvas);
  }

  void _renderSausage(Canvas canvas) {
    final sausage = state.sausage;
    if (sausage == null) return;
    final frame = ((elapsedSeconds / 0.18).floor()) % sausageIdle.length;
    sausageIdle[frame].render(
      canvas,
      position: _cellPosition(sausage),
      size: Vector2.all(cellSize),
      overridePaint: _pixelPaint,
    );
  }

  void _renderDog(Canvas canvas) {
    final body = state.body;
    if (body.isEmpty) return;
    final walkFrame = ((elapsedSeconds / 0.11).floor()) % 4;

    _renderSeamGuard(canvas);

    for (var index = body.length - 2; index >= 1; index--) {
      final spriteIndex = _bodySpriteIndex(
        previous: body[index - 1],
        current: body[index],
        next: body[index + 1],
      );
      bodySprites[spriteIndex].render(
        canvas,
        position: _renderPosition(index),
        size: Vector2.all(cellSize),
        overridePaint: _dogPaint,
      );
    }

    if (body.length > 1) {
      final connector = _directionBetween(body.last, body[body.length - 2]);
      final tailFacing = connector.opposite;
      tailWalk[_directionRow(tailFacing) * 4 + walkFrame].render(
        canvas,
        position: _renderPosition(body.length - 1),
        size: Vector2.all(cellSize),
        overridePaint: _dogPaint,
      );
    }

    final headSprites = _eatElapsed < 0.28 ? headEat : headWalk;
    final headFrame = _eatElapsed < 0.28
        ? min(3, (_eatElapsed / 0.07).floor())
        : walkFrame;
    headSprites[_directionRow(state.direction) * 4 + headFrame].render(
      canvas,
      position: _renderPosition(0),
      size: Vector2.all(cellSize),
      overridePaint: _dogPaint,
    );
  }

  void _renderSeamGuard(Canvas canvas) {
    if (state.body.length < 2) return;
    final path = Path();
    for (var index = 0; index < state.body.length; index++) {
      final position = _renderPosition(index);
      final center = Offset(
        position.x + cellSize / 2,
        position.y + cellSize / 2,
      );
      if (index == 0) {
        path.moveTo(center.dx, center.dy);
      } else {
        path.lineTo(center.dx, center.dy);
      }
    }
    canvas
      ..drawPath(path, _seamOutlinePaint)
      ..drawPath(path, _seamCoatPaint);
  }

  void _renderBiteFx(Canvas canvas) {
    final cell = _lastEatenCell;
    if (cell == null || _biteElapsed >= 0.32) return;
    final frame = min(3, (_biteElapsed / 0.08).floor());
    biteFx[frame].render(
      canvas,
      position: _cellPosition(cell),
      size: Vector2.all(cellSize),
      overridePaint: _pixelPaint,
    );
  }

  void _renderFinishFeedback(Canvas canvas) {
    final reason = _finishReason;
    if (reason == null) return;
    if (reason == DachshundFinishReason.wall ||
        reason == DachshundFinishReason.self) {
      _overlayPaint.color = const Color(0x88FF4B2B);
      canvas.drawRect(_cellRect(state.head).inflate(2), _overlayPaint);
    } else {
      _overlayPaint.color = const Color(0x554ED8C7);
      canvas.drawRect(boardRect, _overlayPaint);
    }
  }

  Vector2 _cellPosition(DachshundCell cell) => Vector2(
    boardLeft + cell.column * cellSize,
    boardTop + cell.row * cellSize,
  );

  Vector2 _renderPosition(int bodyIndex) {
    final destination = _cellPosition(state.body[bodyIndex]);
    if (_previousBody.isEmpty ||
        bodyIndex >= _previousBody.length ||
        movementProgress >= 1) {
      return destination;
    }
    final start = _cellPosition(_previousBody[bodyIndex]);
    final progress = Curves.easeOutCubic.transform(movementProgress);
    return Vector2(
      start.x + (destination.x - start.x) * progress,
      start.y + (destination.y - start.y) * progress,
    );
  }

  Rect _cellRect(DachshundCell cell) => Rect.fromLTWH(
    boardLeft + cell.column * cellSize,
    boardTop + cell.row * cellSize,
    cellSize,
    cellSize,
  );

  static int _directionRow(DachshundDirection direction) => switch (direction) {
    DachshundDirection.down => 0,
    DachshundDirection.left => 1,
    DachshundDirection.right => 2,
    DachshundDirection.up => 3,
  };

  static DachshundDirection _directionBetween(
    DachshundCell from,
    DachshundCell to,
  ) {
    if (to.row < from.row) return DachshundDirection.up;
    if (to.column > from.column) return DachshundDirection.right;
    if (to.row > from.row) return DachshundDirection.down;
    return DachshundDirection.left;
  }

  static int _bodySpriteIndex({
    required DachshundCell previous,
    required DachshundCell current,
    required DachshundCell next,
  }) {
    final sides = {
      _directionBetween(current, previous),
      _directionBetween(current, next),
    };
    if (sides.contains(DachshundDirection.left) &&
        sides.contains(DachshundDirection.right)) {
      return 0;
    }
    if (sides.contains(DachshundDirection.up) &&
        sides.contains(DachshundDirection.down)) {
      return 1;
    }
    if (sides.contains(DachshundDirection.left) &&
        sides.contains(DachshundDirection.down)) {
      return 2;
    }
    if (sides.contains(DachshundDirection.up) &&
        sides.contains(DachshundDirection.right)) {
      return 3;
    }
    if (sides.contains(DachshundDirection.right) &&
        sides.contains(DachshundDirection.down)) {
      return 4;
    }
    return 5;
  }
}
