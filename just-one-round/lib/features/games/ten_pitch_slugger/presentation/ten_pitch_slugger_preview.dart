import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/domain/ten_pitch_slugger_rules.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_motion.dart';
import 'package:just_one_round/features/games/ten_pitch_slugger/presentation/ten_pitch_slugger_scene.dart';

enum TenPitchSluggerPreviewScene { home, tap, timing, distance, magic, score }

enum TenPitchSluggerPreviewStage { windup, flight, swing, result }

class TenPitchSluggerPreviewSnapshot {
  const TenPitchSluggerPreviewSnapshot({
    required this.frame,
    required this.stage,
    required this.pitchFrame,
    required this.batterFrame,
    required this.ballProgress,
    required this.scoreCm,
    required this.caption,
  });

  static const frameCount = 60;

  final int frame;
  final TenPitchSluggerPreviewStage stage;
  final int pitchFrame;
  final int batterFrame;
  final double ballProgress;
  final int scoreCm;
  final String caption;

  factory TenPitchSluggerPreviewSnapshot.forFrame(int rawFrame) {
    final frame = rawFrame % frameCount;
    if (frame < 14) {
      return TenPitchSluggerPreviewSnapshot(
        frame: frame,
        stage: TenPitchSluggerPreviewStage.windup,
        pitchFrame: TenPitchSluggerMotion.regularWindupFrame(frame / 14),
        batterFrame: (frame ~/ 3) % 6,
        ballProgress: 0,
        scoreCm: 0,
        caption: '4 / 10  ·  몸쪽 직구',
      );
    }
    if (frame < 35) {
      final progress = (frame - 14) / 20;
      return TenPitchSluggerPreviewSnapshot(
        frame: frame,
        stage: TenPitchSluggerPreviewStage.flight,
        pitchFrame: TenPitchSluggerMotion.regularFollowThroughFrame(
          (frame - 14) * 0.1,
        ),
        batterFrame: 0,
        ballProgress: progress.clamp(0, 1),
        scoreCm: 0,
        caption: '공을 보고 탭! 헛스윙하면 다시!',
      );
    }
    if (frame < 43) {
      return TenPitchSluggerPreviewSnapshot(
        frame: frame,
        stage: TenPitchSluggerPreviewStage.swing,
        pitchFrame: -1,
        batterFrame: TenPitchSluggerMotion.batterSwingFrame(
          (frame - 35) * 0.06,
        ),
        ballProgress: 1,
        scoreCm: 0,
        caption: '딱!',
      );
    }
    return TenPitchSluggerPreviewSnapshot(
      frame: frame,
      stage: TenPitchSluggerPreviewStage.result,
      pitchFrame: 0,
      batterFrame: ((frame - 43) ~/ 2).clamp(0, 7),
      ballProgress: 1,
      scoreCm: 11240,
      caption: '+112.4m  ·  HOME RUN!',
    );
  }
}

class TenPitchSluggerPreview extends StatefulWidget {
  const TenPitchSluggerPreview({
    required this.scene,
    this.animate = true,
    this.initialFrame = 0,
    super.key,
  });

  final TenPitchSluggerPreviewScene scene;
  final bool animate;
  final int initialFrame;

  @override
  State<TenPitchSluggerPreview> createState() => _TenPitchSluggerPreviewState();
}

class _TenPitchSluggerPreviewState extends State<TenPitchSluggerPreview> {
  Timer? _timer;
  late var _frame = widget.initialFrame;

  @override
  void initState() {
    super.initState();
    if (widget.scene == TenPitchSluggerPreviewScene.home && widget.animate) {
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
    final scene = widget.scene;
    final snapshot = TenPitchSluggerPreviewSnapshot.forFrame(
      scene == TenPitchSluggerPreviewScene.home
          ? _frame
          : _frameForScene(scene),
    );
    return ColoredBox(
      key: scene == TenPitchSluggerPreviewScene.home
          ? const Key('ten-pitch-home-animation')
          : Key('ten-pitch-guide-${scene.name}'),
      color: const Color(0xFF11152A),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 360,
          height: 460,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/ten_pitch_slugger/background_preview_v4.png',
                  fit: BoxFit.none,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.none,
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  key: const Key('ten-pitch-hitter-view-scene'),
                  painter: _TenPitchScenePainter(
                    snapshot: snapshot,
                    scene: scene,
                  ),
                ),
              ),
              ..._characterSprites(snapshot, scene),
              _scoreboard(snapshot, scene),
              ..._sceneEffects(snapshot, scene),
              Positioned(
                left: 28,
                right: 28,
                bottom: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  color: const Color(0xD911152A),
                  child: Text(
                    _caption(snapshot, scene),
                    key: const Key('ten-pitch-preview-caption'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFE28A),
                      fontFamily: 'Galmuri',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _frameForScene(TenPitchSluggerPreviewScene scene) => switch (scene) {
    TenPitchSluggerPreviewScene.home => _frame,
    TenPitchSluggerPreviewScene.tap => 28,
    TenPitchSluggerPreviewScene.timing => 32,
    TenPitchSluggerPreviewScene.distance => 48,
    TenPitchSluggerPreviewScene.magic => 30,
    TenPitchSluggerPreviewScene.score => 52,
  };

  List<Widget> _characterSprites(
    TenPitchSluggerPreviewSnapshot snapshot,
    TenPitchSluggerPreviewScene scene,
  ) {
    const previewSize = Size(360, 460);
    final pitcherBounds = TenPitchSluggerScene.pitcherSpriteBoundsFor(
      previewSize,
    );
    final batterBounds = TenPitchSluggerScene.batterSpriteBoundsFor(
      previewSize,
    );
    final magic = scene == TenPitchSluggerPreviewScene.magic;
    final pitching = magic || snapshot.pitchFrame >= 0;
    final pitcherAsset = pitching
        ? magic
              ? 'assets/images/ten_pitch_slugger/pitcher_front_magic_v3.png'
              : 'assets/images/ten_pitch_slugger/pitcher_front_pitch_v3.png'
        : 'assets/images/ten_pitch_slugger/pitcher_front_idle_v3.png';
    final pitcherColumns = pitching ? 4 : 2;
    final pitcherRows = pitching ? (magic ? 4 : 3) : 3;
    final pitcherFrame = magic
        ? 11
        : pitching
        ? snapshot.pitchFrame.clamp(0, 11)
        : snapshot.frame ~/ 3 % 6;

    final result =
        snapshot.stage == TenPitchSluggerPreviewStage.result ||
        scene == TenPitchSluggerPreviewScene.distance ||
        scene == TenPitchSluggerPreviewScene.score;
    final swinging =
        snapshot.stage == TenPitchSluggerPreviewStage.swing ||
        scene == TenPitchSluggerPreviewScene.timing;
    final batterAsset = result
        ? 'assets/images/ten_pitch_slugger/batter_rear_result_v3.png'
        : swinging
        ? 'assets/images/ten_pitch_slugger/batter_rear_swing_v4.png'
        : 'assets/images/ten_pitch_slugger/batter_rear_idle_v3.png';
    final batterColumns = result || swinging ? 4 : 2;
    final batterRows = swinging
        ? 4
        : result
        ? 2
        : 3;
    final batterFrame = result
        ? snapshot.batterFrame.clamp(0, 7)
        : swinging
        ? scene == TenPitchSluggerPreviewScene.timing
              ? TenPitchSluggerScene.batterContactFrame
              : snapshot.batterFrame.clamp(0, 15)
        : snapshot.frame ~/ 3 % 6;

    return [
      Positioned.fromRect(
        rect: pitcherBounds,
        child: _TenPitchAtlasFrame(
          asset: pitcherAsset,
          columns: pitcherColumns,
          rows: pitcherRows,
          frame: pitcherFrame,
        ),
      ),
      Positioned.fromRect(
        rect: batterBounds,
        child: _TenPitchAtlasFrame(
          asset: batterAsset,
          columns: batterColumns,
          rows: batterRows,
          frame: batterFrame,
        ),
      ),
    ];
  }

  Widget _scoreboard(
    TenPitchSluggerPreviewSnapshot snapshot,
    TenPitchSluggerPreviewScene scene,
  ) {
    final magic = scene == TenPitchSluggerPreviewScene.magic;
    final score = scene == TenPitchSluggerPreviewScene.score
        ? 12640
        : snapshot.scoreCm;
    return Positioned(
      left: 18,
      right: 18,
      top: 18,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xD911152A),
          border: Border.all(color: const Color(0xFFE9D39B), width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MAX DISTANCE',
                  style: TextStyle(
                    color: Color(0xFF9FB9B2),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${(score / 100).toStringAsFixed(1)}m',
                  key: const Key('ten-pitch-preview-score'),
                  style: const TextStyle(
                    color: Color(0xFFFFE28A),
                    fontFamily: 'Galmuri',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            Text(
              magic ? '10 / 10' : '4 / 10',
              key: const Key('ten-pitch-preview-pitch'),
              style: TextStyle(
                color: magic
                    ? const Color(0xFFC28BFF)
                    : const Color(0xFFE9E0C5),
                fontFamily: 'Galmuri',
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sceneEffects(
    TenPitchSluggerPreviewSnapshot snapshot,
    TenPitchSluggerPreviewScene scene,
  ) {
    if (scene == TenPitchSluggerPreviewScene.timing) {
      final zone = TenPitchSluggerScene.strikeZoneFor(const Size(360, 460));
      return [
        for (final item in const [(0.0, '빠름'), (0.5, '딱!'), (1.0, '느림')])
          Positioned(
            left: zone.left - 30 + item.$1 * (zone.width + 44),
            top: zone.bottom - 12,
            child: Column(
              children: [
                SizedBox(
                  width: item.$1 == 0.5 ? 24 : 17,
                  height: item.$1 == 0.5 ? 24 : 17,
                  child: _TenPitchAtlasFrame(
                    asset: 'assets/images/ten_pitch_slugger/ball_spin_v4.png',
                    columns: 3,
                    rows: 2,
                    frame: (item.$1 * 4).round(),
                  ),
                ),
                Text(
                  item.$2,
                  style: TextStyle(
                    color: item.$1 == 0.5
                        ? const Color(0xFFFFE28A)
                        : const Color(0xFFB3B7C5),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
      ];
    }

    if (scene == TenPitchSluggerPreviewScene.distance ||
        snapshot.stage == TenPitchSluggerPreviewStage.result) {
      final contact = TenPitchSluggerScene.contactFor(const Size(360, 460));
      const launchSamples = [0.20, 0.27, 0.35];
      return [
        const Positioned(
          left: 52,
          right: 52,
          top: 88,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xE611162B),
              border: Border.symmetric(
                horizontal: BorderSide(color: Color(0xFFFFD447), width: 3),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'HOME RUN!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFFE36E),
                  fontFamily: 'Galmuri',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: Color(0xFFFF6B35), offset: Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: contact.dx - 48,
          top: contact.dy - 48,
          width: 96,
          height: 96,
          child: const _TenPitchAtlasFrame(
            asset: 'assets/images/ten_pitch_slugger/hit_fx_v4.png',
            columns: 4,
            rows: 2,
            frame: 2,
          ),
        ),
        for (var index = 0; index < launchSamples.length; index++)
          _launchedPreviewBall(
            contact: contact,
            progress: launchSamples[index],
            opacity: index == launchSamples.length - 1
                ? 1
                : 0.22 + index * 0.16,
            frame: 3 + index,
          ),
      ];
    }

    if (scene == TenPitchSluggerPreviewScene.score) {
      return const [];
    }

    final progress = snapshot.ballProgress.clamp(0.0, 1.0);
    if (snapshot.stage == TenPitchSluggerPreviewStage.windup) return const [];
    const previewSize = Size(360, 460);
    final release = TenPitchSluggerScene.releaseFor(previewSize);
    final contact = TenPitchSluggerScene.contactFor(previewSize);
    final magicOffset = scene == TenPitchSluggerPreviewScene.magic
        ? math.sin(progress * math.pi * 2) * 24 * progress
        : 0.0;
    final visualProgress = TenPitchSluggerMotion.perspectiveProgress(progress);
    final center = Offset.lerp(
      release,
      contact,
      visualProgress,
    )!.translate(magicOffset, 0);
    final ballSize = 7 + 23 * visualProgress;
    return [
      if (scene == TenPitchSluggerPreviewScene.magic)
        Positioned(
          left: center.dx - 16,
          top: center.dy - 16,
          width: 32,
          height: 32,
          child: const _TenPitchAtlasFrame(
            asset: 'assets/images/ten_pitch_slugger/trail_fx_v3.png',
            columns: 4,
            rows: 2,
            frame: 3,
          ),
        ),
      Positioned(
        left: center.dx - ballSize / 2,
        top: center.dy - ballSize / 2,
        child: SizedBox(
          width: ballSize,
          height: ballSize,
          child: _TenPitchAtlasFrame(
            asset: 'assets/images/ten_pitch_slugger/ball_spin_v4.png',
            columns: 3,
            rows: 2,
            frame: snapshot.frame % 6,
          ),
        ),
      ),
      if (scene == TenPitchSluggerPreviewScene.tap)
        const Positioned(
          right: 56,
          bottom: 68,
          child: Icon(
            Icons.touch_app_rounded,
            color: Color(0xFFFFE28A),
            size: 34,
            shadows: [Shadow(color: Color(0xFF11152A), blurRadius: 4)],
          ),
        ),
    ];
  }

  Widget _launchedPreviewBall({
    required Offset contact,
    required double progress,
    required double opacity,
    required int frame,
  }) {
    final center = TenPitchSluggerMotion.launchedBallPoint(
      contact: contact,
      progress: progress,
      quality: 0.9,
      direction: 1,
      hitType: TenPitchHitType.homeRun,
    );
    final size = TenPitchSluggerMotion.launchedBallSize(
      progress,
      hitType: TenPitchHitType.homeRun,
    );
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: Opacity(
        opacity: opacity,
        child: _TenPitchAtlasFrame(
          asset: 'assets/images/ten_pitch_slugger/ball_spin_v4.png',
          columns: 3,
          rows: 2,
          frame: frame % 6,
        ),
      ),
    );
  }

  String _caption(
    TenPitchSluggerPreviewSnapshot snapshot,
    TenPitchSluggerPreviewScene scene,
  ) => switch (scene) {
    TenPitchSluggerPreviewScene.home => snapshot.caption,
    TenPitchSluggerPreviewScene.tap => '공 오기 전부터 탭! 0.3초마다 계속 스윙!',
    TenPitchSluggerPreviewScene.timing => '공과 방망이 끝이 만나는 ‘딱!’ 순간!',
    TenPitchSluggerPreviewScene.distance => '정타 중심 12% · 100m부터 HOME RUN!',
    TenPitchSluggerPreviewScene.magic => '7구부터 장타 보상 급상승 · 10구는 최대 +40m!',
    TenPitchSluggerPreviewScene.score => '10구 중 가장 긴 한 공이 최종 점수!',
  };
}

class _TenPitchScenePainter extends CustomPainter {
  const _TenPitchScenePainter({required this.snapshot, required this.scene});

  final TenPitchSluggerPreviewSnapshot snapshot;
  final TenPitchSluggerPreviewScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final magic = scene == TenPitchSluggerPreviewScene.magic;
    TenPitchSluggerScene.drawFieldGuides(canvas, size, magic: magic);
  }

  @override
  bool shouldRepaint(covariant _TenPitchScenePainter oldDelegate) =>
      oldDelegate.snapshot.frame != snapshot.frame ||
      oldDelegate.scene != scene;
}

class _TenPitchAtlasFrame extends StatelessWidget {
  const _TenPitchAtlasFrame({
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final frameWidth = constraints.maxWidth;
      final frameHeight = constraints.maxHeight;
      final column = frame % columns;
      final row = (frame ~/ columns).clamp(0, rows - 1);
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: frameWidth * columns,
          maxWidth: frameWidth * columns,
          minHeight: frameHeight * rows,
          maxHeight: frameHeight * rows,
          child: Transform.translate(
            offset: Offset(-column * frameWidth, -row * frameHeight),
            child: Image.asset(
              asset,
              width: frameWidth * columns,
              height: frameHeight * rows,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    },
  );
}
