import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_one_round/features/games/western_duel/western_duel_game.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

enum WesternDuelPreviewScene { wait, draw, result }

/// The phase shown by the animated home card.
enum WesternDuelPreviewPhase { wait, draw, result }

@immutable
class WesternDuelPreviewFrame {
  const WesternDuelPreviewFrame({
    required this.phase,
    required this.phaseElapsed,
    required this.playerFrame,
    required this.opponentFrame,
    required this.showMuzzleFlash,
  });

  final WesternDuelPreviewPhase phase;
  final double phaseElapsed;
  final int playerFrame;
  final int opponentFrame;
  final bool showMuzzleFlash;
}

class WesternDuelPreview extends StatefulWidget {
  const WesternDuelPreview({
    this.scene = WesternDuelPreviewScene.wait,
    this.animate = false,
    super.key,
  });

  static const playerAtlasAsset =
      'assets/images/western_duel/first_person/player_detail_action_v11/sheet-transparent.png';
  static const playerIdleAtlasAsset =
      'assets/images/western_duel/first_person/player_detail_idle_v11/sheet-transparent.png';
  static const opponentIdleAtlasAsset =
      'assets/images/western_duel/first_person/opponent_idle_close/sheet-transparent.png';
  static const opponentDrawAtlasAsset =
      'assets/images/western_duel/first_person/opponent_draw_fire_close/sheet-transparent.png';
  static const opponentHitAtlasAsset =
      'assets/images/western_duel/first_person/opponent_hit_fall_close/sheet-transparent.png';

  // Keep the home demonstration short enough to scan, while still showing a
  // complete wait -> signal -> result loop.
  static const double waitDurationSeconds = 2.8;
  static const double drawDurationSeconds = 0.8;
  static const double resultDurationSeconds = 1.8;
  static const double cycleDurationSeconds =
      waitDurationSeconds + drawDurationSeconds + resultDurationSeconds;

  // A very short guide slot still needs room for the name, signal, opponent,
  // and first-person muzzle. The scene is then scaled as one unit into the
  // slot, so the background and all foreground layers always agree.
  static const double logicalWidth = 360;
  static const double minimumLogicalHeight = 480;

  final WesternDuelPreviewScene scene;
  final bool animate;

  /// Returns the same state used by the home animation at a deterministic
  /// point in time. Keeping this pure makes the cycle boundary testable.
  @visibleForTesting
  static WesternDuelPreviewFrame frameForElapsed(double elapsedSeconds) {
    final elapsed = elapsedSeconds.isFinite ? math.max(0, elapsedSeconds) : 0.0;
    final cycleElapsed = elapsed % cycleDurationSeconds;
    if (cycleElapsed < waitDurationSeconds) {
      return WesternDuelPreviewFrame(
        phase: WesternDuelPreviewPhase.wait,
        phaseElapsed: cycleElapsed,
        playerFrame: WesternDuelGame.playerIdleFrameForElapsed(cycleElapsed),
        opponentFrame: (cycleElapsed / 0.75).floor() % 4,
        showMuzzleFlash: false,
      );
    }
    if (cycleElapsed < waitDurationSeconds + drawDurationSeconds) {
      final phaseElapsed = cycleElapsed - waitDurationSeconds;
      return WesternDuelPreviewFrame(
        phase: WesternDuelPreviewPhase.draw,
        phaseElapsed: phaseElapsed,
        playerFrame: WesternDuelGame.playerActionFrameForElapsed(phaseElapsed),
        opponentFrame: math.min(7, (phaseElapsed / 0.035).floor()),
        // Both shots are shown together around the player's authored firing
        // frame, so the transition into the result never looks half-reset.
        showMuzzleFlash: phaseElapsed >= 0.21 && phaseElapsed < 0.34,
      );
    }
    return WesternDuelPreviewFrame(
      phase: WesternDuelPreviewPhase.result,
      phaseElapsed: cycleElapsed - waitDurationSeconds - drawDurationSeconds,
      playerFrame: WesternDuelGame.playerActionFrameCount - 1,
      opponentFrame: 5,
      showMuzzleFlash: false,
    );
  }

  /// Calculates the logical viewport used by a physical preview slot.
  @visibleForTesting
  static double logicalHeightForSlot(Size slot) {
    if (!slot.width.isFinite || slot.width <= 0) {
      return minimumLogicalHeight;
    }
    final height = slot.height.isFinite && slot.height > 0
        ? slot.height * logicalWidth / slot.width
        : minimumLogicalHeight;
    return math.max(minimumLogicalHeight, height);
  }

  /// The whole logical scene is scaled together and top aligned. A rect taller
  /// than the slot is intentionally clipped by the preview frame.
  @visibleForTesting
  static Rect sceneRectForSlot(Size slot) {
    if (!slot.width.isFinite || slot.width <= 0) return Rect.zero;
    final scale = slot.width / logicalWidth;
    return Rect.fromLTWH(
      0,
      0,
      logicalWidth * scale,
      logicalHeightForSlot(slot) * scale,
    );
  }

  @visibleForTesting
  static Rect opponentNameRectForHeight(double height) {
    final opponent = WesternDuelGame.opponentRectForHeight(height);
    return Rect.fromLTWH(126, math.max(8, opponent.top - 29), 108, 21);
  }

  @visibleForTesting
  static Rect signalRectForHeight(double height) {
    final name = opponentNameRectForHeight(height);
    return Rect.fromLTWH(95, math.max(4, name.top - 45), 170, 37);
  }

  @visibleForTesting
  static Rect resultRectForHeight(double height) {
    final signal = signalRectForHeight(height);
    return Rect.fromLTWH(50, signal.top, 260, signal.height);
  }

  @override
  State<WesternDuelPreview> createState() => _WesternDuelPreviewState();
}

class _WesternDuelPreviewState extends State<WesternDuelPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (WesternDuelPreview.cycleDurationSeconds * 1000).round(),
      ),
    );
    if (widget.animate) _clock.repeat();
  }

  @override
  void didUpdateWidget(covariant WesternDuelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _clock.repeat();
    } else {
      _clock.stop();
      _clock.value = 0;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  double get _time {
    if (widget.animate) {
      return _clock.value * WesternDuelPreview.cycleDurationSeconds;
    }
    return switch (widget.scene) {
      WesternDuelPreviewScene.wait => 0,
      WesternDuelPreviewScene.draw =>
        WesternDuelPreview.waitDurationSeconds + 0.28,
      WesternDuelPreviewScene.result =>
        WesternDuelPreview.waitDurationSeconds +
            WesternDuelPreview.drawDurationSeconds +
            0.55,
    };
  }

  @override
  Widget build(BuildContext context) {
    final animation = widget.animate
        ? _clock
        : const AlwaysStoppedAnimation<double>(0);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.biggest;
          if (!slot.width.isFinite || !slot.height.isFinite || slot.isEmpty) {
            return const SizedBox.shrink();
          }
          final frame = WesternDuelPreview.frameForElapsed(_time);
          final logicalHeight = WesternDuelPreview.logicalHeightForSlot(slot);
          return ClipRect(
            key: const Key('western-duel-preview-clip'),
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: WesternDuelPreview.logicalWidth,
                height: logicalHeight,
                child: _WesternDuelLogicalScene(
                  height: logicalHeight,
                  frame: frame,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WesternDuelLogicalScene extends StatelessWidget {
  const _WesternDuelLogicalScene({required this.height, required this.frame});

  final double height;
  final WesternDuelPreviewFrame frame;

  String get _opponentAsset {
    final frameName = (frame.opponentFrame + 1).toString().padLeft(2, '0');
    return switch (frame.phase) {
      WesternDuelPreviewPhase.wait =>
        'assets/images/western_duel/first_person/opponent_idle_close/frame_$frameName.png',
      WesternDuelPreviewPhase.draw =>
        'assets/images/western_duel/first_person/opponent_draw_fire_close/frame_$frameName.png',
      WesternDuelPreviewPhase.result =>
        'assets/images/western_duel/first_person/opponent_hit_fall_close/frame_06.png',
    };
  }

  @override
  Widget build(BuildContext context) {
    final opponent = WesternDuelGame.opponentRectForHeight(height);
    final nameRect = WesternDuelPreview.opponentNameRectForHeight(height);
    final signalRect = WesternDuelPreview.signalRectForHeight(height);
    final resultRect = WesternDuelPreview.resultRectForHeight(height);
    final playerIsFiring = frame.phase != WesternDuelPreviewPhase.wait;
    final playerRect = playerIsFiring
        ? WesternDuelGame.playerActionRectForHeight(height, frame.playerFrame)
        : WesternDuelGame.playerIdleRectForHeight(
            height,
            frame.playerFrame,
            elapsedSeconds: frame.phaseElapsed,
          );
    final playerMuzzle = WesternDuelGame.playerMuzzlePositionForHeight(
      height,
      frame: playerIsFiring
          ? frame.playerFrame
          : WesternDuelGame.playerActionFireFrame,
    );
    final opponentMuzzle = WesternDuelGame.opponentMuzzleRectForHeight(height);

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/western_duel/background/saloon_day_180x480.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.none,
          ),
        ),
        Positioned.fromRect(
          rect: opponent,
          child: Image.asset(
            _opponentAsset,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
        ),
        Positioned.fromRect(
          rect: nameRect,
          child: _PreviewBadge(
            label: '맥크리',
            textSize: 14,
            background: const Color(0xB51B1520),
          ),
        ),
        if (frame.phase != WesternDuelPreviewPhase.wait)
          Positioned.fromRect(
            rect: frame.phase == WesternDuelPreviewPhase.result
                ? resultRect
                : signalRect,
            child: frame.phase == WesternDuelPreviewPhase.result
                ? const _PreviewResultBadge()
                : const _PreviewBadge(
                    label: 'DRAW!',
                    textSize: 28,
                    background: Color(0xD51B1520),
                    accent: Color(0xFFFFDF40),
                  ),
          ),
        Positioned.fromRect(
          rect: playerRect,
          child: _PlayerAtlasFrame(
            asset: playerIsFiring
                ? WesternDuelPreview.playerAtlasAsset
                : WesternDuelPreview.playerIdleAtlasAsset,
            frame: frame.playerFrame,
            columns: playerIsFiring
                ? WesternDuelGame.playerActionSheetColumns
                : WesternDuelGame.playerIdleSheetColumns,
            rows: playerIsFiring
                ? WesternDuelGame.playerActionSheetRows
                : WesternDuelGame.playerIdleSheetRows,
          ),
        ),
        if (frame.showMuzzleFlash) ...[
          Positioned(
            left: opponentMuzzle.center.dx - 28,
            top: opponentMuzzle.center.dy - 28,
            width: 56,
            height: 56,
            child: Image.asset(
              'assets/images/western_duel/fx/muzzle_flash/frame_04.png',
              filterQuality: FilterQuality.none,
            ),
          ),
          Positioned(
            left: playerMuzzle.dx - WesternDuelGame.playerFlashSize / 2,
            top: playerMuzzle.dy - WesternDuelGame.playerFlashSize / 2,
            width: WesternDuelGame.playerFlashSize,
            height: WesternDuelGame.playerFlashSize,
            child: Transform.rotate(
              angle: WesternDuelGame.playerShotAngleForHeight(
                height,
                frame: frame.playerFrame,
              ),
              child: Image.asset(
                'assets/images/western_duel/fx/muzzle_flash/frame_04.png',
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PreviewResultBadge extends StatelessWidget {
  const _PreviewResultBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xD51B1520),
      border: Border.all(color: const Color(0xFFFFDF40), width: 1.5),
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 5,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: WordSafeText(
            '승리 · 나0.184초 / 상대0.231초',
            maxLines: 1,
            overflow: TextOverflow.clip,
            singleLine: true,
            style: TextStyle(
              fontFamily: 'Galmuri',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFFDF40),
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({
    required this.label,
    required this.textSize,
    required this.background,
    this.accent = const Color(0xFFFFE7B0),
  });

  final String label;
  final double textSize;
  final Color background;
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: accent.withValues(alpha: 0.72), width: 1.5),
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 5,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Center(
      child: WordSafeText(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        singleLine: true,
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontSize: textSize,
          fontWeight: FontWeight.w900,
          color: accent,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
    ),
  );
}

class _PlayerAtlasFrame extends StatelessWidget {
  const _PlayerAtlasFrame({
    required this.asset,
    required this.frame,
    required this.columns,
    required this.rows,
  });

  final String asset;
  final int frame;
  final int columns;
  final int rows;

  @override
  Widget build(BuildContext context) {
    const displayFrameWidth = WesternDuelGame.playerActionDisplayWidth;
    const displayFrameHeight = WesternDuelGame.playerActionDisplayHeight;
    final column = frame % columns;
    final row = frame ~/ columns;
    final atlasWidth = displayFrameWidth * columns;
    final atlasHeight = displayFrameHeight * rows;
    return ClipRect(
      child: SizedBox(
        width: displayFrameWidth,
        height: displayFrameHeight,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: atlasWidth,
          maxWidth: atlasWidth,
          minHeight: atlasHeight,
          maxHeight: atlasHeight,
          child: Transform.translate(
            offset: Offset(
              -column * displayFrameWidth,
              -row * displayFrameHeight,
            ),
            child: Image.asset(
              asset,
              width: atlasWidth,
              height: atlasHeight,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}
