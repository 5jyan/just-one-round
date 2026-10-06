import 'dart:async';
import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/apple_game_v2/domain/apple_game_v2_rules.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';

class AppleGameV2AssetSet {
  const AppleGameV2AssetSet({
    required this.directory,
    required this.appleSourceCellSize,
    required this.popSourceCellSize,
    required this.appleDisplaySize,
    required this.numberFontSize,
    required this.numberShadowOffset,
    required this.numberVerticalOffset,
    required this.phoneOverscan,
    this.comboSourceCellSize,
    this.numberLineHeight,
  });

  static const midnightOrchard = AppleGameV2AssetSet(
    directory: 'apple_game_v2',
    appleSourceCellSize: 42,
    popSourceCellSize: 40,
    appleDisplaySize: 42,
    numberFontSize: 18,
    numberShadowOffset: 1,
    numberVerticalOffset: 4,
    phoneOverscan: true,
    comboSourceCellSize: 32,
    numberLineHeight: 1,
  );

  final String directory;
  final double appleSourceCellSize;
  final double popSourceCellSize;
  final double appleDisplaySize;
  final double numberFontSize;
  final double numberShadowOffset;
  final double numberVerticalOffset;
  final bool phoneOverscan;
  final double? comboSourceCellSize;
  final double? numberLineHeight;
}

class AppleGameV2 extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  AppleGameV2({
    required this.onFinished,
    this.gameDuration = AppleGameV2Rules.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    this.assetSet = AppleGameV2AssetSet.midnightOrchard,
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
  static final phoneBackgroundSize = Vector2(408, 880);
  static final phoneBackgroundPosition = Vector2(-24, -80);
  static const maxPhoneVisibleHeight = 840.0;
  static const comboEffectFrameCount = 4;

  static int? comboEffectTierForOrdinal(int ordinal) {
    if (ordinal < 2) return null;
    return min(ordinal - 2, 2);
  }

  static double? comboEffectDisplaySizeForOrdinal(int ordinal) {
    return switch (comboEffectTierForOrdinal(ordinal)) {
      0 => 64,
      1 => 96,
      2 => 128,
      _ => null,
    };
  }

  final Duration gameDuration;
  final Duration countdownDuration;
  final AppleGameV2AssetSet assetSet;
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

  static Vector2 viewportResolutionForCanvas(Vector2 canvasSize) {
    if (canvasSize.x <= 0 || canvasSize.y <= 0) {
      return logicalSize.clone();
    }
    final canvasAspectRatio = canvasSize.y / canvasSize.x;
    if (canvasAspectRatio < logicalSize.y / logicalSize.x) {
      final visibleWidth = (logicalSize.y / canvasAspectRatio).clamp(
        logicalSize.x,
        phoneBackgroundSize.x,
      );
      return Vector2(visibleWidth, logicalSize.y);
    }
    final visibleHeight = (logicalSize.x * canvasAspectRatio).clamp(
      logicalSize.y,
      maxPhoneVisibleHeight,
    );
    return Vector2(logicalSize.x, visibleHeight);
  }

  void _configureViewport(Vector2 canvasSize) {
    final resolution = assetSet.phoneOverscan
        ? viewportResolutionForCanvas(canvasSize)
        : logicalSize.clone();
    camera.viewport = FixedResolutionViewport(resolution: resolution);
    camera.viewfinder.position = logicalSize / 2;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);

    final comboSourceCellSize = assetSet.comboSourceCellSize;
    final loaded = await images.loadAll([
      '${assetSet.directory}/apple_game_background.png',
      '${assetSet.directory}/apple_faces_atlas.png',
      '${assetSet.directory}/apple_pop_sheet.png',
      if (comboSourceCellSize != null)
        '${assetSet.directory}/apple_combo_burst_sheet.png',
    ]);

    await world.add(
      SpriteComponent(
        sprite: Sprite(loaded[0]),
        position: assetSet.phoneOverscan
            ? phoneBackgroundPosition.clone()
            : Vector2.zero(),
        size: assetSet.phoneOverscan
            ? phoneBackgroundSize.clone()
            : logicalSize.clone(),
        priority: -20,
      ),
    );

    final appleSheet = SpriteSheet(
      image: loaded[1],
      srcSize: Vector2.all(assetSet.appleSourceCellSize),
    );
    final apples = <Sprite>[];
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        apples.add(appleSheet.getSprite(row, column));
      }
    }
    final popSheet = SpriteSheet(
      image: loaded[2],
      srcSize: Vector2.all(assetSet.popSourceCellSize),
    );
    final popSprites = List.generate(
      4,
      (index) => popSheet.getSprite(0, index),
      growable: false,
    );
    final comboSprites = comboSourceCellSize == null
        ? null
        : SpriteSheet(
            image: loaded[3],
            srcSize: Vector2.all(comboSourceCellSize),
          );

    _board = _AppleBoardComponent(
      board: AppleGameV2Rules.createBoard(_random),
      appleSprites: apples,
      popSprites: popSprites,
      comboSprites: comboSprites,
      appleSize: assetSet.appleDisplaySize,
      numberFontSize: assetSet.numberFontSize,
      numberShadowOffset: assetSet.numberShadowOffset,
      numberVerticalOffset: assetSet.numberVerticalOffset,
      numberLineHeight: assetSet.numberLineHeight,
      onRemoved: _handleRemoved,
      onBoardCleared: _handleBoardCleared,
    );
    await world.add(_board);

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
          _finishGame(GameEndType.timeUp);
        } else {
          _publishHud();
        }
      case MiniGamePhase.finished:
        return;
    }
  }

  void _handleRemoved(int count) {
    if (_phase != MiniGamePhase.playing || count <= 0) return;
    unawaited(
      assetSet.comboSourceCellSize == null
          ? _playClassicApplePopHaptic(count)
          : _playEscalatingApplePopHaptic(count),
    );
    _score += count;
    _publishHud(force: true);
  }

  void _handleBoardCleared() {
    if (_phase != MiniGamePhase.playing) return;
    _finishGame(GameEndType.clear);
  }

  Future<void> _playClassicApplePopHaptic(int count) async {
    await HapticFeedback.heavyImpact();
    for (var pulse = 1; pulse < count; pulse++) {
      await Future<void>.delayed(const Duration(milliseconds: 65));
      await HapticFeedback.mediumImpact();
    }
  }

  Future<void> _playEscalatingApplePopHaptic(int count) async {
    for (var pulse = 0; pulse < count; pulse++) {
      if (pulse > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (pulse == 0) {
        await HapticFeedback.lightImpact();
      } else if (pulse == 1) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.heavyImpact();
        if (pulse >= 3) {
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 45),
              HapticFeedback.heavyImpact,
            ),
          );
        }
      }
    }
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
      camera.globalToLocal(canvasPosition);

  void _finishGame(GameEndType endType) {
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
        endType: endType,
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

  @visibleForTesting
  void setBoardForTesting(List<List<int?>> replacement, {int score = 0}) {
    _board.replaceBoard(replacement);
    _score = score;
    _publishHud(force: true);
  }

  @visibleForTesting
  void commitSelectionForTesting(AppleCellRange range) {
    _board.commitSelectionRange(range);
  }
}

class _AppleBoardComponent extends PositionComponent {
  _AppleBoardComponent({
    required this.board,
    required this.appleSprites,
    required this.popSprites,
    required this.comboSprites,
    required this.appleSize,
    required this.numberFontSize,
    required this.numberShadowOffset,
    required this.numberVerticalOffset,
    required this.numberLineHeight,
    required this.onRemoved,
    required this.onBoardCleared,
  }) : super(
         position: Vector2(_boardLeft, _boardTop),
         size: Vector2(_boardWidth, _boardHeight),
         priority: 5,
       );

  static const _boardLeft = 10.0;
  static const _boardTop = 96.0;
  static const _cellSize = 42.0;
  static const _innerPadding = 2.0;
  static const _boardWidth =
      AppleGameV2Rules.columnCount * _cellSize + _innerPadding * 2;
  static const _boardHeight =
      AppleGameV2Rules.rowCount * _cellSize + _innerPadding * 2;
  static const _sequentialRemovalInterval = 0.15;

  final List<List<int?>> board;
  final List<Sprite> appleSprites;
  final List<Sprite> popSprites;
  final SpriteSheet? comboSprites;
  final double appleSize;
  final double numberFontSize;
  final double numberShadowOffset;
  final double numberVerticalOffset;
  final double? numberLineHeight;
  final ValueChanged<int> onRemoved;
  final VoidCallback onBoardCleared;
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
  List<(int, int)>? _pendingRemovalCells;
  var _nextRemovalIndex = 0;
  var _sequentialRemovalElapsed = 0.0;

  void beginSelection(Vector2 viewportPosition) {
    if (_pendingRemovalCells != null) return;
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
    if (_pendingRemovalCells != null) return;
    final startRow = _startRow;
    final startColumn = _startColumn;
    if (startRow == null || startColumn == null) return;
    final localX = (viewportPosition.x - position.x - _innerPadding).clamp(
      0.0,
      AppleGameV2Rules.columnCount * _cellSize - 0.001,
    );
    final localY = (viewportPosition.y - position.y - _innerPadding).clamp(
      0.0,
      AppleGameV2Rules.rowCount * _cellSize - 0.001,
    );
    _selection = AppleCellRange(
      startRow: startRow,
      startColumn: startColumn,
      endRow: localY ~/ _cellSize,
      endColumn: localX ~/ _cellSize,
    );
  }

  void commitSelection() {
    if (_pendingRemovalCells != null) return;
    final selection = _selection;
    if (selection == null) return;
    commitSelectionRange(selection);
  }

  void commitSelectionRange(AppleCellRange selection) {
    if (_pendingRemovalCells != null) return;
    if (AppleGameV2Rules.selectionSum(board, selection) !=
        AppleGameV2Rules.targetSum) {
      cancelSelection();
      return;
    }
    final removedCells = AppleGameV2Rules.orderedSelectedCells(
      board,
      selection,
    );
    if (removedCells.isEmpty) {
      cancelSelection();
      return;
    }

    if (comboSprites == null) {
      AppleGameV2Rules.removeSelection(board, selection);
      for (final cell in removedCells) {
        _spawnPop(cell, ordinal: 1);
      }
      onRemoved(removedCells.length);
      if (AppleGameV2Rules.isBoardCleared(board)) onBoardCleared();
    } else {
      _pendingRemovalCells = removedCells;
      _nextRemovalIndex = 0;
      _sequentialRemovalElapsed = 0;
      onRemoved(removedCells.length);
      _removeNextSequentialApple();
    }
    cancelSelection();
  }

  void cancelSelection() {
    _startRow = null;
    _startColumn = null;
    _selection = null;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_pendingRemovalCells == null) return;
    _sequentialRemovalElapsed += dt;
    while (_pendingRemovalCells != null &&
        _sequentialRemovalElapsed >= _sequentialRemovalInterval) {
      _sequentialRemovalElapsed -= _sequentialRemovalInterval;
      _removeNextSequentialApple();
    }
  }

  void _removeNextSequentialApple() {
    final cells = _pendingRemovalCells;
    if (cells == null) return;
    final cell = cells[_nextRemovalIndex];
    board[cell.$1][cell.$2] = null;
    _spawnPop(cell, ordinal: _nextRemovalIndex + 1);
    _nextRemovalIndex++;
    if (_nextRemovalIndex >= cells.length) {
      _pendingRemovalCells = null;
      _nextRemovalIndex = 0;
      _sequentialRemovalElapsed = 0;
      if (AppleGameV2Rules.isBoardCleared(board)) onBoardCleared();
    }
  }

  void replaceBoard(List<List<int?>> replacement) {
    assert(replacement.length == AppleGameV2Rules.rowCount);
    for (var row = 0; row < AppleGameV2Rules.rowCount; row++) {
      assert(replacement[row].length == AppleGameV2Rules.columnCount);
      for (var column = 0; column < AppleGameV2Rules.columnCount; column++) {
        board[row][column] = replacement[row][column];
      }
    }
    _pendingRemovalCells = null;
    _nextRemovalIndex = 0;
    _sequentialRemovalElapsed = 0;
    cancelSelection();
  }

  void _spawnPop((int, int) cell, {required int ordinal}) {
    final cellCenter = Vector2(
      position.x + _innerPadding + (cell.$2 + 0.5) * _cellSize,
      position.y + _innerPadding + (cell.$1 + 0.5) * _cellSize,
    );
    parent?.add(_ApplePopComponent(position: cellCenter, sprites: popSprites));
    final comboTier = AppleGameV2.comboEffectTierForOrdinal(ordinal);
    final comboDisplaySize = AppleGameV2.comboEffectDisplaySizeForOrdinal(
      ordinal,
    );
    final comboSheet = comboSprites;
    if (comboTier == null || comboDisplaySize == null || comboSheet == null) {
      return;
    }
    parent?.add(
      _AppleComboBurstComponent(
        position: cellCenter,
        displaySize: comboDisplaySize,
        sprites: List.generate(
          AppleGameV2.comboEffectFrameCount,
          (column) => comboSheet.getSprite(comboTier, column),
          growable: false,
        ),
      ),
    );
  }

  (int, int)? _cellAt(Vector2 viewportPosition) {
    final x = viewportPosition.x - position.x - _innerPadding;
    final y = viewportPosition.y - position.y - _innerPadding;
    if (x < 0 ||
        y < 0 ||
        x >= AppleGameV2Rules.columnCount * _cellSize ||
        y >= AppleGameV2Rules.rowCount * _cellSize) {
      return null;
    }
    return (y ~/ _cellSize, x ~/ _cellSize);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (var row = 0; row < AppleGameV2Rules.rowCount; row++) {
      for (var column = 0; column < AppleGameV2Rules.columnCount; column++) {
        final value = board[row][column];
        if (value == null) continue;
        final topLeft = Vector2(
          _innerPadding + column * _cellSize,
          _innerPadding + row * _cellSize,
        );
        appleSprites[value - 1].render(
          canvas,
          position: topLeft + Vector2.all((_cellSize - appleSize) / 2),
          size: Vector2.all(appleSize),
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
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontSize: numberFontSize,
          height: numberLineHeight,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFF3C4),
          shadows: [
            Shadow(
              color: const Color(0xFF591F2C),
              offset: Offset(numberShadowOffset, 0),
            ),
            Shadow(
              color: const Color(0xFF591F2C),
              offset: Offset(-numberShadowOffset, 0),
            ),
            Shadow(
              color: const Color(0xFF591F2C),
              offset: Offset(0, numberShadowOffset),
            ),
            Shadow(
              color: const Color(0xFF591F2C),
              offset: Offset(0, -numberShadowOffset),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (topLeft.x + (_cellSize - painter.width) / 2).roundToDouble(),
        (topLeft.y + (_cellSize - painter.height) / 2 + numberVerticalOffset)
            .roundToDouble(),
      ),
    );
  }

  void _drawSelectionSum(
    Canvas canvas,
    AppleCellRange selection,
    Rect selectionRect,
  ) {
    final sum = AppleGameV2Rules.selectionSum(board, selection);
    final painter = TextPainter(
      text: TextSpan(
        text: '$sum / ${AppleGameV2Rules.targetSum}',
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: sum == AppleGameV2Rules.targetSum
              ? const Color(0xFFFFF3C4)
              : const Color(0xFF591F2C),
          backgroundColor: sum == AppleGameV2Rules.targetSum
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

class _AppleComboBurstComponent extends PositionComponent {
  _AppleComboBurstComponent({
    required super.position,
    required this.sprites,
    required double displaySize,
  }) : super(
         size: Vector2.all(displaySize),
         anchor: Anchor.center,
         priority: 40,
       );

  static const _frameDuration = 0.07;

  final List<Sprite> sprites;
  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= sprites.length * _frameDuration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final index = min(sprites.length - 1, (_elapsed / _frameDuration).floor());
    sprites[index].render(canvas, size: size, overridePaint: _paint);
  }
}
