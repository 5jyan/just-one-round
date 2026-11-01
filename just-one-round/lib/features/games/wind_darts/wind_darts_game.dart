import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_opponent.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_art.dart';

enum WindDartsPhase {
  loading,
  opponentPreview,
  opponentIntro,
  boardApproach,
  countdown,
  shotPreview,
  aiming,
  flight,
  impact,
  opponentFlight,
  opponentImpact,
  finished,
  interrupted,
}

class WindDartsGame extends FlameGame implements MiniGameController {
  WindDartsGame({
    required this.onFinished,
    required int challengeSeed,
    required this.gameDuration,
    required this.countdownDuration,
  }) : _winds = WindDartsRules.windsForSeed(challengeSeed),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: null,
           countdownNumber: countdownDuration.inSeconds,
         ),
       );

  static final logicalSize = Vector2(360, 640);
  static const boardCenter = Offset(180, 235);
  static const flightStart = Offset(210, 510);
  static const cameraRetreatDuration = Duration(milliseconds: 700);
  static const opponentIntroDuration = Duration(milliseconds: 2500);
  static const boardApproachDuration = Duration(milliseconds: 700);
  static const opponentDartFlightDuration = Duration(milliseconds: 560);
  static const opponentDartImpactDuration = Duration(milliseconds: 850);
  static const _opponentIntroFrameSeconds = 0.14;
  static const _opponentSmokeStartSeconds = 0.49;
  static const _opponentSmokeFrameSeconds = 0.09;
  static const _opponentDartScreenStart = Offset(320, 420);

  final Duration gameDuration;
  final Duration countdownDuration;
  final ValueChanged<GameResult> onFinished;
  final List<WindDartsWind> _winds;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  final List<WindDartsImpact> shotRecords = [];
  WindDartsOpponent? opponent;
  WindDartsPhase phase = WindDartsPhase.loading;
  double _elapsed = 0;
  double _countdownElapsed = 0;
  double _phaseElapsed = 0;
  double _holdElapsed = 0;
  int _shotIndex = 0;
  int _activePointer = -1;
  Offset? _lastPointerPosition;
  Offset _manualAimOffset = Offset.zero;
  bool _assetsReady = false;
  bool _terminal = false;
  bool _opponentPreviewRequested = false;
  bool _opponentIntroPending = false;
  bool _opponentIntroPlayed = false;
  bool _hudPublishScheduled = false;
  bool _controllerDisposed = false;
  MiniGameHudState? _pendingHudState;
  WindDartsImpact? _pendingImpact;
  int _opponentRevealedThrough = -1;
  int? _opponentPendingScore;
  WindDartsAimSample? _shotAim;
  Offset _shotOffset = Offset.zero;
  double _displayedBoardScale = 1;
  double _launchBoardRadius = WindDartsRules.baseBoardRadius;
  double _launchCameraZoom = WindDartsArt.worldZoomForShotScale(1);
  Offset _flightWorldStart = boardCenter;
  Offset _flightWorldTarget = boardCenter;
  Offset _flightTailDirectionWorld = const Offset(0, 1);
  Offset _opponentFlightWorldStart = boardCenter;
  Offset _opponentFlightWorldTarget = boardCenter;
  Offset _opponentFlightTailDirectionWorld = const Offset(0, 1);
  double _cameraForwardElapsed = 0;
  double _cameraForwardFromScale = 1;
  bool _cameraForwarding = false;
  double _cameraRetreatElapsed = 0;
  double _cameraRetreatFromScale = 1;
  double _cameraRetreatToScale = 1;
  bool _cameraRetreating = false;

  bool get assetsReady => _assetsReady;
  int get score => shotRecords.fold(0, (sum, shot) => sum + shot.score);
  int get shotIndex => _shotIndex;
  double get holdSeconds => _holdElapsed;
  WindDartsAimSample get currentAim {
    final sample = WindDartsRules.aimAt(_holdElapsed, boardRadius);
    return WindDartsAimSample(
      offset: sample.offset + _manualAimOffset,
      power: sample.power,
    );
  }

  WindDartsWind get currentWind => _winds[min(_shotIndex, _winds.length - 1)];
  double get boardScale => WindDartsRules.boardScaleForShot(_shotIndex);
  double get boardRadius => WindDartsRules.baseBoardRadius * boardScale;
  double get boardAngle => WindDartsRules.boardAngle;
  double get cameraZoom =>
      WindDartsArt.worldZoomForShotScale(_displayedBoardScale);
  double get displayedBoardScale => _displayedBoardScale;
  double get launchCameraZoom => _launchCameraZoom;
  Offset get flightWorldStart => _flightWorldStart;
  Offset get flightWorldTarget => _flightWorldTarget;
  Offset get flightTailDirectionWorld => _flightTailDirectionWorld;
  Offset get cameraFocusOffset => Offset.zero;
  bool get cameraForwarding => _cameraForwarding;
  bool get cameraRetreating => _cameraRetreating;
  @visibleForTesting
  int get revealedOpponentShotCountForTesting => _opponentRevealedThrough + 1;

  int get _revealedOpponentTotal {
    final currentOpponent = opponent;
    if (currentOpponent == null) return 0;
    final lastRevealed = min(
      _opponentRevealedThrough,
      currentOpponent.shotScores.length - 1,
    );
    var total = 0;
    for (var index = 0; index <= lastRevealed; index++) {
      total += currentOpponent.shotScores[index];
    }
    return total;
  }

  @visibleForTesting
  int get revealedOpponentTotalForTesting => _revealedOpponentTotal;

  void prepareOpponentPreview() {
    if (_terminal || _opponentIntroPlayed || _opponentIntroPending) return;
    _opponentPreviewRequested = true;
    _phaseElapsed = 0;
    _countdownElapsed = 0;
    _activePointer = -1;
    _lastPointerPosition = null;
    _holdElapsed = 0;
    _manualAimOffset = Offset.zero;
    _cameraForwarding = false;
    _cameraRetreating = false;
    _displayedBoardScale = WindDartsArt.worldBoardScale;
    phase = WindDartsPhase.opponentPreview;
    _publishHud();
  }

  void setOpponent(WindDartsOpponent value) {
    opponent = value;
    if (!_opponentIntroPlayed) {
      if (_assetsReady) {
        _beginOpponentIntro();
      } else {
        _opponentIntroPending = true;
      }
    }
    _publishHud();
  }

  @override
  Color backgroundColor() => const Color(0xFF17110B);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;
    final images = await this.images.loadAll(
      WindDartsArtAssets.flameImagePaths,
    );
    await world.add(_WindDartsScene(this, WindDartsArtImages.fromList(images)));
    _assetsReady = true;
    if (_opponentIntroPending) {
      _beginOpponentIntro();
    } else if (_opponentPreviewRequested) {
      phase = WindDartsPhase.opponentPreview;
      _displayedBoardScale = WindDartsArt.worldBoardScale;
    } else if (countdownDuration == Duration.zero) {
      phase = WindDartsPhase.shotPreview;
    } else {
      phase = WindDartsPhase.countdown;
    }
    _publishHud();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_terminal || !_assetsReady) return;
    // Keep animation interpolation stable after a long frame, but preserve
    // the actual positive elapsed time for the submitted result.
    final elapsedStep = dt < 0 ? 0.0 : dt;
    final step = elapsedStep.clamp(0.0, 0.1);
    if (phase == WindDartsPhase.opponentPreview) return;
    _elapsed += elapsedStep;
    _updateCameraRetreat(step);
    if (phase == WindDartsPhase.countdown) {
      _countdownElapsed += step;
      if (_countdownElapsed >= countdownDuration.inMicroseconds / 1e6) {
        phase = WindDartsPhase.shotPreview;
      }
    } else if (phase == WindDartsPhase.opponentIntro) {
      _phaseElapsed += step;
      if (_phaseElapsed >= opponentIntroDuration.inMicroseconds / 1e6) {
        _phaseElapsed = 0;
        _displayedBoardScale = WindDartsArt.worldBoardScale;
        phase = WindDartsPhase.boardApproach;
      }
    } else if (phase == WindDartsPhase.boardApproach) {
      _phaseElapsed += step;
      final t = (_phaseElapsed / (boardApproachDuration.inMicroseconds / 1e6))
          .clamp(0.0, 1.0);
      final eased = t * t * (3 - 2 * t);
      _displayedBoardScale =
          WindDartsArt.worldBoardScale +
          (boardScale - WindDartsArt.worldBoardScale) * eased;
      if (t >= 1) {
        _displayedBoardScale = boardScale;
        _phaseElapsed = 0;
        _countdownElapsed = 0;
        phase = countdownDuration == Duration.zero
            ? WindDartsPhase.shotPreview
            : WindDartsPhase.countdown;
      }
    } else if (phase == WindDartsPhase.aiming) {
      _holdElapsed += step;
    } else if (phase == WindDartsPhase.opponentFlight) {
      _phaseElapsed += step;
      if (_phaseElapsed >= opponentDartFlightDuration.inMicroseconds / 1e6) {
        phase = WindDartsPhase.opponentImpact;
        _phaseElapsed = 0;
        _opponentRevealedThrough = _shotIndex;
      }
    } else if (phase == WindDartsPhase.opponentImpact) {
      _phaseElapsed += step;
      if (_phaseElapsed >= opponentDartImpactDuration.inMicroseconds / 1e6) {
        _advanceToNextShot();
      }
    } else if (phase == WindDartsPhase.flight ||
        phase == WindDartsPhase.impact) {
      _phaseElapsed += step;
      if (phase == WindDartsPhase.flight) {
        _updateCameraForward(step);
        if (_phaseElapsed >= _flightDuration) {
          _completeCameraForward();
          phase = WindDartsPhase.impact;
          _phaseElapsed = 0;
          _pendingImpact = WindDartsRules.resolveImpact(
            point: _shotOffset,
            boardRadius: _launchBoardRadius,
            boardAngle: boardAngle,
            isGoldenDart: WindDartsRules.isGoldenDart(_shotIndex),
          );
          if (_pendingImpact != null) shotRecords.add(_pendingImpact!);
        }
      } else if (phase == WindDartsPhase.impact &&
          _phaseElapsed >=
              WindDartsRules.impactDisplayDuration.inMicroseconds / 1e6) {
        if (_beginOpponentShot()) {
          phase = WindDartsPhase.opponentFlight;
        } else {
          _advanceToNextShot();
        }
      }
    }
    _publishHud();
  }

  double get _flightDuration => 0.72 + _shotIndex * 0.05;

  void _beginOpponentIntro() {
    _opponentPreviewRequested = false;
    _opponentIntroPending = false;
    _opponentIntroPlayed = true;
    _countdownElapsed = 0;
    _phaseElapsed = 0;
    _activePointer = -1;
    _lastPointerPosition = null;
    _holdElapsed = 0;
    _manualAimOffset = Offset.zero;
    _cameraForwarding = false;
    _cameraRetreating = false;
    _displayedBoardScale = WindDartsArt.worldBoardScale;
    phase = WindDartsPhase.opponentIntro;
  }

  bool _beginOpponentShot() {
    final opponent = this.opponent;
    if (opponent == null || _shotIndex >= opponent.shotScores.length) {
      return false;
    }
    final score = opponent.shotScores[_shotIndex];
    final target = WindDartsRules.representativePointForScore(
      score: score,
      boardRadius: boardRadius,
      isGoldenDart: WindDartsRules.isGoldenDart(_shotIndex),
    );
    final zoom = cameraZoom;
    _opponentPendingScore = score;
    _opponentFlightWorldStart =
        boardCenter + (_opponentDartScreenStart - boardCenter) / zoom;
    _opponentFlightWorldTarget = boardCenter + target / zoom;
    _opponentFlightTailDirectionWorld =
        _opponentFlightWorldStart - _opponentFlightWorldTarget;
    _phaseElapsed = 0;
    return true;
  }

  void _advanceToNextShot() {
    _shotIndex++;
    if (_shotIndex >= WindDartsRules.shotCount) {
      _finish();
      return;
    }
    phase = WindDartsPhase.shotPreview;
    _phaseElapsed = 0;
    _pendingImpact = null;
    _opponentPendingScore = null;
    _shotAim = null;
    _beginCameraRetreat();
  }

  void pointerDown(int pointerId, Offset position) {
    if (_terminal ||
        !_assetsReady ||
        _cameraRetreating ||
        phase != WindDartsPhase.shotPreview) {
      return;
    }
    if (_activePointer != -1) return;
    _activePointer = pointerId;
    _lastPointerPosition = position;
    _manualAimOffset = Offset.zero;
    _holdElapsed = 0;
    phase = WindDartsPhase.aiming;
    _publishHud();
  }

  void pointerMove(int pointerId, Offset position) {
    if (pointerId != _activePointer || phase != WindDartsPhase.aiming) return;
    final previous = _lastPointerPosition;
    _lastPointerPosition = position;
    if (previous == null) return;
    final adjusted = _manualAimOffset + position - previous;
    final maxOffset = boardRadius * 0.75;
    _manualAimOffset = adjusted.distance > maxOffset
        ? adjusted / adjusted.distance * maxOffset
        : adjusted;
  }

  void pointerUp(int pointerId) {
    if (pointerId != _activePointer) return;
    _activePointer = -1;
    _lastPointerPosition = null;
    if (phase == WindDartsPhase.aiming) _releaseShot();
  }

  void pointerCancel(int pointerId) {
    if (pointerId != _activePointer) return;
    _activePointer = -1;
    _lastPointerPosition = null;
    _holdElapsed = 0;
    _manualAimOffset = Offset.zero;
    if (phase == WindDartsPhase.aiming) phase = WindDartsPhase.shotPreview;
    _publishHud();
  }

  @visibleForTesting
  void beginAimForTesting() {
    if (phase != WindDartsPhase.shotPreview || _terminal || _cameraRetreating) {
      return;
    }
    _holdElapsed = 0;
    _manualAimOffset = Offset.zero;
    phase = WindDartsPhase.aiming;
  }

  @visibleForTesting
  void releaseForTesting() => _releaseShot();

  @visibleForTesting
  Offset get shotOffset => _shotOffset;

  @visibleForTesting
  void updateForTesting(double dt) => update(dt);

  void _beginCameraRetreat() {
    _cameraRetreating = true;
    _cameraRetreatElapsed = 0;
    _cameraRetreatFromScale = _displayedBoardScale;
    _cameraRetreatToScale = boardScale;
  }

  void _updateCameraRetreat(double step) {
    if (!_cameraRetreating) return;
    _cameraRetreatElapsed += step;
    final t =
        (_cameraRetreatElapsed / (cameraRetreatDuration.inMicroseconds / 1e6))
            .clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    _displayedBoardScale =
        _cameraRetreatFromScale +
        (_cameraRetreatToScale - _cameraRetreatFromScale) * eased;
    if (t >= 1) {
      _displayedBoardScale = _cameraRetreatToScale;
      _cameraRetreating = false;
    }
  }

  void _beginCameraForward() {
    _cameraForwarding = true;
    _cameraForwardElapsed = 0;
    _cameraForwardFromScale = _displayedBoardScale;
  }

  void _updateCameraForward(double step) {
    if (!_cameraForwarding) return;
    _cameraForwardElapsed += step;
    final t = (_cameraForwardElapsed / _flightDuration).clamp(0.0, 1.0);
    final eased = t * t * (3 - 2 * t);
    _displayedBoardScale =
        _cameraForwardFromScale + (1 - _cameraForwardFromScale) * eased;
    if (t >= 1) _completeCameraForward();
  }

  void _completeCameraForward() {
    _displayedBoardScale = 1;
    _cameraForwarding = false;
    _cameraForwardElapsed = _flightDuration;
  }

  void _releaseShot() {
    if (_terminal || phase != WindDartsPhase.aiming) return;
    _shotAim = currentAim;
    _launchBoardRadius = boardRadius;
    _launchCameraZoom = cameraZoom;
    final wind = currentWind;
    final distanceScale =
        0.75 + WindDartsRules.distanceForShot(_shotIndex) * 0.12;
    final windOffset =
        wind.unitVector *
        (wind.metersPerSecond /
            3.5 *
            _launchBoardRadius *
            WindDartsRules.windOffsetCoefficient *
            distanceScale);
    _shotOffset = _shotAim!.offset + windOffset;
    _flightWorldStart =
        boardCenter + (flightStart - boardCenter) / _launchCameraZoom;
    _flightWorldTarget = boardCenter + _shotOffset / _launchCameraZoom;
    _flightTailDirectionWorld = _flightWorldStart - _flightWorldTarget;
    _pendingImpact = null;
    _phaseElapsed = 0;
    _activePointer = -1;
    _lastPointerPosition = null;
    phase = WindDartsPhase.flight;
    _beginCameraForward();
    HapticFeedback.lightImpact();
    _publishHud();
  }

  void _finish() {
    if (_terminal) return;
    _terminal = true;
    phase = WindDartsPhase.finished;
    pauseEngine();
    _publishHud();
    onFinished(
      GameResult(
        score: WindDartsRules.rankingScore(score),
        starsCollected: 0,
        collisions: 0,
        duration: Duration(milliseconds: (_elapsed * 1000).round()),
        endType: GameEndType.clear,
        windDartsShotScores: [
          ...shotRecords.map((shot) => shot.score),
          ...List.filled(WindDartsRules.shotCount - shotRecords.length, 0),
        ],
      ),
    );
  }

  void _publishHud() {
    final nextState = MiniGameHudState(
      phase: switch (phase) {
        WindDartsPhase.loading ||
        WindDartsPhase.opponentPreview ||
        WindDartsPhase.countdown => MiniGamePhase.countdown,
        WindDartsPhase.opponentIntro => MiniGamePhase.playing,
        WindDartsPhase.finished ||
        WindDartsPhase.interrupted => MiniGamePhase.finished,
        _ => MiniGamePhase.playing,
      },
      score: score,
      elapsedSeconds: _elapsed.floor(),
      remainingSeconds: null,
      countdownNumber: max(
        0,
        (countdownDuration.inMicroseconds / 1e6 - _countdownElapsed).ceil(),
      ),
      distance: _shotIndex + 1,
      message: switch (phase) {
        WindDartsPhase.impact when _pendingImpact != null =>
          '${_pendingImpact!.score}점',
        WindDartsPhase.opponentImpact when _opponentPendingScore != null =>
          '상대 $_opponentPendingScore점',
        _ => null,
      },
    );
    if (_controllerDisposed || _sameHudState(hud.value, nextState)) return;

    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      hud.value = nextState;
      return;
    }

    _pendingHudState = nextState;
    if (_hudPublishScheduled) return;
    _hudPublishScheduled = true;
    scheduler.addPostFrameCallback((_) {
      _hudPublishScheduled = false;
      final pending = _pendingHudState;
      _pendingHudState = null;
      if (_controllerDisposed ||
          pending == null ||
          _sameHudState(hud.value, pending)) {
        return;
      }
      hud.value = pending;
    });
  }

  bool _sameHudState(MiniGameHudState a, MiniGameHudState b) =>
      a.phase == b.phase &&
      a.score == b.score &&
      a.elapsedSeconds == b.elapsedSeconds &&
      a.remainingSeconds == b.remainingSeconds &&
      a.countdownNumber == b.countdownNumber &&
      a.distance == b.distance &&
      a.comboRemainingPercent == b.comboRemainingPercent &&
      a.message == b.message &&
      a.primaryActionEnabled == b.primaryActionEnabled &&
      a.primaryActionLabel == b.primaryActionLabel;

  @override
  void interrupt() {
    if (_terminal) return;
    _terminal = true;
    phase = WindDartsPhase.interrupted;
    _activePointer = -1;
    pauseEngine();
  }

  @override
  void disposeController() {
    _controllerDisposed = true;
    if (_terminal && phase == WindDartsPhase.finished) {
      hud.dispose();
      return;
    }
    _terminal = true;
    _activePointer = -1;
    pauseEngine();
    hud.dispose();
  }
}

class _WindDartsScene extends Component {
  _WindDartsScene(this.game, this.assets);

  final WindDartsGame game;
  final WindDartsArtImages assets;
  static const _cream = Color(0xFFE9E0C9);
  static const _brass = Color(0xFFB5945D);
  static const _gold = Color(0xFFFFC84A);
  static const _ledgerInk = Color(0xFF392316);
  static const _ledgerMutedInk = Color(0xFF684328);
  static final _spritePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  @override
  void render(Canvas canvas) {
    WindDartsArt.drawWorld(
      canvas,
      pivot: WindDartsGame.boardCenter,
      zoom: game.cameraZoom,
      focusOffset: game.cameraFocusOffset,
      draw: () {
        _drawBackground(canvas);
        _drawBoard(canvas);
        if (game.phase == WindDartsPhase.opponentIntro) {
          _drawOpponentIntro(canvas);
        } else if (game.phase == WindDartsPhase.opponentPreview) {
          _drawOpponentIntro(canvas, showSmoke: false, showNickname: false);
        }
        if (game.phase == WindDartsPhase.flight) _drawFlightDart(canvas);
        if (game.phase == WindDartsPhase.opponentFlight) {
          _drawOpponentFlightDart(canvas);
        }
      },
    );
    _drawHud(canvas);
  }

  void _drawBackground(Canvas canvas) {
    WindDartsArt.drawPubBackground(
      canvas,
      assets.pubInterior,
      const Size(360, 640),
    );
  }

  void _drawBoard(Canvas canvas) {
    Offset? embeddedTip;
    Offset? embeddedTailDirection;
    final isPlayerImpact =
        game.phase == WindDartsPhase.impact && game._pendingImpact != null;
    final isOpponentImpact =
        game.phase == WindDartsPhase.opponentImpact &&
        game._opponentPendingScore != null;
    if (isPlayerImpact || isOpponentImpact) {
      final target = isOpponentImpact
          ? game._opponentFlightWorldTarget
          : game._flightWorldTarget;
      final tailDirection = isOpponentImpact
          ? game._opponentFlightTailDirectionWorld
          : game._flightTailDirectionWorld;
      embeddedTip = WindDartsArt.toBoardLocalVector(
        target - WindDartsGame.boardCenter,
        game.boardAngle,
      );
      embeddedTailDirection = WindDartsArt.toBoardLocalVector(
        tailDirection,
        game.boardAngle,
      );
    }
    WindDartsArt.drawBoard(
      canvas: canvas,
      boardFace: assets.boardFace,
      boardNumbers: assets.boardNumbers,
      center: WindDartsGame.boardCenter,
      logicalBoardRadius: WindDartsArt.worldBoardRadius,
      boardAngle: game.boardAngle,
      dartAtlas: assets.dartAtlas,
      embeddedTip: embeddedTip,
      embeddedTailDirection: embeddedTailDirection,
      embeddedGoldenDart: isPlayerImpact
          ? game._pendingImpact!.isGoldenDart
          : WindDartsRules.isGoldenDart(game.shotIndex),
      embeddedImpactProgress: isPlayerImpact
          ? game._phaseElapsed /
                (WindDartsRules.impactDisplayDuration.inMicroseconds / 1e6)
          : isOpponentImpact
          ? game._phaseElapsed /
                (WindDartsGame.opponentDartImpactDuration.inMicroseconds / 1e6)
          : 0,
      embeddedImpactKind: isPlayerImpact ? game._pendingImpact!.kind : null,
      embeddedImpactElapsed: isPlayerImpact ? game._phaseElapsed : 0,
      embeddedImpactRadiusScale: 1 / game.cameraZoom,
      embeddedImpactClipRect: isPlayerImpact ? _boardEffectClipRectWorld : null,
    );
  }

  Rect get _boardEffectClipRectWorld {
    final zoom = game.cameraZoom;
    const pivot = WindDartsGame.boardCenter;
    return Rect.fromLTRB(
      pivot.dx + (0 - pivot.dx) / zoom,
      pivot.dy + (70 - pivot.dy) / zoom,
      pivot.dx + (360 - pivot.dx) / zoom,
      pivot.dy + (410 - pivot.dy) / zoom,
    );
  }

  void _drawFlightDart(Canvas canvas) {
    final progress = (game._phaseElapsed / game._flightDuration).clamp(
      0.0,
      1.0,
    );
    final tip = Offset.lerp(
      game._flightWorldStart,
      game._flightWorldTarget,
      progress * progress,
    )!;
    WindDartsArt.drawDart(
      canvas,
      atlas: assets.dartAtlas,
      cell: 0,
      tip: tip,
      tailDirection: game._flightTailDirectionWorld,
      scale: WindDartsArt.dartScaleForBoardRadius(
        WindDartsArt.worldBoardRadius,
      ),
      golden: WindDartsRules.isGoldenDart(game.shotIndex),
    );
  }

  void _drawOpponentFlightDart(Canvas canvas) {
    final progress =
        (game._phaseElapsed /
                (WindDartsGame.opponentDartFlightDuration.inMicroseconds / 1e6))
            .clamp(0.0, 1.0);
    final tip = Offset.lerp(
      game._opponentFlightWorldStart,
      game._opponentFlightWorldTarget,
      progress * progress,
    )!;
    WindDartsArt.drawDart(
      canvas,
      atlas: assets.dartAtlas,
      cell: 0,
      tip: tip,
      tailDirection: game._opponentFlightTailDirectionWorld,
      scale: WindDartsArt.dartScaleForBoardRadius(
        WindDartsArt.worldBoardRadius,
      ),
      golden: WindDartsRules.isGoldenDart(game.shotIndex),
    );
  }

  void _drawHud(Canvas canvas) {
    if (game.phase == WindDartsPhase.opponentIntro ||
        game.phase == WindDartsPhase.opponentPreview ||
        game.phase == WindDartsPhase.boardApproach) {
      return;
    }

    _drawWindPanel(canvas);

    _text(
      canvas,
      'THROW  ${min(game.shotIndex + 1, WindDartsRules.shotCount)} / ${WindDartsRules.shotCount}',
      const Offset(226, 16),
      11,
      _brass,
    );
    _text(canvas, 'TOTAL  ${game.score}', const Offset(226, 36), 12, _cream);

    final distance = WindDartsRules.distanceLabelForShot(game.shotIndex);
    final isGoldenRound = WindDartsRules.isGoldenDart(game.shotIndex);
    _text(
      canvas,
      isGoldenRound ? '$distance  ·  GOLD · 점수2배' : distance,
      const Offset(180, 425),
      12,
      isGoldenRound ? _brass : _cream,
      centered: true,
    );
    if (game.phase != WindDartsPhase.loading &&
        game.phase != WindDartsPhase.countdown) {
      _drawScoreLedger(canvas);
    }
    if (game.phase == WindDartsPhase.countdown) {
      _text(
        canvas,
        '${max(0, (game.countdownDuration.inSeconds - game._countdownElapsed).ceil())}',
        const Offset(180, 470),
        44,
        _cream,
        centered: true,
      );
    } else if (game.phase == WindDartsPhase.shotPreview ||
        game.phase == WindDartsPhase.aiming) {
      final sample = game.phase == WindDartsPhase.aiming
          ? game.currentAim
          : null;
      if (sample != null) {
        _drawCrosshair(canvas, WindDartsGame.boardCenter + sample.offset);
      }
      _text(
        canvas,
        game.cameraRetreating ? '뒤로 이동 중' : 'AIM TIME',
        const Offset(245, 558),
        10,
        _brass,
        centered: true,
        centerMinX: 140,
        centerMaxX: 350,
      );
      _text(
        canvas,
        game.phase == WindDartsPhase.aiming
            ? 'DRAG TO AIM · RELEASE TO THROW'
            : 'HOLD TO AIM',
        const Offset(245, 572),
        9,
        _cream,
        centered: true,
        centerMinX: 140,
        centerMaxX: 350,
      );
      final power = game.phase == WindDartsPhase.aiming
          ? game.currentAim.power
          : 0.0;
      WindDartsArt.drawAimGauge(
        canvas,
        frame: assets.aimGaugeFrame,
        fill: assets.aimGaugeFill,
        fraction: power,
      );
    } else if (game.phase == WindDartsPhase.impact &&
        game._pendingImpact != null) {
      _drawImpactFx(canvas);
    } else if (game.phase == WindDartsPhase.opponentFlight) {
      _text(
        canvas,
        '${game.opponent?.nickname ?? '상대'} 차례',
        const Offset(245, 558),
        11,
        _brass,
        centered: true,
        centerMinX: 140,
        centerMaxX: 350,
      );
    } else if (game.phase == WindDartsPhase.opponentImpact) {
      _drawOpponentImpactFx(canvas);
    } else if (game.phase == WindDartsPhase.finished) {
      _text(
        canvas,
        'TOTAL  ${game.score}',
        const Offset(180, 530),
        20,
        _brass,
        centered: true,
      );
    }
  }

  void _drawWindPanel(Canvas canvas) {
    final wind = game.currentWind;
    final direction = wind.unitVector;
    final titlePainter = TextPainter(
      text: const TextSpan(
        text: 'WIND',
        style: TextStyle(
          color: Color(0xFFCBB998),
          fontFamily: 'Galmuri',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          shadows: <Shadow>[],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final valuePainter = TextPainter(
      text: TextSpan(
        text: wind.metersPerSecond.toStringAsFixed(1),
        style: const TextStyle(
          color: Color(0xFFF2E6CB),
          fontFamily: 'Galmuri',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          shadows: <Shadow>[],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final unitPainter = TextPainter(
      text: const TextSpan(
        text: 'm/s',
        style: TextStyle(
          color: Color(0xFFB7A181),
          fontFamily: 'Galmuri',
          fontSize: 10,
          fontWeight: FontWeight.w400,
          shadows: <Shadow>[],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const arrowWidth = 18.0;
    const titleArrowGap = 10.0;
    const arrowValueGap = 10.0;
    const unitGap = 4.0;
    final groupWidth =
        titlePainter.width +
        titleArrowGap +
        arrowWidth +
        arrowValueGap +
        valuePainter.width +
        unitGap +
        unitPainter.width;
    final groupStart = 127 - groupWidth / 2;
    final arrowBoxStart = groupStart + titlePainter.width + titleArrowGap;
    final arrowCenter = Offset(arrowBoxStart + arrowWidth / 2, 29);
    final arrowStart = Offset(
      arrowCenter.dx - direction.dx * arrowWidth / 2,
      arrowCenter.dy - direction.dy * arrowWidth / 2,
    );
    final arrowTip = Offset(
      arrowCenter.dx + direction.dx * arrowWidth / 2,
      arrowCenter.dy + direction.dy * arrowWidth / 2,
    );
    final arrowPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xFFE4BB72)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(arrowStart, arrowTip, arrowPaint);
    final perpendicular = Offset(-direction.dy, direction.dx);
    final arrowBase = arrowTip - direction * 6;
    final arrowHead = Path()
      ..moveTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(
        arrowBase.dx + perpendicular.dx * 3,
        arrowBase.dy + perpendicular.dy * 3,
      )
      ..lineTo(
        arrowBase.dx - perpendicular.dx * 3,
        arrowBase.dy - perpendicular.dy * 3,
      )
      ..close();
    canvas.drawPath(
      arrowHead,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0xFFE4BB72),
    );

    final valueBaseline = valuePainter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final unitBaseline = unitPainter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    titlePainter.paint(
      canvas,
      Offset(groupStart, 29 - titlePainter.height / 2),
    );
    final sharedAscent = max(valueBaseline, unitBaseline);
    final sharedDescent = max(
      valuePainter.height - valueBaseline,
      unitPainter.height - unitBaseline,
    );
    final sharedBaseline = 29 + (sharedAscent - sharedDescent) / 2;
    valuePainter.paint(
      canvas,
      Offset(
        arrowBoxStart + arrowWidth + arrowValueGap,
        sharedBaseline - valueBaseline,
      ),
    );
    unitPainter.paint(
      canvas,
      Offset(
        arrowBoxStart +
            arrowWidth +
            arrowValueGap +
            valuePainter.width +
            unitGap,
        sharedBaseline - unitBaseline,
      ),
    );
  }

  void _drawScoreLedger(Canvas canvas) {
    WindDartsArt.drawScoreParchment(canvas, assets.scoreParchment);
    final separatorPaint = Paint()
      ..color = _ledgerInk.withAlpha(64)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      const Offset(24, 441),
      const Offset(118, 441),
      separatorPaint,
    );
    canvas.drawLine(
      const Offset(24, 544),
      const Offset(118, 544),
      separatorPaint,
    );
    _ledgerText(
      canvas,
      'R',
      const Offset(34, 432),
      color: _ledgerMutedInk,
      centered: true,
    );
    _ledgerText(
      canvas,
      '나',
      const Offset(70, 432),
      color: _ledgerMutedInk,
      centered: true,
    );
    _ledgerText(
      canvas,
      '상대',
      const Offset(106, 432),
      color: _ledgerMutedInk,
      centered: true,
    );
    for (var index = 0; index < WindDartsRules.shotCount; index++) {
      final y = 450 + index * 14.0;
      final mine = index < game.shotRecords.length
          ? '${game.shotRecords[index].score}'
          : '—';
      final opponent = _opponentShotScore(index);
      _ledgerText(
        canvas,
        '${index + 1}R',
        Offset(34, y),
        color: _ledgerInk,
        centered: true,
      );
      _ledgerText(
        canvas,
        mine,
        Offset(70, y),
        color: _ledgerInk,
        centered: true,
      );
      _ledgerText(
        canvas,
        opponent == null ? '—' : '$opponent',
        Offset(106, y),
        color: _ledgerInk,
        centered: true,
      );
    }
    _ledgerText(
      canvas,
      '총합',
      const Offset(34, 554),
      color: _ledgerInk,
      centered: true,
      fontWeight: FontWeight.w600,
    );
    _ledgerText(
      canvas,
      '${game.score}',
      const Offset(70, 554),
      color: _ledgerInk,
      centered: true,
      fontWeight: FontWeight.w600,
    );
    _ledgerText(
      canvas,
      '${game._revealedOpponentTotal}',
      const Offset(106, 554),
      color: _ledgerInk,
      centered: true,
      fontWeight: FontWeight.w600,
    );
  }

  void _ledgerText(
    Canvas canvas,
    String text,
    Offset position, {
    required Color color,
    bool centered = false,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    _text(
      canvas,
      text,
      position,
      10,
      color,
      centered: centered,
      fontWeight: fontWeight,
    );
  }

  int? _opponentShotScore(int index) {
    if (index > game._opponentRevealedThrough) return null;
    final opponent = game.opponent;
    if (opponent == null || index >= opponent.shotScores.length) return null;
    return opponent.shotScores[index];
  }

  void _drawOpponentIntro(
    Canvas canvas, {
    bool showSmoke = true,
    bool showNickname = true,
  }) {
    final frame = min(
      5,
      (game._phaseElapsed / WindDartsGame._opponentIntroFrameSeconds).floor(),
    );
    const cellWidth = 128.0;
    const cellHeight = 184.0;
    final characterRect = Rect.fromLTWH(58.4, 187.5, 243.2, 349.6);
    canvas.drawImageRect(
      assets.opponentVictory,
      Rect.fromLTWH(
        (frame % 2) * cellWidth,
        (frame ~/ 2) * cellHeight,
        cellWidth,
        cellHeight,
      ),
      characterRect,
      _spritePaint,
    );

    if (showSmoke) {
      final smokeElapsed =
          game._phaseElapsed - WindDartsGame._opponentSmokeStartSeconds;
      if (smokeElapsed >= 0 &&
          smokeElapsed < 4 * WindDartsGame._opponentSmokeFrameSeconds) {
        final smokeFrame =
            (smokeElapsed / WindDartsGame._opponentSmokeFrameSeconds)
                .floor()
                .clamp(0, 3);
        canvas.drawImageRect(
          assets.victorySmoke,
          Rect.fromLTWH((smokeFrame % 2) * 64, (smokeFrame ~/ 2) * 64, 64, 64),
          Rect.fromCenter(
            center: Offset(
              characterRect.left + characterRect.width * (56 / 128),
              characterRect.top + characterRect.height * (38 / 184),
            ),
            width: 121.6,
            height: 121.6,
          ),
          _spritePaint,
        );
      }
    }

    _text(
      canvas,
      '대결 상대',
      const Offset(180, 120),
      10,
      _cream.withAlpha(210),
      centered: true,
      centerMinX: 10,
      centerMaxX: 350,
    );
    if (showNickname) {
      _text(
        canvas,
        game.opponent?.nickname ?? '펍의 단골',
        const Offset(180, 138),
        13,
        _cream,
        centered: true,
        centerMinX: 10,
        centerMaxX: 350,
      );
    }
  }

  void _drawOpponentImpactFx(Canvas canvas) {
    final score = game._opponentPendingScore;
    if (score == null) return;
    final progress =
        (game._phaseElapsed /
                (WindDartsGame.opponentDartImpactDuration.inMicroseconds / 1e6))
            .clamp(0.0, 1.0);
    final opacity = ((1 - progress) * 255).round().clamp(0, 255);
    final target =
        WindDartsGame.boardCenter +
        (game._opponentFlightWorldTarget - WindDartsGame.boardCenter) *
            game.cameraZoom;
    final scoreY = (target.dy - 24 - progress * 36).clamp(100.0, 410.0);
    final isGolden = WindDartsRules.isGoldenDart(game.shotIndex);
    _text(
      canvas,
      '$score점',
      Offset(target.dx, scoreY),
      36,
      (isGolden ? _brass : _cream).withAlpha(opacity),
      centered: true,
      scale: _impactScorePop(game._phaseElapsed),
      centerMinX: 12,
      centerMaxX: 348,
      maxWidth: 336,
    );
    _text(
      canvas,
      isGolden
          ? 'GOLD ×2  ${score ~/ 2}×2=$score'
          : game.opponent?.nickname ?? '상대',
      Offset(target.dx, scoreY + 28),
      12,
      _brass.withAlpha(opacity),
      centered: true,
      centerMinX: 12,
      centerMaxX: 348,
      maxWidth: 336,
    );
  }

  void _drawImpactFx(Canvas canvas) {
    final impact = game._pendingImpact;
    if (impact == null) return;
    final progress =
        (game._phaseElapsed /
                (WindDartsRules.impactDisplayDuration.inMicroseconds / 1e6))
            .clamp(0.0, 1.0);
    final opacity = ((1 - progress) * 255).round().clamp(0, 255);
    final isMultiplier =
        impact.kind == WindDartsImpactKind.double ||
        impact.kind == WindDartsImpactKind.triple;
    final isSpecial =
        isMultiplier ||
        impact.kind == WindDartsImpactKind.singleBull ||
        impact.kind == WindDartsImpactKind.doubleBull ||
        impact.isGoldenDart;
    final scoreSize = isMultiplier
        ? 58.0
        : isSpecial
        ? 52.0
        : 42.0;
    final scoreY = 500 - progress * 52;
    _text(
      canvas,
      '${impact.score}점',
      Offset(280, scoreY),
      scoreSize,
      (impact.isGoldenDart ? _brass : _cream).withAlpha(opacity),
      centered: true,
      centerMinX: 140,
      centerMaxX: 350,
      scale: _impactScorePop(game._phaseElapsed),
      maxWidth: 210,
    );
    final kindLabel = switch (impact.kind) {
      WindDartsImpactKind.miss => 'MISS',
      WindDartsImpactKind.single => 'SINGLE',
      WindDartsImpactKind.double => 'DOUBLE',
      WindDartsImpactKind.triple => 'TRIPLE',
      WindDartsImpactKind.singleBull => 'S-BULL',
      WindDartsImpactKind.doubleBull => 'D-BULL',
    };
    _text(
      canvas,
      kindLabel,
      Offset(280, scoreY + 44),
      23,
      _brass.withAlpha(opacity),
      centered: true,
      centerMinX: 140,
      centerMaxX: 350,
      maxWidth: 210,
    );
    if (impact.isGoldenDart) {
      _text(
        canvas,
        'GOLD ×2  ${impact.score ~/ 2}×2=${impact.score}',
        Offset(280, scoreY + 70),
        17,
        _gold.withAlpha(opacity),
        centered: true,
        centerMinX: 140,
        centerMaxX: 350,
        maxWidth: 210,
      );
    }
  }

  double _impactScorePop(double elapsed) {
    if (elapsed <= 0) return 0.85;
    if (elapsed >= 0.18) return 1;
    if (elapsed <= 0.09) {
      return 0.85 + 0.27 * (elapsed / 0.09);
    }
    return 1.12 - 0.12 * ((elapsed - 0.09) / 0.09);
  }

  void _drawCrosshair(Canvas canvas, Offset point, {double radius = 8}) {
    final paint = Paint()
      ..color = const Color(0xFFFFE8B7)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(point, radius, paint);
    canvas.drawLine(
      point - Offset(radius + 4, 0),
      point + Offset(radius + 4, 0),
      paint,
    );
    canvas.drawLine(
      point - Offset(0, radius + 4),
      point + Offset(0, radius + 4),
      paint,
    );
    canvas.drawCircle(point, 1.4, Paint()..color = const Color(0xFFFFE8B7));
  }

  void _text(
    Canvas canvas,
    String text,
    Offset position,
    double size,
    Color color, {
    bool centered = false,
    double scale = 1,
    double? centerMinX,
    double? centerMaxX,
    FontWeight fontWeight = FontWeight.w800,
    double? letterSpacing,
    bool? shadows,
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: 'Galmuri',
          fontSize: size,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
          height: 1.05,
          shadows:
              shadows == false ||
                  color == _ledgerInk ||
                  color == _ledgerMutedInk
              ? const []
              : const [Shadow(color: Color(0xFF100B07), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var textScale = scale;
    if (maxWidth != null && painter.width > 0) {
      textScale = min(textScale, maxWidth / painter.width);
    }
    var centerX = position.dx;
    if (centered && centerMinX != null && centerMaxX != null) {
      final halfWidth = painter.width * textScale / 2;
      final minCenter = centerMinX + halfWidth;
      final maxCenter = centerMaxX - halfWidth;
      centerX = minCenter <= maxCenter
          ? centerX.clamp(minCenter, maxCenter)
          : (centerMinX + centerMaxX) / 2;
    }
    if (textScale == 1) {
      painter.paint(
        canvas,
        centered
            ? Offset(
                centerX - painter.width / 2,
                position.dy - painter.height / 2,
              )
            : position,
      );
      return;
    }
    canvas.save();
    canvas.translate(centerX, position.dy);
    canvas.scale(textScale);
    painter.paint(
      canvas,
      centered ? Offset(-painter.width / 2, -painter.height / 2) : Offset.zero,
    );
    canvas.restore();
  }
}
