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
import 'package:just_one_round/features/games/net_boat/domain/net_boat_rules.dart';
import 'package:just_one_round/features/games/net_boat/net_boat_net_painter.dart';

class NetBoatGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  NetBoatGame({
    required this.onFinished,
    this.gameDuration = NetBoatRules.gameDuration,
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

  final Duration gameDuration;
  final Duration countdownDuration;
  final bool enableHaptics;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final Sprite _background;
  late final SpriteSheet _boatSheet;
  late final SpriteSheet _sardineSheet;
  late final SpriteSheet _piranhaSheet;
  late final SpriteSheet _marlinSheet;
  late final SpriteSheet _sharkSheet;
  late final SpriteSheet _sharkWakeSheet;
  late final SpriteSheet _whaleSheet;
  late final SpriteSheet _reefSheet;
  late final SpriteSheet _netFxSheet;
  late final _NetBoatScene _scene;
  final _turnBuffer = NetBoatTurnBuffer();
  final _net = <Point<double>>[
    const Point(NetBoatRules.startX, NetBoatRules.startY),
  ];
  final _creatures = <_CreatureState>[];
  final _respawns = <_CreatureRespawn>[];
  final _nextRespawnAllowedAt = <NetBoatCreatureKind, double>{};
  final _scorePopups = <_ScorePopup>[];
  final _netBounceVisuals = <_NetBounceVisual>[];
  _WhaleWarning? _whaleWarning;
  var _nextWhaleWaveIndex = 0;
  var _boat = const Point<double>(NetBoatRules.startX, NetBoatRules.startY);
  var _direction = NetBoatDirection.north;
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _elapsed = 0.0;
  var _score = 0;
  var _caughtFish = 0;
  var _closedLoops = 0;
  var _maxCapture = 0;
  var _turnVisual = 0.0;
  var _netRecoveryRemaining = 0.0;
  var _feedback = '';
  var _feedbackRemaining = 0.0;
  _CaptureVisual? _captureVisual;
  var _hasFinished = false;

  static Vector2 viewportResolutionForCanvas(Vector2 canvasSize) {
    if (canvasSize.x <= 0 || canvasSize.y <= 0) return logicalSize.clone();
    final height = (canvasSize.y * logicalSize.x / canvasSize.x).clamp(
      logicalSize.y,
      maxVisibleHeight,
    );
    return Vector2(logicalSize.x, height);
  }

  void _configureViewport(Vector2 canvasSize) {
    camera.viewport = FixedResolutionViewport(
      resolution: viewportResolutionForCanvas(canvasSize),
    );
    camera.viewfinder.position = logicalSize / 2;
  }

  @override
  Color backgroundColor() => const Color(0xFF073C4A);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);
    final loaded = await images.loadAll([
      'net_boat/sea_background.png',
      'net_boat/boat_navigation_atlas.png',
      'net_boat/sardine_atlas.png',
      'net_boat/piranha_atlas.png',
      'net_boat/marlin_atlas.png',
      'net_boat/shark_fin_atlas.png',
      'net_boat/shark_wake_atlas.png',
      'net_boat/whale_atlas.png',
      'net_boat/reef_modules_atlas.png',
      'net_boat/net_capture_fx_atlas.png',
    ]);
    _background = Sprite(loaded[0]);
    _boatSheet = SpriteSheet(image: loaded[1], srcSize: Vector2.all(64));
    _sardineSheet = SpriteSheet(image: loaded[2], srcSize: Vector2.all(84));
    _piranhaSheet = SpriteSheet(image: loaded[3], srcSize: Vector2.all(84));
    _marlinSheet = SpriteSheet(image: loaded[4], srcSize: Vector2(168, 114));
    _sharkSheet = SpriteSheet(image: loaded[5], srcSize: Vector2(74, 38));
    _sharkWakeSheet = SpriteSheet(image: loaded[6], srcSize: Vector2(72, 36));
    _whaleSheet = SpriteSheet(image: loaded[7], srcSize: Vector2(160, 106));
    _reefSheet = SpriteSheet(image: loaded[8], srcSize: Vector2.all(48));
    _netFxSheet = SpriteSheet(image: loaded[9], srcSize: Vector2.all(64));
    _scene = _NetBoatScene(this);
    await world.add(_scene);
    _fillCreatureRoster();
    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _publishHud(force: true);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _configureViewport(size);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hasFinished || dt <= 0) return;
    if (_phase == MiniGamePhase.countdown) {
      _countdownElapsed += dt;
      if (_countdownElapsed >= countdownDuration.inSeconds) {
        _phase = MiniGamePhase.playing;
        _publishHud(force: true);
      } else {
        _publishHud();
      }
      return;
    }
    var remaining = dt;
    while (remaining > 1e-9 && !_hasFinished) {
      final step = min(remaining, 1 / 120);
      _updatePlaying(step);
      remaining -= step;
    }
  }

  void _updatePlaying(double dt) {
    final remainingToClear = gameDuration.inMicroseconds / 1000000 - _elapsed;
    final effectiveDt = min(dt, max(0.0, remainingToClear));
    if (effectiveDt <= 1e-9) {
      _finish(clear: true);
      return;
    }
    _elapsed += effectiveDt;
    _turnVisual = max(0.0, _turnVisual - effectiveDt);
    _feedbackRemaining = max(0.0, _feedbackRemaining - effectiveDt);
    final netWasRecovering = _netRecoveryRemaining > 0;
    _netRecoveryRemaining = max(0.0, _netRecoveryRemaining - effectiveDt);
    if (netWasRecovering && _netRecoveryRemaining <= 0) {
      _net
        ..clear()
        ..add(_boat);
      _feedback = '그물 준비!';
      _feedbackRemaining = 0.6;
    }
    if (_captureVisual case final visual?) {
      visual.remaining = max(0, visual.remaining - effectiveDt);
      if (visual.remaining <= 0) _captureVisual = null;
    }
    for (final popup in _scorePopups) {
      popup.remaining = max(0, popup.remaining - effectiveDt);
    }
    _scorePopups.removeWhere((popup) => popup.remaining <= 0);
    for (final visual in _netBounceVisuals) {
      visual.remaining = max(0, visual.remaining - effectiveDt);
    }
    _netBounceVisuals.removeWhere((visual) => visual.remaining <= 0);
    if (_turnBuffer.update(effectiveDt)) _turnRight();

    final difficulty = NetBoatRules.difficultyAt(_elapsed);
    final vector = NetBoatRules.directionVector(_direction);
    final next = Point<double>(
      _boat.x + vector.x * difficulty.boatSpeed * effectiveDt,
      _boat.y + vector.y * difficulty.boatSpeed * effectiveDt,
    );
    final candidatePath = [..._net, next];
    final loop = NetBoatRules.latestLoop(candidatePath);
    final candidateNetLength = NetBoatRules.netLength(candidatePath);
    _boat = loop?.intersection ?? next;

    final previousCreaturePositions = <_CreatureState, Point<double>>{
      for (final creature in _creatures) creature: creature.position,
    };
    _updateCreatures(effectiveDt);
    _updateWhaleWarning(effectiveDt);
    _updateRespawns();
    _updateWhaleSchedule();
    _fillCreatureRoster();

    // Reaching the configured duration boundary wins a simultaneous collision.
    if (_elapsed >= gameDuration.inMicroseconds / 1000000 - 1e-9) {
      _finish(clear: true);
      return;
    }
    if (_elapsed > NetBoatRules.safeOpeningSeconds &&
        !NetBoatRules.isBoatInsidePlayArea(_boat, direction: _direction)) {
      _finish(clear: false, failure: NetBoatFailure.reef);
      return;
    }
    if (_elapsed > NetBoatRules.safeOpeningSeconds) {
      for (final creature in _creatures) {
        if (!NetBoatRules.isLethalOnBoatContact(creature.kind)) continue;
        if (!NetBoatRules.boatHitsCreature(
          boat: _boat,
          boatDirection: NetBoatRules.directionVector(_direction),
          creature: creature.position,
          direction: creature.velocity,
          kind: creature.kind,
        )) {
          continue;
        }
        _feedback = '${_creatureName(creature.kind)} 충돌!';
        _finish(clear: false, failure: NetBoatFailure.creature);
        return;
      }
    }
    _resolveNetBounces([
      ..._net,
      _boat,
    ], previousCreaturePositions: previousCreaturePositions);
    if (loop != null) {
      _resolveCapture(loop);
    } else if (_netRecoveryRemaining <= 0 &&
        NetBoatRules.isNetAtLimit(candidateNetLength)) {
      _breakNet();
    }
    _publishHud();
  }

  void _turnRight() {
    if (_netRecoveryRemaining <= 0 &&
        (_net.isEmpty || _distance(_net.last, _boat) > 1e-6)) {
      _net.add(_boat);
    }
    _direction = NetBoatRules.turnRight(_direction);
    _turnVisual = NetBoatRules.turnCooldownSeconds;
    if (enableHaptics) unawaited(HapticFeedback.lightImpact());
  }

  void _resolveCapture(NetLoop loop) {
    final caught = _creatures
        .where(
          (creature) => NetBoatRules.pointInPolygonInclusive(
            creature.position,
            loop.polygon,
          ),
        )
        .toList();
    _closedLoops++;
    _captureVisual = _CaptureVisual(
      polygon: List<Point<double>>.of(loop.polygon),
      center: _polygonCenter(loop.polygon),
      remaining: _CaptureVisual.duration,
      caughtCount: caught.length,
    );
    _net
      ..clear()
      ..add(_boat);
    if (caught.isEmpty) {
      _feedback = '';
      _feedbackRemaining = 0;
      return;
    }
    final points = NetBoatRules.captureScore(caught.map((item) => item.kind));
    _score = NetBoatRules.clampSubmittedScore(_score + points);
    _caughtFish += caught.length;
    _maxCapture = max(_maxCapture, caught.length);
    for (final creature in caught) {
      _scorePopups.add(
        _ScorePopup(
          position: creature.position,
          label: NetBoatRules.capturePopupLabel(creature.kind),
        ),
      );
      _creatures.remove(creature);
      if (creature.kind != NetBoatCreatureKind.whale) {
        _respawns.add(
          _CreatureRespawn(
            kind: creature.kind,
            due: _elapsed + NetBoatRules.specFor(creature.kind).respawnSeconds,
          ),
        );
      }
    }
    final caughtWhale = caught.any(
      (creature) => creature.kind == NetBoatCreatureKind.whale,
    );
    _feedback = caughtWhale
        ? '고래 만선! +${NetBoatRules.formatHudScore(points)}'
        : '만선! ×${caught.length} · +${NetBoatRules.formatHudScore(points)}';
    _feedbackRemaining = caughtWhale ? 1.5 : 1.0;
    if (enableHaptics) unawaited(HapticFeedback.mediumImpact());
  }

  void _resolveNetBounces(
    List<Point<double>> activeNet, {
    required Map<_CreatureState, Point<double>> previousCreaturePositions,
  }) {
    if (_netRecoveryRemaining > 0 || activeNet.length < 2) return;
    for (final creature in _creatures) {
      final previous = previousCreaturePositions[creature] ?? creature.position;
      final bounce = NetBoatRules.bounceCreatureOffNet(
        previousCreature: previous,
        creature: creature.position,
        velocity: creature.velocity,
        kind: creature.kind,
        net: activeNet,
      );
      if (bounce == null) continue;
      creature
        ..position = bounce.position
        ..velocity = bounce.velocity;
      _netBounceVisuals.add(_NetBounceVisual(position: bounce.position));
    }
  }

  void _breakNet() {
    _net.clear();
    _netRecoveryRemaining = NetBoatRules.netRecoverySeconds;
    _feedback = '그물이 끊어졌어요! 1초 후 재전개';
    _feedbackRemaining = NetBoatRules.netRecoverySeconds;
    if (enableHaptics) unawaited(HapticFeedback.mediumImpact());
  }

  void _updateCreatures(double dt) {
    for (final creature in _creatures) {
      creature.turnRemaining -= dt;
      if (creature.kind == NetBoatCreatureKind.sardine &&
          creature.turnRemaining <= 0) {
        final angle =
            atan2(creature.velocity.y, creature.velocity.x) +
            (_random.nextDouble() - 0.5) * 1.2;
        final speed = _speed(creature.velocity);
        creature
          ..velocity = Point(cos(angle) * speed, sin(angle) * speed)
          ..turnRemaining = 0.9 + _random.nextDouble() * 0.8;
      }
      var vx = creature.velocity.x;
      var vy = creature.velocity.y;
      final radius = _creatureEdgeRadius(creature.kind);
      var next = Point(
        creature.position.x + vx * dt,
        creature.position.y + vy * dt,
      );
      if (next.x < NetBoatRules.playLeft + radius ||
          next.x > NetBoatRules.playRight - radius) {
        vx = -vx;
      }
      if (next.y < NetBoatRules.playTop + radius ||
          next.y > NetBoatRules.playBottom - radius) {
        vy = -vy;
      }
      next = Point(
        next.x.clamp(
          NetBoatRules.playLeft + radius,
          NetBoatRules.playRight - radius,
        ),
        next.y.clamp(
          NetBoatRules.playTop + radius,
          NetBoatRules.playBottom - radius,
        ),
      );
      creature
        ..position = next
        ..velocity = Point(vx, vy)
        ..animationTime += dt;
    }
  }

  void _updateWhaleWarning(double dt) {
    final warning = _whaleWarning;
    if (warning == null) return;
    warning.remaining -= dt;
    if (warning.remaining > 0) return;
    if (_hasActiveWhale) {
      _whaleWarning = null;
      return;
    }
    _creatures.add(warning.creature);
    _whaleWarning = null;
  }

  void _updateWhaleSchedule() {
    if (_nextWhaleWaveIndex >= NetBoatRules.whaleSpawnSeconds.length) return;
    final spawnAt = NetBoatRules.whaleSpawnSeconds[_nextWhaleWaveIndex];
    final warningAt = spawnAt - NetBoatRules.whaleWarningSeconds;
    if (_elapsed + 1e-9 < warningAt) return;

    if (_hasActiveWhale) {
      _nextWhaleWaveIndex++;
      return;
    }

    final creature = _makeScheduledWhale();
    final remaining = max(0.0, spawnAt - _elapsed);
    if (remaining <= 1e-9) {
      _creatures.add(creature);
    } else {
      _whaleWarning = _WhaleWarning(creature: creature, remaining: remaining);
    }
    _nextWhaleWaveIndex++;
  }

  bool get _hasActiveWhale =>
      _creatures.any((creature) => creature.kind == NetBoatCreatureKind.whale);

  _CreatureState _makeScheduledWhale() {
    const kind = NetBoatCreatureKind.whale;
    final spec = NetBoatRules.specFor(kind);
    final radius = _creatureEdgeRadius(kind);
    final point = Point<double>(
      NetBoatRules.playLeft +
          radius +
          _random.nextDouble() *
              (NetBoatRules.playRight - NetBoatRules.playLeft - radius * 2),
      NetBoatRules.playTop +
          radius +
          _random.nextDouble() *
              (NetBoatRules.playBottom - NetBoatRules.playTop - radius * 2),
    );
    final angle = _random.nextDouble() * 2 * pi;
    final speed =
        spec.minimumSpeed +
        _random.nextDouble() * (spec.maximumSpeed - spec.minimumSpeed);
    return _CreatureState(
      kind: kind,
      position: point,
      velocity: Point(cos(angle) * speed, sin(angle) * speed),
      turnRemaining: double.infinity,
    );
  }

  void _updateRespawns() {
    for (final respawn in List<_CreatureRespawn>.of(_respawns)) {
      if (respawn.due > _elapsed) continue;
      final nextAllowedAt = _nextRespawnAllowedAt[respawn.kind] ?? 0;
      if (nextAllowedAt > _elapsed) {
        respawn.due = nextAllowedAt;
        continue;
      }
      if (_requestSpawn(respawn.kind)) {
        _respawns.remove(respawn);
        _nextRespawnAllowedAt[respawn.kind] =
            _elapsed + NetBoatRules.specFor(respawn.kind).respawnSeconds;
      } else {
        respawn.due = _elapsed + 0.5;
      }
    }
  }

  void _fillCreatureRoster() {
    final roster = NetBoatRules.difficultyAt(_elapsed).roster;
    for (final kind in NetBoatCreatureKind.values) {
      if (kind == NetBoatCreatureKind.whale) continue;
      while (_countPlanned(kind) < roster.targetFor(kind)) {
        if (!_requestSpawn(kind)) break;
      }
    }
  }

  int _countPlanned(NetBoatCreatureKind kind) =>
      _creatures.where((item) => item.kind == kind).length +
      _respawns.where((item) => item.kind == kind).length +
      ((_whaleWarning?.creature.kind == kind) ? 1 : 0);

  bool _requestSpawn(NetBoatCreatureKind kind) {
    if (kind == NetBoatCreatureKind.whale) return false;
    final creature = _makeSafeCreature(kind);
    if (creature == null) return false;
    _creatures.add(creature);
    return true;
  }

  _CreatureState? _makeSafeCreature(NetBoatCreatureKind kind) {
    final spec = NetBoatRules.specFor(kind);
    final radius = _creatureEdgeRadius(kind);
    for (var attempt = 0; attempt < 60; attempt++) {
      final point = Point<double>(
        NetBoatRules.playLeft +
            radius +
            _random.nextDouble() *
                (NetBoatRules.playRight - NetBoatRules.playLeft - radius * 2),
        NetBoatRules.playTop +
            radius +
            _random.nextDouble() *
                (NetBoatRules.playBottom - NetBoatRules.playTop - radius * 2),
      );
      final angle = _random.nextDouble() * 2 * pi;
      final speed =
          spec.minimumSpeed +
          _random.nextDouble() * (spec.maximumSpeed - spec.minimumSpeed);
      final velocity = Point(cos(angle) * speed, sin(angle) * speed);
      if (_distance(point, _boat) <
              max(NetBoatRules.minimumCreatureBoatSpawnDistance, radius + 64) ||
          NetBoatRules.distanceToPolyline(point, [..._net, _boat]) <
              radius + 18 ||
          _creatures.any(
            (other) =>
                _distance(point, other.position) <
                radius +
                    _creatureEdgeRadius(other.kind) +
                    _spawnSeparation(kind, other.kind),
          )) {
        continue;
      }
      final reaction = _elapsed < NetBoatRules.safeOpeningSeconds
          ? NetBoatRules.safeCreatureSpawnSeconds
          : 1.5;
      if (!_spawnPathIsSafe(point, velocity, kind, reaction)) continue;
      return _CreatureState(
        kind: kind,
        position: point,
        velocity: velocity,
        turnRemaining: kind == NetBoatCreatureKind.sardine
            ? 0.9 + _random.nextDouble() * 0.8
            : double.infinity,
      );
    }
    return null;
  }

  bool _spawnPathIsSafe(
    Point<double> start,
    Point<double> velocity,
    NetBoatCreatureKind kind,
    double seconds,
  ) {
    final boatVector = NetBoatRules.directionVector(_direction);
    final boatSpeed = NetBoatRules.difficultyAt(_elapsed).boatSpeed;
    for (var step = 0; step <= 6; step++) {
      final time = seconds * step / 6;
      final creature = Point(
        start.x + velocity.x * time,
        start.y + velocity.y * time,
      );
      final boat = Point(
        _boat.x + boatVector.x * boatSpeed * time,
        _boat.y + boatVector.y * boatSpeed * time,
      );
      if (NetBoatRules.boatHitsCreature(
        boat: boat,
        boatDirection: boatVector,
        creature: creature,
        direction: velocity,
        kind: kind,
      )) {
        return false;
      }
    }
    return true;
  }

  double _creatureEdgeRadius(NetBoatCreatureKind kind) {
    final spec = NetBoatRules.specFor(kind);
    return sqrt(
      spec.renderWidth * spec.renderWidth / 4 +
          spec.renderHeight * spec.renderHeight / 4,
    );
  }

  double _speed(Point<double> velocity) =>
      sqrt(velocity.x * velocity.x + velocity.y * velocity.y);

  double _spawnSeparation(
    NetBoatCreatureKind first,
    NetBoatCreatureKind second,
  ) =>
      first == NetBoatCreatureKind.sardine &&
          second == NetBoatCreatureKind.sardine
      ? 0
      : (first == NetBoatCreatureKind.sardine ||
            second == NetBoatCreatureKind.sardine)
      ? 6
      : 12;

  String _creatureName(NetBoatCreatureKind kind) => switch (kind) {
    NetBoatCreatureKind.sardine => '정어리',
    NetBoatCreatureKind.piranha => '피라냐',
    NetBoatCreatureKind.marlin => '청새치',
    NetBoatCreatureKind.shark => '상어',
    NetBoatCreatureKind.whale => '고래',
  };

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    tapForTesting();
  }

  void _publishHud({bool force = false}) {
    final netLength = currentNetLength;
    final showNetWarning =
        _netRecoveryRemaining <= 0 && NetBoatRules.isNetWarning(netLength);
    final next = MiniGameHudState(
      phase: _phase,
      score: _score,
      elapsedSeconds: _elapsed.floor(),
      remainingSeconds: _phase == MiniGamePhase.finished
          ? 0
          : max(0, gameDuration.inSeconds - _elapsed.floor()),
      countdownNumber: max(
        0,
        countdownDuration.inSeconds - _countdownElapsed.floor(),
      ),
      distance: (netLength / 4).floor() * 4,
      message: _feedbackRemaining > 0
          ? _feedback
          : showNetWarning
          ? NetBoatRules.netWarningMessage
          : '잡은 물고기 $_caughtFish마리',
    );
    final current = hud.value;
    if (force ||
        current.phase != next.phase ||
        current.score != next.score ||
        current.elapsedSeconds != next.elapsedSeconds ||
        current.distance != next.distance ||
        current.message != next.message ||
        current.countdownNumber != next.countdownNumber) {
      hud.value = next;
    }
  }

  void _finish({required bool clear, NetBoatFailure? failure}) {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _feedback = clear
        ? '만선 귀항!'
        : switch (failure) {
            NetBoatFailure.reef => '돌 벽 충돌!',
            NetBoatFailure.creature =>
              _feedback.endsWith('충돌!') ? _feedback : '바다생물 충돌!',
            null => '항해 종료',
          };
    _feedbackRemaining = 99;
    _publishHud(force: true);
    pauseEngine();
    onFinished(
      GameResult(
        score: NetBoatRules.clampSubmittedScore(_score),
        starsCollected: 0,
        collisions: clear ? 0 : 1,
        duration: clear
            ? gameDuration
            : Duration(milliseconds: (_elapsed * 1000).round()),
        endType: clear ? GameEndType.clear : GameEndType.gameOver,
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

  @override
  void disposeController() {
    if (!_hasFinished) interrupt();
    hud.dispose();
  }

  int get closedLoopsForTesting => _closedLoops;
  int get caughtFishForTesting => _caughtFish;
  int get maximumCaptureForTesting => _maxCapture;
  int get scorePopupCountForTesting => _scorePopups.length;
  List<String> get scorePopupLabelsForTesting =>
      _scorePopups.map((popup) => popup.label).toList(growable: false);
  Point<double>? creaturePositionForTesting(NetBoatCreatureKind kind) =>
      _creatures
          .where((creature) => creature.kind == kind)
          .firstOrNull
          ?.position;
  Point<double>? creatureVelocityForTesting(NetBoatCreatureKind kind) =>
      _creatures
          .where((creature) => creature.kind == kind)
          .firstOrNull
          ?.velocity;
  Point<double> get boatPositionForTesting => _boat;
  NetBoatDirection get directionForTesting => _direction;
  double get currentNetLength => NetBoatRules.netLength([..._net, _boat]);
  double get netRecoveryRemainingForTesting => _netRecoveryRemaining;
  int creatureCountForTesting(NetBoatCreatureKind kind) =>
      _creatures.where((creature) => creature.kind == kind).length;
  double? get whaleWarningRemainingForTesting => _whaleWarning?.remaining;

  @visibleForTesting
  void setNetPathForTesting(
    List<Point<double>> path, {
    required NetBoatDirection direction,
  }) {
    assert(path.isNotEmpty);
    _net
      ..clear()
      ..addAll(path.take(path.length - 1));
    _boat = path.last;
    _direction = direction;
    _netRecoveryRemaining = 0;
    _publishHud(force: true);
  }

  @visibleForTesting
  void setCreatureForTesting(
    NetBoatCreatureKind kind,
    Point<double> position, {
    double turnRemaining = 99,
  }) {
    _creatures
      ..clear()
      ..add(
        _CreatureState(
          kind: kind,
          position: position,
          velocity: const Point<double>(1, 0),
          turnRemaining: turnRemaining,
        ),
      );
  }

  @visibleForTesting
  void setCreatureVelocityForTesting(Point<double> velocity) {
    for (final creature in _creatures) {
      creature.velocity = velocity;
      creature.turnRemaining = 99;
    }
  }

  @visibleForTesting
  void setElapsedForTesting(double elapsedSeconds) {
    _elapsed = elapsedSeconds;
    _publishHud(force: true);
  }

  @visibleForTesting
  void updateWhaleScheduleForTesting() => _updateWhaleSchedule();

  @visibleForTesting
  void updateWhaleWarningForTesting(double dt) => _updateWhaleWarning(dt);

  bool tapForTesting() {
    if (_phase != MiniGamePhase.playing || _hasFinished) return false;
    if (_turnBuffer.request()) {
      _turnRight();
      return true;
    }
    return false;
  }

  double _distance(Point<double> a, Point<double> b) =>
      sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

  Point<double> _polygonCenter(List<Point<double>> polygon) {
    final points = polygon.length > 1 && polygon.first == polygon.last
        ? polygon.take(polygon.length - 1)
        : polygon;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final point in points) {
      minX = min(minX, point.x);
      minY = min(minY, point.y);
      maxX = max(maxX, point.x);
      maxY = max(maxY, point.y);
    }
    return Point((minX + maxX) / 2, (minY + maxY) / 2);
  }
}

class _CreatureState {
  _CreatureState({
    required this.kind,
    required this.position,
    required this.velocity,
    required this.turnRemaining,
  });

  final NetBoatCreatureKind kind;
  Point<double> position;
  Point<double> velocity;
  double turnRemaining;
  double animationTime = 0;
}

class _WhaleWarning {
  _WhaleWarning({required this.creature, required this.remaining});

  final _CreatureState creature;
  double remaining;
}

class _CreatureRespawn {
  _CreatureRespawn({required this.kind, required this.due});

  final NetBoatCreatureKind kind;
  double due;
}

class _CaptureVisual {
  _CaptureVisual({
    required this.polygon,
    required this.center,
    required this.remaining,
    required this.caughtCount,
  });

  static const duration = 0.25;
  final List<Point<double>> polygon;
  final Point<double> center;
  final int caughtCount;
  double remaining;
}

class _ScorePopup {
  _ScorePopup({required this.position, required this.label});

  static const duration = 0.85;
  final Point<double> position;
  final String label;
  double remaining = duration;
}

class _NetBounceVisual {
  _NetBounceVisual({required this.position});

  static const duration = 0.12;
  static const ringStartRadius = 2.5;
  static const ringExpansion = 3.5;
  static const ringStrokeWidth = 1.0;
  static const particleStartRadius = 2.5;
  static const particleExpansion = 3.0;
  static const particleRadius = 0.7;
  final Point<double> position;
  double remaining = duration;
}

class _NetBoatScene extends Component {
  _NetBoatScene(this.game);

  final NetBoatGame game;
  final _netPainter = NetBoatNetPainter();
  final _pixelPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;
  final _smoothFishPaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high;
  final _warningPaint = Paint()
    ..color = const Color(0xFFFF6A4C)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  @override
  void render(Canvas canvas) {
    game._background.render(
      canvas,
      position: Vector2(0, -NetBoatGame.overscanTop),
      size: NetBoatGame.overscanSize,
    );
    _renderReefs(canvas);
    _renderCaptureVisual(canvas);
    _renderNet(canvas);
    if (game._whaleWarning case final warning?) {
      final pulse = 1 + sin(warning.remaining * 10).abs() * 0.08;
      final spec = NetBoatRules.specFor(NetBoatCreatureKind.whale);
      canvas
        ..save()
        ..translate(warning.creature.position.x, warning.creature.position.y)
        ..scale(pulse)
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: spec.renderWidth * 0.82,
            height: spec.renderHeight * 0.52,
          ),
          Paint()..color = const Color(0x8A062D42),
        )
        ..restore();
      canvas.drawCircle(
        Offset(warning.creature.position.x, warning.creature.position.y),
        56 + sin(warning.remaining * 12).abs() * 8,
        _warningPaint,
      );
    }
    for (final creature in game._creatures) {
      final sprite = switch (creature.kind) {
        NetBoatCreatureKind.sardine => game._sardineSheet.getSprite(
          (creature.animationTime * 8).floor() % 4 ~/ 2,
          (creature.animationTime * 8).floor() % 2,
        ),
        NetBoatCreatureKind.piranha => game._piranhaSheet.getSprite(
          0,
          (creature.animationTime * 9).floor() % 4,
        ),
        NetBoatCreatureKind.marlin => game._marlinSheet.getSprite(
          0,
          (creature.animationTime * 7).floor() % 4,
        ),
        NetBoatCreatureKind.shark => game._sharkSheet.getSprite(
          0,
          (creature.animationTime * 6).floor() % 4,
        ),
        NetBoatCreatureKind.whale => game._whaleSheet.getSprite(
          0,
          (creature.animationTime * 4).floor() % 4,
        ),
      };
      final spec = NetBoatRules.specFor(creature.kind);
      final transform = NetBoatRules.spriteTransformForVelocity(
        creature.kind,
        creature.velocity,
      );
      if (creature.kind == NetBoatCreatureKind.shark) {
        final speed = sqrt(
          creature.velocity.x * creature.velocity.x +
              creature.velocity.y * creature.velocity.y,
        );
        final wakeCenter = speed <= 1e-6
            ? creature.position
            : Point<double>(
                creature.position.x - creature.velocity.x / speed * 18,
                creature.position.y - creature.velocity.y / speed * 18,
              );
        _renderRotatedSprite(
          canvas,
          game._sharkWakeSheet.getSprite(
            0,
            (creature.animationTime * 6).floor() % 4,
          ),
          wakeCenter,
          72,
          transform.rotation,
          height: 36,
          flipHorizontally: transform.flipHorizontally,
        );
      }
      _renderRotatedSprite(
        canvas,
        sprite,
        creature.position,
        spec.renderWidth,
        transform.rotation,
        height: spec.renderHeight,
        flipHorizontally: transform.flipHorizontally,
        overridePaint: switch (creature.kind) {
          NetBoatCreatureKind.sardine ||
          NetBoatCreatureKind.piranha ||
          NetBoatCreatureKind.marlin => _smoothFishPaint,
          NetBoatCreatureKind.shark || NetBoatCreatureKind.whale => _pixelPaint,
        },
      );
    }
    _renderNetBounces(canvas);
    _renderScorePopups(canvas);
    final boatColumn = game._turnVisual > 0
        ? 4 + ((game._turnVisual * 20).floor() % 2)
        : (game._elapsed * 7).floor() % 4;
    final boatVertical =
        game._direction == NetBoatDirection.north ||
        game._direction == NetBoatDirection.south;
    final boatWidth = boatVertical ? 48.0 : 56.0;
    final boatHeight = boatVertical ? 56.0 : 48.0;
    game._boatSheet
        .getSprite(game._direction.index, boatColumn)
        .render(
          canvas,
          position: Vector2(
            game._boat.x - boatWidth / 2,
            game._boat.y - boatHeight / 2,
          ),
          size: Vector2(boatWidth, boatHeight),
        );
  }

  void _renderNet(Canvas canvas) {
    if (game._net.isEmpty) return;
    final points = [
      ...game._net.map((point) => Offset(point.x, point.y)),
      Offset(game._boat.x, game._boat.y),
    ];
    if (points.length < 2) return;
    _netPainter.draw(
      canvas,
      points,
      warning: NetBoatRules.isNetWarning(game.currentNetLength),
    );
  }

  void _renderScorePopups(Canvas canvas) {
    for (final popup in game._scorePopups) {
      final progress = 1 - popup.remaining / _ScorePopup.duration;
      final opacity = (popup.remaining / _ScorePopup.duration).clamp(0.0, 1.0);
      final scale = 0.9 + sin(progress * pi) * 0.16;
      final textPainter = TextPainter(
        text: TextSpan(
          text: popup.label,
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: Color.fromRGBO(255, 228, 92, opacity),
            fontSize: 15,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: Color.fromRGBO(10, 43, 53, opacity),
                offset: const Offset(2, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final center = Offset(
        popup.position.x,
        popup.position.y - 18 - progress * 20,
      );
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..scale(scale);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }
  }

  void _renderNetBounces(Canvas canvas) {
    for (final visual in game._netBounceVisuals) {
      final progress = 1 - visual.remaining / _NetBounceVisual.duration;
      final center = Offset(visual.position.x, visual.position.y);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        _NetBounceVisual.ringStartRadius +
            progress * _NetBounceVisual.ringExpansion,
        Paint()
          ..color = Color.fromRGBO(221, 255, 250, opacity * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _NetBounceVisual.ringStrokeWidth,
      );
      for (var index = 0; index < 4; index++) {
        final angle = index * pi / 2 + progress * 0.35;
        canvas.drawCircle(
          center +
              Offset(cos(angle), sin(angle)) *
                  (_NetBounceVisual.particleStartRadius +
                      progress * _NetBounceVisual.particleExpansion),
          _NetBounceVisual.particleRadius,
          Paint()..color = Color.fromRGBO(255, 240, 190, opacity * 0.7),
        );
      }
    }
  }

  void _renderCaptureVisual(Canvas canvas) {
    final visual = game._captureVisual;
    if (visual == null || visual.polygon.length < 3) return;
    final progress = 1 - visual.remaining / _CaptureVisual.duration;
    final scale = 1 - progress * 0.08;
    canvas
      ..save()
      ..translate(visual.center.x, visual.center.y)
      ..scale(scale)
      ..translate(-visual.center.x, -visual.center.y);
    _netPainter.draw(
      canvas,
      visual.polygon
          .map((point) => Offset(point.x, point.y))
          .toList(growable: false),
      closed: true,
    );
    canvas.restore();
    final frame = (progress * 4).floor().clamp(0, 3);
    game._netFxSheet
        .getSprite(0, frame)
        .render(
          canvas,
          position: Vector2(visual.center.x - 48, visual.center.y - 48),
          size: Vector2.all(96),
        );
  }

  void _renderReefs(Canvas canvas) {
    const placements = <Point<double>>[
      Point(18, 82),
      Point(60, 82),
      Point(102, 82),
      Point(144, 82),
      Point(186, 82),
      Point(228, 82),
      Point(270, 82),
      Point(312, 82),
      Point(342, 82),
      Point(18, 616),
      Point(60, 616),
      Point(102, 616),
      Point(144, 616),
      Point(186, 616),
      Point(228, 616),
      Point(270, 616),
      Point(312, 616),
      Point(342, 616),
      Point(18, 124),
      Point(18, 166),
      Point(18, 208),
      Point(18, 250),
      Point(18, 292),
      Point(18, 334),
      Point(18, 376),
      Point(18, 418),
      Point(18, 460),
      Point(18, 502),
      Point(18, 544),
      Point(18, 586),
      Point(342, 124),
      Point(342, 166),
      Point(342, 208),
      Point(342, 250),
      Point(342, 292),
      Point(342, 334),
      Point(342, 376),
      Point(342, 418),
      Point(342, 460),
      Point(342, 502),
      Point(342, 544),
      Point(342, 586),
    ];
    for (var index = 0; index < placements.length; index++) {
      _reef(canvas, placements[index], index);
    }
  }

  void _reef(Canvas canvas, Point<double> point, int index) {
    game._reefSheet
        .getSprite((index ~/ 4) % 2, index % 4)
        .render(
          canvas,
          position: Vector2(point.x - 24, point.y - 24),
          size: Vector2.all(48),
        );
  }

  void _renderRotatedSprite(
    Canvas canvas,
    Sprite sprite,
    Point<double> center,
    double width,
    double angle, {
    double? height,
    bool flipHorizontally = false,
    Paint? overridePaint,
  }) {
    final renderHeight = height ?? width;
    canvas
      ..save()
      ..translate(center.x, center.y)
      ..rotate(angle)
      ..scale(flipHorizontally ? -1.0 : 1.0, 1.0);
    sprite.render(
      canvas,
      position: Vector2(-width / 2, -renderHeight / 2),
      size: Vector2(width, renderHeight),
      overridePaint: overridePaint ?? _pixelPaint,
    );
    canvas.restore();
  }
}
