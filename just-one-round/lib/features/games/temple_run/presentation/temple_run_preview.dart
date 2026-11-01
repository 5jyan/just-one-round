import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

import 'temple_run_art.dart';

enum TempleRunPreviewScene {
  home,
  controls,
  hazards,
  maneuvers,
  corner,
  items,
  score,
}

const _homePreviewObstacles = [
  TempleRunObstacle(
    id: 0,
    distanceMeters: 58,
    lane: TempleRunRules.lastLane,
    kind: TempleRunObstacleKind.narrowPath,
    span: TempleRunObstacleSpan.singleLane,
    lengthMeters: TempleRunRules.narrowPathHalfLengthMeters,
  ),
  TempleRunObstacle(
    id: 1,
    distanceMeters: 70,
    lane: TempleRunRules.centerLane,
    kind: TempleRunObstacleKind.hurdle,
    span: TempleRunObstacleSpan.fullRoad,
  ),
  TempleRunObstacle(
    id: 2,
    distanceMeters: 84,
    lane: TempleRunRules.centerLane,
    kind: TempleRunObstacleKind.hurdle,
    span: TempleRunObstacleSpan.fullRoad,
  ),
  TempleRunObstacle(
    id: 3,
    distanceMeters: 96,
    lane: TempleRunRules.centerLane,
    kind: TempleRunObstacleKind.arch,
    span: TempleRunObstacleSpan.fullRoad,
  ),
];

const _maneuverPreviewObstacles = [
  TempleRunObstacle(
    id: 21,
    distanceMeters: 50,
    lane: TempleRunRules.centerLane,
    kind: TempleRunObstacleKind.hurdle,
    span: TempleRunObstacleSpan.fullRoad,
  ),
  TempleRunObstacle(
    id: 22,
    distanceMeters: 64,
    lane: TempleRunRules.centerLane,
    kind: TempleRunObstacleKind.hurdle,
    span: TempleRunObstacleSpan.fullRoad,
  ),
  TempleRunObstacle(
    id: 23,
    distanceMeters: 78,
    lane: TempleRunRules.centerLane,
    kind: TempleRunObstacleKind.arch,
    span: TempleRunObstacleSpan.fullRoad,
  ),
];

const _previewTurnDistance = 74.0;
const _previewTurnWindowStart =
    _previewTurnDistance - TempleRunRules.mandatoryTurnLeadSeconds * 8;
const _previewTurnWindowEnd =
    _previewTurnDistance + TempleRunRules.mandatoryTurnTailSeconds * 8;

/// The home card and guide pages share the same small deterministic timeline
/// and the same pixel asset bundle as the production game.
class TempleRunPreviewSnapshot {
  const TempleRunPreviewSnapshot({
    required this.scene,
    required this.frame,
    required this.progress,
    required this.lane,
    required this.visualLane,
    required this.phoneTilt,
    required this.runnerFrame,
    required this.jumpProgress,
    required this.slideProgress,
    required this.cornerVisible,
    required this.narrowPathActive,
    required this.turnReserved,
    required this.turnCrossed,
    required this.cornerDirection,
    required this.completedTurnCount,
    required this.bendProgress,
    required this.distanceMeters,
    required this.jumpActive,
    required this.slideActive,
    required this.coins,
    required this.score,
    required this.caption,
  });

  static const cycleFrameCount = 96;

  static List<TempleRunObstacle> obstaclesForScene(
    TempleRunPreviewScene scene,
  ) => List.unmodifiable(_previewObstaclesForScene(scene));

  factory TempleRunPreviewSnapshot.forFrame(
    int inputFrame, {
    TempleRunPreviewScene scene = TempleRunPreviewScene.home,
  }) {
    final frame = inputFrame % cycleFrameCount;
    return TempleRunPreviewSnapshot.forProgress(
      frame / cycleFrameCount,
      scene: scene,
    );
  }

  factory TempleRunPreviewSnapshot.forProgress(
    double inputProgress, {
    TempleRunPreviewScene scene = TempleRunPreviewScene.home,
    int completedTurnCount = 0,
    double? bendProgress,
  }) {
    final progress = inputProgress.isFinite
        ? ((inputProgress % 1) + 1) % 1
        : 0.0;
    final frame = (progress * cycleFrameCount).floor().clamp(
      0,
      cycleFrameCount - 1,
    );
    final distanceMeters = _previewDistanceForScene(scene, progress);
    final lane = TempleRunRules.centerLane;
    final basePhoneTilt = math.sin(progress * math.pi * 2) * 0.58;
    final phoneTilt = _narrowPathDemoTilt(scene, distanceMeters, basePhoneTilt);
    final visualLane = TempleRunRules.clampPosition(
      TempleRunRules.centerLane + phoneTilt,
    );
    final turn = _previewTurnForScene(scene);
    final narrowPath = _narrowPathForScene(scene);
    final narrowPathActive =
        narrowPath != null &&
        distanceMeters >= narrowPath.distanceMeters &&
        distanceMeters <= narrowPath.endDistanceMeters;
    final turnCrossed = turn != null && distanceMeters >= turn.distanceMeters;
    final turnReserved =
        turn != null &&
        distanceMeters >= turn.windowStartMeters &&
        distanceMeters < turn.distanceMeters;
    final cornerVisible =
        turn != null &&
        distanceMeters >= turn.windowStartMeters &&
        distanceMeters <= turn.windowEndMeters;
    final derivedBendProgress = turnCrossed
        ? (1 -
                  (distanceMeters - turn.distanceMeters) /
                      (TempleRunRules.speedForElapsed(0) *
                          TempleRunRules.turnAnimationDurationSeconds))
              .clamp(0.0, 1.0)
        : 0.0;
    final derivedCompletedTurnCount = turnCrossed ? 1 : 0;
    final effectiveCompletedTurnCount =
        completedTurnCount > derivedCompletedTurnCount
        ? completedTurnCount
        : derivedCompletedTurnCount;
    final effectiveBendProgress = (bendProgress ?? derivedBendProgress).clamp(
      0.0,
      1.0,
    );
    final action = _actionPoseForDistance(scene, distanceMeters);
    const cornerDirection = 'LEFT';
    final coins = 2 + ((frame ~/ 16) % 7);
    final score = TempleRunRules.scoreFor(
      distanceMeters: distanceMeters.toDouble(),
      coins: coins,
    );
    final caption = turnReserved
        ? '${cornerDirection == 'LEFT' ? '왼쪽' : '오른쪽'} 회전 예약'
        : cornerVisible
        ? turnCrossed
              ? '${cornerDirection == 'LEFT' ? '←' : '→'} 새 길로 이동'
              : '${cornerDirection == 'LEFT' ? '←' : '→'} 지금 꺾기'
        : '폰을 기울여 안전한 위치';
    return TempleRunPreviewSnapshot(
      scene: scene,
      frame: frame,
      progress: progress,
      lane: lane,
      visualLane: visualLane,
      phoneTilt: phoneTilt,
      // The loop lasts six seconds, so four run cells advance at 8fps.
      runnerFrame: (progress * 48).floor() % 4,
      jumpProgress: action.jumpProgress,
      slideProgress: action.slideProgress,
      cornerVisible: cornerVisible,
      narrowPathActive: narrowPathActive,
      turnReserved: turnReserved,
      turnCrossed: turnCrossed,
      cornerDirection: cornerDirection,
      completedTurnCount: effectiveCompletedTurnCount,
      bendProgress: effectiveBendProgress,
      distanceMeters: distanceMeters,
      jumpActive: action.jumpActive,
      slideActive: action.slideActive,
      coins: coins,
      score: score,
      caption: caption,
    );
  }

  final TempleRunPreviewScene scene;
  final int frame;
  final double progress;
  final int lane;
  final double visualLane;
  final double phoneTilt;
  final int runnerFrame;
  final double jumpProgress;
  final double slideProgress;
  final bool cornerVisible;
  final bool narrowPathActive;
  final bool turnReserved;
  final bool turnCrossed;
  final String cornerDirection;
  final int completedTurnCount;
  final double bendProgress;
  final double distanceMeters;
  final bool jumpActive;
  final bool slideActive;
  final int coins;
  final int score;
  final String caption;

  bool get isJumping => jumpActive;
  bool get isSliding => slideActive;
}

double _previewDistanceForScene(TempleRunPreviewScene scene, double progress) {
  final start = switch (scene) {
    TempleRunPreviewScene.home || TempleRunPreviewScene.hazards => 52.0,
    TempleRunPreviewScene.controls || TempleRunPreviewScene.corner => 46.5,
    TempleRunPreviewScene.maneuvers || TempleRunPreviewScene.items => 42.0,
    TempleRunPreviewScene.score => 46.0,
  };
  return start + progress * 48;
}

List<TempleRunObstacle> _previewObstaclesForScene(
  TempleRunPreviewScene scene,
) => switch (scene) {
  TempleRunPreviewScene.home ||
  TempleRunPreviewScene.hazards => _homePreviewObstacles,
  TempleRunPreviewScene.maneuvers => _maneuverPreviewObstacles,
  _ => const [],
};

TempleRunTurn? _previewTurnForScene(
  TempleRunPreviewScene scene, [
  TempleRunTurnDirection direction = TempleRunTurnDirection.left,
]) => switch (scene) {
  TempleRunPreviewScene.home ||
  TempleRunPreviewScene.controls ||
  TempleRunPreviewScene.corner => TempleRunTurn(
    distanceMeters: _previewTurnDistance,
    direction: direction,
    windowStartMeters: _previewTurnWindowStart,
    windowEndMeters: _previewTurnWindowEnd,
  ),
  _ => null,
};

TempleRunObstacle? _narrowPathForScene(TempleRunPreviewScene scene) {
  for (final obstacle in _previewObstaclesForScene(scene)) {
    if (obstacle.isNarrowPath) return obstacle;
  }
  return null;
}

double _narrowPathDemoTilt(
  TempleRunPreviewScene scene,
  double distanceMeters,
  double baseTilt,
) {
  final path = _narrowPathForScene(scene);
  if (path == null) return baseTilt;
  const safeTilt = .92;
  const approachMeters = 2.0;
  const exitMeters = 2.0;
  final start = path.distanceMeters;
  final end = path.endDistanceMeters;
  if (distanceMeters < start - approachMeters) return baseTilt;
  if (distanceMeters < start) {
    return baseTilt +
        (safeTilt - baseTilt) *
            ((distanceMeters - (start - approachMeters)) / approachMeters);
  }
  if (distanceMeters <= end) return safeTilt;
  if (distanceMeters < end + exitMeters) {
    return safeTilt +
        (baseTilt - safeTilt) * ((distanceMeters - end) / exitMeters);
  }
  return baseTilt;
}

({bool jumpActive, double jumpProgress, bool slideActive, double slideProgress})
_actionPoseForDistance(TempleRunPreviewScene scene, double distanceMeters) {
  final speed = TempleRunRules.speedForElapsed(0);
  for (final obstacle in _previewObstaclesForScene(scene)) {
    final jumping = obstacle.isJumpable;
    final sliding = obstacle.kind == TempleRunObstacleKind.arch;
    if (!jumping && !sliding) continue;
    final duration = jumping
        ? TempleRunRules.jumpDurationSeconds
        : TempleRunRules.slideDurationSeconds;
    final halfActionDistance = speed * duration / 2;
    final start = obstacle.distanceMeters - halfActionDistance;
    final end = obstacle.distanceMeters + halfActionDistance;
    if (distanceMeters < start || distanceMeters >= end) continue;
    final progress = ((distanceMeters - start) / (end - start)).clamp(0.0, 1.0);
    return (
      jumpActive: jumping,
      jumpProgress: jumping ? progress : 0.0,
      slideActive: sliding,
      slideProgress: sliding ? progress : 0.0,
    );
  }
  return (
    jumpActive: false,
    jumpProgress: 0.0,
    slideActive: false,
    slideProgress: 0.0,
  );
}

class TempleRunPreview extends StatefulWidget {
  const TempleRunPreview({
    super.key,
    this.scene = TempleRunPreviewScene.home,
    this.animate = true,
    this.initialFrame,
    this.completedTurnCount = 0,
    this.bendProgress,
    this.useImageAssets = true,
  });

  final TempleRunPreviewScene scene;
  final bool animate;
  final int? initialFrame;
  final int completedTurnCount;
  final double? bendProgress;

  /// Primitive geometry is available only through this explicit debug switch.
  final bool useImageAssets;

  int get resolvedInitialFrame =>
      initialFrame ??
      switch (scene) {
        TempleRunPreviewScene.home => 0,
        TempleRunPreviewScene.controls => 8,
        TempleRunPreviewScene.hazards => 16,
        TempleRunPreviewScene.maneuvers => 16,
        TempleRunPreviewScene.corner => 55,
        TempleRunPreviewScene.items => 84,
        TempleRunPreviewScene.score => 64,
      };

  @visibleForTesting
  static Future<void> preloadAssets() async {
    final future = _TempleRunPreviewState._imageAssetsFuture ??=
        TempleRunArt.loadImageAssets();
    try {
      _TempleRunPreviewState._imageAssets = await future;
    } on Object {
      if (identical(_TempleRunPreviewState._imageAssetsFuture, future)) {
        _TempleRunPreviewState._imageAssetsFuture = null;
      }
      _TempleRunPreviewState._imageAssets = null;
      rethrow;
    }
  }

  @override
  State<TempleRunPreview> createState() => _TempleRunPreviewState();
}

class _TempleRunPreviewState extends State<TempleRunPreview>
    with SingleTickerProviderStateMixin {
  static const _cycleDuration = Duration(seconds: 6);
  static const _cycleFadeProgress = 0.02;

  late final AnimationController _controller;
  TempleRunArt _art = TempleRunArt();
  var _assetsReady = false;
  var _cycleHasCompleted = false;
  Object? _assetLoadError;
  static Future<Map<String, ui.Image>>? _imageAssetsFuture;
  static Map<String, ui.Image>? _imageAssets;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: _cycleDuration,
            value: _progressForFrame(widget.resolvedInitialFrame),
          )
          ..addListener(_handleTick)
          ..addStatusListener(_handleAnimationStatus);
    if (widget.useImageAssets) {
      final cachedImages = _imageAssets;
      if (cachedImages != null) {
        _art = TempleRunArt(images: cachedImages, useImageAssets: true);
        _assetsReady = true;
      } else {
        _loadImageAssets();
      }
    } else {
      _art = TempleRunArt();
      _assetsReady = true;
    }
    if (widget.animate) _play();
  }

  Future<void> _loadImageAssets() async {
    final future = _imageAssetsFuture ??= TempleRunArt.loadImageAssets();
    try {
      final images = await future;
      _imageAssets = images;
      if (!mounted) return;
      setState(() {
        _art = TempleRunArt(images: images, useImageAssets: true);
        _assetsReady = true;
      });
    } on Object catch (error, stackTrace) {
      if (identical(_imageAssetsFuture, future)) _imageAssetsFuture = null;
      _imageAssets = null;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: '집에 좀 가자 미리보기',
          context: ErrorDescription('production image assets failed to load'),
        ),
      );
      if (!mounted) return;
      setState(() => _assetLoadError = error);
    }
  }

  double _progressForFrame(int frame) {
    final wrapped = frame % TempleRunPreviewSnapshot.cycleFrameCount;
    return wrapped < 0
        ? (wrapped + TempleRunPreviewSnapshot.cycleFrameCount) /
              TempleRunPreviewSnapshot.cycleFrameCount
        : wrapped / TempleRunPreviewSnapshot.cycleFrameCount;
  }

  void _play() {
    if (_controller.value >= 1) _controller.value = 0;
    _controller.forward();
  }

  void _handleTick() {
    if (mounted) setState(() {});
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && widget.animate) {
      _cycleHasCompleted = true;
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant TempleRunPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _cycleHasCompleted = false;
      if (widget.animate) {
        _play();
      } else {
        _controller.stop();
      }
    }
    if (oldWidget.scene != widget.scene ||
        oldWidget.resolvedInitialFrame != widget.resolvedInitialFrame) {
      _cycleHasCompleted = false;
      _controller.value = _progressForFrame(widget.resolvedInitialFrame);
      if (widget.animate) _play();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _controller.value;
    final resetFadeOpacity = !_cycleHasCompleted
        ? 0.0
        : progress < _cycleFadeProgress
        ? 1 - progress / _cycleFadeProgress
        : progress > 1 - _cycleFadeProgress
        ? (progress - (1 - _cycleFadeProgress)) / _cycleFadeProgress
        : 0.0;
    final snapshot = TempleRunPreviewSnapshot.forProgress(
      progress,
      scene: widget.scene,
      completedTurnCount: widget.completedTurnCount,
      bendProgress: widget.bendProgress,
    );
    return LayoutBuilder(
      builder: (context, constraints) => KeyedSubtree(
        key: const Key('temple-run-preview'),
        child: _TempleRunPreviewCanvas(
          scene: widget.scene,
          snapshot: snapshot,
          art: _art,
          assetsReady: _assetsReady,
          assetLoadFailed: _assetLoadError != null,
          resetFadeOpacity: resetFadeOpacity,
          size: constraints.biggest,
        ),
      ),
    );
  }
}

class _TempleRunPreviewCanvas extends StatelessWidget {
  const _TempleRunPreviewCanvas({
    required this.scene,
    required this.snapshot,
    required this.art,
    required this.assetsReady,
    required this.assetLoadFailed,
    required this.resetFadeOpacity,
    required this.size,
  });

  final TempleRunPreviewScene scene;
  final TempleRunPreviewSnapshot snapshot;
  final TempleRunArt art;
  final bool assetsReady;
  final bool assetLoadFailed;
  final double resetFadeOpacity;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final isHome = scene == TempleRunPreviewScene.home;
    return Semantics(
      label: '집에 좀 가자 ${scene.name} 미리보기',
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              key: isHome ? const Key('temple-run-home-world') : null,
              child: RepaintBoundary(
                key: const Key('temple-run-art'),
                child: CustomPaint(
                  painter: _TempleRunArtPainter(
                    art: art,
                    scene: scene,
                    snapshot: snapshot,
                  ),
                ),
              ),
            ),
            if (assetsReady)
              const Positioned(
                left: 0,
                top: 0,
                child: SizedBox(key: Key('temple-run-preview-ready')),
              ),
            if (assetLoadFailed)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0xCC101A18),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: WordSafeText(
                        '골목 그림을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.text,
                          fontFamily: 'Galmuri',
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (scene == TempleRunPreviewScene.controls) _controlsOverlay(),
            if (scene == TempleRunPreviewScene.hazards) _hazardsOverlay(),
            if (scene == TempleRunPreviewScene.maneuvers) _maneuversOverlay(),
            if (scene == TempleRunPreviewScene.corner) _cornerOverlay(),
            if (isHome || scene == TempleRunPreviewScene.score)
              _hud(isHome: isHome),
            if (!isHome) _caption(_captionForScene()),
            if (resetFadeOpacity > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: resetFadeOpacity),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _captionForScene() => switch (scene) {
    TempleRunPreviewScene.controls => '폰 기울이기 · ←→ 코너 예약 · ↑↓ 동작',
    TempleRunPreviewScene.hazards => '덮개 자재 사이 열린 통로 유지',
    TempleRunPreviewScene.maneuvers => '낮은 차단대 점프 · 작업발판 슬라이드',
    TempleRunPreviewScene.corner =>
      snapshot.turnReserved
          ? '${snapshot.cornerDirection == 'LEFT' ? '←' : '→'} 회전 예약'
          : snapshot.turnCrossed
          ? '${snapshot.cornerDirection == 'LEFT' ? '←' : '→'} 새 길로 이동'
          : snapshot.cornerVisible
          ? '${snapshot.cornerDirection == 'LEFT' ? '←' : '→'} 지금 꺾기'
          : '방향 표지판 · 약 3초 전 예고',
    TempleRunPreviewScene.items => '코너 예약 · 코인 +10 · 아이템 활용',
    TempleRunPreviewScene.score => '달린 거리 1m마다 1점 · 코인 1개당 10점',
    TempleRunPreviewScene.home => snapshot.caption,
  };

  Widget _controlsOverlay() => Positioned(
    left: 12,
    right: 12,
    top: 10,
    child: Row(
      children: [
        Expanded(child: _gestureChip('↔', '코너 예약')),
        const SizedBox(width: 5),
        Expanded(child: _gestureChip('90°', '회전')),
        const SizedBox(width: 5),
        Expanded(child: _gestureChip('↑', '점프')),
        const SizedBox(width: 5),
        Expanded(child: _gestureChip('↓', '슬라이드')),
      ],
    ),
  );

  Widget _gestureChip(String icon, String label) => Container(
    constraints: const BoxConstraints(minWidth: 56, maxWidth: 90),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xD014211D),
      border: Border.all(color: AppColors.primary, width: 1.5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        WordSafeText(
          icon,
          style: const TextStyle(
            color: AppColors.primary,
            fontFamily: 'Galmuri',
            fontSize: 23,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        WordSafeText(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _hazardsOverlay() => Positioned(
    left: 12,
    right: 12,
    top: size.height * 0.18,
    child: Align(
      alignment: Alignment.topLeft,
      child: _smallPanel('골목의 모양을 보고 동작을 골라요', const [
        '덮개 자재 사이 열린 통로 유지',
        '낮은 차단대 · 점프',
        '작업발판 · 슬라이드',
      ]),
    ),
  );

  Widget _maneuversOverlay() => Positioned(
    left: 12,
    right: 12,
    top: size.height * 0.18,
    child: Align(
      alignment: Alignment.topLeft,
      child: _smallPanel('세로 스와이프는 한 동작씩', const [
        '↑ 낮은 차단대 · 점프',
        '↓ 위가 막힌 작업발판 · 슬라이드',
        '동작 중 다음 입력 1회 · 0.30초 대기',
      ]),
    ),
  );

  Widget _cornerOverlay() => Positioned(
    left: 14,
    right: 14,
    top: size.height * 0.17,
    child: _smallPanel(
      snapshot.turnReserved
          ? '회전 예약 완료'
          : snapshot.turnCrossed
          ? '새 길로 이동'
          : snapshot.cornerVisible
          ? '지금 꺾기'
          : '방향 표지판 · 미리 준비',
      [snapshot.cornerDirection == 'LEFT' ? '← 왼쪽' : '오른쪽 →'],
      accent:
          snapshot.turnCrossed ||
          snapshot.cornerVisible ||
          snapshot.turnReserved,
    ),
  );

  Widget _smallPanel(
    String title,
    List<String> details, {
    bool accent = false,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xD014211D),
      border: Border.all(
        color: accent ? const Color(0xFFFFD96D) : AppColors.primary,
        width: 1.5,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          WordSafeText(
            title,
            style: TextStyle(
              color: accent ? const Color(0xFFFFD96D) : AppColors.primary,
              fontFamily: 'Galmuri',
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              for (final detail in details)
                WordSafeText(
                  detail,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontFamily: 'Galmuri',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _hud({required bool isHome}) => Positioned(
    left: 10,
    right: 10,
    top: 10,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _hudValue('점수', '${snapshot.score}'),
        _hudValue('거리', '${snapshot.distanceMeters.floor()}m'),
        _hudValue('코인', '${snapshot.coins}'),
      ],
    ),
  );

  Widget _hudValue(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xD014211D),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        WordSafeText(
          label,
          style: const TextStyle(
            color: AppColors.primary,
            fontFamily: 'Galmuri',
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        WordSafeText(
          value,
          style: const TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _caption(String value) => Positioned(
    left: 12,
    right: 12,
    bottom: 10,
    child: Container(
      key: const Key('temple-run-preview-caption'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xD014211D),
        borderRadius: BorderRadius.circular(7),
      ),
      child: WordSafeText(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.text,
          fontFamily: 'Galmuri',
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _TempleRunArtPainter extends CustomPainter {
  const _TempleRunArtPainter({
    required this.art,
    required this.scene,
    required this.snapshot,
  });

  final TempleRunArt art;
  final TempleRunPreviewScene scene;
  final TempleRunPreviewSnapshot snapshot;

  @override
  void paint(Canvas canvas, Size size) {
    art.resizeToViewport(Vector2(size.width, size.height));
    final course = _courseForScene(scene, snapshot);
    final distance = snapshot.distanceMeters;
    final turn = course.turns.isEmpty ? null : course.turns.first;
    final narrowPathActive = snapshot.narrowPathActive;
    final turnCrossed = snapshot.turnCrossed;
    final bendProgress = turnCrossed ? snapshot.bendProgress : 0.0;
    final completedTurnCount = turnCrossed ? snapshot.completedTurnCount : 0;
    final showActionPose =
        scene == TempleRunPreviewScene.maneuvers ||
        ((scene == TempleRunPreviewScene.home ||
                scene == TempleRunPreviewScene.hazards) &&
            !narrowPathActive);
    final jumpRemaining = showActionPose && snapshot.isJumping
        ? TempleRunRules.jumpDurationSeconds * (1 - snapshot.jumpProgress)
        : 0.0;
    final slideRemaining = showActionPose && snapshot.isSliding
        ? TempleRunRules.slideDurationSeconds * (1 - snapshot.slideProgress)
        : 0.0;
    final direction = turn?.direction;
    art.updateScene(
      course: course,
      distanceMeters: distance,
      lane: snapshot.lane,
      visualLane: snapshot.visualLane,
      phoneTilt: snapshot.phoneTilt,
      jumpRemaining: jumpRemaining,
      slideRemaining: slideRemaining,
      runnerFrame: snapshot.runnerFrame.toDouble(),
      activeTurn: turn,
      bendProgress: bendProgress,
      bendDirection: direction,
      completedTurnCount: completedTurnCount,
      // Explicit turn progress drives the real route/camera projection. Keep
      // the legacy yaw hint at zero so guide frames cannot flatten a 90° bend.
      cameraYaw: 0,
      guardianVisible: scene == TempleRunPreviewScene.score,
      failureVisible: false,
      shieldVisible:
          scene == TempleRunPreviewScene.items &&
          _powerUpActiveBetween(
            course.powerUps,
            TempleRunPowerUpKind.shield,
            TempleRunPowerUpKind.boost,
            distance,
          ),
      boostVisible:
          scene == TempleRunPreviewScene.items &&
          _powerUpActiveBetween(
            course.powerUps,
            TempleRunPowerUpKind.boost,
            null,
            distance,
          ),
    );
    art.render(canvas);
  }

  @override
  bool shouldRepaint(covariant _TempleRunArtPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.snapshot.progress != snapshot.progress ||
      oldDelegate.snapshot.frame != snapshot.frame ||
      oldDelegate.snapshot.completedTurnCount != snapshot.completedTurnCount ||
      oldDelegate.snapshot.bendProgress != snapshot.bendProgress;
}

TempleRunPowerUp? _powerUpOfKind(
  List<TempleRunPowerUp> powerUps,
  TempleRunPowerUpKind kind,
) {
  for (final powerUp in powerUps) {
    if (powerUp.kind == kind) return powerUp;
  }
  return null;
}

bool _powerUpActiveBetween(
  List<TempleRunPowerUp> powerUps,
  TempleRunPowerUpKind kind,
  TempleRunPowerUpKind? endsAt,
  double distanceMeters,
) {
  final start = _powerUpOfKind(powerUps, kind);
  if (start == null || distanceMeters < start.distanceMeters) return false;
  if (endsAt == null) return true;
  final end = _powerUpOfKind(powerUps, endsAt);
  return end == null || distanceMeters < end.distanceMeters;
}

TempleRunCourse _courseForScene(
  TempleRunPreviewScene scene,
  TempleRunPreviewSnapshot snapshot,
) {
  final turnDirection = snapshot.cornerDirection == 'LEFT'
      ? TempleRunTurnDirection.left
      : TempleRunTurnDirection.right;
  return switch (scene) {
    TempleRunPreviewScene.home => TempleRunCourse(
      obstacles: _homePreviewObstacles,
      coins: const [
        TempleRunCoin(distanceMeters: 56, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 63, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 70, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 77, lane: TempleRunRules.centerLane),
      ],
      powerUps: const [
        TempleRunPowerUp(
          distanceMeters: 92,
          lane: TempleRunRules.centerLane,
          kind: TempleRunPowerUpKind.shield,
        ),
      ],
      turns: [_previewTurnForScene(scene, turnDirection)!],
      totalDistanceMeters: 220,
    ),
    TempleRunPreviewScene.controls => TempleRunCourse(
      obstacles: const [],
      coins: const [
        TempleRunCoin(distanceMeters: 60, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 70, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 80, lane: TempleRunRules.centerLane),
      ],
      powerUps: const [],
      turns: [_previewTurnForScene(scene, turnDirection)!],
      totalDistanceMeters: 180,
    ),
    TempleRunPreviewScene.hazards => TempleRunCourse(
      obstacles: _homePreviewObstacles,
      coins: const [
        TempleRunCoin(distanceMeters: 48, lane: TempleRunRules.centerLane),
      ],
      powerUps: const [],
      turns: const [],
      totalDistanceMeters: 180,
    ),
    TempleRunPreviewScene.maneuvers => TempleRunCourse(
      obstacles: _maneuverPreviewObstacles,
      coins: const [
        TempleRunCoin(distanceMeters: 50, lane: TempleRunRules.centerLane),
      ],
      powerUps: const [],
      turns: const [],
      totalDistanceMeters: 180,
    ),
    TempleRunPreviewScene.corner => TempleRunCourse(
      obstacles: const [],
      coins: const [
        TempleRunCoin(distanceMeters: 57, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 66, lane: TempleRunRules.centerLane),
      ],
      powerUps: const [],
      turns: [_previewTurnForScene(scene, turnDirection)!],
      totalDistanceMeters: 160,
    ),
    TempleRunPreviewScene.items => TempleRunCourse(
      obstacles: const [],
      coins: const [
        TempleRunCoin(distanceMeters: 48, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 56, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 64, lane: TempleRunRules.centerLane),
      ],
      powerUps: const [
        TempleRunPowerUp(
          distanceMeters: 58,
          lane: TempleRunRules.centerLane,
          kind: TempleRunPowerUpKind.magnet,
        ),
        TempleRunPowerUp(
          distanceMeters: 72,
          lane: TempleRunRules.centerLane,
          kind: TempleRunPowerUpKind.shield,
        ),
        TempleRunPowerUp(
          distanceMeters: 86,
          lane: TempleRunRules.centerLane,
          kind: TempleRunPowerUpKind.boost,
        ),
      ],
      turns: const [],
      totalDistanceMeters: 180,
    ),
    TempleRunPreviewScene.score => TempleRunCourse(
      obstacles: const [],
      coins: const [
        TempleRunCoin(distanceMeters: 63, lane: TempleRunRules.centerLane),
        TempleRunCoin(distanceMeters: 70, lane: TempleRunRules.centerLane),
      ],
      powerUps: const [],
      turns: const [],
      totalDistanceMeters: 180,
    ),
  };
}
