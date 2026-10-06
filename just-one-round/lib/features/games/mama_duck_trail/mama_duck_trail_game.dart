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
import 'package:just_one_round/features/games/mama_duck_trail/domain/mama_duck_trail_rules.dart';

class MamaDuckTrailGame extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  MamaDuckTrailGame({
    required this.onFinished,
    this.gameDuration = MamaDuckTrailRules.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    Random? random,
  }) : _random =
           random ??
           Random(MamaDuckTrailRules.dailySeed(DateTime.now().toUtc())),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: gameDuration.inSeconds,
           countdownNumber: countdownDuration.inSeconds,
           distance: MamaDuckTrailRules.startingLives,
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

  late final _MamaDuckBoard _board;
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _score = 0;
  var _combo = 0;
  var _lives = MamaDuckTrailRules.startingLives;
  var _successfulRounds = 0;
  var _lostDucks = 0;
  var _hasFinished = false;
  var _assetsReady = false;
  var _lastPublishedSecond = -1;
  var _lastPublishedScore = -1;

  @override
  Color backgroundColor() => const Color(0xFF172D38);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = MaxViewport();
    camera.viewfinder
      ..visibleGameSize = Vector2(360, 0)
      ..position = logicalSize / 2;

    final loaded = await images.loadAll([
      'mama_duck_trail/duckling_walk_sheet.png',
      'mama_duck_trail/duckling_cheer_sheet.png',
      'mama_duck_trail/mother_duck_walk_sheet.png',
      'mama_duck_trail/mother_duck_idle.png',
      'mama_duck_trail/mother_duck_cheer_sheet.png',
      'mama_duck_trail/wolf_failure_sheet.png',
      'mama_duck_trail/marsh_board_map.png',
      'mama_duck_trail/footprints_atlas.png',
      'mama_duck_trail/marsh_background.png',
      'mama_duck_trail/duckling_grubby_walk_sheet.png',
      'mama_duck_trail/duckling_grubby_cheer_sheet.png',
      'mama_duck_trail/duckling_scarf_walk_sheet.png',
      'mama_duck_trail/duckling_scarf_cheer_sheet.png',
    ]);

    _board = _MamaDuckBoard(
      random: _random,
      ducklingWalkTypes: [
        for (final image in [loaded[0], loaded[9], loaded[11]])
          _spritesFromGrid(image, rows: 2, columns: 3, cellSize: 72),
      ],
      ducklingCheerTypes: [
        for (final image in [loaded[1], loaded[10], loaded[12]])
          _spritesFromGrid(image, rows: 2, columns: 3, cellSize: 72),
      ],
      motherWalk: _spritesFromGrid(
        loaded[2],
        rows: 2,
        columns: 3,
        cellSize: 72,
      ),
      motherIdle: Sprite(loaded[3]),
      motherCheer: _spritesFromGrid(
        loaded[4],
        rows: 2,
        columns: 3,
        cellSize: 72,
      ),
      wolfFailure: _spritesFromGrid(
        loaded[5],
        rows: 2,
        columns: 3,
        cellSize: 96,
      ),
      terrain: Sprite(loaded[6]),
      footprints: _spritesFromGrid(
        loaded[7],
        rows: 3,
        columns: 4,
        cellSize: 48,
      ),
      background: Sprite(loaded[8]),
      onSuccess: _handleRoundSuccess,
      onFailure: _handleRoundFailure,
      onFatalFailureComplete: () => _finishGame(livesExhausted: true),
      combo: () => _combo,
    );
    await world.add(_board);
    _assetsReady = true;

    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _board.startSession();
      _publishHud(force: true);
    }
  }

  @override
  void update(double dt) {
    final timerWasFrozen = _assetsReady && _board.freezesSessionTimer;
    super.update(dt);
    switch (_phase) {
      case MiniGamePhase.countdown:
        _countdownElapsed += dt;
        final countdownSeconds =
            countdownDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_countdownElapsed >= countdownSeconds && _assetsReady) {
          _phase = MiniGamePhase.playing;
          _board.startSession();
          _publishHud(force: true);
        } else {
          _publishHud();
        }
      case MiniGamePhase.playing:
        if (!timerWasFrozen && (!_assetsReady || !_board.freezesSessionTimer)) {
          _playingElapsed += dt;
        }
        final maximumSeconds =
            gameDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_playingElapsed >= maximumSeconds) {
          _playingElapsed = maximumSeconds;
          _finishGame(livesExhausted: false);
          return;
        }
        _board.sessionElapsed = _playingElapsed;
        _publishHud();
      case MiniGamePhase.finished:
        return;
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_phase != MiniGamePhase.playing) return;
    _board.beginDrag(camera.globalToLocal(event.canvasPosition));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (_phase != MiniGamePhase.playing) return;
    _board.updateDrag(camera.globalToLocal(event.canvasEndPosition));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_phase != MiniGamePhase.playing) return;
    _board.endDrag();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (_phase != MiniGamePhase.playing) return;
    _board.endDrag();
  }

  void _handleRoundSuccess(int pathLength) {
    unawaited(HapticFeedback.mediumImpact());
    if (_phase != MiniGamePhase.playing) return;
    _combo++;
    _successfulRounds++;
    _score = min(
      MamaDuckTrailRules.maximumSubmittedScore,
      _score +
          MamaDuckTrailRules.scoreForSuccess(
            pathLength: pathLength,
            comboAfterSuccess: _combo,
          ),
    );
    _publishHud(force: true);
  }

  bool _handleRoundFailure() {
    unawaited(HapticFeedback.heavyImpact());
    if (_phase != MiniGamePhase.playing) return true;
    _combo = 0;
    _lives = max(0, _lives - 1);
    _lostDucks++;
    _publishHud(force: true);
    return _lives > 0;
  }

  void _finishGame({required bool livesExhausted}) {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    if (_assetsReady) _board.stop();
    _publishHud(force: true);
    pauseEngine();
    onFinished(
      GameResult(
        score: _score,
        starsCollected: _successfulRounds,
        collisions: _lostDucks,
        duration: Duration(
          milliseconds: (_playingElapsed * 1000).round().clamp(
            1,
            gameDuration.inMilliseconds,
          ),
        ),
        endType: livesExhausted ? GameEndType.gameOver : GameEndType.timeUp,
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
    if (!force &&
        elapsedSecond == _lastPublishedSecond &&
        _score == _lastPublishedScore &&
        hud.value.countdownNumber == countdown) {
      return;
    }
    _lastPublishedSecond = elapsedSecond;
    _lastPublishedScore = _score;
    hud.value = MiniGameHudState(
      phase: _phase,
      score: _score,
      elapsedSeconds: elapsedSecond,
      remainingSeconds: max(0, gameDuration.inSeconds - elapsedSecond),
      countdownNumber: countdown,
      distance: _lives,
    );
  }

  @visibleForTesting
  int get livesForTesting => _lives;

  @visibleForTesting
  int get scoreForTesting => _score;

  @visibleForTesting
  int get rescuedDuckCountForTesting => _successfulRounds;

  @visibleForTesting
  int get visibleRescuedDuckCountForTesting =>
      MamaDuckTrailRules.visibleRescuedDuckCount(_successfulRounds);

  @visibleForTesting
  MamaDuckFeverTier get feverTierForTesting =>
      MamaDuckTrailRules.feverTierForCombo(_combo);

  @visibleForTesting
  bool get isRecallingForTesting => _assetsReady && _board.isRecalling;

  @visibleForTesting
  Rect get boardRectForTesting => _board.boardRect;

  @visibleForTesting
  Set<String> get visibleActorsForTesting => _board.visibleActorKinds;

  @visibleForTesting
  int get currentPathLengthForTesting => _board.currentPathLength;

  @visibleForTesting
  bool get isCheeringForTesting => _assetsReady && _board.isCheering;

  @visibleForTesting
  bool get isMotherCheeringForTesting =>
      _assetsReady && _board.isMotherCheering;

  @visibleForTesting
  List<Vector2> get successDuckCentersForTesting =>
      _assetsReady ? _board.successDuckCenters : const [];

  @visibleForTesting
  Vector2 get successMotherCenterForTesting => _board.successMotherCenter;

  @visibleForTesting
  double get playingElapsedForTesting => _playingElapsed;

  @visibleForTesting
  @visibleForTesting
  List<MamaDuckCell> get pathForTesting => _board.path;

  @visibleForTesting
  Vector2 cellCenterForTesting(MamaDuckCell cell) => _board.cellCenter(cell);

  @visibleForTesting
  void beginLogicalDragForTesting(Vector2 position) =>
      _board.beginDrag(position);

  @visibleForTesting
  void updateLogicalDragForTesting(Vector2 position) =>
      _board.updateDrag(position);

  @visibleForTesting
  void endLogicalDragForTesting() => _board.endDrag();

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    if (_assetsReady) _board.stop();
    _publishHud(force: true);
    pauseEngine();
  }

  @override
  void disposeController() => hud.dispose();

  static List<Sprite> _spritesFromGrid(
    ui.Image image, {
    required int rows,
    required int columns,
    required double cellSize,
  }) {
    final sheet = SpriteSheet(image: image, srcSize: Vector2.all(cellSize));
    return [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          sheet.getSprite(row, column),
    ];
  }

  static int wolfFailureFrameForElapsed(double elapsedSeconds) {
    if (elapsedSeconds < 0.10) return 0;
    if (elapsedSeconds < 0.20) return 1;
    if (elapsedSeconds < 0.44) return 2;
    if (elapsedSeconds < 0.60) return 3;
    if (elapsedSeconds < 0.80) return 4;
    return 5;
  }
}

enum _TrailStage { waiting, preview, recall, success, failure, stopped }

class _MamaDuckBoard extends PositionComponent {
  _MamaDuckBoard({
    required this.random,
    required this.ducklingWalkTypes,
    required this.ducklingCheerTypes,
    required this.motherWalk,
    required this.motherIdle,
    required this.motherCheer,
    required this.wolfFailure,
    required this.terrain,
    required this.footprints,
    required this.background,
    required this.onSuccess,
    required this.onFailure,
    required this.onFatalFailureComplete,
    required this.combo,
  }) : assert(ducklingWalkTypes.length == 3),
       assert(ducklingCheerTypes.length == 3),
       assert(ducklingWalkTypes.every((sprites) => sprites.length == 6)),
       assert(ducklingCheerTypes.every((sprites) => sprites.length == 6)),
       assert(motherWalk.length == 6),
       assert(motherCheer.length == 6),
       assert(wolfFailure.length == 6),
       assert(footprints.length == 12),
       super(size: MamaDuckTrailGame.logicalSize.clone());

  static const boardLeft = 0.0;
  static const boardTop = 68.0;
  static const tileSize = 72.0;
  static const boardWidth = tileSize * MamaDuckTrailRules.columnCount;
  static const boardHeight = tileSize * MamaDuckTrailRules.rowCount;
  static const _inputInset = 8.0;

  final Random random;
  final List<List<Sprite>> ducklingWalkTypes;
  final List<List<Sprite>> ducklingCheerTypes;
  final List<Sprite> motherWalk;
  final Sprite motherIdle;
  final List<Sprite> motherCheer;
  final List<Sprite> wolfFailure;
  final Sprite terrain;
  final List<Sprite> footprints;
  final Sprite background;
  final void Function(int pathLength) onSuccess;
  final bool Function() onFailure;
  final VoidCallback onFatalFailureComplete;
  final int Function() combo;

  final Paint _pixelPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;
  final Paint _flatPaint = Paint()..isAntiAlias = false;
  final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  var _stage = _TrailStage.waiting;
  var _stageElapsed = 0.0;
  var _visualElapsed = 0.0;
  var sessionElapsed = 0.0;
  var _completedPaths = 0;
  var _dragActive = false;
  var _invalidStartElapsed = 0.0;
  var _failureCanContinue = true;
  MamaDuckCell? _wrongCell;
  List<MamaDuckCell> _path = const [
    MamaDuckCell(6, 0),
    MamaDuckCell(5, 0),
    MamaDuckCell(5, 1),
    MamaDuckCell(4, 1),
    MamaDuckCell(4, 2),
    MamaDuckCell(3, 2),
    MamaDuckCell(3, 3),
  ];
  final List<MamaDuckCell> _entered = [];

  bool get isRecalling => _stage == _TrailStage.recall;

  bool get isCheering =>
      _stage == _TrailStage.success &&
      _stageElapsed >= MamaDuckTrailRules.successTravelDurationSeconds;

  bool get isMotherCheering => isCheering;

  bool get freezesSessionTimer => isCheering;

  Rect get boardRect =>
      const Rect.fromLTWH(boardLeft, boardTop, boardWidth, boardHeight);

  Set<String> get visibleActorKinds => switch (_stage) {
    _TrailStage.preview => const {'mother'},
    _TrailStage.recall => const {'mother'},
    _TrailStage.success => const {'mother', 'duckling'},
    _TrailStage.failure => const {'wolf'},
    _ => const {},
  };

  int get currentPathLength => _path.length;

  Vector2 cellCenter(MamaDuckCell cell) => _cellCenter(cell);

  List<MamaDuckCell> get path => List.unmodifiable(_path);

  List<Vector2> get successDuckCenters =>
      _stage == _TrailStage.success ? _successDuckCenters() : const [];

  Vector2 get successMotherCenter => _cellCenter(_path.last);

  void startSession() {
    if (_stage == _TrailStage.stopped) return;
    sessionElapsed = 0;
    _completedPaths = 0;
    _startRound();
  }

  void stop() {
    _dragActive = false;
    _stage = _TrailStage.stopped;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_stage == _TrailStage.waiting || _stage == _TrailStage.stopped) return;
    _stageElapsed += dt;
    _visualElapsed += dt;
    _invalidStartElapsed = max(0, _invalidStartElapsed - dt);

    switch (_stage) {
      case _TrailStage.preview:
        if (_stageElapsed >= _previewDuration) {
          _enterRecall();
        }
      case _TrailStage.success:
        if (_stageElapsed >= MamaDuckTrailRules.successDurationSeconds) {
          _startRound();
        }
      case _TrailStage.failure:
        if (_stageElapsed >= MamaDuckTrailRules.failureDurationSeconds) {
          if (_failureCanContinue) {
            _startRound();
          } else {
            _stage = _TrailStage.stopped;
            onFatalFailureComplete();
          }
        }
      case _TrailStage.waiting || _TrailStage.recall || _TrailStage.stopped:
        return;
    }
  }

  double get _previewDuration {
    return _path.length * MamaDuckTrailRules.pathStepSeconds +
        MamaDuckTrailRules.holdSecondsAt(sessionElapsed) +
        MamaDuckTrailRules.recallReadyDelaySeconds;
  }

  double get _motherTravelDuration =>
      max(0, _path.length - 1) * MamaDuckTrailRules.pathStepSeconds;

  bool get _motherHasArrived => _stageElapsed >= _motherTravelDuration;

  void _startRound() {
    _path = MamaDuckTrailRules.generatePath(
      random,
      MamaDuckTrailRules.pathLengthAfterSuccesses(_completedPaths),
    );
    _entered.clear();
    _wrongCell = null;
    _dragActive = false;
    _stage = _TrailStage.preview;
    _stageElapsed = 0;
  }

  void beginDrag(Vector2 point) {
    if (_dragActive) return;
    if (_stage == _TrailStage.preview) {
      if (!_motherHasArrived) return;
      final cell = _cellAt(point);
      if (cell == null || cell != _path.first) {
        _invalidStartElapsed = 0.24;
        return;
      }
      _enterRecall();
    }
    if (_stage != _TrailStage.recall) return;
    final cell = _cellAt(point);
    if (cell == null || cell != _path.first) {
      _invalidStartElapsed = 0.24;
      return;
    }
    _dragActive = true;
    _entered
      ..clear()
      ..add(cell);
    unawaited(HapticFeedback.selectionClick());
    if (_path.length == 1) _completeSuccess();
  }

  void _enterRecall() {
    if (_stage != _TrailStage.preview) return;
    _stage = _TrailStage.recall;
    _stageElapsed = 0;
    _entered.clear();
    _wrongCell = null;
  }

  void updateDrag(Vector2 point) {
    if (_stage != _TrailStage.recall || !_dragActive) return;
    final cell = _cellAt(point);
    if (cell == null || cell == _entered.last) return;

    final nextIndex = _entered.length;
    final adjacent = _entered.last.manhattanDistanceTo(cell) == 1;
    final fresh = !_entered.contains(cell);
    final expected = MamaDuckTrailRules.isExpectedStep(
      target: _path,
      enteredCount: nextIndex,
      candidate: cell,
    );
    if (!adjacent || !fresh || !expected) {
      _completeFailure(cell);
      return;
    }

    _entered.add(cell);
    unawaited(HapticFeedback.selectionClick());
    if (_entered.length == _path.length) _completeSuccess();
  }

  void endDrag() {
    if (_stage != _TrailStage.recall || !_dragActive) return;
    if (_entered.length < _path.length) {
      _completeFailure(_entered.last);
    }
  }

  void _completeSuccess() {
    if (_stage != _TrailStage.recall) return;
    _dragActive = false;
    _stage = _TrailStage.success;
    _stageElapsed = 0;
    _completedPaths++;
    onSuccess(_path.length);
  }

  void _completeFailure(MamaDuckCell wrongCell) {
    if (_stage != _TrailStage.recall) return;
    _dragActive = false;
    _wrongCell = wrongCell;
    _stage = _TrailStage.failure;
    _stageElapsed = 0;
    _failureCanContinue = onFailure();
  }

  MamaDuckCell? _cellAt(Vector2 point) {
    final localX = point.x - boardLeft;
    final localY = point.y - boardTop;
    if (localX < 0 ||
        localY < 0 ||
        localX >= boardWidth ||
        localY >= boardHeight) {
      return null;
    }
    final column = localX ~/ tileSize;
    final row = localY ~/ tileSize;
    final insideX = localX - column * tileSize;
    final insideY = localY - row * tileSize;
    if (insideX < _inputInset ||
        insideX > tileSize - _inputInset ||
        insideY < _inputInset ||
        insideY > tileSize - _inputInset) {
      return null;
    }
    return MamaDuckCell(row, column);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderBackground(canvas);
    _renderBoard(canvas);
    _renderFeverAtmosphere(canvas);
    _renderTrails(canvas);
    _renderActors(canvas);
    _renderSuccessFeedback(canvas);
    _renderFooter(canvas);
  }

  void _renderBackground(Canvas canvas) {
    background.render(
      canvas,
      position: Vector2(0, -100),
      size: Vector2(360, 840),
      overridePaint: _pixelPaint,
    );
    final feverTier = MamaDuckTrailRules.feverTierForCombo(combo());
    _flatPaint.color = feverTier == MamaDuckFeverTier.radiant
        ? const Color(0x803A6157)
        : const Color(0xFF234A50);
    final rainDropCount = feverTier == MamaDuckFeverTier.radiant ? 8 : 24;
    for (var index = 0; index < rainDropCount; index++) {
      final x = ((index * 47 + (sessionElapsed * 34).floor()) % 380) - 10;
      final y = (index * 71) % 840 - 100;
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 2, 10),
        _flatPaint,
      );
    }
  }

  void _renderFeverAtmosphere(Canvas canvas) {
    final tier = MamaDuckTrailRules.feverTierForCombo(combo());
    if (tier == MamaDuckFeverTier.none) return;

    final pulse = 0.55 + sin(_visualElapsed * 5) * 0.15;
    _flatPaint.color = const Color(0xFFFFC744).withValues(
      alpha: tier == MamaDuckFeverTier.radiant ? pulse * 0.32 : pulse * 0.16,
    );
    canvas.drawRect(
      const Rect.fromLTWH(boardLeft, boardTop, 6, boardHeight),
      _flatPaint,
    );
    canvas.drawRect(
      const Rect.fromLTWH(boardLeft + boardWidth - 6, boardTop, 6, boardHeight),
      _flatPaint,
    );

    if (tier.index < MamaDuckFeverTier.sparkling.index) return;
    _flatPaint.color = const Color(0xFFFFE58A).withValues(alpha: pulse);
    for (var index = 0; index < 8; index++) {
      final x = 18.0 + ((index * 43 + (_visualElapsed * 18).floor()) % 324);
      final y = boardTop + 18 + ((index * 67) % 456);
      final size = index.isEven ? 3.0 : 2.0;
      canvas.drawRect(Rect.fromLTWH(x, y.toDouble(), size, size), _flatPaint);
    }
  }

  void _renderBoard(Canvas canvas) {
    terrain.render(
      canvas,
      position: Vector2(boardLeft, boardTop),
      size: Vector2(boardWidth, boardHeight),
      overridePaint: _pixelPaint,
    );
    _renderCellGuides(canvas);

    if (_invalidStartElapsed > 0) {
      final start = _cellRect(_path.first);
      _flatPaint
        ..color = const Color(0xFFFFD466)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawRect(start.deflate(3), _flatPaint);
      _flatPaint.style = PaintingStyle.fill;
    }
  }

  void _renderCellGuides(Canvas canvas) {
    // Keep the authored water and mud continuous, while restoring the old
    // two-pixel seams that make the 5x7 drag cells immediately readable.
    _flatPaint
      ..color = const Color(0xA3322D29)
      ..style = PaintingStyle.fill;
    for (var column = 1; column < MamaDuckTrailRules.columnCount; column++) {
      final x = boardLeft + column * tileSize - 1;
      canvas.drawRect(Rect.fromLTWH(x, boardTop, 2, boardHeight), _flatPaint);
    }
    for (var row = 1; row < MamaDuckTrailRules.rowCount; row++) {
      final y = boardTop + row * tileSize - 1;
      canvas.drawRect(Rect.fromLTWH(boardLeft, y, boardWidth, 2), _flatPaint);
    }
  }

  void _renderTrails(Canvas canvas) {
    if (_stage == _TrailStage.preview) {
      final stepDuration = _motherTravelDuration;
      final count = _stageElapsed < stepDuration
          ? min(
              _path.length,
              (_stageElapsed / MamaDuckTrailRules.pathStepSeconds).floor() + 1,
            )
          : _path.length;
      final fadeStart =
          _previewDuration - MamaDuckTrailRules.recallReadyDelaySeconds;
      final opacity = _stageElapsed <= fadeStart
          ? 1.0
          : (1 -
                    (_stageElapsed - fadeStart) /
                        MamaDuckTrailRules.recallReadyDelaySeconds)
                .clamp(0.0, 1.0);
      _renderPath(canvas, _path.take(count).toList(), row: 0, opacity: opacity);
    }

    if (_stage == _TrailStage.recall || _stage == _TrailStage.success) {
      _renderPath(canvas, _entered, row: 1, directionPath: _path);
    }

    if (_stage == _TrailStage.failure) {
      _renderPath(canvas, _path, row: 0, opacity: 0.48);
      _renderPath(canvas, _entered, row: 1, directionPath: _path);
      final wrong = _wrongCell;
      if (wrong != null) {
        _renderFootprint(canvas, wrong, row: 2);
      }
    }
  }

  void _renderPath(
    Canvas canvas,
    List<MamaDuckCell> path, {
    required int row,
    double opacity = 1,
    List<MamaDuckCell>? directionPath,
  }) {
    final directions = directionPath ?? path;
    // The final cell is where the mother waits, so it intentionally has no
    // footprint. Every visible footprint points from its cell to the next
    // cell in the actual route.
    final footprintCount = min(path.length, max(0, directions.length - 1));
    for (var index = 0; index < footprintCount; index++) {
      final angle = _directionAngle(directions, index);
      _renderFootprint(
        canvas,
        path[index],
        row: row,
        angle: angle,
        opacity: opacity,
      );
    }
  }

  double _directionAngle(List<MamaDuckCell> path, int index) {
    if (index < 0 || index >= path.length - 1) return 0;
    final from = path[index];
    final to = path[index + 1];
    final rowDelta = to.row - from.row;
    final columnDelta = to.column - from.column;
    // The authored canonical footprint points down. Rotate it into the
    // direction of travel instead of trusting the atlas' mislabeled compass
    // columns (which contain a duplicated vertical frame).
    if (rowDelta < 0) return pi;
    if (columnDelta > 0) return -pi / 2;
    if (rowDelta > 0) return 0;
    return pi / 2;
  }

  void _renderFootprint(
    Canvas canvas,
    MamaDuckCell cell, {
    required int row,
    double angle = 0,
    double opacity = 1,
  }) {
    final feverTier = MamaDuckTrailRules.feverTierForCombo(combo());
    final isGoldenPlayerTrail = row == 1 && feverTier != MamaDuckFeverTier.none;
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none
      ..color = (isGoldenPlayerTrail ? const Color(0xFFFFC53D) : Colors.white)
          .withValues(alpha: opacity);
    final center = _cellCenter(cell);
    canvas.save();
    canvas.translate(center.x, center.y);
    canvas.rotate(angle);
    // Column 0 is the canonical downward-facing footprint for each color
    // row. Rendering it with an explicit rotation keeps every arrow honest
    // even though the remaining atlas columns are not reliable directions.
    footprints[row * 4].render(
      canvas,
      position: Vector2.all(-24),
      size: Vector2.all(48),
      overridePaint: paint,
    );
    canvas.restore();
  }

  void _renderActors(Canvas canvas) {
    if (_stage == _TrailStage.preview) {
      final endCenter = _cellCenter(_path.last);
      final progress = (_stageElapsed / MamaDuckTrailRules.pathStepSeconds)
          .clamp(0.0, max(0, _path.length - 1).toDouble());
      final segment = progress.floor().clamp(0, _path.length - 1);
      final motherCenter = segment >= _path.length - 1
          ? endCenter
          : _cellCenter(_path[segment]) +
                (_cellCenter(_path[segment + 1]) -
                        _cellCenter(_path[segment])) *
                    (progress - segment);
      final sprite = progress >= _path.length - 1
          ? motherIdle
          : motherWalk[(_stageElapsed / 0.11).floor() % motherWalk.length];
      _renderSprite(canvas, sprite, motherCenter - Vector2.all(36), 72);
      return;
    }

    if (_stage == _TrailStage.recall) {
      _renderSprite(
        canvas,
        motherIdle,
        _cellCenter(_path.last) - Vector2.all(36),
        72,
      );
      return;
    }

    if (_stage == _TrailStage.success) {
      final hasArrived =
          _stageElapsed >= MamaDuckTrailRules.successTravelDurationSeconds;
      final cheerFrame =
          (((_stageElapsed - MamaDuckTrailRules.successTravelDurationSeconds) /
                      0.125)
                  .floor())
              .clamp(0, 11) %
          motherCheer.length;
      _renderSprite(
        canvas,
        hasArrived ? motherCheer[cheerFrame] : motherIdle,
        _cellCenter(_path.last) - Vector2.all(36),
        72,
      );
      final duckCenters = _successDuckCenters();
      for (var index = 0; index < duckCenters.length; index++) {
        final type = index % ducklingWalkTypes.length;
        final walk = ducklingWalkTypes[type];
        final cheer = ducklingCheerTypes[type];
        final lateFollower = index >= _path.length - 3;
        final cheerElapsed = max(
          0.0,
          _stageElapsed -
              MamaDuckTrailRules.successTravelDurationSeconds -
              index * 0.025,
        );
        final sprite = hasArrived
            ? cheer[(cheerElapsed / 0.125).floor() % cheer.length]
            : walk[((_stageElapsed / (lateFollower ? 0.06 : 0.09)).floor() +
                      index) %
                  walk.length];
        _renderSprite(canvas, sprite, duckCenters[index] - Vector2.all(36), 72);
      }
      return;
    }

    if (_stage == _TrailStage.failure) {
      final wrong = _wrongCell ?? _path.first;
      final center = _cellCenter(wrong);
      final wolfPosition = Vector2(
        (center.x - 48).clamp(0, 264),
        (center.y - 58).clamp(58, 514),
      );
      final frame = MamaDuckTrailGame.wolfFailureFrameForElapsed(_stageElapsed);
      _renderSprite(canvas, wolfFailure[frame], wolfPosition, 96);
    }
  }

  void _renderSuccessFeedback(Canvas canvas) {
    if (_stage != _TrailStage.success) return;
    final currentCombo = combo();
    final tier = MamaDuckTrailRules.feverTierForCombo(currentCombo);
    final elapsedAfterArrival =
        _stageElapsed - MamaDuckTrailRules.successTravelDurationSeconds;
    if (elapsedAfterArrival < 0 || elapsedAfterArrival > 1.15) return;

    final opacity = (1 - elapsedAfterArrival / 1.15).clamp(0.0, 1.0);
    final score = MamaDuckTrailRules.scoreForSuccess(
      pathLength: _path.length,
      comboAfterSuccess: currentCombo,
    );
    final destination = _cellCenter(_path.last);
    final label = tier == MamaDuckFeverTier.none
        ? '+$score'
        : 'FEVER!  +$score';
    _drawText(
      canvas,
      label,
      Offset(destination.x, max(88, destination.y - 52)),
      color:
          (tier == MamaDuckFeverTier.none
                  ? const Color(0xFFFFE4A3)
                  : const Color(0xFFFFC53D))
              .withValues(alpha: opacity),
      fontSize: tier == MamaDuckFeverTier.none ? 13 : 15,
    );
  }

  List<Vector2> _successDuckCenters() {
    final progress =
        (_stageElapsed / MamaDuckTrailRules.successTravelDurationSeconds).clamp(
          0.0,
          1.0,
        );
    final leaderDistance =
        MamaDuckTrailRules.successLeaderFinalDistance(_path.length) * progress;
    final centers = <Vector2>[];
    for (var index = 0; index < _path.length - 1; index++) {
      final distance = MamaDuckTrailRules.travelingDuckDistance(
        leaderDistance: leaderDistance,
        followerIndex: index,
      );
      if (distance < 0) continue;
      centers.add(_pointAlongPathDistance(_path, distance));
    }
    return List.unmodifiable(centers);
  }

  Vector2 _pointAlongPathDistance(List<MamaDuckCell> path, double distance) {
    if (path.length == 1) return _cellCenter(path.first);
    final scaled = distance.clamp(0.0, (path.length - 1).toDouble());
    final segment = scaled.floor().clamp(0, path.length - 2);
    final local = scaled - segment;
    final start = _cellCenter(path[segment]);
    return start + (_cellCenter(path[segment + 1]) - start) * local;
  }

  void _renderFooter(Canvas canvas) {
    final rescuedCount = _completedPaths;
    final visibleCount = MamaDuckTrailRules.visibleRescuedDuckCount(
      rescuedCount,
    );
    final hiddenCount = MamaDuckTrailRules.hiddenRescuedDuckCount(rescuedCount);
    final paradeFrame =
        (_visualElapsed / 0.18).floor() % ducklingWalkTypes.first.length;

    _drawText(
      canvas,
      'COMBO ${combo()}',
      const Offset(180, 582),
      color:
          MamaDuckTrailRules.feverTierForCombo(combo()) ==
              MamaDuckFeverTier.none
          ? const Color(0xFFFFC54D)
          : const Color(0xFFFFE27A),
    );

    if (visibleCount == 0 || _stage == _TrailStage.success) return;
    const startX = 24.0;
    const spacing = 52.0;
    for (var index = 0; index < visibleCount; index++) {
      final bob = ((index + (_visualElapsed / 0.18).floor()).isEven)
          ? 0.0
          : 2.0;
      _renderSprite(
        canvas,
        ducklingWalkTypes[index % ducklingWalkTypes.length][(paradeFrame +
                index) %
            ducklingWalkTypes.first.length],
        Vector2(startX + index * spacing, 592 + bob),
        48,
      );
    }
    if (hiddenCount > 0) {
      _drawText(
        canvas,
        '+$hiddenCount',
        const Offset(316, 616),
        color: const Color(0xFFFFE6A0),
        fontSize: 14,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset center, {
    required Color color,
    double fontSize = 12,
  }) {
    _textPainter.text = TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Galmuri',
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: color,
      ),
    );
    _textPainter.layout();
    _textPainter.paint(
      canvas,
      center - Offset(_textPainter.width / 2, _textPainter.height / 2),
    );
  }

  Rect _cellRect(MamaDuckCell cell) => Rect.fromLTWH(
    boardLeft + cell.column * tileSize,
    boardTop + cell.row * tileSize,
    tileSize,
    tileSize,
  );

  Vector2 _cellCenter(MamaDuckCell cell) => Vector2(
    boardLeft + cell.column * tileSize + tileSize / 2,
    boardTop + cell.row * tileSize + tileSize / 2,
  );

  void _renderSprite(
    Canvas canvas,
    Sprite sprite,
    Vector2 position,
    double displaySize,
  ) {
    sprite.render(
      canvas,
      position: Vector2(position.x.roundToDouble(), position.y.roundToDouble()),
      size: Vector2.all(displaySize),
      overridePaint: _pixelPaint,
    );
  }
}
