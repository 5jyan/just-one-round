import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';

const _seed = 20261018;
const _outputRoot =
    'artifacts/homebound_run/wall_continuity_after_facade55_camera5';
const _shortViewport = Size(360, 640);
const _tallViewport = Size(360, 820);
const _viewports = [_shortViewport, _tallViewport];
const _maximumDistanceStep = .5;
const _turnOffsets = [-1.0, 5.0, 5.5, 6.0, 6.5, 7.0, 9.0];
const _expandedTurnOffsets = [
  -1.0,
  0.0,
  1.0,
  3.0,
  4.0,
  4.5,
  5.0,
  5.5,
  6.0,
  6.5,
  7.0,
  7.5,
  8.0,
  10.0,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('capture generated-route facade continuity after renderer repair', () async {
    final expanded = Platform.environment['WALL_CONTINUITY_EXPANDED'] == '1';
    final outputDirectory = Directory(
      expanded ? '$_outputRoot/expanded' : _outputRoot,
    )..createSync(recursive: true);
    final images = await TempleRunArt.loadImageAssets();
    final course = TempleRunCourseGenerator(
      Random(_seed),
    ).generate(duration: const Duration(seconds: 60));
    final turns = course.turns.take(2).toList(growable: false);
    expect(
      turns.length,
      2,
      reason: 'The fixed seed must provide two real generated junctions.',
    );

    final groups = _buildGroups(turns, expanded: expanded);
    final groupRecords = <_GroupRecord>[];
    final frameRecords = <_FrameRecord>[];
    try {
      for (final group in groups) {
        final record = await _captureGroup(
          images: images,
          course: course,
          group: group,
          outputDirectory: outputDirectory,
        );
        groupRecords.add(record);
        frameRecords.addAll(record.frames);
      }

      final longCourse = TempleRunCourseGenerator(
        Random(_seed),
      ).generate(duration: const Duration(seconds: 260));
      final lateTurnIndex = _turnNearestElapsed(longCourse.turns, 240);
      final lateTurn = longCourse.turns[lateTurnIndex];
      final lateTurnElapsed = TempleRunRules.elapsedForGenerationDistance(
        lateTurn.distanceMeters,
      );
      expect(lateTurnElapsed, closeTo(240, 1));
      expect(
        lateTurn.windowEndMeters - lateTurn.distanceMeters,
        greaterThan(3.8),
        reason: 'The late input grace must reach past the 3.8m wall offset.',
      );
      for (final group in _buildLateTurnGroups(
        turn: lateTurn,
        completedTurns: lateTurnIndex,
      )) {
        final record = await _captureGroup(
          images: images,
          course: longCourse,
          group: group,
          outputDirectory: outputDirectory,
        );
        groupRecords.add(record);
        frameRecords.addAll(record.frames);
      }
      final lateGraceRecovery = await _captureLateGraceRecovery(
        images: images,
        course: longCourse,
        turn: lateTurn,
        turnIndex: lateTurnIndex,
        outputDirectory: outputDirectory,
      );
      groupRecords.add(lateGraceRecovery);
      frameRecords.addAll(lateGraceRecovery.frames);

      for (final pair in _craftedTurnPairs) {
        final pairCourse = _courseForPair(pair.directions);
        for (
          var turnIndex = 0;
          turnIndex < pair.directions.length;
          turnIndex++
        ) {
          final turn = pairCourse.turns[turnIndex];
          final lane = (pair.name == 'LL' || pair.name == 'RL')
              ? TempleRunRules.firstLane
              : TempleRunRules.lastLane;
          final group = _CaptureGroup(
            name: 'pair_${pair.name}_turn${turnIndex + 1}_lane$lane',
            focus: '0.5m renderer sweep through ${pair.name} turn sequence',
            viewport: _shortViewport,
            lane: lane,
            targetDistances: [
              -1.0,
              0.0,
              1.0,
              3.0,
              for (var offset = 4.0; offset <= 9.0; offset += .5) offset,
            ].map((offset) => turn.distanceMeters + offset).toList(),
          );
          final record = await _captureGroup(
            images: images,
            course: pairCourse,
            group: group,
            outputDirectory: outputDirectory,
          );
          groupRecords.add(record);
          frameRecords.addAll(record.frames);
        }
      }

      for (final group in groupRecords) {
        final sheet = await _contactSheet(group);
        try {
          await _writePng(
            File('${outputDirectory.path}/sheet_${group.name}.png'),
            sheet,
          );
        } finally {
          sheet.dispose();
        }
      }

      final turnManifest = course.turns
          .take(6)
          .map((turn) {
            return {
              'distanceMeters': turn.distanceMeters,
              'direction': turn.direction.name,
              'windowStartMeters': turn.windowStartMeters,
              'windowEndMeters': turn.windowEndMeters,
            };
          })
          .toList(growable: false);
      final manifest = {
        'captureMode': expanded
            ? 'expanded selected sweep plus late-level and mixed-turn cases'
            : 'bounded continuity sample plus late-level and mixed-turn cases',
        'renderer': 'TempleRunArt image mode with production bundle assets',
        'seed': _seed,
        'durationSeconds': 60,
        'maximumDistanceStepMeters': _maximumDistanceStep,
        'routeState':
            'Generated-route sweeps advance completed turns with distance. Late-grace captures force all earlier turns completed and leave the selected turn unarmed. LL/RR/LR/RL cases use fixed, valid TempleRunTurn sequences and advance distance in 0.5m frame steps.',
        'courseTurns': turnManifest,
        'lateTurn': {
          'turnIndex': lateTurnIndex,
          'elapsedSeconds': lateTurnElapsed,
          'distanceMeters': lateTurn.distanceMeters,
          'tailMeters': lateTurn.windowEndMeters - lateTurn.distanceMeters,
          'inputEndMeters': lateTurn.windowEndMeters,
        },
        'viewports': _viewports
            .map((size) => {'width': size.width, 'height': size.height})
            .toList(growable: false),
        'groups': groupRecords
            .map(
              (group) => {
                'name': group.name,
                'viewport': {
                  'width': group.viewport.width,
                  'height': group.viewport.height,
                },
                'lane': group.lane,
                'focus': group.focus,
                'contactSheet': 'sheet_${group.name}.png',
                'frames': group.frames
                    .map((frame) => frame.toManifest())
                    .toList(growable: false),
              },
            )
            .toList(growable: false),
        'individualFrameCount': frameRecords.length,
      };
      await File('${outputDirectory.path}/manifest.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );

      // Keep decoded images alive until every labelled contact sheet is saved.
      for (final record in frameRecords) {
        record.image.dispose();
      }
      frameRecords.clear();
    } finally {
      for (final record in frameRecords) {
        record.image.dispose();
      }
      for (final image in images.values) {
        image.dispose();
      }
    }
  });
}

List<_CaptureGroup> _buildGroups(
  List<TempleRunTurn> turns, {
  required bool expanded,
}) {
  final groups = <_CaptureGroup>[];
  final offsets = expanded ? _expandedTurnOffsets : _turnOffsets;
  for (var index = 0; index < turns.length; index++) {
    final turn = turns[index];
    final configurations = expanded
        ? [
            for (final viewport in _viewports)
              for (final lane in [
                TempleRunRules.firstLane,
                TempleRunRules.centerLane,
                TempleRunRules.lastLane,
              ])
                (viewport: viewport, lane: lane),
          ]
        : index == 0
        ? [
            (viewport: _shortViewport, lane: TempleRunRules.centerLane),
            (viewport: _tallViewport, lane: TempleRunRules.firstLane),
          ]
        : [
            (viewport: _shortViewport, lane: TempleRunRules.lastLane),
            (viewport: _tallViewport, lane: TempleRunRules.centerLane),
          ];
    for (final configuration in configurations) {
      final turnName = 'turn${index + 1}_${turn.direction.name}';
      final viewportName = _viewportName(configuration.viewport);
      final name = '${turnName}_${viewportName}_lane${configuration.lane}';
      groups.add(
        _CaptureGroup(
          name: name,
          focus: 'turn + 6m camera pass',
          viewport: configuration.viewport,
          lane: configuration.lane,
          targetDistances: offsets
              .map((offset) => turn.distanceMeters + offset)
              .where((distance) => distance >= 0)
              .toList(growable: false),
        ),
      );
    }
  }

  final styleOffsets = expanded
      ? [-1.0, -.5, 0.0, .5, 1.0, 1.5, 2.0]
      : [-.5, 0.0, .5];
  final styleConfigurations = expanded
      ? [
          (viewport: _shortViewport, lane: TempleRunRules.firstLane),
          (viewport: _shortViewport, lane: TempleRunRules.centerLane),
          (viewport: _tallViewport, lane: TempleRunRules.centerLane),
          (viewport: _tallViewport, lane: TempleRunRules.lastLane),
        ]
      : [
          (viewport: _shortViewport, lane: TempleRunRules.centerLane),
          (viewport: _tallViewport, lane: TempleRunRules.lastLane),
        ];
  const tileLength = TempleRunArt.facadeHeightMeters * 4 / 3;
  const styleLength = tileLength * 10;
  for (final boundary in [styleLength, styleLength * 2]) {
    for (final configuration in styleConfigurations) {
      final boundaryName = boundary.toStringAsFixed(2).replaceAll('.', '_');
      final name =
          'style${boundaryName}_${_viewportName(configuration.viewport)}_lane${configuration.lane}';
      groups.add(
        _CaptureGroup(
          name: name,
          focus:
              'camera start crosses ${boundary.toStringAsFixed(2)}m facade style boundary',
          viewport: configuration.viewport,
          lane: configuration.lane,
          targetDistances: styleOffsets
              .map((offset) => boundary + 6 + offset)
              .where((distance) => distance >= 0)
              .toList(growable: false),
        ),
      );
    }
  }

  // The seeded route's first junction is a right turn. Its miter changes
  // actual wall arclength by 2 * wallOffset on each side, so these frames put
  // the camera directly over the second material boundary on both walls.
  const wallOffset = 4.4 / 2 + 1.6;
  final secondStyleBoundary = styleLength * 2;
  for (final sample in [
    (
      name: 'style93_33_outer_after_right',
      lane: TempleRunRules.firstLane,
      routeOffset: -2 * wallOffset,
      viewport: _shortViewport,
    ),
    (
      name: 'style93_33_inner_after_right',
      lane: TempleRunRules.lastLane,
      routeOffset: 2 * wallOffset,
      viewport: _tallViewport,
    ),
  ]) {
    groups.add(
      _CaptureGroup(
        name: '${sample.name}_lane${sample.lane}',
        focus: 'camera passes second material seam after the first right turn',
        viewport: sample.viewport,
        lane: sample.lane,
        targetDistances: [-.5, 0.0, .5]
            .map(
              (offset) => secondStyleBoundary + 6 + sample.routeOffset + offset,
            )
            .toList(growable: false),
      ),
    );
  }
  return groups;
}

int _turnNearestElapsed(List<TempleRunTurn> turns, double targetElapsed) {
  if (turns.isEmpty) throw StateError('A late turn is required for capture.');
  var bestIndex = 0;
  var bestDifference = double.infinity;
  for (var index = 0; index < turns.length; index++) {
    final elapsed = TempleRunRules.elapsedForGenerationDistance(
      turns[index].distanceMeters,
    );
    final difference = (elapsed - targetElapsed).abs();
    if (difference < bestDifference) {
      bestDifference = difference;
      bestIndex = index;
    }
  }
  return bestIndex;
}

List<_CaptureGroup> _buildLateTurnGroups({
  required TempleRunTurn turn,
  required int completedTurns,
}) => [
  _CaptureGroup(
    name: 'late_unarmed_last_input_elapsed240',
    focus: 'last distance accepting the late turn input near 240 seconds',
    viewport: _shortViewport,
    lane: TempleRunRules.centerLane,
    targetDistances: [turn.windowEndMeters],
    completedTurnsOverride: completedTurns,
    unarmedFailureAfter: turn.windowEndMeters,
  ),
  _CaptureGroup(
    name: 'late_unarmed_failure_elapsed240',
    focus: 'first distance after the late turn input expires near 240 seconds',
    viewport: _shortViewport,
    lane: TempleRunRules.centerLane,
    targetDistances: [turn.windowEndMeters + .01],
    completedTurnsOverride: completedTurns,
    unarmedFailureAfter: turn.windowEndMeters,
  ),
];

const _craftedTurnPairs =
    <({String name, List<TempleRunTurnDirection> directions})>[
      (
        name: 'LL',
        directions: [TempleRunTurnDirection.left, TempleRunTurnDirection.left],
      ),
      (
        name: 'RR',
        directions: [
          TempleRunTurnDirection.right,
          TempleRunTurnDirection.right,
        ],
      ),
      (
        name: 'LR',
        directions: [TempleRunTurnDirection.left, TempleRunTurnDirection.right],
      ),
      (
        name: 'RL',
        directions: [TempleRunTurnDirection.right, TempleRunTurnDirection.left],
      ),
    ];

TempleRunCourse _courseForPair(List<TempleRunTurnDirection> directions) =>
    TempleRunCourse(
      obstacles: const [],
      coins: const [],
      powerUps: const [],
      turns: [
        for (var index = 0; index < directions.length; index++)
          TempleRunTurn(
            distanceMeters: 53.15 + index * 47.72,
            direction: directions[index],
            windowStartMeters: 45.15 + index * 47.72,
            windowEndMeters: 61.15 + index * 47.72,
          ),
      ],
      totalDistanceMeters: 220,
    );

Future<_GroupRecord> _captureGroup({
  required Map<String, ui.Image> images,
  required TempleRunCourse course,
  required _CaptureGroup group,
  required Directory outputDirectory,
}) async {
  final art = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: group.viewport.width,
    viewportHeight: group.viewport.height,
  );
  final frames = <_FrameRecord>[];
  final targets = group.targetDistances.toList()..sort();
  var distance = 0.0;
  for (final target in targets) {
    while (distance + .000001 < target) {
      distance = min(target, distance + _maximumDistanceStep);
      _updateScene(
        art,
        course,
        distance,
        group.lane,
        completedTurnsOverride: group.completedTurnsOverride,
        unarmedFailureAfter: group.unarmedFailureAfter,
      );
    }
    distance = target;
    _updateScene(
      art,
      course,
      distance,
      group.lane,
      completedTurnsOverride: group.completedTurnsOverride,
      unarmedFailureAfter: group.unarmedFailureAfter,
    );
    final image = await _render(art, group.viewport);
    final name =
        '${group.name}_d${distance.toStringAsFixed(2).replaceAll('.', '_')}.png';
    await _writePng(File('${outputDirectory.path}/$name'), image);
    frames.add(
      _FrameRecord(
        filename: name,
        image: image,
        distance: distance,
        lane: group.lane,
        completedTurns:
            group.completedTurnsOverride ??
            _completedTurnCount(course, distance),
        failureVisible:
            group.unarmedFailureAfter != null &&
            distance > group.unarmedFailureAfter!,
        sheetOrder: frames.length + 1,
        renderedDistance: art.renderedDistanceForTesting,
      ),
    );
  }
  return _GroupRecord(
    name: group.name,
    focus: group.focus,
    viewport: group.viewport,
    lane: group.lane,
    frames: frames,
  );
}

Future<_GroupRecord> _captureLateGraceRecovery({
  required Map<String, ui.Image> images,
  required TempleRunCourse course,
  required TempleRunTurn turn,
  required int turnIndex,
  required Directory outputDirectory,
}) async {
  const viewport = _shortViewport;
  const lane = TempleRunRules.centerLane;
  const bendDuration = .35;
  final actualAtLastInput = turn.windowEndMeters;
  final lateDebt = actualAtLastInput - turn.distanceMeters;
  expect(lateDebt, greaterThan(3.8));
  final speed = TempleRunRules.maxBoostedSpeedAtDistance(turn.distanceMeters);
  final art = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: viewport.width,
    viewportHeight: viewport.height,
  );
  final frames = <_FrameRecord>[];

  Future<void> capture({
    required String state,
    required double distance,
    required int completedTurns,
    required double bendProgress,
    bool failure = false,
    TempleRunTurnDirection? bendDirection,
  }) async {
    _updateScene(
      art,
      course,
      distance,
      lane,
      completedTurnsOverride: completedTurns,
      bendProgress: bendProgress,
      bendDirectionOverride: bendDirection,
      failureVisibleOverride: failure,
      unarmedFailureAfter: failure ? turn.windowEndMeters : null,
    );
    final image = await _render(art, viewport);
    final filename =
        'late_grace_${state}_actual${distance.toStringAsFixed(2).replaceAll('.', '_')}_render${art.renderedDistanceForTesting.toStringAsFixed(2).replaceAll('.', '_')}.png';
    await _writePng(File('${outputDirectory.path}/$filename'), image);
    frames.add(
      _FrameRecord(
        filename: filename,
        image: image,
        distance: distance,
        lane: lane,
        completedTurns: completedTurns,
        failureVisible: failure,
        sheetOrder: frames.length + 1,
        stateLabel: state,
        renderedDistance: art.renderedDistanceForTesting,
        bendProgress: bendProgress,
      ),
    );
  }

  // Progress from the actual junction into the unarmed input grace, then
  // commit the late turn and sample the renderer's distance-debt easing.
  await capture(
    state: 'junction_T',
    distance: turn.distanceMeters,
    completedTurns: turnIndex,
    bendProgress: 0,
  );
  await capture(
    state: 'held_last_input',
    distance: actualAtLastInput,
    completedTurns: turnIndex,
    bendProgress: 0,
  );
  for (final progress in [1.0, .75, .5, .25, 0.0]) {
    final elapsed = bendDuration * (1 - progress);
    await capture(
      state: 'commit_p${progress.toStringAsFixed(2)}',
      distance: actualAtLastInput + speed * elapsed,
      completedTurns: turnIndex + 1,
      bendProgress: progress,
      bendDirection: turn.direction,
    );
  }

  final failureArt = TempleRunArt(
    images: images,
    useImageAssets: true,
    viewportWidth: viewport.width,
    viewportHeight: viewport.height,
  );
  _updateScene(
    failureArt,
    course,
    actualAtLastInput,
    lane,
    completedTurnsOverride: turnIndex,
  );
  final failureDistance = actualAtLastInput + .01;
  _updateScene(
    failureArt,
    course,
    failureDistance,
    lane,
    completedTurnsOverride: turnIndex,
    unarmedFailureAfter: actualAtLastInput,
  );
  final failureImage = await _render(failureArt, viewport);
  final failureFilename =
      'late_grace_failure_hold_actual${failureDistance.toStringAsFixed(2).replaceAll('.', '_')}_render${failureArt.renderedDistanceForTesting.toStringAsFixed(2).replaceAll('.', '_')}.png';
  await _writePng(
    File('${outputDirectory.path}/$failureFilename'),
    failureImage,
  );
  frames.add(
    _FrameRecord(
      filename: failureFilename,
      image: failureImage,
      distance: failureDistance,
      lane: lane,
      completedTurns: turnIndex,
      failureVisible: true,
      sheetOrder: frames.length + 1,
      stateLabel: 'failure_hold',
      renderedDistance: failureArt.renderedDistanceForTesting,
      bendProgress: 0,
    ),
  );

  return _GroupRecord(
    name: 'late_grace_recovery',
    focus:
        'junction hold, late-input hold, successful turn catch-up, and failure hold',
    viewport: viewport,
    lane: lane,
    frames: frames,
  );
}

void _updateScene(
  TempleRunArt art,
  TempleRunCourse course,
  double distance,
  int lane, {
  int? completedTurnsOverride,
  double? unarmedFailureAfter,
  double bendProgress = 0,
  TempleRunTurnDirection? bendDirectionOverride,
  bool? failureVisibleOverride,
}) {
  final completedTurns =
      completedTurnsOverride ?? _completedTurnCount(course, distance);
  TempleRunTurn? activeTurn;
  if (completedTurns < course.turns.length) {
    final candidate = course.turns[completedTurns];
    final distanceUntilTurn = candidate.distanceMeters - distance;
    if (candidate.contains(distance) ||
        (distanceUntilTurn >= 0 && distanceUntilTurn <= 80)) {
      activeTurn = candidate;
    }
  }
  final previousDirection =
      bendDirectionOverride ??
      (completedTurns == 0 ? null : course.turns[completedTurns - 1].direction);
  art.updateScene(
    course: course,
    distanceMeters: distance,
    lane: lane,
    visualLane: lane.toDouble(),
    phoneTilt: (lane - TempleRunRules.centerLane).toDouble(),
    jumpRemaining: 0,
    slideRemaining: 0,
    runnerFrame: distance * .8,
    activeTurn: activeTurn,
    bendProgress: bendProgress,
    bendDirection: previousDirection,
    completedTurnCount: completedTurns,
    guardianVisible: false,
    failureVisible:
        failureVisibleOverride ??
        (unarmedFailureAfter != null && distance > unarmedFailureAfter),
    shieldVisible: false,
    boostVisible: false,
  );
}

int _completedTurnCount(TempleRunCourse course, double distance) {
  var count = 0;
  while (count < course.turns.length &&
      course.turns[count].distanceMeters <= distance) {
    count++;
  }
  return count;
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

Future<ui.Image> _contactSheet(_GroupRecord group) async {
  const columns = 4;
  const gutter = 8.0;
  const thumbnailWidth = 112.0;
  final thumbnailHeight =
      thumbnailWidth * group.viewport.height / group.viewport.width;
  final cellWidth = thumbnailWidth + gutter * 2;
  final cellHeight = thumbnailHeight + gutter * 2;
  final rows = (group.frames.length / columns).ceil();
  const headerHeight = 8.0;
  final width = columns * cellWidth + gutter;
  final height = headerHeight + rows * cellHeight + gutter;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  canvas.drawColor(const Color(0xFF172126), BlendMode.src);
  for (var index = 0; index < group.frames.length; index++) {
    final frame = group.frames[index];
    final row = index ~/ columns;
    final column = index % columns;
    final left = gutter + column * cellWidth;
    final top = headerHeight + gutter + row * cellHeight;
    final card = Rect.fromLTWH(left, top, cellWidth, cellHeight);
    canvas.drawRect(card, Paint()..color = const Color(0xFF2B363B));
    canvas.drawImageRect(
      frame.image,
      Rect.fromLTWH(
        0,
        0,
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      ),
      Rect.fromLTWH(
        left + gutter,
        top + gutter,
        thumbnailWidth,
        thumbnailHeight,
      ),
      Paint()..filterQuality = FilterQuality.none,
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width.ceil(), height.ceil());
  } finally {
    picture.dispose();
  }
}

Future<void> _writePng(File file, ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('Failed to encode ${file.path}');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
}

String _viewportName(Size viewport) =>
    viewport.height == _shortViewport.height ? 'short360x640' : 'tall360x820';

class _CaptureGroup {
  const _CaptureGroup({
    required this.name,
    required this.focus,
    required this.viewport,
    required this.lane,
    required this.targetDistances,
    this.completedTurnsOverride,
    this.unarmedFailureAfter,
  });

  final String name;
  final String focus;
  final Size viewport;
  final int lane;
  final List<double> targetDistances;
  final int? completedTurnsOverride;
  final double? unarmedFailureAfter;
}

class _GroupRecord {
  const _GroupRecord({
    required this.name,
    required this.focus,
    required this.viewport,
    required this.lane,
    required this.frames,
  });

  final String name;
  final String focus;
  final Size viewport;
  final int lane;
  final List<_FrameRecord> frames;
}

class _FrameRecord {
  const _FrameRecord({
    required this.filename,
    required this.image,
    required this.distance,
    required this.lane,
    required this.completedTurns,
    required this.failureVisible,
    required this.sheetOrder,
    this.stateLabel,
    this.renderedDistance,
    this.bendProgress,
  });

  final String filename;
  final ui.Image image;
  final double distance;
  final int lane;
  final int completedTurns;
  final bool failureVisible;
  final int sheetOrder;
  final String? stateLabel;
  final double? renderedDistance;
  final double? bendProgress;

  Map<String, Object?> toManifest() => {
    'file': filename,
    'distanceMeters': distance,
    'lane': lane,
    'completedTurns': completedTurns,
    'failureVisible': failureVisible,
    'contactSheetOrder': sheetOrder,
    if (stateLabel != null) 'stateLabel': stateLabel,
    if (renderedDistance != null) 'renderedDistanceMeters': renderedDistance,
    if (bendProgress != null) 'bendProgress': bendProgress,
  };
}
