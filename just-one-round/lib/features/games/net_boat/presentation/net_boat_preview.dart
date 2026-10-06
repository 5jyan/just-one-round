import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/games/net_boat/net_boat_net_painter.dart';

enum NetBoatPreviewScene {
  home,
  turn,
  close,
  score,
  difficulty,
  failure,
  limit,
}

@immutable
class NetBoatPreviewFrame {
  const NetBoatPreviewFrame({
    required this.boat,
    required this.direction,
    required this.net,
    required this.captured,
    required this.score,
    required this.secondsLeft,
  });

  factory NetBoatPreviewFrame.fromCycle(double cycle) {
    final value = cycle % 1;
    const start = Offset(90, 346);
    const topLeft = Offset(90, 190);
    const topRight = Offset(300, 190);
    const bottomRight = Offset(300, 346);
    final captured = value >= 0.82;
    if (captured) {
      return const NetBoatPreviewFrame(
        boat: start,
        direction: 3,
        net: [start, topLeft, topRight, bottomRight, start],
        captured: true,
        score: 2500,
        secondsLeft: 164,
      );
    }
    final travel = value / 0.82 * 4;
    if (travel < 1) {
      return NetBoatPreviewFrame(
        boat: Offset.lerp(start, topLeft, travel)!,
        direction: 0,
        net: [start],
        captured: false,
        score: 0,
        secondsLeft: 166,
      );
    }
    if (travel < 2) {
      return NetBoatPreviewFrame(
        boat: Offset.lerp(topLeft, topRight, travel - 1)!,
        direction: 1,
        net: const [start, topLeft],
        captured: false,
        score: 0,
        secondsLeft: 165,
      );
    }
    if (travel < 3) {
      return NetBoatPreviewFrame(
        boat: Offset.lerp(topRight, bottomRight, travel - 2)!,
        direction: 2,
        net: const [start, topLeft, topRight],
        captured: false,
        score: 0,
        secondsLeft: 165,
      );
    }
    return NetBoatPreviewFrame(
      boat: Offset.lerp(bottomRight, start, travel - 3)!,
      direction: 3,
      net: const [start, topLeft, topRight, bottomRight],
      captured: false,
      score: 0,
      secondsLeft: 164,
    );
  }

  final Offset boat;
  final int direction;
  final List<Offset> net;
  final bool captured;
  final int score;
  final int secondsLeft;
}

class NetBoatPreview extends StatefulWidget {
  const NetBoatPreview({
    super.key,
    required this.scene,
    this.animate = true,
    this.staticCycle = 0.58,
  });

  final NetBoatPreviewScene scene;
  final bool animate;
  final double staticCycle;

  @override
  State<NetBoatPreview> createState() => _NetBoatPreviewState();
}

class _NetBoatPreviewState extends State<NetBoatPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );
  _NetBoatPreviewImages? _images;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
    unawaited(_loadImages());
  }

  Future<void> _loadImages() async {
    final loaded = <ui.Image>[];
    try {
      for (final path in _NetBoatPreviewImages.assetPaths) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        loaded.add(frame.image);
      }
      final images = _NetBoatPreviewImages(loaded);
      if (!mounted) {
        images.dispose();
        return;
      }
      setState(() => _images = images);
    } catch (error, stackTrace) {
      debugPrint('Net boat preview asset load failed: $error\n$stackTrace');
      for (final image in loaded) {
        image.dispose();
      }
    }
  }

  @override
  void didUpdateWidget(covariant NetBoatPreview oldWidget) {
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
    key: const Key('net-boat-preview-clip'),
    clipBehavior: Clip.hardEdge,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        key: const Key('net-boat-preview'),
        painter: _NetBoatPreviewPainter(
          scene: widget.scene,
          cycle: widget.animate ? _controller.value : widget.staticCycle,
          images: _images,
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _NetBoatPreviewImages {
  _NetBoatPreviewImages(List<ui.Image> images)
    : background = images[0],
      boat = images[1],
      sardine = images[2],
      piranha = images[3],
      marlin = images[4],
      shark = images[5],
      sharkWake = images[6],
      whale = images[7],
      reefs = images[8],
      effects = images[9];

  static const assetPaths = <String>[
    'assets/images/net_boat/sea_background.png',
    'assets/images/net_boat/boat_navigation_atlas.png',
    'assets/images/net_boat/sardine_atlas.png',
    'assets/images/net_boat/piranha_atlas.png',
    'assets/images/net_boat/marlin_atlas.png',
    'assets/images/net_boat/shark_fin_atlas.png',
    'assets/images/net_boat/shark_wake_atlas.png',
    'assets/images/net_boat/whale_atlas.png',
    'assets/images/net_boat/reef_modules_atlas.png',
    'assets/images/net_boat/net_capture_fx_atlas.png',
  ];

  final ui.Image background;
  final ui.Image boat;
  final ui.Image sardine;
  final ui.Image piranha;
  final ui.Image marlin;
  final ui.Image shark;
  final ui.Image sharkWake;
  final ui.Image whale;
  final ui.Image reefs;
  final ui.Image effects;

  void dispose() {
    background.dispose();
    boat.dispose();
    sardine.dispose();
    piranha.dispose();
    marlin.dispose();
    shark.dispose();
    sharkWake.dispose();
    whale.dispose();
    reefs.dispose();
    effects.dispose();
  }
}

class _NetBoatPreviewPainter extends CustomPainter {
  _NetBoatPreviewPainter({
    required this.scene,
    required this.cycle,
    required this.images,
  }) : _netPainter = NetBoatNetPainter();

  final NetBoatPreviewScene scene;
  final double cycle;
  final _NetBoatPreviewImages? images;
  final NetBoatNetPainter _netPainter;
  static final _smoothFishPaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high;

  @override
  void paint(Canvas canvas, Size size) {
    const logical = Size(360, 462);
    final scale = math.max(
      size.width / logical.width,
      size.height / logical.height,
    );
    final offset = Offset(
      (size.width - logical.width * scale) / 2,
      (size.height - logical.height * scale) / 2,
    );
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    if (images == null) {
      canvas.drawRect(
        Offset.zero & logical,
        paint..color = const Color(0xFF209DA2),
      );
      canvas.restore();
      return;
    }
    _drawImage(
      canvas,
      images!.background,
      const Rect.fromLTWH(0, 160, 360, 462),
      Offset.zero & logical,
      paint,
    );
    _drawBoundary(canvas, paint);
    switch (scene) {
      case NetBoatPreviewScene.home:
        _drawHome(canvas, paint, NetBoatPreviewFrame.fromCycle(cycle));
        break;
      case NetBoatPreviewScene.turn:
        _drawHome(canvas, paint, NetBoatPreviewFrame.fromCycle(cycle));
        _label(canvas, '탭하면 오른쪽 90°', const Offset(180, 76));
        _rightArrow(canvas, const Offset(232, 136), paint);
        break;
      case NetBoatPreviewScene.close:
        _drawHome(canvas, paint, NetBoatPreviewFrame.fromCycle(0.74));
        _label(canvas, '내 그물선을 만나면 닫힘!', const Offset(180, 78));
        break;
      case NetBoatPreviewScene.score:
        _drawScoreRoster(canvas, paint);
        break;
      case NetBoatPreviewScene.difficulty:
        _drawDifficulty(canvas, paint);
        break;
      case NetBoatPreviewScene.failure:
        _drawFailure(canvas, paint);
        break;
      case NetBoatPreviewScene.limit:
        _drawLimit(canvas, paint);
        break;
    }
    canvas.restore();
  }

  void _drawHome(Canvas canvas, Paint paint, NetBoatPreviewFrame frame) {
    if (!frame.captured) {
      _creatureSprite(
        canvas,
        images!.whale,
        160,
        106,
        (cycle * 16).floor() % 4,
        const Offset(198, 270),
        160,
        106,
        paint,
      );
    }
    _creatureSprite(
      canvas,
      images!.piranha,
      84,
      84,
      (cycle * 28).floor() % 4,
      const Offset(74, 250),
      28,
      28,
      paint,
    );
    _creatureSprite(
      canvas,
      images!.marlin,
      168,
      114,
      (cycle * 24).floor() % 4,
      const Offset(290, 390),
      56,
      38,
      paint,
    );
    final netPoints = [...frame.net, frame.boat];
    _drawNet(canvas, netPoints, paint, closed: frame.captured);
    paint.style = PaintingStyle.fill;
    _boatSprite(
      canvas,
      frame.direction,
      (cycle * 20).floor() % 4,
      frame.boat,
      paint,
    );
    if (frame.captured) {
      _sprite(
        canvas,
        images!.effects,
        64,
        0,
        (cycle * 20).floor() % 4,
        const Offset(198, 270),
        96,
        paint,
      );
      _label(
        canvas,
        '고래 만선!   +2,500',
        const Offset(198, 128),
        color: const Color(0xFFFFE47A),
      );
    }
    _hud(canvas, frame.score, frame.secondsLeft);
  }

  void _drawScoreRoster(Canvas canvas, Paint paint) {
    _label(canvas, '물고기별 포획 점수', const Offset(180, 54));
    _sardineSprite(canvas, 1, const Offset(92, 122), paint);
    _scoreLabel(canvas, '정어리  +10', const Offset(242, 114));
    _creatureSprite(
      canvas,
      images!.piranha,
      84,
      84,
      1,
      const Offset(92, 170),
      28,
      28,
      paint,
      flipHorizontally: true,
    );
    _scoreLabel(canvas, '피라냐  +100', const Offset(242, 162));
    _creatureSprite(
      canvas,
      images!.marlin,
      168,
      114,
      1,
      const Offset(100, 230),
      56,
      38,
      paint,
    );
    _scoreLabel(canvas, '청새치  +300', const Offset(242, 222));
    _sharkSprite(canvas, 1, const Offset(106, 296), paint);
    _scoreLabel(canvas, '상어  +700', const Offset(242, 288));
    _creatureSprite(
      canvas,
      images!.whale,
      160,
      106,
      1,
      const Offset(112, 368),
      150,
      100,
      paint,
    );
    _scoreLabel(canvas, '고래  +2,500', const Offset(260, 368));
  }

  void _scoreLabel(Canvas canvas, String text, Offset center) =>
      _label(canvas, text, center, color: const Color(0xFFFFE47A));

  void _drawDifficulty(Canvas canvas, Paint paint) {
    _boatSprite(canvas, 0, 1, const Offset(180, 322), paint);
    _creatureSprite(
      canvas,
      images!.whale,
      160,
      106,
      2,
      const Offset(180, 190),
      160,
      106,
      paint,
    );
    _sharkSprite(canvas, 0, const Offset(75, 385), paint);
    _sharkSprite(canvas, 2, const Offset(286, 370), paint);
    _label(canvas, '30  ·  60  ·  90  ·  150초', const Offset(180, 78));
    _label(
      canvas,
      '60초부터 거대한 고래 등장',
      const Offset(180, 118),
      color: const Color(0xFFFFB09D),
    );
  }

  void _drawFailure(Canvas canvas, Paint paint) {
    _label(
      canvas,
      '위험 물고기 충돌 = 종료',
      const Offset(180, 118),
      color: const Color(0xFFFFB09D),
    );
    _drawNet(canvas, const [Offset(62, 202), Offset(126, 202)], paint);
    _boatSprite(canvas, 1, 1, const Offset(126, 202), paint);
    _creatureSprite(
      canvas,
      images!.piranha,
      84,
      84,
      1,
      const Offset(184, 202),
      34,
      34,
      paint,
    );
    _dangerImpact(canvas, const Offset(158, 202));

    _label(
      canvas,
      '바깥 돌 벽 충돌 = 종료',
      const Offset(180, 288),
      color: const Color(0xFFFFB09D),
    );
    _drawNet(canvas, const [Offset(168, 348), Offset(302, 348)], paint);
    _boatSprite(canvas, 1, 1, const Offset(310, 348), paint);
    _dangerImpact(canvas, const Offset(333, 348));
    _label(canvas, '고래는 통과 · 다른 물고기는 반대로 튕김', const Offset(180, 424));
  }

  void _dangerImpact(Canvas canvas, Offset center) {
    final path = Path();
    const radii = <double>[22, 9, 19, 8, 21, 9, 18, 8];
    for (var index = 0; index < radii.length; index++) {
      final angle = -math.pi / 2 + index * math.pi / 4;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * radii[index];
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas
      ..drawPath(path, Paint()..color = const Color(0xFFFF4D3D))
      ..drawCircle(center, 6, Paint()..color = const Color(0xFFFFE36A));
  }

  void _drawLimit(Canvas canvas, Paint paint) {
    const points = [
      Offset(70, 400),
      Offset(70, 120),
      Offset(180, 120),
      Offset(180, 390),
      Offset(290, 390),
      Offset(290, 160),
    ];
    _drawNet(canvas, points, paint, warning: true);
    _boatSprite(canvas, 0, 1, points.last, paint);
    _label(
      canvas,
      'NET  1000 / 1000',
      const Offset(180, 108),
      color: const Color(0xFFFFE36A),
    );
    canvas
      ..drawRect(
        const Rect.fromLTWH(88, 130, 184, 10),
        Paint()..color = const Color(0xCC183F47),
      )
      ..drawRect(
        const Rect.fromLTWH(91, 133, 178, 4),
        Paint()..color = const Color(0xFFFFE36A),
      );
    _label(canvas, '한계에 닿으면 끊김 · 1초 후 재전개', const Offset(180, 430));
  }

  void _drawNet(
    Canvas canvas,
    List<Offset> points,
    Paint paint, {
    bool closed = false,
    bool warning = false,
  }) {
    _netPainter.draw(canvas, points, closed: closed, warning: warning);
    paint.style = PaintingStyle.fill;
  }

  void _drawBoundary(Canvas canvas, Paint paint) {
    const wall = <Offset>[
      Offset(18, 82),
      Offset(60, 82),
      Offset(102, 82),
      Offset(144, 82),
      Offset(186, 82),
      Offset(228, 82),
      Offset(270, 82),
      Offset(312, 82),
      Offset(342, 82),
      Offset(18, 450),
      Offset(60, 450),
      Offset(102, 450),
      Offset(144, 450),
      Offset(186, 450),
      Offset(228, 450),
      Offset(270, 450),
      Offset(312, 450),
      Offset(342, 450),
      Offset(18, 124),
      Offset(18, 166),
      Offset(18, 208),
      Offset(18, 250),
      Offset(18, 292),
      Offset(18, 334),
      Offset(18, 376),
      Offset(18, 418),
      Offset(342, 124),
      Offset(342, 166),
      Offset(342, 208),
      Offset(342, 250),
      Offset(342, 292),
      Offset(342, 334),
      Offset(342, 376),
      Offset(342, 418),
    ];
    for (var i = 0; i < wall.length; i++) {
      _sprite(
        canvas,
        images!.reefs,
        48,
        (i ~/ 4) % 2,
        i % 4,
        wall[i],
        48,
        paint,
      );
    }
  }

  void _boatSprite(
    Canvas canvas,
    int direction,
    int frame,
    Offset center,
    Paint paint,
  ) {
    final vertical = direction == 0 || direction == 2;
    _drawImage(
      canvas,
      images!.boat,
      Rect.fromLTWH(frame * 64, direction * 64, 64, 64),
      Rect.fromCenter(
        center: center,
        width: vertical ? 48 : 56,
        height: vertical ? 56 : 48,
      ),
      paint,
    );
  }

  void _hud(Canvas canvas, int score, int time) {
    _label(canvas, 'NET  $score', const Offset(70, 36), color: Colors.white);
    _label(canvas, 'TIME  $time', const Offset(285, 36), color: Colors.white);
  }

  void _rightArrow(Canvas canvas, Offset center, Paint paint) {
    final rect = Rect.fromCircle(center: center, radius: 28);
    canvas.drawArc(
      rect,
      -math.pi * 0.9,
      math.pi * 1.1,
      false,
      paint
        ..color = const Color(0xFFFFE47A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    final tip = Offset(center.dx + 24, center.dy + 14);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - 12, tip.dy - 2)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 4, tip.dy - 12),
      paint,
    );
    paint.style = PaintingStyle.fill;
  }

  void _label(
    Canvas canvas,
    String text,
    Offset center, {
    Color color = Colors.white,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Galmuri',
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black87, offset: Offset(2, 2))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _sprite(
    Canvas canvas,
    ui.Image image,
    double cell,
    int row,
    int col,
    Offset center,
    double size,
    Paint paint,
  ) {
    _drawImage(
      canvas,
      image,
      Rect.fromLTWH(col * cell, row * cell, cell, cell),
      Rect.fromCenter(center: center, width: size, height: size),
      paint,
    );
  }

  void _creatureSprite(
    Canvas canvas,
    ui.Image image,
    double cellWidth,
    double cellHeight,
    int frame,
    Offset center,
    double width,
    double height,
    Paint paint, {
    bool flipHorizontally = false,
  }) {
    final spritePaint =
        identical(image, images!.piranha) || identical(image, images!.marlin)
        ? _smoothFishPaint
        : paint;
    if (flipHorizontally) {
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..scale(-1, 1);
      _drawImage(
        canvas,
        image,
        Rect.fromLTWH(frame * cellWidth, 0, cellWidth, cellHeight),
        Rect.fromCenter(center: Offset.zero, width: width, height: height),
        spritePaint,
      );
      canvas.restore();
      return;
    }
    _drawImage(
      canvas,
      image,
      Rect.fromLTWH(frame * cellWidth, 0, cellWidth, cellHeight),
      Rect.fromCenter(center: center, width: width, height: height),
      spritePaint,
    );
  }

  void _sardineSprite(Canvas canvas, int frame, Offset center, Paint paint) {
    final normalized = frame % 4;
    _drawImage(
      canvas,
      images!.sardine,
      Rect.fromLTWH((normalized % 2) * 84, (normalized ~/ 2) * 84, 84, 84),
      Rect.fromCenter(center: center, width: 28, height: 28),
      _smoothFishPaint,
    );
  }

  void _sharkSprite(Canvas canvas, int frame, Offset center, Paint paint) {
    _creatureSprite(
      canvas,
      images!.sharkWake,
      72,
      36,
      frame,
      center.translate(-18, 0),
      72,
      36,
      paint,
    );
    _creatureSprite(
      canvas,
      images!.shark,
      74,
      38,
      frame,
      center,
      74,
      38,
      paint,
    );
  }

  void _drawImage(
    Canvas canvas,
    ui.Image image,
    Rect source,
    Rect destination,
    Paint paint,
  ) {
    canvas.drawImageRect(
      image,
      source,
      destination,
      paint
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _NetBoatPreviewPainter oldDelegate) =>
      oldDelegate.cycle != cycle ||
      oldDelegate.scene != scene ||
      oldDelegate.images != images;
}
