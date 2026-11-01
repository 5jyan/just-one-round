import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_one_round/features/games/wind_darts/domain/wind_darts_rules.dart';
import 'package:just_one_round/features/games/wind_darts/presentation/wind_darts_art.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

/// Each guide page teaches one idea without turning the preview into a busy
/// screenshot. All scenes reuse the production board, dart, and pub assets.
enum WindDartsPreviewScene { home, controls, wind, distance, scoring }

/// The staged home sequence follows the production shot timings while keeping
/// the preview independent from a live Flame game.
enum WindDartsPreviewPhase { aim, flight, impact, retreat }

@visibleForTesting
class WindDartsPreviewTiming {
  const WindDartsPreviewTiming({
    required this.shotIndex,
    required this.phase,
    required this.cycleElapsed,
    required this.flightProgress,
    required this.impactProgress,
    required this.retreatProgress,
  });

  final int shotIndex;
  final WindDartsPreviewPhase phase;
  final double cycleElapsed;
  final double flightProgress;
  final double impactProgress;
  final double retreatProgress;
}

const _previewGaugeFillSeconds = 6.0;
const _previewImpactSeconds = 2.0;
const _previewRetreatSeconds = .7;
// A short legal hold keeps the staged launch inside the game's real manual
// aim range while leaving the six-second gauge explanation visible.
const _previewHoldSeconds = 2.4;
const _previewFlightBaseSeconds = .72;

const _previewPlayerScores = <int>[20, 40, 60, 25, 50, 18, 120];
const _previewOpponentScores = <int>[7, 19, 10, 20, 6, 9, 22];
const _previewWind = WindDartsWind(clockDirection: 2, metersPerSecond: 2.8);

double _previewFlightSecondsForShot(int shotIndex) =>
    _previewFlightBaseSeconds +
    shotIndex.clamp(0, WindDartsRules.shotCount - 1) * .05;

double _previewCycleSecondsForShot(int shotIndex) =>
    _previewHoldSeconds +
    _previewFlightSecondsForShot(shotIndex) +
    _previewImpactSeconds +
    _previewRetreatSeconds;

double _previewDurationSeconds() {
  var duration = 0.0;
  for (var index = 0; index < WindDartsRules.shotCount; index++) {
    duration += _previewCycleSecondsForShot(index);
  }
  return duration;
}

@visibleForTesting
double windDartsPreviewDurationSeconds() => _previewDurationSeconds();

@visibleForTesting
double windDartsPreviewCycleSecondsForShot(int shotIndex) =>
    _previewCycleSecondsForShot(shotIndex);

@visibleForTesting
int windDartsPreviewScoreForShot(int shotIndex) =>
    _previewPlayerScores[shotIndex.clamp(0, WindDartsRules.shotCount - 1)];

@visibleForTesting
int windDartsPreviewTotalForCompletedShots(int completedShots) {
  final count = completedShots.clamp(0, WindDartsRules.shotCount);
  return _previewPlayerScores
      .take(count)
      .fold(0, (total, score) => total + score);
}

@visibleForTesting
WindDartsPreviewTiming windDartsPreviewTimingForElapsed(double elapsed) {
  final duration = _previewDurationSeconds();
  var remaining = elapsed.isFinite && elapsed >= 0 ? elapsed % duration : 0.0;
  var shotIndex = 0;
  for (; shotIndex < WindDartsRules.shotCount; shotIndex++) {
    final cycle = _previewCycleSecondsForShot(shotIndex);
    if (remaining < cycle || shotIndex == WindDartsRules.shotCount - 1) break;
    remaining -= cycle;
  }

  final flightSeconds = _previewFlightSecondsForShot(shotIndex);
  final flightEnd = _previewHoldSeconds + flightSeconds;
  final impactEnd = flightEnd + _previewImpactSeconds;
  if (remaining < _previewHoldSeconds) {
    return WindDartsPreviewTiming(
      shotIndex: shotIndex,
      phase: WindDartsPreviewPhase.aim,
      cycleElapsed: remaining,
      flightProgress: 0,
      impactProgress: 0,
      retreatProgress: 0,
    );
  }
  if (remaining < flightEnd) {
    return WindDartsPreviewTiming(
      shotIndex: shotIndex,
      phase: WindDartsPreviewPhase.flight,
      cycleElapsed: remaining,
      flightProgress: ((remaining - _previewHoldSeconds) / flightSeconds).clamp(
        0.0,
        1.0,
      ),
      impactProgress: 0,
      retreatProgress: 0,
    );
  }
  if (remaining < impactEnd) {
    return WindDartsPreviewTiming(
      shotIndex: shotIndex,
      phase: WindDartsPreviewPhase.impact,
      cycleElapsed: remaining,
      flightProgress: 1,
      impactProgress: ((remaining - flightEnd) / _previewImpactSeconds).clamp(
        0.0,
        1.0,
      ),
      retreatProgress: 0,
    );
  }
  return WindDartsPreviewTiming(
    shotIndex: shotIndex,
    phase: WindDartsPreviewPhase.retreat,
    cycleElapsed: remaining,
    flightProgress: 1,
    impactProgress: 1,
    retreatProgress: ((remaining - impactEnd) / _previewRetreatSeconds).clamp(
      0.0,
      1.0,
    ),
  );
}

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
  late final AnimationController _clock;
  WindDartsArtImages? _images;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (_previewDurationSeconds() * 1000).round(),
      ),
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
            ? _clock.value * _previewDurationSeconds()
            : _staticTimeForScene(widget.scene);
        final timing = windDartsPreviewTimingForElapsed(rawTime);
        final shotIndex = timing.shotIndex;
        final phase = timing.phase;
        final flightProgress = timing.flightProgress;
        final impactProgress = timing.impactProgress;
        final retreatProgress = timing.retreatProgress;

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
                : phase == WindDartsPreviewPhase.aim
                ? timing.cycleElapsed.clamp(0.0, _previewGaugeFillSeconds)
                : _previewHoldSeconds;
            final power = widget.scene == WindDartsPreviewScene.controls
                ? (aimSeconds / _previewGaugeFillSeconds).clamp(0.0, 1.0)
                : WindDartsRules.powerAt(aimSeconds);
            final cameraZoom = WindDartsArt.worldZoomForShotScale(
              effectiveScale,
            );
            final worldBoardRadius =
                layout.boardRadius * WindDartsArt.worldBoardScale;
            final launchScale = WindDartsRules.boardScaleForShot(shotIndex);
            final launchRadius = layout.boardRadius * launchScale;
            final launchZoom = WindDartsArt.worldZoomForShotScale(launchScale);
            final launchAimOffset = widget.scene == WindDartsPreviewScene.home
                ? windDartsPreviewLaunchAimOffsetForShot(
                    shotIndex,
                    boardRadius: layout.boardRadius,
                  )
                : null;
            final launchAimWorldOffset = launchAimOffset == null
                ? null
                : launchAimOffset / launchZoom;
            final stagedManualOffset = launchAimOffset == null
                ? null
                : launchAimOffset -
                      WindDartsRules.aimAt(
                        _previewHoldSeconds,
                        launchRadius,
                      ).offset;
            final dynamicAimOffset = widget.scene == WindDartsPreviewScene.home
                ? phase == WindDartsPreviewPhase.aim
                      ? WindDartsRules.aimAt(
                              timing.cycleElapsed,
                              launchRadius,
                            ).offset +
                            (stagedManualOffset ?? Offset.zero) *
                                (timing.cycleElapsed / .5).clamp(0.0, 1.0)
                      : (launchAimWorldOffset ?? Offset.zero) * cameraZoom
                : widget.scene == WindDartsPreviewScene.scoring
                ? WindDartsRules.representativePointForScore(
                        score: 120,
                        boardRadius: worldBoardRadius,
                        isGoldenDart: true,
                      ) *
                      cameraZoom
                : WindDartsRules.aimAt(aimSeconds, boardRadius).offset;
            final targetWorldOffset = _targetWorldOffset(
              scene: widget.scene,
              shotIndex: shotIndex,
              worldBoardRadius: worldBoardRadius,
              dynamicAimOffset: dynamicAimOffset,
              cameraZoom: cameraZoom,
            );
            final targetOffset = targetWorldOffset * cameraZoom;
            final flightStart = layout.center + Offset(0, boardRadius * 2.35);
            final flightTarget = layout.center + targetOffset;
            final completedShots = widget.scene == WindDartsPreviewScene.home
                ? switch (phase) {
                    WindDartsPreviewPhase.impact ||
                    WindDartsPreviewPhase.retreat => shotIndex + 1,
                    _ => shotIndex,
                  }
                : 0;
            final totalScore = windDartsPreviewTotalForCompletedShots(
              completedShots,
            );
            final goldenDart =
                widget.scene == WindDartsPreviewScene.scoring ||
                WindDartsRules.isGoldenDart(shotIndex);

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
                        shotIndex: shotIndex,
                        goldenDart: goldenDart,
                        aim: layout.center + dynamicAimOffset,
                        power: power,
                        images: _images,
                        phase: phase,
                        flightProgress: flightProgress,
                        impactProgress: impactProgress,
                        flightStart: flightStart,
                        flightTarget: flightTarget,
                        targetWorldOffset: targetWorldOffset,
                        windLanding: widget.scene == WindDartsPreviewScene.wind
                            ? _windLandingOffset(
                                aim: layout.center + dynamicAimOffset,
                                radius: boardRadius,
                              )
                            : null,
                        previewSize: size,
                      ),
                    ),
                  ),
                ),
                _PreviewHud(
                  scene: widget.scene,
                  power: power,
                  images: _images,
                  shotIndex: shotIndex,
                  totalScore: totalScore,
                  completedShots: completedShots,
                ),
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
        WindDartsPreviewScene.scoring =>
          _previewHoldSeconds + _previewFlightBaseSeconds + .2,
      };

  static double _effectiveBoardScale(
    double shotScale,
    WindDartsPreviewPhase phase,
    double flightProgress,
    double retreatProgress,
  ) {
    if (phase == WindDartsPreviewPhase.flight) {
      final t = flightProgress.clamp(0.0, 1.0);
      final eased = t * t * (3 - 2 * t);
      return ui.lerpDouble(shotScale, 1.0, eased) ?? 1.0;
    }
    if (phase == WindDartsPreviewPhase.impact) {
      return 1.0;
    }
    if (phase == WindDartsPreviewPhase.retreat) {
      final t = retreatProgress.clamp(0.0, 1.0);
      final eased = t * t * (3 - 2 * t);
      return ui.lerpDouble(1.0, shotScale, eased) ?? shotScale;
    }
    return shotScale;
  }
}

Offset _targetWorldOffset({
  required WindDartsPreviewScene scene,
  required int shotIndex,
  required double worldBoardRadius,
  required Offset dynamicAimOffset,
  required double cameraZoom,
}) {
  if (scene == WindDartsPreviewScene.home ||
      scene == WindDartsPreviewScene.scoring) {
    final score = scene == WindDartsPreviewScene.scoring
        ? 120
        : windDartsPreviewScoreForShot(shotIndex);
    return WindDartsRules.representativePointForScore(
      score: score,
      boardRadius: worldBoardRadius,
      isGoldenDart:
          scene == WindDartsPreviewScene.scoring ||
          WindDartsRules.isGoldenDart(shotIndex),
    );
  }
  return dynamicAimOffset / cameraZoom;
}

Offset _windLandingOffset({required Offset aim, required double radius}) {
  final distanceScale = .75 + WindDartsRules.distanceForShot(0) * .12;
  final drift =
      _previewWind.unitVector *
      (_previewWind.metersPerSecond /
          3.5 *
          radius *
          WindDartsRules.windOffsetCoefficient *
          distanceScale);
  return aim + drift;
}

Offset _previewWindOffsetForShot({
  required int shotIndex,
  required double launchRadius,
}) {
  final distanceScale = .75 + WindDartsRules.distanceForShot(shotIndex) * .12;
  return _previewWind.unitVector *
      (_previewWind.metersPerSecond /
          3.5 *
          launchRadius *
          WindDartsRules.windOffsetCoefficient *
          distanceScale);
}

@visibleForTesting
Offset windDartsPreviewLaunchAimOffsetForShot(
  int shotIndex, {
  double boardRadius = WindDartsRules.baseBoardRadius,
}) {
  final safeIndex = shotIndex.clamp(0, WindDartsRules.shotCount - 1);
  final shotScale = WindDartsRules.boardScaleForShot(safeIndex);
  final worldRadius = boardRadius * WindDartsArt.worldBoardScale;
  final launchZoom = shotScale / WindDartsArt.worldBoardScale;
  final golden = WindDartsRules.isGoldenDart(safeIndex);
  final target = WindDartsRules.representativePointForScore(
    score: _previewPlayerScores[safeIndex],
    boardRadius: worldRadius,
    isGoldenDart: golden,
  );
  return target * launchZoom -
      _previewWindOffsetForShot(
        shotIndex: safeIndex,
        launchRadius: boardRadius * shotScale,
      );
}

@visibleForTesting
Offset windDartsPreviewManualAimOffsetForShot(
  int shotIndex, {
  double boardRadius = WindDartsRules.baseBoardRadius,
}) {
  final safeIndex = shotIndex.clamp(0, WindDartsRules.shotCount - 1);
  final shotScale = WindDartsRules.boardScaleForShot(safeIndex);
  final rawAim = WindDartsRules.aimAt(
    _previewHoldSeconds,
    boardRadius * shotScale,
  ).offset;
  return windDartsPreviewLaunchAimOffsetForShot(
        safeIndex,
        boardRadius: boardRadius,
      ) -
      rawAim;
}

WindDartsImpact _previewImpactForShot(
  int shotIndex,
  double worldBoardRadius, {
  bool forceTriple = false,
}) {
  final golden = forceTriple || WindDartsRules.isGoldenDart(shotIndex);
  final score = forceTriple ? 120 : windDartsPreviewScoreForShot(shotIndex);
  final point = WindDartsRules.representativePointForScore(
    score: score,
    boardRadius: worldBoardRadius,
    isGoldenDart: golden,
  );
  return WindDartsRules.resolveImpact(
    point: point,
    boardRadius: worldBoardRadius,
    boardAngle: WindDartsRules.boardAngle,
    isGoldenDart: golden,
  );
}

Offset _unitVector(Offset vector) {
  final distance = vector.distance;
  if (!distance.isFinite || distance < .001) return const Offset(0, 1);
  return vector / distance;
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
    required this.shotIndex,
    required this.totalScore,
    required this.completedShots,
  });

  final WindDartsPreviewScene scene;
  final double power;
  final WindDartsArtImages? images;
  final int shotIndex;
  final int totalScore;
  final int completedShots;

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
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: scene == WindDartsPreviewScene.distance
                      ? _HudPill(title: 'DISTANCE', detail: '1m → 3.5m')
                      : const _WindHudPreview(),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: _HudPill(
                      alignEnd: true,
                      title: scene == WindDartsPreviewScene.scoring
                          ? 'GOLD · TRIPLE 20'
                          : scene == WindDartsPreviewScene.distance
                          ? 'CAMERA'
                          : scene == WindDartsPreviewScene.controls
                          ? 'AIM TIME'
                          : 'YOUR TOTAL',
                      detail: scene == WindDartsPreviewScene.scoring
                          ? '60 × 2 = 120점'
                          : scene == WindDartsPreviewScene.distance
                          ? '판까지 가까워져요'
                          : scene == WindDartsPreviewScene.controls
                          ? '게이지는 파워 아님'
                          : '$totalScore점 · $completedShots/${WindDartsRules.shotCount}',
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
                  WordSafeText(
                    scene == WindDartsPreviewScene.controls
                        ? 'AIM TIME · 누르고 조정 · 놓아 발사'
                        : 'AIM TIME · 6초 뒤에도 계속 조준 가능',
                    singleLine: true,
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
              child: WordSafeText(
                switch (scene) {
                  WindDartsPreviewScene.distance => '준비할 땐 멀어지고 · 명중할 땐 확대',
                  _ => '',
                },
                singleLine: true,
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

class _WindHudPreview extends StatelessWidget {
  const _WindHudPreview();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _WindHudPreviewPainter());
}

class _WindHudPreviewPainter extends CustomPainter {
  const _WindHudPreviewPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final titlePainter = TextPainter(
      text: const TextSpan(
        text: 'WIND',
        style: TextStyle(
          color: Color(0xFFCBB998),
          fontFamily: 'Galmuri',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final valuePainter = TextPainter(
      text: TextSpan(
        text: _previewWind.metersPerSecond.toStringAsFixed(1),
        style: const TextStyle(
          color: Color(0xFFF2E6CB),
          fontFamily: 'Galmuri',
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final unitPainter = TextPainter(
      text: const TextSpan(
        text: 'm/s',
        style: TextStyle(
          color: Color(0xFFB7A181),
          fontFamily: 'Galmuri',
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const arrowWidth = 18.0;
    const titleArrowGap = 10.0;
    const arrowValueGap = 10.0;
    const unitGap = 4.0;
    final groupWidth =
        titlePainter.width +
        titleArrowGap +
        arrowWidth +
        arrowValueGap +
        valuePainter.width +
        unitGap +
        unitPainter.width;
    final groupStart = (size.width - groupWidth) / 2;
    final arrowBoxStart = groupStart + titlePainter.width + titleArrowGap;
    const centerY = 21.0;
    final direction = _previewWind.unitVector;
    final arrowCenter = Offset(arrowBoxStart + arrowWidth / 2, centerY);
    final arrowStart = arrowCenter - direction * (arrowWidth / 2);
    final arrowTip = arrowCenter + direction * (arrowWidth / 2);
    final arrowPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xFFE4BB72)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(arrowStart, arrowTip, arrowPaint);
    final perpendicular = Offset(-direction.dy, direction.dx);
    final arrowBase = arrowTip - direction * 6;
    final arrowHead = Path()
      ..moveTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(
        arrowBase.dx + perpendicular.dx * 3,
        arrowBase.dy + perpendicular.dy * 3,
      )
      ..lineTo(
        arrowBase.dx - perpendicular.dx * 3,
        arrowBase.dy - perpendicular.dy * 3,
      )
      ..close();
    canvas.drawPath(arrowHead, Paint()..color = const Color(0xFFE4BB72));
    titlePainter.paint(
      canvas,
      Offset(groupStart, centerY - titlePainter.height / 2),
    );
    final valueBaseline = valuePainter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final unitBaseline = unitPainter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final sharedAscent = math.max(valueBaseline, unitBaseline);
    final sharedDescent = math.max(
      valuePainter.height - valueBaseline,
      unitPainter.height - unitBaseline,
    );
    final sharedBaseline = centerY + (sharedAscent - sharedDescent) / 2;
    valuePainter.paint(
      canvas,
      Offset(
        arrowBoxStart + arrowWidth + arrowValueGap,
        sharedBaseline - valueBaseline,
      ),
    );
    unitPainter.paint(
      canvas,
      Offset(
        arrowBoxStart +
            arrowWidth +
            arrowValueGap +
            valuePainter.width +
            unitGap,
        sharedBaseline - unitBaseline,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _WindHudPreviewPainter oldDelegate) => false;
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
      WordSafeText(
        title,
        singleLine: true,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          color: Color(0xFFFFE2A1),
          fontFamily: 'Galmuri',
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      WordSafeText(
        detail,
        singleLine: true,
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
    required this.shotIndex,
    required this.goldenDart,
    required this.aim,
    required this.power,
    required this.images,
    required this.phase,
    required this.flightProgress,
    required this.impactProgress,
    required this.flightStart,
    required this.flightTarget,
    required this.targetWorldOffset,
    required this.windLanding,
    required this.previewSize,
  });

  final double boardAngle;
  final Offset center;
  final double radius;
  final double worldRadius;
  final double cameraZoom;
  final WindDartsPreviewScene scene;
  final int shotIndex;
  final bool goldenDart;
  final Offset aim;
  final double power;
  final WindDartsArtImages? images;
  final WindDartsPreviewPhase phase;
  final double flightProgress;
  final double impactProgress;
  final Offset flightStart;
  final Offset flightTarget;
  final Offset targetWorldOffset;
  final Offset? windLanding;
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
            phase == WindDartsPreviewPhase.impact ||
                phase == WindDartsPreviewPhase.retreat ||
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
          embeddedGoldenDart: goldenDart,
          embeddedImpactProgress: impactProgress,
          embeddedImpactKind:
              phase == WindDartsPreviewPhase.impact &&
                  (scene == WindDartsPreviewScene.home ||
                      scene == WindDartsPreviewScene.scoring)
              ? _previewImpactForShot(
                  scene == WindDartsPreviewScene.scoring ? 6 : shotIndex,
                  worldRadius,
                  forceTriple: scene == WindDartsPreviewScene.scoring,
                ).kind
              : null,
          embeddedImpactElapsed: phase == WindDartsPreviewPhase.impact
              ? impactProgress * _previewImpactSeconds
              : 0,
          embeddedImpactRadiusScale: 1 / cameraZoom,
          embeddedImpactClipRect: _impactClipRect(size),
        );
        if (phase == WindDartsPreviewPhase.flight) {
          final progress = flightProgress * flightProgress;
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
            golden: goldenDart,
          );
        }
      },
    );

    if (scene == WindDartsPreviewScene.wind && windLanding != null) {
      _drawWindDrift(canvas, windLanding!);
    }
    if (scene == WindDartsPreviewScene.controls ||
        scene == WindDartsPreviewScene.home) {
      _drawAim(canvas);
    }
    if (scene == WindDartsPreviewScene.scoring) {
      _drawScoringLedger(canvas, size, loaded);
    }
  }

  Rect _impactClipRect(Size size) {
    final top = math.min(48.0, size.height);
    final bottom = math.max(
      top,
      size.height - (scene == WindDartsPreviewScene.home ? 70 : 48),
    );
    return Rect.fromLTRB(
      center.dx + (0 - center.dx) / cameraZoom,
      center.dy + (top - center.dy) / cameraZoom,
      center.dx + (size.width - center.dx) / cameraZoom,
      center.dy + (bottom - center.dy) / cameraZoom,
    );
  }

  void _drawAim(Canvas canvas) {
    if (phase == WindDartsPreviewPhase.flight ||
        phase == WindDartsPreviewPhase.impact) {
      return;
    }
    _drawCrosshair(canvas, aim, color: const Color(0xFFFFE8B7), radius: 7);
    if (scene == WindDartsPreviewScene.controls) {
      canvas.drawCircle(
        aim,
        11 + 18 * power,
        Paint()
          ..color = const Color(0x88FFE8B7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final ghost = center + Offset(-radius * .42, radius * .24);
      final pathPaint = Paint()
        ..color = const Color(0xA8E4BB72)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      final segments = 5;
      for (var index = 0; index < segments; index++) {
        final startT = index / segments;
        final endT = (index + .58) / segments;
        canvas.drawLine(
          Offset.lerp(ghost, aim, startT)!,
          Offset.lerp(ghost, aim, endT)!,
          pathPaint,
        );
      }
      final direction = _unitVector(aim - ghost);
      final normal = Offset(-direction.dy, direction.dx);
      final arrowBase = aim - direction * 7;
      final arrowHead = Path()
        ..moveTo(aim.dx, aim.dy)
        ..lineTo(arrowBase.dx + normal.dx * 3, arrowBase.dy + normal.dy * 3)
        ..lineTo(arrowBase.dx - normal.dx * 3, arrowBase.dy - normal.dy * 3)
        ..close();
      canvas.drawPath(arrowHead, Paint()..color = const Color(0xFFE4BB72));
      _drawCrosshair(canvas, ghost, color: const Color(0x99E4BB72), radius: 6);
    }
  }

  void _drawCrosshair(
    Canvas canvas,
    Offset point, {
    required Color color,
    required double radius,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
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
  }

  void _drawWindDrift(Canvas canvas, Offset landing) {
    final linePaint = Paint()
      ..color = const Color(0xD6E4BB72)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(aim, landing, linePaint);
    final direction = _unitVector(landing - aim);
    final headBase = landing - direction * 7;
    final normal = Offset(-direction.dy, direction.dx);
    final head = Path()
      ..moveTo(landing.dx, landing.dy)
      ..lineTo(headBase.dx + normal.dx * 3, headBase.dy + normal.dy * 3)
      ..lineTo(headBase.dx - normal.dx * 3, headBase.dy - normal.dy * 3)
      ..close();
    canvas.drawPath(head, Paint()..color = const Color(0xFFE4BB72));
    _drawCrosshair(canvas, aim, color: const Color(0xFFE8D09D), radius: 6);
    _drawCrosshair(canvas, landing, color: const Color(0xFFFFE8B7), radius: 6);
    _paintText(canvas, '조준', aim + const Offset(-20, 13), 8);
    _paintText(canvas, '착탄', landing + const Offset(4, -15), 8);
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
    final labelY = size.height * .42 + smallRadius * 1.22;
    _paintText(canvas, '1m', Offset(left.dx - 11, labelY), 11);
    _paintText(canvas, '3.5m', Offset(right.dx - 18, labelY), 11);
    _arrow(
      canvas,
      Offset(left.dx + smallRadius * 1.1, size.height * .42),
      Offset(right.dx - smallRadius * 1.1, size.height * .42),
    );
    final progressY = size.height - 34;
    for (var index = 0; index < WindDartsRules.shotCount; index++) {
      final x = size.width / 2 + (index - 3) * 13;
      canvas.drawCircle(
        Offset(x, progressY),
        index == WindDartsRules.shotCount - 1 ? 4 : 3,
        Paint()
          ..color = index == WindDartsRules.shotCount - 1
              ? const Color(0xFFFFD36A)
              : const Color(0xFFB7A181),
      );
    }
    _paintCenteredText(
      canvas,
      '7R',
      centerX: size.width / 2,
      y: progressY - 17,
      fontSize: 8,
    );
  }

  void _drawScoringLedger(Canvas canvas, Size size, WindDartsArtImages loaded) {
    final ledgerSize = Size(
      math.min(108, math.max(84, size.width * .27)),
      math.min(132, math.max(116, size.height * .56)),
    );
    final offset = Offset(4, size.height - ledgerSize.height - 5);
    WindDartsArt.drawScoreParchment(
      canvas,
      loaded.scoreParchment,
      offset: offset,
      size: ledgerSize,
    );
    const ink = Color(0xFF3A2113);
    _paintText(canvas, 'R', offset + const Offset(9, 12), 8, color: ink);
    _paintText(canvas, '나', offset + const Offset(36, 12), 8, color: ink);
    _paintText(canvas, '상대', offset + const Offset(59, 12), 8, color: ink);
    for (var index = 0; index < WindDartsRules.shotCount; index++) {
      final y = 27.0 + index * 11.5;
      _paintText(
        canvas,
        index == WindDartsRules.shotCount - 1 ? '7R' : '${index + 1}',
        offset + Offset(7, y),
        8,
        color: ink,
      );
      _paintText(
        canvas,
        '${_previewPlayerScores[index]}',
        offset + Offset(34, y),
        8,
        color: ink,
      );
      _paintText(
        canvas,
        '${_previewOpponentScores[index]}',
        offset + Offset(61, y),
        8,
        color: ink,
      );
    }
    _paintText(
      canvas,
      '총합 333 / 93',
      offset + const Offset(8, 111),
      8,
      color: ink,
    );
    _paintCenteredText(
      canvas,
      'TRIPLE 20 · 60 × GOLD 2 = 120점',
      centerX: size.width * .66,
      y: size.height - 34,
      fontSize: 9,
    );
    _paintCenteredText(
      canvas,
      'S-BULL 25 · D-BULL 50 · MISS 0',
      centerX: size.width * .66,
      y: size.height - 20,
      fontSize: 8,
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

  void _paintCenteredText(
    Canvas canvas,
    String text, {
    required double centerX,
    required double y,
    required double fontSize,
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
    final left = (centerX - painter.width / 2)
        .clamp(4.0, previewSize.width - painter.width - 4)
        .toDouble();
    painter.paint(canvas, Offset(left, y));
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
      shotIndex != oldDelegate.shotIndex ||
      goldenDart != oldDelegate.goldenDart ||
      center != oldDelegate.center ||
      radius != oldDelegate.radius ||
      cameraZoom != oldDelegate.cameraZoom ||
      phase != oldDelegate.phase ||
      flightProgress != oldDelegate.flightProgress ||
      impactProgress != oldDelegate.impactProgress ||
      flightStart != oldDelegate.flightStart ||
      flightTarget != oldDelegate.flightTarget ||
      targetWorldOffset != oldDelegate.targetWorldOffset ||
      windLanding != oldDelegate.windLanding ||
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
