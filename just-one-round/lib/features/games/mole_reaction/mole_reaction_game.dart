import 'dart:async' as async;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/mole_reaction/mole_reaction_hole_clip.dart';
import 'package:just_one_round/features/games/mole_reaction/domain/mole_reaction_rules.dart';

enum MoleReactionGamePhase {
  loading,
  countdown,
  waiting,
  activeTarget,
  settle,
  finished,
  timeout,
  interrupted,
}

/// Flame runtime for the fixed 2x2 mole reaction board.
class MoleReactionGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  MoleReactionGame({
    required this.onFinished,
    Duration? gameDuration,
    Duration? maxDuration,
    this.countdownDuration = MoleReactionRules.countdownDuration,
    this.attemptOrdinal = 1,
    this.challengeSeed = 0,
    this.enableHaptics = true,
    math.Random? random,
  }) : gameDuration = _capDuration(
         maxDuration ?? gameDuration ?? MoleReactionRules.sessionDeadline,
       ),
       challenge = MoleReactionRules.challengeForSeed(
         random?.nextInt(1 << 30) ?? challengeSeed,
       ),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: MoleReactionRules.sessionDeadline.inSeconds,
           countdownNumber: _initialCountdownNumber(countdownDuration),
         ),
       );

  static final logicalSize = Vector2(360, 800);
  static const double backgroundOverscanTop = 80;
  // Mole art is authored as a 256px source cell and sampled at 96px with
  // nearest-neighbor filtering so the new chunky pixel clusters stay crisp.
  static const double moleSourceCell = 256;

  // The board deliberately leaves an input-safe margin around every cell.
  static const double holeSize = 96;
  static const double holeHorizontalGap = 28;
  static const double holeVerticalGap = 36;
  // Center the 2x2 board in the 360px logical playfield with a little more
  // breathing room between cells so the board reads as one deliberate group.
  static const double boardLeft = 70;
  // Place the board below the HUD and closer to the lower half of the dirt
  // clearing. This keeps the top foliage from making the board feel cramped
  // while using the previously empty space below the holes.
  static const double boardTop = 330;

  // The sprite is authored as an upper-body mole. The final 72px seam meets
  // the first pixel of the foreground dirt rim's last opaque row; the contour
  // clip below also hides side pixels that could otherwise leak through
  // transparent rim corners on individual animation frames.
  static const double moleVisibleHeight = 72;
  static const double goldenMoleVisibleHeight = moleVisibleHeight;

  static const double _settleDurationSeconds = 0.35;
  static const double _feedbackDurationSeconds = 0.72;
  static const double _hammerDurationSeconds = 0.18;
  static const double _impactDurationSeconds = 0.42;

  final ValueChanged<GameResult> onFinished;
  final Duration gameDuration;
  final Duration countdownDuration;
  final int attemptOrdinal;
  final int challengeSeed;
  final bool enableHaptics;
  final MoleReactionChallenge challenge;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _MoleReactionScene _scene;

  MoleReactionGamePhase _phase = MoleReactionGamePhase.loading;
  var _countdownElapsed = 0.0;
  var _wallElapsed = 0.0;
  var _waitingRemaining = 0.0;
  var _waitingElapsed = 0.0;
  var _activeAge = 0.0;
  var _activeSince = 0.0;
  final Stopwatch _reactionStopwatch = Stopwatch();
  var _settleRemaining = 0.0;
  var _eventIndex = 0;
  var _resolvedEvents = 0;
  var _weightedReactionTotalMs = 0;
  var _rawReactionTotalMs = 0;
  var _totalMs = 0;
  var _invalidTapCount = 0;
  var _normalMissCount = 0;
  var _goldenMissCount = 0;
  var _goldenHitCount = 0;
  int? _goldenActualMs;
  int? _goldenWeightedMs;
  int? _preparationReactionMs;
  var _preparationMissed = false;
  var _assetsReady = false;
  var _controllerDisposed = false;
  var _hasFinished = false;
  var _resultReported = false;
  var _clearPending = false;
  var _interrupted = false;
  var _visualElapsed = 0.0;
  var _completionWallElapsed = 0.0;
  async.Timer? _clearTimer;

  String? _feedback;
  var _feedbackRemaining = 0.0;
  var _hammerHole = -1;
  var _hammerAt = double.negativeInfinity;
  MoleReactionEvent? _settledEvent;
  var _settledWasHit = false;
  int? _settledReactionMilliseconds;
  var _impactAt = double.negativeInfinity;

  @visibleForTesting
  bool get isReadyForTesting => _assetsReady;

  @visibleForTesting
  MoleReactionGamePhase get gamePhase => _phase;

  @visibleForTesting
  List<MoleReactionEvent> get eventsForTesting => challenge.events;

  @visibleForTesting
  MoleReactionEvent? get currentEventForTesting =>
      _eventIndex < challenge.length ? challenge[_eventIndex] : null;

  @visibleForTesting
  MoleReactionEvent? get activeEventForTesting =>
      _phase == MoleReactionGamePhase.activeTarget
      ? currentEventForTesting
      : null;

  @visibleForTesting
  int? get targetHoleIndexForTesting => activeEventForTesting?.holeIndex;

  @visibleForTesting
  bool get targetIsGoldenForTesting => activeEventForTesting?.isGolden == true;

  @visibleForTesting
  int get eventIndexForTesting => _eventIndex;

  @visibleForTesting
  int get resolvedEventsForTesting => _resolvedEvents;

  @visibleForTesting
  int get totalMsForTesting => _totalMs;

  @visibleForTesting
  int get rawReactionTotalMsForTesting => _rawReactionTotalMs;

  @visibleForTesting
  int get weightedReactionTotalMsForTesting => _weightedReactionTotalMs;

  @visibleForTesting
  int get invalidTapCountForTesting => _invalidTapCount;

  @visibleForTesting
  int get normalMissCountForTesting => _normalMissCount;

  @visibleForTesting
  int get goldenMissCountForTesting => _goldenMissCount;

  @visibleForTesting
  int get goldenHitCountForTesting => _goldenHitCount;

  @visibleForTesting
  int? get goldenActualMsForTesting => _goldenActualMs;

  @visibleForTesting
  int? get goldenWeightedMsForTesting => _goldenWeightedMs;

  @visibleForTesting
  int? get preparationReactionMsForTesting => _preparationReactionMs;

  @visibleForTesting
  bool get preparationMissedForTesting => _preparationMissed;

  @visibleForTesting
  bool get resultReportedForTesting => _resultReported;

  @visibleForTesting
  double get wallElapsedSecondsForTesting => _wallElapsed;

  @visibleForTesting
  double get activeAgeSecondsForTesting => _activeAge;

  @visibleForTesting
  double get waitingElapsedSecondsForTesting => _waitingElapsed;

  @visibleForTesting
  String? get feedbackForTesting => _feedback;

  @visibleForTesting
  MoleReactionSpeedTier? get feedbackTierForTesting {
    final milliseconds = _settledReactionMilliseconds;
    return milliseconds == null
        ? null
        : MoleReactionRules.speedTierForMilliseconds(milliseconds);
  }

  /// The normalized hitbox for one of the twelve holes.
  @visibleForTesting
  Rect holeRectForTesting(int holeIndex) {
    if (!MoleReactionRules.isValidHoleIndex(holeIndex)) {
      throw ArgumentError.value(holeIndex, 'holeIndex');
    }
    return _holeRect(holeIndex);
  }

  @visibleForTesting
  Vector2 holeCenterForTesting(int holeIndex) {
    final rect = holeRectForTesting(holeIndex);
    return Vector2(rect.center.dx, rect.center.dy);
  }

  @visibleForTesting
  List<Rect> get holeRectsForTesting => List<Rect>.generate(
    MoleReactionRules.holeCount,
    holeRectForTesting,
    growable: false,
  );

  /// Advances the deterministic engine clock without needing a rendered frame.
  @visibleForTesting
  void advanceTimeForTesting(Duration delta) {
    if (delta.isNegative) throw ArgumentError.value(delta, 'delta');
    _advance(delta.inMicroseconds / Duration.microsecondsPerSecond);
    _publishHud(force: true);
  }

  /// Skips the remaining countdown. This still leaves the first target in its
  /// contracted random waiting state.
  @visibleForTesting
  void forceCountdownCompleteForTesting() {
    if (_phase != MoleReactionGamePhase.countdown) return;
    _countdownElapsed = _seconds(countdownDuration);
    _startWaiting();
    _publishHud(force: true);
  }

  /// Reveals the current target immediately, preserving its generated kind and
  /// location. No target can be revealed by this method during a countdown.
  @visibleForTesting
  void forceRevealTargetForTesting() {
    if (_phase != MoleReactionGamePhase.waiting ||
        _eventIndex >= challenge.length) {
      return;
    }
    _waitingRemaining = 0;
    _activateTarget();
    _publishHud(force: true);
  }

  /// Completes the current event as a miss for deterministic boundary tests.
  @visibleForTesting
  void forceMissForTesting() {
    if (_phase != MoleReactionGamePhase.activeTarget) return;
    _resolveMiss();
    _publishHud(force: true);
  }

  /// Sends a new pointer-down to a hole. A supplied reaction duration is only
  /// a test hook; runtime input uses the high-resolution monotonic stopwatch.
  @visibleForTesting
  void tapHoleForTesting(int holeIndex, {int? reactionMilliseconds}) {
    if (!MoleReactionRules.isValidHoleIndex(holeIndex)) {
      throw ArgumentError.value(holeIndex, 'holeIndex');
    }
    if (reactionMilliseconds != null &&
        _phase == MoleReactionGamePhase.activeTarget) {
      if (reactionMilliseconds < 0) {
        throw ArgumentError.value(reactionMilliseconds, 'reactionMilliseconds');
      }
      _wallElapsed = _activeSince + reactionMilliseconds / 1000;
      _activeAge = reactionMilliseconds / 1000;
    }
    _handlePointerDown(holeIndex, reactionMilliseconds: reactionMilliseconds);
    _publishHud(force: true);
  }

  @visibleForTesting
  void tapLogicalPositionForTesting(
    Vector2 position, {
    int? reactionMilliseconds,
  }) {
    tapLogicalPosition(position, reactionMilliseconds: reactionMilliseconds);
  }

  /// Test-friendly counterpart to [onTapDown] in logical camera coordinates.
  @visibleForTesting
  void tapLogicalPosition(Vector2 position, {int? reactionMilliseconds}) {
    final holeIndex = _holeIndexAt(position);
    if (holeIndex == null) return;
    tapHoleForTesting(holeIndex, reactionMilliseconds: reactionMilliseconds);
  }

  @override
  Color backgroundColor() => const Color(0xFF754527);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _configureViewport(canvasSize);
    try {
      // The game uses one shared pixel-art normal master for the preparation
      // event and one gold palette transform for the final event.
      final normalVariantNames = <String>['01_honey'];
      final assetPaths = <String>[
        'mole_reaction/mole_reaction_background.png',
        'mole_reaction/hole_back.png',
        'mole_reaction/hole_front.png',
        for (final variant in normalVariantNames)
          'mole_reaction/high_res/$variant/idle_sheet.png',
        for (final variant in normalVariantNames)
          'mole_reaction/high_res/$variant/hurt_sheet.png',
        for (final variant in normalVariantNames)
          'mole_reaction/high_res/$variant/thumbs_up_sheet.png',
        'mole_reaction/high_res/gold_from_attached_thumb_reference/idle_sheet.png',
        'mole_reaction/high_res/gold_from_attached_thumb_reference/hurt_sheet.png',
        'mole_reaction/high_res/gold_from_attached_thumb_reference/thumbs_up_sheet.png',
        'mole_reaction/ant_crawler_sheet.png',
        'mole_reaction/worm_crawler_sheet.png',
        'mole_reaction/hammer.png',
        'mole_reaction/dirt_impact_sheet.png',
        'mole_reaction/gold_burst_sheet.png',
      ];
      final loaded = await images.loadAll(assetPaths);
      var cursor = 0;
      final background = loaded[cursor++];
      final holeBack = loaded[cursor++];
      final holeFront = loaded[cursor++];
      final moleIdle = <ui.Image>[
        for (var index = 0; index < normalVariantNames.length; index++)
          loaded[cursor++],
      ];
      final moleHurt = <ui.Image>[
        for (var index = 0; index < normalVariantNames.length; index++)
          loaded[cursor++],
      ];
      final moleThumbsUp = <ui.Image>[
        for (var index = 0; index < normalVariantNames.length; index++)
          loaded[cursor++],
      ];
      final goldIdle = loaded[cursor++];
      final goldHurt = loaded[cursor++];
      final goldThumbsUp = loaded[cursor++];
      final antCrawler = loaded[cursor++];
      final wormCrawler = loaded[cursor++];
      final hammer = loaded[cursor++];
      final dirtImpact = loaded[cursor++];
      final goldBurst = loaded[cursor++];
      _scene = _MoleReactionScene(
        game: this,
        background: background,
        holeBack: holeBack,
        holeFront: holeFront,
        moleIdle: moleIdle,
        moleHurt: moleHurt,
        moleThumbsUp: moleThumbsUp,
        goldIdle: goldIdle,
        goldHurt: goldHurt,
        goldThumbsUp: goldThumbsUp,
        antCrawler: antCrawler,
        wormCrawler: wormCrawler,
        hammer: hammer,
        dirtImpact: dirtImpact,
        goldBurst: goldBurst,
      );
      await world.add(_scene);
      _assetsReady = true;
    } catch (_) {
      _markInterrupted();
      return;
    }

    if (countdownDuration == Duration.zero) {
      _startWaiting();
    } else {
      _phase = MoleReactionGamePhase.countdown;
    }
    _publishHud(force: true);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _configureViewport(size);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_assetsReady || _controllerDisposed || _interrupted || dt <= 0) return;
    _advance(dt);
    _publishHud();
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final position = camera.viewport.globalToLocal(event.canvasPosition);
    final holeIndex = _holeIndexAt(position);
    if (holeIndex == null) return;
    _handlePointerDown(
      holeIndex,
      reactionMilliseconds: _reactionStopwatch.elapsedMicroseconds ~/ 1000,
    );
    _publishHud(force: true);
  }

  void _advance(double deltaSeconds) {
    if (deltaSeconds <= 0 || _controllerDisposed || _interrupted) return;
    var remaining = deltaSeconds;
    while (remaining > 1e-9 && !_interrupted) {
      if (_phase == MoleReactionGamePhase.finished) break;

      // A completed final event gets its short hit animation even if the
      // engine clock moves beyond the session deadline during that animation.
      if (_clearPending) {
        final step = remaining;
        _advanceClock(step);
        _settleRemaining = math.max(0, _settleRemaining - step);
        remaining = 0;
        if (_settleRemaining <= 1e-9) _emitClear();
        continue;
      }

      final deadlineSeconds = _seconds(gameDuration);
      final deadlineRemaining = deadlineSeconds - _wallElapsed;
      if (deadlineRemaining <= 1e-9) {
        _finishTimeout();
        break;
      }

      switch (_phase) {
        case MoleReactionGamePhase.loading:
          return;
        case MoleReactionGamePhase.countdown:
          final phaseRemaining =
              _seconds(countdownDuration) - _countdownElapsed;
          final step = math.min(
            remaining,
            math.min(phaseRemaining, deadlineRemaining),
          );
          if (step <= 1e-9) {
            _startWaiting();
            continue;
          }
          _advanceClock(step);
          _countdownElapsed += step;
          remaining -= step;
          if (_countdownElapsed >= _seconds(countdownDuration) - 1e-9) {
            _startWaiting();
          }
        case MoleReactionGamePhase.waiting:
          final step = math.min(
            remaining,
            math.min(_waitingRemaining, deadlineRemaining),
          );
          if (step <= 1e-9) {
            _activateTarget();
            continue;
          }
          _advanceClock(step);
          _waitingRemaining = math.max(0, _waitingRemaining - step);
          _waitingElapsed += step;
          remaining -= step;
          if (_waitingRemaining <= 1e-9) _activateTarget();
        case MoleReactionGamePhase.activeTarget:
          final targetRemaining =
              MoleReactionRules.targetActiveMilliseconds / 1000 - _activeAge;
          final step = math.min(
            remaining,
            math.min(targetRemaining, deadlineRemaining),
          );
          if (step <= 1e-9) {
            _resolveMiss();
            continue;
          }
          _advanceClock(step);
          _activeAge += step;
          remaining -= step;
          if (_activeAge >=
              MoleReactionRules.targetActiveMilliseconds / 1000 - 1e-9) {
            _resolveMiss();
          }
        case MoleReactionGamePhase.settle:
          final step = math.min(
            remaining,
            math.min(_settleRemaining, deadlineRemaining),
          );
          if (step <= 1e-9) {
            _finishTimeout();
            continue;
          }
          _advanceClock(step);
          _settleRemaining = math.max(0, _settleRemaining - step);
          remaining -= step;
          if (_settleRemaining <= 1e-9) _startNextAfterSettle();
        case MoleReactionGamePhase.finished:
        case MoleReactionGamePhase.timeout:
        case MoleReactionGamePhase.interrupted:
          return;
      }
    }
  }

  void _advanceClock(double seconds) {
    _wallElapsed += seconds;
    _visualElapsed += seconds;
    _feedbackRemaining = math.max(0, _feedbackRemaining - seconds);
  }

  void _startWaiting() {
    if (_hasFinished || _interrupted || _eventIndex >= challenge.length) return;
    if (_phase == MoleReactionGamePhase.countdown) {
      _countdownElapsed = _seconds(countdownDuration);
    }
    final event = challenge[_eventIndex];
    _phase = MoleReactionGamePhase.waiting;
    _waitingRemaining = event.waitSeconds.toDouble();
    _waitingElapsed = 0;
    _activeAge = 0;
    _feedback = event.isPreparation
        ? MoleReactionRules.preparationPrompt
        : MoleReactionRules.realPrompt;
    // Keep the title visible through the wait and the following reveal. A
    // hit/miss replaces it with the reaction result as soon as the player
    // resolves the target.
    _feedbackRemaining =
        _waitingRemaining + MoleReactionRules.targetActiveMilliseconds / 1000;
  }

  void _activateTarget() {
    if (_hasFinished || _interrupted || _eventIndex >= challenge.length) return;
    final event = challenge[_eventIndex];
    _phase = MoleReactionGamePhase.activeTarget;
    _activeAge = 0;
    _activeSince = _wallElapsed;
    _waitingRemaining = 0;
    _waitingElapsed = 0;
    _feedback = event.isPreparation
        ? MoleReactionRules.preparationPrompt
        : MoleReactionRules.realPrompt;
    _feedbackRemaining = MoleReactionRules.targetActiveMilliseconds / 1000;
    _reactionStopwatch
      ..reset()
      ..start();
  }

  void _handlePointerDown(int holeIndex, {int? reactionMilliseconds}) {
    if (_controllerDisposed || _interrupted) return;
    switch (_phase) {
      case MoleReactionGamePhase.loading:
      case MoleReactionGamePhase.countdown:
      case MoleReactionGamePhase.finished:
      case MoleReactionGamePhase.timeout:
      case MoleReactionGamePhase.interrupted:
        return;
      case MoleReactionGamePhase.waiting:
        _registerInvalidTap(
          practice:
              _eventIndex < challenge.length &&
              challenge[_eventIndex].isPreparation,
        );
      case MoleReactionGamePhase.settle:
        _registerInvalidTap(practice: _settledEvent?.isPreparation == true);
      case MoleReactionGamePhase.activeTarget:
        final event = challenge[_eventIndex];
        final ageMilliseconds =
            reactionMilliseconds ??
            _reactionStopwatch.elapsedMicroseconds ~/ 1000;
        if (ageMilliseconds > MoleReactionRules.targetActiveMilliseconds) {
          _resolveMiss();
          return;
        }
        if (ageMilliseconds < 0) return;
        if (holeIndex != event.holeIndex) {
          _registerInvalidTap(practice: event.isPreparation);
          return;
        }
        _resolveHit(event, ageMilliseconds);
    }
  }

  void _registerInvalidTap({required bool practice}) {
    if (practice) {
      _feedback = '준비판은 기록에 포함되지 않아요';
      _feedbackRemaining = _feedbackDurationSeconds;
      if (enableHaptics) async.unawaited(HapticFeedback.lightImpact());
      return;
    }
    _invalidTapCount++;
    _totalMs += MoleReactionRules.invalidTapPenaltyMilliseconds;
    _feedback = '빈 구멍  +${MoleReactionRules.invalidTapPenaltyMilliseconds}ms';
    _feedbackRemaining = _feedbackDurationSeconds;
    if (enableHaptics) async.unawaited(HapticFeedback.lightImpact());
  }

  void _resolveHit(MoleReactionEvent event, int rawReactionMilliseconds) {
    if (_phase != MoleReactionGamePhase.activeTarget) return;
    _reactionStopwatch.stop();
    final reactionMilliseconds = MoleReactionRules.quantizeReactionMilliseconds(
      rawReactionMilliseconds,
    );
    if (event.isPreparation) {
      _preparationReactionMs = reactionMilliseconds;
      _feedback = '준비  ${reactionMilliseconds}ms';
      _feedbackRemaining = _feedbackDurationSeconds;
      _hammerHole = event.holeIndex;
      _hammerAt = _visualElapsed;
      _impactAt = _visualElapsed;
      _settledEvent = event;
      _settledWasHit = true;
      _settledReactionMilliseconds = reactionMilliseconds;
      _resolveEvent();
      if (enableHaptics) async.unawaited(HapticFeedback.lightImpact());
      return;
    }
    final weighted = MoleReactionRules.weightedReactionMilliseconds(
      reactionMilliseconds: reactionMilliseconds,
      golden: event.isGolden,
    );
    _rawReactionTotalMs += reactionMilliseconds;
    _weightedReactionTotalMs += weighted;
    _totalMs += weighted;
    if (event.isGolden) {
      _goldenHitCount++;
      _goldenActualMs = reactionMilliseconds;
      _goldenWeightedMs = weighted;
      _feedback = '황금!  ${reactionMilliseconds}ms ×2 = ${weighted}ms';
    } else {
      _feedback = '반응  ${reactionMilliseconds}ms';
    }
    _feedbackRemaining = _feedbackDurationSeconds;
    _hammerHole = event.holeIndex;
    _hammerAt = _visualElapsed;
    _impactAt = _visualElapsed;
    _settledEvent = event;
    _settledWasHit = true;
    _settledReactionMilliseconds = reactionMilliseconds;
    _resolveEvent();
    if (enableHaptics) {
      final tier = MoleReactionRules.speedTierForMilliseconds(
        reactionMilliseconds,
      );
      async.unawaited(
        event.isGolden || tier == MoleReactionSpeedTier.perfect
            ? HapticFeedback.heavyImpact()
            : tier == MoleReactionSpeedTier.lightning
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.lightImpact(),
      );
      if (tier == MoleReactionSpeedTier.perfect) {
        async.unawaited(HapticFeedback.selectionClick());
      }
    }
  }

  void _resolveMiss() {
    if (_phase != MoleReactionGamePhase.activeTarget ||
        _eventIndex >= challenge.length) {
      return;
    }
    _reactionStopwatch.stop();
    final event = challenge[_eventIndex];
    if (event.isPreparation) {
      _preparationMissed = true;
      _feedback = '준비판 놓침 · 진짜 기록은 다음 한 번';
      _feedbackRemaining = _feedbackDurationSeconds;
      _impactAt = _visualElapsed;
      _settledEvent = event;
      _settledWasHit = false;
      _settledReactionMilliseconds = null;
      _resolveEvent();
      if (enableHaptics) async.unawaited(HapticFeedback.lightImpact());
      return;
    }
    final penalty = MoleReactionRules.missPenalty(golden: event.isGolden);
    _totalMs += penalty;
    if (event.isGolden) {
      _goldenMissCount++;
      _feedback = '황금 놓침  +${penalty}ms';
    } else {
      _normalMissCount++;
      _feedback = '놓침  +${penalty}ms';
    }
    _feedbackRemaining = _feedbackDurationSeconds;
    _impactAt = _visualElapsed;
    _settledEvent = event;
    _settledWasHit = false;
    _settledReactionMilliseconds = null;
    _resolveEvent();
    if (enableHaptics) async.unawaited(HapticFeedback.lightImpact());
  }

  void _resolveEvent() {
    _resolvedEvents++;
    _eventIndex++;
    _phase = MoleReactionGamePhase.settle;
    _settleRemaining = _settleDurationSeconds;
    if (_eventIndex >= challenge.length) {
      _clearPending = true;
      _hasFinished = true;
      _completionWallElapsed = _wallElapsed;
      _clearTimer?.cancel();
      _clearTimer = async.Timer(const Duration(milliseconds: 350), _emitClear);
    }
  }

  void _startNextAfterSettle() {
    if (_clearPending || _hasFinished || _interrupted) return;
    if (_eventIndex >= challenge.length) {
      _emitClear();
      return;
    }
    _startWaiting();
  }

  void _finishTimeout() {
    if (_hasFinished || _interrupted || _resultReported) return;
    _hasFinished = true;
    _phase = MoleReactionGamePhase.timeout;
    _reactionStopwatch.stop();
    _wallElapsed = math.min(_wallElapsed, _seconds(gameDuration));
    _feedback = '시간 초과';
    _feedbackRemaining = _feedbackDurationSeconds;
    _publishHud(force: true);
    if (enableHaptics) async.unawaited(HapticFeedback.mediumImpact());
    _reportResult(
      GameResult(
        score: MoleReactionRules.timeoutRankingScore,
        // This game has no collectible stars; golden feedback is represented
        // by the weighted reaction time and must not alter the generic field.
        starsCollected: 0,
        collisions: _invalidTapCount + _normalMissCount + _goldenMissCount + 1,
        duration: Duration(
          milliseconds: math.max(1, (_wallElapsed * 1000).round()),
        ),
        endType: GameEndType.timeUp,
      ),
    );
  }

  void _emitClear() {
    if (!_clearPending ||
        _resultReported ||
        _controllerDisposed ||
        _interrupted) {
      return;
    }
    _clearPending = false;
    _phase = MoleReactionGamePhase.finished;
    _hasFinished = true;
    _clearTimer?.cancel();
    _clearTimer = null;
    final total = _totalMs;
    int score;
    try {
      score = MoleReactionRules.rankingScoreForTotal(total);
    } on ArgumentError {
      // A malformed total should never be submitted as a fake ranked score.
      _phase = MoleReactionGamePhase.timeout;
      _reportResult(
        GameResult(
          score: MoleReactionRules.timeoutRankingScore,
          starsCollected: 0,
          collisions:
              _invalidTapCount + _normalMissCount + _goldenMissCount + 1,
          duration: Duration(
            milliseconds: math.max(1, (_completionWallElapsed * 1000).round()),
          ),
          endType: GameEndType.timeUp,
        ),
      );
      return;
    }
    _feedback = '기록 확정  ${MoleReactionRules.formatTotalMs(total)}';
    _feedbackRemaining = _feedbackDurationSeconds;
    _publishHud(force: true);
    _reportResult(
      GameResult(
        score: score,
        starsCollected: 0,
        collisions: _invalidTapCount + _normalMissCount + _goldenMissCount,
        duration: Duration(
          milliseconds: math.max(1, (_completionWallElapsed * 1000).round()),
        ),
        endType: GameEndType.clear,
      ),
    );
  }

  void _reportResult(GameResult result) {
    if (_resultReported || _controllerDisposed || _interrupted) return;
    _resultReported = true;
    pauseEngine();
    onFinished(result);
  }

  void _markInterrupted() {
    if (_interrupted || _resultReported) return;
    _interrupted = true;
    _hasFinished = true;
    _clearPending = false;
    _clearTimer?.cancel();
    _clearTimer = null;
    _phase = MoleReactionGamePhase.interrupted;
    _reactionStopwatch.stop();
    _publishHud(force: true);
    pauseEngine();
  }

  @override
  void interrupt() {
    if (_hasFinished || _interrupted || _resultReported) return;
    _markInterrupted();
  }

  @override
  void disposeController() {
    if (_controllerDisposed) return;
    _controllerDisposed = true;
    _hasFinished = true;
    _interrupted = true;
    _clearPending = false;
    _clearTimer?.cancel();
    _clearTimer = null;
    _reactionStopwatch.stop();
    pauseEngine();
    hud.dispose();
  }

  void _publishHud({bool force = false}) {
    if (_controllerDisposed) return;
    final countdownNumber = _countdownNumber;
    final next = _hudPhase;
    final remaining = math.max(
      0,
      (_seconds(gameDuration) - _wallElapsed).ceil(),
    );
    final message = _feedbackRemaining > 0 ? _feedback : null;
    final nextState = MiniGameHudState(
      phase: next,
      score: _totalMs,
      elapsedSeconds: _wallElapsed.floor(),
      remainingSeconds: remaining,
      countdownNumber: countdownNumber,
      distance: _resolvedEvents,
      message: message,
    );
    if (!force && _sameHudState(hud.value, nextState)) return;
    hud.value = nextState;
  }

  bool _sameHudState(MiniGameHudState a, MiniGameHudState b) =>
      a.phase == b.phase &&
      a.score == b.score &&
      a.elapsedSeconds == b.elapsedSeconds &&
      a.remainingSeconds == b.remainingSeconds &&
      a.countdownNumber == b.countdownNumber &&
      a.distance == b.distance &&
      a.message == b.message;

  MiniGamePhase get _hudPhase => switch (_phase) {
    MoleReactionGamePhase.loading ||
    MoleReactionGamePhase.countdown => MiniGamePhase.countdown,
    MoleReactionGamePhase.finished ||
    MoleReactionGamePhase.timeout ||
    MoleReactionGamePhase.interrupted => MiniGamePhase.finished,
    MoleReactionGamePhase.waiting ||
    MoleReactionGamePhase.activeTarget ||
    MoleReactionGamePhase.settle => MiniGamePhase.playing,
  };

  int get _countdownNumber {
    if (_phase != MoleReactionGamePhase.countdown) return 0;
    final seconds = math.max(
      0,
      (_seconds(countdownDuration) - _countdownElapsed).ceil(),
    );
    return math.min(seconds, countdownDuration.inSeconds);
  }

  void _configureViewport(Vector2 canvasSize) {
    camera.viewport = FixedResolutionViewport(resolution: logicalSize.clone());
    camera.viewfinder.position = logicalSize / 2;
  }

  MoleReactionEvent? get _renderEvent {
    if (_phase == MoleReactionGamePhase.activeTarget) {
      return currentEventForTesting;
    }
    if (_phase == MoleReactionGamePhase.settle) return _settledEvent;
    return null;
  }

  bool get _renderWasHit => _settledWasHit;

  MoleReactionSpeedTier? get _settledSpeedTier {
    final milliseconds = _settledReactionMilliseconds;
    return milliseconds == null
        ? null
        : MoleReactionRules.speedTierForMilliseconds(milliseconds);
  }

  double get _settledImpactDuration => switch (_settledSpeedTier) {
    MoleReactionSpeedTier.perfect => 0.78,
    MoleReactionSpeedTier.lightning => 0.66,
    MoleReactionSpeedTier.great => 0.56,
    MoleReactionSpeedTier.steady => 0.48,
    MoleReactionSpeedTier.late => 0.42,
    null => _impactDurationSeconds,
  };

  Offset get _impactShakeOffset {
    if (!_settledWasHit || _impactAt.isInfinite) return Offset.zero;
    final age = _visualElapsed - _impactAt;
    if (age < 0 || age >= 0.24) return Offset.zero;
    final strength = switch (_settledSpeedTier) {
      MoleReactionSpeedTier.perfect => 7.0,
      MoleReactionSpeedTier.lightning => 5.5,
      MoleReactionSpeedTier.great => 4.0,
      MoleReactionSpeedTier.steady => 2.7,
      MoleReactionSpeedTier.late => 1.5,
      null => 0.0,
    };
    final envelope = math.pow(1 - age / 0.24, 0.7).toDouble();
    return Offset(
      math.sin(age * math.pi * 54) * strength * envelope,
      math.cos(age * math.pi * 43) * strength * 0.55 * envelope,
    );
  }

  double get _renderEventAge => _phase == MoleReactionGamePhase.activeTarget
      ? _activeAge
      : _settledEvent == null
      ? 0
      : _settleDurationSeconds - _settleRemaining;

  int _renderMoleFrame(MoleReactionEvent event) {
    if (_phase == MoleReactionGamePhase.activeTarget) {
      return ((_visualElapsed * 4).floor()) % 4;
    }
    final elapsed = _renderEventAge;
    if (!_settledWasHit) return math.min(3, (elapsed * 9).floor());
    if (event.isGolden && elapsed >= 0.15) {
      return math.min(3, ((elapsed - 0.15) * 9).floor());
    }
    return math.min(3, (elapsed * 11).floor());
  }

  String _moleSheetName(MoleReactionEvent event) {
    if (_phase == MoleReactionGamePhase.activeTarget) {
      return event.isGolden ? 'goldIdle' : 'idle';
    }
    if (event.isGolden && _settledWasHit && _renderEventAge >= 0.15) {
      return 'goldThumbsUp';
    }
    if (event.isGolden) return 'goldHurt';
    if (_settledWasHit && _renderEventAge >= 0.15) return 'thumbsUp';
    return 'hurt';
  }

  static int _initialCountdownNumber(Duration duration) {
    if (duration == Duration.zero) return 0;
    return math.min(duration.inSeconds, math.max(0, duration.inSeconds));
  }

  static double _seconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;

  static Duration _capDuration(Duration duration) {
    if (duration.isNegative) return Duration.zero;
    if (duration > MoleReactionRules.sessionDeadline) {
      return MoleReactionRules.sessionDeadline;
    }
    return duration;
  }

  static Rect _holeRect(int holeIndex) {
    final row = holeIndex ~/ MoleReactionRules.columnCount;
    final column = holeIndex % MoleReactionRules.columnCount;
    return Rect.fromLTWH(
      boardLeft + column * (holeSize + holeHorizontalGap),
      boardTop + row * (holeSize + holeVerticalGap),
      holeSize,
      holeSize,
    );
  }

  static int? _holeIndexAt(Vector2 point) {
    for (var index = 0; index < MoleReactionRules.holeCount; index++) {
      if (_holeRect(index).contains(Offset(point.x, point.y))) return index;
    }
    return null;
  }
}

class _MoleReactionScene extends PositionComponent {
  _MoleReactionScene({
    required this.game,
    required this.background,
    required this.holeBack,
    required this.holeFront,
    required this.moleIdle,
    required this.moleHurt,
    required this.moleThumbsUp,
    required this.goldIdle,
    required this.goldHurt,
    required this.goldThumbsUp,
    required this.antCrawler,
    required this.wormCrawler,
    required this.hammer,
    required this.dirtImpact,
    required this.goldBurst,
  }) : super(size: MoleReactionGame.logicalSize, priority: -10);

  final MoleReactionGame game;
  final ui.Image background;
  final ui.Image holeBack;
  final ui.Image holeFront;
  final List<ui.Image> moleIdle;
  final List<ui.Image> moleHurt;
  final List<ui.Image> moleThumbsUp;
  final ui.Image goldIdle;
  final ui.Image goldHurt;
  final ui.Image goldThumbsUp;
  final ui.Image antCrawler;
  final ui.Image wormCrawler;
  final ui.Image hammer;
  final ui.Image dirtImpact;
  final ui.Image goldBurst;

  final Paint _paint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  final Paint _molePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  final Paint _goldMolePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  final Paint _antPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  final Paint _wormPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none
    // Keep the worm as a quiet background cue: muted tint and lower alpha
    // prevent it from competing with the mole and reaction HUD.
    ..color = const Color(0xC8D7C2AE);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, 360, 800));
    final shake = game._impactShakeOffset;
    canvas.translate(shake.dx, shake.dy);
    _drawBackground(canvas);
    for (var index = 0; index < MoleReactionRules.holeCount; index++) {
      _drawCellAsset(canvas, holeBack, MoleReactionGame._holeRect(index));
    }
    _drawMole(canvas);
    for (var index = 0; index < MoleReactionRules.holeCount; index++) {
      _drawCellAsset(canvas, holeFront, MoleReactionGame._holeRect(index));
    }
    _drawAmbientCrawlers(canvas);
    _drawImpact(canvas);
    _drawHammer(canvas);
    canvas.restore();
  }

  void _drawBackground(Canvas canvas) {
    canvas.drawImageRect(
      background,
      Rect.fromLTWH(
        0,
        0,
        background.width.toDouble(),
        background.height.toDouble(),
      ),
      Rect.fromLTWH(0, -MoleReactionGame.backgroundOverscanTop, 360, 960),
      _paint,
    );
  }

  void _drawCellAsset(Canvas canvas, ui.Image image, Rect destination) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      _paint,
    );
  }

  void _drawMole(Canvas canvas) {
    final event = game._renderEvent;
    if (event == null) return;
    final rect = MoleReactionGame._holeRect(event.holeIndex);
    final frame = game._renderMoleFrame(event).clamp(0, 3);
    final sheetName = game._moleSheetName(event);
    final normalVariant = event.index
        .clamp(0, MoleReactionRules.normalMoleColorVariantCount - 1)
        .toInt();
    final image = switch (sheetName) {
      'goldIdle' => goldIdle,
      'goldHurt' => goldHurt,
      'goldThumbsUp' => goldThumbsUp,
      'thumbsUp' => moleThumbsUp[normalVariant],
      'idle' => moleIdle[normalVariant],
      _ => moleHurt[normalVariant],
    };
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width,
        event.isGolden
            ? MoleReactionGame.goldenMoleVisibleHeight
            : MoleReactionGame.moleVisibleHeight,
      ),
    );
    canvas.clipPath(moleReactionMoleClipPath(rect), doAntiAlias: false);
    _drawSheetFrame(
      canvas,
      image,
      frame,
      MoleReactionGame.moleSourceCell,
      rect,
      paint: event.isGolden ? _goldMolePaint : _molePaint,
    );
    canvas.restore();
  }

  /// Ambient crawlers live on clear dirt lanes and never participate in hit
  /// testing. They continue through waiting, target, and settle phases so the
  /// ant does not pop out exactly when a mole appears. Their lanes stay above
  /// and below the 2x2 board, keeping every tap target visually unambiguous.
  void _drawAmbientCrawlers(Canvas canvas) {
    if (!_isAmbientPhase) return;
    _drawAntCrawler(canvas);
    _drawWormCrawler(canvas);
  }

  bool get _isAmbientPhase => switch (game._phase) {
    MoleReactionGamePhase.waiting ||
    MoleReactionGamePhase.activeTarget ||
    MoleReactionGamePhase.settle => true,
    _ => false,
  };

  void _drawAntCrawler(Canvas canvas) {
    const spriteSize = 32.0;
    const laneLeft = 28.0;
    const laneWidth = 272.0;
    const laneTop = 588.0;
    final elapsed = game._visualElapsed;
    final cycle = (elapsed / 4.2) % 2;
    final movingForward = cycle <= 1;
    final travel = movingForward ? cycle : 2 - cycle;
    final x = laneLeft + travel * laneWidth;
    final y = laneTop + math.sin(elapsed * 2.3) * 1.5;
    final frame = (elapsed * 8).floor() % 4;
    final source = Rect.fromLTWH(frame * spriteSize, 0, spriteSize, spriteSize);
    final destination = Rect.fromLTWH(x, y, spriteSize, spriteSize);

    canvas.save();
    if (!movingForward) {
      canvas.translate(destination.right, destination.top);
      canvas.scale(-1, 1);
      canvas.drawImageRect(
        antCrawler,
        source,
        Rect.fromLTWH(0, 0, spriteSize, spriteSize),
        _antPaint,
      );
    } else {
      canvas.drawImageRect(antCrawler, source, destination, _antPaint);
    }
    canvas.restore();
  }

  void _drawWormCrawler(Canvas canvas) {
    const sourceCellWidth = 96.0;
    const sourceCellHeight = 48.0;
    const displayWidth = 64.0;
    const displayHeight = 32.0;
    const laneLeft = 24.0;
    const laneWidth = 272.0;
    const laneTop = 244.0;
    final elapsed = game._visualElapsed;
    // The upper crawler is intentionally slow: it gives the long wait a
    // gentle moving focal point without competing with the mole reaction.
    final cycle = (elapsed / 15.0) % 2;
    final movingForward = cycle <= 1;
    final travel = movingForward ? cycle : 2 - cycle;
    final x = laneLeft + travel * laneWidth;
    final y = laneTop + math.sin(elapsed * 0.8) * 1.0;
    final frame = (elapsed * 6.5).floor() % 6;
    final source = Rect.fromLTWH(
      frame * sourceCellWidth,
      0,
      sourceCellWidth,
      sourceCellHeight,
    );
    final destination = Rect.fromLTWH(x, y, displayWidth, displayHeight);

    canvas.save();
    if (!movingForward) {
      canvas.translate(destination.right, destination.top);
      canvas.scale(-1, 1);
      canvas.drawImageRect(
        wormCrawler,
        source,
        Rect.fromLTWH(0, 0, displayWidth, displayHeight),
        _wormPaint,
      );
    } else {
      canvas.drawImageRect(wormCrawler, source, destination, _wormPaint);
    }
    canvas.restore();
  }

  void _drawImpact(Canvas canvas) {
    if (game._impactAt.isInfinite) return;
    final age = game._visualElapsed - game._impactAt;
    final event = game._settledEvent;
    if (event == null) return;
    final tier = game._settledSpeedTier;
    final duration = game._settledImpactDuration;
    if (age < 0 || age >= duration) return;
    final progress = (age / duration).clamp(0.0, 1.0);
    final frame = math.min(3, (progress * 4).floor());
    final rect = MoleReactionGame._holeRect(event.holeIndex);
    if (event.isGolden && game._renderWasHit) {
      _drawSheetFrame(canvas, goldBurst, frame, 32, rect.inflate(16));
    } else {
      _drawSheetFrame(canvas, dirtImpact, frame, 32, rect.inflate(16));
    }
    if (game._renderWasHit && tier != null) {
      _drawReactionBurst(canvas, rect, progress, tier, golden: event.isGolden);
    }
  }

  void _drawReactionBurst(
    Canvas canvas,
    Rect rect,
    double progress,
    MoleReactionSpeedTier tier, {
    required bool golden,
  }) {
    final intensity = switch (tier) {
      MoleReactionSpeedTier.perfect => 1.3,
      MoleReactionSpeedTier.lightning => 1.12,
      MoleReactionSpeedTier.great => 0.96,
      MoleReactionSpeedTier.steady => 0.82,
      MoleReactionSpeedTier.late => 0.66,
    };
    final fade = (1 - progress).clamp(0.0, 1.0);
    final center = Offset(rect.center.dx, rect.top + rect.height * 0.48);
    final accent = golden
        ? const Color(0xFFFFD35A)
        : switch (tier) {
            MoleReactionSpeedTier.perfect => const Color(0xFFFFF0A6),
            MoleReactionSpeedTier.lightning => const Color(0xFF87F5E5),
            MoleReactionSpeedTier.great => const Color(0xFF9CD7FF),
            MoleReactionSpeedTier.steady => const Color(0xFFD8C1FF),
            MoleReactionSpeedTier.late => const Color(0xFFFFB36B),
          };
    final flashStrength = switch (tier) {
      MoleReactionSpeedTier.perfect => 0.2,
      MoleReactionSpeedTier.lightning => 0.15,
      MoleReactionSpeedTier.great => 0.1,
      MoleReactionSpeedTier.steady => 0.07,
      MoleReactionSpeedTier.late => 0.04,
    };
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 360, 800),
      Paint()..color = accent.withValues(alpha: flashStrength * fade),
    );

    final ringCount = switch (tier) {
      MoleReactionSpeedTier.perfect => 3,
      MoleReactionSpeedTier.lightning => 3,
      MoleReactionSpeedTier.great => 2,
      MoleReactionSpeedTier.steady => 2,
      MoleReactionSpeedTier.late => 1,
    };
    for (var ring = 0; ring < ringCount; ring++) {
      final ringProgress = (progress + ring * 0.13).clamp(0.0, 1.0);
      final ringFade = ((1 - ringProgress) * fade).clamp(0.0, 1.0);
      final radius = 20 + ringProgress * (54 * intensity) + ring * 8;
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + intensity * 2.2 - ring * 0.35
        ..color = accent.withValues(alpha: (0.9 * ringFade).clamp(0.0, 1.0));
      canvas.drawCircle(center, radius, ringPaint);
    }

    final rayCount = switch (tier) {
      MoleReactionSpeedTier.perfect => 16,
      MoleReactionSpeedTier.lightning => 13,
      MoleReactionSpeedTier.great => 10,
      MoleReactionSpeedTier.steady => 8,
      MoleReactionSpeedTier.late => 6,
    };
    final rayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 + intensity * 1.8
      ..color = accent.withValues(alpha: (0.68 * fade).clamp(0.0, 1.0));
    final rotation = progress * math.pi * 0.8;
    for (var index = 0; index < rayCount; index++) {
      final angle = rotation + (math.pi * 2 * index / rayCount);
      final direction = Offset(math.cos(angle), math.sin(angle));
      final rayStart = 16 + progress * 34;
      final rayEnd = 45 + progress * (42 * intensity);
      final start = center + direction * rayStart;
      final end = center + direction * rayEnd;
      canvas.drawLine(start, end, rayPaint);
    }

    final corePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = accent.withValues(alpha: (0.36 * fade).clamp(0.0, 1.0));
    canvas.drawCircle(center, 7 + intensity * 5, corePaint);

    final particleCount = switch (tier) {
      MoleReactionSpeedTier.perfect => 24,
      MoleReactionSpeedTier.lightning => 19,
      MoleReactionSpeedTier.great => 14,
      MoleReactionSpeedTier.steady => 10,
      MoleReactionSpeedTier.late => 7,
    };
    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < particleCount; index++) {
      final angle = (math.pi * 2 * index / particleCount) + rotation * 0.42;
      final wobble = 0.82 + ((index * 17) % 7) / 20;
      final distance = (28 + progress * (70 * intensity)) * wobble;
      final particle =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final size = (1.5 + ((index * 11) % 4) * 0.7) * (1 - progress * 0.25);
      particlePaint.color = (index.isEven ? accent : const Color(0xFFFFF4C2))
          .withValues(alpha: (0.88 * fade).clamp(0.0, 1.0));
      canvas.drawRect(
        Rect.fromCenter(center: particle, width: size * 2, height: size * 2),
        particlePaint,
      );
    }

    if (tier == MoleReactionSpeedTier.perfect) {
      final sparklePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = accent.withValues(alpha: (0.9 * fade).clamp(0.0, 1.0));
      for (var index = 0; index < 8; index++) {
        final angle = rotation * 0.7 + (math.pi / 4 * index);
        final position =
            center +
            Offset(math.cos(angle), math.sin(angle)) * (48 + progress * 45);
        final size = 4.5 + fade * 3.5;
        final diamond = Path()
          ..moveTo(position.dx, position.dy - size)
          ..lineTo(position.dx + size * 0.55, position.dy)
          ..lineTo(position.dx, position.dy + size)
          ..lineTo(position.dx - size * 0.55, position.dy)
          ..close();
        canvas.drawPath(diamond, sparklePaint);
      }
    }
  }

  void _drawHammer(Canvas canvas) {
    if (game._hammerHole < 0) return;
    final age = game._visualElapsed - game._hammerAt;
    if (age < 0 || age >= MoleReactionGame._hammerDurationSeconds) return;
    final hole = MoleReactionGame._holeRect(game._hammerHole);
    final hammerScale = switch (game._settledSpeedTier) {
      MoleReactionSpeedTier.perfect => 13.0,
      MoleReactionSpeedTier.lightning => 11.0,
      MoleReactionSpeedTier.great => 9.0,
      MoleReactionSpeedTier.steady => 8.0,
      MoleReactionSpeedTier.late => 7.0,
      null => 8.0,
    };
    final offset = Offset(
      math.sin(age * math.pi * 9) * (3 + hammerScale * 0.25),
      -age * (8 + hammerScale * 0.35),
    );
    final destination = hole.shift(offset).inflate(hammerScale);
    _drawCellAsset(canvas, hammer, destination);
  }

  void _drawSheetFrame(
    Canvas canvas,
    ui.Image image,
    int frame,
    double sourceCell,
    Rect destination, {
    Paint? paint,
  }) {
    final normalized = frame % 4;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(
        (normalized % 2) * sourceCell,
        (normalized ~/ 2) * sourceCell,
        sourceCell,
        sourceCell,
      ),
      destination,
      paint ?? _paint,
    );
  }
}
