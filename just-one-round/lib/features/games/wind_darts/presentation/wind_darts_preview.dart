import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_art.dart';

/// Each guide page teaches one idea without turning the preview into a busy
/// screenshot. All scenes reuse the production board, dart, and pub assets.
enum WindDartsPreviewScene { home, controls, wind, distance, scoring }

class WindDartsPreview extends StatefulWidget {
  const WindDartsPreview({
    this.scene = WindDartsPreviewScene.home,
    this.animate = true,
    super.key,
  });

  final WindDartsPreviewScene scene;
  final bool animate;

  @override
  State<WindDartsPreview> createState() => _WindDartsPreviewState();
}

class _WindDartsPreviewState extends State<WindDartsPreview>
    with SingleTickerProviderStateMixin {
  static const _previewDurationSeconds = 36.0;
  static const _gaugeFillSeconds = 6.0;
  static const _flightSeconds = .72;
  static const _impactSeconds = 2.0;
  static const _retreatSeconds = .7;
  static const _holdSeconds = 4.0;
  static const _cycleSeconds =
      _holdSeconds + _flightSeconds + _impactSeconds + _retreatSeconds;

  late final AnimationController _clock;
  WindDartsArtImages? _images;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    );
    if (widget.animate) _clock.repeat();
    unawaited(_loadImages());
  }

  Future<void> _loadImages() async {
    try {
      final images = await WindDartsArt.loadFromBundle();
      if (!mounted) {
        images.dispose();
        return;
      }
      setState(() => _images = images);
    } catch (error, stackTrace) {
      debugPrint('Wind darts preview asset load failed: $error\n$stackTrace');
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _images?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: widget.animate ? _clock : const AlwaysStoppedAnimation(0),
      builder: (context, _) {
        final rawTime = widget.animate
            ? _clock.value * _previewDurationSeconds
            : _staticTimeForScene(widget.scene);
        final cycleTime = rawTime % _cycleSeconds;
        final shotIndex = (rawTime ~/ _cycleSeconds) % WindDartsRules.shotCount;
        final phase = _previewPhaseForElapsed(cycleTime);
        final flightProgress = phase == _PreviewPhase.flight
            ? ((cycleTime - _holdSeconds) / _flightSeconds).clamp(0.0, 1.0)
            : phase == _PreviewPhase.impact || phase == _PreviewPhase.retreat
            ? 1.0
            : 0.0;
        final impactProgress = phase == _PreviewPhase.impact
            ? ((cycleTime - _holdSeconds - _flightSeconds) / _impactSeconds)
                  .clamp(0.0, 1.0)
            : phase == _PreviewPhase.retreat
            ? 1.0
            : 0.0;
        final retreatProgress = phase == _PreviewPhase.retreat
            ? ((cycleTime - _holdSeconds - _flightSeconds - _impactSeconds) /
                      _retreatSeconds)
                  .clamp(0.0, 1.0)
            : 0.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final layout = _WindDartsPreviewLayout.forSize(
              size,
              scene: widget.scene,
              shotScale: WindDartsRules.boardScaleForShot(shotIndex),
            );
            final displayedShotScale =
                widget.scene == WindDartsPreviewScene.distance
                ? 1.0
                : WindDartsRules.boardScaleForShot(shotIndex);
            final effectiveScale = _effectiveBoardScale(
              displayedShotScale,
              phase,
              flightProgress,
              retreatProgress,
            );
            final boardRadius = layout.boardRadius * effectiveScale;
            final aimSeconds = widget.scene == WindDartsPreviewScene.controls
                ? 3.5
                : widget.scene == WindDartsPreviewScene.wind
                ? 3.0
                : widget.animate
                ? cycleTime.clamp(0.0, _gaugeFillSeconds)
                : 4.0;
            final aimSample = WindDartsRules.aimAt(aimSeconds, boardRadius);
            final aimOffset = aimSample.offset;
            final power = widget.scene == WindDartsPreviewScene.controls
                ? (aimSeconds / _gaugeFillSeconds).clamp(0.0, 1.0)
                : aimSample.power;
            final targetOffset = widget.scene == WindDartsPreviewScene.scoring
                ? Offset(
                    0,
                    -boardRadius *
                        (WindDartsRules.tripleInnerRadiusRatio +
                            WindDartsRules.tripleOuterRadiusRatio) /
                        2,
                  )
                : aimOffset;
            final cameraZoom = WindDartsArt.worldZoomForShotScale(
              effectiveScale,
            );
            final worldBoardRadius =
                layout.boardRadius * WindDartsArt.worldBoardScale;
            final targetWorldOffset = targetOffset / cameraZoom;
            final flightStart = layout.center + Offset(0, boardRadius * 2.35);
            final flightTarget = layout.center + targetOffset;

            return Stack(
              clipBehavior: Clip.hardEdge,
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: KeyedSubtree(
                    key: ValueKey(
                      _images == null
                          ? 'wind-darts-preview-loading'
                          : 'wind-darts-preview-ready',
                    ),
                    child: CustomPaint(
                      key: const Key('wind-darts-preview'),
                      painter: _WindDartsPreviewPainter(
                        boardAngle: WindDartsRules.boardAngle,
                        center: layout.center,
                        radius: boardRadius,
                        worldRadius: worldBoardRadius,
                        cameraZoom: cameraZoom,
                        scene: widget.scene,
                        aim: layout.center + targetOffset,
                        power: power,
                        images: _images,
                        phase: phase,
                        flightProgress: flightProgress,
                        impactProgress: impactProgress,
                        flightStart: flightStart,
                        flightTarget: flightTarget,
                        targetWorldOffset: targetWorldOffset,
                        previewSize: size,
                      ),
                    ),
                  ),
                ),
                _PreviewHud(scene: widget.scene, power: power, images: _images),
              ],
            );
          },
        );
      },
    ),
  );

  static double _staticTimeForScene(WindDartsPreviewScene scene) =>
      switch (scene) {
        WindDartsPreviewScene.home => 0,
        WindDartsPreviewScene.controls => 3.5,
        WindDartsPreviewScene.wind => 3.0,
        WindDartsPreviewScene.distance => 0,
        WindDartsPreviewScene.scoring => _holdSeconds + _flightSeconds + .2,
      };

  static double _effectiveBoardScale(
    double shotScale,
    _PreviewPhase phase,
    double flightProgress,
    double retreatProgress,
  ) {
    if (phase == _PreviewPhase.flight || phase == _PreviewPhase.impact) {
      return ui.lerpDouble(shotScale, 1.0, flightProgress) ?? 1.0;
    }
    if (phase == _PreviewPhase.retreat) {
      return ui.lerpDouble(1.0, shotScale, retreatProgress) ?? shotScale;
    }
    return shotScale;
  }
}

enum _PreviewPhase { aim, flight, impact, retreat }

_PreviewPhase _previewPhaseForElapsed(double elapsed) {
  if (elapsed < _WindDartsPreviewState._holdSeconds) {
    return _PreviewPhase.aim;
  }
  if (elapsed <
      _WindDartsPreviewState._holdSeconds +
          _WindDartsPreviewState._flightSeconds) {
    return _PreviewPhase.flight;
  }
  if (elapsed <
      _WindDartsPreviewState._holdSeconds +
          _WindDartsPreviewState._flightSeconds +
          _WindDartsPreviewState._impactSeconds) {
    return _PreviewPhase.impact;
  }
  return _PreviewPhase.retreat;
}

class _WindDartsPreviewLayout {
  const _WindDartsPreviewLayout({
    required this.center,
    required this.boardRadius,
  });

  final Offset center;
  final double boardRadius;

  static _WindDartsPreviewLayout forSize(
    Size size, {
    required WindDartsPreviewScene scene,
    required double shotScale,
  }) {
    final safeWidth = size.width.isFinite && size.width > 0 ? size.width : 1;
    final safeHeight = size.height.isFinite && size.height > 0
        ? size.height
        : 1;
    if (scene == WindDartsPreviewScene.distance) {
      final radius = math.min(safeWidth * .2, (safeHeight - 78) / 2.58);
      return _WindDartsPreviewLayout(
        center: Offset(safeWidth / 2, math.max(112, safeHeight * .42)),
        boardRadius: radius.clamp(42.0, 86.0),
      );
    }

    // 292/228 is the furthest authored number cell from the centre. The
    // vertical cap keeps every number and the bottom HUD inside short guide
    // cards (including 280x260 test slots).
    const outerToScoringRadius = 292 / 228;
    const topSafe = 38.0;
    final footer = scene == WindDartsPreviewScene.controls ? 48.0 : 38.0;
    final widthRadius = safeWidth * .36;
    final heightRadius =
        (safeHeight - topSafe - footer) / (2 * outerToScoringRadius + .04);
    final radius = math.min(widthRadius, heightRadius).clamp(42.0, 154.0);
    final centerX = scene == WindDartsPreviewScene.scoring
        ? safeWidth * .57
        : safeWidth / 2;
    final centerY = topSafe + radius * (outerToScoringRadius + .02);
    return _WindDartsPreviewLayout(
      center: Offset(centerX, centerY),
      // The layout radius is the initial 1m board radius. Distance and the
      // forward camera then scale this same world board around its centre.
      boardRadius: radius,
    );
  }
}

class _PreviewHud extends StatelessWidget {
  const _PreviewHud({
    required this.scene,
    required this.power,
    required this.images,
  });

  final WindDartsPreviewScene scene;
  final double power;
  final WindDartsArtImages? images;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gaugeWidth = math.min(
        320.0,
        math.max(0.0, constraints.maxWidth - 24),
      );
      final gaugeHeight = math.min(36.0, math.max(24.0, gaugeWidth * .1125));
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 10,
            right: 10,
            top: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: _HudPill(
                    title: switch (scene) {
                      WindDartsPreviewScene.wind => 'WIND · 2시',
                      WindDartsPreviewScene.distance => 'DISTANCE',
                      _ => 'WIND · 1.4 m/s',
                    },
                    detail: switch (scene) {
                      WindDartsPreviewScene.controls => '누르고 끌어 조준',
                      WindDartsPreviewScene.wind => '방향 + m/s',
                      WindDartsPreviewScene.distance => '1m → 3.5m',
                      WindDartsPreviewScene.scoring => '착탄 지점',
                      _ => 'THROW · 1 / 6',
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: _HudPill(
                      alignEnd: true,
                      title: scene == WindDartsPreviewScene.scoring
                          ? 'TRIPLE · 20'
                          : scene == WindDartsPreviewScene.distance
                          ? 'CAMERA'
                          : 'YOUR TOTAL',
                      detail: scene == WindDartsPreviewScene.scoring
                          ? '20 × 3 = 60점'
                          : scene == WindDartsPreviewScene.distance
                          ? '판까지 가까워져요'
                          : scene == WindDartsPreviewScene.controls
                          ? '게이지는 파워 아님'
                          : '0점',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (scene == WindDartsPreviewScene.home ||
              scene == WindDartsPreviewScene.controls)
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    scene == WindDartsPreviewScene.controls
                        ? 'AIM TIME · 누르고 조정 · 놓아 발사'
                        : 'AIM TIME · 6초 뒤에도 계속 조준 가능',
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: Color(0xFFFFE2A1),
                      fontFamily: 'Galmuri',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (images != null)
                    SizedBox(
                      height: gaugeHeight,
                      width: gaugeWidth,
                      child: CustomPaint(
                        painter: _WindDartsGaugePainter(
                          frame: images!.aimGaugeFrame,
                          fill: images!.aimGaugeFill,
                          fraction: power,
                        ),
                      ),
                    ),
                ],
              ),
            )
          else if (scene != WindDartsPreviewScene.scoring)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(
                switch (scene) {
                  WindDartsPreviewScene.wind => '바람 · 2시 방향 · 2.8 m/s',
                  WindDartsPreviewScene.distance => '던질수록 준비 화면은 작아져요',
                  _ => '',
                },
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFE2A1),
                  fontFamily: 'Galmuri',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _HudPill extends StatelessWidget {
  const _HudPill({
    required this.title,
    required this.detail,
    this.alignEnd = false,
  });

  final String title;
  final String detail;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      Text(
        title,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          color: Color(0xFFFFE2A1),
          fontFamily: 'Galmuri',
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(
        detail,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          color: Color(0xFFF5EEE0),
          fontFamily: 'Galmuri',
          fontSize: 8,
        ),
      ),
    ],
  );
}

class _WindDartsPreviewPainter extends CustomPainter {
  _WindDartsPreviewPainter({
    required this.boardAngle,
    required this.center,
    required this.radius,
    required this.worldRadius,
    required this.cameraZoom,
    required this.scene,
    required this.aim,
    required this.power,
    required this.images,
    required this.phase,
    required this.flightProgress,
    required this.impactProgress,
    required this.flightStart,
    required this.flightTarget,
    required this.targetWorldOffset,
    required this.previewSize,
  });

  final double boardAngle;
  final Offset center;
  final double radius;
  final double worldRadius;
  final double cameraZoom;
  final WindDartsPreviewScene scene;
  final Offset aim;
  final double power;
  final WindDartsArtImages? images;
  final _PreviewPhase phase;
  final double flightProgress;
  final double impactProgress;
  final Offset flightStart;
  final Offset flightTarget;
  final Offset targetWorldOffset;
  final Size previewSize;

  @override
  void paint(Canvas canvas, Size size) {
    final loaded = images;
    if (loaded == null) {
      canvas.drawColor(const Color(0xFF17110B), BlendMode.srcOver);
      return;
    }
    if (scene == WindDartsPreviewScene.distance) {
      _drawDistanceScene(canvas, size, loaded);
      return;
    }

    WindDartsArt.drawWorld(
      canvas,
      pivot: center,
      zoom: cameraZoom,
      draw: () {
        WindDartsArt.drawPubBackground(canvas, loaded.pubInterior, size);
        final embeddedTip =
            phase == _PreviewPhase.impact ||
                phase == _PreviewPhase.retreat ||
                scene == WindDartsPreviewScene.scoring
            ? WindDartsArt.toBoardLocalVector(targetWorldOffset, boardAngle)
            : null;
        WindDartsArt.drawBoard(
          canvas: canvas,
          boardFace: loaded.boardFace,
          boardNumbers: loaded.boardNumbers,
          center: center,
          logicalBoardRadius: worldRadius,
          boardAngle: boardAngle,
          dartAtlas: loaded.dartAtlas,
          embeddedTip: embeddedTip,
          embeddedTailDirection: embeddedTip,
          embeddedImpactProgress: impactProgress,
        );
        if (phase == _PreviewPhase.flight) {
          final progress = Curves.easeInCubic.transform(flightProgress);
          final screenTip = Offset.lerp(flightStart, flightTarget, progress)!;
          final worldTip = center + (screenTip - center) / cameraZoom;
          final startWorld = center + (flightStart - center) / cameraZoom;
          WindDartsArt.drawDart(
            canvas,
            atlas: loaded.dartAtlas,
            cell: 0,
            tip: worldTip,
            tailDirection: startWorld - worldTip,
            scale: WindDartsArt.dartScaleForBoardRadius(worldRadius),
          );
        }
      },
    );

    if (scene == WindDartsPreviewScene.wind) {
      _drawWindCallout(canvas, size);
    }
    if (scene == WindDartsPreviewScene.controls ||
        scene == WindDartsPreviewScene.home) {
      _drawAim(canvas, loaded);
    }
    if (scene == WindDartsPreviewScene.scoring) {
      _drawScoringLedger(canvas, size, loaded);
    }
  }

  void _drawAim(Canvas canvas, WindDartsArtImages loaded) {
    if (phase == _PreviewPhase.flight || phase == _PreviewPhase.impact) return;
    final launch = Offset(
      center.dx + radius * .45,
      math.min(previewSize.height - radius * .2, center.dy + radius * 2.1),
    );
    WindDartsArt.drawDart(
      canvas,
      atlas: loaded.dartAtlas,
      cell: 0,
      tip: aim,
      tailDirection: launch - aim,
      scale: WindDartsArt.dartScaleForBoardRadius(radius),
    );
    final crosshair = Paint()
      ..color = const Color(0xFFFFE8B7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawCircle(aim, 7, crosshair);
    canvas.drawLine(
      aim - const Offset(11, 0),
      aim + const Offset(11, 0),
      crosshair,
    );
    canvas.drawLine(
      aim - const Offset(0, 11),
      aim + const Offset(0, 11),
      crosshair,
    );
    if (scene == WindDartsPreviewScene.controls) {
      canvas.drawCircle(
        aim,
        11 + 18 * power,
        Paint()
          ..color = const Color(0x88FFE8B7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final arrowY = math.min(
        previewSize.height - 52,
        center.dy + radius * 1.28,
      );
      _arrow(
        canvas,
        Offset(center.dx - 42, arrowY),
        Offset(center.dx + 42, arrowY),
      );
    }
  }

  void _drawWindCallout(Canvas canvas, Size size) {
    final y = math.min(size.height - 44, center.dy + radius * 1.3);
    _arrow(canvas, Offset(center.dx - 26, y), Offset(center.dx + 35, y - 10));
    _paintText(canvas, '2시 · 2.8 m/s', Offset(center.dx - 46, y + 7), 10);
  }

  void _drawDistanceScene(Canvas canvas, Size size, WindDartsArtImages loaded) {
    WindDartsArt.drawPubBackground(canvas, loaded.pubInterior, size);
    final smallRadius = _WindDartsPreviewLayout.forSize(
      size,
      scene: WindDartsPreviewScene.distance,
      shotScale: 1,
    ).boardRadius;
    final left = Offset(size.width * .27, size.height * .42);
    final right = Offset(size.width * .73, size.height * .42);
    final boards = <(Offset, double)>[(left, 1.0), (right, .61)];
    for (final entry in boards) {
      WindDartsArt.drawBoard(
        canvas: canvas,
        boardFace: loaded.boardFace,
        boardNumbers: loaded.boardNumbers,
        center: entry.$1,
        logicalBoardRadius: smallRadius * entry.$2,
        boardAngle: boardAngle,
      );
    }
    _paintText(canvas, '1m', left - Offset(11, -smallRadius * 1.25), 12);
    _paintText(canvas, '3.5m', right - Offset(18, -smallRadius * .84), 12);
    _arrow(
      canvas,
      Offset(left.dx + smallRadius * 1.1, size.height * .42),
      Offset(right.dx - smallRadius * 1.1, size.height * .42),
    );
    _paintText(
      canvas,
      '카메라가 판까지 전진',
      Offset(size.width / 2 - 55, size.height * .7),
      10,
    );
  }

  void _drawScoringLedger(Canvas canvas, Size size, WindDartsArtImages loaded) {
    final ledgerSize = Size(
      math.min(82, size.width * .22),
      math.min(110, size.height * .31),
    );
    final offset = Offset(8, size.height - ledgerSize.height - 32);
    WindDartsArt.drawScoreParchment(
      canvas,
      loaded.scoreParchment,
      offset: offset,
      size: ledgerSize,
    );
    _paintText(
      canvas,
      'R1  60',
      offset + const Offset(12, 28),
      10,
      color: const Color(0xFF3A2113),
    );
    _paintText(
      canvas,
      '상대 42',
      offset + const Offset(12, 46),
      9,
      color: const Color(0xFF3A2113),
    );
    _paintText(
      canvas,
      'TRIPLE 20',
      Offset(size.width * .43, size.height - 28),
      11,
    );
    final target = aim;
    canvas.drawCircle(
      target,
      math.max(6, radius * .075),
      Paint()
        ..color = const Color(0xFFFFE596)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _arrow(Canvas canvas, Offset start, Offset end) {
    final paint = Paint()
      ..color = const Color(0xFFFFE2A1)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(start, end, paint);
    final direction =
        (end - start) /
        ((end - start).distance == 0 ? 1 : (end - start).distance);
    final normal = Offset(-direction.dy, direction.dx);
    canvas.drawLine(end, end - direction * 8 + normal * 4, paint);
    canvas.drawLine(end, end - direction * 8 - normal * 4, paint);
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize, {
    Color color = const Color(0xFFFFE2A1),
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: 'Galmuri',
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: previewSize.width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _WindDartsPreviewPainter oldDelegate) =>
      boardAngle != oldDelegate.boardAngle ||
      aim != oldDelegate.aim ||
      power != oldDelegate.power ||
      scene != oldDelegate.scene ||
      center != oldDelegate.center ||
      radius != oldDelegate.radius ||
      cameraZoom != oldDelegate.cameraZoom ||
      phase != oldDelegate.phase ||
      flightProgress != oldDelegate.flightProgress ||
      impactProgress != oldDelegate.impactProgress ||
      images != oldDelegate.images;
}

class _WindDartsGaugePainter extends CustomPainter {
  const _WindDartsGaugePainter({
    required this.frame,
    required this.fill,
    required this.fraction,
  });

  final ui.Image frame;
  final ui.Image fill;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    WindDartsArt.drawAimGauge(
      canvas,
      frame: frame,
      fill: fill,
      fraction: fraction,
      offset: Offset.zero,
      size: size,
    );
  }

  @override
  bool shouldRepaint(covariant _WindDartsGaugePainter oldDelegate) =>
      fraction != oldDelegate.fraction ||
      frame != oldDelegate.frame ||
      fill != oldDelegate.fill;
}
