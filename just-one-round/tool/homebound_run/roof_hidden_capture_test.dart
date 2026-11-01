import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

const _seed = 20261018;
const _short = Size(360, 640);
const _tall = Size(360, 820);
const _extraTall = Size(360, 1200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('capture facade-height and low-camera review frames', () async {
    final earlyOnly = Platform.environment['ROOF_HIDDEN_EARLY_ONLY'] == '1';
    final outputDirectory = Directory(
      earlyOnly
          ? 'artifacts/homebound_run/roof_hidden/early_review'
          : 'artifacts/homebound_run/roof_hidden/final',
    )..createSync(recursive: true);
    await (FontLoader(
      'Galmuri',
    )..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'))).load();
    final images = await TempleRunArt.loadImageAssets();
    final course = TempleRunCourseGenerator(
      math.Random(_seed),
    ).generate(duration: const Duration(seconds: 60));
    final captures = <_CaptureSpec>[
      _CaptureSpec(name: 'straight_short', viewport: _short, distance: 20),
      _CaptureSpec(name: 'straight_tall', viewport: _tall, distance: 20),
      _CaptureSpec(
        name: 'straight_extratall_background',
        viewport: _extraTall,
        distance: 20,
      ),
      _CaptureSpec(name: 'shop_motifs_short', viewport: _short, distance: 84),
      _CaptureSpec(name: 'shop_motifs_tall', viewport: _tall, distance: 84),
      _turnCapture('right_turn_short', course.turns[0], 0, _short, 1),
      _turnCapture('right_turn_tall', course.turns[0], 0, _tall, 0),
      _turnCapture('left_turn_short', course.turns[2], 2, _short, 2),
      _turnCapture('left_turn_tall', course.turns[2], 2, _tall, 1),
    ];
    if (!earlyOnly) {
      captures.addAll([
        for (final turnIndex in [0, 2])
          for (final offset in [1.0, 2.0, 3.0, 4.0])
            _turnProgressCapture(course.turns[turnIndex], turnIndex, offset),
      ]);
    }

    TempleRunCourse? longCourse;
    TempleRunTurn? lateTurn;
    var lateTurnIndex = 0;
    if (!earlyOnly) {
      final narrow = course.obstacles.firstWhere(
        (obstacle) => obstacle.kind == TempleRunObstacleKind.narrowPath,
      );
      final hurdle = course.obstacles.firstWhere(
        (obstacle) => obstacle.kind == TempleRunObstacleKind.hurdle,
      );
      final arch = course.obstacles.firstWhere(
        (obstacle) => obstacle.kind == TempleRunObstacleKind.arch,
      );
      captures.addAll([
        _CaptureSpec(
          name: 'narrow_safe_lane_tall',
          viewport: _tall,
          distance: narrow.distanceMeters + narrow.lengthMeters / 2,
          lane: narrow.lane,
        ),
        _CaptureSpec(
          name: 'hurdle_jump_short',
          viewport: _short,
          distance: hurdle.distanceMeters,
          jumpRemaining: TempleRunRules.jumpDurationSeconds / 2,
        ),
        _CaptureSpec(
          name: 'shutter_slide_tall',
          viewport: _tall,
          distance: arch.distanceMeters,
          slideRemaining: TempleRunRules.slideDurationSeconds / 2,
        ),
      ]);
      longCourse = TempleRunCourseGenerator(
        math.Random(_seed),
      ).generate(duration: const Duration(seconds: 260));
      lateTurnIndex = _nearestTurnToElapsed(longCourse.turns, 240);
      lateTurn = longCourse.turns[lateTurnIndex];
    }

    final records = <_CaptureRecord>[];
    try {
      for (final spec in captures) {
        records.add(
          await _captureSpec(
            images: images,
            spec: spec,
            defaultCourse: course,
            outputDirectory: outputDirectory,
          ),
        );
      }
      if (!earlyOnly) {
        records.addAll(
          await _captureLateTurnSequence(
            images: images,
            course: longCourse!,
            turn: lateTurn!,
            turnIndex: lateTurnIndex,
            outputDirectory: outputDirectory,
          ),
        );
      }

      final contactSheet = await _contactSheet(records, earlyOnly: earlyOnly);
      try {
        await _writePng(
          File('${outputDirectory.path}/contact_sheet.png'),
          contactSheet,
        );
      } finally {
        contactSheet.dispose();
      }
      final manifest = {
        'renderer': 'TempleRunArt with production image bundle assets',
        'seed': _seed,
        'mode': earlyOnly ? 'early-review' : 'targeted-final-matrix',
        'facadeHeightMeters': TempleRunArt.facadeHeightMeters,
        'generatedTurns': course.turns
            .take(4)
            .map(
              (turn) => {
                'distanceMeters': turn.distanceMeters,
                'direction': turn.direction.name,
              },
            )
            .toList(growable: false),
        'frames': records
            .map(
              (record) => {
                'file': '${record.spec.name}.png',
                'viewport': {
                  'width': record.spec.viewport.width,
                  'height': record.spec.viewport.height,
                },
                'distanceMeters': record.spec.distance,
                'lane': record.spec.lane,
                'completedTurns': record.completedTurns,
                'renderedDistanceMeters': record.renderedDistance,
                'cameraHeightMeters': record.cameraHeight,
                'horizonY': record.horizonY,
                'jumpRemaining': record.spec.jumpRemaining,
                'slideRemaining': record.spec.slideRemaining,
                'bendProgress': record.spec.bendProgress,
                'bendDirection': record.spec.bendDirection?.name,
                'failureVisible': record.spec.failureVisible,
              },
            )
            .toList(growable: false),
      };
      await File('${outputDirectory.path}/manifest.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );
      for (final record in records) {
        record.image.dispose();
      }
      records.clear();
    } finally {
      for (final record in records) {
        record.image.dispose();
      }
      for (final image in images.values) {
        image.dispose();
      }
    }
  });
}

_CaptureSpec _turnCapture(
  String name,
  TempleRunTurn turn,
  int turnIndex,
  Size viewport,
  int lane,
) => _CaptureSpec(
  name: name,
  viewport: viewport,
  distance: turn.distanceMeters + 6,
  completedTurnsOverride: turnIndex + 1,
  lane: lane,
);

_CaptureSpec _turnProgressCapture(
  TempleRunTurn turn,
  int turnIndex,
  double offset,
) {
  final junctionTime = TempleRunRules.elapsedForGenerationDistance(
    turn.distanceMeters,
  );
  final captureTime = TempleRunRules.elapsedForGenerationDistance(
    turn.distanceMeters + offset,
  );
  return _CaptureSpec(
    name: '${turn.direction.name}_mid_${offset.toInt()}m',
    viewport: _short,
    distance: turn.distanceMeters + offset,
    completedTurnsOverride: turnIndex + 1,
    bendProgress: (1 - (captureTime - junctionTime) / .35).clamp(0.0, 1.0),
    bendDirection: turn.direction,
  );
}

int _nearestTurnToElapsed(List<TempleRunTurn> turns, double targetSeconds) {
  var bestIndex = 0;
  var bestDifference = double.infinity;
  for (var index = 0; index < turns.length; index++) {
    final elapsed = TempleRunRules.elapsedForGenerationDistance(
      turns[index].distanceMeters,
    );
    final difference = (elapsed - targetSeconds).abs();
    if (difference < bestDifference) {
      bestIndex = index;
      bestDifference = difference;
    }
  }
  return bestIndex;
}

void _updateScene(TempleRunArt art, TempleRunCourse course, _CaptureSpec spec) {
  final completedTurns =
      spec.completedTurnsOverride ??
      course.turns.where((turn) => turn.distanceMeters <= spec.distance).length;
  TempleRunTurn? activeTurn;
  if (completedTurns < course.turns.length) {
    final candidate = course.turns[completedTurns];
    final distanceUntil = candidate.distanceMeters - spec.distance;
    if (candidate.contains(spec.distance) ||
        distanceUntil >= 0 && distanceUntil <= 80) {
      activeTurn = candidate;
    }
  }
  art.updateScene(
    course: course,
    distanceMeters: spec.distance,
    lane: spec.lane,
    visualLane: spec.lane.toDouble(),
    phoneTilt: (spec.lane - TempleRunRules.centerLane).toDouble(),
    jumpRemaining: spec.jumpRemaining,
    slideRemaining: spec.slideRemaining,
    runnerFrame: spec.distance * .8,
    activeTurn: activeTurn,
    bendProgress: spec.bendProgress,
    bendDirection:
        spec.bendDirection ??
        (completedTurns == 0
            ? null
            : course.turns[completedTurns - 1].direction),
    completedTurnCount: completedTurns,
    guardianVisible: false,
    failureVisible: spec.failureVisible,
    shieldVisible: false,
    boostVisible: false,
  );
}

Future<_CaptureRecord> _captureSpec({
  required Map<String, ui.Image> images,
  required _CaptureSpec spec,
  required TempleRunCourse defaultCourse,
  required Directory outputDirectory,
  TempleRunArt? renderer,
}) async {
  final course = spec.course ?? defaultCourse;
  final art =
      renderer ??
      TempleRunArt(
        images: images,
        useImageAssets: true,
        viewportWidth: spec.viewport.width,
        viewportHeight: spec.viewport.height,
      );
  _updateScene(art, course, spec);
  final image = await _render(art, spec.viewport);
  await _writePng(File('${outputDirectory.path}/${spec.name}.png'), image);
  return _CaptureRecord(
    spec: spec,
    image: image,
    completedTurns:
        spec.completedTurnsOverride ??
        course.turns
            .where((turn) => turn.distanceMeters <= spec.distance)
            .length,
    renderedDistance: art.renderedDistanceForTesting,
    // ignore: invalid_use_of_visible_for_testing_member
    cameraHeight: art.cameraHeightForTesting,
    // ignore: invalid_use_of_visible_for_testing_member
    horizonY: art.horizonYForTesting,
  );
}

Future<List<_CaptureRecord>> _captureLateTurnSequence({
  required Map<String, ui.Image> images,
  required TempleRunCourse course,
  required TempleRunTurn turn,
  required int turnIndex,
  required Directory outputDirectory,
}) async {
  final renderer = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: _short.width,
    viewportHeight: _short.height,
  );
  final records = <_CaptureRecord>[];
  final lastInputElapsed = TempleRunRules.elapsedForGenerationDistance(
    turn.windowEndMeters,
  );
  Future<void> capture({
    required String name,
    required double distance,
    required int completedTurns,
    required double bendProgress,
    TempleRunTurnDirection? bendDirection,
    bool failureVisible = false,
  }) async {
    records.add(
      await _captureSpec(
        images: images,
        spec: _CaptureSpec(
          name: name,
          viewport: _short,
          course: course,
          distance: distance,
          completedTurnsOverride: completedTurns,
          bendProgress: bendProgress,
          bendDirection: bendDirection,
          failureVisible: failureVisible,
        ),
        defaultCourse: course,
        outputDirectory: outputDirectory,
        renderer: renderer,
      ),
    );
  }

  await capture(
    name: 'late_turn_T',
    distance: turn.distanceMeters,
    completedTurns: turnIndex,
    bendProgress: 0,
  );
  await capture(
    name: 'late_turn_held',
    distance: turn.windowEndMeters,
    completedTurns: turnIndex,
    bendProgress: 0,
  );
  for (final progress in [1.0, .75, .5, .25, 0.0]) {
    final elapsed = .35 * (1 - progress);
    final distance = progress == 1
        ? turn.windowEndMeters
        : TempleRunRules.distanceForGeneration(lastInputElapsed + elapsed);
    await capture(
      name:
          'late_turn_recovery_${progress.toStringAsFixed(2).replaceAll('.', '_')}',
      distance: distance,
      completedTurns: turnIndex + 1,
      bendProgress: progress,
      bendDirection: turn.direction,
    );
  }
  final failureRenderer = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: _short.width,
    viewportHeight: _short.height,
  );
  records.add(
    await _captureSpec(
      images: images,
      spec: _CaptureSpec(
        name: 'late_turn_failure_hold',
        viewport: _short,
        course: course,
        distance: turn.windowEndMeters + .01,
        completedTurnsOverride: turnIndex,
        failureVisible: true,
      ),
      defaultCourse: course,
      outputDirectory: outputDirectory,
      renderer: failureRenderer,
    ),
  );
  return records;
}

Future<ui.Image> _render(TempleRunArt art, Size viewport) async {
  final recorder = ui.PictureRecorder();
  art.render(
    Canvas(recorder, Rect.fromLTWH(0, 0, viewport.width, viewport.height)),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(
      viewport.width.toInt(),
      viewport.height.toInt(),
    );
  } finally {
    picture.dispose();
  }
}

Future<ui.Image> _contactSheet(
  List<_CaptureRecord> records, {
  required bool earlyOnly,
}) async {
  const columns = 3;
  const gutter = 12.0;
  const thumbnailWidth = 108.0;
  const thumbnailHeight = 246.0;
  const labelHeight = 30.0;
  const titleHeight = 30.0;
  final cardWidth = thumbnailWidth + gutter * 2;
  final cardHeight = thumbnailHeight + labelHeight + gutter * 2;
  final rows = (records.length / columns).ceil();
  final width = columns * cardWidth + gutter;
  final height = titleHeight + rows * cardHeight + gutter;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  canvas.drawColor(const Color(0xFF172126), BlendMode.src);
  _drawLabel(
    canvas,
    earlyOnly ? 'Roof hidden - early review' : 'Roof hidden - final captures',
    Offset(gutter, 5),
    16,
    const Color(0xFFE4EEE7),
  );
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    final row = index ~/ columns;
    final column = index % columns;
    final left = gutter + column * cardWidth;
    final top = titleHeight + gutter + row * cardHeight;
    canvas.drawRect(
      Rect.fromLTWH(left, top, cardWidth, cardHeight),
      Paint()..color = const Color(0xFF2B363B),
    );
    canvas.drawImageRect(
      record.image,
      Rect.fromLTWH(
        0,
        0,
        record.image.width.toDouble(),
        record.image.height.toDouble(),
      ),
      _thumbnailRect(
        left + gutter,
        top + gutter,
        record.image.width.toDouble(),
        record.image.height.toDouble(),
        thumbnailWidth,
        thumbnailHeight,
      ),
      Paint()..filterQuality = FilterQuality.none,
    );
    _drawLabel(
      canvas,
      '${_captureLabel(record.spec.name)} d${record.spec.distance.toStringAsFixed(1)}',
      Offset(left + gutter, top + gutter + thumbnailHeight + 5),
      7,
      const Color(0xFFE4EEE7),
    );
    _drawLabel(
      canvas,
      '${record.spec.viewport.height.toInt()}h c${record.cameraHeight.toStringAsFixed(1)} y${record.horizonY.toStringAsFixed(0)}',
      Offset(left + gutter, top + gutter + thumbnailHeight + 17),
      7,
      const Color(0xFFAFC0BF),
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width.ceil(), height.ceil());
  } finally {
    picture.dispose();
  }
}

String _captureLabel(String name) => switch (name) {
  'straight_short' => 'straight-S',
  'straight_tall' => 'straight-T',
  'straight_extratall_background' => 'extraTall-bg',
  'shop_motifs_short' => 'shops-S',
  'shop_motifs_tall' => 'shops-T',
  'right_turn_short' => 'right-S',
  'right_turn_tall' => 'right-T',
  'left_turn_short' => 'left-S',
  'left_turn_tall' => 'left-T',
  'right_mid_1m' => 'right+1m',
  'right_mid_2m' => 'right+2m',
  'right_mid_3m' => 'right+3m',
  'right_mid_4m' => 'right+4m',
  'left_mid_1m' => 'left+1m',
  'left_mid_2m' => 'left+2m',
  'left_mid_3m' => 'left+3m',
  'left_mid_4m' => 'left+4m',
  'narrow_safe_lane_tall' => 'narrow-T',
  'hurdle_jump_short' => 'jump-S',
  'shutter_slide_tall' => 'slide-T',
  'late_turn_T' => 'late-T',
  'late_turn_held' => 'late-held',
  'late_turn_recovery_1_00' => 'late-p1',
  'late_turn_recovery_0_75' => 'late-p.75',
  'late_turn_recovery_0_50' => 'late-p.5',
  'late_turn_recovery_0_25' => 'late-p.25',
  'late_turn_recovery_0_00' => 'late-p0',
  'late_turn_failure_hold' => 'late-fail',
  _ => name,
};

Rect _thumbnailRect(
  double left,
  double top,
  double sourceWidth,
  double sourceHeight,
  double maxWidth,
  double maxHeight,
) {
  final scale = math.min(maxWidth / sourceWidth, maxHeight / sourceHeight);
  final width = sourceWidth * scale;
  final height = sourceHeight * scale;
  return Rect.fromLTWH(
    left + (maxWidth - width) / 2,
    top + (maxHeight - height) / 2,
    width,
    height,
  );
}

void _drawLabel(
  Canvas canvas,
  String text,
  Offset offset,
  double fontSize,
  Color color,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize, fontFamily: 'Galmuri'),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 360);
  painter.paint(canvas, offset);
}

Future<void> _writePng(File file, ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('Failed to encode ${file.path}');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
}

class _CaptureSpec {
  const _CaptureSpec({
    required this.name,
    required this.viewport,
    required this.distance,
    this.course,
    this.lane = TempleRunRules.centerLane,
    this.completedTurnsOverride,
    this.bendProgress = 0,
    this.bendDirection,
    this.jumpRemaining = 0,
    this.slideRemaining = 0,
    this.failureVisible = false,
  });

  final String name;
  final Size viewport;
  final double distance;
  final TempleRunCourse? course;
  final int lane;
  final int? completedTurnsOverride;
  final double bendProgress;
  final TempleRunTurnDirection? bendDirection;
  final double jumpRemaining;
  final double slideRemaining;
  final bool failureVisible;
}

class _CaptureRecord {
  const _CaptureRecord({
    required this.spec,
    required this.image,
    required this.completedTurns,
    required this.renderedDistance,
    required this.cameraHeight,
    required this.horizonY,
  });

  final _CaptureSpec spec;
  final ui.Image image;
  final int completedTurns;
  final double renderedDistance;
  final double cameraHeight;
  final double horizonY;
}
