import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/app/theme/app_colors.dart';

typedef StartupImpact = Future<void> Function();

class StartupIntro extends StatefulWidget {
  const StartupIntro({
    required this.child,
    this.ready = true,
    this.duration = const Duration(milliseconds: 920),
    this.firstImpact,
    this.secondImpact,
    this.reduceMotion,
    super.key,
  });

  final Widget child;
  final bool ready;
  final Duration duration;
  final StartupImpact? firstImpact;
  final StartupImpact? secondImpact;
  final bool? reduceMotion;

  @override
  State<StartupIntro> createState() => _StartupIntroState();
}

class _StartupIntroState extends State<StartupIntro>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_handleStatus);
  late final AnimationController _loadingController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 660),
  );

  final List<Timer> _timers = [];
  bool _started = false;
  bool _animationComplete = false;
  bool _showIntro = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (widget.reduceMotion ?? MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0.99;
      _timers.add(
        Timer(const Duration(milliseconds: 260), _markAnimationComplete),
      );
      return;
    }

    unawaited(_controller.forward());
    _scheduleImpact(
      const Duration(milliseconds: 80),
      widget.firstImpact ?? HapticFeedback.heavyImpact,
    );
    _scheduleImpact(
      const Duration(milliseconds: 730),
      widget.secondImpact ?? HapticFeedback.heavyImpact,
    );
  }

  @override
  void didUpdateWidget(covariant StartupIntro oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.ready && widget.ready) _tryFinishIntro();
  }

  void _scheduleImpact(Duration delay, StartupImpact impact) {
    _timers.add(
      Timer(delay, () {
        if (mounted) unawaited(impact());
      }),
    );
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _markAnimationComplete();
  }

  void _markAnimationComplete() {
    if (!mounted || _animationComplete) return;
    setState(() => _animationComplete = true);
    if (!widget.ready) unawaited(_loadingController.repeat());
    _tryFinishIntro();
  }

  void _tryFinishIntro() {
    if (!_animationComplete || !widget.ready) return;
    _finishIntro();
  }

  void _finishIntro() {
    if (!mounted || !_showIntro) return;
    _loadingController.stop();
    setState(() => _showIntro = false);
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showIntro)
          Positioned.fill(
            child: AbsorbPointer(
              key: const Key('startup-intro'),
              child: AnimatedBuilder(
                animation: Listenable.merge([_controller, _loadingController]),
                builder: (context, _) => _StartupIntroFrame(
                  progress: _controller.value,
                  waitingForData: _animationComplete && !widget.ready,
                  loadingProgress: _loadingController.value,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StartupIntroFrame extends StatelessWidget {
  const _StartupIntroFrame({
    required this.progress,
    required this.waitingForData,
    required this.loadingProgress,
  });

  final double progress;
  final bool waitingForData;
  final double loadingProgress;

  static double _interval(
    double value,
    double begin,
    double end, [
    Curve curve = Curves.linear,
  ]) {
    return curve.transform(((value - begin) / (end - begin)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final firstEntrance = _interval(progress, 0.02, 0.13, Curves.easeOutExpo);
    final firstOpacity = _interval(progress, 0.01, 0.04);
    final secondEntrance = _interval(progress, 0.63, 0.80, Curves.easeOutExpo);
    final secondOpacity = _interval(progress, 0.62, 0.65);
    final collisionIn = _interval(progress, 0.76, 0.805, Curves.easeOut);
    final collisionOut = _interval(progress, 0.805, 0.91, Curves.easeOutBack);
    final collision = collisionIn * (1 - collisionOut);
    final firstImpact = 1 - _interval(progress, 0.08, 0.19, Curves.easeOut);
    final firstShake = progress >= 0.07 && progress <= 0.19
        ? math.sin(progress * math.pi * 66) * firstImpact * 4
        : 0.0;
    final collisionShake = progress >= 0.76 && progress <= 0.91
        ? math.sin(progress * math.pi * 82) * collision * 9
        : 0.0;

    return ColoredBox(
      color: AppColors.background,
      child: CustomPaint(
        painter: const _IntroBackgroundPainter(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shortest = math.min(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final firstSize = (shortest * 0.21).clamp(72.0, 122.0);
              final secondSize = (shortest * 0.115).clamp(42.0, 70.0);

              return Transform.translate(
                offset: Offset(firstShake + collisionShake, 0),
                child: Center(
                  child: SizedBox(
                    width: math.min(constraints.maxWidth * 0.94, 680),
                    height: math.min(constraints.maxHeight * 0.32, 250),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              flex: 3,
                              child: Opacity(
                                opacity: firstOpacity,
                                child: Transform.translate(
                                  offset: Offset(
                                    -(1 - firstEntrance) *
                                        constraints.maxWidth *
                                        0.55,
                                    0,
                                  ),
                                  child: Text(
                                    '딱!',
                                    key: const Key('startup-intro-first'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Galmuri',
                                      fontSize: firstSize,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -firstSize * 0.08,
                                      color: AppColors.text,
                                      decoration: TextDecoration.none,
                                      shadows: const [
                                        Shadow(
                                          color: AppColors.primaryShadow,
                                          offset: Offset(5, 7),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              flex: 5,
                              child: Opacity(
                                opacity: secondOpacity,
                                child: Transform.translate(
                                  offset: Offset(
                                    (1 - secondEntrance) *
                                        constraints.maxWidth *
                                        0.9,
                                    0,
                                  ),
                                  child: Transform(
                                    alignment: Alignment.centerLeft,
                                    transform: Matrix4.diagonal3Values(
                                      1 - collision * 0.24,
                                      1 + collision * 0.18,
                                      1,
                                    ),
                                    child: Text(
                                      '한 판만!',
                                      key: const Key('startup-intro-second'),
                                      maxLines: 1,
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        fontFamily: 'Galmuri',
                                        fontSize: secondSize,
                                        height: 1,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -secondSize * 0.055,
                                        color: AppColors.primary,
                                        decoration: TextDecoration.none,
                                        shadows: [
                                          Shadow(
                                            color: AppColors.primaryShadow,
                                            offset: Offset(
                                              3 + collision * 7,
                                              4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 30,
                          child: waitingForData
                              ? _StartupLoadingDots(progress: loadingProgress)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StartupLoadingDots extends StatelessWidget {
  const _StartupLoadingDots({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final activeDot = (progress * 3).floor() % 3;
    return Semantics(
      key: const Key('startup-intro-loading'),
      label: '오늘의 게임 준비 중',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          3,
          (index) => Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: index == activeDot
                ? AppColors.primary
                : AppColors.surfaceLight,
          ),
        ),
      ),
    );
  }
}

class _IntroBackgroundPainter extends CustomPainter {
  const _IntroBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.surface.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (double y = 22; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final dotPaint = Paint()
      ..color = AppColors.surfaceLight.withValues(alpha: 0.28);
    for (double y = 12; y < size.height; y += 48) {
      for (double x = 12; x < size.width; x += 48) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
