import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum LilyFrogPreviewScene {
  home,
  orbit,
  tangent,
  speed,
  scoring,
  bonus,
  failure,
}

class LilyFrogPreview extends StatefulWidget {
  const LilyFrogPreview({super.key, required this.scene, this.animate = true});

  final LilyFrogPreviewScene scene;
  final bool animate;

  @override
  State<LilyFrogPreview> createState() => _LilyFrogPreviewState();
}

class _LilyFrogPreviewState extends State<LilyFrogPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  _LilyFrogImages? _images;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
    unawaited(_loadImages());
  }

  Future<void> _loadImages() async {
    final loaded = <ui.Image>[];
    try {
      for (final path in _LilyFrogImages.assetPaths) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        loaded.add(frame.image);
      }
      final images = _LilyFrogImages(loaded);
      if (!mounted) {
        images.dispose();
        return;
      }
      setState(() => _images = images);
    } catch (error, stackTrace) {
      debugPrint('Lily frog preview asset load failed: $error\n$stackTrace');
      for (final image in loaded) {
        image.dispose();
      }
    }
  }

  @override
  void didUpdateWidget(covariant LilyFrogPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate == widget.animate) return;
    widget.animate ? _controller.repeat() : _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    _images?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => KeyedSubtree(
      key: Key(
        _images == null
            ? 'lily-frog-preview-loading'
            : 'lily-frog-preview-ready',
      ),
      child: CustomPaint(
        key: const Key('lily-frog-preview'),
        painter: _LilyFrogPreviewPainter(
          scene: widget.scene,
          cycle: widget.animate ? _controller.value : 0.16,
          images: _images,
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _LilyFrogImages {
  _LilyFrogImages(List<ui.Image> images)
    : background = images[0],
      frog = images[1],
      lilies = images[2],
      goldenLilies = images[3],
      fly = images[4],
      flyCollect = images[5],
      water = images[6];

  static const assetPaths = <String>[
    'assets/images/lily_frog/pond_background.png',
    'assets/images/lily_frog/frog_actions_atlas.png',
    'assets/images/lily_frog/lily_pad_atlas.png',
    'assets/images/lily_frog/golden_lily_pad_atlas.png',
    'assets/images/lily_frog/fly_sheet.png',
    'assets/images/lily_frog/fly_collect_fx_atlas.png',
    'assets/images/lily_frog/water_fx_atlas.png',
  ];

  final ui.Image background;
  final ui.Image frog;
  final ui.Image lilies;
  final ui.Image goldenLilies;
  final ui.Image fly;
  final ui.Image flyCollect;
  final ui.Image water;

  void dispose() {
    background.dispose();
    frog.dispose();
    lilies.dispose();
    goldenLilies.dispose();
    fly.dispose();
    flyCollect.dispose();
    water.dispose();
  }
}

class _LilyFrogPreviewPainter extends CustomPainter {
  const _LilyFrogPreviewPainter({
    required this.scene,
    required this.cycle,
    required this.images,
  });

  final LilyFrogPreviewScene scene;
  final double cycle;
  final _LilyFrogImages? images;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (scene != LilyFrogPreviewScene.home) {
      final scale = size.width / 360;
      final logicalHeight = size.height / scale;
      canvas.scale(scale);
      canvas.clipRect(Rect.fromLTWH(0, 0, 360, logicalHeight));
      final paint = Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none;
      final art = images;
      if (art == null) {
        paint.color = const Color(0xFF093444);
        canvas.drawRect(Rect.fromLTWH(0, 0, 360, logicalHeight), paint);
      } else {
        _paintGuide(canvas, logicalHeight, paint, art);
      }
      canvas.restore();
      return;
    }
    canvas.scale(size.width / 360, size.height / 460);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 360, 460));
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    final art = images;
    if (art == null) {
      paint.color = const Color(0xFF093444);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 360, 460), paint);
      canvas.restore();
      return;
    }
    canvas.drawImageRect(
      art.background,
      const Rect.fromLTWH(0, 76, 180, 230),
      const Rect.fromLTWH(0, 0, 360, 460),
      paint,
    );

    final turn =
        cycle * math.pi * 2 * (scene == LilyFrogPreviewScene.speed ? 1.8 : 1);
    _lily(canvas, paint, art.lilies, 104, 320, row: 0, column: 4, angle: turn);
    _lily(
      canvas,
      paint,
      art.lilies,
      272,
      196,
      row: 1,
      column: 2,
      angle: -turn * 0.9,
    );
    final bonusScene = scene == LilyFrogPreviewScene.bonus;
    _lily(
      canvas,
      paint,
      bonusScene ? art.goldenLilies : art.lilies,
      104,
      80,
      row: bonusScene ? 0 : 2,
      column: bonusScene ? 0 : 1,
      angle: turn * 1.1,
    );
    if (scene == LilyFrogPreviewScene.home) {
      _hud(canvas, 'SCORE', cycle < 0.70 ? '680' : '810', const Offset(68, 26));
      _hud(canvas, 'TIME', cycle < 0.40 ? '248' : '247', const Offset(292, 26));
    }
    if (scene == LilyFrogPreviewScene.scoring) {
      _dottedPath(
        canvas,
        const Offset(151, 305),
        const Offset(272, 196),
        markerRadius: 20,
      );
      _label(canvas, '새 연잎 착지 300 + 콤보×10', const Offset(180, 28), 17);
      _label(canvas, '게이지가 비기 전에 점프', const Offset(180, 376), 17);
    }
    if (bonusScene) {
      for (var index = 0; index < 3; index++) {
        _sheetCell(
          canvas,
          paint,
          art.fly,
          index,
          0,
          32,
          Rect.fromLTWH(160 + index * 30, 268 - index * 22, 32, 32),
        );
      }
      _sheetCell(
        canvas,
        paint,
        art.flyCollect,
        2,
        0,
        64,
        const Rect.fromLTWH(181, 226, 64, 64),
      );
      _label(canvas, '5번째! 황금 착지 1,000', const Offset(180, 28), 17);
      _label(canvas, '파리는 일반 길에서 POP!', const Offset(180, 376), 17);
    }

    final staticScene =
        scene != LilyFrogPreviewScene.home &&
        scene != LilyFrogPreviewScene.speed;
    final t = staticScene ? 0.16 : cycle;
    Offset frogCenter;
    int frogRow;
    if (scene == LilyFrogPreviewScene.failure) {
      frogCenter = const Offset(210, 298);
      frogRow = 3;
      _sheetCell(
        canvas,
        paint,
        art.water,
        2,
        1,
        64,
        const Rect.fromLTWH(178, 268, 64, 64),
      );
      _label(canvas, '풍덩! 즉시 종료', const Offset(180, 376), 19);
    } else if (scene == LilyFrogPreviewScene.tangent) {
      frogCenter = const Offset(170, 253);
      frogRow = 0;
      _dottedPath(
        canvas,
        const Offset(151, 305),
        const Offset(230, 235),
        markerRadius: 14,
      );
      _label(canvas, '점선 끝이 연잎일 때 TAP', const Offset(180, 376), 17);
    } else if (scene == LilyFrogPreviewScene.orbit) {
      frogCenter = const Offset(170, 253);
      frogRow = 0;
      _label(canvas, '화면 아무 곳이나 TAP', const Offset(180, 376), 18);
    } else if (scene == LilyFrogPreviewScene.speed) {
      final theta = -0.8 + cycle * math.pi * 3.6;
      frogCenter = Offset(
        104 + math.cos(theta) * 94,
        320 + math.sin(theta) * 94,
      );
      frogRow = 0;
      _orbitTicks(canvas, const Offset(104, 320), 103, cycle);
      _label(canvas, '초반 1.35  →  140초에 2.80', const Offset(180, 28), 17);
      _label(canvas, '140초부터 최고 속도 유지', const Offset(180, 376), 17);
    } else if (scene == LilyFrogPreviewScene.scoring) {
      frogCenter = const Offset(206, 252);
      frogRow = 1;
    } else {
      final jump = ((t - 0.40) / 0.30).clamp(0.0, 1.0);
      if (t < 0.40) {
        final theta = -0.8 + t / 0.40 * 1.25;
        frogCenter = Offset(
          104 + math.cos(theta) * 94,
          320 + math.sin(theta) * 94,
        );
        frogRow = 0;
        if (scene == LilyFrogPreviewScene.home) {
          _dottedPath(
            canvas,
            frogCenter,
            const Offset(225, 238),
            markerRadius: 12,
          );
        }
      } else if (t < 0.70) {
        frogCenter = Offset.lerp(
          const Offset(188, 279),
          const Offset(209, 247),
          jump,
        )!;
        frogCenter = frogCenter.translate(0, -math.sin(math.pi * jump) * 18);
        frogRow = 1;
        if (scene == LilyFrogPreviewScene.home) {
          _dottedPath(
            canvas,
            const Offset(188, 279),
            const Offset(225, 238),
            markerRadius: 12,
          );
          for (var index = 0; index < 2; index++) {
            _sheetCell(
              canvas,
              paint,
              art.fly,
              (frameForCycle(t) + index) % 4,
              0,
              32,
              Rect.fromCenter(
                center: Offset(198 + index * 13, 266 - index * 13),
                width: 28,
                height: 28,
              ),
            );
          }
          if (t > 0.54) {
            _sheetCell(
              canvas,
              paint,
              art.flyCollect,
              2,
              0,
              64,
              const Rect.fromLTWH(176, 232, 56, 56),
            );
          }
        }
      } else {
        final theta = 2.45 - (t - 0.70) / 0.30 * 1.0;
        frogCenter = Offset(
          272 + math.cos(theta) * 78,
          196 + math.sin(theta) * 78,
        );
        frogRow = 0;
      }
      if (!bonusScene) {
        _label(
          canvas,
          t < 0.40
              ? '점선이 닿을 때 TAP'
              : t < 0.70
              ? '파리 POP! +100'
              : '착지 300 + 콤보×10',
          const Offset(180, 410),
          18,
        );
      }
    }
    final frame = frameForCycle(t);
    _sheetCell(
      canvas,
      paint,
      art.frog,
      scene == LilyFrogPreviewScene.failure ? 3 : frame,
      frogRow,
      56,
      Rect.fromCenter(center: frogCenter, width: 56, height: 56),
    );
    canvas.restore();
  }

  void _paintGuide(
    Canvas canvas,
    double height,
    Paint paint,
    _LilyFrogImages art,
  ) {
    canvas.drawImageRect(
      art.background,
      const Rect.fromLTWH(0, 70, 180, 180),
      Rect.fromLTWH(0, 0, 360, height),
      paint,
    );
    final turn =
        cycle * math.pi * 2 * (scene == LilyFrogPreviewScene.speed ? 1.8 : 1);
    final lower = Offset(120, height - 140);
    final right = Offset(272, height - 154);
    const upper = Offset(92, 62);
    final bonus = scene == LilyFrogPreviewScene.bonus;

    _lily(
      canvas,
      paint,
      art.lilies,
      lower.dx,
      lower.dy,
      row: 0,
      column: 4,
      angle: turn,
      size: 166,
    );
    _lily(
      canvas,
      paint,
      art.lilies,
      right.dx,
      right.dy,
      row: 1,
      column: 2,
      angle: -turn * 0.9,
      size: 154,
    );
    _lily(
      canvas,
      paint,
      bonus ? art.goldenLilies : art.lilies,
      upper.dx,
      upper.dy,
      row: bonus ? 0 : 2,
      column: bonus ? 0 : 1,
      angle: turn * 1.1,
      size: bonus ? 112 : 138,
    );

    Offset frogCenter;
    var frogRow = 0;
    if (scene == LilyFrogPreviewScene.orbit) {
      final theta = -0.7 + cycle * math.pi * 2;
      frogCenter = lower + Offset(math.cos(theta), math.sin(theta)) * 78;
      _label(canvas, '화면 아무 곳이나 TAP', Offset(180, height - 20), 17);
    } else if (scene == LilyFrogPreviewScene.tangent) {
      frogCenter = Offset(154, height - 119);
      _dottedPath(
        canvas,
        frogCenter,
        Offset(right.dx - 35, right.dy + 18),
        markerRadius: 13,
      );
      _label(canvas, '점선 끝이 연잎일 때 TAP', Offset(180, height - 20), 16);
    } else if (scene == LilyFrogPreviewScene.speed) {
      final theta = -0.7 + cycle * math.pi * 3.6;
      frogCenter = lower + Offset(math.cos(theta), math.sin(theta)) * 78;
      _orbitTicks(canvas, lower, 84, cycle);
      _label(canvas, '초반 1.35  →  140초에 2.80', const Offset(180, 20), 16);
      _label(canvas, '140초부터 최고 속도 유지', Offset(180, height - 20), 16);
    } else if (scene == LilyFrogPreviewScene.scoring) {
      frogCenter = Offset(176, height - 126);
      frogRow = 1;
      _dottedPath(canvas, Offset(148, height - 116), right, markerRadius: 18);
      _label(canvas, '새 연잎 착지 300 + 콤보×10', const Offset(180, 20), 16);
      _label(canvas, '게이지가 비기 전에 점프', Offset(180, height - 20), 16);
    } else if (scene == LilyFrogPreviewScene.bonus) {
      frogCenter = Offset(174, height - 127);
      frogRow = 1;
      for (var index = 0; index < 3; index++) {
        _sheetCell(
          canvas,
          paint,
          art.fly,
          index,
          0,
          32,
          Rect.fromCenter(
            center: Offset(190 + index * 19, height - 126 - index * 7),
            width: 27,
            height: 27,
          ),
        );
      }
      _sheetCell(
        canvas,
        paint,
        art.flyCollect,
        2,
        0,
        64,
        Rect.fromCenter(
          center: Offset(226, height - 142),
          width: 50,
          height: 50,
        ),
      );
      _label(canvas, '5번째! 황금 착지 1,000', const Offset(180, 20), 16);
      _label(canvas, '파리는 일반 길에서 POP!', Offset(180, height - 20), 16);
    } else {
      frogCenter = Offset(190, height - 118);
      frogRow = 3;
      _sheetCell(
        canvas,
        paint,
        art.water,
        2,
        1,
        64,
        Rect.fromCenter(center: frogCenter, width: 58, height: 58),
      );
      _label(canvas, '풍덩! 즉시 종료', Offset(180, height - 20), 18);
    }

    _sheetCell(
      canvas,
      paint,
      art.frog,
      scene == LilyFrogPreviewScene.failure ? 3 : frameForCycle(cycle),
      frogRow,
      56,
      Rect.fromCenter(center: frogCenter, width: 48, height: 48),
    );
  }

  void _lily(
    Canvas canvas,
    Paint paint,
    ui.Image image,
    double x,
    double y, {
    required int row,
    required int column,
    required double angle,
    double size = 256,
  }) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    _sheetCell(
      canvas,
      paint,
      image,
      column,
      row,
      256,
      Rect.fromLTWH(-size / 2, -size / 2, size, size),
    );
    canvas.restore();
  }

  void _sheetCell(
    Canvas canvas,
    Paint paint,
    ui.Image image,
    int column,
    int row,
    double cell,
    Rect destination,
  ) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(column * cell, row * cell, cell, cell),
      destination,
      paint,
    );
  }

  int frameForCycle(double value) => ((value * 12).floor() % 4);

  void _dottedPath(
    Canvas canvas,
    Offset start,
    Offset end, {
    required double markerRadius,
  }) {
    final outline = Paint()
      ..color = const Color(0xE6102638)
      ..style = PaintingStyle.fill;
    final paint = Paint()
      ..color = const Color(0xFFFFE36B)
      ..style = PaintingStyle.fill;
    for (var index = 1; index <= 8; index++) {
      final point = Offset.lerp(start, end, index / 9)!;
      final radius = index.isEven ? 3.2 : 2.3;
      canvas.drawCircle(point, radius + 2, outline);
      canvas.drawCircle(point, radius, paint);
    }
    outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(end, markerRadius, outline);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(end, markerRadius, paint);
  }

  void _orbitTicks(Canvas canvas, Offset center, double radius, double cycle) {
    final paint = Paint()
      ..color = const Color(0xB3FFF1A1)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 5; index++) {
      final angle = cycle * math.pi * 3.6 - index * 0.16;
      final start = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final end =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (radius + 10 + index * 2);
      canvas.drawLine(start, end, paint);
    }
  }

  void _hud(Canvas canvas, String title, String value, Offset center) {
    final background = Paint()..color = const Color(0xD9143850);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 104, height: 38),
        const Radius.circular(8),
      ),
      background,
    );
    _label(canvas, '$title  $value', center, 13);
  }

  void _label(Canvas canvas, String text, Offset center, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          fontWeight: FontWeight.w900,
          fontFamily: 'Galmuri',
          shadows: const [Shadow(color: Colors.black, offset: Offset(2, 2))],
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
  bool shouldRepaint(covariant _LilyFrogPreviewPainter oldDelegate) =>
      oldDelegate.cycle != cycle ||
      oldDelegate.scene != scene ||
      oldDelegate.images != images;
}
