import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_opponent.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_art.dart';

enum WindDartsPhase {
  loading,
  countdown,
  shotPreview,
  aiming,
  flight,
  impact,
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
  WindDartsImpact? _pendingImpact;
  WindDartsAimSample? _shotAim;
  Offset _shotOffset = Offset.zero;
  double _displayedBoardScale = 1;
  double _launchBoardRadius = WindDartsRules.baseBoardRadius;
  double _launchCameraZoom = WindDartsArt.worldZoomForShotScale(1);
  Offset _flightWorldStart = boardCenter;
  Offset _flightWorldTarget = boardCenter;
  Offset _flightTailDirectionWorld = const Offset(0, 1);
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

  void setOpponent(WindDartsOpponent value) => opponent = value;

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
    if (countdownDuration == Duration.zero) {
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
    _elapsed += elapsedStep;
    _updateCameraRetreat(step);
    if (phase == WindDartsPhase.countdown) {
      _countdownElapsed += step;
      if (_countdownElapsed >= countdownDuration.inMicroseconds / 1e6) {
        phase = WindDartsPhase.shotPreview;
      }
    } else if (phase == WindDartsPhase.aiming) {
      _holdElapsed += step;
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
          );
          if (_pendingImpact != null) shotRecords.add(_pendingImpact!);
        }
      } else if (phase == WindDartsPhase.impact &&
          _phaseElapsed >=
              WindDartsRules.impactDisplayDuration.inMicroseconds / 1e6) {
        _shotIndex++;
        if (_shotIndex >= WindDartsRules.shotCount) {
          _finish();
        } else {
          phase = WindDartsPhase.shotPreview;
          _phaseElapsed = 0;
          _pendingImpact = null;
          _shotAim = null;
          _beginCameraRetreat();
        }
      }
    }
    _publishHud();
  }

  double get _flightDuration => 0.72 + _shotIndex * 0.05;

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
    hud.value = MiniGameHudState(
      phase: switch (phase) {
        WindDartsPhase.loading ||
        WindDartsPhase.countdown => MiniGamePhase.countdown,
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
      message: phase == WindDartsPhase.impact && _pendingImpact != null
          ? '${_pendingImpact!.score}점'
          : null,
    );
  }

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
  static const _ledgerInk = Color(0xFF392316);
  static const _ledgerMutedInk = Color(0xFF684328);

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
        if (game.phase == WindDartsPhase.flight) _drawFlightDart(canvas);
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
    if (game.phase == WindDartsPhase.impact && game._pendingImpact != null) {
      embeddedTip = WindDartsArt.toBoardLocalVector(
        game._flightWorldTarget - WindDartsGame.boardCenter,
        game.boardAngle,
      );
      embeddedTailDirection = WindDartsArt.toBoardLocalVector(
        game._flightTailDirectionWorld,
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
      embeddedImpactProgress: game.phase == WindDartsPhase.impact
          ? game._phaseElapsed /
                (WindDartsRules.impactDisplayDuration.inMicroseconds / 1e6)
          : 0,
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
    );
  }

  void _drawHud(Canvas canvas) {
    _text(
      canvas,
      'WIND  ${game.currentWind.metersPerSecond.toStringAsFixed(1)} m/s',
      const Offset(71, 16),
      12,
      _brass,
    );
    final direction = game.currentWind.unitVector;
    final from = const Offset(83, 44);
    final to = from + direction * 9;
    final arrowPaint = Paint()
      ..color = const Color(0xFFFFE2A1)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(from, to, arrowPaint);
    canvas.drawLine(
      to,
      to - Offset(direction.dy, -direction.dx) * 4 - direction * 3,
      arrowPaint,
    );
    canvas.drawLine(
      to,
      to + Offset(direction.dy, -direction.dx) * 4 - direction * 3,
      arrowPaint,
    );
    _text(
      canvas,
      '${game.currentWind.label} 바람',
      const Offset(96, 36),
      10,
      _cream,
    );

    _text(
      canvas,
      'THROW  ${min(game.shotIndex + 1, WindDartsRules.shotCount)} / ${WindDartsRules.shotCount}',
      const Offset(226, 16),
      11,
      _brass,
    );
    _text(canvas, 'TOTAL  ${game.score}', const Offset(226, 36), 12, _cream);

    final distance = WindDartsRules.distanceLabelForShot(game.shotIndex);
    _text(canvas, distance, const Offset(180, 425), 12, _cream, centered: true);
    if (game.shotRecords.isNotEmpty) _drawScoreLedger(canvas);
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

  void _drawScoreLedger(Canvas canvas) {
    WindDartsArt.drawScoreParchment(canvas, assets.scoreParchment);
    _ledgerText(
      canvas,
      'R',
      const Offset(27, 432),
      color: _ledgerMutedInk,
      centered: true,
    );
    _ledgerText(
      canvas,
      '나',
      const Offset(67, 432),
      color: _ledgerMutedInk,
      centered: true,
    );
    _ledgerText(
      canvas,
      '상대',
      const Offset(105, 432),
      color: _ledgerMutedInk,
      centered: true,
    );
    const baselineOffsets = <double>[0, 0.6, -0.3, 0.5, -0.2, 0.35];
    for (var index = 0; index < WindDartsRules.shotCount; index++) {
      final y = 445 + index * 20.0 + baselineOffsets[index];
      final mine = index < game.shotRecords.length
          ? '${game.shotRecords[index].score}'
          : '—';
      final opponent = _opponentShotScore(index);
      final ink = _ledgerInk.withAlpha(index.isEven ? 242 : 224);
      _ledgerText(
        canvas,
        '${index + 1}R',
        Offset(27, y),
        color: ink,
        centered: true,
      );
      _ledgerText(canvas, mine, Offset(67, y), color: ink, centered: true);
      _ledgerText(
        canvas,
        opponent == null ? '—' : '$opponent',
        Offset(105, y),
        color: ink,
        centered: true,
      );
    }
  }

  void _ledgerText(
    Canvas canvas,
    String text,
    Offset position, {
    required Color color,
    bool centered = false,
  }) {
    _text(
      canvas,
      text,
      position,
      10,
      color,
      centered: centered,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      shadows: false,
    );
  }

  int? _opponentShotScore(int index) {
    final opponent = game.opponent;
    if (opponent == null || index >= opponent.shotScores.length) return null;
    return opponent.shotScores[index];
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
        isMultiplier || impact.kind == WindDartsImpactKind.doubleBull;
    final scoreSize = isMultiplier
        ? 84.0
        : isSpecial
        ? 68.0
        : 46.0;
    final scoreY = 500 - progress * 52;
    final pulse = isSpecial ? 1 + sin(progress * pi * 8) * 0.08 : 1.0;
    _text(
      canvas,
      '${impact.score}점',
      Offset(280, scoreY),
      scoreSize,
      _cream.withAlpha(opacity),
      centered: true,
      scale: pulse,
      centerMinX: 140,
      centerMaxX: 350,
    );
    final subtitle = switch (impact.kind) {
      WindDartsImpactKind.double => 'DOUBLE',
      WindDartsImpactKind.triple => 'TRIPLE',
      WindDartsImpactKind.doubleBull => 'D-BULL',
      _ => null,
    };
    if (subtitle != null) {
      _text(
        canvas,
        subtitle,
        Offset(280, scoreY + (isMultiplier ? 70 : 48)),
        isMultiplier ? 32 : 24,
        _brass.withAlpha(opacity),
        centered: true,
        centerMinX: 140,
        centerMaxX: 350,
      );
    }
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
    var centerX = position.dx;
    if (centered && centerMinX != null && centerMaxX != null) {
      final halfWidth = painter.width * scale / 2;
      final minCenter = centerMinX + halfWidth;
      final maxCenter = centerMaxX - halfWidth;
      centerX = minCenter <= maxCenter
          ? centerX.clamp(minCenter, maxCenter)
          : (centerMinX + centerMaxX) / 2;
    }
    if (scale == 1) {
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
    canvas.scale(scale);
    painter.paint(
      canvas,
      centered ? Offset(-painter.width / 2, -painter.height / 2) : Offset.zero,
    );
    canvas.restore();
  }
}
