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
import 'package:just_one_round/features/games/western_duel/domain/western_duel_opponent.dart';
import 'package:just_one_round/features/games/western_duel/domain/western_duel_rules.dart';

enum WesternDuelPhase {
  loading,
  countdown,
  standoff,
  draw,
  resolve,
  finished,
  interrupted,
}

class WesternDuelGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  WesternDuelGame({
    required this.onFinished,
    required int challengeSeed,
    Duration countdownDuration = WesternDuelRules.safeCountdown,
    this.enableHaptics = true,
  }) : _random = Random(challengeSeed),
       _decorativeRandom = Random(challengeSeed ^ 0x5F3759DF),
       _countdownSeconds = countdownDuration.inMicroseconds / 1000000,
       hud = ValueNotifier(
         const MiniGameHudState(
           phase: MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: null,
           countdownNumber: 4,
         ),
       );

  static final logicalSize = Vector2(360, 720);
  // The full-body source stays intact; the fixed viewport supplies the
  // first-person crop by placing the sprite mostly off-screen.
  static const int playerIdleSheetColumns = 2;
  static const int playerIdleSheetRows = 2;
  static const int playerIdleFrameCount = 4;
  static const int playerActionSheetColumns = 4;
  static const int playerActionSheetRows = 4;
  static const int playerActionFrameCount = 16;
  // The eighth authored pose (zero-based index 7) is the visual firing pose.
  // Keep this shared by timing, muzzle anchors, preview, and tests so a
  // future atlas layout cannot silently drift away from the shot event.
  static const int playerActionFireFrame = 7;
  static const double playerActionSourceCellWidth = 540;
  static const double playerActionSourceCellHeight = 1080;
  static const double playerActionScaleX = 1;
  static const double playerActionScaleY = 1;
  // The opponent is enlarged around the same center and foot line. Keep the
  // foot anchor fixed while the opponent uses 1.38x from the original art.
  static const double opponentCenterX = 180;
  static const double opponentFeetY = 430;
  static const double opponentScale = 1.38;
  static const double opponentWidth = 112 * opponentScale;
  static const double opponentHeight = 160 * opponentScale;
  static const double opponentX = opponentCenterX - opponentWidth / 2;
  static Rect opponentRectForHeight(double height) => Rect.fromLTWH(
    opponentX,
    opponentFeetY + (height - 720) / 2 - opponentHeight,
    opponentWidth,
    opponentHeight,
  );

  static Rect _opponentOverlayRectForHeight(double height, Rect baseRect) {
    final feet = opponentFeetY + (height - 720) / 2;
    final anchor = Offset(opponentCenterX, feet);
    final scaledTopLeft = Offset(
      anchor.dx + (baseRect.left - anchor.dx) * opponentScale,
      anchor.dy + (baseRect.top - anchor.dy) * opponentScale,
    );
    return Rect.fromLTWH(
      scaledTopLeft.dx,
      scaledTopLeft.dy,
      baseRect.width * opponentScale,
      baseRect.height * opponentScale,
    );
  }

  static Rect opponentMuzzleRectForHeight(double height) =>
      _opponentOverlayRectForHeight(
        height,
        Rect.fromLTWH(192, 342 + (height - 720) / 2, 42, 42),
      );

  static Rect opponentHitRectForHeight(double height) =>
      _opponentOverlayRectForHeight(
        height,
        Rect.fromLTWH(158, 326 + (height - 720) / 2, 44, 44),
      );

  static Rect opponentMissRectForHeight(double height) =>
      _opponentOverlayRectForHeight(
        height,
        Rect.fromLTWH(219, 444 + (height - 720) / 2, 42, 42),
      );
  static const double playerActionDisplayX = -254;
  static const double playerActionDisplayYFromBottom = -680;
  static const double playerActionDisplayWidth =
      playerActionSourceCellWidth * playerActionScaleX;
  static const double playerActionDisplayHeight =
      playerActionSourceCellHeight * playerActionScaleY;
  static const int playerForwardFallSheetColumns = 2;
  static const int playerForwardFallSheetRows = 4;
  static const int playerForwardFallFrameCount = 8;
  static const int victoryFrameCount = 6;
  static const double victoryFrameSeconds = 0.14;
  static const double victoryDurationSeconds =
      victoryFrameCount * victoryFrameSeconds;
  static const double victorySmokeStartSeconds = 0.49;
  static const List<double> playerForwardFallFrameSeconds = [
    0.08,
    0.08,
    0.10,
    0.16,
    0.22,
    0.10,
    0.12,
    0.10,
  ];
  static const double playerForwardFallDurationSeconds = 0.96;
  static const double playerForwardFallBlendSeconds = 0.08;
  // Only the death pose is reduced; the standing and firing views stay put.
  // Anchor the first fall frame near the standing body's center and hat line.
  static const double playerForwardFallDisplayScale = 0.65;
  static const double playerForwardFallTravelX = 45;
  static const double playerForwardFallTravelY = 40;
  // Measured from the v11 fire frame's visible revolver muzzle in the
  // 540x1080 delivery cell. The body itself remains a whole, uncropped asset;
  // only the fixed viewport clips the lower/left portions at runtime.
  static const double playerMuzzleSourceX = 410;
  static const double playerMuzzleSourceY = 365;
  static const double playerBreechSourceX = 381;
  static const double playerBreechSourceY = 404;
  // The flash spans the fire pose and the first three recoil poses. Track the
  // gray revolver tip per frame so the flash stays attached while the arm
  // settles; all other action frames intentionally use the fire anchor.
  static Offset playerMuzzleSourceForActionFrame(int frame) => switch (frame) {
    8 => const Offset(413, 360),
    9 => const Offset(412, 365),
    10 => const Offset(411, 365),
    _ => const Offset(playerMuzzleSourceX, playerMuzzleSourceY),
  };
  static const double playerMuzzleDisplayX =
      playerActionDisplayX + playerMuzzleSourceX * playerActionScaleX;
  static const double playerMuzzleDisplayY =
      playerMuzzleSourceY * playerActionScaleY;
  static const double playerFlashSize = 56;
  static const double playerIdleBreathingCycleSeconds = 3;
  static const double playerIdleBreathingAmplitude = 0.009;
  static const double playerIdleBreathingWaistSourceY = 650;
  // The shot frame begins at 0.21s while the complete body stays planted.
  static const double _visualShotLagSeconds = 0.21;
  // Frames 0..6 are quick grip/draw/aim stages; frame 7 starts at 0.21s and
  // lines up with the shared flash. The remaining nine frames settle at 0.04s
  // each, for a deterministic 0.57s one-shot animation.
  static const double _playerPreFireFrameSeconds = 0.03;
  static const double _playerPostFireFrameSeconds = 0.04;
  // Decimal frame durations cannot all be represented exactly as doubles;
  // absorb only sub-picosecond arithmetic noise, not a meaningful early tap.
  static const double _playerFrameBoundaryEpsilon = 1e-12;
  static const double _playerFireStartSeconds =
      playerActionFireFrame * _playerPreFireFrameSeconds;
  static const double playerActionDurationSeconds =
      _playerFireStartSeconds +
      (playerActionFrameCount - playerActionFireFrame) *
          _playerPostFireFrameSeconds;
  static const double _playerIdleFrameSeconds = 0.75;
  static const double _opponentFrameSeconds = 0.035;
  static const double _visualFlashSeconds = 0.12;

  @visibleForTesting
  static int playerActionFrameForTesting(double elapsedSeconds) {
    final elapsed = max(0, elapsedSeconds);
    if (elapsed < _playerFireStartSeconds) {
      return min(
        playerActionFireFrame - 1,
        (elapsed / _playerPreFireFrameSeconds + _playerFrameBoundaryEpsilon)
            .floor(),
      );
    }
    return min(
      playerActionFrameCount - 1,
      playerActionFireFrame +
          ((elapsed - _playerFireStartSeconds) / _playerPostFireFrameSeconds +
                  _playerFrameBoundaryEpsilon)
              .floor(),
    );
  }

  /// Shared by the runtime and static presentation previews.
  static int playerActionFrameForElapsed(double elapsedSeconds) =>
      playerActionFrameForTesting(elapsedSeconds);

  @visibleForTesting
  static int playerIdleFrameForTesting(double elapsedSeconds) =>
      (elapsedSeconds / _playerIdleFrameSeconds).floor() % playerIdleFrameCount;

  /// Shared by the runtime and static presentation previews.
  static int playerIdleFrameForElapsed(double elapsedSeconds) =>
      playerIdleFrameForTesting(elapsedSeconds);

  @visibleForTesting
  static int playerForwardFallFrameForTesting(double elapsedSeconds) {
    var boundary = 0.0;
    for (var frame = 0; frame < playerForwardFallFrameCount - 1; frame++) {
      boundary += playerForwardFallFrameSeconds[frame];
      if (elapsedSeconds < boundary - _playerFrameBoundaryEpsilon) return frame;
    }
    return playerForwardFallFrameCount - 1;
  }

  static Rect playerUnifiedRectForHeight(double height) => Rect.fromLTWH(
    playerActionDisplayX,
    height + playerActionDisplayYFromBottom,
    playerActionDisplayWidth,
    playerActionDisplayHeight,
  );

  @visibleForTesting
  static Rect playerForwardFallRectForHeight(
    double height,
    double elapsedSeconds,
  ) {
    final base = playerUnifiedRectForHeight(height);
    double smooth(double value) {
      final t = value.clamp(0.0, 1.0).toDouble();
      return t * t * (3 - 2 * t);
    }

    final travel = elapsedSeconds <= 0.26
        ? 0.18 * smooth((elapsedSeconds - playerForwardFallBlendSeconds) / 0.18)
        : elapsedSeconds <= 0.64
        ? 0.18
        : 0.18 + 0.82 * smooth((elapsedSeconds - 0.64) / 0.32);
    final scale = playerForwardFallDisplayScale;
    return Rect.fromLTWH(
      (base.left + 270 * (1 - scale) + playerForwardFallTravelX * travel)
          .roundToDouble(),
      (base.top + 306 * (1 - scale) + playerForwardFallTravelY * travel)
          .roundToDouble(),
      base.width * scale,
      base.height * scale,
    );
  }

  // Pose motion is authored inside the atlas; its close-up root stays fixed.
  static Rect playerActionRectForHeight(double height, int frame) {
    RangeError.checkValueInInterval(frame, 0, playerActionFrameCount - 1);
    return playerUnifiedRectForHeight(height);
  }

  // The v11 idle atlas repeats one planted master in every cell. Breathing
  // scales around the waist so the hip/holster anchor stays still while the
  // head moves by roughly three logical pixels over the slow cycle.
  static Rect playerIdleRectForHeight(
    double height,
    int frame, {
    double elapsedSeconds = 0,
  }) {
    RangeError.checkValueInInterval(frame, 0, playerIdleFrameCount - 1);
    final base = playerUnifiedRectForHeight(height);
    final scaleY =
        1 +
        playerIdleBreathingAmplitude *
            sin(2 * pi * elapsedSeconds / playerIdleBreathingCycleSeconds);
    return Rect.fromLTWH(
      base.left,
      base.top + playerIdleBreathingWaistSourceY * (1 - scaleY),
      base.width,
      base.height * scaleY,
    );
  }

  // Compatibility alias for old preview/test callers. The foreground no
  // longer renders this as a separate body layer.
  static Rect playerBodyRectForHeight(double height) =>
      playerUnifiedRectForHeight(height);

  static Offset playerMuzzlePositionForHeight(
    double height, {
    int frame = playerActionFireFrame,
  }) {
    final sprite = playerActionRectForHeight(height, frame);
    final source = playerMuzzleSourceForActionFrame(frame);
    return Offset(
      sprite.left + source.dx * playerActionScaleX,
      sprite.top + source.dy * playerActionScaleY,
    );
  }

  static Offset playerBreechPositionForHeight(double height) {
    final sprite = playerActionRectForHeight(height, playerActionFireFrame);
    return Offset(
      sprite.left + playerBreechSourceX * playerActionScaleX,
      sprite.top + playerBreechSourceY * playerActionScaleY,
    );
  }

  static Offset playerShotTargetPositionForHeight(double height) {
    final opponent = opponentRectForHeight(height);
    return Offset(opponent.center.dx, opponent.top + opponent.height * 0.38);
  }

  static double playerShotAngleForHeight(
    double height, {
    int frame = playerActionFireFrame,
  }) {
    final muzzle = playerMuzzlePositionForHeight(height, frame: frame);
    final target = playerShotTargetPositionForHeight(height);
    return atan2(target.dy - muzzle.dy, target.dx - muzzle.dx);
  }

  final ValueChanged<GameResult> onFinished;
  final Random _random;
  final Random _decorativeRandom;
  final double _countdownSeconds;
  final bool enableHaptics;

  @override
  final ValueNotifier<MiniGameHudState> hud;
  @override
  FlameGame get flameGame => this;

  WesternDuelOpponent? _opponent;
  WesternDuelPhase phase = WesternDuelPhase.loading;
  late final _WesternDuelScene _scene;
  final Stopwatch _reactionClock = Stopwatch();
  final Set<int> _heldPointers = {};
  double _logicalHeight = 720;
  double _elapsed = 0;
  double _phaseElapsed = 0;
  double _standoffSeconds = 0;
  double _resolveSeconds = 0;
  int? reactionMilliseconds;
  bool opponentFired = false;
  bool playerFired = false;
  double _opponentFlash = 0;
  double _playerFlash = 0;
  double _opponentActionElapsed = 0;
  double _playerActionElapsed = 0;
  bool _opponentVisualFired = false;
  bool _playerVisualFired = false;
  double? _bothFiredAt;
  bool _impactApplied = false;
  bool _forcedTimeout = false;
  double? _winnerCelebrationElapsed;
  bool _playerForwardFallStarted = false;
  bool _playerForwardFallCompleted = false;
  double _playerForwardFallElapsed = 0;
  Rect? _playerForwardFallEntryRect;
  int _playerForwardFallEntryFrame = 0;
  bool _disposed = false;
  bool _reported = false;
  String? _failure;

  // Decorative atmosphere has its own RNG and state so it can never consume
  // challenge randomness or create more than one wind ribbon/leaf at once.
  bool _windVisible = false;
  double _windGapRemaining = 0;
  double _windX = 0;
  double _windSpeed = 0;
  double _windY = 430;
  double _windBobAmplitude = 0;
  double _windBobPhase = 0;
  double _windAnimationElapsed = 0;
  bool _leafVisible = false;
  double _leafGapRemaining = 0;
  double _leafX = 0;
  double _leafSpeed = 0;
  double _leafY = 444;
  double _leafBobAmplitude = 0;
  double _leafBobPhase = 0;
  double _leafAnimationElapsed = 0;

  @visibleForTesting
  bool get isReadyForTesting => phase == WesternDuelPhase.countdown;

  @visibleForTesting
  bool get impactAppliedForTesting => _impactApplied;

  @visibleForTesting
  bool get opponentVisualShotForTesting => _opponentVisualFired;

  @visibleForTesting
  bool get playerVisualShotForTesting => _playerVisualFired;

  @visibleForTesting
  bool get playerForwardFallStartedForTesting => _playerForwardFallStarted;

  @visibleForTesting
  bool get playerForwardFallCompletedForTesting => _playerForwardFallCompleted;

  @visibleForTesting
  bool get forcedTimeoutForTesting => _forcedTimeout;

  @visibleForTesting
  double? get winnerCelebrationElapsedForTesting => _winnerCelebrationElapsed;

  bool get _playerWon =>
      _impactApplied &&
      reactionMilliseconds != null &&
      _opponent != null &&
      WesternDuelRules.compare(
            reactionMilliseconds!,
            _opponent!.reactionMilliseconds,
          ) ==
          WesternDuelOutcome.win;

  bool get _opponentWon =>
      _failure != null ||
      (_impactApplied &&
          reactionMilliseconds != null &&
          _opponent != null &&
          WesternDuelRules.compare(
                reactionMilliseconds!,
                _opponent!.reactionMilliseconds,
              ) ==
              WesternDuelOutcome.lose);

  @visibleForTesting
  double get standoffSecondsForTesting => _standoffSeconds;

  @visibleForTesting
  bool get atmosphereActiveForTesting =>
      _windVisible ||
      _leafVisible ||
      _windGapRemaining > 0 ||
      _leafGapRemaining > 0;

  @visibleForTesting
  int nextChallengeRandomForTesting() => _random.nextInt(1 << 30);

  WesternDuelOpponent? get opponent => _opponent;
  String? get failureMessage => _failure;

  void setOpponent(WesternDuelOpponent opponent) {
    if (phase != WesternDuelPhase.countdown &&
        phase != WesternDuelPhase.loading) {
      throw StateError('Opponent must be fixed before the duel starts');
    }
    if (!WesternDuelRules.isValidReaction(opponent.reactionMilliseconds)) {
      throw ArgumentError.value(
        opponent.reactionMilliseconds,
        'reactionMilliseconds',
      );
    }
    _opponent = opponent;
    _publishHud();
  }

  @override
  Color backgroundColor() => const Color(0xFFAD784B);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);
    final paths = [
      'western_duel/background/saloon_day_180x480.png',
      'western_duel/first_person/opponent_idle_close/sheet-transparent.png',
      'western_duel/first_person/opponent_draw_fire_close/sheet-transparent.png',
      'western_duel/first_person/opponent_hit_fall_close/sheet-transparent.png',
      'western_duel/first_person/player_detail_idle_v11/sheet-transparent.png',
      'western_duel/first_person/player_detail_action_v11/sheet-transparent.png',
      'western_duel/fx/muzzle_flash/sheet-transparent.png',
      'western_duel/fx/miss_dust/sheet-transparent.png',
      'western_duel/fx/hit_spark/sheet-transparent.png',
      'western_duel/fx/standoff_wind/sheet-transparent.png',
      'western_duel/fx/standoff_leaf/sheet-transparent.png',
      'western_duel/first_person/player_forward_fall_v13/sheet-transparent.png',
      'western_duel/first_person/player_victory_v14/sheet-transparent.png',
      'western_duel/first_person/opponent_victory_v14/sheet-transparent.png',
      'western_duel/fx/victory_smoke_v14/sheet-transparent.png',
    ];
    try {
      final loaded = await images.loadAll(paths);
      _scene = _WesternDuelScene(this, loaded);
      await world.add(_scene);
      phase = WesternDuelPhase.countdown;
      _standoffSeconds = WesternDuelRules.standoffMilliseconds(_random) / 1000;
      _publishHud();
    } catch (_) {
      phase = WesternDuelPhase.interrupted;
      pauseEngine();
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _configureViewport(size);
  }

  void _configureViewport(Vector2 size) {
    _logicalHeight = size.x <= 0
        ? 720
        : (360 * size.y / size.x).clamp(640, 800).toDouble();
    final resolution = Vector2(360, _logicalHeight);
    camera.viewport = FixedResolutionViewport(resolution: resolution);
    camera.viewfinder.position = resolution / 2;
  }

  double _decorativeRange(double minValue, double maxValue) =>
      minValue + _decorativeRandom.nextDouble() * (maxValue - minValue);

  void _beginStandoffAtmosphere() {
    _windVisible = false;
    _leafVisible = false;
    _windGapRemaining = _decorativeRange(0.08, 0.62);
    _leafGapRemaining = _decorativeRange(0.28, 1.05);
  }

  void _clearStandoffAtmosphere() {
    _windVisible = false;
    _leafVisible = false;
    _windGapRemaining = 0;
    _leafGapRemaining = 0;
  }

  void _spawnWind() {
    _windVisible = true;
    _windX = -256;
    _windSpeed = _decorativeRange(165, 235);
    _windY = _decorativeRange(424, 442);
    _windBobAmplitude = _decorativeRange(1.5, 6.5);
    _windBobPhase = _decorativeRange(0, 2 * pi);
    _windAnimationElapsed = 0;
  }

  void _spawnLeaf() {
    _leafVisible = true;
    _leafX = -32;
    _leafSpeed = _decorativeRange(115, 195);
    _leafY = _decorativeRange(438, 454);
    _leafBobAmplitude = _decorativeRange(2.5, 8.5);
    _leafBobPhase = _decorativeRange(0, 2 * pi);
    _leafAnimationElapsed = 0;
  }

  void _updateStandoffAtmosphere(double dt) {
    if (!_windVisible) {
      _windGapRemaining -= dt;
      if (_windGapRemaining <= 0) _spawnWind();
    } else {
      _windX += _windSpeed * dt;
      _windAnimationElapsed += dt;
      if (_windX > 360) {
        _windVisible = false;
        _windGapRemaining = _decorativeRange(0.42, 1.35);
      }
    }

    if (!_leafVisible) {
      _leafGapRemaining -= dt;
      if (_leafGapRemaining <= 0) _spawnLeaf();
    } else {
      _leafX += _leafSpeed * dt;
      _leafAnimationElapsed += dt;
      if (_leafX > 360) {
        _leafVisible = false;
        _leafGapRemaining = _decorativeRange(0.58, 1.55);
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_disposed || _reported || _opponent == null || dt <= 0) return;
    _opponentFlash = max(0, _opponentFlash - dt);
    _playerFlash = max(0, _playerFlash - dt);
    _elapsed += dt;
    _phaseElapsed += dt;
    if (phase == WesternDuelPhase.standoff ||
        phase == WesternDuelPhase.draw ||
        phase == WesternDuelPhase.resolve) {
      _updateStandoffAtmosphere(dt);
    }
    _advanceVisualShot(dt);
    if (_winnerCelebrationElapsed != null) {
      _winnerCelebrationElapsed = min(
        victoryDurationSeconds,
        _winnerCelebrationElapsed! + dt,
      );
    }
    switch (phase) {
      case WesternDuelPhase.countdown:
        if (_phaseElapsed >= _countdownSeconds) {
          _next(WesternDuelPhase.standoff);
        }
      case WesternDuelPhase.standoff:
        if (_phaseElapsed >= _standoffSeconds) {
          _next(WesternDuelPhase.draw);
          _reactionClock.start();
        }
      case WesternDuelPhase.draw:
        final elapsedMs = _reactionClock.elapsedMicroseconds ~/ 1000;
        if (!opponentFired && elapsedMs >= _opponent!.reactionMilliseconds) {
          _fireOpponent();
        }
        if (elapsedMs >= WesternDuelRules.responseDeadlineMs) {
          _timeoutAtDeadline();
        }
      case WesternDuelPhase.resolve:
        _resolveSeconds += dt;
        // The player remains unharmed until both flashes have happened.
        if (!opponentFired &&
            (_reactionClock.isRunning
                ? _reactionClock.elapsedMicroseconds ~/ 1000 >=
                      _opponent!.reactionMilliseconds
                : _failure != null && _resolveSeconds >= 0.18)) {
          _fireOpponent();
        }
        if (opponentFired && (playerFired || _failure != null)) {
          _bothFiredAt ??= _elapsed;
          final afterBoth = _elapsed - _bothFiredAt!;
          // A logical shot is not a hit on screen until both draw animations
          // reach their firing frame. A timeout keeps the deterministic
          // 1.000s ranked score but never shows a fake player shot or impact.
          if (playerFired && _playerVisualFired && _opponentVisualFired) {
            _impactApplied = true;
          }
          if (_winnerCelebrationElapsed == null &&
              afterBoth >= 0.45 &&
              _opponentVisualFired &&
              (!playerFired || _playerVisualFired) &&
              (_playerWon || _opponentWon)) {
            // Derive pose time from the duel clock so a large frame/test tick
            // cannot postpone completion of an already-finished victory.
            _winnerCelebrationElapsed = min(
              victoryDurationSeconds,
              afterBoth - 0.45,
            );
          }
          final fallReady =
              !_playerForwardFallStarted || _playerForwardFallCompleted;
          if (afterBoth >= 1.4 &&
              (!playerFired || _impactApplied) &&
              fallReady &&
              (_winnerCelebrationElapsed == null ||
                  _winnerCelebrationElapsed! >= victoryDurationSeconds)) {
            _finish();
          }
        }
      case WesternDuelPhase.loading:
      case WesternDuelPhase.finished:
      case WesternDuelPhase.interrupted:
        break;
    }
    _publishHud();
  }

  void _fireOpponent() {
    if (opponentFired) return;
    opponentFired = true;
    _opponentActionElapsed = 0;
    _opponentVisualFired = false;
    if (playerFired || _failure != null) _reactionClock.stop();
  }

  void _advanceVisualShot(double dt) {
    if (_playerForwardFallStarted && !_playerForwardFallCompleted) {
      _playerForwardFallElapsed += dt;
      if (_playerForwardFallElapsed >=
          WesternDuelGame.playerForwardFallDurationSeconds) {
        _playerForwardFallElapsed =
            WesternDuelGame.playerForwardFallDurationSeconds;
        _playerForwardFallCompleted = true;
      }
    }
    if (opponentFired) {
      _opponentActionElapsed += dt;
      if (!_opponentVisualFired &&
          _opponentActionElapsed >= _visualShotLagSeconds) {
        _opponentVisualFired = true;
        _opponentFlash = _visualFlashSeconds;
      }
    }
    if (playerFired) {
      _playerActionElapsed += dt;
      if (!_playerVisualFired &&
          _playerActionElapsed >= _visualShotLagSeconds) {
        _playerVisualFired = true;
        _playerFlash = _visualFlashSeconds;
        if (_playerIsSlowerThanOpponent) _startPlayerForwardFall();
      }
    }
  }

  bool get _playerIsSlowerThanOpponent =>
      !_forcedTimeout &&
      reactionMilliseconds != null &&
      _opponent != null &&
      WesternDuelRules.compare(
            reactionMilliseconds!,
            _opponent!.reactionMilliseconds,
          ) ==
          WesternDuelOutcome.lose;

  void _startPlayerForwardFall() {
    if (_playerForwardFallStarted) return;
    _playerForwardFallStarted = true;
    _playerForwardFallCompleted = false;
    _playerForwardFallElapsed = 0;
    if (playerFired) {
      _playerForwardFallEntryFrame = playerActionFrameForTesting(
        _playerActionElapsed,
      );
      _playerForwardFallEntryRect = playerActionRectForHeight(
        _logicalHeight,
        _playerForwardFallEntryFrame,
      );
    } else {
      _playerForwardFallEntryFrame = playerIdleFrameForTesting(_elapsed);
      _playerForwardFallEntryRect = playerIdleRectForHeight(
        _logicalHeight,
        _playerForwardFallEntryFrame,
        elapsedSeconds: _elapsed,
      );
    }
  }

  void _timeoutAtDeadline() {
    if (_forcedTimeout) return;
    _reactionClock.stop();
    _forcedTimeout = true;
    reactionMilliseconds = WesternDuelRules.responseDeadlineMs;
    _failure = '발사하지 못했어요';
    _startPlayerForwardFall();
    _next(WesternDuelPhase.resolve);
  }

  void _startPlayerAction() {
    playerFired = true;
    _playerActionElapsed = 0;
    _playerVisualFired = false;
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final alreadyHeld = _heldPointers.isNotEmpty;
    _heldPointers.add(event.pointerId);
    if (alreadyHeld) return;
    final point = camera.viewport.globalToLocal(event.canvasPosition);
    if (point.x < 12 ||
        point.x > 348 ||
        point.y < 90 ||
        point.y > _logicalHeight - 12) {
      return;
    }
    tapForTesting();
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    _heldPointers.remove(event.pointerId);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    _heldPointers.remove(event.pointerId);
  }

  @visibleForTesting
  void tapForTesting({int? reactionMs}) {
    if (_disposed || _opponent == null) return;
    if (phase == WesternDuelPhase.standoff) {
      // A false start loses the attempt, but never draws or fires our gun.
      _failure = '너무 빨리 눌렀어요';
      _next(WesternDuelPhase.resolve);
    } else if (phase == WesternDuelPhase.draw) {
      final measured =
          reactionMs ?? max(1, _reactionClock.elapsedMicroseconds ~/ 1000);
      if (measured >= WesternDuelRules.responseDeadlineMs) {
        _timeoutAtDeadline();
        _publishHud();
        return;
      }
      if (!WesternDuelRules.isValidReaction(measured)) return;
      // Capture the score at input time. The draw animation is deliberately
      // delayed so visual feedback cannot change the measured reaction.
      reactionMilliseconds = measured;
      _startPlayerAction();
      if (!opponentFired &&
          _reactionClock.elapsedMicroseconds ~/ 1000 >=
              _opponent!.reactionMilliseconds) {
        _fireOpponent();
      }
      if (opponentFired) {
        _reactionClock.stop();
        _bothFiredAt = _elapsed;
      }
      _next(WesternDuelPhase.resolve);
      if (enableHaptics) HapticFeedback.selectionClick();
    }
    _publishHud();
  }

  void _next(WesternDuelPhase next) {
    phase = next;
    _phaseElapsed = 0;
    if (next == WesternDuelPhase.standoff) {
      _beginStandoffAtmosphere();
    } else if (next == WesternDuelPhase.finished ||
        next == WesternDuelPhase.interrupted) {
      _clearStandoffAtmosphere();
    }
  }

  void _finish() {
    if (_reported) return;
    _reported = true;
    phase = WesternDuelPhase.finished;
    _clearStandoffAtmosphere();
    pauseEngine();
    final ms = reactionMilliseconds;
    final lost =
        _forcedTimeout ||
        (ms != null &&
            _opponent != null &&
            WesternDuelRules.compare(ms, _opponent!.reactionMilliseconds) ==
                WesternDuelOutcome.lose);
    onFinished(
      GameResult(
        score: ms == null ? 0 : WesternDuelRules.scoreForReaction(ms),
        starsCollected: 0,
        collisions: 0,
        duration: Duration(milliseconds: (_elapsed * 1000).round()),
        endType: ms == null || lost ? GameEndType.gameOver : GameEndType.clear,
      ),
    );
  }

  void _publishHud() {
    if (_disposed) return;
    hud.value = MiniGameHudState(
      phase: phase == WesternDuelPhase.countdown
          ? MiniGamePhase.countdown
          : phase == WesternDuelPhase.finished
          ? MiniGamePhase.finished
          : MiniGamePhase.playing,
      score: reactionMilliseconds == null
          ? 0
          : WesternDuelRules.scoreForReaction(reactionMilliseconds!),
      elapsedSeconds: _elapsed.floor(),
      remainingSeconds: null,
      countdownNumber: phase == WesternDuelPhase.countdown
          ? max(0, (_countdownSeconds - _phaseElapsed).ceil())
          : 0,
      message: _failure,
    );
  }

  @override
  void interrupt() {
    if (_reported || _disposed) return;
    if (reactionMilliseconds != null) {
      _finish();
    } else {
      phase = WesternDuelPhase.interrupted;
      _clearStandoffAtmosphere();
      _reactionClock.stop();
      pauseEngine();
    }
  }

  @override
  void disposeController() {
    if (_disposed) return;
    _disposed = true;
    _reactionClock.stop();
    pauseEngine();
    hud.dispose();
  }
}

class _WesternDuelScene extends PositionComponent {
  _WesternDuelScene(this.game, this.art);
  final WesternDuelGame game;
  final List<ui.Image> art;
  final Paint paint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  void _image(
    Canvas canvas,
    ui.Image image,
    Rect target, {
    int frame = 0,
    int frames = 1,
    int? columns,
  }) {
    final gridColumns = columns ?? (frames == 1 ? 1 : 2);
    final rows = (frames / gridColumns).ceil();
    final width = image.width / gridColumns;
    final height = image.height / rows;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        width * (frame % gridColumns),
        height * (frame ~/ gridColumns),
        width,
        height,
      ),
      target,
      paint,
    );
  }

  void _imageRotated(
    Canvas canvas,
    ui.Image image,
    Rect target, {
    required double rotation,
    int frame = 0,
    int frames = 1,
    int? columns,
  }) {
    final center = target.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    _image(
      canvas,
      image,
      Rect.fromCenter(
        center: Offset.zero,
        width: target.width,
        height: target.height,
      ),
      frame: frame,
      frames: frames,
      columns: columns,
    );
    canvas.restore();
  }

  int _muzzleFlashFrame(double remainingSeconds) =>
      ((1 - remainingSeconds / WesternDuelGame._visualFlashSeconds) * 4)
          .floor()
          .clamp(0, 3)
          .toInt();

  void _label(
    Canvas canvas,
    String text,
    double y, {
    double size = 20,
    Color color = const Color(0xFFFFE6B4),
    double centerX = 180,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w900,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 5, offset: Offset(2, 2)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 340);
    painter.paint(canvas, Offset(centerX - painter.width / 2, y));
  }

  Color _nameColor(String? value) => switch (value) {
    'coral' => const Color(0xFFFFA182),
    'mint' => const Color(0xFF9AE2C0),
    'sky' => const Color(0xFF9DCBFF),
    'violet' => const Color(0xFFC7A5FF),
    'pink' => const Color(0xFFFFB8D5),
    _ => const Color(0xFFFFE6B4),
  };

  void _renderStandoffAtmosphere(Canvas canvas, double centerOffset) {
    if (game.phase != WesternDuelPhase.standoff &&
        game.phase != WesternDuelPhase.draw &&
        game.phase != WesternDuelPhase.resolve) {
      return;
    }

    // The alpha is intentionally part of the draw paint, not the source art:
    // the same tiny sheets remain reusable for other scene lighting.
    if (game._windVisible) {
      final windY =
          game._windY +
          centerOffset +
          sin(game._windBobPhase + game._windAnimationElapsed * 2.4) *
              game._windBobAmplitude;
      paint.color = const Color(0x66FFFFFF);
      _image(
        canvas,
        art[9],
        Rect.fromLTWH(game._windX, windY, 256, 64),
        frame: (game._windAnimationElapsed / 0.18).floor() % 4,
        frames: 4,
        columns: 2,
      );
    }
    if (game._leafVisible) {
      final leafY =
          game._leafY +
          centerOffset +
          sin(game._leafBobPhase + game._leafAnimationElapsed * 3.1) *
              game._leafBobAmplitude;
      paint.color = const Color(0xBFFFFFFF);
      _imageRotated(
        canvas,
        art[10],
        Rect.fromLTWH(game._leafX, leafY, 32, 32),
        rotation:
            sin(game._leafBobPhase + game._leafAnimationElapsed * 3.1) * 0.3,
        frame: (game._leafAnimationElapsed / 0.23).floor() % 4,
        frames: 4,
        columns: 2,
      );
    }
    paint.color = Colors.white;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final height = game._logicalHeight;
    final centerOffset = (height - 720) / 2;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, 360, height));
    _image(canvas, art[0], Rect.fromLTWH(0, (height - 960) / 2, 360, 960));
    final opponent = game._opponent;
    final resolved = game._impactApplied && game.reactionMilliseconds != null;
    final outcome = resolved
        ? WesternDuelRules.compare(
            game.reactionMilliseconds!,
            opponent!.reactionMilliseconds,
          )
        : null;
    final opponentFall =
        !game._forcedTimeout && outcome == WesternDuelOutcome.win;
    final victoryElapsed = game._winnerCelebrationElapsed;
    final opponentCelebrating = victoryElapsed != null && game._opponentWon;
    final playerCelebrating = victoryElapsed != null && game._playerWon;
    final idleFrame = (game._elapsed * 2).floor() % 4;
    final opponentFrame = opponentCelebrating
        ? min(
            WesternDuelGame.victoryFrameCount - 1,
            (victoryElapsed / WesternDuelGame.victoryFrameSeconds).floor(),
          )
        : opponentFall
        ? min(5, (game._resolveSeconds * 5).floor())
        : game.opponentFired
        ? min(
            7,
            (game._opponentActionElapsed /
                    WesternDuelGame._opponentFrameSeconds)
                .floor(),
          )
        : idleFrame;
    final opponentArt = opponentCelebrating
        ? art[13]
        : opponentFall
        ? art[3]
        : game.opponentFired
        ? art[2]
        : art[1];
    final opponentFrames = opponentCelebrating
        ? WesternDuelGame.victoryFrameCount
        : opponentFall
        ? 6
        : game.opponentFired
        ? 8
        : 4;
    _image(
      canvas,
      opponentArt,
      WesternDuelGame.opponentRectForHeight(height),
      frame: opponentCelebrating
          ? opponentFrame
          : opponentFall
          ? opponentFrame
          : game.opponentFired
          ? opponentFrame
          : idleFrame,
      frames: opponentFrames,
      columns: opponentCelebrating
          ? 2
          : opponentFall
          ? 3
          : game.opponentFired
          ? 4
          : 2,
    );
    _renderStandoffAtmosphere(canvas, centerOffset);
    if (opponentCelebrating &&
        victoryElapsed >= WesternDuelGame.victorySmokeStartSeconds) {
      _image(
        canvas,
        art[14],
        Rect.fromLTWH(
          WesternDuelGame.opponentCenterX - 50,
          WesternDuelGame.opponentRectForHeight(height).top - 24,
          128,
          128,
        ),
        frame: min(
          3,
          ((victoryElapsed - WesternDuelGame.victorySmokeStartSeconds) / 0.09)
              .floor(),
        ),
        frames: 4,
      );
    }
    if (game._opponentFlash > 0) {
      _image(
        canvas,
        art[6],
        // Keep the opponent's muzzle offset relative to the shifted sprite.
        WesternDuelGame.opponentMuzzleRectForHeight(height),
        frame: _muzzleFlashFrame(game._opponentFlash),
        frames: 4,
      );
    }
    if (outcome == WesternDuelOutcome.win) {
      _image(
        canvas,
        art[8],
        WesternDuelGame.opponentHitRectForHeight(height),
        frames: 4,
      );
    }
    if (outcome == WesternDuelOutcome.lose ||
        outcome == WesternDuelOutcome.draw ||
        game._failure != null) {
      if (game._impactApplied) {
        _image(
          canvas,
          art[7],
          WesternDuelGame.opponentMissRectForHeight(height),
          frames: 4,
        );
      }
    }
    // The intact full-body atlas is deliberately placed below and left of the
    // viewport; only its first-person edge remains visible on screen.
    final playerIsFiring = game.playerFired;
    final playerFrame = playerCelebrating
        ? min(
            WesternDuelGame.victoryFrameCount - 1,
            (victoryElapsed / WesternDuelGame.victoryFrameSeconds).floor(),
          )
        : playerIsFiring
        ? WesternDuelGame.playerActionFrameForTesting(game._playerActionElapsed)
        : WesternDuelGame.playerIdleFrameForTesting(game._elapsed);
    final playerArt = playerCelebrating
        ? art[12]
        : playerIsFiring
        ? art[5]
        : art[4];
    final playerFrameCount = playerCelebrating
        ? WesternDuelGame.victoryFrameCount
        : playerIsFiring
        ? WesternDuelGame.playerActionFrameCount
        : WesternDuelGame.playerIdleFrameCount;
    final playerColumns = playerCelebrating
        ? 2
        : playerIsFiring
        ? WesternDuelGame.playerActionSheetColumns
        : WesternDuelGame.playerIdleSheetColumns;
    final playerRect = playerIsFiring
        ? WesternDuelGame.playerActionRectForHeight(height, playerFrame)
        : WesternDuelGame.playerIdleRectForHeight(
            height,
            playerFrame,
            elapsedSeconds: game._elapsed,
          );
    final playerFalling = game._playerForwardFallStarted;
    final fallBlend = playerFalling
        ? (game._playerForwardFallElapsed /
                  WesternDuelGame.playerForwardFallBlendSeconds)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;
    if (!playerFalling) {
      _image(
        canvas,
        playerArt,
        playerRect,
        frame: playerFrame,
        frames: playerFrameCount,
        columns: playerColumns,
      );
    }
    if (playerFalling) {
      final entryArt = playerIsFiring ? art[5] : art[4];
      final entryRect = game._playerForwardFallEntryRect ?? playerRect;
      if (fallBlend < 1) {
        paint.color = Color.fromARGB(
          ((1 - fallBlend) * 255).round(),
          255,
          255,
          255,
        );
        _image(
          canvas,
          entryArt,
          entryRect,
          frame: game._playerForwardFallEntryFrame,
          frames: playerIsFiring
              ? WesternDuelGame.playerActionFrameCount
              : WesternDuelGame.playerIdleFrameCount,
          columns: playerIsFiring
              ? WesternDuelGame.playerActionSheetColumns
              : WesternDuelGame.playerIdleSheetColumns,
        );
      }
      paint.color = Color.fromARGB((fallBlend * 255).round(), 255, 255, 255);
      _image(
        canvas,
        art[11],
        WesternDuelGame.playerForwardFallRectForHeight(
          height,
          game._playerForwardFallElapsed,
        ),
        frame: WesternDuelGame.playerForwardFallFrameForTesting(
          game._playerForwardFallElapsed,
        ),
        frames: WesternDuelGame.playerForwardFallFrameCount,
        columns: WesternDuelGame.playerForwardFallSheetColumns,
      );
      paint.color = Colors.white;
    }
    if (game._playerFlash > 0 && game._playerVisualFired) {
      final muzzle = WesternDuelGame.playerMuzzlePositionForHeight(
        height,
        frame: playerFrame,
      );
      _imageRotated(
        canvas,
        art[6],
        Rect.fromCenter(
          center: muzzle,
          width: WesternDuelGame.playerFlashSize,
          height: WesternDuelGame.playerFlashSize,
        ),
        rotation: WesternDuelGame.playerShotAngleForHeight(
          height,
          frame: playerFrame,
        ),
        frame: _muzzleFlashFrame(game._playerFlash),
        frames: 4,
      );
    }
    if (playerCelebrating &&
        victoryElapsed >= WesternDuelGame.victorySmokeStartSeconds) {
      _image(
        canvas,
        art[14],
        Rect.fromLTWH(58, height - 390, 128, 128),
        frame: min(
          3,
          ((victoryElapsed - WesternDuelGame.victorySmokeStartSeconds) / 0.09)
              .floor(),
        ),
        frames: 4,
      );
    }
    _label(
      canvas,
      opponent == null
          ? '상대 준비 중'
          : opponent.isBot
          ? '맥크리'
          : opponent.nickname,
      WesternDuelGame.opponentRectForHeight(height).top - 30,
      size: 16,
      color: _nameColor(opponent?.nicknameColor),
      centerX: WesternDuelGame.opponentCenterX,
    );
    if (game.phase == WesternDuelPhase.countdown) {
      _label(
        canvas,
        '${max(1, (_countdown(game)).ceil())}',
        120 + centerOffset,
        size: 48,
      );
    }
    if (game.phase == WesternDuelPhase.draw) {
      _label(
        canvas,
        'DRAW!',
        130 + centerOffset,
        size: 42,
        color: const Color(0xFFFFE040),
        centerX: WesternDuelGame.opponentCenterX,
      );
    }
    if (game.phase == WesternDuelPhase.resolve ||
        game.phase == WesternDuelPhase.finished) {
      final mine = game.reactionMilliseconds;
      _label(
        canvas,
        game._failure ??
            (outcome == WesternDuelOutcome.win
                ? '승리'
                : outcome == WesternDuelOutcome.lose
                ? '패배'
                : outcome == WesternDuelOutcome.draw
                ? '무승부'
                : '발사!'),
        120 + centerOffset,
        size: 30,
      );
      if (mine != null && opponent != null) {
        _label(
          canvas,
          '나 ${WesternDuelRules.formatMilliseconds(mine)}  /  상대 ${WesternDuelRules.formatMilliseconds(opponent.reactionMilliseconds)}',
          165 + centerOffset,
          size: 15,
        );
      }
    }
    canvas.restore();
  }

  double _countdown(WesternDuelGame game) =>
      game._countdownSeconds - game._phaseElapsed;
}
