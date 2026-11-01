import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/games/temple_run/domain/temple_run_rules.dart';
import 'package:just_one_round/features/games/temple_run/presentation/temple_run_art.dart';
import 'package:just_one_round/features/games/temple_run/temple_run_game.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late lateral move can collect a coin before its center passes', () {
    final game = _game(
      course: _course(
        coins: const [TempleRunCoin(distanceMeters: 20, lane: 2)],
      ),
    );
    addTearDown(game.disposeController);

    // Enter the coin's longitudinal pickup window before the faster tilt
    // reaches lane 2, leaving the late lateral move as the collection gate.
    _advanceToDistance(game, 17.35);
    game.setTiltNeutralForTesting(0);
    for (var index = 0; index < 30; index++) {
      game.pushAccelerometerEventForTesting(
        AccelerometerEvent(-4, 0, 0, DateTime.fromMillisecondsSinceEpoch(0)),
      );
    }
    game.advanceTimeForTesting(const Duration(milliseconds: 125));

    expect(
      game.distanceMetersForTesting,
      inInclusiveRange(20 - TempleRunRules.coinPickupWindowMeters, 20),
    );
    expect(game.lateralPositionForTesting, closeTo(1.53, 0.04));
    expect(
      TempleRunRules.overlapsLanePosition(
        lane: 2,
        positionInLanes: game.lateralPositionForTesting,
        halfWidthInLanes: TempleRunRules.pickupHalfWidthInLanes,
      ),
      isFalse,
    );
    expect(game.coinsForTesting, 0);
    expect(game.expiredCoinIndicesForTesting, isEmpty);

    game.advanceTimeForTesting(const Duration(milliseconds: 40));

    expect(game.distanceMetersForTesting, lessThan(20));
    expect(game.coinsForTesting, 1);
    expect(game.collectedCoinIndicesForTesting, {0});
  });

  test('late lateral move can collect a power-up before its center passes', () {
    final game = _game(
      course: _course(
        powerUps: const [
          TempleRunPowerUp(
            distanceMeters: 20,
            lane: 2,
            kind: TempleRunPowerUpKind.shield,
          ),
        ],
      ),
    );
    addTearDown(game.disposeController);

    // Match the coin fixture: the power-up is longitudinally available while
    // the runner remains outside its lane pickup radius.
    _advanceToDistance(game, 17.35);
    game.setTiltNeutralForTesting(0);
    for (var index = 0; index < 30; index++) {
      game.pushAccelerometerEventForTesting(
        AccelerometerEvent(-4, 0, 0, DateTime.fromMillisecondsSinceEpoch(0)),
      );
    }
    game.advanceTimeForTesting(const Duration(milliseconds: 125));

    expect(
      game.distanceMetersForTesting,
      inInclusiveRange(20 - TempleRunRules.powerUpPickupWindowMeters, 20),
    );
    expect(game.lateralPositionForTesting, closeTo(1.53, 0.04));
    expect(
      TempleRunRules.overlapsLanePosition(
        lane: 2,
        positionInLanes: game.lateralPositionForTesting,
        halfWidthInLanes: TempleRunRules.pickupHalfWidthInLanes,
      ),
      isFalse,
    );
    expect(game.shieldChargesForTesting, 0);
    expect(game.expiredPowerUpIndicesForTesting, isEmpty);

    game.advanceTimeForTesting(const Duration(milliseconds: 40));

    expect(game.distanceMetersForTesting, lessThan(20));
    expect(game.shieldChargesForTesting, 1);
    expect(game.collectedPowerUpIndicesForTesting, {0});
  });

  test('overlapping coins are each collected once across a large update', () {
    final game = _game(
      gameDuration: const Duration(seconds: 8),
      course: _course(
        coins: const [
          TempleRunCoin(distanceMeters: 10, lane: 1),
          TempleRunCoin(distanceMeters: 10.2, lane: 1),
          TempleRunCoin(distanceMeters: 11, lane: 1),
        ],
      ),
    );
    addTearDown(game.disposeController);

    game.advanceTimeForTesting(const Duration(seconds: 4));
    expect(game.coinsForTesting, 3);
    expect(game.collectedCoinIndicesForTesting, {0, 1, 2});
    expect(game.expiredCoinIndicesForTesting, isEmpty);
    game.advanceTimeForTesting(const Duration(seconds: 1));
    expect(game.coinsForTesting, 3);
  });

  test(
    'a missed coin stays visible and expires only after the trailing edge',
    () {
      final game = _game(
        course: _course(
          coins: const [TempleRunCoin(distanceMeters: 10, lane: 2)],
        ),
      );
      addTearDown(game.disposeController);

      _advanceToDistance(game, 11.64);
      expect(game.coinsForTesting, 0);
      expect(game.expiredCoinIndicesForTesting, isEmpty);
      _advanceToDistance(game, 11.8);
      expect(game.expiredCoinIndicesForTesting, {0});
      expect(game.collectedCoinIndicesForTesting, isEmpty);
    },
  );

  test('a missed power-up expires only after its trailing edge', () {
    final game = _game(
      course: _course(
        powerUps: const [
          TempleRunPowerUp(
            distanceMeters: 10,
            lane: 2,
            kind: TempleRunPowerUpKind.shield,
          ),
        ],
      ),
    );
    addTearDown(game.disposeController);

    _advanceToDistance(game, 11.64);
    expect(game.expiredPowerUpIndicesForTesting, isEmpty);
    _advanceToDistance(game, 11.8);
    expect(game.expiredPowerUpIndicesForTesting, {0});
    expect(game.collectedPowerUpIndicesForTesting, isEmpty);
  });

  test('magnet collects overlapping coins from other lanes', () {
    final game = _game(
      course: _course(
        coins: const [
          TempleRunCoin(distanceMeters: 6, lane: 2),
          TempleRunCoin(distanceMeters: 8, lane: 0),
        ],
        powerUps: const [
          TempleRunPowerUp(
            distanceMeters: 5,
            lane: 1,
            kind: TempleRunPowerUpKind.magnet,
          ),
        ],
      ),
    );
    addTearDown(game.disposeController);

    _advanceToDistance(game, 9);

    expect(game.magnetRemainingForTesting, greaterThan(0));
    expect(game.coinsForTesting, 2);
    expect(game.collectedCoinIndicesForTesting, {0, 1});
    expect(game.collectedPowerUpIndicesForTesting, {0});
  });

  test('all power-up kinds are consumed once and activate their effect', () {
    for (final kind in TempleRunPowerUpKind.values) {
      final game = _game(
        course: _course(
          powerUps: [TempleRunPowerUp(distanceMeters: 5, lane: 1, kind: kind)],
        ),
      );
      _advanceToDistance(game, 5);

      expect(game.collectedPowerUpIndicesForTesting, {0}, reason: '$kind');
      expect(game.expiredPowerUpIndicesForTesting, isEmpty, reason: '$kind');
      switch (kind) {
        case TempleRunPowerUpKind.magnet:
          expect(game.magnetRemainingForTesting, greaterThan(0));
        case TempleRunPowerUpKind.shield:
          expect(game.shieldChargesForTesting, 1);
        case TempleRunPowerUpKind.boost:
          expect(game.boostRemainingForTesting, greaterThan(0));
      }
      game.advanceTimeForTesting(const Duration(milliseconds: 500));
      expect(game.collectedPowerUpIndicesForTesting, {0}, reason: '$kind');
      game.disposeController();
    }
  });

  test('renderer immediately hides a consumed coin', () async {
    final course = _course(
      coins: const [TempleRunCoin(distanceMeters: 20, lane: 1)],
    );
    final visible = _art(course);
    final consumed = _art(course, consumedCoinIndices: const {0});
    final visibleImage = await _render(visible);
    final consumedImage = await _render(consumed);
    addTearDown(visibleImage.dispose);
    addTearDown(consumedImage.dispose);

    final visibleBytes = await visibleImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final consumedBytes = await consumedImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(visibleBytes, isNotNull);
    expect(consumedBytes, isNotNull);
    expect(
      visibleBytes!.buffer.asUint8List(
        visibleBytes.offsetInBytes,
        visibleBytes.offsetInBytes + visibleBytes.lengthInBytes,
      ),
      isNot(
        equals(
          consumedBytes!.buffer.asUint8List(
            consumedBytes.offsetInBytes,
            consumedBytes.offsetInBytes + consumedBytes.lengthInBytes,
          ),
        ),
      ),
    );
  });

  test(
    'collection feedback is once-only, readable, and survives consumption',
    () async {
      final course = _course(
        coins: const [TempleRunCoin(distanceMeters: 18, lane: 1)],
        powerUps: const [
          TempleRunPowerUp(
            distanceMeters: 18,
            lane: 1,
            kind: TempleRunPowerUpKind.shield,
          ),
        ],
      );
      final art = _art(course);
      art.updateScene(
        course: course,
        distanceMeters: 18.35,
        lane: TempleRunRules.centerLane,
        visualLane: TempleRunRules.centerLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 0,
        activeTurn: null,
        bendProgress: 0,
        bendDirection: null,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
        collectedCoinIndices: const {0},
        collectedPowerUpIndices: const {0},
      );
      expect(art.activePickupEffectCountForTesting, 2);
      expect(
        art.activePickupEffectLabelsForTesting,
        containsAll(<String>['+10', 'SHIELD']),
      );

      final effectImage = await _render(art);
      addTearDown(effectImage.dispose);
      final effectBytes = await effectImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(effectBytes, isNotNull);
      final effectPng = await effectImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      expect(effectPng, isNotNull);
      final capture = File(
        'artifacts/temple_run/pickup_fx_candidates/coin_plus10_shield_ring.png',
      )..createSync(recursive: true);
      capture.writeAsBytesSync(
        effectPng!.buffer.asUint8List(
          effectPng.offsetInBytes,
          effectPng.offsetInBytes + effectPng.lengthInBytes,
        ),
      );

      art.updateScene(
        course: course,
        distanceMeters: 18.35,
        lane: TempleRunRules.centerLane,
        visualLane: TempleRunRules.centerLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 0,
        activeTurn: null,
        bendProgress: 0,
        bendDirection: null,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
        consumedCoinIndices: const {0},
        consumedPowerUpIndices: const {0},
        collectedCoinIndices: const {0},
        collectedPowerUpIndices: const {0},
        deltaSeconds: .2,
      );
      expect(art.activePickupEffectCountForTesting, 2);
      expect(art.activePickupEffectLabelsForTesting, contains('+10'));

      // Expiry/consumption updates cannot replay the burst because the
      // collected set is unchanged, and the effect still owns its lifetime.
      art.updateScene(
        course: course,
        distanceMeters: 18.35,
        lane: TempleRunRules.centerLane,
        visualLane: TempleRunRules.centerLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 0,
        activeTurn: null,
        bendProgress: 0,
        bendDirection: null,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
        consumedCoinIndices: const {0},
        consumedPowerUpIndices: const {0},
        collectedCoinIndices: const {0},
        collectedPowerUpIndices: const {0},
        deltaSeconds: .31,
      );
      expect(art.activePickupEffectCountForTesting, 0);

      final expiredOnly = _art(course, consumedCoinIndices: const {0});
      expect(expiredOnly.activePickupEffectCountForTesting, 0);
    },
  );

  test(
    'production pickup captures keep labels readable over the runner',
    () async {
      final fontLoader = FontLoader('Galmuri')
        ..addFont(rootBundle.load('assets/fonts/Galmuri11-Bold.ttf'));
      await fontLoader.load();
      final images = await TempleRunArt.loadImageAssets();
      try {
        final coinCourse = _course(
          coins: const [TempleRunCoin(distanceMeters: 18, lane: 1)],
        );
        final coinArt = TempleRunArt(
          images: images,
          useImageAssets: true,
          viewportWidth: TempleRunRules.logicalWidth,
          viewportHeight: TempleRunRules.logicalHeight,
        );
        _updateCollectedScene(coinArt, coinCourse, coins: const {0});
        await _writeCapture(coinArt, 'pickup_coin_plus10_production.png');
        expect(coinArt.activePickupEffectLabelsForTesting, contains('+10'));

        final powerUpCourse = _course(
          powerUps: const [
            TempleRunPowerUp(
              distanceMeters: 18,
              lane: 1,
              kind: TempleRunPowerUpKind.shield,
            ),
          ],
        );
        final powerUpArt = TempleRunArt(
          images: images,
          useImageAssets: true,
          viewportWidth: TempleRunRules.logicalWidth,
          viewportHeight: TempleRunRules.logicalHeight,
        );
        _updateCollectedScene(powerUpArt, powerUpCourse, powerUps: const {0});
        await _writeCapture(powerUpArt, 'pickup_shield_production.png');
        expect(
          powerUpArt.activePickupEffectLabelsForTesting,
          contains('SHIELD'),
        );
      } finally {
        for (final image in images.values) {
          image.dispose();
        }
      }
    },
  );

  test(
    'scene reset clears pickup feedback without replaying collected sets',
    () {
      final course = _course(
        coins: const [TempleRunCoin(distanceMeters: 18, lane: 1)],
      );
      final art = _art(course);
      art.updateScene(
        course: course,
        distanceMeters: 18.35,
        lane: TempleRunRules.centerLane,
        visualLane: TempleRunRules.centerLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 0,
        activeTurn: null,
        bendProgress: 0,
        bendDirection: null,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
        collectedCoinIndices: const {0},
      );
      expect(art.activePickupEffectCountForTesting, 1);

      art.updateScene(
        course: course,
        distanceMeters: 17,
        lane: TempleRunRules.centerLane,
        visualLane: TempleRunRules.centerLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 0,
        activeTurn: null,
        bendProgress: 0,
        bendDirection: null,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
        collectedCoinIndices: const {0},
      );
      expect(art.activePickupEffectCountForTesting, 0);
      art.updateScene(
        course: course,
        distanceMeters: 18.35,
        lane: TempleRunRules.centerLane,
        visualLane: TempleRunRules.centerLane.toDouble(),
        jumpRemaining: 0,
        slideRemaining: 0,
        runnerFrame: 0,
        activeTurn: null,
        bendProgress: 0,
        bendDirection: null,
        guardianVisible: false,
        failureVisible: false,
        shieldVisible: false,
        boostVisible: false,
        collectedCoinIndices: const {0},
      );
      expect(art.activePickupEffectCountForTesting, 0);
    },
  );
}

TempleRunGame _game({
  required TempleRunCourse course,
  Duration gameDuration = const Duration(seconds: 20),
}) => TempleRunGame(
  gameDuration: gameDuration,
  countdownDuration: Duration.zero,
  enableTiltInput: false,
  random: Random(7),
  course: course,
  onFinished: (_) {},
);

TempleRunCourse _course({
  List<TempleRunCoin> coins = const [],
  List<TempleRunPowerUp> powerUps = const [],
}) => TempleRunCourse(
  obstacles: const [],
  coins: coins,
  powerUps: powerUps,
  turns: const [],
  totalDistanceMeters: 100,
);

void _advanceToDistance(TempleRunGame game, double distance) {
  final targetElapsed = TempleRunRules.elapsedForDistance(distance);
  final remaining = targetElapsed - game.playingElapsedForTesting;
  // Use the internal clock directly; the gameplay adapter still divides a
  // large frame delta into bounded simulation steps.
  game.advanceTimeForTesting(
    Duration(
      microseconds: (remaining * Duration.microsecondsPerSecond).round(),
    ),
  );
}

TempleRunArt _art(
  TempleRunCourse course, {
  Set<int> consumedCoinIndices = const {},
}) {
  final art = TempleRunArt(
    viewportWidth: TempleRunRules.logicalWidth,
    viewportHeight: TempleRunRules.logicalHeight,
  );
  art.updateScene(
    course: course,
    distanceMeters: 18.35,
    lane: TempleRunRules.centerLane,
    visualLane: TempleRunRules.centerLane.toDouble(),
    jumpRemaining: 0,
    slideRemaining: 0,
    runnerFrame: 0,
    activeTurn: null,
    bendProgress: 0,
    bendDirection: null,
    guardianVisible: false,
    failureVisible: false,
    shieldVisible: false,
    boostVisible: false,
    consumedCoinIndices: consumedCoinIndices,
  );
  return art;
}

Future<ui.Image> _render(TempleRunArt art) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 360, 640));
  art.render(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(360, 640);
  picture.dispose();
  return image;
}

void _updateCollectedScene(
  TempleRunArt art,
  TempleRunCourse course, {
  Set<int> coins = const <int>{},
  Set<int> powerUps = const <int>{},
}) {
  void update({
    Set<int> collectedCoins = const <int>{},
    Set<int> collectedPowerUps = const <int>{},
  }) {
    art.updateScene(
      course: course,
      distanceMeters: 18.35,
      lane: TempleRunRules.centerLane,
      visualLane: TempleRunRules.centerLane.toDouble(),
      jumpRemaining: 0,
      slideRemaining: 0,
      runnerFrame: 0,
      activeTurn: null,
      bendProgress: 0,
      bendDirection: null,
      guardianVisible: false,
      failureVisible: false,
      shieldVisible: false,
      boostVisible: false,
      collectedCoinIndices: collectedCoins,
      collectedPowerUpIndices: collectedPowerUps,
      consumedCoinIndices: collectedCoins,
      consumedPowerUpIndices: collectedPowerUps,
    );
  }

  update();
  if (coins.isNotEmpty || powerUps.isNotEmpty) {
    update(collectedCoins: coins, collectedPowerUps: powerUps);
  }
}

Future<void> _writeCapture(TempleRunArt art, String name) async {
  final image = await _render(art);
  addTearDown(image.dispose);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  expect(png, isNotNull);
  final file = File('artifacts/temple_run/pickup_fx_candidates/$name')
    ..createSync(recursive: true);
  file.writeAsBytesSync(
    png!.buffer.asUint8List(
      png.offsetInBytes,
      png.offsetInBytes + png.lengthInBytes,
    ),
  );
}
