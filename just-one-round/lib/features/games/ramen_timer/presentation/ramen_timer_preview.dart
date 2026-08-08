import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum RamenTimerPreviewScene { home, calibration, checkpoints, result }

class RamenTimerPreviewSnapshot {
  const RamenTimerPreviewSnapshot({
    required this.frame,
    required this.tapCount,
    required this.idleFrame,
    required this.poseFrame,
    required this.timerText,
    required this.clockCovered,
    required this.clockPeekStrength,
    required this.smokeProgress,
    required this.resultVisible,
    required this.ingredientFrame,
    required this.ingredientProgress,
    required this.caption,
  });

  static const frameCount = 60;

  static const calibrationGuide = RamenTimerPreviewSnapshot(
    frame: 30,
    tapCount: 1,
    idleFrame: 1,
    poseFrame: -1,
    timerText: '12.50초',
    clockCovered: true,
    clockPeekStrength: 1,
    smokeProgress: 1,
    resultVisible: false,
    ingredientFrame: -1,
    ingredientProgress: 0,
    caption: '1 / 3 · 다음 목표 20초',
  );

  static const checkpointsGuide = RamenTimerPreviewSnapshot(
    frame: 36,
    tapCount: 2,
    idleFrame: 2,
    poseFrame: 3,
    timerText: '??.??초',
    clockCovered: true,
    clockPeekStrength: 0,
    smokeProgress: 1,
    resultVisible: false,
    ingredientFrame: 3,
    ingredientProgress: 0.5,
    caption: '2 / 3 · 마지막 30초!',
  );

  static const resultGuide = RamenTimerPreviewSnapshot(
    frame: 54,
    tapCount: 3,
    idleFrame: 3,
    poseFrame: 7,
    timerText: '??.??초',
    clockCovered: true,
    clockPeekStrength: 0,
    smokeProgress: 1,
    resultVisible: true,
    ingredientFrame: -1,
    ingredientProgress: 0,
    caption: '총 오차가 작을수록 승리!',
  );

  final int frame;
  final int tapCount;
  final int idleFrame;
  final int poseFrame;
  final String timerText;
  final bool clockCovered;
  final double clockPeekStrength;
  final double smokeProgress;
  final bool resultVisible;
  final int ingredientFrame;
  final double ingredientProgress;
  final String caption;

  factory RamenTimerPreviewSnapshot.forFrame(int rawFrame) {
    final frame = rawFrame % frameCount;
    if (frame < 30) {
      final seconds = frame ~/ 10 + 1;
      return RamenTimerPreviewSnapshot(
        frame: frame,
        tapCount: 0,
        idleFrame: (frame ~/ 5) % 4,
        poseFrame: -1,
        timerText: '$seconds.00초',
        clockCovered: false,
        clockPeekStrength: 0,
        smokeProgress: 0,
        resultVisible: false,
        ingredientFrame: -1,
        ingredientProgress: 0,
        caption: '1·2·3초 박자를 익혀요',
      );
    }
    return RamenTimerPreviewSnapshot(
      frame: frame,
      tapCount: 0,
      idleFrame: 0,
      poseFrame: frame < 37 ? 1 : -1,
      timerText: '??.??초',
      clockCovered: true,
      clockPeekStrength: 0,
      smokeProgress: ((frame - 30) / 7).clamp(0.0, 1.0),
      resultVisible: false,
      ingredientFrame: -1,
      ingredientProgress: 0,
      caption: '10초라고 느끼면 찍기!',
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
    return ColoredBox(
      key: widget.scene == RamenTimerPreviewScene.home
          ? const Key('ramen-timer-home-animation')
          : Key('ramen-timer-guide-${widget.scene.name}'),
      color: const Color(0xFF071224),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 360,
          height: _isGuide ? 246 : 460,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                top: -170,
                width: 360,
                height: 800,
                child: Image.asset(
                  'assets/images/ramen_timer/office_background.png',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                  excludeFromSemantics: true,
                ),
              ),
              if (snapshot.resultVisible) _resultPanel(),
              _timerPanel(snapshot),
              if (_isGuide &&
                  widget.scene == RamenTimerPreviewScene.checkpoints)
                _checkpointStrip(),
              _raccoon(snapshot),
              Positioned(
                left: 0,
                top: _isGuide ? 196 : 304,
                width: 360,
                height: 144,
                child: Image.asset(
                  'assets/images/ramen_timer/counter_front.png',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                  excludeFromSemantics: true,
                ),
              ),
              _cup(snapshot),
              if (snapshot.ingredientFrame >= 0) _ingredient(snapshot),
              if (snapshot.clockCovered && !snapshot.resultVisible)
                _steam(snapshot),
              if (!(_isGuide && widget.scene == RamenTimerPreviewScene.result))
                _topProgress(snapshot),
              if (!(_isGuide && widget.scene == RamenTimerPreviewScene.result))
                _button(snapshot),
            ],
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

  Widget _timerPanel(RamenTimerPreviewSnapshot snapshot) {
    if (snapshot.resultVisible ||
        (_isGuide && widget.scene == RamenTimerPreviewScene.checkpoints)) {
      return const SizedBox.shrink();
    }
    final beat = snapshot.clockCovered
        ? 3
        : (snapshot.frame ~/ 10 + 1).clamp(1, 3);
    return Positioned(
      left: 82,
      top: _isGuide ? 44 : 70,
      width: 196,
      height: _isGuide ? 86 : 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF13283B),
                border: Border.all(color: const Color(0xFF49677A), width: 3),
                boxShadow: const [
                  BoxShadow(color: Color(0xB3000710), offset: Offset(4, 5)),
                ],
              ),
              child: Stack(
                children: [
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 6,
                    child: Text(
                      'RAMEN TIMER',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF91ABBA),
                        fontFamily: 'Galmuri',
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 24,
                    height: 39,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF081621),
                        border: Border.all(
                          color: const Color(0xFF29485B),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        snapshot.timerText,
                        key: const Key('ramen-timer-preview-clock'),
                        style: TextStyle(
                          color: !snapshot.clockCovered
                              ? const Color(0xFFFFE18A)
                              : snapshot.clockPeekStrength > 0
                              ? const Color(0xFFFFE18A).withValues(
                                  alpha:
                                      0.26 + snapshot.clockPeekStrength * 0.58,
                                )
                              : const Color(0xFFCED7DB),
                          fontFamily: 'Galmuri',
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 48,
                    right: 48,
                    bottom: 8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        3,
                        (index) => Container(
                          width: 24,
                          height: 8,
                          color: index < beat
                              ? const Color(0xFFFFC85C)
                              : const Color(0xFF29465A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _steam(RamenTimerPreviewSnapshot snapshot) {
    final timerTop = _isGuide ? 44.0 : 70.0;
    final cupTop = _isGuide ? 138.0 : 240.0;
    final seed = snapshot.frame / RamenTimerPreviewSnapshot.frameCount;
    final particles = <Widget>[];

    for (var index = 0; index < 7; index++) {
      final rawProgress = (seed * (8.4 + index * 0.37) + index * 0.16) % 1;
      final progress = rawProgress * snapshot.smokeProgress;
      final rise = Curves.easeOutCubic.transform(progress);
      final drift =
          math.sin((rawProgress + index * 0.31) * math.pi * 2) *
          (4 + index % 3 * 2);
      final x = 234 + (154 + index % 4 * 26 - 234) * rise + drift;
      final y = cupTop + 10 + (timerTop + 5 + index % 3 * 8 - cupTop) * rise;
      final size = 22 + rise * (20 + index % 2 * 6);
      final opacity =
          math.sin(rawProgress * math.pi).clamp(0.0, 1.0) *
          (0.66 - snapshot.clockPeekStrength * 0.14);
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

    final veilAlpha =
        snapshot.smokeProgress * (0.38 - snapshot.clockPeekStrength * 0.30);
    return Positioned.fill(
      key: const Key('ramen-timer-preview-steam'),
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ...particles,
            Positioned(
              left: 94,
              top: timerTop + 24,
              width: 172,
              height: 39,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: const Color(
                          0xFFD3DDD7,
                        ).withValues(alpha: veilAlpha),
                      ),
                    ),
                    for (var index = 0; index < 9; index++)
                      Positioned(
                        left:
                            -24 +
                            ((seed * (43 + index * 2) + index * 0.17) % 1) *
                                214,
                        top: -3 + (index % 3) * 12,
                        width: 20 + (index % 4) * 7,
                        height: 20 + (index % 4) * 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7ECE8).withValues(
                              alpha:
                                  snapshot.smokeProgress *
                                  (0.28 - snapshot.clockPeekStrength * 0.22),
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    for (var index = 0; index < 3; index++)
                      Positioned(
                        left:
                            4 +
                            index * 56 +
                            math.sin(
                                  (seed * (11 + index) + index) * math.pi * 2,
                                ) *
                                8,
                        top: -2 + (index % 2) * 4,
                        width: 40,
                        height: 40,
                        child: Opacity(
                          opacity:
                              snapshot.smokeProgress *
                              (0.58 - snapshot.clockPeekStrength * 0.40),
                          child: _RamenAtlasFrame(
                            asset:
                                'assets/images/ramen_timer/ramen_fx_atlas.png',
                            columns: 3,
                            rows: 2,
                            frame: index % 2,
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
    final (left, top, size) = switch (widget.scene) {
      RamenTimerPreviewScene.calibration => (84.0, 110.0, 96.0),
      RamenTimerPreviewScene.checkpoints => (86.0, 100.0, 96.0),
      RamenTimerPreviewScene.result => (82.0, 124.0, 96.0),
      RamenTimerPreviewScene.home => (
        94.0,
        snapshot.resultVisible ? 208.0 : 202.0,
        96.0,
      ),
    };
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
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

  Widget _cup(RamenTimerPreviewSnapshot snapshot) {
    if (snapshot.resultVisible) {
      return Positioned(
        left: _isGuide ? 204 : 196,
        top: _isGuide ? 124 : 198,
        width: _isGuide ? 96 : 128,
        height: _isGuide ? 96 : 128,
        child: const _RamenAtlasFrame(
          asset: 'assets/images/ramen_timer/ramen_result_atlas.png',
          columns: 3,
          rows: 1,
          frame: 2,
        ),
      );
    }
    return Positioned(
      left: _isGuide ? 204 : 202,
      top: _isGuide
          ? widget.scene == RamenTimerPreviewScene.calibration
                ? 138
                : 132
          : 240,
      width: 64,
      height: 64,
      child: _RamenAtlasFrame(
        asset: 'assets/images/ramen_timer/ramen_cup_atlas.png',
        columns: 4,
        rows: 1,
        frame: snapshot.tapCount.clamp(0, 3),
      ),
    );
  }

  Widget _ingredient(RamenTimerPreviewSnapshot snapshot) => Positioned(
    left: 210,
    top: (_isGuide ? 64 : 166) + 70 * snapshot.ingredientProgress,
    width: 48,
    height: 48,
    child: _RamenAtlasFrame(
      asset: 'assets/images/ramen_timer/ramen_fx_atlas.png',
      columns: 3,
      rows: 2,
      frame: snapshot.ingredientFrame,
    ),
  );

  Widget _checkpointStrip() => Positioned(
    left: 30,
    right: 30,
    top: 48,
    height: 44,
    child: Row(
      children: [
        _checkpointNode('10초', '완료', const Color(0xFF6FD8D2)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: Text(
            '▶',
            style: TextStyle(
              color: Color(0xFF718D9D),
              fontFamily: 'Galmuri',
              fontSize: 12,
            ),
          ),
        ),
        _checkpointNode('20초', '완료', const Color(0xFF6FD8D2)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: Text(
            '▶',
            style: TextStyle(
              color: Color(0xFF718D9D),
              fontFamily: 'Galmuri',
              fontSize: 12,
            ),
          ),
        ),
        _checkpointNode('30초', '목표', const Color(0xFFFFD45F)),
      ],
    ),
  );

  Widget _checkpointNode(String label, String status, Color accent) => Expanded(
    child: Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xED102536),
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE9F0EC),
              fontFamily: 'Galmuri',
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            status,
            style: TextStyle(
              color: accent,
              fontFamily: 'Galmuri',
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _topProgress(RamenTimerPreviewSnapshot snapshot) {
    final nextTarget = snapshot.resultVisible
        ? '공개'
        : snapshot.tapCount == 0
        ? '10초'
        : snapshot.tapCount == 1
        ? '20초'
        : '30초';
    return Positioned(
      left: 18,
      right: 18,
      top: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _previewHudBadge(
            label: snapshot.resultVisible ? 'RESULT' : 'NEXT',
            value: nextTarget,
            accent: const Color(0xFFFFE18A),
          ),
          _previewHudBadge(
            label: 'PROGRESS',
            value: '${snapshot.tapCount} / 3',
            valueKey: const Key('ramen-timer-preview-progress'),
            accent: const Color(0xFFE9F0EC),
          ),
        ],
      ),
    );
  }

  Widget _previewHudBadge({
    required String label,
    required String value,
    required Color accent,
    Key? valueKey,
  }) => Container(
    constraints: const BoxConstraints(minWidth: 94),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xDE0C1C2B),
      border: Border.all(color: const Color(0xFF38576A), width: 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7895A7),
            fontFamily: 'Galmuri',
            fontSize: 7,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        Text(
          value,
          key: valueKey,
          style: TextStyle(
            color: accent,
            fontFamily: 'Galmuri',
            fontSize: 13,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
      ],
    ),
  );

  Widget _button(RamenTimerPreviewSnapshot snapshot) {
    final target = snapshot.tapCount == 0
        ? '10초'
        : snapshot.tapCount == 1
        ? '20초'
        : '30초';
    final label = snapshot.resultVisible
        ? '기록 확인 완료'
        : snapshot.tapCount >= 3
        ? '기록 여는 중...'
        : '$target 지금 찍기!';
    return Positioned(
      left: _isGuide ? 20 : 24,
      right: _isGuide ? 20 : 24,
      bottom: _isGuide ? 6 : 14,
      height: _isGuide ? 42 : 58,
      child: Container(
        decoration: BoxDecoration(
          color: snapshot.resultVisible
              ? const Color(0xFF7F9298)
              : const Color(0xFFFFD45F),
          border: Border.all(color: const Color(0xFF0D1723), width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0xFF925144), offset: Offset(0, 5)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: const Color(0xFF0D1723),
                fontFamily: 'Galmuri',
                fontSize: _isGuide ? 15 : 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (widget.scene == RamenTimerPreviewScene.home)
              Text(
                '연출 미리보기 · 실제 타이밍 아님',
                key: const Key('ramen-timer-preview-demo-label'),
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: snapshot.resultVisible
                      ? const Color(0xFFE9F0EC)
                      : const Color(0xFF5E3F34),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultPanel() => Positioned(
    left: _isGuide ? 24 : 18,
    right: _isGuide ? 24 : 18,
    top: _isGuide ? 20 : 52,
    height: _isGuide ? 102 : 138,
    child: Container(
      key: const Key('ramen-timer-preview-result'),
      padding: EdgeInsets.symmetric(
        horizontal: _isGuide ? 10 : 14,
        vertical: _isGuide ? 7 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xF014293B),
        border: Border.all(color: const Color(0xFF55758A), width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0xA8000710), offset: Offset(4, 5)),
        ],
      ),
      child: Column(
        children: [
          const Text(
            '세 기록 합산',
            style: TextStyle(
              color: Color(0xFF8EA9B8),
              fontFamily: 'Galmuri',
              fontSize: 9,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          Text(
            '총 오차 0.59초',
            style: TextStyle(
              color: const Color(0xFFFFD45F),
              fontFamily: 'Galmuri',
              fontSize: _isGuide ? 19 : 22,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          SizedBox(height: _isGuide ? 4 : 8),
          Row(
            children: [
              _errorChip('10초', '0.18초', '빠름', const Color(0xFF6FD8D2)),
              const SizedBox(width: 6),
              _errorChip('20초', '0.31초', '느림', const Color(0xFFFF8E79)),
              const SizedBox(width: 6),
              _errorChip('30초', '0.10초', '빠름', const Color(0xFF6FD8D2)),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _errorChip(
    String target,
    String error,
    String direction,
    Color accent,
  ) => Expanded(
    child: Container(
      height: _isGuide ? 39 : 47,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2232),
        border: Border.all(color: accent, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            target,
            style: const TextStyle(
              color: Color(0xFFE9F0EC),
              fontFamily: 'Galmuri',
              fontSize: 9,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          Text(
            '$error $direction',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: accent,
              fontFamily: 'Galmuri',
              fontSize: _isGuide ? 8 : 9,
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
                  filterQuality: FilterQuality.none,
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
