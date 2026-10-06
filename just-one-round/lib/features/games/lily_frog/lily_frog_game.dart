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
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_field_generator.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_frog_rules.dart';

enum LilyFrogMotionPhase { orbiting, airborne, landing, failing }

typedef _LilyTrajectory = ({
  Point<double> start,
  Point<double> end,
  int? padId,
});

class LilyFrogGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  LilyFrogGame({
    required this.onFinished,
    this.gameDuration = LilyFrogRules.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    this.enableHaptics = true,
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

  static final logicalSize = Vector2(360, 640);
  static final overscanSize = Vector2(360, 960);
  static const overscanTop = 160.0;
  static const maxVisibleHeight = 800.0;
  static const currentPadTargetY = 480.0;
  static const frogDisplaySize = 56.0;

  final Duration gameDuration;
  final Duration countdownDuration;
  final bool enableHaptics;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final LilyFieldGenerator _fieldGenerator;
  late final _FrogComponent _frog;
  late final Sprite _pondSprite;
  late final SpriteSheet _frogSheet;
  late final SpriteSheet _lilySheet;
  late final SpriteSheet _goldenLilySheet;
  late final List<Sprite> _flySprites;
  late final List<Sprite> _flyCollectSprites;
  late final List<Sprite> _rippleSprites;
  late final List<Sprite> _splashSprites;
  final Map<int, _LilyPadComponent> _pads = {};
  final Map<int, int> _safeChildByPadId = {};
  final Map<int, Future<LilyPadSpec>> _pendingChildByPadId = {};
  final Map<int, _FlyComponent> _flies = {};
  final Set<int> _visitedPadIds = {0};
  var _phase = MiniGamePhase.countdown;
  var _motionPhase = LilyFrogMotionPhase.orbiting;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _orbitTheta = -pi / 2;
  var _orbitTravelSinceLanding = 0.0;
  var _launchedBeforeFullOrbit = false;
  var _combo = 0;
  var _comboShakeRemaining = 0.0;
  var _landingElapsed = 0.0;
  var _failureElapsed = 0.0;
  var _flightElapsed = 0.0;
  var _score = 0;
  var _newLandings = 0;
  var _riskyLandings = 0;
  var _fliesCaught = 0;
  var _revisitedLandings = 0;
  var _goldenLandings = 0;
  var _launchCount = 0;
  var _currentPadId = 0;
  var _departedPadId = 0;
  var _nextPadId = 3;
  var _nextFlyId = 1;
  var _hasFinished = false;
  var _rejectedAimPulse = 0.0;
  var _flightVelocity = const Point<double>(0, 0);
  _LilyTrajectory? _activeFlightGuide;
  var _feedbackMessage = '';
  var _feedbackRemaining = 0.0;
  var _scrollRemaining = 0.0;

  static Vector2 viewportResolutionForCanvas(Vector2 canvasSize) {
    if (canvasSize.x <= 0 || canvasSize.y <= 0) return logicalSize.clone();
    final visibleHeight = (canvasSize.y * logicalSize.x / canvasSize.x).clamp(
      logicalSize.y,
      maxVisibleHeight,
    );
    return Vector2(logicalSize.x, visibleHeight);
  }

  void _configureViewport(Vector2 canvasSize) {
    camera.viewport = FixedResolutionViewport(
      resolution: viewportResolutionForCanvas(canvasSize),
    );
    camera.viewfinder.position = logicalSize / 2;
  }

  @override
  Color backgroundColor() => const Color(0xFF071F2C);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);
    _fieldGenerator = LilyFieldGenerator(_random);
    final loaded = await images.loadAll([
      'lily_frog/pond_background.png',
      'lily_frog/frog_actions_atlas.png',
      'lily_frog/lily_pad_atlas.png',
      'lily_frog/golden_lily_pad_atlas.png',
      'lily_frog/fly_sheet.png',
      'lily_frog/fly_collect_fx_atlas.png',
      'lily_frog/water_fx_atlas.png',
    ]);
    _pondSprite = Sprite(loaded[0]);
    _frogSheet = SpriteSheet(image: loaded[1], srcSize: Vector2.all(56));
    _lilySheet = SpriteSheet(image: loaded[2], srcSize: Vector2.all(256));
    _goldenLilySheet = SpriteSheet(image: loaded[3], srcSize: Vector2.all(256));
    final flySheet = SpriteSheet(image: loaded[4], srcSize: Vector2.all(32));
    final flyCollectSheet = SpriteSheet(
      image: loaded[5],
      srcSize: Vector2.all(64),
    );
    final waterSheet = SpriteSheet(image: loaded[6], srcSize: Vector2.all(64));
    _flySprites = [
      for (var column = 0; column < 4; column++) flySheet.getSprite(0, column),
    ];
    _flyCollectSprites = [
      for (var column = 0; column < 5; column++)
        flyCollectSheet.getSprite(0, column),
    ];
    _rippleSprites = [
      for (var column = 0; column < 4; column++)
        waterSheet.getSprite(0, column),
    ];
    _splashSprites = [
      for (var column = 0; column < 4; column++)
        waterSheet.getSprite(1, column),
    ];
    await world.add(
      _PondComponent(
        position: Vector2(0, -overscanTop),
        size: overscanSize.clone(),
        sprite: _pondSprite,
      ),
    );

    const startBase = LilyPadSpec(
      id: 0,
      center: Point(122, 500),
      diameter: 208,
      clockwise: false,
      angularSpeed: 1.35,
      variant: 0,
      risky: false,
      progressIndex: 0,
    );
    const firstBase = LilyPadSpec(
      id: 1,
      center: Point(238, 312),
      diameter: 192,
      clockwise: true,
      angularSpeed: 1.35,
      variant: 1,
      risky: false,
      progressIndex: 1,
    );
    const secondBase = LilyPadSpec(
      id: 2,
      center: Point(122, 144),
      diameter: 176,
      clockwise: false,
      angularSpeed: 1.35,
      variant: 2,
      risky: false,
      progressIndex: 2,
    );
    Point<double> expectedLandingPoint(LilyPadSpec from, LilyPadSpec target) =>
        LilyFrogRules.bestTangentLandingPoint(
          fromCenter: from.center,
          orbitRadius: from.orbitRadius,
          clockwise: from.clockwise,
          targetCenter: target.center,
          targetLandingRadius: target.landingRadius,
        ) ??
        LilyFrogRules.orbitPosition(
          center: target.center,
          radius: target.orbitRadius,
          theta: -pi / 2,
        );

    final startLandingPoint = LilyFrogRules.orbitPosition(
      center: startBase.center,
      radius: startBase.orbitRadius,
      theta: -pi / 2,
    );
    final start = startBase.copyWith(
      clockwise: LilyFrogRules.optimalClockwiseForNextJump(
        fromCenter: startBase.center,
        orbitRadius: startBase.orbitRadius,
        landingPoint: startLandingPoint,
        angularSpeed: startBase.angularSpeed,
        targetCenter: firstBase.center,
        targetLandingRadius: firstBase.landingRadius,
        fallbackClockwise: startBase.clockwise,
      ),
      expectedLandingPoint: startLandingPoint,
    );
    final firstLandingPoint = expectedLandingPoint(start, firstBase);
    final firstTarget = firstBase.copyWith(
      clockwise: LilyFrogRules.optimalClockwiseForNextJump(
        fromCenter: firstBase.center,
        orbitRadius: firstBase.orbitRadius,
        landingPoint: firstLandingPoint,
        angularSpeed: firstBase.angularSpeed,
        targetCenter: secondBase.center,
        targetLandingRadius: secondBase.landingRadius,
        fallbackClockwise: firstBase.clockwise,
      ),
      expectedLandingPoint: firstLandingPoint,
    );
    final secondTarget = secondBase.copyWith(
      expectedLandingPoint: expectedLandingPoint(firstTarget, secondBase),
    );
    await _addPad(start);
    await _addPad(firstTarget);
    await _addPad(secondTarget);
    _safeChildByPadId[start.id] = firstTarget.id;
    _safeChildByPadId[firstTarget.id] = secondTarget.id;
    await _ensureLookahead(start, depth: LilyFrogRules.prebuiltSafeLookahead);
    _frog = _FrogComponent(
      size: Vector2.all(frogDisplaySize),
      orbitSprites: _frogRow(0),
      jumpSprites: _frogRow(1),
      landingSprites: _frogRow(2),
      resultSprites: _frogRow(3),
    );
    _syncFrogToOrbit();
    await world.add(_frog);
    await world.add(_TrajectoryGuideComponent(game: this));

    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _publishHud(force: true);
    }
  }

  List<Sprite> _frogRow(int row) => [
    for (var column = 0; column < 4; column++)
      _frogSheet.getSprite(row, column),
  ];

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _configureViewport(size);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _comboShakeRemaining = max(0, _comboShakeRemaining - dt);
    final shake = _comboShakeRemaining / 0.24;
    final shakeStrength = 3.5 + _comboEffectTier(_combo) * 1.9;
    camera.viewfinder.position =
        logicalSize / 2 +
        Vector2(
          sin(_comboShakeRemaining * 105) * shakeStrength * shake,
          cos(_comboShakeRemaining * 77) * shakeStrength * 0.6 * shake,
        );
    if (_rejectedAimPulse > 0) {
      _rejectedAimPulse = max(0, _rejectedAimPulse - dt);
    }
    if (_feedbackRemaining > 0) {
      _feedbackRemaining = max(0, _feedbackRemaining - dt);
    }
    switch (_phase) {
      case MiniGamePhase.countdown:
        _updateCountdown(dt);
      case MiniGamePhase.playing:
        _updatePlaying(dt);
      case MiniGamePhase.finished:
        return;
    }
  }

  void _updateCountdown(double dt) {
    final speed = LilyFrogRules.difficultyAt(0).angularSpeed;
    _setAllPadAngularSpeeds(speed);
    _advanceOrbit(dt, speed);
    _countdownElapsed += dt;
    final total =
        countdownDuration.inMicroseconds / Duration.microsecondsPerSecond;
    if (_countdownElapsed >= total) {
      _phase = MiniGamePhase.playing;
      _orbitTravelSinceLanding = 0;
      _publishHud(force: true);
    } else {
      _publishHud();
    }
  }

  void _updatePlaying(double dt) {
    _playingElapsed += dt;
    final maximum =
        gameDuration.inMicroseconds / Duration.microsecondsPerSecond;
    if (_playingElapsed >= maximum) {
      _playingElapsed = maximum;
      _finish(timedOut: true);
      return;
    }
    _setAllPadAngularSpeeds(
      LilyFrogRules.difficultyAt(_playingElapsed).angularSpeed,
    );
    switch (_motionPhase) {
      case LilyFrogMotionPhase.orbiting:
        _updateOrbiting(dt);
      case LilyFrogMotionPhase.airborne:
        _updateAirborne(dt);
      case LilyFrogMotionPhase.landing:
        _updateLanding(dt);
      case LilyFrogMotionPhase.failing:
        _updateFailing(dt);
    }
    _publishHud();
  }

  void _updateOrbiting(double dt) {
    final speed = LilyFrogRules.difficultyAt(_playingElapsed).angularSpeed;
    _advanceOrbit(dt, speed);
  }

  void _advanceOrbit(double dt, double speed) {
    final current = _pads[_currentPadId]!.spec;
    _pads[_currentPadId]!.setAngularSpeed(speed);
    _orbitTheta += (current.clockwise ? -1 : 1) * speed * dt;
    _orbitTheta %= 2 * pi;
    if (_phase == MiniGamePhase.playing) {
      _orbitTravelSinceLanding += speed * dt;
      if (_orbitTravelSinceLanding >= 2 * pi) _combo = 0;
    }
    _syncFrogToOrbit();
  }

  void _setAllPadAngularSpeeds(double speed) {
    for (final pad in _pads.values) {
      pad.setAngularSpeed(speed);
    }
  }

  void _syncFrogToOrbit() {
    final current = _pads[_currentPadId]?.spec;
    if (current == null) return;
    final position = LilyFrogRules.orbitPosition(
      center: current.center,
      radius: current.orbitRadius,
      theta: _orbitTheta,
    );
    _frog.position = Vector2(position.x, position.y);
    _frog.angle = 0;
    _frog.isAirborne = false;
  }

  void _updateAirborne(double dt) {
    final previous = Point<double>(_frog.position.x, _frog.position.y);
    _flightElapsed += dt;
    final next = Point<double>(
      previous.x + _flightVelocity.x * dt,
      previous.y + _flightVelocity.y * dt,
    );
    final landing = _firstLanding(previous, next);
    if (landing != null) {
      final (:pad, :t) = landing;
      final hit = Point<double>(
        previous.x + (next.x - previous.x) * t,
        previous.y + (next.y - previous.y) * t,
      );
      _collectFlies(previous, hit);
      _frog.position = Vector2(hit.x, hit.y);
      _landOn(pad);
      return;
    }
    _collectFlies(previous, next);
    _frog.position = Vector2(next.x, next.y);
    _frog.jumpProgress = (_flightElapsed / LilyFrogRules.maximumFlightSeconds)
        .clamp(0, 1);
    if (_flightElapsed >= LilyFrogRules.maximumFlightSeconds) {
      _activeFlightGuide = null;
      _motionPhase = LilyFrogMotionPhase.failing;
      _failureElapsed = 0;
      _frog.isFailing = true;
      if (enableHaptics) unawaited(HapticFeedback.heavyImpact());
      world.add(
        _WaterFxComponent(
          position: _frog.position.clone(),
          sprites: _splashSprites,
        ),
      );
    }
  }

  ({_LilyPadComponent pad, double t})? _firstLanding(
    Point<double> start,
    Point<double> end, {
    int? excludedPadId,
  }) {
    _LilyPadComponent? bestPad;
    var bestT = double.infinity;
    final excluded = excludedPadId ?? _departedPadId;
    for (final pad in _pads.values) {
      if (pad.spec.id == excluded) continue;
      final hit = LilyFrogRules.firstSegmentCircleHit(
        start: start,
        end: end,
        center: pad.spec.center,
        radius: pad.spec.landingRadius,
      );
      if (hit != null && hit < bestT) {
        bestT = hit;
        bestPad = pad;
      }
    }
    return bestPad == null ? null : (pad: bestPad, t: bestT);
  }

  _LilyTrajectory? _predictedLandingPath() {
    if (_phase == MiniGamePhase.finished ||
        _motionPhase != LilyFrogMotionPhase.orbiting) {
      return null;
    }
    final current = _pads[_currentPadId]?.spec;
    if (current == null) return null;
    final start = Point<double>(_frog.position.x, _frog.position.y);
    final direction = LilyFrogRules.tangentDirection(
      theta: _orbitTheta,
      clockwise: current.clockwise,
    );
    final travel =
        LilyFrogRules.launchSpeed * LilyFrogRules.maximumFlightSeconds;
    final maximumEnd = Point<double>(
      start.x + direction.x * travel,
      start.y + direction.y * travel,
    );
    final landing = _firstLanding(
      start,
      maximumEnd,
      excludedPadId: _currentPadId,
    );
    if (landing == null) {
      return (start: start, end: maximumEnd, padId: null);
    }
    final end = Point<double>(
      start.x + (maximumEnd.x - start.x) * landing.t,
      start.y + (maximumEnd.y - start.y) * landing.t,
    );
    return (start: start, end: end, padId: landing.pad.spec.id);
  }

  _LilyTrajectory? _trajectoryPath() {
    if (_motionPhase == LilyFrogMotionPhase.airborne) {
      return _activeFlightGuide;
    }
    if (_launchCount >= LilyFrogRules.trajectoryGuideLaunches) return null;
    return _predictedLandingPath();
  }

  void _collectFlies(Point<double> start, Point<double> end) {
    for (final fly in List<_FlyComponent>.of(_flies.values)) {
      final hit = LilyFrogRules.firstSegmentCircleHit(
        start: start,
        end: end,
        center: fly.spec.center,
        radius: LilyFrogRules.flyPickupRadius,
      );
      if (hit == null) continue;
      final contact = Point<double>(
        start.x + (end.x - start.x) * hit,
        start.y + (end.y - start.y) * hit,
      );
      _flies.remove(fly.spec.id);
      fly.removeFromParent();
      world.add(
        _FlyCollectFxComponent(
          position: Vector2(contact.x, contact.y),
          sprites: _flyCollectSprites,
        ),
      );
      world.add(
        _ScorePopupComponent(
          position: Vector2(contact.x, contact.y - 24),
          label: '파리 +${LilyFrogRules.flyScore}',
          color: const Color(0xFFFFE47A),
        ),
      );
      _fliesCaught++;
      _score = LilyFrogRules.clampSubmittedScore(
        _score + LilyFrogRules.flyScore,
      );
      if (enableHaptics) unawaited(HapticFeedback.mediumImpact());
    }
  }

  void _landOn(_LilyPadComponent pad) {
    _activeFlightGuide = null;
    _currentPadId = pad.spec.id;
    _orbitTheta = atan2(
      _frog.position.y - pad.spec.center.y,
      _frog.position.x - pad.spec.center.x,
    );
    _motionPhase = LilyFrogMotionPhase.landing;
    _landingElapsed = 0;
    _orbitTravelSinceLanding = 0;
    _frog
      ..isAirborne = false
      ..isLanding = true
      ..jumpProgress = 0;
    world.add(
      _WaterFxComponent(
        position: _frog.position.clone(),
        sprites: _rippleSprites,
      ),
    );
    pad.triggerLanding();
    if (_visitedPadIds.add(pad.spec.id)) {
      _combo = _launchedBeforeFullOrbit ? _combo + 1 : 1;
      if (_combo >= 2) {
        for (final effect
            in world.children.whereType<_ComboImpactComponent>()) {
          effect.removeFromParent();
        }
        _comboShakeRemaining = 0.24;
        world.add(_ComboImpactComponent(game: this, combo: _combo));
      }
      if (enableHaptics) {
        unawaited(
          _combo >= 2
              ? HapticFeedback.heavyImpact()
              : HapticFeedback.lightImpact(),
        );
      }
      _newLandings++;
      if (pad.spec.risky && !pad.spec.golden) _riskyLandings++;
      if (pad.spec.golden) _goldenLandings++;
      final landingScore = LilyFrogRules.landingScore(
        risky: pad.spec.risky && !pad.spec.golden,
        caughtFly: false,
        golden: pad.spec.golden,
        combo: _combo,
      );
      _score = LilyFrogRules.clampSubmittedScore(_score + landingScore);
      _showFeedback(
        pad.spec.golden ? '황금 연잎! +$landingScore' : '+$landingScore',
        pad.spec.golden ? const Color(0xFFFFD54A) : Colors.white,
      );
      unawaited(
        _ensureLookahead(pad.spec, depth: LilyFrogRules.prebuiltSafeLookahead),
      );
    } else {
      _combo = 0;
      if (enableHaptics) unawaited(HapticFeedback.lightImpact());
      _revisitedLandings++;
    }
    _scrollRemaining = currentPadTargetY - pad.spec.center.y;
  }

  void _completeLanding() {
    if (_motionPhase != LilyFrogMotionPhase.landing) return;
    if (_scrollRemaining.abs() > 0.01) {
      _translateField(_scrollRemaining);
    }
    _scrollRemaining = 0;
    _frog.isLanding = false;
    _motionPhase = LilyFrogMotionPhase.orbiting;
    _pruneField();
    _syncFrogToOrbit();
  }

  void _showFeedback(String label, Color color) {
    _feedbackMessage = label;
    _feedbackRemaining = 0.9;
    world.add(
      _ScorePopupComponent(
        position: _frog.position + Vector2(0, -34),
        label: label,
        color: color,
      ),
    );
  }

  void _updateLanding(double dt) {
    _landingElapsed += dt;
    if (_scrollRemaining.abs() > 0.01) {
      final step = _scrollRemaining * min(1, dt / 0.08);
      _translateField(step);
      _scrollRemaining -= step;
    }
    final speed = LilyFrogRules.difficultyAt(_playingElapsed).angularSpeed;
    _advanceOrbit(dt, speed);
    if (_landingElapsed >= LilyFrogRules.landingLockSeconds &&
        _scrollRemaining.abs() <= 0.5) {
      _completeLanding();
    }
  }

  void _updateFailing(double dt) {
    _failureElapsed += dt;
    if (_failureElapsed >= 0.38) _finish(timedOut: false);
  }

  Future<void> _ensureLookahead(
    LilyPadSpec from, {
    int depth = LilyFrogRules.prebuiltSafeLookahead,
  }) async {
    var cursor = from;
    for (var step = 0; step < depth; step++) {
      final existingChildId = _safeChildByPadId[cursor.id];
      final existingChild = existingChildId == null
          ? null
          : _pads[existingChildId]?.spec;
      cursor = existingChild ?? await _generateAheadOnce(cursor);
    }
  }

  Future<LilyPadSpec> _generateAheadOnce(LilyPadSpec from) async {
    final existingChildId = _safeChildByPadId[from.id];
    final existingChild = existingChildId == null
        ? null
        : _pads[existingChildId]?.spec;
    if (existingChild != null) return existingChild;
    final pending = _pendingChildByPadId[from.id];
    if (pending != null) return pending;
    final generated = _generateAhead(from);
    _pendingChildByPadId[from.id] = generated;
    try {
      return await generated;
    } finally {
      if (identical(_pendingChildByPadId[from.id], generated)) {
        _pendingChildByPadId.remove(from.id);
      }
    }
  }

  Future<LilyPadSpec> _generateAhead(LilyPadSpec from) async {
    final existing = _pads.values
        .map((pad) => pad.spec)
        .toList(growable: false);
    final effectiveFrom = LilyPadSpec(
      id: from.id,
      center: from.center,
      diameter: from.diameter,
      clockwise: from.clockwise,
      angularSpeed: LilyFrogRules.difficultyAt(_playingElapsed).angularSpeed,
      variant: from.variant,
      risky: from.risky,
      progressIndex: from.progressIndex,
      golden: from.golden,
      expectedLandingPoint: from.expectedLandingPoint,
    );
    final primaryGeneration = _fieldGenerator.generate(
      from: effectiveFrom,
      nextPadId: _nextPadId,
      nextFlyId: _nextFlyId,
      elapsedSeconds: _playingElapsed,
      existing: existing,
    );
    var generation = primaryGeneration;
    final generations = <LilyGeneration>[generation];
    if (generation.continuation == null) {
      // Prepare one extra safe target before adding the primary target. This
      // lets the primary target start with its optimized direction instead of
      // appearing with a random direction and changing on a later jump.
      final nextGeneration = _fieldGenerator.generate(
        from: generation.safe,
        nextPadId: _nextPadId + 1,
        nextFlyId: _nextFlyId + generation.flies.length,
        elapsedSeconds: _playingElapsed,
        existing: [...existing, ...generation.pads],
      );
      generation = LilyGeneration(
        safe: generation.safe.copyWith(
          clockwise:
              nextGeneration.preparedFromClockwise ?? generation.safe.clockwise,
        ),
        preparedFromClockwise: generation.preparedFromClockwise,
        risky: generation.risky,
        continuation: generation.continuation,
        flies: generation.flies,
      );
      generations.add(nextGeneration);
    }
    final preparedDirection = generation.preparedFromClockwise;
    if (preparedDirection != null) {
      // Rotation is prepared during look-ahead, before the newly generated
      // route is added. Launch and landing never change a pad's direction.
      _pads[from.id]?.prepareClockwise(preparedDirection);
    }
    final padComponents = [
      for (final generated in generations)
        for (final pad in generated.pads) _buildPad(pad),
    ];
    for (final component in padComponents) {
      _pads[component.spec.id] = component;
    }
    _safeChildByPadId[from.id] = generation.safe.id;
    if (generation.continuation case final continuation?) {
      _safeChildByPadId[generation.safe.id] = continuation.id;
      if (generation.risky case final golden?) {
        _safeChildByPadId[golden.id] = continuation.id;
      }
    }
    if (generations.length > 1) {
      final nextGeneration = generations[1];
      _safeChildByPadId[generation.safe.id] = nextGeneration.safe.id;
      if (nextGeneration.continuation case final continuation?) {
        _safeChildByPadId[nextGeneration.safe.id] = continuation.id;
        if (nextGeneration.risky case final golden?) {
          _safeChildByPadId[golden.id] = continuation.id;
        }
      }
    }
    _nextPadId += generations.fold<int>(
      0,
      (count, generated) => count + generated.pads.length,
    );
    final flyComponents = <_FlyComponent>[];
    var generatedFlyCount = 0;
    for (final generated in generations) {
      for (final fly in generated.flies) {
        final component = _FlyComponent(spec: fly, sprites: _flySprites);
        _flies[fly.id] = component;
        flyComponents.add(component);
        generatedFlyCount++;
      }
    }
    await world.addAll([...padComponents, ...flyComponents]);
    _nextFlyId += generatedFlyCount;
    return generation.safe;
  }

  Future<void> _addPad(LilyPadSpec spec) async {
    final component = _buildPad(spec);
    _pads[spec.id] = component;
    await world.add(component);
  }

  _LilyPadComponent _buildPad(LilyPadSpec spec) {
    final sizeIndex = switch (spec.diameter.round()) {
      <= 128 => 0,
      <= 160 => 1,
      <= 176 => 2,
      <= 192 => 3,
      _ => 4,
    };
    final component = _LilyPadComponent(
      spec: spec,
      sprite: spec.golden
          ? _goldenLilySheet.getSprite(0, spec.variant % 3)
          : _lilySheet.getSprite(spec.variant % 3, sizeIndex),
    );
    return component;
  }

  void _translateField(double dy) {
    for (final pad in _pads.values) {
      pad.translate(0, dy);
    }
    for (final fly in _flies.values) {
      fly.translate(0, dy);
    }
  }

  void _pruneField() {
    final removablePads = _pads.values
        .where(
          (pad) =>
              pad.spec.id != _currentPadId &&
              pad.spec.center.y > logicalSize.y + 120,
        )
        .toList();
    for (final pad in removablePads) {
      _pads.remove(pad.spec.id);
      pad.removeFromParent();
    }
    final livePadIds = _pads.keys.toSet();
    final removableFlies = _flies.values
        .where(
          (fly) =>
              !livePadIds.contains(fly.spec.padId) ||
              fly.spec.center.y > logicalSize.y + 120,
        )
        .toList();
    for (final fly in removableFlies) {
      _flies.remove(fly.spec.id);
      fly.removeFromParent();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    event.continuePropagation = false;
    _tryLaunch();
  }

  bool _tryLaunch() {
    if (_phase != MiniGamePhase.playing ||
        _motionPhase == LilyFrogMotionPhase.airborne ||
        _motionPhase == LilyFrogMotionPhase.failing) {
      return false;
    }
    // A tap received on the landing frame should become the next jump
    // immediately. Settle the camera shift first so the launch uses the same
    // world coordinates as a tap received one frame later.
    if (_motionPhase == LilyFrogMotionPhase.landing) _completeLanding();
    if (_motionPhase != LilyFrogMotionPhase.orbiting) return false;
    final current = _pads[_currentPadId]!.spec;
    final direction = LilyFrogRules.tangentDirection(
      theta: _orbitTheta,
      clockwise: current.clockwise,
    );
    final start = Point<double>(_frog.position.x, _frog.position.y);
    final travel =
        LilyFrogRules.launchSpeed * LilyFrogRules.maximumFlightSeconds;
    final end = Point<double>(
      start.x + direction.x * travel,
      start.y + direction.y * travel,
    );
    final safeOpening = _playingElapsed < LilyFrogRules.safeOpeningSeconds;
    if (safeOpening && _firstLanding(start, end) == null) {
      _rejectedAimPulse = 0.28;
      if (enableHaptics) unawaited(HapticFeedback.selectionClick());
      return false;
    }
    _departedPadId = _currentPadId;
    _launchedBeforeFullOrbit = _orbitTravelSinceLanding < 2 * pi;
    final predictedPath = _predictedLandingPath();
    _activeFlightGuide = _launchCount < LilyFrogRules.trajectoryGuideLaunches
        ? predictedPath
        : null;
    _launchCount++;
    _flightVelocity = Point<double>(
      direction.x * LilyFrogRules.launchSpeed,
      direction.y * LilyFrogRules.launchSpeed,
    );
    _flightElapsed = 0;
    _motionPhase = LilyFrogMotionPhase.airborne;
    _frog
      ..isAirborne = true
      ..isLanding = false
      ..isFailing = false
      ..jumpProgress = 0;
    if (enableHaptics) unawaited(HapticFeedback.selectionClick());
    return true;
  }

  void _finish({required bool timedOut}) {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _motionPhase = timedOut
        ? LilyFrogMotionPhase.orbiting
        : LilyFrogMotionPhase.failing;
    _publishHud(force: true);
    onFinished(
      GameResult(
        score: LilyFrogRules.clampSubmittedScore(_score),
        starsCollected: _fliesCaught,
        collisions: timedOut ? 0 : 1,
        duration: Duration(milliseconds: (_playingElapsed * 1000).round()),
        endType: timedOut ? GameEndType.timeUp : GameEndType.gameOver,
      ),
    );
  }

  void _publishHud({bool force = false}) {
    final elapsed = _playingElapsed.floor();
    final remaining = max(0, gameDuration.inSeconds - elapsed);
    final countdown = max(
      0,
      countdownDuration.inSeconds - _countdownElapsed.floor(),
    );
    final comboRemainingPercent = _combo > 0
        ? ((1 - _orbitTravelSinceLanding / (2 * pi)).clamp(0.0, 1.0) * 50)
                  .ceil() *
              2
        : null;
    final previous = hud.value;
    if (!force &&
        previous.phase == _phase &&
        previous.score == _score &&
        previous.elapsedSeconds == elapsed &&
        previous.remainingSeconds == remaining &&
        previous.countdownNumber == countdown &&
        previous.distance == _combo &&
        previous.comboRemainingPercent == comboRemainingPercent) {
      return;
    }
    hud.value = MiniGameHudState(
      phase: _phase,
      score: _score,
      elapsedSeconds: elapsed,
      remainingSeconds: remaining,
      countdownNumber: countdown,
      distance: _combo,
      comboRemainingPercent: comboRemainingPercent,
      message: _rejectedAimPulse > 0
          ? '물결 방향을 보고 다시 탭!'
          : _feedbackRemaining > 0
          ? _feedbackMessage
          : null,
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

  @override
  void disposeController() {
    if (!_hasFinished) interrupt();
    hud.dispose();
  }

  bool tapForTesting() => _tryLaunch();

  /// Used only by the non-interactive home card. It waits for the real
  /// trajectory solver to point at the generated safe child, then performs the
  /// same launch as a player tap.
  bool launchWhenSafeForPreview() {
    if (_phase != MiniGamePhase.playing ||
        _motionPhase != LilyFrogMotionPhase.orbiting) {
      return false;
    }
    final safeChildId = _safeChildByPadId[_currentPadId];
    final path = _predictedLandingPath();
    if (safeChildId == null || path?.padId != safeChildId) return false;
    return _tryLaunch();
  }

  bool launchSafeImmediatelyForPreview() {
    if (_phase != MiniGamePhase.playing ||
        _motionPhase != LilyFrogMotionPhase.orbiting) {
      return false;
    }
    final safeChildId = _safeChildByPadId[_currentPadId];
    if (safeChildId == null) return false;
    final theta = launchThetaForPadForTesting(safeChildId);
    if (theta == null) return false;
    _orbitTheta = theta;
    _syncFrogToOrbit();
    return _tryLaunch();
  }

  int get currentProgressForPreview =>
      _pads[_currentPadId]?.spec.progressIndex ?? 0;

  void setElapsedSecondsForPreview(double seconds) {
    if (_phase != MiniGamePhase.playing) return;
    final maximum = gameDuration.inMilliseconds / 1000;
    _playingElapsed = seconds.clamp(0, maximum - 0.001).toDouble();
    _publishHud(force: true);
  }

  bool launchUnsafeForPreview() {
    if (_phase != MiniGamePhase.playing ||
        _motionPhase != LilyFrogMotionPhase.orbiting) {
      return false;
    }
    _playingElapsed = max(_playingElapsed, LilyFrogRules.safeOpeningSeconds);
    for (var index = 0; index < 360; index++) {
      _orbitTheta = 2 * pi * index / 360;
      _syncFrogToOrbit();
      if (_predictedLandingPath()?.padId == null) return _tryLaunch();
    }
    return false;
  }

  void setOrbitThetaForTesting(double theta) {
    _orbitTheta = theta;
    _syncFrogToOrbit();
  }

  double? launchThetaForPadForTesting(int padId) {
    final target = _pads[padId]?.spec;
    final current = _pads[_currentPadId]?.spec;
    if (target == null || current == null) return null;
    double? bestTheta;
    var bestMiss = double.infinity;
    for (var index = 0; index < 1440; index++) {
      final theta = 2 * pi * index / 1440;
      final start = LilyFrogRules.orbitPosition(
        center: current.center,
        radius: current.orbitRadius,
        theta: theta,
      );
      final direction = LilyFrogRules.tangentDirection(
        theta: theta,
        clockwise: current.clockwise,
      );
      final travel =
          LilyFrogRules.launchSpeed * LilyFrogRules.maximumFlightSeconds;
      final end = Point<double>(
        start.x + direction.x * travel,
        start.y + direction.y * travel,
      );
      if (LilyFrogRules.firstSegmentCircleHit(
            start: start,
            end: end,
            center: target.center,
            radius: target.landingRadius,
          ) !=
          null) {
        final toTarget = Point<double>(
          target.center.x - start.x,
          target.center.y - start.y,
        );
        final projection = toTarget.x * direction.x + toTarget.y * direction.y;
        final missX = toTarget.x - direction.x * projection;
        final missY = toTarget.y - direction.y * projection;
        final miss = sqrt(missX * missX + missY * missY);
        if (miss < bestMiss) {
          bestMiss = miss;
          bestTheta = theta;
        }
      }
    }
    return bestTheta;
  }

  double? launchThetaForFlyRouteForTesting(int padId) {
    final target = _pads[padId]?.spec;
    final current = _pads[_currentPadId]?.spec;
    final routeFlies = _flies.values
        .where((fly) => fly.spec.padId == padId)
        .toList();
    if (target == null || current == null || routeFlies.isEmpty) return null;
    double? bestTheta;
    var bestCaught = 0;
    for (var index = 0; index < 2880; index++) {
      final theta = 2 * pi * index / 2880;
      final start = LilyFrogRules.orbitPosition(
        center: current.center,
        radius: current.orbitRadius,
        theta: theta,
      );
      final direction = LilyFrogRules.tangentDirection(
        theta: theta,
        clockwise: current.clockwise,
      );
      final end = Point<double>(
        start.x +
            direction.x *
                LilyFrogRules.launchSpeed *
                LilyFrogRules.maximumFlightSeconds,
        start.y +
            direction.y *
                LilyFrogRules.launchSpeed *
                LilyFrogRules.maximumFlightSeconds,
      );
      final lands = LilyFrogRules.firstSegmentCircleHit(
        start: start,
        end: end,
        center: target.center,
        radius: target.landingRadius,
      );
      if (lands == null) continue;
      final caught = routeFlies
          .where(
            (fly) =>
                LilyFrogRules.firstSegmentCircleHit(
                  start: start,
                  end: end,
                  center: fly.spec.center,
                  radius: LilyFrogRules.flyPickupRadius,
                ) !=
                null,
          )
          .length;
      if (caught > bestCaught) {
        bestCaught = caught;
        bestTheta = theta;
      }
    }
    return bestTheta;
  }

  LilyFrogMotionPhase get motionPhaseForTesting => _motionPhase;
  int get currentPadIdForTesting => _currentPadId;
  int get scoreForTesting => _score;
  int get comboForTesting => _combo;
  int get activeComboEffectsForTesting =>
      world.children.whereType<_ComboImpactComponent>().length;
  bool get isTerminalForTesting => _hasFinished;
  int get newLandingsForTesting => _newLandings;
  int get riskyLandingsForTesting => _riskyLandings;
  int get revisitedLandingsForTesting => _revisitedLandings;
  int get goldenLandingsForTesting => _goldenLandings;
  int get launchCountForTesting => _launchCount;
  int get fliesCaughtForTesting => _fliesCaught;
  double get frogAngleForTesting => _frog.angle;
  double? padAngleForTesting(int id) => _pads[id]?.visualAngle;
  double? padAngularSpeedForTesting(int id) => _pads[id]?.visualAngularSpeed;
  bool? padClockwiseForTesting(int id) => _pads[id]?.spec.clockwise;
  Vector2? padCenterForTesting(int id) {
    final center = _pads[id]?.spec.center;
    return center == null ? null : Vector2(center.x, center.y);
  }

  double? reachableWindowSecondsForTesting(int fromId, int targetId) {
    final from = _pads[fromId]?.spec;
    final target = _pads[targetId]?.spec;
    if (from == null || target == null) return null;
    return _fieldGenerator.reachableWindowSeconds(from: from, target: target);
  }

  int? get predictedLandingPadIdForTesting => _predictedLandingPath()?.padId;
  Vector2? get predictedLandingPointForTesting {
    final end = _predictedLandingPath()?.end;
    return end == null ? null : Vector2(end.x, end.y);
  }

  Vector2? get visibleTrajectoryEndForTesting {
    final end = _trajectoryPath()?.end;
    return end == null ? null : Vector2(end.x, end.y);
  }

  double? padEdgeGapForTesting(int firstId, int secondId) {
    final first = _pads[firstId]?.spec;
    final second = _pads[secondId]?.spec;
    if (first == null || second == null) return null;
    final dx = first.center.x - second.center.x;
    final dy = first.center.y - second.center.y;
    return sqrt(dx * dx + dy * dy) - (first.diameter + second.diameter) / 2;
  }

  Vector2 get frogPositionForTesting => _frog.position.clone();
  int get safeFuturePadCountForTesting => _pads.values
      .where(
        (pad) =>
            !pad.spec.risky &&
            pad.spec.progressIndex > _pads[_currentPadId]!.spec.progressIndex,
      )
      .length;
  int? get nextSafePadIdForTesting => _safeChildByPadId[_currentPadId];
  int get goldenFuturePadCountForTesting => _pads.values
      .where(
        (pad) =>
            pad.spec.golden &&
            pad.spec.progressIndex > _pads[_currentPadId]!.spec.progressIndex,
      )
      .length;
  int get visibleFlyCountForTesting => _flies.length;
  int flyCountForPadForTesting(int padId) =>
      _flies.values.where((fly) => fly.spec.padId == padId).length;
  bool get trajectoryGuideVisibleForTesting => _trajectoryPath() != null;
  Set<int> get flyTargetPadIdsForTesting =>
      _flies.values.map((fly) => fly.spec.padId).toSet();
  Set<int> get allPadIdsForTesting => _pads.keys.toSet();
  Set<int> get visiblePadIdsForTesting => _pads.values
      .where(
        (pad) =>
            pad.spec.center.y + pad.spec.diameter / 2 >= 0 &&
            pad.spec.center.y - pad.spec.diameter / 2 <= logicalSize.y,
      )
      .map((pad) => pad.spec.id)
      .toSet();
  bool get fliesTargetOnlyNormalPadsForTesting =>
      _flies.values.every((fly) => _pads[fly.spec.padId]?.spec.golden == false);
  int get activeFlyCollectEffectCountForTesting =>
      world.children.whereType<_FlyCollectFxComponent>().length;
}

class _PondComponent extends PositionComponent {
  _PondComponent({
    required super.position,
    required super.size,
    required this.sprite,
  }) : super(priority: -100);

  final Sprite sprite;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;

  @override
  void render(Canvas canvas) {
    sprite.render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _TrajectoryGuideComponent extends PositionComponent {
  _TrajectoryGuideComponent({required this.game}) : super(priority: 15);

  final LilyFrogGame game;
  final Paint _dotPaint = Paint()..color = const Color(0xE6E9FFFF);
  final Paint _missPaint = Paint()..color = const Color(0x99FFAA8A);
  final Paint _shadowPaint = Paint()..color = const Color(0x99051D2A);
  final Paint _markerPaint = Paint()
    ..color = const Color(0xFFF6FF9A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  @override
  void render(Canvas canvas) {
    final path = game._trajectoryPath();
    if (path == null) return;
    final hasLanding = path.padId != null;
    final dx = path.end.x - path.start.x;
    final dy = path.end.y - path.start.y;
    final distance = sqrt(dx * dx + dy * dy);
    if (distance <= 1) return;
    final unitX = dx / distance;
    final unitY = dy / distance;
    for (var traveled = 12.0; traveled < distance - 7; traveled += 14) {
      final point = Offset(
        path.start.x + unitX * traveled,
        path.start.y + unitY * traveled,
      );
      canvas.drawCircle(point.translate(1.5, 2), 3.5, _shadowPaint);
      canvas.drawCircle(
        point,
        hasLanding ? 3.0 : 2.4,
        hasLanding ? _dotPaint : _missPaint,
      );
    }
    if (!hasLanding) return;
    final landing = Offset(path.end.x, path.end.y);
    canvas.drawCircle(landing.translate(1.5, 2), 10, _shadowPaint);
    canvas.drawCircle(landing, 9, _markerPaint);
    canvas.drawCircle(landing, 2.5, _dotPaint);
  }
}

class _LilyPadComponent extends PositionComponent {
  _LilyPadComponent({required this.spec, required this.sprite})
    : _visualAngularSpeed = spec.angularSpeed,
      super(
        position: Vector2(spec.center.x, spec.center.y),
        size: Vector2.all(256),
        anchor: Anchor.center,
        priority: 0,
      );

  LilyPadSpec spec;
  final Sprite sprite;
  double _visualAngularSpeed;
  double _visualAngle = 0;
  double _squashRemaining = 0;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;

  double get visualAngle => _visualAngle;
  double get visualAngularSpeed => _visualAngularSpeed;

  void setAngularSpeed(double value) => _visualAngularSpeed = value;
  void prepareClockwise(bool value) => spec = spec.copyWith(clockwise: value);
  void triggerLanding() => _squashRemaining = 0.18;

  @override
  void update(double dt) {
    super.update(dt);
    _visualAngle += (spec.clockwise ? -1 : 1) * _visualAngularSpeed * dt;
    _visualAngle %= 2 * pi;
    _squashRemaining = max(0, _squashRemaining - dt);
  }

  void translate(double dx, double dy) {
    final expectedLandingPoint = spec.expectedLandingPoint;
    spec = spec.copyWith(
      center: Point(spec.center.x + dx, spec.center.y + dy),
      expectedLandingPoint: expectedLandingPoint == null
          ? null
          : Point(expectedLandingPoint.x + dx, expectedLandingPoint.y + dy),
    );
    position = Vector2(spec.center.x, spec.center.y);
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(size.x / 2, size.y / 2);
    final radius = spec.diameter / 2;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (_squashRemaining > 0) {
      final pulse = sin(pi * (_squashRemaining / 0.18));
      canvas.scale(1 + pulse * 0.06, 1 - pulse * 0.10);
    }
    canvas.rotate(_visualAngle);
    if (spec.golden) {
      canvas.scale(spec.diameter / 128);
    }
    canvas.translate(-center.dx, -center.dy);
    sprite.render(canvas, size: size, overridePaint: _spritePaint);
    canvas.restore();
    if (spec.risky && !spec.golden) {
      canvas.drawCircle(
        center,
        radius + 5,
        Paint()
          ..color = const Color(0xFFFF8A62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }
}

class _FrogComponent extends PositionComponent {
  _FrogComponent({
    required super.size,
    required this.orbitSprites,
    required this.jumpSprites,
    required this.landingSprites,
    required this.resultSprites,
  }) : super(anchor: Anchor.center, priority: 20);

  final List<Sprite> orbitSprites;
  final List<Sprite> jumpSprites;
  final List<Sprite> landingSprites;
  final List<Sprite> resultSprites;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  bool isAirborne = false;
  bool isLanding = false;
  bool isFailing = false;
  double jumpProgress = 0;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    final lift = isAirborne ? sin(pi * jumpProgress) * 12 : 0.0;
    final frames = isFailing
        ? resultSprites
        : isLanding
        ? landingSprites
        : isAirborne
        ? jumpSprites
        : orbitSprites;
    final index = isFailing
        ? 2 + ((_elapsed / 0.11).floor() % 2)
        : isLanding
        ? ((_elapsed / 0.055).floor() % frames.length)
        : isAirborne
        ? (jumpProgress * frames.length).floor().clamp(0, frames.length - 1)
        : ((_elapsed / 0.11).floor() % frames.length);
    canvas.save();
    canvas.translate(0, -lift);
    frames[index].render(canvas, size: size, overridePaint: _spritePaint);
    canvas.restore();
  }
}

class _FlyComponent extends PositionComponent {
  _FlyComponent({required this.spec, required this.sprites})
    : super(
        position: Vector2(spec.center.x, spec.center.y),
        size: Vector2.all(32),
        anchor: Anchor.center,
        priority: 10,
      );

  FlySpec spec;
  final List<Sprite> sprites;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  var _elapsed = 0.0;

  void translate(double dx, double dy) {
    spec = FlySpec(
      id: spec.id,
      center: Point(spec.center.x + dx, spec.center.y + dy),
      padId: spec.padId,
    );
    position = Vector2(spec.center.x, spec.center.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    final index = (_elapsed / 0.08).floor() % sprites.length;
    sprites[index].render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _WaterFxComponent extends PositionComponent {
  _WaterFxComponent({
    required super.position,
    required this.sprites,
    Vector2? size,
    this.tint,
  }) : super(
         size: size ?? Vector2.all(64),
         anchor: Anchor.center,
         priority: 30,
       );

  final List<Sprite> sprites;
  final Color? tint;
  late final Paint _spritePaint = Paint()
    ..filterQuality = FilterQuality.none
    ..colorFilter = tint == null
        ? null
        : ColorFilter.mode(tint!, BlendMode.modulate);
  var elapsed = 0.0;

  @override
  void update(double dt) {
    elapsed += dt;
    if (elapsed >= 0.4) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final index = (elapsed / 0.1).floor().clamp(0, sprites.length - 1);
    sprites[index].render(canvas, size: size, overridePaint: _spritePaint);
  }
}

class _FlyCollectFxComponent extends PositionComponent {
  _FlyCollectFxComponent({required super.position, required this.sprites})
    : super(size: Vector2.all(64), anchor: Anchor.center, priority: 35);

  final List<Sprite> sprites;
  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= LilyFrogRules.flyCollectEffectSeconds) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final progress = (_elapsed / LilyFrogRules.flyCollectEffectSeconds).clamp(
      0.0,
      0.999,
    );
    final index = (progress * sprites.length).floor();
    final punch = index <= 2 ? 1 + sin(progress * pi) * 0.18 : 1.0;
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(punch);
    canvas.translate(-size.x / 2, -size.y / 2);
    sprites[index].render(canvas, size: size, overridePaint: _spritePaint);
    canvas.restore();
  }
}

int _comboEffectTier(int combo) => combo >= 71
    ? 4
    : combo >= 41
    ? 3
    : combo >= 21
    ? 2
    : combo >= 11
    ? 1
    : 0;

class _ComboImpactComponent extends PositionComponent {
  _ComboImpactComponent({required this.game, required this.combo})
    : super(position: Vector2(0, -160), size: Vector2(360, 960), priority: 60);

  final LilyFrogGame game;
  final int combo;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= 0.72) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final progress = (_elapsed / 0.72).clamp(0.0, 1.0);
    final fade = (1 - max(0.0, (progress - 0.55) / 0.45))
        .clamp(0.0, 1.0)
        .toDouble();
    final tier = _comboEffectTier(combo);
    final accent = switch (tier) {
      1 => const Color(0xFFFFCF45),
      2 => const Color(0xFFFF853F),
      3 => const Color(0xFFFF4ECA),
      4 => const Color(0xFFB878FF),
      _ => const Color(0xFF54EFFF),
    };
    final center = Offset(game._frog.position.x, game._frog.position.y + 160);
    final flash = (1 - progress * 4).clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()
        ..color = accent.withValues(
          alpha: flash * (tier == 0 ? 0.14 : 0.22 + tier * 0.04),
        ),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(0.8);
    canvas.translate(-center.dx, -center.dy);
    for (var ring = 0; ring < 2 + tier; ring++) {
      final wave = ((progress - ring * 0.11) / 0.84).clamp(0.0, 1.0);
      if (wave == 0) continue;
      canvas.drawCircle(
        center,
        25 + wave * 145,
        Paint()
          ..color = (ring == 0 ? Colors.white : accent).withValues(
            alpha: (1 - wave) * fade,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == 0 ? 5.5 + tier * 1.5 : 3 + tier * 0.75
          ..isAntiAlias = false,
      );
    }
    final rayCount = tier == 0 ? 8 : 12 + tier * 4;
    for (var index = 0; index < rayCount; index++) {
      final angle = index * 2 * pi / rayCount;
      final inner = 34 + progress * 45;
      final outer = inner + 24 * (1 - progress);
      canvas.drawLine(
        center + Offset(cos(angle) * inner, sin(angle) * inner),
        center + Offset(cos(angle) * outer, sin(angle) * outer),
        Paint()
          ..color = (index.isEven ? Colors.white : accent).withValues(
            alpha: fade,
          )
          ..strokeWidth = index.isEven ? 6 : 4
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false,
      );
    }

    const bannerY = 300.0; // World y=140, safely below the HUD.
    final scale =
        1 +
        (0.34 + tier * 0.05) * (1 - progress) * sin(pi * min(1, progress * 3));
    final painter = TextPainter(
      text: TextSpan(
        text: '$combo COMBO!',
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontSize: 38 + tier * 2,
          fontWeight: FontWeight.w900,
          color: Color.lerp(
            Colors.white,
            accent,
            0.72,
          )!.withValues(alpha: fade),
          shadows: [
            Shadow(
              color: accent.withValues(alpha: fade),
              blurRadius: tier == 0 ? 8 : 12 + tier * 5,
            ),
            Shadow(
              color: Colors.black.withValues(alpha: fade),
              offset: const Offset(-2, -2),
            ),
            Shadow(
              color: Colors.black.withValues(alpha: fade),
              offset: const Offset(2, -2),
            ),
            Shadow(
              color: Colors.black.withValues(alpha: fade),
              offset: const Offset(-2, 2),
            ),
            Shadow(
              color: Colors.black.withValues(alpha: fade),
              offset: const Offset(2, 2),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(180, bannerY);
    canvas.scale(scale * min(1.0, 310 / painter.width));
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    canvas.restore();
  }
}

class _ScorePopupComponent extends PositionComponent {
  _ScorePopupComponent({
    required super.position,
    required this.label,
    required this.color,
  }) : super(anchor: Anchor.center, priority: 45);

  final String label;
  final Color color;
  var _elapsed = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    position.y -= 24 * dt;
    if (_elapsed >= 0.8) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final opacity = (1 - _elapsed / 0.8).clamp(0.0, 1.0);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color.withValues(alpha: opacity),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: opacity * 0.9),
              offset: const Offset(1.5, 2),
              blurRadius: 0,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
  }
}
