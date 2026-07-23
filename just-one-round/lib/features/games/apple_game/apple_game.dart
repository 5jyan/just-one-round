import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/apple_game/domain/apple_game_rules.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';

class AppleGame extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  AppleGame({
    required this.onFinished,
    this.gameDuration = const Duration(seconds: 120),
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

  static final logicalSize = Vector2(360, 720);

  final Duration gameDuration;
  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _AppleBoardComponent _board;
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _score = 0;
  var _lastPublishedSecond = -1;
  var _lastPublishedScore = -1;
  var _hasFinished = false;

  @override
  Color backgroundColor() => const Color(0xFF011B19);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    final loaded = await images.loadAll([
      'apple_game/apple_game_background.png',
      'apple_game/apple_faces_atlas.png',
      'apple_game/apple_pop_sheet.png',
    ]);

    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );

    final appleSheet = SpriteSheet(image: loaded[1], srcSize: Vector2.all(48));
    final apples = <Sprite>[];
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        apples.add(appleSheet.getSprite(row, column));
      }
    }
    final popSheet = SpriteSheet(image: loaded[2], srcSize: Vector2.all(48));
    final popSprites = List.generate(
      4,
      (index) => popSheet.getSprite(0, index),
      growable: false,
    );

    _board = _AppleBoardComponent(
      board: AppleGameRules.createBoard(_random),
      appleSprites: apples,
      popSprites: popSprites,
      onRemoved: _handleRemoved,
    );
    await world.add(_board);

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
        final seconds =
            gameDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_playingElapsed >= seconds) {
          _finishGame();
        } else {
          _publishHud();
        }
      case MiniGamePhase.finished:
        return;
    }
  }

  void _handleRemoved(int count) {
    if (_phase != MiniGamePhase.playing || count <= 0) return;
    _score += count;
    _publishHud(force: true);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_phase != MiniGamePhase.playing) return;
    _board.beginSelection(_viewportPosition(event.canvasPosition));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_phase != MiniGamePhase.playing) return;
    _board.updateSelection(_viewportPosition(event.canvasEndPosition));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_phase != MiniGamePhase.playing) return;
    _board.commitSelection();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _board.cancelSelection();
  }

  Vector2 _viewportPosition(Vector2 canvasPosition) =>
      camera.viewport.globalToLocal(canvasPosition);

  void _finishGame() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _board.cancelSelection();
    _publishHud(force: true);
    pauseEngine();
    onFinished(
      GameResult(
        score: _score,
        starsCollected: 0,
        collisions: 0,
        duration: Duration(
          milliseconds: (_playingElapsed * 1000).round().clamp(
            1,
            gameDuration.inMilliseconds,
          ),
        ),
      ),
    );
  }

  void _publishHud({bool force = false}) {
    final remaining = max(
      0,
      (gameDuration.inMicroseconds / Duration.microsecondsPerSecond -
              _playingElapsed)
          .ceil(),
    );
    final countdown = max(
      0,
      (countdownDuration.inMicroseconds / Duration.microsecondsPerSecond -
              _countdownElapsed)
          .ceil(),
    );
    if (!force &&
        remaining == _lastPublishedSecond &&
        _score == _lastPublishedScore &&
        hud.value.countdownNumber == countdown) {
      return;
    }
    _lastPublishedSecond = remaining;
    _lastPublishedScore = _score;
    hud.value = MiniGameHudState(
      phase: _phase,
      score: _score,
      elapsedSeconds: _playingElapsed.floor(),
      remainingSeconds: remaining,
      countdownNumber: countdown,
    );
  }

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _board.cancelSelection();
    _publishHud(force: true);
    pauseEngine();
  }

  @override
  void disposeController() => hud.dispose();
}

class _AppleBoardComponent extends PositionComponent {
  _AppleBoardComponent({
    required this.board,
    required this.appleSprites,
    required this.popSprites,
    required this.onRemoved,
  }) : super(
         position: Vector2(_boardLeft, _boardTop),
         size: Vector2(_boardWidth, _boardHeight),
         priority: 5,
       );

  static const _boardLeft = 10.0;
  static const _boardTop = 64.0;
  static const _cellSize = 42.0;
  static const _appleSize = 40.0;
  static const _innerPadding = 2.0;
  static const _boardWidth =
      AppleGameRules.columnCount * _cellSize + _innerPadding * 2;
  static const _boardHeight =
      AppleGameRules.rowCount * _cellSize + _innerPadding * 2;

  final List<List<int?>> board;
  final List<Sprite> appleSprites;
  final List<Sprite> popSprites;
  final ValueChanged<int> onRemoved;
  final Paint _spritePaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;
  final Paint _selectionFill = Paint()
    ..color = const Color(0x55FFF3C4)
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;
  final Paint _selectionBorder = Paint()
    ..color = const Color(0xFFFFD24A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..isAntiAlias = false;

  AppleCellRange? _selection;
  int? _startRow;
  int? _startColumn;

  void beginSelection(Vector2 viewportPosition) {
    final cell = _cellAt(viewportPosition);
    if (cell == null) {
      cancelSelection();
      return;
    }
    _startRow = cell.$1;
    _startColumn = cell.$2;
    _selection = AppleCellRange(
      startRow: cell.$1,
      startColumn: cell.$2,
      endRow: cell.$1,
      endColumn: cell.$2,
    );
  }

  void updateSelection(Vector2 viewportPosition) {
    final startRow = _startRow;
    final startColumn = _startColumn;
    if (startRow == null || startColumn == null) return;
    final localX = (viewportPosition.x - position.x - _innerPadding).clamp(
      0.0,
      AppleGameRules.columnCount * _cellSize - 0.001,
    );
    final localY = (viewportPosition.y - position.y - _innerPadding).clamp(
      0.0,
      AppleGameRules.rowCount * _cellSize - 0.001,
    );
    _selection = AppleCellRange(
      startRow: startRow,
      startColumn: startColumn,
      endRow: localY ~/ _cellSize,
      endColumn: localX ~/ _cellSize,
    );
  }

  void commitSelection() {
    final selection = _selection;
    if (selection == null) return;
    final removedCells = <(int, int)>[];
    if (AppleGameRules.selectionSum(board, selection) ==
        AppleGameRules.targetSum) {
      for (var row = selection.top; row <= selection.bottom; row++) {
        for (var column = selection.left; column <= selection.right; column++) {
          if (board[row][column] != null) removedCells.add((row, column));
        }
      }
    }
    final removed = AppleGameRules.removeSelection(board, selection);
    if (removed > 0) {
      for (final cell in removedCells) {
        parent?.add(
          _ApplePopComponent(
            position: Vector2(
              position.x + _innerPadding + (cell.$2 + 0.5) * _cellSize,
              position.y + _innerPadding + (cell.$1 + 0.5) * _cellSize,
            ),
            sprites: popSprites,
          ),
        );
      }
      onRemoved(removed);
    }
    cancelSelection();
  }

  void cancelSelection() {
    _startRow = null;
    _startColumn = null;
    _selection = null;
  }

  (int, int)? _cellAt(Vector2 viewportPosition) {
    final x = viewportPosition.x - position.x - _innerPadding;
    final y = viewportPosition.y - position.y - _innerPadding;
    if (x < 0 ||
        y < 0 ||
        x >= AppleGameRules.columnCount * _cellSize ||
        y >= AppleGameRules.rowCount * _cellSize) {
      return null;
    }
    return (y ~/ _cellSize, x ~/ _cellSize);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (var row = 0; row < AppleGameRules.rowCount; row++) {
      for (var column = 0; column < AppleGameRules.columnCount; column++) {
        final value = board[row][column];
        if (value == null) continue;
        final topLeft = Vector2(
          _innerPadding + column * _cellSize,
          _innerPadding + row * _cellSize,
        );
        appleSprites[value - 1].render(
          canvas,
          position: topLeft + Vector2.all((_cellSize - _appleSize) / 2),
          size: Vector2.all(_appleSize),
          overridePaint: _spritePaint,
        );
        _drawNumber(canvas, value, topLeft);
      }
    }

    if (_selection case final selection?) {
      final rect = Rect.fromLTWH(
        _innerPadding + selection.left * _cellSize,
        _innerPadding + selection.top * _cellSize,
        (selection.right - selection.left + 1) * _cellSize,
        (selection.bottom - selection.top + 1) * _cellSize,
      );
      canvas
        ..drawRect(rect, _selectionFill)
        ..drawRect(rect, _selectionBorder);
      _drawSelectionSum(canvas, selection, rect);
    }
  }

  void _drawNumber(Canvas canvas, int value, Vector2 topLeft) {
    final painter = TextPainter(
      text: TextSpan(
        text: '$value',
        style: const TextStyle(
          fontFamily: 'Galmuri',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFFF3C4),
          shadows: [
            Shadow(color: Color(0xFF591F2C), offset: Offset(2, 0)),
            Shadow(color: Color(0xFF591F2C), offset: Offset(-2, 0)),
            Shadow(color: Color(0xFF591F2C), offset: Offset(0, 2)),
            Shadow(color: Color(0xFF591F2C), offset: Offset(0, -2)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (topLeft.x + (_cellSize - painter.width) / 2).roundToDouble(),
        (topLeft.y + (_cellSize - painter.height) / 2 - 1).roundToDouble(),
      ),
    );
  }

  void _drawSelectionSum(
    Canvas canvas,
    AppleCellRange selection,
    Rect selectionRect,
  ) {
    final sum = AppleGameRules.selectionSum(board, selection);
    final painter = TextPainter(
      text: TextSpan(
        text: '$sum / ${AppleGameRules.targetSum}',
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: sum == AppleGameRules.targetSum
              ? const Color(0xFFFFF3C4)
              : const Color(0xFF591F2C),
          backgroundColor: sum == AppleGameRules.targetSum
              ? const Color(0xFF7B352D)
              : const Color(0xCCFFF3C4),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = (selectionRect.right - painter.width).clamp(
      0.0,
      size.x - painter.width,
    );
    final y = (selectionRect.top - painter.height).clamp(
      0.0,
      size.y - painter.height,
    );
    painter.paint(canvas, Offset(x, y));
  }
}

class _ApplePopComponent extends PositionComponent {
  _ApplePopComponent({required super.position, required this.sprites})
    : super(size: Vector2.all(40), anchor: Anchor.center, priority: 30);

  final List<Sprite> sprites;
  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;
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
    sprites[index].render(canvas, size: size, overridePaint: _paint);
  }
}
