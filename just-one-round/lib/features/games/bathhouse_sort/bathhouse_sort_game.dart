import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/bathhouse_sort/domain/bathhouse_sort_rules.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';

enum BathhouseSortPhase { loading, countdown, playing, finished, interrupted }

enum BathhouseTapOutcome { ignored, queued, correct, wrong }

class BathhouseSortGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  BathhouseSortGame({
    required this.onFinished,
    this.gameDuration = BathhouseSortRules.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    Random? random,
  }) : _guestGenerator = BathhouseGuestGenerator(random ?? Random()),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: gameDuration.inSeconds,
           countdownNumber: countdownDuration.inSeconds,
           distance: 0,
         ),
       );

  static final logicalSize = Vector2(360, 640);
  static const maxVisibleHeight = 900.0;
  static const maxVisibleWidth = 420.0;

  final Duration gameDuration;
  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final BathhouseGuestGenerator _guestGenerator;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  BathhouseSortPhase _phase = BathhouseSortPhase.loading;
  final List<BathhouseGuest> _guestQueue = [];
  late _BathhouseScene _scene;
  final List<_DepartingGuest> _departingGuests = [];
  final List<_SuccessBurst> _successBursts = [];
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _rosterRevealElapsed = double.infinity;
  var _activePairCount = 1;
  int? _rosterRevealPairIndex;
  final ListQueue<_QueuedTap> _pendingInputs = ListQueue();
  var _inputCommitCooldown = 0.0;
  var _inputLockRemaining = 0.0;
  var _correctPulse = 0.0;
  var _wrongFlash = 0.0;
  var _wrongBounceAge = double.infinity;
  var _wrongBounceDirection = 0.0;
  var _queueAdvanceElapsed = double.infinity;
  var _score = 0;
  var _combo = 0;
  var _bestCombo = 0;
  var _correctCount = 0;
  var _mistakeCount = 0;
  var _hasFinished = false;
  var _resultReported = false;
  var _controllerDisposed = false;
  var _loaded = false;
  var _lastPublishedTenth = -1;
  var _lastPublishedCountdown = -1;
  var _successSerial = 0;
  Vector2 _visibleResolution = logicalSize.clone();

  double get visibleLeft => logicalSize.x / 2 - _visibleResolution.x / 2;
  double get visibleTop => logicalSize.y - _visibleResolution.y;
  double get visibleRight => visibleLeft + _visibleResolution.x;
  double get visibleBottom => logicalSize.y;

  @visibleForTesting
  Vector2 viewportPositionForWorld(Vector2 worldPosition) =>
      Vector2(worldPosition.x - visibleLeft, worldPosition.y - visibleTop);

  @visibleForTesting
  BathhouseSortPhase get gamePhase => _phase;

  @visibleForTesting
  BathhouseGuest get currentGuest => _guestQueue.first;

  @visibleForTesting
  List<BathhouseGuest> get guestQueue => List.unmodifiable(_guestQueue);

  @visibleForTesting
  int get combo => _combo;

  @visibleForTesting
  int get bestCombo => _bestCombo;

  @visibleForTesting
  int get correctCount => _correctCount;

  @visibleForTesting
  int get mistakeCount => _mistakeCount;

  @visibleForTesting
  bool get inputLocked => _inputLockRemaining > 0;

  @visibleForTesting
  int get pendingInputCount => _pendingInputs.length;

  @visibleForTesting
  int get successBurstCount => _successBursts.length;

  @visibleForTesting
  bool get isReady => _loaded;

  double get playingElapsed => _playingElapsed;
  int get activePairCount => _activePairCount;
  int? get rosterRevealPairIndex =>
      _rosterRevealElapsed < _seconds(BathhouseSortRules.rosterRevealDuration)
      ? _rosterRevealPairIndex
      : null;
  double get rosterRevealProgress =>
      (_rosterRevealElapsed / _seconds(BathhouseSortRules.rosterRevealDuration))
          .clamp(0.0, 1.0);
  List<BathhouseSpecies> get activeSpecies =>
      BathhouseSortRules.activeSpecies(_activePairCount);
  double get correctPulse => _correctPulse;
  double get wrongFlash => _wrongFlash;
  BathhouseGuest get visibleGuest => _guestQueue.first;
  List<BathhouseGuest> get visibleQueue => _guestQueue;
  List<_DepartingGuest> get departingGuests => _departingGuests;
  List<_SuccessBurst> get successBursts => _successBursts;
  double get queueAdvanceProgress => _queueAdvanceElapsed.isFinite
      ? (_queueAdvanceElapsed /
                (BathhouseSortRules.queueAdvanceDuration.inMicroseconds /
                    Duration.microsecondsPerSecond))
            .clamp(0.0, 1.0)
      : 1;
  double get wrongBounceOffset {
    if (!_wrongBounceAge.isFinite || _wrongBounceAge >= 0.25) return 0;
    final progress = _wrongBounceAge / 0.25;
    return _wrongBounceDirection * sin(progress * pi * 4) * (1 - progress) * 24;
  }

  @override
  Color backgroundColor() => const Color(0xFF3B2418);

  @visibleForTesting
  static Vector2 viewportResolutionForCanvas(Vector2 canvasSize) {
    if (canvasSize.x <= 0 || canvasSize.y <= 0) {
      return logicalSize.clone();
    }
    final canvasAspectRatio = canvasSize.y / canvasSize.x;
    final logicalAspectRatio = logicalSize.y / logicalSize.x;
    if (canvasAspectRatio < logicalAspectRatio) {
      final visibleWidth = (logicalSize.y / canvasAspectRatio).clamp(
        logicalSize.x,
        maxVisibleWidth,
      );
      return Vector2(visibleWidth, logicalSize.y);
    }
    final visibleHeight = (logicalSize.x * canvasAspectRatio).clamp(
      logicalSize.y,
      maxVisibleHeight,
    );
    return Vector2(logicalSize.x, visibleHeight);
  }

  void _configureViewport(Vector2 canvasSize) {
    _visibleResolution = viewportResolutionForCanvas(canvasSize);
    camera.viewport = FixedResolutionViewport(resolution: _visibleResolution);
    camera.viewfinder.position = Vector2(
      logicalSize.x / 2,
      logicalSize.y - _visibleResolution.y / 2,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);
    final loaded = await images.loadAll(const [
      'bathhouse_sort/bathhouse_corridor_background.png',
      'bathhouse_sort/bathhouse_hanja_noren_atlas.png',
      'bathhouse_sort/bathhouse_guests_atlas.png',
      'bathhouse_sort/bathhouse_feedback_fx_atlas.png',
    ]);
    final norenSheet = SpriteSheet(image: loaded[1], srcSize: Vector2.all(80));
    final guestSheet = SpriteSheet(
      image: loaded[2],
      srcSize: Vector2(112, 224),
    );
    final feedbackSheet = SpriteSheet(
      image: loaded[3],
      srcSize: Vector2.all(32),
    );
    _guestQueue.addAll(
      List.generate(
        BathhouseSortRules.queueSize,
        (_) => _guestGenerator.next(activePairCount: _activePairCount),
      ),
    );
    _scene = _BathhouseScene(
      this,
      background: Sprite(loaded[0]),
      noren: List.generate(
        6,
        (index) => norenSheet.getSprite(index ~/ 3, index % 3),
      ),
      guests: List.generate(
        BathhouseSpecies.values.length,
        (index) => guestSheet.getSprite(index ~/ 4, index % 4),
      ),
      guestFaces: List.generate(
        BathhouseSpecies.values.length,
        (index) => Sprite(
          loaded[2],
          srcPosition: Vector2((index % 4) * 112, (index ~/ 4) * 224),
          srcSize: Vector2(112, 112),
        ),
      ),
      successFx: List.generate(4, (index) => feedbackSheet.getSprite(0, index)),
      errorFx: List.generate(4, (index) => feedbackSheet.getSprite(1, index)),
      steamFx: List.generate(4, (index) => feedbackSheet.getSprite(2, index)),
    );
    await world.add(_scene);
    _loaded = true;
    if (countdownDuration == Duration.zero) {
      _phase = BathhouseSortPhase.playing;
    } else {
      _phase = BathhouseSortPhase.countdown;
    }
    _publishHud(force: true);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _configureViewport(size);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_loaded || _hasFinished || _controllerDisposed) return;
    _updateEffects(dt);

    if (_phase == BathhouseSortPhase.countdown) {
      _countdownElapsed += dt;
      if (_countdownElapsed >= _seconds(countdownDuration)) {
        _phase = BathhouseSortPhase.playing;
      }
      _publishHud();
      return;
    }
    if (_phase != BathhouseSortPhase.playing) return;

    _advanceInputBuffer(dt);
    _advancePlayingClock(dt);
    _publishHud();
  }

  void _advancePlayingClock(double dt) {
    var remaining = dt;
    while (remaining > 0 && !_hasFinished) {
      final durationSeconds = _seconds(gameDuration);
      final nextMilestone =
          _activePairCount <= BathhouseSortRules.unlockMilestones.length
          ? _seconds(BathhouseSortRules.unlockMilestones[_activePairCount - 1])
          : durationSeconds;
      final boundary = min(durationSeconds, nextMilestone);
      final consumed = min(remaining, boundary - _playingElapsed);
      _playingElapsed += consumed;
      remaining -= consumed;
      if (_playingElapsed + 0.000001 >= durationSeconds) {
        _playingElapsed = durationSeconds;
        _finish();
      } else if (_playingElapsed + 0.000001 >= nextMilestone) {
        _revealPair(_activePairCount);
      } else {
        break;
      }
    }
  }

  void _revealPair(int pairIndex) {
    _activePairCount = pairIndex + 1;
    _rosterRevealPairIndex = pairIndex;
    _rosterRevealElapsed = 0;
    _publishHud(force: true);
  }

  void _updateEffects(double dt) {
    _inputLockRemaining = max(0, _inputLockRemaining - dt);
    _correctPulse = max(0, _correctPulse - dt * 5);
    _wrongFlash = max(0, _wrongFlash - dt * 4);
    if (_wrongBounceAge.isFinite) _wrongBounceAge += dt;
    if (_queueAdvanceElapsed.isFinite) _queueAdvanceElapsed += dt;
    if (_rosterRevealElapsed.isFinite) _rosterRevealElapsed += dt;
    for (final guest in _departingGuests) {
      guest.age += dt;
    }
    _departingGuests.removeWhere((guest) => guest.age >= 0.36);
    for (final burst in _successBursts) {
      burst.age += dt;
    }
    _successBursts.removeWhere((burst) => burst.age >= _SuccessBurst.lifetime);
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final viewportPosition = camera.viewport.globalToLocal(
      event.canvasPosition,
    );
    tapLogical(
      Vector2(
        viewportPosition.x + visibleLeft,
        viewportPosition.y + visibleTop,
      ),
    );
  }

  @visibleForTesting
  BathhouseTapOutcome tapLogical(Vector2 position) {
    if (_phase != BathhouseSortPhase.playing || _inputLockRemaining > 0) {
      return BathhouseTapOutcome.ignored;
    }
    final routed = BathhouseSortRules.entranceForTap(
      x: position.x,
      y: position.y,
    );
    if (routed == null) return BathhouseTapOutcome.ignored;
    if (_pendingInputs.length >= BathhouseSortRules.inputBufferCapacity) {
      return BathhouseTapOutcome.ignored;
    }
    _pendingInputs.add(
      _QueuedTap(
        entrance: routed,
        direction: routed == BathEntrance.mens ? -1 : 1,
      ),
    );
    if (_inputCommitCooldown <= 0) return _commitNextInput();
    return BathhouseTapOutcome.queued;
  }

  void _advanceInputBuffer(double dt) {
    if (_pendingInputs.isEmpty) {
      _inputCommitCooldown = max(0, _inputCommitCooldown - dt);
      return;
    }
    for (final input in _pendingInputs) {
      input.age += dt;
    }
    final lifetime = _seconds(BathhouseSortRules.inputReservationLifetime);
    while (_pendingInputs.isNotEmpty && _pendingInputs.first.age > lifetime) {
      _pendingInputs.removeFirst();
    }
    _inputCommitCooldown -= dt;
    while (_pendingInputs.isNotEmpty &&
        _inputCommitCooldown <= 0 &&
        _inputLockRemaining <= 0) {
      final outcome = _commitNextInput(preserveSchedule: true);
      if (outcome == BathhouseTapOutcome.wrong) break;
    }
    if (_pendingInputs.isEmpty) {
      _inputCommitCooldown = max(0, _inputCommitCooldown);
    }
  }

  BathhouseTapOutcome _commitNextInput({bool preserveSchedule = false}) {
    if (_pendingInputs.isEmpty) return BathhouseTapOutcome.ignored;
    final priorCooldown = _inputCommitCooldown;
    final input = _pendingInputs.removeFirst();
    final outcome = _routeGuest(input.entrance, direction: input.direction);
    _inputCommitCooldown = preserveSchedule
        ? priorCooldown + _seconds(BathhouseSortRules.inputCommitInterval)
        : _seconds(BathhouseSortRules.inputCommitInterval);
    return outcome;
  }

  BathhouseTapOutcome _routeGuest(
    BathEntrance routed, {
    required double direction,
  }) {
    if (!BathhouseSortRules.isCorrect(
      guestEntrance: currentGuest.entrance,
      tappedEntrance: routed,
    )) {
      _combo = 0;
      _mistakeCount++;
      _inputLockRemaining =
          BathhouseSortRules.wrongInputLock.inMicroseconds /
          Duration.microsecondsPerSecond;
      _wrongFlash = 1;
      _wrongBounceAge = 0;
      _wrongBounceDirection = direction;
      _pendingInputs.clear();
      unawaited(HapticFeedback.heavyImpact());
      unawaited(SystemSound.play(SystemSoundType.alert));
      _publishHud(force: true);
      return BathhouseTapOutcome.wrong;
    }

    _combo = BathhouseSortRules.comboAfterCorrect(_combo);
    _bestCombo = max(_bestCombo, _combo);
    _correctCount++;
    final earnedPoints = BathhouseSortRules.pointsForCorrect(_combo);
    _score = BathhouseSortRules.addCorrectScore(score: _score, combo: _combo);
    _successBursts.add(
      _SuccessBurst(
        combo: _combo,
        points: earnedPoints,
        serial: _successSerial++,
      ),
    );
    if (_successBursts.length > 12) _successBursts.removeAt(0);
    _departingGuests.add(
      _DepartingGuest(profile: currentGuest, entrance: routed),
    );
    _guestQueue.removeAt(0);
    _guestQueue.add(_guestGenerator.next(activePairCount: _activePairCount));
    _queueAdvanceElapsed = 0;
    _correctPulse = 1;
    unawaited(HapticFeedback.selectionClick());
    unawaited(SystemSound.play(SystemSoundType.click));
    _publishHud(force: true);
    return BathhouseTapOutcome.correct;
  }

  void _finish() {
    if (_hasFinished) return;
    _hasFinished = true;
    _pendingInputs.clear();
    _phase = BathhouseSortPhase.finished;
    _publishHud(force: true);
    pauseEngine();
    if (_resultReported || _controllerDisposed) return;
    _resultReported = true;
    unawaited(HapticFeedback.mediumImpact());
    onFinished(
      GameResult(
        score: _score,
        starsCollected: 0,
        collisions: _mistakeCount,
        duration: gameDuration,
        endType: GameEndType.timeUp,
      ),
    );
  }

  void _publishHud({bool force = false}) {
    final tenth = (_playingElapsed * 10).floor();
    final remaining = max(0, (_seconds(gameDuration) - _playingElapsed).ceil());
    final countdown = max(
      0,
      (_seconds(countdownDuration) - _countdownElapsed).ceil(),
    );
    if (!force) {
      if (_phase == BathhouseSortPhase.countdown &&
          countdown == _lastPublishedCountdown) {
        return;
      }
      if (_phase == BathhouseSortPhase.playing &&
          tenth == _lastPublishedTenth) {
        return;
      }
    }
    if (_phase == BathhouseSortPhase.countdown) {
      _lastPublishedCountdown = countdown;
    } else if (_phase == BathhouseSortPhase.playing) {
      _lastPublishedTenth = tenth;
    }
    hud.value = MiniGameHudState(
      phase: switch (_phase) {
        BathhouseSortPhase.loading ||
        BathhouseSortPhase.countdown => MiniGamePhase.countdown,
        BathhouseSortPhase.playing => MiniGamePhase.playing,
        _ => MiniGamePhase.finished,
      },
      score: _score,
      distance: _combo,
      elapsedSeconds: _playingElapsed.floor(),
      remainingSeconds: remaining,
      countdownNumber: countdown,
      message: rosterRevealPairIndex != null
          ? '새 동물 추가!'
          : _inputLockRemaining > 0
          ? '앗! 다시 보고!'
          : null,
    );
  }

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _pendingInputs.clear();
    _phase = BathhouseSortPhase.interrupted;
    if (_loaded) _publishHud(force: true);
    pauseEngine();
  }

  @override
  void disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    hud.dispose();
  }

  static double _seconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;
}

class _DepartingGuest {
  _DepartingGuest({required this.profile, required this.entrance});

  final BathhouseGuest profile;
  final BathEntrance entrance;
  double age = 0;
}

class _QueuedTap {
  _QueuedTap({required this.entrance, required this.direction});

  final BathEntrance entrance;
  final double direction;
  double age = 0;
}

class _SuccessBurst {
  _SuccessBurst({
    required this.combo,
    required this.points,
    required this.serial,
  });

  static const lifetime = 0.72;

  final int combo;
  final int points;
  final int serial;
  double age = 0;
}

class _BathhouseScene extends PositionComponent {
  _BathhouseScene(
    this.game, {
    required this.background,
    required this.noren,
    required this.guests,
    required this.guestFaces,
    required this.successFx,
    required this.errorFx,
    required this.steamFx,
  }) : super(position: Vector2.zero(), size: BathhouseSortGame.logicalSize);

  final BathhouseSortGame game;
  final Sprite background;
  final List<Sprite> noren;
  final List<Sprite> guests;
  final List<Sprite> guestFaces;
  final List<Sprite> successFx;
  final List<Sprite> errorFx;
  final List<Sprite> steamFx;
  final Paint _paint = Paint()..isAntiAlias = false;
  final Paint _spritePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  static const _queueY = <double>[438, 350, 300, 264, 238, 219, 204];
  static const _queueScale = <double>[1.05, 0.72, 0.55, 0.44, 0.36, 0.30, 0.25];

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    _drawRoom(canvas);
    final advance = game.queueAdvanceProgress;
    for (var index = game.visibleQueue.length - 1; index >= 0; index--) {
      final fromIndex = min(index + 1, _queueY.length - 1);
      final y =
          _queueY[fromIndex] + (_queueY[index] - _queueY[fromIndex]) * advance;
      final scale =
          _queueScale[fromIndex] +
          (_queueScale[index] - _queueScale[fromIndex]) * advance;
      final isCurrent = index == 0;
      _drawGuest(
        canvas,
        game.visibleQueue[index],
        x: 180 + (isCurrent ? game.wrongBounceOffset : 0),
        y: y - (isCurrent ? game.correctPulse * 4 : 0),
        scale: scale * (isCurrent ? 1 + game.correctPulse * 0.025 : 1),
        opacity: index == game.visibleQueue.length - 1 ? max(0.45, advance) : 1,
      );
    }
    for (final departing in game.departingGuests) {
      final progress = (departing.age / 0.36).clamp(0.0, 1.0);
      final eased = 1 - pow(1 - progress, 3).toDouble();
      final targetX = departing.entrance == BathEntrance.mens ? 78.0 : 282.0;
      _drawGuest(
        canvas,
        departing.profile,
        x: 180 + (targetX - 180) * eased,
        y: _queueY.first - 176 * eased,
        scale: 1 - eased * 0.34,
        opacity: (1 - max(0, progress - 0.72) / 0.28).clamp(0.0, 1.0),
      );
    }
    _drawNorenLayer(canvas);
    _drawActiveRoster(canvas);
    _drawFeedback(canvas);
    _drawTapZones(canvas);
    _drawSteam(canvas);
    if (game.wrongFlash > 0) {
      _paint.color = Color.fromRGBO(210, 40, 40, game.wrongFlash * 0.22);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 360, 640), _paint);
    }
  }

  void _drawRoom(ui.Canvas canvas) {
    final visibleRect = Rect.fromLTRB(
      game.visibleLeft,
      game.visibleTop,
      game.visibleRight,
      game.visibleBottom,
    );
    _paint.color = const Color(0xFF3B2418);
    canvas.drawRect(visibleRect, _paint);
    background.render(
      canvas,
      position: Vector2(0, -40),
      size: Vector2(360, 720),
      overridePaint: _spritePaint,
    );

    final source = background.srcSize;
    const edgeSample = 8.0;
    if (game.visibleLeft < 0) {
      canvas.drawImageRect(
        background.image,
        Rect.fromLTWH(0, 0, edgeSample, source.y),
        Rect.fromLTRB(game.visibleLeft, -40, 0, 680),
        _spritePaint,
      );
    }
    if (game.visibleRight > 360) {
      canvas.drawImageRect(
        background.image,
        Rect.fromLTWH(source.x - edgeSample, 0, edgeSample, source.y),
        Rect.fromLTRB(360, -40, game.visibleRight, 680),
        _spritePaint,
      );
    }
    if (game.visibleTop < -40) {
      canvas.drawImageRect(
        background.image,
        Rect.fromLTWH(0, 0, source.x, edgeSample),
        Rect.fromLTRB(
          game.visibleLeft,
          game.visibleTop,
          game.visibleRight,
          -40,
        ),
        _spritePaint,
      );
    }
    if (game.visibleBottom > 680) {
      canvas.drawImageRect(
        background.image,
        Rect.fromLTWH(0, source.y - edgeSample, source.x, edgeSample),
        Rect.fromLTRB(
          game.visibleLeft,
          680,
          game.visibleRight,
          game.visibleBottom,
        ),
        _spritePaint,
      );
    }
  }

  void _drawNorenLayer(ui.Canvas canvas) {
    _drawNoren(canvas, entrance: BathEntrance.mens, x: 12);
    _drawNoren(canvas, entrance: BathEntrance.womens, x: 220);
  }

  void _drawNoren(
    ui.Canvas canvas, {
    required BathEntrance entrance,
    required double x,
  }) {
    final rowOffset = entrance == BathEntrance.mens ? 0 : 3;
    final departing = game.departingGuests
        .where((guest) => guest.entrance == entrance)
        .fold<_DepartingGuest?>(
          null,
          (youngest, guest) =>
              youngest == null || guest.age < youngest.age ? guest : youngest,
        );
    var frame = 0;
    if (departing != null) {
      final progress = departing.age / 0.36;
      frame = progress < 0.18 ? 0 : (progress < 0.68 ? 1 : 2);
    }
    noren[rowOffset + frame].render(
      canvas,
      position: Vector2(x, 94),
      size: Vector2.all(128),
      overridePaint: _spritePaint,
    );
  }

  void _drawGuest(
    ui.Canvas canvas,
    BathhouseGuest guest, {
    required double x,
    required double y,
    double scale = 1,
    double opacity = 1,
  }) {
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scale);
    _paint.color = const Color(0xFF59412F).withValues(alpha: opacity * 0.25);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 113), width: 108, height: 18),
      _paint,
    );
    _spritePaint.color = Colors.white.withValues(alpha: opacity);
    guests[_guestSpriteIndex(guest)].render(
      canvas,
      position: Vector2(-56, -111),
      size: Vector2(112, 224),
      overridePaint: _spritePaint,
    );
    _spritePaint.color = Colors.white;
    canvas.restore();
  }

  int _guestSpriteIndex(BathhouseGuest guest) => guest.species.index;

  void _drawActiveRoster(ui.Canvas canvas) {
    final mens = game.activeSpecies
        .where((species) => species.entrance == BathEntrance.mens)
        .toList();
    final womens = game.activeSpecies
        .where((species) => species.entrance == BathEntrance.womens)
        .toList();
    _drawRosterSide(canvas, mens, left: true);
    _drawRosterSide(canvas, womens, left: false);
  }

  void _drawRosterSide(
    ui.Canvas canvas,
    List<BathhouseSpecies> species, {
    required bool left,
  }) {
    final startX = left ? 5.0 : 297.0;
    final revealIndex = game.rosterRevealPairIndex;
    final revealPair = revealIndex == null
        ? null
        : BathhouseSortRules.speciesPairs[revealIndex];
    for (var index = 0; index < species.length; index++) {
      final item = species[index];
      final highlighted =
          item == revealPair?.mens || item == revealPair?.womens;
      final progress = game.rosterRevealProgress;
      final pop = highlighted ? sin(progress * pi) * 0.22 : 0.0;
      final x = startX;
      final y = 212.0 + index * 56;
      canvas.save();
      canvas.translate(x + 29, y + 29);
      canvas.scale(1 + pop);
      canvas.translate(-29, -29);
      _paint
        ..color = const Color(0xFF1C130E).withValues(alpha: 0.58)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(29, 29), 27, _paint);
      final sprite = guestFaces[item.index];
      _spritePaint.color = Colors.white;
      sprite.render(
        canvas,
        position: Vector2(3, -3),
        size: Vector2(52, 52),
        overridePaint: _spritePaint,
      );
      _paint
        ..color = const Color(0xFF24160F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5;
      canvas.drawCircle(const Offset(29, 29), 27, _paint);
      _paint
        ..color = left ? const Color(0xFF86C8FF) : const Color(0xFFFF9A9F)
        ..strokeWidth = 2.5;
      canvas.drawCircle(const Offset(29, 29), 25.5, _paint);
      if (highlighted) {
        _paint
          ..color = const Color(
            0xFFFFD66B,
          ).withValues(alpha: (1 - progress).clamp(0.2, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4;
        canvas.drawCircle(const Offset(29, 29), 29, _paint);
        _paint.style = PaintingStyle.fill;
        final sparkle = 2.5 + sin(progress * pi * 4).abs() * 2.5;
        canvas.drawCircle(const Offset(1, 2), sparkle, _paint);
        canvas.drawCircle(const Offset(57, 7), sparkle * 0.75, _paint);
      }
      _paint.style = PaintingStyle.fill;
      canvas.restore();
    }
  }

  void _drawFeedback(ui.Canvas canvas) {
    for (
      var burstIndex = 0;
      burstIndex < game.successBursts.length;
      burstIndex++
    ) {
      final burst = game.successBursts[burstIndex];
      final progress = (burst.age / _SuccessBurst.lifetime).clamp(0.0, 1.0);
      final tier = BathhouseSortRules.comboTier(burst.combo);
      final intensity = BathhouseSortRules.successEffectScale(burst.combo);
      final fade = (1 - progress).clamp(0.0, 1.0);
      final center = Offset(
        180 + sin(burst.serial * 2.17) * (6 + tier * 4),
        game.visibleTop + 86 - progress * (8 + tier * 2),
      );
      final fxSize = (54 + progress * 18) * intensity;
      final frame = (progress * successFx.length).floor().clamp(
        0,
        successFx.length - 1,
      );
      _spritePaint.color = Colors.white.withValues(alpha: fade);
      successFx[frame].render(
        canvas,
        position: Vector2(center.dx - fxSize / 2, center.dy - fxSize / 2),
        size: Vector2.all(fxSize),
        overridePaint: _spritePaint,
      );
      _spritePaint.color = Colors.white;

      _paint
        ..color = const Color(0xFFFFD45C).withValues(alpha: fade * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + tier * 1.2;
      final ringRadius = (18 + progress * 20) * intensity;
      canvas.drawCircle(center, ringRadius, _paint);
      _paint
        ..color = const Color(0xFFFF9D36).withValues(alpha: fade * 0.68)
        ..strokeWidth = 1.5 + tier;
      canvas.drawCircle(center, ringRadius * 0.62, _paint);
      _paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFFFF1A6).withValues(alpha: fade * 0.16);
      canvas.drawCircle(center, (12 + tier * 3) * intensity, _paint);
      _paint
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFFFFD45C).withValues(alpha: fade * 0.9)
        ..strokeWidth = 2 + tier.toDouble();
      final sparkCount = 8 + tier * 6;
      for (var index = 0; index < sparkCount; index++) {
        final angle = (pi * 2 * index / sparkCount) + burst.serial * 0.37;
        final inner = (20 + progress * 18) * intensity;
        final outer = inner + (7 + tier * 4) * fade;
        canvas.drawLine(
          center + Offset(cos(angle), sin(angle)) * inner,
          center + Offset(cos(angle), sin(angle)) * outer,
          _paint,
        );
      }
      _paint.style = PaintingStyle.fill;
      if (burstIndex == game.successBursts.length - 1) {
        final tierLabel = switch (tier) {
          0 => '+${burst.points}',
          1 => '+${burst.points}  GOOD!',
          2 => '+${burst.points}  FEVER!',
          _ => '+${burst.points}  MAX!',
        };
        final textCenter = center.translate(0, -18 - tier * 4);
        final textSize = 18.0 + tier * 4;
        _text(
          canvas,
          tierLabel,
          textCenter.translate(1.5, 2),
          textSize,
          const Color(0xFF4A1D0B).withValues(alpha: fade * 0.8),
          bold: true,
        );
        _text(
          canvas,
          tierLabel,
          textCenter,
          textSize,
          Color.lerp(
            const Color(0xFFFFF3B0),
            const Color(0xFFFF8B3D),
            tier / 3,
          )!.withValues(alpha: fade),
          bold: true,
        );
      }
    }
    if (game.wrongFlash > 0) {
      final progress = 1 - game.wrongFlash;
      final frame = (progress * errorFx.length).floor().clamp(
        0,
        errorFx.length - 1,
      );
      errorFx[frame].render(
        canvas,
        position: Vector2(148, 358),
        size: Vector2.all(64),
        overridePaint: _spritePaint,
      );
    }
  }

  void _drawTapZones(ui.Canvas canvas) {
    _drawTapButton(
      canvas,
      const Rect.fromLTWH(8, 536, 164, 82),
      fill: const Color(0xFF123F73),
      male: true,
    );
    _drawTapButton(
      canvas,
      const Rect.fromLTWH(188, 536, 164, 82),
      fill: const Color(0xFF8F2330),
      male: false,
    );
  }

  void _drawTapButton(
    ui.Canvas canvas,
    Rect rect, {
    required Color fill,
    required bool male,
  }) {
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF120B08).withValues(alpha: 0.72);
    canvas.drawRRect(outer.shift(const Offset(0, 4)), _paint);
    _paint.color = const Color(0xFFFFD66B);
    canvas.drawRRect(outer, _paint);
    final inner = RRect.fromRectAndRadius(
      rect.deflate(4),
      const Radius.circular(8),
    );
    _paint.color = fill;
    canvas.drawRRect(inner, _paint);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.38);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(8), const Radius.circular(6)),
      _paint,
    );
    _paint.style = PaintingStyle.fill;
    final center = Offset(rect.center.dx, rect.center.dy - 1);
    _drawHanja(
      canvas,
      male: male,
      center: center.translate(2, 3),
      color: const Color(0xFF120B08).withValues(alpha: 0.65),
      scale: 1.18,
    );
    _drawHanja(
      canvas,
      male: male,
      center: center,
      color: Colors.white,
      scale: 1.18,
    );
  }

  void _drawHanja(
    ui.Canvas canvas, {
    required bool male,
    required Offset center,
    required Color color,
    double scale = 1,
  }) {
    final path = Path();
    if (male) {
      path
        ..addRect(const Rect.fromLTWH(-16, -20, 32, 23))
        ..moveTo(-16, -8)
        ..lineTo(16, -8)
        ..moveTo(0, -20)
        ..lineTo(0, 3)
        ..moveTo(-10, 10)
        ..lineTo(13, 10)
        ..lineTo(9, 23)
        ..lineTo(3, 23)
        ..moveTo(2, 3)
        ..lineTo(-4, 23);
    } else {
      path
        ..moveTo(4, -21)
        ..lineTo(-8, 8)
        ..lineTo(14, 22)
        ..moveTo(-17, -1)
        ..lineTo(17, 4)
        ..moveTo(13, -16)
        ..lineTo(3, 9)
        ..lineTo(-14, 21);
    }
    _paint
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.drawPath(path, _paint);
    canvas.restore();
    _paint
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.butt;
  }

  void _drawSteam(ui.Canvas canvas) {
    final difficulty = BathhouseSortRules.difficultyForElapsed(
      Duration(milliseconds: (game.playingElapsed * 1000).round()),
    );
    if (difficulty == BathhouseDifficulty.learn ||
        difficulty == BathhouseDifficulty.establish) {
      return;
    }
    final frame = (game.playingElapsed * 6).floor() % steamFx.length;
    final opacity = difficulty == BathhouseDifficulty.mastery ? 0.68 : 0.48;
    _spritePaint.color = Colors.white.withValues(alpha: opacity);
    steamFx[frame].render(
      canvas,
      position: Vector2(14, 350),
      size: Vector2.all(64),
      overridePaint: _spritePaint,
    );
    steamFx[(frame + 2) % steamFx.length].render(
      canvas,
      position: Vector2(288, 270),
      size: Vector2.all(64),
      overridePaint: _spritePaint,
    );
    _spritePaint.color = Colors.white;
  }

  void _text(
    ui.Canvas canvas,
    String value,
    Offset center,
    double size,
    Color color, {
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: 'Galmuri',
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }
}
