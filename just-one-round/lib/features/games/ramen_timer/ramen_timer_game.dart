import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/ramen_timer/domain/ramen_timer_rules.dart';

enum RamenTimerPhase {
  loading,
  countdown,
  calibrationVisible,
  clockCovering,
  waitingFor10,
  waitingFor20,
  waitingFor30,
  resultReveal,
  finishedClear,
  finishedTimeout,
  interrupted,
}

abstract interface class RamenTimerClock {
  Duration get elapsed;
  bool get isRunning;

  void start();
  void stop();
}

final class StopwatchRamenTimerClock implements RamenTimerClock {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  bool get isRunning => _stopwatch.isRunning;

  @override
  void start() => _stopwatch.start();

  @override
  void stop() => _stopwatch.stop();
}

class RamenTimerGame extends FlameGame
    implements MiniGameController, PrimaryActionMiniGameController {
  RamenTimerGame({
    required this.onFinished,
    this.countdownDuration = const Duration(seconds: 3),
    this.challengeSeed = 0,
    RamenTimerClock? clock,
  }) : clock = clock ?? StopwatchRamenTimerClock();

  static final logicalSize = Vector2(360, 640);
  static const maxVisibleHeight = 800.0;
  static const resultTimelineRevealDuration = 1.5;
  static const resultRevealDuration = 2.8;

  final ValueChanged<GameResult> onFinished;
  final Duration countdownDuration;
  final int challengeSeed;
  final RamenTimerClock clock;

  @override
  final ValueNotifier<MiniGameHudState> hud = ValueNotifier(
    const MiniGameHudState(
      phase: MiniGamePhase.countdown,
      score: 0,
      elapsedSeconds: 0,
      remainingSeconds: null,
      countdownNumber: 3,
      primaryActionLabel: '준비 중...',
    ),
  );

  RamenTimerPhase _phase = RamenTimerPhase.loading;
  final List<int> _tapMilliseconds = [];
  final List<int> _rawTapMicroseconds = [];
  late _RamenTimerScene _scene;
  var _countdownElapsed = 0.0;
  var _visualElapsed = 0.0;
  var _resultRevealElapsed = 0.0;
  var _eventStartedAt = double.negativeInfinity;
  var _eventTapIndex = -1;
  var _lastCalibrationBeat = 0;
  var _hasFinished = false;
  var _resultReported = false;
  var _assetsReady = false;
  var _controllerDisposed = false;
  int? _lockedScore;
  RamenTimerVerdict? _verdict;

  @override
  FlameGame get flameGame => this;

  RamenTimerPhase get gamePhase => _phase;

  @visibleForTesting
  bool get assetsReady => _assetsReady;

  List<int> get tapMilliseconds => List<int>.unmodifiable(_tapMilliseconds);

  @visibleForTesting
  int? get lockedScore => _lockedScore;

  @visibleForTesting
  RamenTimerVerdict? get resultVerdict => _verdict;

  @visibleForTesting
  int get cupFrame {
    if (_phase == RamenTimerPhase.resultReveal ||
        _tapMilliseconds.length >= 3) {
      return 3;
    }
    final eventIndex = _eventTapIndex;
    final eventActive =
        eventIndex >= 0 &&
        eventIndex < 2 &&
        eventAge >= 0 &&
        eventAge <= RamenTimerRules.ingredientEventMilliseconds / 1000;
    return eventActive ? eventIndex + 1 : 0;
  }

  @visibleForTesting
  bool get canTap => _isWaitingPhase && _inputLockExpired;

  double get visualElapsed => _visualElapsed;
  double get eventAge => _visualElapsed - _eventStartedAt;
  int get eventTapIndex => _eventTapIndex;

  double get resultRevealProgress =>
      (_resultRevealElapsed / resultTimelineRevealDuration).clamp(0.0, 1.0);

  String? get checkpointFeedbackText {
    final index = _eventTapIndex;
    if (index < 0 || index > 1 || index >= _tapMilliseconds.length) return null;
    if (eventAge < 0 ||
        eventAge >= RamenTimerRules.checkpointFeedbackMilliseconds / 1000) {
      return null;
    }
    return RamenTimerRules.formatSignedDelta(
      RamenTimerRules.signedErrorForTap(index, _tapMilliseconds[index]),
    );
  }

  bool get _isWaitingPhase => switch (_phase) {
    RamenTimerPhase.waitingFor10 ||
    RamenTimerPhase.waitingFor20 ||
    RamenTimerPhase.waitingFor30 => true,
    _ => false,
  };

  bool get _inputLockExpired {
    if (_rawTapMicroseconds.isEmpty) return true;
    return clock.elapsed.inMicroseconds - _rawTapMicroseconds.last >=
        RamenTimerRules.inputLockMilliseconds * 1000;
  }

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
  Color backgroundColor() => const Color(0xFF071224);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);

    final loaded = await images.loadAll(const [
      'ramen_timer/office_background.png',
      'ramen_timer/counter_front.png',
      'ramen_timer/raccoon_idle_sheet.png',
      'ramen_timer/raccoon_pose_atlas.png',
      'ramen_timer/ramen_cup_atlas.png',
      'ramen_timer/ramen_fx_atlas.png',
      'ramen_timer/ramen_result_atlas.png',
    ]);
    _scene = _RamenTimerScene(
      game: this,
      background: loaded[0],
      counter: loaded[1],
      raccoonIdle: loaded[2],
      raccoonPoses: loaded[3],
      ramenCup: loaded[4],
      ramenFx: loaded[5],
      ramenResult: loaded[6],
    );
    await world.add(_scene);
    _assetsReady = true;
    if (countdownDuration == Duration.zero) {
      _startActivePlay();
    } else {
      _phase = RamenTimerPhase.countdown;
    }
    _publishHud();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _configureViewport(size);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_assetsReady || _hasFinished || _controllerDisposed) return;
    _visualElapsed += dt;

    if (_phase == RamenTimerPhase.countdown) {
      _countdownElapsed += dt;
      if (_countdownElapsed >= _seconds(countdownDuration)) {
        _startActivePlay();
      }
      _publishHud();
      return;
    }

    if (_phase == RamenTimerPhase.resultReveal) {
      _resultRevealElapsed += dt;
      if (_resultRevealElapsed >= resultRevealDuration) _finishClear();
      _publishHud();
      return;
    }

    final elapsedMilliseconds = clock.elapsed.inMilliseconds;
    if (elapsedMilliseconds >= RamenTimerRules.timeoutMilliseconds) {
      _finishTimeout();
      return;
    }
    _updateCalibrationBeat(elapsedMilliseconds);
    _updateTimedPhase(elapsedMilliseconds);
    _publishHud();
  }

  void _startActivePlay() {
    if (_hasFinished || clock.isRunning) return;
    clock.start();
    _phase = RamenTimerPhase.calibrationVisible;
    _publishHud();
  }

  void _updateCalibrationBeat(int elapsedMilliseconds) {
    if (elapsedMilliseconds > RamenTimerRules.calibrationVisibleMilliseconds) {
      return;
    }
    final beat = elapsedMilliseconds ~/ 1000;
    if (beat <= _lastCalibrationBeat || beat > 3) return;
    _lastCalibrationBeat = beat;
    unawaited(SystemSound.play(SystemSoundType.click));
    unawaited(HapticFeedback.selectionClick());
  }

  void _updateTimedPhase(int elapsedMilliseconds) {
    if (elapsedMilliseconds < RamenTimerRules.calibrationVisibleMilliseconds) {
      _phase = RamenTimerPhase.calibrationVisible;
      return;
    }
    if (elapsedMilliseconds < RamenTimerRules.inputUnlockMilliseconds) {
      _phase = RamenTimerPhase.clockCovering;
      return;
    }
    _phase = switch (_tapMilliseconds.length) {
      0 => RamenTimerPhase.waitingFor10,
      1 => RamenTimerPhase.waitingFor20,
      _ => RamenTimerPhase.waitingFor30,
    };
  }

  @override
  void triggerPrimaryAction() {
    if (_hasFinished || !_assetsReady || _controllerDisposed) return;
    if (_phase == RamenTimerPhase.loading ||
        _phase == RamenTimerPhase.countdown ||
        _phase == RamenTimerPhase.resultReveal) {
      return;
    }
    final rawMicroseconds = clock.elapsed.inMicroseconds;
    if (rawMicroseconds < RamenTimerRules.inputUnlockMilliseconds * 1000) {
      return;
    }
    if (rawMicroseconds > RamenTimerRules.timeoutMilliseconds * 1000) {
      _finishTimeout();
      return;
    }
    _updateTimedPhase(rawMicroseconds ~/ 1000);
    if (!_isWaitingPhase) return;
    if (!_inputLockExpired) return;

    final quantized = RamenTimerRules.quantizeMicroseconds(rawMicroseconds);
    _rawTapMicroseconds.add(rawMicroseconds);
    _tapMilliseconds.add(quantized);
    _eventTapIndex = _tapMilliseconds.length - 1;
    _eventStartedAt = _visualElapsed;
    unawaited(SystemSound.play(SystemSoundType.click));

    if (_tapMilliseconds.length == RamenTimerRules.targetMilliseconds.length) {
      clock.stop();
      _lockedScore = RamenTimerRules.rankingScore(_tapMilliseconds);
      _verdict = RamenTimerRules.verdict(_tapMilliseconds);
      _phase = RamenTimerPhase.resultReveal;
      _resultRevealElapsed = 0;
      unawaited(HapticFeedback.heavyImpact());
    } else {
      _phase = _tapMilliseconds.length == 1
          ? RamenTimerPhase.waitingFor20
          : RamenTimerPhase.waitingFor30;
      unawaited(
        _tapMilliseconds.length == 1
            ? HapticFeedback.lightImpact()
            : HapticFeedback.mediumImpact(),
      );
    }
    _publishHud();
  }

  void _finishClear() {
    if (_hasFinished || _tapMilliseconds.length != 3) return;
    _hasFinished = true;
    _phase = RamenTimerPhase.finishedClear;
    _publishHud();
    pauseEngine();
    if (_resultReported) return;
    _resultReported = true;
    onFinished(
      GameResult(
        score: _lockedScore!,
        starsCollected: 0,
        collisions: 0,
        duration: Duration(milliseconds: _tapMilliseconds.last),
        endType: GameEndType.clear,
      ),
    );
  }

  void _finishTimeout() {
    if (_hasFinished) return;
    _hasFinished = true;
    clock.stop();
    _lockedScore = RamenTimerRules.timeoutRankingScore;
    _phase = RamenTimerPhase.finishedTimeout;
    _publishHud();
    pauseEngine();
    if (_resultReported) return;
    _resultReported = true;
    onFinished(
      const GameResult(
        score: RamenTimerRules.timeoutRankingScore,
        starsCollected: 0,
        collisions: 0,
        duration: Duration(milliseconds: RamenTimerRules.timeoutMilliseconds),
        endType: GameEndType.timeUp,
      ),
    );
  }

  void _publishHud() {
    if (_controllerDisposed) return;
    final countdownNumber = math.max(
      0,
      (_seconds(countdownDuration) - _countdownElapsed).ceil(),
    );
    final elapsedMilliseconds = clock.elapsed.inMilliseconds;
    hud.value = MiniGameHudState(
      phase: switch (_phase) {
        RamenTimerPhase.loading ||
        RamenTimerPhase.countdown => MiniGamePhase.countdown,
        RamenTimerPhase.finishedClear ||
        RamenTimerPhase.finishedTimeout ||
        RamenTimerPhase.interrupted => MiniGamePhase.finished,
        _ => MiniGamePhase.playing,
      },
      score: _lockedScore ?? 0,
      elapsedSeconds: elapsedMilliseconds ~/ 1000,
      remainingSeconds: null,
      countdownNumber: countdownNumber,
      distance: _tapMilliseconds.length,
      message: switch (_phase) {
        RamenTimerPhase.calibrationVisible => '1초 감각을 눈에 담으세요',
        RamenTimerPhase.clockCovering => '증기가 시계를 가렸어요',
        RamenTimerPhase.finishedTimeout => '시간 초과',
        RamenTimerPhase.finishedClear => '조리 완료!',
        _ => null,
      },
      primaryActionEnabled: canTap,
      primaryActionLabel: switch (_phase) {
        RamenTimerPhase.waitingFor10 =>
          RamenTimerRules.culinaryActionLabelForTapCount(0),
        RamenTimerPhase.waitingFor20 =>
          RamenTimerRules.culinaryActionLabelForTapCount(1),
        RamenTimerPhase.waitingFor30 =>
          RamenTimerRules.culinaryActionLabelForTapCount(2),
        RamenTimerPhase.resultReveal => '기록 확인 중',
        RamenTimerPhase.calibrationVisible ||
        RamenTimerPhase.clockCovering => '감각 익히는 중...',
        _ => '준비 중...',
      },
    );
  }

  @override
  void interrupt() {
    if (_hasFinished) return;
    if (_phase == RamenTimerPhase.resultReveal &&
        _tapMilliseconds.length == RamenTimerRules.targetMilliseconds.length) {
      _finishClear();
      return;
    }
    _hasFinished = true;
    clock.stop();
    _phase = RamenTimerPhase.interrupted;
    _publishHud();
    pauseEngine();
  }

  @override
  void disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    _hasFinished = true;
    clock.stop();
    pauseEngine();
    hud.dispose();
  }

  double _seconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;
}

class _RamenTimerScene extends PositionComponent {
  _RamenTimerScene({
    required this.game,
    required this.background,
    required this.counter,
    required this.raccoonIdle,
    required this.raccoonPoses,
    required this.ramenCup,
    required this.ramenFx,
    required this.ramenResult,
  }) : super(size: RamenTimerGame.logicalSize, priority: -10);

  final RamenTimerGame game;
  final ui.Image background;
  final ui.Image counter;
  final ui.Image raccoonIdle;
  final ui.Image raccoonPoses;
  final ui.Image ramenCup;
  final ui.Image ramenFx;
  final ui.Image ramenResult;

  final Paint _paint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.medium;

  static const _raccoonRect = Rect.fromLTWH(30, 230, 190, 214);
  static const _cupRect = Rect.fromLTWH(207, 340, 126, 126);
  static const _cupContactShadowRect = Rect.fromLTWH(228, 454, 98, 14);
  static const _timerDisplayRect = Rect.fromLTWH(94, 146, 172, 36);
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.drawImageRect(
      background,
      Rect.fromLTWH(
        0,
        0,
        background.width.toDouble(),
        background.height.toDouble(),
      ),
      const Rect.fromLTWH(0, -80, 360, 800),
      _paint,
    );

    _drawTimer(canvas);
    _drawSteam(canvas);
    _drawCheckpointFeedback(canvas);
    _drawRaccoon(canvas);
    canvas.drawImageRect(
      counter,
      Rect.fromLTWH(0, 0, counter.width.toDouble(), counter.height.toDouble()),
      const Rect.fromLTWH(0, 432, 360, 144),
      _paint,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 432, 360, 3),
      Paint()..color = const Color(0xFF9CA9A0),
    );
    _drawCupAndEffects(canvas);
    if (game.gamePhase == RamenTimerPhase.resultReveal) {
      _drawResultTimeline(canvas);
    }
  }

  void _drawTimer(Canvas canvas) {
    if (game.gamePhase == RamenTimerPhase.resultReveal) return;
    final panel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(80, 120, 200, 88),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      panel.shift(const Offset(4, 5)),
      Paint()..color = const Color(0xB3000710),
    );
    canvas.drawRRect(panel, Paint()..color = const Color(0xFFF0DEB2));
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF2C7473),
    );

    _text(
      canvas,
      '조리 타이머',
      const Offset(180, 127),
      color: const Color(0xFF286563),
      size: 11,
      anchor: Alignment.topCenter,
    );

    canvas.drawRect(
      _timerDisplayRect,
      Paint()..color = const Color(0xFF174B51),
    );
    canvas.drawRect(
      _timerDisplayRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF2C7473),
    );

    final elapsed = game.clock.elapsed.inMilliseconds;
    final visible = game.gamePhase == RamenTimerPhase.calibrationVisible;
    final coverProgress = ((elapsed - 3000) / 360).clamp(0.0, 1.0);
    final timer = visible || coverProgress < 1
        ? RamenTimerRules.formatMilliseconds(elapsed)
        : '??.??초';
    final timerColor = visible
        ? const Color(0xFFFFE18A)
        : coverProgress < 1
        ? const Color(0xFFFFE18A).withValues(alpha: 1 - coverProgress * 0.78)
        : const Color(0xFFCED7DB);
    _text(
      canvas,
      timer,
      const Offset(180, 149),
      color: timerColor,
      size: 27,
      anchor: Alignment.topCenter,
    );

    if (visible) {
      final beat = (elapsed ~/ 1000).clamp(0, 3);
      for (var index = 0; index < 3; index++) {
        final active = index < beat;
        final rect = Rect.fromLTWH(132 + index * 34, 195, 24, 8);
        canvas.drawRect(
          rect,
          Paint()
            ..color = active
                ? const Color(0xFFFFC85C)
                : const Color(0xFF29465A),
        );
      }
    }
  }

  void _drawSteam(Canvas canvas) {
    final phase = game.gamePhase;
    if (phase == RamenTimerPhase.resultReveal ||
        phase == RamenTimerPhase.finishedClear ||
        phase == RamenTimerPhase.interrupted) {
      return;
    }

    final elapsed = game.clock.elapsed.inMilliseconds;
    if (elapsed < RamenTimerRules.calibrationVisibleMilliseconds) return;

    final steamElapsed =
        (elapsed - RamenTimerRules.calibrationVisibleMilliseconds) / 1000;
    final coverProgress = (steamElapsed / 0.72).clamp(0.0, 1.0);
    final seedOffset = (game.challengeSeed.abs() % 97) / 97;

    const targetXs = <double>[148, 176, 204, 232, 218];
    for (var index = 0; index < targetXs.length; index++) {
      final lifetime = 1.28 + (index % 4) * 0.17;
      final rawProgress =
          (steamElapsed - index * 0.11 + seedOffset * 0.23) / lifetime;
      if (rawProgress < 0) continue;
      final progress = rawProgress - rawProgress.floorToDouble();
      final rise = Curves.easeOutCubic.transform(progress);
      final drift =
          math.sin((rawProgress + index * 0.41) * math.pi * 2) *
          (5 + index % 3 * 2);
      final x = ui.lerpDouble(270, targetXs[index], rise)! + drift;
      final y = ui.lerpDouble(416, 126 + (index % 3) * 10, rise)!;
      final size = ui.lerpDouble(22, 42 + (index % 2) * 6, rise)!;
      final fade = math.sin(progress * math.pi).clamp(0.0, 1.0);
      _drawFrame(
        canvas,
        ramenFx,
        columns: 3,
        rows: 2,
        frameIndex: (index + game.challengeSeed.abs()) % 2,
        destination: Rect.fromCenter(
          center: Offset(x, y),
          width: size,
          height: size,
        ),
        opacity: fade * 0.66,
      );
    }

    canvas.save();
    canvas.clipRect(_timerDisplayRect.inflate(-2));
    final veilAlpha = coverProgress * 0.38;
    canvas.drawRect(
      _timerDisplayRect,
      Paint()..color = const Color(0xFFD3DDD7).withValues(alpha: veilAlpha),
    );

    for (var index = 0; index < 9; index++) {
      final speed = 0.11 + index * 0.013;
      final cloudPhase = (steamElapsed * speed + seedOffset + index * 0.19) % 1;
      final radius = 10.0 + (index % 4) * 3.5;
      final x =
          _timerDisplayRect.left -
          radius +
          cloudPhase * (_timerDisplayRect.width + radius * 2);
      final y = _timerDisplayRect.top + 7 + (index % 3) * 12;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.medium
          ..color = const Color(
            0xFFE7ECE8,
          ).withValues(alpha: coverProgress * 0.28),
      );
    }

    for (var index = 0; index < 2; index++) {
      final drift =
          math.sin(
            (steamElapsed * (0.8 + index * 0.13) + index) * math.pi * 2,
          ) *
          12;
      _drawFrame(
        canvas,
        ramenFx,
        columns: 3,
        rows: 2,
        frameIndex: (index + game.challengeSeed.abs()) % 2,
        destination: Rect.fromLTWH(
          114 + index * 52 + drift,
          145 + (index % 2) * 9,
          40,
          40,
        ),
        opacity: coverProgress * 0.58,
      );
    }
    canvas.restore();
  }

  void _drawCheckpointFeedback(Canvas canvas) {
    final feedback = game.checkpointFeedbackText;
    if (feedback == null) return;
    _text(
      canvas,
      feedback,
      const Offset(181, 92),
      color: const Color(0xFF321418),
      size: 23,
      anchor: Alignment.topCenter,
    );
    _text(
      canvas,
      feedback,
      const Offset(180, 90),
      color: const Color(0xFFFF5B57),
      size: 23,
      anchor: Alignment.topCenter,
    );
  }

  void _drawRaccoon(Canvas canvas) {
    final poseIndex = switch (game.gamePhase) {
      RamenTimerPhase.calibrationVisible
          when game.clock.elapsed.inMilliseconds >= 2600 =>
        0,
      RamenTimerPhase.clockCovering => 1,
      RamenTimerPhase.resultReveal => switch (game.resultVerdict) {
        RamenTimerVerdict.perfect => 5,
        RamenTimerVerdict.tooEarly => 6,
        RamenTimerVerdict.tooLate => 7,
        null => 4,
      },
      _ when game.eventAge < 0.72 && game.eventTapIndex == 0 => 2,
      _ when game.eventAge < 0.72 && game.eventTapIndex == 1 => 3,
      _ when game.eventAge < 0.72 && game.eventTapIndex == 2 => 4,
      _ => -1,
    };
    if (poseIndex >= 0) {
      _drawFrame(
        canvas,
        raccoonPoses,
        columns: 4,
        rows: 2,
        frameIndex: poseIndex,
        destination: _raccoonRect,
      );
      return;
    }

    final calibration =
        game.gamePhase == RamenTimerPhase.countdown ||
        game.gamePhase == RamenTimerPhase.calibrationVisible;
    final idleFrame = calibration
        ? ((game.visualElapsed * 3.4).floor() % 4)
        : game.tapMilliseconds.length.clamp(0, 3);
    _drawFrame(
      canvas,
      raccoonIdle,
      columns: 4,
      rows: 1,
      frameIndex: idleFrame,
      destination: _raccoonRect,
    );
  }

  void _drawCupAndEffects(Canvas canvas) {
    canvas.drawOval(
      _cupContactShadowRect,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0x40000A0B),
    );

    if (game.gamePhase == RamenTimerPhase.resultReveal) {
      final resultIndex = switch (game.resultVerdict) {
        RamenTimerVerdict.perfect => 0,
        RamenTimerVerdict.tooEarly => 1,
        RamenTimerVerdict.tooLate => 2,
        null => 0,
      };
      _drawFrame(
        canvas,
        ramenResult,
        columns: 3,
        rows: 1,
        frameIndex: resultIndex,
        destination: _cupRect,
      );
      return;
    }

    _drawFrame(
      canvas,
      ramenCup,
      columns: 4,
      rows: 1,
      frameIndex: game.cupFrame,
      destination: _cupRect,
    );

    final age = game.eventAge;
    if (age < 0 ||
        age > RamenTimerRules.ingredientEventMilliseconds / 1000 ||
        game.eventTapIndex > 1) {
      return;
    }
    final progress =
        (age / (RamenTimerRules.ingredientEventMilliseconds / 1000)).clamp(
          0.0,
          1.0,
        );
    final y = ui.lerpDouble(310, 386, Curves.easeIn.transform(progress))!;
    _drawFrame(
      canvas,
      ramenFx,
      columns: 3,
      rows: 2,
      frameIndex: game.eventTapIndex == 0 ? 2 : 3,
      destination: Rect.fromCenter(
        center: Offset(270, y),
        width: 48,
        height: 48,
      ),
    );
  }

  void _drawResultTimeline(Canvas canvas) {
    final taps = game.tapMilliseconds;
    if (taps.length != RamenTimerRules.targetMilliseconds.length) return;
    final errors = RamenTimerRules.signedErrorsMilliseconds(taps);
    final revealCount = (game.resultRevealProgress * 3.4).floor().clamp(0, 3);
    final panel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 84, 324, 202),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      panel.shift(const Offset(5, 6)),
      Paint()..color = const Color(0xB3000710),
    );
    canvas.drawRRect(panel, Paint()..color = const Color(0xF014293B));
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF55758A),
    );
    _text(
      canvas,
      '조리 기록표',
      const Offset(180, 98),
      color: const Color(0xFFFFDE78),
      size: 19,
      anchor: Alignment.topCenter,
    );
    _text(
      canvas,
      '회차',
      const Offset(40, 130),
      color: const Color(0xFF8EA9B8),
      size: 10,
    );
    _text(
      canvas,
      '목표 대비 오차',
      const Offset(322, 130),
      color: const Color(0xFF8EA9B8),
      size: 10,
      anchor: Alignment.topRight,
    );
    canvas.drawRect(
      const Rect.fromLTWH(32, 145, 296, 2),
      Paint()..color = const Color(0xFF38576A),
    );

    for (var index = 0; index < revealCount; index++) {
      final y = 158.0 + index * 39;
      _text(
        canvas,
        '${index + 1}차',
        Offset(40, y),
        color: const Color(0xFFE9F0EC),
        size: 15,
      );
      _text(
        canvas,
        RamenTimerRules.formatSignedError(errors[index]),
        Offset(322, y),
        color: errors[index] < 0
            ? const Color(0xFF6FD8D2)
            : errors[index] > 0
            ? const Color(0xFFFF8E79)
            : const Color(0xFFFFD86A),
        size: 16,
        anchor: Alignment.topRight,
      );
      if (index < 2) {
        canvas.drawRect(
          Rect.fromLTWH(32, y + 27, 296, 1),
          Paint()..color = const Color(0xFF2D4A5B),
        );
      }
    }
  }

  void _drawFrame(
    Canvas canvas,
    ui.Image image, {
    required int columns,
    required int rows,
    required int frameIndex,
    required Rect destination,
    double opacity = 1,
  }) {
    final safeIndex = frameIndex.clamp(0, columns * rows - 1);
    final cellWidth = image.width / columns;
    final cellHeight = image.height / rows;
    final column = safeIndex % columns;
    final row = safeIndex ~/ columns;
    final paint = opacity >= 0.999
        ? _paint
        : (Paint()
            ..isAntiAlias = true
            ..filterQuality = FilterQuality.medium
            ..color = const Color(
              0xFFFFFFFF,
            ).withValues(alpha: opacity.clamp(0.0, 1.0)));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        column * cellWidth,
        row * cellHeight,
        cellWidth,
        cellHeight,
      ),
      destination,
      paint,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset position, {
    required Color color,
    required double size,
    Alignment anchor = Alignment.topLeft,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'Galmuri',
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = Offset(
      position.dx - painter.width * (anchor.x + 1) / 2,
      position.dy - painter.height * (anchor.y + 1) / 2,
    );
    painter.paint(canvas, offset);
  }
}
