import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';

const gameEndTransitionDuration = Duration(milliseconds: 2100);
const gameEndResultRevealDuration = Duration(milliseconds: 520);
const gameEndTitleAlignment = Alignment(0, -0.68);

class GameEndTransition extends StatefulWidget {
  const GameEndTransition({
    required this.endType,
    required this.onCompleted,
    this.resultPanel,
    super.key,
  });

  final GameEndType endType;
  final VoidCallback onCompleted;
  final Widget? resultPanel;

  @override
  State<GameEndTransition> createState() => _GameEndTransitionState();
}

class _GameEndTransitionState extends State<GameEndTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _backdropOpacity;
  late final Animation<double> _titleArrival;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: gameEndTransitionDuration, vsync: this)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              widget.onCompleted();
            }
          });
    _backdropOpacity = Tween<double>(begin: 0, end: 0.78).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.12, curve: Curves.easeOut),
      ),
    );
    _titleArrival = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.08, 0.34, curve: Curves.elasticOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _settlingShake(double progress) {
    if (progress < 0.24 || progress > 0.48) return 0;
    final localProgress = (progress - 0.24) / 0.24;
    return math.sin(localProgress * math.pi * 6) * 4 * (1 - localProgress);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.resultPanel == null,
      child: Semantics(
        label: widget.endType.label,
        liveRegion: true,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  key: const Key('game-end-backdrop'),
                  color: AppColors.backgroundDeep.withValues(
                    alpha: _backdropOpacity.value,
                  ),
                ),
                Align(
                  alignment: gameEndTitleAlignment,
                  child: Transform.translate(
                    offset: Offset(_settlingShake(_controller.value), 0),
                    child: Transform.scale(
                      scale: 0.68 + (_titleArrival.value * 0.32),
                      child: GameEndTitle(endType: widget.endType),
                    ),
                  ),
                ),
                if (widget.resultPanel case final panel?)
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: math.max(152, constraints.maxHeight * 0.19),
                          ),
                          child: TweenAnimationBuilder<double>(
                            key: const Key('game-end-result-reveal'),
                            duration: gameEndResultRevealDuration,
                            curve: Curves.easeOutCubic,
                            tween: Tween(begin: 1, end: 0),
                            builder: (context, progress, child) {
                              return Transform.translate(
                                offset: Offset(0, 120 * progress),
                                child: Opacity(
                                  opacity: 1 - progress,
                                  child: child,
                                ),
                              );
                            },
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 360,
                                  ),
                                  child: panel,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class GameEndTitle extends StatelessWidget {
  const GameEndTitle({required this.endType, super.key});

  final GameEndType endType;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontFamily: 'Galmuri',
      fontSize: 46,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      height: 1,
    );

    return RepaintBoundary(
      key: const Key('game-end-title'),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            endType.label,
            style: baseStyle.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 8
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xFF2A1938),
            ),
          ),
          Text(
            endType.label,
            style: const TextStyle(
              fontFamily: 'Galmuri',
              color: Color(0xFFFFE7A3),
              fontSize: 46,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              height: 1,
              shadows: [Shadow(color: Color(0xFFA63F48), offset: Offset(4, 4))],
            ),
          ),
        ],
      ),
    );
  }
}
