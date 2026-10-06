import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/domain/ten_pitch_slugger_rules.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_motion.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_scene.dart';

enum TenPitchSluggerPhase {
  countdown,
  safeOpening,
  sluggerEntrance,
  windup,
  pitchFlight,
  feedback,
  finished,
}

class TenPitchSluggerGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  TenPitchSluggerGame({
    required this.onFinished,
    required int challengeSeed,
    this.countdownDuration = const Duration(seconds: 3),
    this.watchdogDuration = TenPitchSluggerRules.watchdogDuration,
  }) : pitches = TenPitchSluggerRules.buildPitchSequence(Random(challengeSeed)),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: null,
           countdownNumber: countdownDuration.inSeconds,
           distance: 1,
         ),
       );

  static final logicalSize = Vector2(360, 640);
  static final backgroundSize = Vector2(360, 720);
  static const safeOpeningDuration = TenPitchSluggerRules.safeOpeningSeconds;
  static const regularWindupDuration = 0.92;
  static const sluggerEntranceDuration = 1.6;
  static const magicWindupDuration = 1.28;
  static const missFeedbackDuration = 1.08;
  static const missedBallExitDuration = 0.58;
  static const farFlightCoastDuration = 0.42;
  static const finalResultHoldDuration = 0.40;

  final Duration countdownDuration;
  final Duration watchdogDuration;
  final ValueChanged<GameResult> onFinished;
  final List<TenPitchSpec> pitches;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _TenPitchBallpark _ballpark;
  var _phase = TenPitchSluggerPhase.countdown;
  var _phaseElapsed = 0.0;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _pitchIndex = 0;
  var _bestDistanceCm = 0;
  var _hits = 0;
  var _misses = 0;
  var _lastDistanceCm = 0;
  var _resolvedFlightElapsed = 0.0;
  var _lastJudgement = TenPitchJudgement.watched;
  TenPitchHitType? _lastHitType;
  var _lastLaunchDirection = 0.0;
  var _hasTappedThisPitch = false;
  double? _tapTime;
  double? _pendingTapTime;
  double? _lastSwingPlayingElapsed;
  var _swingCount = 0;
  var _hasFinished = false;
  var _assetsReady = false;
  var _resultReported = false;

  TenPitchSluggerPhase get gamePhase => _phase;
  TenPitchSpec get currentPitch => pitches[_pitchIndex];
  int get pitchNumber => _pitchIndex + 1;
  int get bestDistanceCm => _bestDistanceCm;
  int get lastDistanceCm => _lastDistanceCm;
  double get resolvedFlightElapsed => _resolvedFlightElapsed;
  TenPitchJudgement get lastJudgement => _lastJudgement;
  TenPitchHitType? get lastHitType => _lastHitType;
  double get lastLaunchDirection => _lastLaunchDirection;
  int get hits => _hits;
  int get misses => _misses;
  bool get hasTappedThisPitch => _hasTappedThisPitch;
  int get swingCount => _swingCount;
  double get phaseElapsed => _phaseElapsed;
  bool get assetsReady => _assetsReady;
  bool get usesSluggerBatter =>
      pitchNumber == TenPitchSluggerRules.sluggerPitchNumber;

  @override
  Color backgroundColor() => const Color(0xFF11152A);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    final loaded = await images.loadAll(const [
      'ten_pitch_slugger/background_hitter_v4.png',
      'ten_pitch_slugger/batter_rear_idle_v3.png',
      'ten_pitch_slugger/batter_rear_swing_v4.png',
      'ten_pitch_slugger/batter_rear_whiff_v3.png',
      'ten_pitch_slugger/batter_rear_result_v3.png',
      'ten_pitch_slugger/batter_slugger_idle_v3.png',
      'ten_pitch_slugger/batter_slugger_swing_v3.png',
      'ten_pitch_slugger/batter_slugger_whiff_v3.png',
      'ten_pitch_slugger/batter_slugger_result_v3.png',
      'ten_pitch_slugger/pitcher_front_idle_v3.png',
      'ten_pitch_slugger/pitcher_front_pitch_v3.png',
      'ten_pitch_slugger/pitcher_front_magic_v3.png',
      'ten_pitch_slugger/ball_spin_v4.png',
      'ten_pitch_slugger/hit_fx_v4.png',
      'ten_pitch_slugger/trail_fx_v3.png',
    ]);

    _ballpark = _TenPitchBallpark(
      game: this,
      background: loaded[0],
      batterIdle: loaded[1],
      batterSwing: loaded[2],
      batterWhiff: loaded[3],
      batterResult: loaded[4],
      sluggerBatterIdle: loaded[5],
      sluggerBatterSwing: loaded[6],
      sluggerBatterWhiff: loaded[7],
      sluggerBatterResult: loaded[8],
      pitcherIdle: loaded[9],
      pitcherPitch: loaded[10],
      pitcherMagic: loaded[11],
      ball: loaded[12],
      hitFx: loaded[13],
      trailFx: loaded[14],
    );
    await world.add(_ballpark);
    _assetsReady = true;

    if (countdownDuration == Duration.zero) _startSafeOpening();
    _publishHud();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hasFinished || !_assetsReady) return;

    if (_phase == TenPitchSluggerPhase.countdown) {
      _countdownElapsed += dt;
      if (_countdownElapsed >= _seconds(countdownDuration)) {
        _startSafeOpening();
      }
      _publishHud();
      return;
    }

    _playingElapsed += dt;
    if (_playingElapsed >= _seconds(watchdogDuration)) {
      interrupt();
      return;
    }

    _phaseElapsed += dt;
    switch (_phase) {
      case TenPitchSluggerPhase.safeOpening:
        if (_phaseElapsed >= safeOpeningDuration) _startWindup();
      case TenPitchSluggerPhase.sluggerEntrance:
        if (_phaseElapsed >= sluggerEntranceDuration) _startWindup();
      case TenPitchSluggerPhase.windup:
        final duration = currentPitch.movement == TenPitchMovement.magic
            ? magicWindupDuration
            : regularWindupDuration;
        if (_phaseElapsed >= duration) _releasePitch();
      case TenPitchSluggerPhase.pitchFlight:
        final pendingTapTime = _pendingTapTime;
        if (pendingTapTime != null &&
            _phaseElapsed >=
                pendingTapTime + TenPitchSluggerRules.swingLeadSeconds) {
          final distance = TenPitchSluggerRules.distanceForTiming(
            pitch: currentPitch,
            timingErrorSeconds: pendingTapTime - currentPitch.idealTapSeconds,
          );
          if (distance > 0) {
            _resolvePitch(pendingTapTime);
          } else {
            _lastJudgement = TenPitchSluggerRules.judgementForTiming(
              pitch: currentPitch,
              timingErrorSeconds: pendingTapTime - currentPitch.idealTapSeconds,
            );
            _pendingTapTime = null;
          }
        }
        if (_phase == TenPitchSluggerPhase.pitchFlight &&
            _phaseElapsed >= currentPitch.flightSeconds) {
          _resolvePitch(_tapTime);
        }
      case TenPitchSluggerPhase.feedback:
        final hitType = _lastHitType;
        var duration = hitType == null
            ? max(
                missFeedbackDuration,
                max(0.0, currentPitch.flightSeconds - _resolvedFlightElapsed) +
                    missedBallExitDuration,
              )
            : TenPitchSluggerMotion.hitStopDurationFor(hitType) +
                  TenPitchSluggerMotion.launchDurationFor(hitType) +
                  farFlightCoastDuration;
        if (pitchNumber == TenPitchSluggerRules.pitchCount) {
          duration += finalResultHoldDuration;
        }
        if (_phaseElapsed >= duration) _advancePitch();
      case TenPitchSluggerPhase.countdown || TenPitchSluggerPhase.finished:
        break;
    }
    _publishHud();
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    tapSwing();
  }

  @visibleForTesting
  void tapSwing() {
    final previousSwingTime = _lastSwingPlayingElapsed;
    final acceptsSwing =
        _phase == TenPitchSluggerPhase.windup ||
        _phase == TenPitchSluggerPhase.pitchFlight;
    if (_hasFinished ||
        !_assetsReady ||
        !acceptsSwing ||
        (previousSwingTime != null &&
            _playingElapsed - previousSwingTime <
                TenPitchSluggerRules.swingCooldownSeconds)) {
      return;
    }
    _lastSwingPlayingElapsed = _playingElapsed;
    _swingCount++;
    if (_phase == TenPitchSluggerPhase.pitchFlight) {
      _hasTappedThisPitch = true;
      _tapTime = _phaseElapsed;
      _pendingTapTime = _phaseElapsed;
    }
    unawaited(HapticFeedback.selectionClick());
  }

  void _startSafeOpening() {
    _phase = TenPitchSluggerPhase.safeOpening;
    _phaseElapsed = 0;
  }

  void _startWindup() {
    _phase = TenPitchSluggerPhase.windup;
    _phaseElapsed = 0;
    _hasTappedThisPitch = false;
    _tapTime = null;
    _pendingTapTime = null;
    _lastSwingPlayingElapsed = null;
    _swingCount = 0;
    _lastDistanceCm = 0;
    _resolvedFlightElapsed = 0;
    _lastJudgement = TenPitchJudgement.watched;
    _lastHitType = null;
  }

  void _releasePitch() {
    _phase = TenPitchSluggerPhase.pitchFlight;
    _phaseElapsed = 0;
  }

  void _resolvePitch(double? tapTime) {
    if (_phase != TenPitchSluggerPhase.pitchFlight) return;
    _resolvedFlightElapsed = _phaseElapsed.clamp(
      0.0,
      currentPitch.flightSeconds,
    );
    final timingError = tapTime == null
        ? null
        : tapTime - currentPitch.idealTapSeconds;
    final distance = tapTime == null
        ? 0
        : TenPitchSluggerRules.distanceForTiming(
            pitch: currentPitch,
            timingErrorSeconds: timingError!,
          );
    _lastJudgement = TenPitchSluggerRules.judgementForTiming(
      pitch: currentPitch,
      timingErrorSeconds: timingError,
    );
    _lastDistanceCm = distance;
    _lastHitType = TenPitchSluggerRules.hitTypeForDistance(distance);
    if (_lastHitType != null) {
      _lastLaunchDirection = TenPitchSluggerRules.launchDirectionForTiming(
        pitch: currentPitch,
        timingErrorSeconds: timingError!,
      );
    }
    _bestDistanceCm = max(_bestDistanceCm, distance);
    if (distance == 0) {
      _misses++;
    } else {
      _hits++;
      unawaited(switch (_lastHitType!) {
        TenPitchHitType.groundBall => HapticFeedback.selectionClick(),
        TenPitchHitType.single => HapticFeedback.lightImpact(),
        TenPitchHitType.double => HapticFeedback.mediumImpact(),
        TenPitchHitType.longHit => HapticFeedback.heavyImpact(),
        TenPitchHitType.homeRun => HapticFeedback.vibrate(),
      });
    }
    _phase = TenPitchSluggerPhase.feedback;
    _phaseElapsed = 0;
  }

  void _advancePitch() {
    if (_pitchIndex >= TenPitchSluggerRules.pitchCount - 1) {
      _finishGame();
      return;
    }
    _pitchIndex++;
    if (usesSluggerBatter) {
      _phase = TenPitchSluggerPhase.sluggerEntrance;
      _phaseElapsed = 0;
      unawaited(HapticFeedback.heavyImpact());
    } else {
      _startWindup();
    }
  }

  void _finishGame() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = TenPitchSluggerPhase.finished;
    _publishHud();
    pauseEngine();
    if (_resultReported) return;
    _resultReported = true;
    onFinished(
      GameResult(
        score: _bestDistanceCm,
        starsCollected: _hits,
        collisions: _misses,
        duration: Duration(milliseconds: (_playingElapsed * 1000).round()),
        endType: GameEndType.clear,
      ),
    );
  }

  void _publishHud() {
    final countdown = max(
      0,
      (_seconds(countdownDuration) - _countdownElapsed).ceil(),
    );
    hud.value = MiniGameHudState(
      phase: switch (_phase) {
        TenPitchSluggerPhase.countdown => MiniGamePhase.countdown,
        TenPitchSluggerPhase.finished => MiniGamePhase.finished,
        _ => MiniGamePhase.playing,
      },
      score: _bestDistanceCm,
      elapsedSeconds: _playingElapsed.floor(),
      remainingSeconds: null,
      countdownNumber: countdown,
      distance: pitchNumber,
      message: switch (_phase) {
        TenPitchSluggerPhase.safeOpening => '준비! 첫 공은 연습 직구',
        TenPitchSluggerPhase.sluggerEntrance => '강타자 등장!',
        TenPitchSluggerPhase.windup || TenPitchSluggerPhase.pitchFlight =>
          usesSluggerBatter
              ? '7번 타자는 강타자 등장!'
              : '${currentPitch.number}구 · ${currentPitch.name}',
        TenPitchSluggerPhase.feedback =>
          _lastDistanceCm == 0
              ? '${TenPitchSluggerRules.judgementLabel(_lastJudgement)}  0m'
              : '${TenPitchSluggerRules.hitTypeLabel(_lastHitType!)} · '
                    '${TenPitchSluggerRules.judgementLabel(_lastJudgement)}  '
                    '+${TenPitchSluggerRules.formatScore(_lastDistanceCm)}',
        TenPitchSluggerPhase.finished => '10구 완료!',
        TenPitchSluggerPhase.countdown => null,
      },
    );
  }

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = TenPitchSluggerPhase.finished;
    _publishHud();
    pauseEngine();
  }

  @override
  void disposeController() => hud.dispose();

  double _seconds(Duration value) =>
      value.inMicroseconds / Duration.microsecondsPerSecond;
}

class _TenPitchBallpark extends PositionComponent {
  _TenPitchBallpark({
    required this.game,
    required this.background,
    required this.batterIdle,
    required this.batterSwing,
    required this.batterWhiff,
    required this.batterResult,
    required this.sluggerBatterIdle,
    required this.sluggerBatterSwing,
    required this.sluggerBatterWhiff,
    required this.sluggerBatterResult,
    required this.pitcherIdle,
    required this.pitcherPitch,
    required this.pitcherMagic,
    required this.ball,
    required this.hitFx,
    required this.trailFx,
  }) : super(size: TenPitchSluggerGame.logicalSize, priority: -10);

  final TenPitchSluggerGame game;
  final ui.Image background;
  final ui.Image batterIdle;
  final ui.Image batterSwing;
  final ui.Image batterWhiff;
  final ui.Image batterResult;
  final ui.Image sluggerBatterIdle;
  final ui.Image sluggerBatterSwing;
  final ui.Image sluggerBatterWhiff;
  final ui.Image sluggerBatterResult;
  final ui.Image pitcherIdle;
  final ui.Image pitcherPitch;
  final ui.Image pitcherMagic;
  final ui.Image ball;
  final ui.Image hitFx;
  final ui.Image trailFx;
  final Paint _paint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  static final _sceneSize = Size(
    TenPitchSluggerGame.logicalSize.x,
    TenPitchSluggerGame.logicalSize.y,
  );
  static final _release = TenPitchSluggerScene.releaseFor(_sceneSize);
  static final _contact = TenPitchSluggerScene.contactFor(_sceneSize);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.drawImageRect(
      background,
      // The final 80 source pixels are authored bottom overscan. Keeping the
      // 360x640 safe core pixel-perfect prevents the stadium from stretching.
      const Rect.fromLTWH(0, 0, 360, 640),
      Offset.zero & _sceneSize,
      _paint,
    );
    final shake = _hitShakeOffset();
    canvas.save();
    canvas.translate(shake.dx, shake.dy);
    TenPitchSluggerScene.drawFieldGuides(
      canvas,
      _sceneSize,
      magic: game.currentPitch.movement == TenPitchMovement.magic,
    );
    _drawPitcher(canvas);
    _drawSluggerAura(canvas);
    _drawBatter(canvas);
    _drawBallAndEffects(canvas);
    canvas.restore();
    _drawImpactFlash(canvas);
    _drawHomeRunCelebration(canvas);
    _drawSluggerEntrance(canvas);
  }

  void _drawSluggerAura(Canvas canvas) {
    if (game.gamePhase != TenPitchSluggerPhase.sluggerEntrance) return;
    final progress =
        (game.phaseElapsed / TenPitchSluggerGame.sluggerEntranceDuration).clamp(
          0.0,
          1.0,
        );
    const center = Offset(76, 466);
    final glow = Paint()
      ..color = const Color(
        0xFFFF3038,
      ).withValues(alpha: 0.52 * (1 - progress * 0.4))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    for (var ring = 0; ring < 3; ring++) {
      final radius = 45 + ring * 27 + progress * 48;
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: radius * 1.4,
          height: radius * 2,
        ),
        glow,
      );
    }
  }

  void _drawSluggerEntrance(Canvas canvas) {
    if (game.gamePhase != TenPitchSluggerPhase.sluggerEntrance) return;
    final elapsed = game.phaseElapsed;
    final progress = (elapsed / TenPitchSluggerGame.sluggerEntranceDuration)
        .clamp(0.0, 1.0);
    final reveal = (elapsed / 0.22).clamp(0.0, 1.0);
    final fade = ((1.6 - elapsed) / 0.30).clamp(0.0, 1.0);
    final opacity = reveal * fade;
    canvas.drawRect(
      Offset.zero & _sceneSize,
      Paint()
        ..color = const Color(0xFF090B1B).withValues(alpha: 0.58 * opacity),
    );
    final rayPaint = Paint()
      ..color = const Color(0xFFFF3848).withValues(alpha: 0.30 * opacity);
    const center = Offset(180, 227);
    for (var index = 0; index < 18; index++) {
      final angle = index * 2 * pi / 18 + progress * 0.12;
      final inner = 90 + 12 * sin(elapsed * 12 + index);
      final path = Path()
        ..moveTo(center.dx + cos(angle) * inner, center.dy + sin(angle) * inner)
        ..lineTo(
          center.dx + cos(angle - 0.035) * 470,
          center.dy + sin(angle - 0.035) * 470,
        )
        ..lineTo(
          center.dx + cos(angle + 0.035) * 470,
          center.dy + sin(angle + 0.035) * 470,
        )
        ..close();
      canvas.drawPath(path, rayPaint);
    }
    final impact = (elapsed / 0.45).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      45 + impact * 195,
      Paint()
        ..color = const Color(0xFFFFD7A0).withValues(alpha: (1 - impact) * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7 * (1 - impact) + 1,
    );
    final scale = 1.22 - 0.22 * (elapsed / 0.28).clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(
      center.dx + (elapsed < 0.35 ? sin(elapsed * 90) * 3 : 0),
      center.dy,
    );
    canvas.scale(scale);
    final style = TextStyle(
      fontFamily: 'Galmuri',
      fontWeight: FontWeight.w900,
      fontSize: 42,
      height: 1,
      color: const Color(0xFFFF3242).withValues(alpha: opacity),
      shadows: [
        Shadow(
          color: const Color(0xFFFF2020).withValues(alpha: opacity),
          blurRadius: 17,
        ),
        Shadow(
          color: const Color(0xFF5A0717).withValues(alpha: opacity),
          offset: const Offset(3, 5),
        ),
      ],
    );
    final title = TextPainter(
      text: TextSpan(text: '강타자 등장!', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final titleOffset = Offset(-title.width / 2, -title.height / 2);
    final outline = TextPainter(
      text: TextSpan(
        text: '강타자 등장!',
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF350812).withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    outline.paint(canvas, titleOffset);
    title.paint(canvas, titleOffset);
    canvas.restore();
  }

  Offset _hitShakeOffset() {
    if (game.gamePhase != TenPitchSluggerPhase.feedback ||
        game.lastDistanceCm == 0 ||
        game.lastHitType == null) {
      return Offset.zero;
    }
    final hitType = game.lastHitType!;
    return TenPitchSluggerMotion.hitShakeOffset(
      elapsedSeconds: game.phaseElapsed,
      strength: TenPitchSluggerMotion.hitShakeStrengthFor(hitType),
      duration: TenPitchSluggerMotion.hitShakeDurationFor(hitType),
      seed: game.pitchNumber,
    );
  }

  void _drawImpactFlash(Canvas canvas) {
    if (game.gamePhase != TenPitchSluggerPhase.feedback) {
      return;
    }
    if (game.lastDistanceCm == 0 || game.lastHitType == null) {
      _drawMissedPitchBall(canvas);
      return;
    }
    final opacity = TenPitchSluggerMotion.hitFlashOpacity(
      game.phaseElapsed,
      hitType: game.lastHitType!,
    );
    if (opacity <= 0) return;
    canvas.drawRect(
      Offset.zero & _sceneSize,
      Paint()
        ..isAntiAlias = false
        ..color = const Color(0xFFFFE9A8).withValues(alpha: opacity),
    );
  }

  void _drawHomeRunCelebration(Canvas canvas) {
    if (game.gamePhase != TenPitchSluggerPhase.feedback ||
        game.lastHitType != TenPitchHitType.homeRun) {
      return;
    }
    final elapsed = game.phaseElapsed;
    final opacity = TenPitchSluggerMotion.homeRunCelebrationOpacity(elapsed);
    if (opacity <= 0) return;
    final scale = TenPitchSluggerMotion.homeRunCelebrationScale(elapsed);
    const center = Offset(180, 164);
    final panel = Rect.fromCenter(
      center: center,
      width: 310 * scale,
      height: 62 * scale,
    );
    final panelPaint = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xFF10162B).withValues(alpha: 0.82 * opacity);
    final goldPaint = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xFFFFD447).withValues(alpha: opacity);
    canvas.drawRect(panel, panelPaint);
    canvas.drawRect(
      Rect.fromLTWH(panel.left, panel.top, panel.width, 4 * scale),
      goldPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        panel.left,
        panel.bottom - 4 * scale,
        panel.width,
        4 * scale,
      ),
      goldPaint,
    );

    final burstProgress = (elapsed / 0.85).clamp(0.0, 1.0);
    for (var index = 0; index < 12; index++) {
      final angle = index * pi / 6 + game.pitchNumber * 0.17;
      final radius = 42 + 72 * burstProgress;
      final sparkCenter = center.translate(
        cos(angle) * radius,
        sin(angle) * radius * 0.48,
      );
      final sparkSize = max(2.0, 6.0 * (1 - burstProgress)) * scale;
      canvas.drawRect(
        Rect.fromCenter(
          center: sparkCenter,
          width: sparkSize,
          height: sparkSize,
        ),
        goldPaint,
      );
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    final outline = TextPainter(
      text: TextSpan(
        text: 'HOME RUN!',
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontWeight: FontWeight.w700,
          fontSize: 34,
          height: 1,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF521A24).withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final fill = TextPainter(
      text: TextSpan(
        text: 'HOME RUN!',
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontWeight: FontWeight.w700,
          fontSize: 34,
          height: 1,
          color: const Color(0xFFFFE36E).withValues(alpha: opacity),
          shadows: [
            Shadow(
              color: const Color(0xFFFF6B35).withValues(alpha: opacity),
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final textOffset = Offset(-fill.width / 2, -fill.height / 2);
    outline.paint(canvas, textOffset);
    fill.paint(canvas, textOffset);
    canvas.restore();
  }

  void _drawPitcher(Canvas canvas) {
    ui.Image sheet = pitcherIdle;
    var columns = 2;
    var frameCount = 6;
    var frameIndex = TenPitchSluggerMotion.loopingFrame(
      game.phaseElapsed,
      frameCount,
      6,
    );
    if (game.gamePhase == TenPitchSluggerPhase.windup) {
      final magic = game.currentPitch.movement == TenPitchMovement.magic;
      final duration = magic
          ? TenPitchSluggerGame.magicWindupDuration
          : TenPitchSluggerGame.regularWindupDuration;
      sheet = magic ? pitcherMagic : pitcherPitch;
      columns = 4;
      frameCount = magic ? 16 : 12;
      final progress = game.phaseElapsed / duration;
      frameIndex = magic
          ? TenPitchSluggerMotion.magicWindupFrame(progress)
          : TenPitchSluggerMotion.regularWindupFrame(progress);
    } else if (game.gamePhase == TenPitchSluggerPhase.pitchFlight) {
      final magic = game.currentPitch.movement == TenPitchMovement.magic;
      final followFrame = magic
          ? TenPitchSluggerMotion.magicFollowThroughFrame(game.phaseElapsed)
          : TenPitchSluggerMotion.regularFollowThroughFrame(game.phaseElapsed);
      if (followFrame >= 0) {
        sheet = magic ? pitcherMagic : pitcherPitch;
        columns = 4;
        frameCount = magic ? 16 : 12;
        frameIndex = followFrame;
      }
    }
    _drawGridFrame(
      canvas,
      sheet,
      columns: columns,
      frameCount: frameCount,
      frameIndex: frameIndex,
      destination: TenPitchSluggerScene.pitcherSpriteBoundsFor(_sceneSize),
    );
  }

  void _drawBatter(Canvas canvas) {
    final slugger = game.usesSluggerBatter;
    ui.Image sheet = slugger ? sluggerBatterIdle : batterIdle;
    var columns = 2;
    var frameCount = 6;
    var frameIndex = TenPitchSluggerMotion.loopingFrame(
      game.phaseElapsed,
      frameCount,
      6,
    );
    final lastSwingTime = game._lastSwingPlayingElapsed;
    if ((game.gamePhase == TenPitchSluggerPhase.windup ||
            game.gamePhase == TenPitchSluggerPhase.pitchFlight) &&
        lastSwingTime != null) {
      final elapsed = game._playingElapsed - lastSwingTime;
      if (elapsed < TenPitchSluggerMotion.swingDurationSeconds) {
        sheet = slugger ? sluggerBatterSwing : batterSwing;
        columns = 4;
        frameCount = 16;
        frameIndex = TenPitchSluggerMotion.batterSwingFrame(elapsed);
      }
    } else if (game.gamePhase == TenPitchSluggerPhase.feedback) {
      final whiff = game.lastDistanceCm == 0;
      final hitType = game.lastHitType;
      if (whiff) {
        final lastTapTime = game._tapTime;
        if (lastTapTime != null) {
          final swingElapsed =
              game.resolvedFlightElapsed - lastTapTime + game.phaseElapsed;
          if (swingElapsed < TenPitchSluggerMotion.swingDurationSeconds) {
            sheet = slugger ? sluggerBatterSwing : batterSwing;
            columns = 4;
            frameCount = 16;
            frameIndex = TenPitchSluggerMotion.batterSwingFrame(swingElapsed);
          } else if (swingElapsed <
              TenPitchSluggerMotion.swingDurationSeconds + 0.55) {
            sheet = slugger ? sluggerBatterWhiff : batterWhiff;
            columns = 4;
            frameCount = 12;
            final recoveryProgress =
                (swingElapsed - TenPitchSluggerMotion.swingDurationSeconds) /
                0.55;
            frameIndex = 6 + (recoveryProgress.clamp(0.0, 0.999) * 6).floor();
          }
        }
      } else {
        columns = 4;
        final swingFeedbackDuration =
            TenPitchSluggerMotion.feedbackSwingDuration(
              hit: true,
              hitType: hitType,
            );
        if (game.phaseElapsed < swingFeedbackDuration) {
          sheet = slugger ? sluggerBatterSwing : batterSwing;
          frameCount = 16;
          frameIndex = TenPitchSluggerMotion.batterFeedbackSwingFrame(
            elapsedSeconds: game.phaseElapsed,
            hit: true,
            hitType: hitType,
          );
        } else {
          sheet = slugger ? sluggerBatterResult : batterResult;
          frameCount = 8;
          const firstRecoveryFrame = 4;
          final recoveryFrameCount = frameCount - firstRecoveryFrame;
          final elapsed = game.phaseElapsed - swingFeedbackDuration;
          frameIndex =
              firstRecoveryFrame +
              ((elapsed / 0.55).clamp(0.0, 0.999) * recoveryFrameCount).floor();
        }
      }
    }
    _drawGridFrame(
      canvas,
      sheet,
      columns: columns,
      frameCount: frameCount,
      frameIndex: frameIndex,
      destination: TenPitchSluggerScene.batterSpriteBoundsFor(_sceneSize),
    );
  }

  void _drawBallAndEffects(Canvas canvas) {
    if (game.gamePhase == TenPitchSluggerPhase.pitchFlight) {
      final point = _pitchPoint(game.currentPitch, game.phaseElapsed);
      final rawProgress = (game.phaseElapsed / game.currentPitch.flightSeconds)
          .clamp(0.0, 1.0);
      final progress = TenPitchSluggerMotion.perspectiveProgress(rawProgress);
      if (game.currentPitch.movement == TenPitchMovement.magic) {
        final trailSize = 26 + 46 * progress;
        _drawGridFrame(
          canvas,
          trailFx,
          columns: 4,
          frameCount: 8,
          // Keep the four strongest crescent frames in flight; the sparse
          // build/fade cells disappear behind the fast-moving ball.
          frameIndex:
              2 + TenPitchSluggerMotion.loopingFrame(game.phaseElapsed, 4, 10),
          destination: Rect.fromCenter(
            center: point,
            width: trailSize,
            height: trailSize,
          ),
        );
      }
      final size = 7 + 23 * progress;
      _drawGridFrame(
        canvas,
        ball,
        columns: 3,
        frameCount: 6,
        frameIndex: TenPitchSluggerMotion.loopingFrame(
          game.phaseElapsed,
          6,
          18 + 10 * progress,
        ),
        destination: Rect.fromCenter(center: point, width: size, height: size),
      );
      return;
    }

    if (game.gamePhase != TenPitchSluggerPhase.feedback ||
        game.lastDistanceCm == 0 ||
        game.lastHitType == null) {
      return;
    }
    final hitType = game.lastHitType!;
    final hitFxDuration = TenPitchSluggerMotion.hitFxDurationFor(hitType);
    if (game.phaseElapsed <= hitFxDuration) {
      final effectSize = 96 * TenPitchSluggerMotion.hitFxScaleFor(hitType);
      _drawGridFrame(
        canvas,
        hitFx,
        columns: 4,
        frameCount: 8,
        frameIndex: TenPitchSluggerMotion.hitFxFrame(
          game.phaseElapsed,
          hitType: hitType,
        ),
        destination: Rect.fromCenter(
          center: _contact,
          width: effectSize,
          height: effectSize,
        ),
      );
    }
    final launchProgress = TenPitchSluggerMotion.launchProgress(
      game.phaseElapsed,
      hitType: hitType,
      coastSeconds: TenPitchSluggerGame.farFlightCoastDuration,
    );
    final direction = game.lastLaunchDirection;
    final quality = hitType == TenPitchHitType.homeRun
        ? TenPitchSluggerRules.wallHeightProgress(game.lastDistanceCm)
        : TenPitchSluggerRules.hitTypeProgress(
            pitch: game.currentPitch,
            distanceCm: game.lastDistanceCm,
          );
    final ballFrame = TenPitchSluggerMotion.loopingFrame(
      game.phaseElapsed,
      6,
      22,
    );
    final ghostCount = TenPitchSluggerMotion.afterimageCountFor(hitType);
    for (var ghost = ghostCount; ghost >= 1; ghost--) {
      final ghostProgress = max(0.0, launchProgress - ghost * 0.055);
      if (launchProgress <= ghostProgress) continue;
      final ghostPoint = TenPitchSluggerMotion.launchedBallPoint(
        contact: _contact,
        progress: ghostProgress,
        quality: quality,
        direction: direction,
        hitType: hitType,
      );
      final ghostSize = TenPitchSluggerMotion.launchedBallSize(
        ghostProgress,
        hitType: hitType,
      );
      _drawGridFrame(
        canvas,
        ball,
        columns: 3,
        frameCount: 6,
        frameIndex: ballFrame,
        destination: Rect.fromCenter(
          center: ghostPoint,
          width: ghostSize,
          height: ghostSize,
        ),
        paint: Paint()
          ..isAntiAlias = false
          ..filterQuality = FilterQuality.none
          ..color = Color.fromARGB(
            26 + (ghostCount - ghost) * 18,
            255,
            244,
            208,
          ),
      );
    }
    final launched = TenPitchSluggerMotion.launchedBallPoint(
      contact: _contact,
      progress: launchProgress,
      quality: quality,
      direction: direction,
      hitType: hitType,
    );
    final size = TenPitchSluggerMotion.launchedBallSize(
      launchProgress,
      hitType: hitType,
    );
    _drawGridFrame(
      canvas,
      ball,
      columns: 3,
      frameCount: 6,
      frameIndex: ballFrame,
      destination: Rect.fromCenter(center: launched, width: size, height: size),
    );
  }

  void _drawMissedPitchBall(Canvas canvas) {
    final pitch = game.currentPitch;
    final continuedFlightElapsed =
        game.resolvedFlightElapsed + game.phaseElapsed;
    final ballFrame = TenPitchSluggerMotion.loopingFrame(
      continuedFlightElapsed,
      6,
      22,
    );

    if (continuedFlightElapsed < pitch.flightSeconds) {
      final point = _pitchPoint(pitch, continuedFlightElapsed);
      final rawProgress = (continuedFlightElapsed / pitch.flightSeconds).clamp(
        0.0,
        1.0,
      );
      final progress = TenPitchSluggerMotion.perspectiveProgress(rawProgress);
      final size = 7 + 23 * progress;
      _drawGridFrame(
        canvas,
        ball,
        columns: 3,
        frameCount: 6,
        frameIndex: ballFrame,
        destination: Rect.fromCenter(center: point, width: size, height: size),
      );
      return;
    }

    final exitProgress =
        ((continuedFlightElapsed - pitch.flightSeconds) /
                TenPitchSluggerGame.missedBallExitDuration)
            .clamp(0.0, 1.0);
    final opacity = TenPitchSluggerMotion.missedBallOpacity(exitProgress);
    if (opacity <= 0) return;
    final point = TenPitchSluggerMotion.missedBallPoint(
      release: _release,
      contact: _contact,
      progress: exitProgress,
    );
    final size = TenPitchSluggerMotion.missedBallSize(exitProgress);
    _drawGridFrame(
      canvas,
      ball,
      columns: 3,
      frameCount: 6,
      frameIndex: ballFrame,
      destination: Rect.fromCenter(center: point, width: size, height: size),
      paint: Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none
        ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity),
    );
  }

  Offset _pitchPoint(TenPitchSpec pitch, double elapsed) {
    var rawProgress = (elapsed / pitch.flightSeconds).clamp(0.0, 1.0);
    if (pitch.movement == TenPitchMovement.changeup) {
      rawProgress = rawProgress < 0.48
          ? rawProgress * 1.08
          : 0.5184 + (rawProgress - 0.48) * 0.9262;
    }
    final progress = TenPitchSluggerMotion.perspectiveProgress(rawProgress);
    final base = Offset.lerp(_release, _contact, progress)!;
    final late = ((progress - 0.42) / 0.58).clamp(0.0, 1.0);
    final returnToContact = 4 * progress * (1 - progress);
    final horizontal = switch (pitch.movement) {
      TenPitchMovement.magic =>
        sin(rawProgress * pi * 2.25) *
            pitch.horizontalBreak *
            late *
            returnToContact,
      TenPitchMovement.inside ||
      TenPitchMovement.outside ||
      TenPitchMovement.slider =>
        pitch.horizontalBreak *
            pitch.breakDirection *
            late *
            late *
            returnToContact,
      _ => 0.0,
    };
    final vertical = pitch.verticalBreak * late * late * returnToContact * 0.72;
    var point = base.translate(horizontal, vertical);

    final tapTime = game._tapTime;
    if (tapTime != null && _willHit(pitch, tapTime)) {
      final correction = TenPitchSluggerMotion.contactCorrection(
        elapsedSeconds: elapsed,
        resolutionSeconds: tapTime + TenPitchSluggerRules.swingLeadSeconds,
      );
      point = Offset.lerp(point, _contact, correction)!;
    }
    return point;
  }

  bool _willHit(TenPitchSpec pitch, double tapTime) =>
      (tapTime - pitch.idealTapSeconds).abs() <= pitch.hitWindowSeconds;

  void _drawGridFrame(
    Canvas canvas,
    ui.Image image, {
    required int columns,
    required int frameCount,
    required int frameIndex,
    required Rect destination,
    Paint? paint,
  }) {
    final rows = (frameCount / columns).ceil();
    final cellWidth = image.width / columns;
    final cellHeight = image.height / rows;
    final safeIndex = frameIndex.clamp(0, frameCount - 1);
    final column = safeIndex % columns;
    final row = safeIndex ~/ columns;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        column * cellWidth,
        row * cellHeight,
        cellWidth,
        cellHeight,
      ),
      destination,
      paint ?? _paint,
    );
  }
}
