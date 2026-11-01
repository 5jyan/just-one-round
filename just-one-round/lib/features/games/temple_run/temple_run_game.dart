import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Flame adapter for 집에 좀 가자. Rules and route generation remain pure and
/// deterministic; this class owns only clock, input, result, and scene state.
class TempleRunGame extends FlameGame
    with DragCallbacks
    implements MiniGameController {
  TempleRunGame({
    required this.onFinished,
    Duration gameDuration = TempleRunRules.gameDuration,
    this.countdownDuration = TempleRunRules.countdownDuration,
    Random? random,
    TempleRunCourse? course,
    this.useImageAssets = false,
    this.accelerometerEvents,
    this.enableTiltInput = true,
  }) : gameDuration = gameDuration.compareTo(TempleRunRules.maximumDuration) > 0
           ? TempleRunRules.maximumDuration
           : gameDuration.isNegative
           ? Duration.zero
           : gameDuration,
       _random = random ?? Random(),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: gameDuration.inSeconds.clamp(0, 300),
           countdownNumber: countdownDuration.inSeconds,
         ),
       ) {
    _course =
        course ??
        TempleRunCourseGenerator(_random).generate(duration: this.gameDuration);
    _phase = countdownDuration == Duration.zero
        ? MiniGamePhase.playing
        : MiniGamePhase.countdown;
  }

  static final logicalSize = Vector2(
    TempleRunRules.logicalWidth,
    TempleRunRules.logicalHeight,
  );

  /// Keeps the authored 360px lane geometry while exposing extra vertical
  /// world space on tall portrait devices. A little horizontal overscan is
  /// allowed on short/wide portrait windows so rails never touch the edge.
  @visibleForTesting
  static Vector2 viewportResolutionForCanvas(Vector2 canvasSize) {
    if (canvasSize.x <= 0 || canvasSize.y <= 0) {
      return logicalSize.clone();
    }
    const maxVisibleWidth = 430.0;
    const maxVisibleHeight = 820.0;
    final canvasAspect = canvasSize.y / canvasSize.x;
    final logicalAspect =
        TempleRunRules.logicalHeight / TempleRunRules.logicalWidth;
    if (canvasAspect < logicalAspect) {
      final visibleWidth = (TempleRunRules.logicalHeight / canvasAspect).clamp(
        TempleRunRules.logicalWidth,
        maxVisibleWidth,
      );
      return Vector2(visibleWidth, TempleRunRules.logicalHeight);
    }
    final visibleHeight = (TempleRunRules.logicalWidth * canvasAspect).clamp(
      TempleRunRules.logicalHeight,
      maxVisibleHeight,
    );
    return Vector2(TempleRunRules.logicalWidth, visibleHeight);
  }

  final Duration gameDuration;
  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  /// The current gameplay pass defaults to the simple code-native scene. Set
  /// this opt-in flag when the final art bundle is intentionally being tested;
  /// required assets then fail loudly instead of silently becoming geometry.
  final bool useImageAssets;

  /// Injectable for deterministic tests and simulator controls. When null,
  /// the game subscribes to the platform accelerometer on load.
  final Stream<AccelerometerEvent>? accelerometerEvents;
  final bool enableTiltInput;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final TempleRunCourse _course;
  TempleRunArt? _scene;
  Map<String, ui.Image>? _ownedImages;
  MiniGamePhase _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _distanceMeters = 0.0;
  var _lateralPosition = TempleRunRules.centerLane.toDouble();
  var _smoothedTilt = 0.0;
  double? _tiltNeutralX;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  var _jumpRemaining = 0.0;
  var _slideRemaining = 0.0;
  var _magnetRemaining = 0.0;
  var _boostRemaining = 0.0;
  var _protectedRecoveryRemaining = 0.0;
  var _shieldCharges = 0;
  var _coins = 0;
  var _collisions = 0;
  var _obstacleIndex = 0;
  var _coinIndex = 0;
  var _powerUpIndex = 0;
  final Set<int> _collectedCoinIndices = <int>{};
  final Set<int> _expiredCoinIndices = <int>{};
  final Set<int> _consumedCoinIndices = <int>{};
  final Set<int> _collectedPowerUpIndices = <int>{};
  final Set<int> _expiredPowerUpIndices = <int>{};
  final Set<int> _consumedPowerUpIndices = <int>{};
  var _turnIndex = 0;
  var _armedTurnIndex = -1;
  TempleRunSwipe? _pendingVerticalSwipe;
  var _pendingVerticalExpiresAt = 0.0;
  TempleRunTurnDirection? _bendDirection;
  var _bendProgress = 0.0;
  var _turnAnimationElapsed = TempleRunRules.turnAnimationDurationSeconds;
  var _cameraYaw = 0.0;
  var _runnerFrame = 0.0;
  var _gesturePointerId = -1;
  Vector2? _gestureStart;
  Vector2? _gestureEnd;
  var _gestureCommitted = false;
  var _isTerminal = false;
  var _isInterrupted = false;
  var _resultReported = false;
  var _disposed = false;
  var _arrivalVisible = false;
  var _lastPublishedSecond = -1;
  var _lastPublishedScore = -1;
  var _visibleResolution = logicalSize.clone();

  MiniGamePhase get gamePhase => _phase;
  TempleRunCourse get courseForTesting => _course;
  double get distanceMetersForTesting => _distanceMeters;
  double get playingElapsedForTesting => _playingElapsed;
  int get laneForTesting => TempleRunRules.clampLane(_lateralPosition.round());
  double get visualLaneForTesting => _lateralPosition;
  double get lateralPositionForTesting => _lateralPosition;
  double get smoothedTiltForTesting => _smoothedTilt;
  double? get tiltNeutralForTesting => _tiltNeutralX;
  double get cameraYawForTesting => _cameraYaw;
  double get countdownElapsedForTesting => _countdownElapsed;
  int get coinsForTesting => _coins;
  Set<int> get collectedCoinIndicesForTesting =>
      Set.unmodifiable(_collectedCoinIndices);
  Set<int> get expiredCoinIndicesForTesting =>
      Set.unmodifiable(_expiredCoinIndices);
  Set<int> get collectedPowerUpIndicesForTesting =>
      Set.unmodifiable(_collectedPowerUpIndices);
  Set<int> get expiredPowerUpIndicesForTesting =>
      Set.unmodifiable(_expiredPowerUpIndices);
  int get collisionsForTesting => _collisions;
  double get jumpRemainingForTesting => _jumpRemaining;
  double get slideRemainingForTesting => _slideRemaining;
  double get magnetRemainingForTesting => _magnetRemaining;
  double get boostRemainingForTesting => _boostRemaining;
  double get protectedRecoveryRemainingForTesting =>
      _protectedRecoveryRemaining;
  int get shieldChargesForTesting => _shieldCharges;
  bool get resultReportedForTesting => _resultReported;
  bool get isInterruptedForTesting => _isInterrupted;
  TempleRunTurn? get activeTurnForTesting => _currentTurn;
  bool get turnArmedForTesting => _armedTurnIndex == _turnIndex;
  TempleRunSwipe? get pendingVerticalSwipeForTesting => _pendingVerticalSwipe;
  int get completedTurnCountForTesting => _turnIndex;
  double get turnAnimationProgressForTesting =>
      1.0 - _bendProgress.clamp(0.0, 1.0);
  double get turnAnimationElapsedForTesting => _turnAnimationElapsed;

  @override
  Color backgroundColor() => const Color(0xFF102A26);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);

    final Map<String, ui.Image> loaded;
    if (useImageAssets) {
      // Decode through the same explicit bundle loader used by the preview.
      // This completes before the scene and countdown are mounted and avoids
      // leaving a pending Flame cache future when Flutter is running the game
      // under the widget test harness.
      loaded = await TempleRunArt.loadImageAssets(bundle: rootBundle);
    } else {
      loaded = <String, ui.Image>{};
    }
    if (_disposed) {
      _disposeImages(loaded);
      return;
    }
    _ownedImages = loaded;
    _scene = TempleRunArt(
      images: loaded,
      useImageAssets: useImageAssets,
      viewportWidth: _visibleResolution.x,
      viewportHeight: _visibleResolution.y,
    );
    await world.add(_scene!);
    if (_disposed) {
      _disposeOwnedImages();
      return;
    }
    _startTiltInput();
    if (!_isTerminal && countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
    }
    _refreshScene();
    _publishHud(force: true);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _configureViewport(size);
  }

  void _configureViewport(Vector2 canvasSize) {
    _visibleResolution = viewportResolutionForCanvas(canvasSize);
    camera.viewport = FixedResolutionViewport(resolution: _visibleResolution);
    camera.viewfinder.position = Vector2(
      _visibleResolution.x / 2,
      _visibleResolution.y / 2,
    );
    _scene?.resizeToViewport(_visibleResolution);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_disposed || _isTerminal || dt <= 0) {
      return;
    }
    _advance(dt);
  }

  @override
  void onRemove() {
    _cancelTiltInput();
    super.onRemove();
    scheduleMicrotask(_disposeOwnedImages);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_phase != MiniGamePhase.playing ||
        _isTerminal ||
        _gesturePointerId != -1) {
      return;
    }
    _gesturePointerId = event.pointerId;
    _gestureCommitted = false;
    _gestureStart = camera.globalToLocal(event.canvasPosition);
    _gestureEnd = _gestureStart?.clone();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _gesturePointerId ||
        _phase != MiniGamePhase.playing) {
      return;
    }
    _gestureEnd = camera.globalToLocal(event.canvasEndPosition);
    if (!_gestureCommitted) {
      final start = _gestureStart;
      final end = _gestureEnd;
      if (start != null && end != null) {
        final swipe = TempleRunRules.swipeForDelta(
          dx: end.x - start.x,
          dy: end.y - start.y,
        );
        if (swipe != null) {
          // Crossing the threshold consumes the gesture even when the action
          // is intentionally ignored at a lane edge or during another
          // maneuver. A held finger must never repeat an action on later
          // drag-update callbacks.
          _handleSwipe(swipe);
          _gestureCommitted = true;
        }
      }
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId != _gesturePointerId) return;
    _commitGesture();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (event.pointerId == _gesturePointerId) _clearGesture();
  }

  /// Test adapters can send exactly one logical swipe through the same path as
  /// touch input.
  @visibleForTesting
  bool handleSwipeForTesting(TempleRunSwipe swipe) => _handleSwipe(swipe);

  @visibleForTesting
  bool queueSwipeForTesting(Vector2 delta) {
    final swipe = TempleRunRules.swipeForDelta(dx: delta.x, dy: delta.y);
    return swipe == null ? false : _handleSwipe(swipe);
  }

  /// Feeds one platform-shaped sample through the same calibration and filter
  /// used by the real stream. This is intentionally an input adapter, not a
  /// position teleport, so soak tests exercise the bounded response.
  @visibleForTesting
  void pushAccelerometerEventForTesting(AccelerometerEvent event) {
    _handleAccelerometerEvent(event);
  }

  @visibleForTesting
  void setTiltNeutralForTesting(double x) {
    _tiltNeutralX = x;
    _smoothedTilt = 0;
  }

  @visibleForTesting
  void advanceTimeForTesting(Duration elapsed) {
    if (_disposed || _isTerminal || elapsed <= Duration.zero) return;
    _advance(elapsed.inMicroseconds / Duration.microsecondsPerSecond);
  }

  @visibleForTesting
  void forceFinishForTesting(GameEndType endType) => _finish(endType);

  @override
  void interrupt() {
    if (_isTerminal) return;
    _isTerminal = true;
    _isInterrupted = true;
    _phase = MiniGamePhase.finished;
    _cancelTiltInput();
    _clearInputBuffers();
    _clearGesture();
    _publishHud(force: true);
    pauseEngine();
  }

  @override
  void disposeController() {
    if (_disposed) return;
    _disposed = true;
    _cancelTiltInput();
    _clearInputBuffers();
    _clearGesture();
    final scene = _scene;
    if (scene == null || (!scene.isMounted && !scene.isLoading)) {
      _disposeOwnedImages();
    }
    hud.dispose();
  }

  void _disposeOwnedImages() {
    final images = _ownedImages;
    _ownedImages = null;
    if (images == null) return;
    _disposeImages(images);
  }

  static void _disposeImages(Map<String, ui.Image> images) {
    for (final image in images.values) {
      image.dispose();
    }
  }

  void _advance(double dt) {
    var remaining = dt;
    if (_phase == MiniGamePhase.countdown) {
      final countdownSeconds =
          countdownDuration.inMicroseconds / Duration.microsecondsPerSecond;
      final countdownLeft = max(0.0, countdownSeconds - _countdownElapsed);
      final countdownStep = min(remaining, countdownLeft);
      _countdownElapsed += countdownStep;
      remaining -= countdownStep;
      _refreshScene(deltaSeconds: countdownStep);
      if (_countdownElapsed >= countdownSeconds) {
        _phase = MiniGamePhase.playing;
        _publishHud(force: true);
      } else {
        _publishHud();
        return;
      }
    }
    if (_phase != MiniGamePhase.playing || remaining <= 0) return;
    _advancePlaying(remaining);
  }

  void _startTiltInput() {
    if (!enableTiltInput || _disposed || _isTerminal) return;
    final stream = accelerometerEvents;
    try {
      _accelerometerSubscription =
          (stream ??
                  accelerometerEventStream(
                    samplingPeriod: SensorInterval.gameInterval,
                  ))
              .listen(_handleAccelerometerEvent, onError: (_) {});
    } on Object {
      // Desktop and web test hosts can expose no motion platform. The runtime
      // remains constructible there; tests may inject bounded tilt samples
      // through the adapter above. Real narrow-terrain play still needs tilt.
      _accelerometerSubscription = null;
    }
  }

  void _cancelTiltInput() {
    final subscription = _accelerometerSubscription;
    _accelerometerSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  void _handleAccelerometerEvent(AccelerometerEvent event) {
    if (_disposed || _isTerminal) return;
    if (_phase == MiniGamePhase.countdown) {
      final neutral = _tiltNeutralX;
      _tiltNeutralX = neutral == null
          ? event.x
          : neutral + ((event.x - neutral) * 0.08);
      _smoothedTilt = 0;
      return;
    }
    if (_phase != MiniGamePhase.playing) return;
    final neutral = _tiltNeutralX ??= event.x;
    // Android's portrait X axis points to the phone's right. Lowering the
    // right edge produces negative gravity, so negate it for rightward motion.
    final corrected = -(event.x - neutral);
    final magnitude = corrected.abs();
    final target = magnitude <= TempleRunRules.tiltDeadzone
        ? 0.0
        : (corrected.sign *
              ((magnitude - TempleRunRules.tiltDeadzone) /
                      (TempleRunRules.tiltFullScaleAcceleration -
                          TempleRunRules.tiltDeadzone))
                  .clamp(0.0, 1.0));
    _smoothedTilt += (target - _smoothedTilt) * TempleRunRules.tiltSmoothing;
  }

  void _updateLateralPosition(double elapsedSeconds) {
    if (_phase != MiniGamePhase.playing || _smoothedTilt == 0) return;
    _lateralPosition = TempleRunRules.clampPosition(
      _lateralPosition +
          (_smoothedTilt *
              TempleRunRules.maximumLateralSpeedInLanesPerSecond *
              elapsedSeconds),
    );
  }

  void _clearInputBuffers() {
    _armedTurnIndex = -1;
    _pendingVerticalSwipe = null;
    _pendingVerticalExpiresAt = 0;
  }

  void _advancePlaying(double dt) {
    var remaining = dt;
    final limit = gameDuration.inMicroseconds / Duration.microsecondsPerSecond;
    while (remaining > 0 && _phase == MiniGamePhase.playing) {
      final timeLeft = max(0.0, limit - _playingElapsed);
      if (timeLeft <= 0) {
        _finish(GameEndType.timeUp);
        break;
      }
      final step = min(remaining, min(timeLeft, 1 / 120));
      final previousDistance = _distanceMeters;
      final speed =
          TempleRunRules.speedForElapsed(_playingElapsed) *
          (_boostRemaining > 0 ? TempleRunRules.boostSpeedMultiplier : 1);
      _playingElapsed += step;
      _distanceMeters += speed * step;
      _updateLateralPosition(step);
      _runnerFrame += step * 8;
      _jumpRemaining = max(0.0, _jumpRemaining - step);
      _slideRemaining = max(0.0, _slideRemaining - step);
      _processPendingVerticalInput();
      _magnetRemaining = max(0.0, _magnetRemaining - step);
      _protectedRecoveryRemaining = max(
        0.0,
        _protectedRecoveryRemaining - step,
      );
      final hadBoost = _boostRemaining > 0;
      _boostRemaining = max(0.0, _boostRemaining - step);
      if (hadBoost && _boostRemaining == 0) {
        _protectedRecoveryRemaining = TempleRunRules.boostExitRecoverySeconds;
        _jumpRemaining = min(_jumpRemaining, 0.03);
        _slideRemaining = min(_slideRemaining, 0.03);
      }
      _processTurns(previousDistance);
      _updateTurnAnimation(step);
      if (_phase == MiniGamePhase.playing) _processPickups();
      if (_phase == MiniGamePhase.playing) _processObstacles(previousDistance);
      _refreshScene(deltaSeconds: step);
      _publishHud();
      remaining -= step;
      if (_phase == MiniGamePhase.playing && _playingElapsed >= limit) {
        _finish(GameEndType.timeUp);
      }
    }
  }

  void _processTurns(double previousDistance) {
    while (_turnIndex < _course.turns.length) {
      final turn = _course.turns[_turnIndex];
      final protectedRun =
          _boostRemaining > 0 || _protectedRecoveryRemaining > 0;
      if (_distanceMeters >= turn.windowStartMeters && protectedRun) {
        // A boost or its guaranteed recovery grace may auto-arm a turn, but
        // execution still waits for the actual junction distance so the
        // renderer never yaws while the runner is metres away.
        _armedTurnIndex = _turnIndex;
      }
      if (_distanceMeters < turn.distanceMeters) {
        if (_distanceMeters > turn.windowEndMeters &&
            _armedTurnIndex != _turnIndex) {
          _finish(GameEndType.gameOver);
        }
        return;
      }
      if (_armedTurnIndex == _turnIndex) {
        _executeTurn(turn);
        continue;
      }
      // A gesture that arrives during the short tail after the junction can
      // still save the turn. The bend starts at the current distance, never at
      // the earlier arm gesture.
      if (previousDistance <= turn.windowEndMeters &&
          _distanceMeters > turn.windowEndMeters) {
        _finish(GameEndType.gameOver);
      }
      return;
    }
  }

  void _executeTurn(TempleRunTurn turn) {
    _armedTurnIndex = -1;
    _turnIndex++;
    _bendDirection = turn.direction;
    _bendProgress = 1;
    _turnAnimationElapsed = 0;
    _cameraYaw = 0;
  }

  void _updateTurnAnimation(double elapsedSeconds) {
    if (_bendDirection == null ||
        (_bendProgress <= 0 &&
            _turnAnimationElapsed >=
                TempleRunRules.turnAnimationDurationSeconds)) {
      return;
    }
    _turnAnimationElapsed = min(
      TempleRunRules.turnAnimationDurationSeconds,
      _turnAnimationElapsed + elapsedSeconds,
    );
    final progress =
        _turnAnimationElapsed / TempleRunRules.turnAnimationDurationSeconds;
    // Keep the remaining animation fraction linear in the shared scene
    // contract. The renderer applies the cubic ease to this remaining value
    // so camera yaw, runner basis, and road projection use the same angle.
    _bendProgress = 1.0 - progress;
    final eased = TempleRunRules.turnEaseOut(progress);
    final sign = _bendDirection == TempleRunTurnDirection.left ? -1.0 : 1.0;
    _cameraYaw = sign * TempleRunRules.turnAngleRadians * eased;
    if (progress >= 1.0) {
      _bendProgress = 0;
      _cameraYaw = sign * TempleRunRules.turnAngleRadians;
    }
  }

  void _processPendingVerticalInput() {
    final pending = _pendingVerticalSwipe;
    if (pending == null) return;
    if (_playingElapsed >= _pendingVerticalExpiresAt) {
      _pendingVerticalSwipe = null;
      _publishHud(force: true);
      return;
    }
    if (_jumpRemaining > 0 || _slideRemaining > 0) return;
    _pendingVerticalSwipe = null;
    _startVerticalPose(pending);
    _publishHud(force: true);
  }

  void _processPickups() {
    // Activate an overlapping magnet before scanning coins so it also pulls a
    // coin whose pickup window begins on this same simulation step.
    _processPowerUpPickups();
    _processCoinPickups();
  }

  void _processCoinPickups() {
    final coins = _course.coins;
    final trailingEdge =
        _distanceMeters - TempleRunRules.coinPickupWindowMeters;
    while (_coinIndex < coins.length &&
        (coins[_coinIndex].distanceMeters < trailingEdge ||
            _consumedCoinIndices.contains(_coinIndex))) {
      final index = _coinIndex++;
      if (_consumedCoinIndices.add(index)) _expiredCoinIndices.add(index);
    }

    final leadingEdge = _distanceMeters + TempleRunRules.coinPickupWindowMeters;
    for (var index = _coinIndex; index < coins.length; index++) {
      final coin = coins[index];
      if (coin.distanceMeters > leadingEdge) break;
      if (coin.distanceMeters < trailingEdge ||
          _consumedCoinIndices.contains(index)) {
        continue;
      }
      final laneOverlap = TempleRunRules.overlapsLanePosition(
        lane: coin.lane,
        positionInLanes: _lateralPosition,
        halfWidthInLanes: TempleRunRules.pickupHalfWidthInLanes,
      );
      if (_magnetRemaining > 0 || laneOverlap) {
        _collectedCoinIndices.add(index);
        _consumedCoinIndices.add(index);
        if (_coins < TempleRunRules.maximumCoinsPerRun) _coins++;
      }
    }
  }

  void _processPowerUpPickups() {
    final powerUps = _course.powerUps;
    final trailingEdge =
        _distanceMeters - TempleRunRules.powerUpPickupWindowMeters;
    while (_powerUpIndex < powerUps.length &&
        (powerUps[_powerUpIndex].distanceMeters < trailingEdge ||
            _consumedPowerUpIndices.contains(_powerUpIndex))) {
      final index = _powerUpIndex++;
      if (_consumedPowerUpIndices.add(index)) _expiredPowerUpIndices.add(index);
    }

    final leadingEdge =
        _distanceMeters + TempleRunRules.powerUpPickupWindowMeters;
    for (var index = _powerUpIndex; index < powerUps.length; index++) {
      final powerUp = powerUps[index];
      if (powerUp.distanceMeters > leadingEdge) break;
      if (powerUp.distanceMeters < trailingEdge ||
          _consumedPowerUpIndices.contains(index) ||
          !TempleRunRules.overlapsLanePosition(
            lane: powerUp.lane,
            positionInLanes: _lateralPosition,
            halfWidthInLanes: TempleRunRules.pickupHalfWidthInLanes,
          )) {
        continue;
      }
      _collectedPowerUpIndices.add(index);
      _consumedPowerUpIndices.add(index);
      switch (powerUp.kind) {
        case TempleRunPowerUpKind.magnet:
          _magnetRemaining = TempleRunRules.magnetDurationSeconds;
        case TempleRunPowerUpKind.shield:
          _shieldCharges = 1;
        case TempleRunPowerUpKind.boost:
          _boostRemaining = TempleRunRules.boostDurationSeconds;
          _protectedRecoveryRemaining = 0;
      }
    }
  }

  void _processObstacles(double previousDistance) {
    while (_obstacleIndex < _course.obstacles.length &&
        _course.obstacles[_obstacleIndex].distanceMeters <=
            _distanceMeters + TempleRunRules.collisionWindowMeters) {
      final obstacle = _course.obstacles[_obstacleIndex];
      if (obstacle.isNarrowPath) {
        final start = obstacle.distanceMeters;
        final end = obstacle.endDistanceMeters;
        if (_distanceMeters < start) return;
        if (_distanceMeters <= end + .05) {
          if (_boostRemaining <= 0 &&
              _protectedRecoveryRemaining <= 0 &&
              TempleRunRules.overlapsObstaclePosition(
                obstacle: obstacle,
                positionInLanes: _lateralPosition,
              )) {
            // Narrow terrain is a positional route failure, but it still
            // counts as the player's collision with the course. A shield
            // cannot absorb it because it is not a solid obstacle.
            _collisions++;
            _finish(GameEndType.gameOver);
          }
          return;
        }
        _obstacleIndex++;
        continue;
      }
      _obstacleIndex++;
      if (obstacle.distanceMeters <
          previousDistance - TempleRunRules.collisionWindowMeters) {
        continue;
      }
      final spatiallyOverlaps = TempleRunRules.overlapsObstaclePosition(
        obstacle: obstacle,
        positionInLanes: _lateralPosition,
      );
      if (!spatiallyOverlaps ||
          _boostRemaining > 0 ||
          _protectedRecoveryRemaining > 0 ||
          TempleRunRules.survivesObstacleAtPosition(
            obstacle: obstacle,
            positionInLanes: _lateralPosition,
            jumpRemainingSeconds: _jumpRemaining,
            slideRemainingSeconds: _slideRemaining,
          )) {
        continue;
      }
      if (obstacle.isSolid && _shieldCharges > 0) {
        _shieldCharges = 0;
        _collisions++;
        continue;
      }
      _collisions++;
      _finish(GameEndType.gameOver);
      return;
    }
  }

  bool _handleSwipe(TempleRunSwipe swipe) {
    if (_phase != MiniGamePhase.playing || _isTerminal) return false;
    final turn = _turnForInput;
    if ((swipe == TempleRunSwipe.left || swipe == TempleRunSwipe.right) &&
        turn != null) {
      final expected = turn.direction == TempleRunTurnDirection.left
          ? TempleRunSwipe.left
          : TempleRunSwipe.right;
      // The latest horizontal gesture in the reservation window wins. It is
      // stored by turn identity and only executes at the actual junction.
      _armedTurnIndex = swipe == expected ? _turnIndex : -1;
      _publishHud(force: true);
      return true;
    }
    switch (swipe) {
      case TempleRunSwipe.left:
      case TempleRunSwipe.right:
        // Phone swipes are reserved for announced corners. Continuous tilt
        // remains the only way to move laterally between junctions.
        return false;
      case TempleRunSwipe.up:
      case TempleRunSwipe.down:
        if (_jumpRemaining > 0 || _slideRemaining > 0) {
          if (_pendingVerticalSwipe == null) {
            _pendingVerticalSwipe = swipe;
            _pendingVerticalExpiresAt =
                _playingElapsed + TempleRunRules.verticalInputBufferSeconds;
            _publishHud(force: true);
            return true;
          }
          return false;
        }
        _startVerticalPose(swipe);
    }
    _refreshScene();
    return true;
  }

  void _startVerticalPose(TempleRunSwipe swipe) {
    switch (swipe) {
      case TempleRunSwipe.up:
        if (_slideRemaining <= 0 && _jumpRemaining <= 0) {
          _jumpRemaining = TempleRunRules.jumpDurationSeconds;
        }
      case TempleRunSwipe.down:
        if (_jumpRemaining <= 0 && _slideRemaining <= 0) {
          _slideRemaining = TempleRunRules.slideDurationSeconds;
        }
      case TempleRunSwipe.left:
      case TempleRunSwipe.right:
        break;
    }
  }

  void _commitGesture() {
    final start = _gestureStart;
    final end = _gestureEnd;
    final alreadyCommitted = _gestureCommitted;
    _clearGesture();
    if (alreadyCommitted || start == null || end == null) return;
    final swipe = TempleRunRules.swipeForDelta(
      dx: end.x - start.x,
      dy: end.y - start.y,
    );
    if (swipe != null) _handleSwipe(swipe);
  }

  void _clearGesture() {
    _gesturePointerId = -1;
    _gestureStart = null;
    _gestureEnd = null;
    _gestureCommitted = false;
  }

  void _finish(GameEndType endType) {
    if (_isTerminal || _isInterrupted) return;
    _isTerminal = true;
    _phase = MiniGamePhase.finished;
    _arrivalVisible = endType == GameEndType.timeUp;
    _cancelTiltInput();
    _clearInputBuffers();
    _clearGesture();
    _refreshScene(failure: endType == GameEndType.gameOver);
    _publishHud(force: true);
    pauseEngine();
    if (_resultReported) return;
    _resultReported = true;
    onFinished(
      GameResult(
        score: TempleRunRules.scoreFor(
          distanceMeters: _distanceMeters,
          coins: _coins,
        ),
        starsCollected: _coins,
        collisions: _collisions,
        duration: Duration(
          milliseconds: (_playingElapsed * 1000).round().clamp(
            1,
            max(1, gameDuration.inMilliseconds),
          ),
        ),
        endType: endType,
      ),
    );
  }

  TempleRunTurn? get _currentTurn {
    if (_turnIndex >= _course.turns.length) return null;
    final turn = _course.turns[_turnIndex];
    return turn.contains(_distanceMeters) ? turn : null;
  }

  TempleRunTurn? get _turnForInput {
    if (_turnIndex >= _course.turns.length) return null;
    final turn = _course.turns[_turnIndex];
    return turn.contains(_distanceMeters) ? turn : null;
  }

  TempleRunTurn? get _turnForScene {
    final current = _currentTurn;
    if (current != null) return current;
    if (_turnIndex >= _course.turns.length) return null;
    final next = _course.turns[_turnIndex];
    final distanceUntil = next.distanceMeters - _distanceMeters;
    return distanceUntil >= 0 && distanceUntil <= 80 ? next : null;
  }

  void _refreshScene({bool failure = false, double deltaSeconds = 0}) {
    final scene = _scene;
    if (scene == null) return;
    final sceneTurn = _turnForScene;
    scene.updateScene(
      course: _course,
      distanceMeters: _distanceMeters,
      lane: laneForTesting,
      visualLane: _lateralPosition,
      phoneTilt: _smoothedTilt,
      jumpRemaining: _jumpRemaining,
      slideRemaining: _slideRemaining,
      runnerFrame: _runnerFrame,
      activeTurn: sceneTurn,
      completedTurnCount: _turnIndex,
      // [activeTurn] carries the approaching junction. Bend progress and yaw
      // remain zero until the armed turn reaches its actual distance.
      bendProgress: _bendProgress,
      bendDirection: _bendDirection,
      cameraYaw: _cameraYaw,
      guardianVisible: _phase == MiniGamePhase.countdown,
      pursuersVisible: _phase == MiniGamePhase.playing && !_arrivalVisible,
      failureVisible: failure,
      arrivalVisible: _arrivalVisible,
      shieldVisible: _shieldCharges > 0,
      boostVisible: _boostRemaining > 0,
      magnetVisible: _magnetRemaining > 0,
      collectedCoinIndices: _collectedCoinIndices,
      collectedPowerUpIndices: _collectedPowerUpIndices,
      consumedCoinIndices: _consumedCoinIndices,
      consumedPowerUpIndices: _consumedPowerUpIndices,
      deltaSeconds: deltaSeconds,
    );
  }

  void _publishHud({bool force = false}) {
    final score = TempleRunRules.scoreFor(
      distanceMeters: _distanceMeters,
      coins: _coins,
    );
    final elapsedSecond = _playingElapsed.floor();
    final countdown = max(
      0,
      (countdownDuration.inMicroseconds / Duration.microsecondsPerSecond -
              _countdownElapsed)
          .ceil(),
    );
    // Turns are deliberately unannounced.  The route, camera bend, and
    // player's buffered swipe are the feedback; a direction label would make
    // the late-game chain easier than the requested read-and-react challenge.
    final message = _pendingVerticalSwipe == null
        ? null
        : '${_pendingVerticalSwipe == TempleRunSwipe.up ? '점프' : '슬라이드'} 대기';
    if (!force &&
        score == _lastPublishedScore &&
        elapsedSecond == _lastPublishedSecond &&
        hud.value.countdownNumber == countdown &&
        hud.value.message == message) {
      return;
    }
    _lastPublishedScore = score;
    _lastPublishedSecond = elapsedSecond;
    hud.value = MiniGameHudState(
      phase: _phase,
      score: score,
      elapsedSeconds: elapsedSecond,
      remainingSeconds: max(0, gameDuration.inSeconds - elapsedSecond),
      countdownNumber: countdown,
      distance: _distanceMeters.floor(),
      message: message,
    );
  }
}
