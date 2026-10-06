import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum BathhouseSortPreviewScene { home, controls, queue, unlock, scoring }

@immutable
class BathhouseSortPreviewFrame {
  const BathhouseSortPreviewFrame({
    required this.isWomensTurn,
    required this.actionProgress,
    required this.isDeparting,
    required this.combo,
    required this.score,
    required this.secondsLeft,
  });

  factory BathhouseSortPreviewFrame.fromCycle(double cycle) {
    final wrapped = cycle % 1;
    final isWomensTurn = wrapped >= 0.5;
    final actionProgress = (wrapped * 2) % 1;
    final isDeparting = actionProgress > 0.58;
    final completed = isDeparting ? 1 : 0;
    final baseCombo = isWomensTurn ? 13 : 12;
    final combo = baseCombo + completed;
    return BathhouseSortPreviewFrame(
      isWomensTurn: isWomensTurn,
      actionProgress: actionProgress,
      isDeparting: isDeparting,
      combo: combo,
      score:
          2460 + (isWomensTurn ? 230 : 0) + completed * (210 + baseCombo * 10),
      secondsLeft: isWomensTurn ? 41 : 42,
    );
  }

  final bool isWomensTurn;
  final double actionProgress;
  final bool isDeparting;
  final int combo;
  final int score;
  final int secondsLeft;
}

class BathhouseSortPreview extends StatefulWidget {
  const BathhouseSortPreview({
    super.key,
    required this.scene,
    this.animate = true,
    this.staticCycle = 0.18,
  });

  final BathhouseSortPreviewScene scene;
  final bool animate;
  final double staticCycle;

  @override
  State<BathhouseSortPreview> createState() => _BathhouseSortPreviewState();
}

class _BathhouseSortPreviewState extends State<BathhouseSortPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  _BathhousePreviewImages? _images;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
    unawaited(_loadImages());
  }

  Future<void> _loadImages() async {
    final loaded = <ui.Image>[];
    try {
      for (final path in _BathhousePreviewImages.assetPaths) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        loaded.add(frame.image);
      }
      final images = _BathhousePreviewImages(loaded);
      if (!mounted) {
        images.dispose();
        return;
      }
      setState(() => _images = images);
    } catch (error, stackTrace) {
      debugPrint('Bathhouse preview asset load failed: $error\n$stackTrace');
      for (final image in loaded) {
        image.dispose();
      }
    }
  }

  @override
  void didUpdateWidget(covariant BathhouseSortPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    widget.animate ? _controller.repeat() : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    _images?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    key: const Key('bathhouse-sort-preview-clip'),
    clipBehavior: Clip.hardEdge,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => KeyedSubtree(
        key: Key(
          _images == null
              ? 'bathhouse-sort-preview-loading'
              : 'bathhouse-sort-preview-ready',
        ),
        child: CustomPaint(
          key: const Key('bathhouse-sort-preview'),
          painter: _BathhouseSortPreviewPainter(
            scene: widget.scene,
            cycle: widget.animate ? _controller.value : widget.staticCycle,
            images: _images,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _BathhousePreviewImages {
  _BathhousePreviewImages(List<ui.Image> images)
    : background = images[0],
      noren = images[1],
      guests = images[2],
      feedback = images[3];

  static const assetPaths = <String>[
    'assets/images/bathhouse_sort/bathhouse_corridor_background.png',
    'assets/images/bathhouse_sort/bathhouse_hanja_noren_atlas.png',
    'assets/images/bathhouse_sort/bathhouse_guests_atlas.png',
    'assets/images/bathhouse_sort/bathhouse_feedback_fx_atlas.png',
  ];

  final ui.Image background;
  final ui.Image noren;
  final ui.Image guests;
  final ui.Image feedback;

  void dispose() {
    background.dispose();
    noren.dispose();
    guests.dispose();
    feedback.dispose();
  }
}

class _BathhouseSortPreviewPainter extends CustomPainter {
  const _BathhouseSortPreviewPainter({
    required this.scene,
    required this.cycle,
    required this.images,
  });

  final BathhouseSortPreviewScene scene;
  final double cycle;
  final _BathhousePreviewImages? images;

  @override
  void paint(Canvas canvas, Size size) {
    final isHome = scene == BathhouseSortPreviewScene.home;
    final logicalSize = Size(360, isHome ? 462 : 372);
    final scale = math.max(
      size.width / logicalSize.width,
      size.height / logicalSize.height,
    );
    final offset = Offset(
      (size.width - logicalSize.width * scale) / 2,
      (size.height - logicalSize.height * scale) / 2,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;

    if (scene == BathhouseSortPreviewScene.queue) {
      _drawSpeciesGuide(canvas, paint, logicalSize);
      canvas.restore();
      return;
    }
    if (scene == BathhouseSortPreviewScene.unlock) {
      _drawUnlockGuide(canvas, paint, logicalSize);
      canvas.restore();
      return;
    }

    if (images == null) {
      paint.color = const Color(0xFFF5E6CD);
      canvas.drawRect(Offset.zero & logicalSize, paint);
      paint.color = const Color(0xFFDABB93);
      for (var y = 0.0; y < logicalSize.height; y += 30) {
        canvas.drawRect(Rect.fromLTWH(0, y, 360, 2), paint);
      }
    } else {
      canvas.drawImageRect(
        images!.background,
        Rect.fromLTWH(
          0,
          0,
          images!.background.width.toDouble(),
          images!.background.height.toDouble(),
        ),
        Rect.fromLTWH(0, isHome ? -40 : -150, 360, 720),
        paint,
      );
    }

    final frame = BathhouseSortPreviewFrame.fromCycle(cycle);
    final isRed = frame.isWomensTurn;
    final action = frame.actionProgress;
    final departing = frame.isDeparting;
    final targetX = isRed ? 282.0 : 78.0;
    final animatedX = departing
        ? 180 + (targetX - 180) * ((action - 0.58) / 0.42)
        : 180.0;
    final x = scene == BathhouseSortPreviewScene.controls
        ? (isRed ? 218.0 : 142.0)
        : animatedX;
    final alpha = departing
        ? (1 - (action - 0.58) / 0.42).clamp(0.0, 1.0)
        : 1.0;
    final queueColors = <bool>[!isRed, isRed, !isRed, isRed, !isRed, isRed];
    final queueY = isHome
        ? const <double>[215, 180, 154, 135, 120, 108]
        : const <double>[210, 174, 147, 126, 110, 98];
    final queueScale = isHome
        ? const <double>[0.44, 0.36, 0.30, 0.26, 0.22, 0.19]
        : const <double>[0.53, 0.43, 0.35, 0.29, 0.25, 0.22];
    for (var index = queueColors.length - 1; index >= 0; index--) {
      _guest(
        canvas,
        paint,
        180,
        queueY[index],
        red: queueColors[index],
        opacity: 1,
        scale: queueScale[index],
        variant: index % 2,
      );
    }
    _guest(
      canvas,
      paint,
      x,
      isHome ? 310 : 222,
      red: isRed,
      opacity: alpha,
      scale: isHome ? 0.68 : 0.68,
      variant: isRed ? 1 : 0,
    );
    final activeFrame = !departing
        ? 0
        : action < 0.72
        ? 1
        : 2;
    _noren(
      canvas,
      paint,
      isHome ? 12 : 20,
      y: isHome ? 94 : 24,
      size: isHome ? 128 : 116,
      row: 0,
      frame: !isRed && departing ? activeFrame : 0,
    );
    _noren(
      canvas,
      paint,
      isHome ? 220 : 224,
      y: isHome ? 94 : 24,
      size: isHome ? 128 : 116,
      row: 1,
      frame: isRed && departing ? activeFrame : 0,
    );
    _roster(canvas, paint, compact: isHome);

    if (scene == BathhouseSortPreviewScene.home ||
        scene == BathhouseSortPreviewScene.scoring) {
      _hud(canvas, paint, frame, compact: isHome);
    }
    if (departing &&
        (scene == BathhouseSortPreviewScene.home ||
            scene == BathhouseSortPreviewScene.scoring)) {
      _successEffect(canvas, paint, frame, compact: isHome);
    }

    if (scene == BathhouseSortPreviewScene.home) {
      _drawButtons(
        canvas,
        paint,
        y: 398,
        height: 58,
        isRed: isRed,
        action: action,
        compact: true,
      );
    } else if (scene == BathhouseSortPreviewScene.controls) {
      _drawButtons(
        canvas,
        paint,
        y: 304,
        height: 64,
        isRed: isRed,
        action: action,
      );
    } else if (scene == BathhouseSortPreviewScene.scoring) {
      _label(
        canvas,
        paint,
        frame.isDeparting
            ? '+${210 + (frame.combo - 1) * 10}  COMBO!'
            : '정확하게 이어 탭!',
        y: 342,
        accent: true,
      );
    }
    canvas.restore();
  }

  void _drawSpeciesGuide(Canvas canvas, Paint paint, Size logicalSize) {
    _guideBackdrop(canvas, paint, logicalSize);
    const panels = <({Rect rect, Color fill, Color border, String title})>[
      (
        rect: Rect.fromLTWH(8, 16, 169, 340),
        fill: Color(0xFFE7F1FA),
        border: Color(0xFF23588E),
        title: '남자 동물 · 파란 옷',
      ),
      (
        rect: Rect.fromLTWH(183, 16, 169, 340),
        fill: Color(0xFFFFE9E8),
        border: Color(0xFFA52D39),
        title: '여자 동물 · 빨간 옷',
      ),
    ];
    const labels = <String>[
      '흑곰',
      '갈색 강아지',
      '너구리',
      '회색 늑대',
      '흰토끼',
      '핑크돼지',
      '크림 양',
      '치즈 고양이',
    ];

    for (var side = 0; side < panels.length; side++) {
      final panel = panels[side];
      paint
        ..style = PaintingStyle.fill
        ..color = panel.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(panel.rect, const Radius.circular(10)),
        paint,
      );
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = panel.border;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          panel.rect.deflate(2),
          const Radius.circular(8),
        ),
        paint,
      );
      paint.style = PaintingStyle.fill;
      _text(
        canvas,
        panel.title,
        Offset(panel.rect.center.dx, 42),
        14,
        panel.border,
      );

      for (var row = 0; row < 4; row++) {
        final spriteIndex = side * 4 + row;
        final centerY = 91.0 + row * 69;
        if (row.isEven) {
          paint.color = panel.border.withValues(alpha: 0.07);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(panel.rect.left + 7, centerY - 29, 155, 60),
              const Radius.circular(7),
            ),
            paint,
          );
        }
        _guideGuest(
          canvas,
          paint,
          spriteIndex,
          Offset(panel.rect.left + 37, centerY + 22),
          0.27,
        );
        _text(
          canvas,
          labels[spriteIndex],
          Offset(panel.rect.left + 105, centerY + 2),
          labels[spriteIndex].length > 5 ? 11 : 13,
          const Color(0xFF281913),
        );
      }
    }
  }

  void _drawUnlockGuide(Canvas canvas, Paint paint, Size logicalSize) {
    _guideBackdrop(canvas, paint, logicalSize);
    _text(
      canvas,
      '시간이 지날수록 새 동물 등장!',
      const Offset(180, 34),
      16,
      const Color(0xFF4B2B18),
    );
    const moments = <String>['처음', '15초', '30초', '45초'];
    const pairLabels = <String>[
      '흑곰  +  흰토끼',
      '강아지  +  핑크돼지',
      '너구리  +  크림 양',
      '늑대  +  치즈 고양이',
    ];
    for (var row = 0; row < 4; row++) {
      final top = 56.0 + row * 74;
      final rect = Rect.fromLTWH(10, top, 340, 68);
      final unlocked = row == 0;
      paint
        ..style = PaintingStyle.fill
        ..color = unlocked ? const Color(0xFFFFF3C4) : const Color(0xFFF7E7D1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(9)),
        paint,
      );
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = unlocked ? const Color(0xFFD89A24) : const Color(0xFF8C6244);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1.5), const Radius.circular(8)),
        paint,
      );
      paint.style = PaintingStyle.fill;

      final badge = Rect.fromLTWH(18, top + 12, 62, 44);
      paint.color = unlocked
          ? const Color(0xFFD89A24)
          : const Color(0xFF6A4531);
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, const Radius.circular(7)),
        paint,
      );
      _text(canvas, moments[row], badge.center, 14, Colors.white);
      _guideGuest(canvas, paint, row, Offset(112, top + 58), 0.22);
      _text(canvas, '+', Offset(160, top + 34), 20, const Color(0xFF4B2B18));
      _guideGuest(canvas, paint, row + 4, Offset(208, top + 58), 0.22);
      _text(
        canvas,
        pairLabels[row],
        Offset(281, top + 34),
        10,
        const Color(0xFF4B2B18),
      );
      if (row > 0) {
        _text(
          canvas,
          '새로 추가',
          Offset(281, top + 50),
          9,
          const Color(0xFFA52D39),
        );
      }
    }
  }

  void _guideBackdrop(Canvas canvas, Paint paint, Size logicalSize) {
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFF2DDBF);
    canvas.drawRect(Offset.zero & logicalSize, paint);
    paint.color = const Color(0xFFD0AD7A).withValues(alpha: 0.38);
    for (var y = 0.0; y < logicalSize.height; y += 24) {
      canvas.drawRect(Rect.fromLTWH(0, y, logicalSize.width, 2), paint);
    }
  }

  void _guideGuest(
    Canvas canvas,
    Paint paint,
    int spriteIndex,
    Offset bottomCenter,
    double scale,
  ) {
    if (images == null) {
      _guest(
        canvas,
        paint,
        bottomCenter.dx,
        bottomCenter.dy,
        red: spriteIndex >= 4,
        opacity: 1,
        scale: scale,
        variant: spriteIndex % 4,
      );
      return;
    }
    paint.color = Colors.white;
    canvas.drawImageRect(
      images!.guests,
      Rect.fromLTWH(
        (spriteIndex % 4) * 112.0,
        (spriteIndex ~/ 4) * 224.0,
        112,
        224,
      ),
      Rect.fromLTWH(
        bottomCenter.dx - 56 * scale,
        bottomCenter.dy - 224 * scale,
        112 * scale,
        224 * scale,
      ),
      paint,
    );
  }

  void _drawButtons(
    Canvas canvas,
    Paint paint, {
    required double y,
    required double height,
    required bool isRed,
    required double action,
    bool compact = false,
  }) {
    final margin = compact ? 8.0 : 6.0;
    final gap = compact ? 10.0 : 12.0;
    final width = (360 - margin * 2 - gap) / 2;
    _previewTapButton(
      canvas,
      paint,
      Rect.fromLTWH(margin, y, width, height),
      male: true,
      fill: const Color(0xFF123F73),
      selected: !isRed,
    );
    _previewTapButton(
      canvas,
      paint,
      Rect.fromLTWH(margin + width + gap, y, width, height),
      male: false,
      fill: const Color(0xFF8F2330),
      selected: isRed,
    );
    if (action > 0.32 && action < 0.64) {
      final target = Offset(isRed ? 270 : 90, y + height / 2);
      final pulse = math.sin((action - 0.32) / 0.32 * math.pi).clamp(0.0, 1.0);
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.9 * pulse);
      canvas.drawCircle(target, 18 + 10 * pulse, paint);
      paint
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.9);
      canvas.drawCircle(target, 7, paint);
    }
  }

  void _noren(
    Canvas canvas,
    Paint paint,
    double x, {
    required double y,
    required double size,
    required int row,
    required int frame,
  }) {
    if (images != null) {
      canvas.drawImageRect(
        images!.noren,
        Rect.fromLTWH(frame * 80.0, row * 80.0, 80, 80),
        Rect.fromLTWH(x, y, size, size),
        paint,
      );
      return;
    }
    paint.color = row == 0 ? const Color(0xFF142D64) : const Color(0xFFC92F24);
    canvas.drawRect(Rect.fromLTWH(x + 8, y + 8, size - 16, size - 16), paint);
    if (row == 0) {
      _text(canvas, '男', Offset(x + size / 2, y + size / 2), 38, Colors.white);
    } else {
      _text(canvas, '女', Offset(x + size / 2, y + size / 2), 38, Colors.white);
    }
  }

  void _roster(Canvas canvas, Paint paint, {required bool compact}) {
    final visibleCount = switch (scene) {
      BathhouseSortPreviewScene.unlock => 2,
      BathhouseSortPreviewScene.home ||
      BathhouseSortPreviewScene.controls ||
      BathhouseSortPreviewScene.queue => 2,
      BathhouseSortPreviewScene.scoring => 4,
    };
    final itemSize = compact ? 48.0 : 46.0;
    final startY = compact ? 220.0 : 148.0;
    final spacing = compact ? 54.0 : 48.0;
    for (var index = 0; index < visibleCount; index++) {
      _rosterFace(
        canvas,
        paint,
        x: compact ? 7 : 6,
        y: startY + index * spacing,
        size: itemSize,
        spriteIndex: index,
        highlighted:
            scene == BathhouseSortPreviewScene.unlock &&
            index == visibleCount - 1,
      );
      _rosterFace(
        canvas,
        paint,
        x: 360 - (compact ? 7 : 6) - itemSize,
        y: startY + index * spacing,
        size: itemSize,
        spriteIndex: index + 4,
        highlighted:
            scene == BathhouseSortPreviewScene.unlock &&
            index == visibleCount - 1,
      );
    }
  }

  void _rosterFace(
    Canvas canvas,
    Paint paint, {
    required double x,
    required double y,
    required double size,
    required int spriteIndex,
    required bool highlighted,
  }) {
    final radius = size / 2;
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF1C130E).withValues(alpha: 0.58);
    canvas.drawCircle(Offset(x + radius, y + radius), radius, paint);
    if (images != null) {
      canvas.drawImageRect(
        images!.guests,
        Rect.fromLTWH(
          (spriteIndex % 4) * 112.0,
          (spriteIndex ~/ 4) * 224.0,
          112,
          112,
        ),
        Rect.fromLTWH(x, y - size * 0.12, size, size),
        paint,
      );
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFF24160F);
    canvas.drawCircle(Offset(x + radius, y + radius), radius, paint);
    paint
      ..strokeWidth = 2
      ..color = spriteIndex < 4
          ? const Color(0xFF86C8FF)
          : const Color(0xFFFF9A9F);
    canvas.drawCircle(Offset(x + radius, y + radius), radius - 1.8, paint);
    if (highlighted) {
      paint
        ..color = const Color(0xFFFFD66B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(x + radius, y + radius), radius + 3, paint);
      paint.style = PaintingStyle.fill;
    }
  }

  void _hud(
    Canvas canvas,
    Paint paint,
    BathhouseSortPreviewFrame frame, {
    required bool compact,
  }) {
    final y = compact ? 10.0 : 4.0;
    final height = compact ? 34.0 : 25.0;
    final labels = <(Rect, String)>[
      (Rect.fromLTWH(5, y, 102, height), 'SCORE ${frame.score}'),
      (Rect.fromLTWH(118, y, 122, height), 'COMBO ${frame.combo}'),
      (Rect.fromLTWH(251, y, 104, height), 'TIME ${frame.secondsLeft}'),
    ];
    for (final item in labels) {
      paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF120B08).withValues(alpha: 0.82);
      canvas.drawRRect(
        RRect.fromRectAndRadius(item.$1, const Radius.circular(5)),
        paint,
      );
      _text(
        canvas,
        item.$2,
        item.$1.center,
        compact ? 11 : 11,
        const Color(0xFFFFE7A0),
      );
    }
  }

  void _successEffect(
    Canvas canvas,
    Paint paint,
    BathhouseSortPreviewFrame frame, {
    required bool compact,
  }) {
    final progress = ((frame.actionProgress - 0.58) / 0.42).clamp(0.0, 1.0);
    final opacity = (1 - progress).clamp(0.25, 1.0);
    final center = Offset(180, compact ? 70 : 82);
    final fxFrame = (progress * 4).floor().clamp(0, 3);
    if (images != null) {
      paint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawImageRect(
        images!.feedback,
        Rect.fromLTWH(fxFrame * 32.0, 0, 32, 32),
        Rect.fromCenter(
          center: center,
          width: compact ? 72 : 92,
          height: compact ? 72 : 92,
        ),
        paint,
      );
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFFFD45C).withValues(alpha: opacity);
    canvas.drawCircle(center, 23 + progress * 22, paint);
    paint.style = PaintingStyle.fill;
  }

  void _label(
    Canvas canvas,
    Paint paint,
    String label, {
    required double y,
    bool accent = false,
  }) {
    final rect = Rect.fromCenter(
      center: Offset(180, y),
      width: 272,
      height: 38,
    );
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF120B08).withValues(alpha: 0.88);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent ? const Color(0xFFFFD45C) : const Color(0xFFFFE7A0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(6)),
      paint,
    );
    paint.style = PaintingStyle.fill;
    _text(
      canvas,
      label,
      rect.center,
      16,
      accent ? const Color(0xFFFFD45C) : Colors.white,
    );
  }

  void _previewTapButton(
    Canvas canvas,
    Paint paint,
    Rect rect, {
    required bool male,
    required Color fill,
    required bool selected,
  }) {
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(11));
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF120B08).withValues(alpha: 0.72);
    canvas.drawRRect(outer.shift(const Offset(0, 3)), paint);
    paint.color = selected ? const Color(0xFFFFF0A2) : const Color(0xFFFFD66B);
    canvas.drawRRect(outer, paint);
    paint.color = fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(7)),
      paint,
    );
    _hanja(
      canvas,
      paint,
      male: male,
      center: rect.center.translate(1.5, 2),
      scale: selected ? 1.08 : 0.98,
      color: const Color(0xFF120B08).withValues(alpha: 0.65),
    );
    _hanja(
      canvas,
      paint,
      male: male,
      center: rect.center,
      scale: selected ? 1.08 : 0.98,
      color: Colors.white,
    );
  }

  void _guest(
    Canvas canvas,
    Paint paint,
    double x,
    double y, {
    required bool red,
    required double opacity,
    double scale = 1,
    int variant = 0,
  }) {
    if (images != null) {
      final index = (red ? 4 : 0) + variant % 4;
      paint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawImageRect(
        images!.guests,
        Rect.fromLTWH((index % 4) * 112.0, (index ~/ 4) * 224.0, 112, 224),
        Rect.fromLTWH(
          x - 56 * scale,
          y - 111 * scale,
          112 * scale,
          224 * scale,
        ),
        paint,
      );
      paint.color = Colors.white;
      return;
    }
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scale);
    paint.color = const Color(0xFF7A4632).withValues(alpha: opacity);
    canvas.drawCircle(const Offset(0, -48), 31, paint);
    paint.color = const Color(0xFF251B18).withValues(alpha: opacity);
    for (var i = -2; i <= 2; i++) {
      canvas.drawCircle(Offset(i * 11, -71 + i.abs() * 2), 10, paint);
    }
    paint.color = const Color(0xFF211A17).withValues(alpha: opacity);
    canvas.drawRect(const Rect.fromLTWH(-12, -50, 4, 4), paint);
    canvas.drawRect(const Rect.fromLTWH(8, -50, 4, 4), paint);
    paint.color = (red ? const Color(0xFFE04859) : const Color(0xFF2384D1))
        .withValues(alpha: opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-43, -8, 86, 122),
        const Radius.circular(16),
      ),
      paint,
    );
    paint.color = Colors.white.withValues(alpha: opacity);
    canvas.drawRect(const Rect.fromLTWH(-4, -8, 8, 108), paint);
    if (red) {
      canvas.drawCircle(const Offset(0, 33), 13, paint);
    } else {
      canvas.drawRect(const Rect.fromLTWH(-12, 21, 24, 24), paint);
    }
    canvas.restore();
  }

  void _hanja(
    Canvas canvas,
    Paint paint, {
    required bool male,
    required Offset center,
    required double scale,
    required Color color,
  }) {
    final path = Path();
    if (male) {
      path
        ..addRect(const Rect.fromLTWH(-16, -20, 32, 23))
        ..moveTo(-16, -8)
        ..lineTo(16, -8)
        ..moveTo(0, -20)
        ..lineTo(0, 3)
        ..moveTo(-10, 10)
        ..lineTo(13, 10)
        ..lineTo(9, 23)
        ..lineTo(3, 23)
        ..moveTo(2, 3)
        ..lineTo(-4, 23);
    } else {
      path
        ..moveTo(4, -21)
        ..lineTo(-8, 8)
        ..lineTo(14, 22)
        ..moveTo(-17, -1)
        ..lineTo(17, 4)
        ..moveTo(13, -16)
        ..lineTo(3, 9)
        ..lineTo(-14, 21);
    }
    paint
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.drawPath(path, paint);
    canvas.restore();
    paint
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.butt;
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: 'Galmuri',
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _BathhouseSortPreviewPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.images != images ||
      (oldDelegate.cycle - cycle).abs() > 1 / math.max(1, 2400);
}
