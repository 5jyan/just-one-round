import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_one_round/features/games/ramen_timer/domain/ramen_timer_rules.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

enum RamenTimerPreviewScene { home, calibration, checkpoints, result }

/// A deterministic, compressed demonstration of the real 10/20/30 second
/// recipe. Every visual state is derived from the same wrapped frame so the
/// home card can loop without leaving a stale target, cup, or result behind.
class RamenTimerPreviewSnapshot {
  const RamenTimerPreviewSnapshot({
    required this.frame,
    required this.elapsedMilliseconds,
    required this.tapCount,
    required this.cupFrame,
    required this.idleFrame,
    required this.poseFrame,
    required this.timerText,
    required this.checkpointDeltaText,
    required this.clockCovered,
    required this.smokeProgress,
    required this.resultVisible,
    required this.ingredientFrame,
    required this.ingredientProgress,
    required this.inputReady,
    required this.caption,
  });

  /// One frame is 500ms of demonstrated game time and 100ms of animation
  /// time. The full sequence therefore takes eight seconds to watch.
  static const frameCount = 80;
  static const frameMilliseconds = 500;

  static const calibrationGuide = RamenTimerPreviewSnapshot(
    frame: 25,
    elapsedMilliseconds: 10000,
    tapCount: 1,
    cupFrame: 1,
    idleFrame: 0,
    poseFrame: 0,
    timerText: '??.??초',
    checkpointDeltaText: '-0.18초',
    clockCovered: true,
    smokeProgress: 1,
    resultVisible: false,
    ingredientFrame: -1,
    ingredientProgress: 0,
    inputReady: true,
    caption: '누른 뒤 목표와의 차이 확인',
  );

  static const checkpointsGuide = RamenTimerPreviewSnapshot(
    frame: 41,
    elapsedMilliseconds: 20500,
    tapCount: 2,
    cupFrame: 2,
    idleFrame: 0,
    poseFrame: 3,
    timerText: '??.??초',
    checkpointDeltaText: '+0.31초',
    clockCovered: true,
    smokeProgress: 1,
    resultVisible: false,
    ingredientFrame: 3,
    ingredientProgress: 0.69,
    inputReady: true,
    caption: '20초 · 계란 넣기',
  );

  static const resultGuide = RamenTimerPreviewSnapshot(
    frame: 70,
    elapsedMilliseconds: 30000,
    tapCount: 3,
    cupFrame: 3,
    idleFrame: 0,
    poseFrame: 5,
    timerText: '??.??초',
    checkpointDeltaText: null,
    clockCovered: true,
    smokeProgress: 1,
    resultVisible: true,
    ingredientFrame: -1,
    ingredientProgress: 0,
    inputReady: false,
    caption: '세 오차를 더해요',
  );

  final int frame;
  final int elapsedMilliseconds;
  final int tapCount;
  final int cupFrame;
  final int idleFrame;
  final int poseFrame;
  final String timerText;
  final String? checkpointDeltaText;
  final bool clockCovered;
  final double smokeProgress;
  final bool resultVisible;
  final int ingredientFrame;
  final double ingredientProgress;
  final bool inputReady;
  final String caption;

  bool get hasCheckpointFeedback => checkpointDeltaText != null;

  String get stageLabel => switch (tapCount) {
    0 => '10초·파 넣기',
    1 => '20초·계란 넣기',
    2 => '30초·뚜껑 열기',
    _ => '완성 · 결과 확인',
  };

  factory RamenTimerPreviewSnapshot.forFrame(int rawFrame) {
    final frame = ((rawFrame % frameCount) + frameCount) % frameCount;
    final elapsedMilliseconds = frame * frameMilliseconds;
    final tapCount = switch (frame) {
      < 20 => 0,
      < 40 => 1,
      < 60 => 2,
      _ => 3,
    };
    final resultVisible = frame >= 64;
    final clockCovered =
        elapsedMilliseconds >= RamenTimerRules.calibrationVisibleMilliseconds;
    final inputReady =
        elapsedMilliseconds >= RamenTimerRules.inputUnlockMilliseconds &&
        !resultVisible;
    var actionIndex = -1;
    var actionTargetMilliseconds = 0;
    for (
      var index = 0;
      index < RamenTimerRules.targetMilliseconds.length;
      index++
    ) {
      final target = RamenTimerRules.targetMilliseconds[index];
      if (elapsedMilliseconds >= target &&
          elapsedMilliseconds <
              target + RamenTimerRules.ingredientEventMilliseconds) {
        actionIndex = index;
        actionTargetMilliseconds = target;
        break;
      }
    }
    final actionFrame = actionIndex < 0 ? -1 : 20 + actionIndex * 20;
    final ingredientFrame = switch (actionIndex) {
      0 => 2,
      1 => 3,
      _ => -1,
    };
    final ingredientProgress = actionIndex < 0
        ? 0.0
        : ((elapsedMilliseconds - actionTargetMilliseconds) /
                  RamenTimerRules.ingredientEventMilliseconds)
              .clamp(0.0, 1.0);
    final poseFrame = resultVisible
        ? 5
        : tapCount >= 3
        ? 4
        : switch (actionIndex) {
            0 => 2,
            1 => 3,
            _ when !clockCovered && elapsedMilliseconds >= 2000 => 0,
            _ => -1,
          };
    final cupFrame = resultVisible || tapCount >= 3
        ? 3
        : actionIndex >= 0 && actionIndex < 2
        ? actionIndex + 1
        : 0;
    final smokeProgress = clockCovered
        ? ((elapsedMilliseconds -
                      RamenTimerRules.calibrationVisibleMilliseconds) /
                  1000)
              .clamp(0.0, 1.0)
        : 0.0;
    final checkpointDeltaText = switch (frame) {
      >= 20 && < 24 => '-0.18초',
      >= 40 && < 44 => '+0.31초',
      _ => null,
    };
    final timerText = !clockCovered
        ? RamenTimerRules.formatMilliseconds(elapsedMilliseconds)
        : '??.??초';
    final caption = resultVisible
        ? '세 오차를 더해요'
        : actionFrame == 20
        ? '10초 · 파 넣기'
        : actionFrame == 40
        ? '20초 · 계란 넣기'
        : actionFrame == 60
        ? '30초 · 뚜껑 열기'
        : !inputReady
        ? '처음 3초는 시계를 봐요'
        : switch (tapCount) {
            0 => '10초 · 파 넣기',
            1 => '20초 · 계란 넣기',
            _ => '30초 · 뚜껑 열기',
          };

    return RamenTimerPreviewSnapshot(
      frame: frame,
      elapsedMilliseconds: elapsedMilliseconds,
      tapCount: tapCount,
      cupFrame: cupFrame,
      idleFrame: (frame ~/ 2) % 4,
      poseFrame: poseFrame,
      timerText: timerText,
      checkpointDeltaText: checkpointDeltaText,
      clockCovered: clockCovered,
      smokeProgress: smokeProgress,
      resultVisible: resultVisible,
      ingredientFrame: ingredientFrame,
      ingredientProgress: ingredientProgress,
      inputReady: inputReady,
      caption: caption,
    );
  }
}

class RamenTimerPreview extends StatefulWidget {
  const RamenTimerPreview({
    required this.scene,
    this.animate = true,
    this.initialFrame = 0,
    super.key,
  });

  final RamenTimerPreviewScene scene;
  final bool animate;
  final int initialFrame;

  @override
  State<RamenTimerPreview> createState() => _RamenTimerPreviewState();
}

class _RamenTimerPreviewState extends State<RamenTimerPreview> {
  Timer? _timer;
  late var _frame = widget.initialFrame;

  bool get _isGuide => widget.scene != RamenTimerPreviewScene.home;
  double get _canvasHeight => _isGuide ? 246 : 460;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() => _frame++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshotForScene();
    return ClipRect(
      child: ColoredBox(
        key: widget.scene == RamenTimerPreviewScene.home
            ? const Key('ramen-timer-home-animation')
            : Key('ramen-timer-guide-${widget.scene.name}'),
        color: const Color(0xFF0C2427),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 360,
            height: _canvasHeight,
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  _background(),
                  if (_isGuide &&
                      widget.scene == RamenTimerPreviewScene.checkpoints)
                    _stageStrip(snapshot),
                  if (!(_isGuide &&
                      (widget.scene == RamenTimerPreviewScene.checkpoints ||
                          widget.scene == RamenTimerPreviewScene.result)))
                    _clockPanel(snapshot),
                  if (!_isGuide) _topProgress(snapshot),
                  _raccoon(snapshot),
                  _counter(),
                  _caption(snapshot),
                  _cup(snapshot),
                  if (snapshot.ingredientFrame >= 0) _ingredient(snapshot),
                  if (snapshot.clockCovered && !snapshot.resultVisible)
                    _steam(snapshot),
                  if (snapshot.resultVisible) _resultPanel(),
                  if (!_isGuide) _button(snapshot),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  RamenTimerPreviewSnapshot _snapshotForScene() => switch (widget.scene) {
    RamenTimerPreviewScene.home => RamenTimerPreviewSnapshot.forFrame(_frame),
    RamenTimerPreviewScene.calibration =>
      RamenTimerPreviewSnapshot.calibrationGuide,
    RamenTimerPreviewScene.checkpoints =>
      RamenTimerPreviewSnapshot.checkpointsGuide,
    RamenTimerPreviewScene.result => RamenTimerPreviewSnapshot.resultGuide,
  };

  Widget _background() => Positioned(
    left: 0,
    top: -150,
    width: 360,
    height: 800,
    child: Image.asset(
      'assets/images/ramen_timer/office_background.png',
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    ),
  );

  Rect _clockRect() {
    if (!_isGuide) return const Rect.fromLTWH(80, 50, 200, 88);
    return switch (widget.scene) {
      RamenTimerPreviewScene.calibration => const Rect.fromLTWH(
        80,
        12,
        200,
        82,
      ),
      _ => const Rect.fromLTWH(80, 10, 200, 82),
    };
  }

  Rect _raccoonRect() {
    if (!_isGuide) {
      return const Rect.fromLTWH(30, 160, 190, 214);
    }
    return switch (widget.scene) {
      RamenTimerPreviewScene.calibration => const Rect.fromLTWH(
        20,
        100,
        160,
        174,
      ),
      RamenTimerPreviewScene.checkpoints => const Rect.fromLTWH(
        20,
        62,
        160,
        174,
      ),
      RamenTimerPreviewScene.result => const Rect.fromLTWH(20, 74, 160, 174),
      RamenTimerPreviewScene.home => const Rect.fromLTWH(30, 160, 190, 214),
    };
  }

  Rect _cupRect() {
    if (!_isGuide) return const Rect.fromLTWH(207, 258, 126, 126);
    return switch (widget.scene) {
      RamenTimerPreviewScene.calibration => const Rect.fromLTWH(
        207,
        128,
        112,
        112,
      ),
      RamenTimerPreviewScene.checkpoints => const Rect.fromLTWH(
        207,
        126,
        112,
        112,
      ),
      RamenTimerPreviewScene.result => const Rect.fromLTWH(207, 126, 112, 112),
      RamenTimerPreviewScene.home => const Rect.fromLTWH(207, 258, 126, 126),
    };
  }

  Rect _counterRect() => _isGuide
      ? const Rect.fromLTWH(0, 210, 360, 144)
      : const Rect.fromLTWH(0, 362, 360, 144);

  Widget _clockPanel(RamenTimerPreviewSnapshot snapshot) {
    final rect = _clockRect();
    final beat = snapshot.clockCovered
        ? 3
        : (snapshot.elapsedMilliseconds ~/ 1000).clamp(0, 3);
    return Positioned.fromRect(
      rect: rect,
      child: Container(
        key: const Key('ramen-timer-preview-clock-panel'),
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        decoration: BoxDecoration(
          color: const Color(0xF01B555A),
          border: Border.all(color: const Color(0xFF8BE0C7), width: 2),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x6600181A), offset: Offset(0, 5)),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const WordSafeText(
                  'RAMEN TIMER',
                  style: TextStyle(
                    color: Color(0xFFB9F0D7),
                    fontFamily: 'Galmuri',
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!snapshot.inputReady && !snapshot.clockCovered)
                  const WordSafeText(
                    '감각 준비',
                    style: TextStyle(
                      color: Color(0xFFFFD77E),
                      fontFamily: 'Galmuri',
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1C6),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFE4C47B), width: 2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: WordSafeText(
                        snapshot.timerText,
                        key: const Key('ramen-timer-preview-clock'),
                        style: TextStyle(
                          color: snapshot.clockCovered
                              ? const Color(0xFF6A8480)
                              : const Color(0xFF126A6C),
                          fontFamily: 'Galmuri',
                          fontSize: _isGuide ? 22 : 26,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                    if (snapshot.checkpointDeltaText case final delta?)
                      Align(
                        alignment: Alignment.topCenter,
                        child: WordSafeText(
                          delta,
                          key: const Key('ramen-timer-preview-delta'),
                          style: const TextStyle(
                            color: Color(0xFFE94C4C),
                            fontFamily: 'Galmuri',
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (index) => Container(
                  width: 28,
                  height: 5,
                  margin: EdgeInsets.only(left: index == 0 ? 0 : 5),
                  decoration: BoxDecoration(
                    color: index < beat
                        ? const Color(0xFFFFD77E)
                        : const Color(0xFF4A7B7A),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _steam(RamenTimerPreviewSnapshot snapshot) {
    final clock = _clockRect();
    final cup = _cupRect();
    final seed = snapshot.frame / RamenTimerPreviewSnapshot.frameCount;
    final particles = <Widget>[];

    for (var index = 0; index < 7; index++) {
      final rawProgress = (seed * (7.2 + index * 0.43) + index * 0.13) % 1;
      final progress = rawProgress * snapshot.smokeProgress;
      final rise = Curves.easeOutCubic.transform(progress);
      final drift =
          math.sin((rawProgress + index * 0.31) * math.pi * 2) *
          (5 + index % 3 * 3);
      final x =
          cup.center.dx + (clock.center.dx - cup.center.dx) * rise + drift;
      final y = cup.top + 6 + (clock.bottom - cup.top - 8) * rise;
      final size = 22 + rise * (18 + index % 2 * 7);
      final opacity = (math.sin(rawProgress * math.pi).clamp(0.0, 1.0) * 0.58)
          .clamp(0.0, 1.0);
      particles.add(
        Positioned(
          left: x - size / 2,
          top: y - size / 2,
          width: size,
          height: size,
          child: Opacity(
            opacity: opacity,
            child: _RamenAtlasFrame(
              asset: 'assets/images/ramen_timer/ramen_fx_atlas.png',
              columns: 3,
              rows: 2,
              frame: index % 2,
            ),
          ),
        ),
      );
    }

    final veilAlpha = (snapshot.smokeProgress * 0.34).clamp(0.0, 1.0);
    return Positioned.fill(
      key: const Key('ramen-timer-preview-steam'),
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ...particles,
            if (!snapshot.hasCheckpointFeedback &&
                !(_isGuide &&
                    widget.scene == RamenTimerPreviewScene.checkpoints))
              Positioned(
                left: clock.left + 2,
                top: clock.top + 31,
                width: clock.width - 4,
                height: 38,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(
                            0xFFD5E6D9,
                          ).withValues(alpha: veilAlpha),
                        ),
                      ),
                      for (var index = 0; index < 8; index++)
                        Positioned(
                          left:
                              -24 +
                              ((seed * (31 + index * 2) + index * 0.19) % 1) *
                                  (clock.width + 24),
                          top: -3 + (index % 3) * 11,
                          width: 22 + (index % 4) * 6,
                          height: 22 + (index % 4) * 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F3E6).withValues(
                                alpha: snapshot.smokeProgress * 0.20,
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _raccoon(RamenTimerPreviewSnapshot snapshot) {
    final rect = _raccoonRect();
    return Positioned.fromRect(
      rect: rect,
      child: _RamenAtlasFrame(
        asset: snapshot.poseFrame >= 0
            ? 'assets/images/ramen_timer/raccoon_pose_atlas.png'
            : 'assets/images/ramen_timer/raccoon_idle_sheet.png',
        columns: 4,
        rows: snapshot.poseFrame >= 0 ? 2 : 1,
        frame: snapshot.poseFrame >= 0
            ? snapshot.poseFrame
            : snapshot.idleFrame,
      ),
    );
  }

  Widget _counter() {
    final rect = _counterRect();
    return Positioned.fromRect(
      rect: rect,
      child: Image.asset(
        'assets/images/ramen_timer/counter_front.png',
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }

  Widget _cup(RamenTimerPreviewSnapshot snapshot) {
    final rect = _cupRect();
    if (snapshot.resultVisible) {
      return Positioned.fromRect(
        rect: rect,
        child: _RamenAtlasFrame(
          asset: 'assets/images/ramen_timer/ramen_result_atlas.png',
          columns: 3,
          rows: 1,
          frame: 0,
        ),
      );
    }
    return Positioned.fromRect(
      rect: rect,
      child: _RamenAtlasFrame(
        asset: 'assets/images/ramen_timer/ramen_cup_atlas.png',
        columns: 4,
        rows: 1,
        frame: snapshot.cupFrame,
      ),
    );
  }

  Widget _ingredient(RamenTimerPreviewSnapshot snapshot) {
    final cup = _cupRect();
    final progress = Curves.easeOut.transform(snapshot.ingredientProgress);
    return Positioned(
      left: cup.center.dx - 24,
      top: cup.top - 48 + (cup.height * progress),
      width: 48,
      height: 48,
      child: Opacity(
        opacity: (1 - snapshot.ingredientProgress * 0.2).clamp(0.0, 1.0),
        child: _RamenAtlasFrame(
          asset: 'assets/images/ramen_timer/ramen_fx_atlas.png',
          columns: 3,
          rows: 2,
          frame: snapshot.ingredientFrame,
        ),
      ),
    );
  }

  Widget _stageStrip(RamenTimerPreviewSnapshot snapshot) => Positioned(
    left: 9,
    right: 9,
    top: 9,
    height: 49,
    child: Row(
      children: [
        _stageNode(
          '10초·파 넣기',
          snapshot.tapCount > 0 ? '완료' : '첫 목표',
          snapshot.tapCount > 0
              ? const Color(0xFF8BE0C7)
              : const Color(0xFFFFD77E),
        ),
        _stageArrow(),
        _stageNode(
          '20초·계란 넣기',
          snapshot.tapCount > 1 ? '완료' : '다음',
          snapshot.tapCount > 1
              ? const Color(0xFF8BE0C7)
              : const Color(0xFFFFD77E),
        ),
        _stageArrow(),
        _stageNode(
          '30초·뚜껑 열기',
          snapshot.tapCount > 2 ? '완료' : '마지막',
          snapshot.tapCount > 2
              ? const Color(0xFF8BE0C7)
              : const Color(0xFFFFD77E),
        ),
      ],
    ),
  );

  Widget _stageArrow() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 2),
    child: WordSafeText(
      '›',
      style: TextStyle(
        color: Color(0xFFFFF1C6),
        fontFamily: 'Galmuri',
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    ),
  );

  Widget _stageNode(String label, String status, Color accent) => Expanded(
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xE51B555A),
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          WordSafeText(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFFF1C6),
              fontFamily: 'Galmuri',
              fontSize: 8,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          WordSafeText(
            status,
            style: TextStyle(
              color: accent,
              fontFamily: 'Galmuri',
              fontSize: 7,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _topProgress(RamenTimerPreviewSnapshot snapshot) => Positioned(
    left: 16,
    right: 16,
    top: 10,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _previewHudBadge(
          label: snapshot.resultVisible ? '완성' : '다음 동작',
          value: snapshot.stageLabel,
          accent: const Color(0xFFFFD77E),
        ),
        _previewHudBadge(
          label: '진행',
          value: '${snapshot.tapCount} / 3',
          valueKey: const Key('ramen-timer-preview-progress'),
          accent: const Color(0xFFB9F0D7),
        ),
      ],
    ),
  );

  Widget _previewHudBadge({
    required String label,
    required String value,
    required Color accent,
    Key? valueKey,
  }) => Container(
    constraints: const BoxConstraints(minWidth: 96, maxWidth: 174),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xE51B555A),
      border: Border.all(color: const Color(0xFF8BE0C7), width: 2),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WordSafeText(
          label,
          style: const TextStyle(
            color: Color(0xFFB9F0D7),
            fontFamily: 'Galmuri',
            fontSize: 7,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        WordSafeText(
          value,
          key: valueKey,
          style: TextStyle(
            color: accent,
            fontFamily: 'Galmuri',
            fontSize: 11,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
      ],
    ),
  );

  Widget _caption(RamenTimerPreviewSnapshot snapshot) => Positioned(
    left: _isGuide ? 18 : 24,
    right: _isGuide ? 18 : 24,
    bottom: _isGuide ? 0 : 88,
    height: _isGuide ? 22 : 30,
    child: Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xE51B555A),
        border: Border.all(color: const Color(0xFF8BE0C7), width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: WordSafeText(
        snapshot.caption,
        style: TextStyle(
          color: snapshot.resultVisible
              ? const Color(0xFFFFD77E)
              : const Color(0xFFFFF1C6),
          fontFamily: 'Galmuri',
          fontSize: _isGuide ? 9 : 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );

  Widget _button(RamenTimerPreviewSnapshot snapshot) {
    final label = snapshot.resultVisible ? '완성! 결과 확인' : snapshot.stageLabel;
    return Positioned(
      left: 24,
      right: 24,
      bottom: 13,
      height: 66,
      child: Container(
        key: const Key('ramen-timer-preview-demo-button'),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD77E),
          border: Border.all(color: const Color(0xFF16484B), width: 3),
          borderRadius: BorderRadius.circular(19),
          boxShadow: const [
            BoxShadow(color: Color(0xFF9A6251), offset: Offset(0, 5)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            WordSafeText(
              label,
              style: const TextStyle(
                color: Color(0xFF16484B),
                fontFamily: 'Galmuri',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            const WordSafeText(
              '빠르게 보는 플레이 예시 · 실제 30초 압축',
              key: Key('ramen-timer-preview-demo-label'),
              style: TextStyle(
                color: Color(0xFF5E4938),
                fontFamily: 'Galmuri',
                fontSize: 8,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultPanel() => Positioned(
    left: _isGuide ? 20 : 18,
    right: _isGuide ? 20 : 18,
    top: _isGuide ? 58 : 40,
    height: _isGuide ? 76 : 96,
    child: Container(
      key: const Key('ramen-timer-preview-result'),
      padding: EdgeInsets.symmetric(
        horizontal: _isGuide ? 9 : 13,
        vertical: _isGuide ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xF01B555A),
        border: Border.all(color: const Color(0xFF8BE0C7), width: 2),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x6600181A), offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          const WordSafeText(
            '세 단계 완료',
            style: TextStyle(
              color: Color(0xFFB9F0D7),
              fontFamily: 'Galmuri',
              fontSize: 9,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          WordSafeText(
            '총 오차 0.59초',
            style: TextStyle(
              color: const Color(0xFFFFD77E),
              fontFamily: 'Galmuri',
              fontSize: _isGuide ? 18 : 21,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RamenAtlasFrame extends StatelessWidget {
  const _RamenAtlasFrame({
    required this.asset,
    required this.columns,
    required this.rows,
    required this.frame,
  });

  final String asset;
  final int columns;
  final int rows;
  final int frame;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final safeFrame = frame.clamp(0, columns * rows - 1);
        final column = safeFrame % columns;
        final row = safeFrame ~/ columns;
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -column * width,
                top: -row * height,
                width: width * columns,
                height: height * rows,
                child: Image.asset(
                  asset,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
