import 'dart:async';
import 'dart:math' show max, min, pi;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The home-page preview uses the same 360x640 world coordinates as the
/// playable game, then lets the surrounding card crop/scale that world.
/// Keeping this as a small deterministic preview makes the board seams,
/// footprint direction, and actor timing match the real game.
class MamaDuckTrailHomePreview extends StatefulWidget {
  const MamaDuckTrailHomePreview({super.key});

  @override
  State<MamaDuckTrailHomePreview> createState() =>
      _MamaDuckTrailHomePreviewState();
}

class _MamaDuckTrailHomePreviewState extends State<MamaDuckTrailHomePreview> {
  static const _tick = Duration(milliseconds: 50);

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  _MamaDuckHomeImages? _images;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) {
        setState(() => _elapsed += _tick);
      }
    });
    unawaited(_loadImages());
  }

  Future<void> _loadImages() async {
    final loaded = <ui.Image>[];
    try {
      for (final path in _MamaDuckHomeImages.assetPaths) {
        loaded.add(await _loadImage(path));
      }
      final images = _MamaDuckHomeImages.fromList(loaded);
      if (!mounted) {
        images.dispose();
        return;
      }
      setState(() => _images = images);
    } catch (_) {
      for (final image in loaded) {
        image.dispose();
      }
    }
  }

  Future<ui.Image> _loadImage(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _images?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _MamaDuckHomeFrame.at(_elapsed);
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
      child: SizedBox(
        key: const Key('mama-duck-trail-home-hero'),
        width: _MamaDuckHomePainter.worldWidth,
        height: _MamaDuckHomePainter.worldHeight,
        child: _images == null
            ? const Image(
                image: AssetImage(
                  'assets/images/mama_duck_trail/home_gameplay_hero.png',
                ),
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
              )
            : CustomPaint(
                key: const Key('mama-duck-trail-home-animation'),
                painter: _MamaDuckHomePainter(images: _images!, frame: frame),
              ),
      ),
    );
  }
}

class _MamaDuckHomeImages {
  const _MamaDuckHomeImages({
    required this.background,
    required this.board,
    required this.footprints,
    required this.motherWalk,
    required this.motherIdle,
    required this.motherCheer,
    required this.ducklingWalk,
    required this.ducklingCheer,
  });

  static const assetPaths = <String>[
    'assets/images/mama_duck_trail/marsh_background.png',
    'assets/images/mama_duck_trail/marsh_board_map.png',
    'assets/images/mama_duck_trail/footprints_atlas.png',
    'assets/images/mama_duck_trail/mother_duck_walk_sheet.png',
    'assets/images/mama_duck_trail/mother_duck_idle.png',
    'assets/images/mama_duck_trail/mother_duck_cheer_sheet.png',
    'assets/images/mama_duck_trail/duckling_walk_sheet.png',
    'assets/images/mama_duck_trail/duckling_cheer_sheet.png',
  ];

  factory _MamaDuckHomeImages.fromList(List<ui.Image> images) {
    if (images.length != assetPaths.length) {
      throw StateError('unexpected mama-duck home asset count');
    }
    return _MamaDuckHomeImages(
      background: images[0],
      board: images[1],
      footprints: images[2],
      motherWalk: images[3],
      motherIdle: images[4],
      motherCheer: images[5],
      ducklingWalk: images[6],
      ducklingCheer: images[7],
    );
  }

  final ui.Image background;
  final ui.Image board;
  final ui.Image footprints;
  final ui.Image motherWalk;
  final ui.Image motherIdle;
  final ui.Image motherCheer;
  final ui.Image ducklingWalk;
  final ui.Image ducklingCheer;

  void dispose() {
    background.dispose();
    board.dispose();
    footprints.dispose();
    motherWalk.dispose();
    motherIdle.dispose();
    motherCheer.dispose();
    ducklingWalk.dispose();
    ducklingCheer.dispose();
  }
}

class _MamaDuckHomeCell {
  const _MamaDuckHomeCell(this.row, this.column);

  final int row;
  final int column;
}

class _MamaDuckHomeFrame {
  const _MamaDuckHomeFrame({
    required this.cycleSeconds,
    required this.pathRevealCount,
    required this.previewTrailOpacity,
    required this.showPlayerTrail,
    required this.motherDistance,
    required this.ducklingDistance,
    required this.showDuckling,
    required this.cheering,
    required this.motherFrame,
    required this.ducklingFrame,
  });

  static const path = <_MamaDuckHomeCell>[
    _MamaDuckHomeCell(6, 0),
    _MamaDuckHomeCell(5, 0),
    _MamaDuckHomeCell(5, 1),
    _MamaDuckHomeCell(4, 1),
    _MamaDuckHomeCell(4, 2),
    _MamaDuckHomeCell(3, 2),
    _MamaDuckHomeCell(3, 3),
  ];

  static const stepSeconds = 0.22;
  // The seven-cell preview path has six movement intervals.
  static const routeDurationSeconds = 6 * stepSeconds;
  static const holdSeconds = 1.05;
  static const fadeSeconds = 0.35;
  static const successTravelSeconds = 0.58;
  static const cheerSeconds = 1.76;
  static const successStartSeconds =
      routeDurationSeconds + holdSeconds + fadeSeconds;
  static const cheerStartSeconds = successStartSeconds + successTravelSeconds;
  static const cycleDurationSeconds = cheerStartSeconds + cheerSeconds;

  final double cycleSeconds;
  final int pathRevealCount;
  final double previewTrailOpacity;
  final bool showPlayerTrail;
  final double motherDistance;
  final double ducklingDistance;
  final bool showDuckling;
  final bool cheering;
  final int motherFrame;
  final int ducklingFrame;

  static _MamaDuckHomeFrame at(Duration elapsed) {
    final cycle =
        (elapsed.inMilliseconds / Duration.millisecondsPerSecond) %
        cycleDurationSeconds;
    final inRoute = cycle < routeDurationSeconds;
    final inFade =
        cycle >= routeDurationSeconds + holdSeconds &&
        cycle < successStartSeconds;
    final inSuccess = cycle >= successStartSeconds;
    final inCheer = cycle >= cheerStartSeconds;
    final routeProgress = inRoute
        ? (cycle / stepSeconds).clamp(0.0, (path.length - 1).toDouble())
        : (path.length - 1).toDouble();
    final successProgress = inSuccess
        ? ((cycle - successStartSeconds) / successTravelSeconds).clamp(0.0, 1.0)
        : 0.0;
    final previewOpacity = inFade
        ? (1 - (cycle - routeDurationSeconds - holdSeconds) / fadeSeconds)
              .clamp(0.0, 1.0)
        : inSuccess
        ? 0.0
        : 1.0;
    final revealed = inRoute
        ? min(path.length, (cycle / stepSeconds).floor() + 1)
        : path.length;

    return _MamaDuckHomeFrame(
      cycleSeconds: cycle,
      pathRevealCount: revealed,
      previewTrailOpacity: previewOpacity,
      showPlayerTrail: inSuccess,
      motherDistance: routeProgress,
      ducklingDistance: (path.length - 2) * successProgress,
      showDuckling: inSuccess,
      cheering: inCheer,
      motherFrame: inRoute
          ? (cycle / 0.11).floor() % 6
          : inCheer
          ? ((cycle - cheerStartSeconds) / 0.125).floor() % 6
          : 0,
      ducklingFrame: inCheer
          ? ((cycle - cheerStartSeconds) / 0.125).floor() % 6
          : (cycle / 0.09).floor() % 6,
    );
  }
}

class _MamaDuckHomePainter extends CustomPainter {
  const _MamaDuckHomePainter({required this.images, required this.frame});

  static const worldWidth = 360.0;
  static const worldHeight = 640.0;
  static const boardTop = 68.0;
  static const tileSize = 72.0;
  static const boardHeight = tileSize * 7;
  static const _footprintSize = 48.0;

  final _MamaDuckHomeImages images;
  final _MamaDuckHomeFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final pixelPaint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    _drawImage(
      canvas,
      images.background,
      source: _sourceRect(images.background),
      destination: const Rect.fromLTWH(0, -100, 360, 840),
      paint: pixelPaint,
    );
    _drawImage(
      canvas,
      images.board,
      source: _sourceRect(images.board),
      destination: const Rect.fromLTWH(0, boardTop, 360, 504),
      paint: pixelPaint,
    );
    _drawCellGuides(canvas);
    _drawRain(canvas);
    _drawFootprints(
      canvas,
      row: 0,
      count: frame.pathRevealCount,
      opacity: frame.previewTrailOpacity,
    );
    if (frame.showPlayerTrail) {
      _drawFootprints(canvas, row: 1, count: _MamaDuckHomeFrame.path.length);
    }
    _drawActors(canvas, pixelPaint);
  }

  void _drawImage(
    Canvas canvas,
    ui.Image image, {
    required Rect source,
    required Rect destination,
    required Paint paint,
  }) {
    canvas.drawImageRect(image, source, destination, paint);
  }

  Rect _sourceRect(ui.Image image) =>
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  void _drawCellGuides(Canvas canvas) {
    final guidePaint = Paint()
      ..color = const Color(0xA3322D29)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    for (var column = 1; column < 5; column++) {
      final x = column * tileSize - 1;
      canvas.drawRect(Rect.fromLTWH(x, boardTop, 2, boardHeight), guidePaint);
    }
    for (var row = 1; row < 7; row++) {
      final y = boardTop + row * tileSize - 1;
      canvas.drawRect(Rect.fromLTWH(0, y, worldWidth, 2), guidePaint);
    }
  }

  void _drawRain(Canvas canvas) {
    final rainPaint = Paint()
      ..color = const Color(0x6637A3A4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    for (var index = 0; index < 16; index++) {
      final x = ((index * 47 + (frame.cycleSeconds * 34).floor()) % 380) - 10;
      final y = (index * 71) % 740 - 100;
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 2, 10),
        rainPaint,
      );
    }
  }

  void _drawFootprints(
    Canvas canvas, {
    required int row,
    required int count,
    double opacity = 1,
  }) {
    final footprintCount = min(
      max(0, count - 1),
      _MamaDuckHomeFrame.path.length - 1,
    );
    if (footprintCount == 0 || opacity <= 0) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    for (var index = 0; index < footprintCount; index++) {
      final cell = _MamaDuckHomeFrame.path[index];
      final next = _MamaDuckHomeFrame.path[index + 1];
      final center = _cellCenter(cell);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(_directionAngle(cell, next));
      canvas.drawImageRect(
        images.footprints,
        Rect.fromLTWH(0, row * _footprintSize, _footprintSize, _footprintSize),
        const Rect.fromLTWH(-24, -24, 48, 48),
        paint,
      );
      canvas.restore();
    }
  }

  void _drawActors(Canvas canvas, Paint paint) {
    final motherCenter = _pointAlongPath(frame.motherDistance);
    if (frame.cheering) {
      _drawSheetFrame(
        canvas,
        images.motherCheer,
        frame.motherFrame,
        motherCenter,
        cellSize: 72,
        paint: paint,
      );
    } else if (frame.motherDistance < _MamaDuckHomeFrame.path.length - 1) {
      _drawSheetFrame(
        canvas,
        images.motherWalk,
        frame.motherFrame,
        motherCenter,
        cellSize: 72,
        paint: paint,
      );
    } else {
      _drawImageFrame(
        canvas,
        images.motherIdle,
        motherCenter,
        cellSize: 72,
        paint: paint,
      );
    }

    if (!frame.showDuckling) return;
    final ducklingCenter = _pointAlongPath(frame.ducklingDistance);
    if (frame.cheering) {
      _drawSheetFrame(
        canvas,
        images.ducklingCheer,
        frame.ducklingFrame,
        ducklingCenter,
        cellSize: 72,
        paint: paint,
      );
    } else {
      _drawSheetFrame(
        canvas,
        images.ducklingWalk,
        frame.ducklingFrame,
        ducklingCenter,
        cellSize: 72,
        paint: paint,
      );
    }
  }

  void _drawSheetFrame(
    Canvas canvas,
    ui.Image sheet,
    int frameIndex,
    Offset center, {
    required double cellSize,
    required Paint paint,
  }) {
    final row = frameIndex ~/ 3;
    final column = frameIndex % 3;
    _drawImage(
      canvas,
      sheet,
      source: Rect.fromLTWH(
        column * cellSize,
        row * cellSize,
        cellSize,
        cellSize,
      ),
      destination: Rect.fromCenter(
        center: center,
        width: cellSize,
        height: cellSize,
      ),
      paint: paint,
    );
  }

  void _drawImageFrame(
    Canvas canvas,
    ui.Image image,
    Offset center, {
    required double cellSize,
    required Paint paint,
  }) {
    _drawImage(
      canvas,
      image,
      source: _sourceRect(image),
      destination: Rect.fromCenter(
        center: center,
        width: cellSize,
        height: cellSize,
      ),
      paint: paint,
    );
  }

  Offset _cellCenter(_MamaDuckHomeCell cell) => Offset(
    (cell.column + 0.5) * tileSize,
    boardTop + (cell.row + 0.5) * tileSize,
  );

  Offset _pointAlongPath(double distance) {
    final path = _MamaDuckHomeFrame.path;
    final scaled = distance.clamp(0.0, (path.length - 1).toDouble());
    final segment = scaled.floor().clamp(0, path.length - 2);
    final local = scaled - segment;
    final from = _cellCenter(path[segment]);
    final to = _cellCenter(path[segment + 1]);
    return Offset.lerp(from, to, local) ?? from;
  }

  double _directionAngle(_MamaDuckHomeCell from, _MamaDuckHomeCell to) {
    final rowDelta = to.row - from.row;
    final columnDelta = to.column - from.column;
    if (rowDelta < 0) return pi;
    if (columnDelta > 0) return -pi / 2;
    if (rowDelta > 0) return 0;
    return pi / 2;
  }

  @override
  bool shouldRepaint(covariant _MamaDuckHomePainter oldDelegate) =>
      oldDelegate.images != images || oldDelegate.frame != frame;
}
