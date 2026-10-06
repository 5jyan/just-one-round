import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/lily_frog/domain/lily_frog_rules.dart';
import 'package:just_one_round/features/games/lily_frog/presentation/lily_frog_combo_gauge.dart';
import 'package:just_one_round/features/games/lily_frog/lily_frog_game.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

enum LilyFrogRuntimePreviewMode {
  home,
  orbit,
  tangent,
  speed,
  scoring,
  bonus,
  failure,
}

class LilyFrogHomePreview extends StatelessWidget {
  const LilyFrogHomePreview({super.key});

  @override
  Widget build(BuildContext context) =>
      const LilyFrogRuntimePreview(mode: LilyFrogRuntimePreviewMode.home);
}

/// A real, non-interactive LilyFrogGame used by the home card and guide.
/// Each mode drives the same runtime into a useful teaching state.
class LilyFrogRuntimePreview extends StatefulWidget {
  const LilyFrogRuntimePreview({super.key, required this.mode});

  final LilyFrogRuntimePreviewMode mode;

  @override
  State<LilyFrogRuntimePreview> createState() => _LilyFrogRuntimePreviewState();
}

class _LilyFrogRuntimePreviewState extends State<LilyFrogRuntimePreview> {
  late LilyFrogGame _game;
  Timer? _driverTimer;
  Timer? _loopTimer;
  var _generation = 0;
  var _speedConfigured = false;
  var _failureTriggered = false;
  var _driverTicks = 0;
  var _gameReady = false;

  bool get _isHome => widget.mode == LilyFrogRuntimePreviewMode.home;

  @override
  void initState() {
    super.initState();
    _game = _createGame();
    _driverTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => _driveRuntime(),
    );
    _scheduleLoop();
  }

  LilyFrogGame _createGame() => LilyFrogGame(
    countdownDuration: Duration.zero,
    random: Random(20260815 + _generation * 97 + widget.mode.index),
    enableHaptics: false,
    onFinished: (_) {},
  );

  void _scheduleLoop() {
    _loopTimer?.cancel();
    final duration = switch (widget.mode) {
      LilyFrogRuntimePreviewMode.home => const Duration(seconds: 16),
      LilyFrogRuntimePreviewMode.orbit => const Duration(seconds: 12),
      LilyFrogRuntimePreviewMode.tangent => const Duration(seconds: 20),
      LilyFrogRuntimePreviewMode.bonus => const Duration(seconds: 10),
      LilyFrogRuntimePreviewMode.failure => const Duration(seconds: 4),
      _ => const Duration(seconds: 8),
    };
    _loopTimer = Timer(duration, _replaceGame);
  }

  void _replaceGame() {
    if (!mounted) return;
    final previous = _game;
    _generation++;
    _speedConfigured = false;
    _failureTriggered = false;
    _driverTicks = 0;
    _gameReady = false;
    setState(() => _game = _createGame());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous.disposeController();
    });
    _scheduleLoop();
  }

  void _driveRuntime() {
    if (!_game.isLoaded) return;
    if (!_gameReady) {
      if (mounted) setState(() => _gameReady = true);
      return;
    }
    _driverTicks++;
    switch (widget.mode) {
      case LilyFrogRuntimePreviewMode.home:
      case LilyFrogRuntimePreviewMode.scoring:
        if (widget.mode == LilyFrogRuntimePreviewMode.home &&
            _driverTicks < 60) {
          return;
        }
        _game.launchWhenSafeForPreview();
        break;
      case LilyFrogRuntimePreviewMode.bonus:
        if (_game.currentProgressForPreview < 4) {
          _game.launchSafeImmediatelyForPreview();
        }
        break;
      case LilyFrogRuntimePreviewMode.orbit:
      case LilyFrogRuntimePreviewMode.tangent:
        // Keep the initial full field visible briefly in guide pages. Without
        // this grace period the first jump can move the camera before the
        // guide capture or a reader has seen the board.
        if (_driverTicks < 60) return;
        _game.launchWhenSafeForPreview();
        break;
      case LilyFrogRuntimePreviewMode.speed:
        if (!_speedConfigured) {
          _speedConfigured = true;
          _game.setElapsedSecondsForPreview(140);
        }
        break;
      case LilyFrogRuntimePreviewMode.failure:
        if (!_failureTriggered && _game.hud.value.elapsedSeconds >= 1) {
          _failureTriggered = _game.launchUnsafeForPreview();
        }
        break;
    }
  }

  @override
  void dispose() {
    _driverTimer?.cancel();
    _loopTimer?.cancel();
    _game.disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (_isHome) {
          final runtimeHeight = constraints.maxWidth * 640 / 360;
          return ClipRect(
            key: const Key('lily-frog-home-runtime-preview'),
            child: OverflowBox(
              alignment: const Alignment(0, 0.55),
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth,
              minHeight: runtimeHeight,
              maxHeight: runtimeHeight,
              child: _buildRuntimeSurface(
                width: constraints.maxWidth,
                height: runtimeHeight,
              ),
            ),
          );
        }

        final runtimeWidth = constraints.maxHeight * 360 / 640;
        return ColoredBox(
          key: const Key('lily-frog-guide-runtime-preview'),
          color: const Color(0xFF061B27),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: _buildRuntimeSurface(
                  width: runtimeWidth,
                  height: constraints.maxHeight,
                ),
              ),
              if (_guideCallout case final callout?)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 58,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    color: const Color(0xD9071F2C),
                    child: WordSafeText(
                      callout,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _buildRuntimeSurface({
    required double width,
    required double height,
  }) => SizedBox(
    key: Key('lily-frog-runtime-game-$_generation'),
    width: width,
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        GameWidget(game: _game),
        if (_gameReady)
          const SizedBox.shrink(key: Key('lily-frog-runtime-ready')),
        ValueListenableBuilder<MiniGameHudState>(
          key: ValueKey(_game),
          valueListenable: _game.hud,
          builder: (context, state, _) => Stack(
            fit: StackFit.expand,
            children: [
              if (_isHome)
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.backgroundDeep.withValues(alpha: 0.78),
                      border: Border.all(color: AppColors.border, width: 2),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.text,
                      size: 22,
                    ),
                  ),
                ),
              Positioned(
                left: _isHome ? 68 : 12,
                right: 12,
                top: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RuntimeHudValue(
                      label: 'SCORE',
                      value: LilyFrogRules.formatHudScore(state.score),
                      compact: !_isHome,
                    ),
                    Column(
                      children: [
                        _RuntimeHudValue(
                          label: 'COMBO',
                          value: '${state.distance}x',
                          alignCenter: true,
                          compact: !_isHome,
                        ),
                        if (state.comboRemainingPercent case final int percent)
                          LilyFrogComboGauge(
                            remainingPercent: percent,
                            combo: state.distance,
                            compact: !_isHome,
                          ),
                      ],
                    ),
                    _RuntimeHudValue(
                      label: 'TIME',
                      value:
                          '${state.remainingSeconds ?? LilyFrogRules.gameDuration.inSeconds}',
                      alignEnd: true,
                      compact: !_isHome,
                    ),
                  ],
                ),
              ),
              if (_isHome)
                if (state.message case final String message)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: 78,
                    child: WordSafeText(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Galmuri',
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.black, offset: Offset(2, 2)),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    ),
  );

  String? get _guideCallout => switch (widget.mode) {
    LilyFrogRuntimePreviewMode.orbit => '90° 접선 = 점선 방향 · 실제 점프',
    LilyFrogRuntimePreviewMode.tangent => '1 · 2 · 3회 점선 ON  →  4회부터 OFF',
    _ => null,
  };
}

class _RuntimeHudValue extends StatelessWidget {
  const _RuntimeHudValue({
    required this.label,
    required this.value,
    this.alignEnd = false,
    this.alignCenter = false,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool alignEnd;
  final bool alignCenter;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignCenter
        ? CrossAxisAlignment.center
        : alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      WordSafeText(
        label,
        style: TextStyle(
          fontFamily: 'Galmuri',
          color: const Color(0xCCFFFFFF),
          fontSize: compact ? 8 : 9,
          fontWeight: FontWeight.w900,
          letterSpacing: compact ? 0.8 : 1.2,
        ),
      ),
      const SizedBox(height: 2),
      WordSafeText(
        value,
        style: TextStyle(
          fontFamily: 'Galmuri',
          color: Colors.white,
          fontSize: compact ? 18 : 24,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Colors.black54, offset: Offset(2, 2))],
        ),
      ),
    ],
  );
}
