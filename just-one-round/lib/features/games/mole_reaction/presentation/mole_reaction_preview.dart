import 'package:flutter/material.dart';
import 'package:just_one_round/features/games/mole_reaction/mole_reaction_hole_clip.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

/// The staged state shown by a home/guide preview.
///
/// These are instructional compositions, not a second game implementation:
/// the hole layers, mole anchor, clipping contour, and nearest-neighbour
/// sampling are the same ones used by the Flame scene.
enum MoleReactionPreviewScene { home, practice, golden, score }

/// Responsive gameplay preview used on the home page and in the guide.
class MoleReactionPreview extends StatelessWidget {
  const MoleReactionPreview({
    this.scene = MoleReactionPreviewScene.home,
    super.key,
  });

  final MoleReactionPreviewScene scene;

  static const _background =
      'assets/images/mole_reaction/mole_reaction_background.png';
  static const _holeBack = 'assets/images/mole_reaction/hole_back.png';
  static const _holeFront = 'assets/images/mole_reaction/hole_front.png';
  static const _normalMole =
      'assets/images/mole_reaction/high_res/01_honey/idle_sheet.png';
  static const _goldenMole =
      'assets/images/mole_reaction/high_res/gold_from_attached_thumb_reference/idle_sheet.png';

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      key: const Key('mole-reaction-preview'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 360.0;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 420.0;

          // Reserve safe bands first. The board is solved inside the
          // remaining space, so the footer cannot cover row two even in the
          // shorter guide sheet viewport.
          final headerHeight = scene == MoleReactionPreviewScene.home
              ? 48.0
              : 44.0;
          final footerHeight = scene == MoleReactionPreviewScene.home
              ? 50.0
              : 44.0;
          const headerTop = 10.0;
          const footerBottom = 10.0;
          const boardGap = 10.0;
          final boardTopLimit = headerTop + headerHeight + boardGap;
          final rawBoardBottom =
              height - footerBottom - footerHeight - boardGap;
          final boardBottomLimit = rawBoardBottom
              .clamp(boardTopLimit, height)
              .toDouble();
          final boardAvailableHeight = (boardBottomLimit - boardTopLimit)
              .clamp(0.0, height)
              .toDouble();

          final desiredCell = (width * 0.27).clamp(64.0, 92.0).toDouble();
          final desiredVerticalGap = desiredCell * 0.2;
          final maxCellByHeight =
              (boardAvailableHeight - desiredVerticalGap) / 2;
          final cell = maxCellByHeight > 0
              ? desiredCell.clamp(48.0, maxCellByHeight).toDouble()
              : desiredCell;
          final horizontalGap = cell * 0.22;
          final verticalGap = cell * 0.2;
          final boardWidth = cell * 2 + horizontalGap;
          final boardHeight = cell * 2 + verticalGap;
          final boardLeft = (width - boardWidth) / 2;
          final boardTop =
              boardTopLimit +
              ((boardAvailableHeight - boardHeight).clamp(0.0, height) / 2);
          final activeHole = switch (scene) {
            MoleReactionPreviewScene.home => 1,
            MoleReactionPreviewScene.practice => 0,
            MoleReactionPreviewScene.golden => 3,
            MoleReactionPreviewScene.score => 2,
          };
          final isGolden = scene != MoleReactionPreviewScene.practice;

          return Stack(
            clipBehavior: Clip.hardEdge,
            fit: StackFit.expand,
            children: [
              const Image(
                image: AssetImage(_background),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.none,
              ),
              Positioned(
                left: 10,
                right: 10,
                top: headerTop,
                height: headerHeight,
                child: _PreviewPanel(
                  title: _headerTitle,
                  subtitle: _headerSubtitle,
                ),
              ),
              for (var index = 0; index < 4; index++)
                Positioned(
                  left: boardLeft + (index % 2) * (cell + horizontalGap),
                  top: boardTop + (index ~/ 2) * (cell + verticalGap),
                  width: cell,
                  height: cell,
                  child: _PreviewHole(
                    active: index == activeHole,
                    golden: isGolden,
                    cell: cell,
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: footerBottom,
                height: footerHeight,
                child: _PreviewPanel(
                  title: _footerTitle,
                  subtitle: _footerSubtitle,
                  accent: isGolden
                      ? const Color(0xFFFFE18A)
                      : const Color(0xFFFFF0BE),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String get _headerTitle => switch (scene) {
    MoleReactionPreviewScene.home => '두더지 반응속도',
    MoleReactionPreviewScene.practice => '첫 두더지는 연습이에요!',
    MoleReactionPreviewScene.golden => '이번엔 진짜에요!',
    MoleReactionPreviewScene.score => '기록 확정',
  };

  String get _headerSubtitle => switch (scene) {
    MoleReactionPreviewScene.home => '준비 1회   ·   진짜 1회',
    MoleReactionPreviewScene.practice => '보이면 그 구멍을 바로 눌러요',
    MoleReactionPreviewScene.golden => '황금 두더지  ·  반응시간 ×2',
    MoleReactionPreviewScene.score => '빠를수록 더 좋은 기록',
  };

  String get _footerTitle => switch (scene) {
    MoleReactionPreviewScene.home => '진짜 한 번에 기록 확정',
    MoleReactionPreviewScene.practice => '손을 풀어 보는 준비판',
    MoleReactionPreviewScene.golden => '황금 두더지 한 마리',
    MoleReactionPreviewScene.score => '147ms  ×2  =  294ms',
  };

  String get _footerSubtitle => switch (scene) {
    MoleReactionPreviewScene.home => '황금 두더지  ·  반응시간 ×2',
    MoleReactionPreviewScene.practice => '준비판은 최종 기록에 포함되지 않아요',
    MoleReactionPreviewScene.golden => '이 순간의 반응시간만 최종 기록에 반영',
    MoleReactionPreviewScene.score => '반응시간과 실수 벌점을 합산해요',
  };
}

class _PreviewHole extends StatelessWidget {
  const _PreviewHole({
    required this.active,
    required this.golden,
    required this.cell,
  });

  final bool active;
  final bool golden;
  final double cell;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    fit: StackFit.expand,
    children: [
      const Image(
        image: AssetImage(MoleReactionPreview._holeBack),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.none,
      ),
      if (active)
        Positioned.fill(
          child: _ClippedAtlasFrame(
            assetPath: golden
                ? MoleReactionPreview._goldenMole
                : MoleReactionPreview._normalMole,
            cell: cell,
          ),
        ),
      // The rim is always painted last, matching _MoleReactionScene.render.
      const Positioned.fill(
        child: Image(
          image: AssetImage(MoleReactionPreview._holeFront),
          fit: BoxFit.fill,
          filterQuality: FilterQuality.none,
        ),
      ),
      if (active && golden)
        Positioned(
          top: -7,
          left: 0,
          right: 0,
          child: _GoldBadge(scale: (cell / 84).clamp(0.82, 1.12)),
        ),
    ],
  );
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.title,
    required this.subtitle,
    this.accent = const Color(0xFFFFF0BE),
  });

  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xD03B2418),
      border: Border.all(color: accent, width: 1.5),
      boxShadow: const [
        BoxShadow(color: Color(0x55000000), offset: Offset(2, 2)),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: WordSafeText(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            singleLine: true,
            style: TextStyle(
              fontFamily: 'Galmuri',
              color: accent,
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Flexible(
          child: WordSafeText(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            singleLine: true,
            style: const TextStyle(
              fontFamily: 'Galmuri',
              color: Color(0xFFFFF4D4),
              fontSize: 8,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _GoldBadge extends StatelessWidget {
  const _GoldBadge({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Transform.scale(
      scale: scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF5A3212),
          border: Border.all(color: const Color(0xFFFFE18A), width: 1),
        ),
        child: const WordSafeText(
          '황금 ×2',
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: Color(0xFFFFE18A),
            fontSize: 8,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ),
  );
}

/// Crops the 2×2 animation sheet to its first 256px frame and keeps the same
/// foreground dirt contour used by the runtime Flame renderer.
class _ClippedAtlasFrame extends StatelessWidget {
  const _ClippedAtlasFrame({required this.assetPath, required this.cell});

  final String assetPath;
  final double cell;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('mole-reaction-visible-sprite'),
    width: cell,
    height: cell,
    child: ClipPath(
      clipper: const MoleReactionHoleClipper(),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: cell * 2,
          maxWidth: cell * 2,
          minHeight: cell * 2,
          maxHeight: cell * 2,
          child: Image.asset(
            assetPath,
            width: cell * 2,
            height: cell * 2,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    ),
  );
}
