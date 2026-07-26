import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/number_rush/domain/number_rush_rules.dart';

class NumberRushGame extends FlameGame
    with TapCallbacks
    implements MiniGameController {
  NumberRushGame({
    required this.onFinished,
    this.countdownDuration = const Duration(seconds: 3),
    this.maxDuration = const Duration(minutes: 2),
    Random? random,
  }) : _random = random ?? Random(),
       hud = ValueNotifier(
         MiniGameHudState(
           phase: countdownDuration == Duration.zero
               ? MiniGamePhase.playing
               : MiniGamePhase.countdown,
           score: 0,
           elapsedSeconds: 0,
           remainingSeconds: null,
           countdownNumber: countdownDuration.inSeconds,
         ),
       );

  static final logicalSize = Vector2(360, 640);

  final Duration countdownDuration;
  final Duration maxDuration;
  final ValueChanged<GameResult> onFinished;
  final Random _random;

  @override
  final ValueNotifier<MiniGameHudState> hud;

  @override
  FlameGame get flameGame => this;

  late final _NumberRushBoard _board;
  var _phase = MiniGamePhase.countdown;
  var _countdownElapsed = 0.0;
  var _playingElapsed = 0.0;
  var _lastPublishedCentisecond = -1;
  var _hasFinished = false;

  @override
  Color backgroundColor() => const Color(0xFF030713);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewport = FixedResolutionViewport(resolution: logicalSize);
    camera.viewfinder.position = logicalSize / 2;

    final background = await images.load('number_rush/arcade_background.png');
    final buttonSheet = await images.load(
      'number_rush/number_button_states.png',
    );
    final fxSheet = await images.load('number_rush/arcade_fx_sheet.png');
    await world.add(
      SpriteComponent(
        sprite: Sprite(background),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );

    final tiles = NumberRushRules.shuffledTiles(_random);
    _board = _NumberRushBoard(
      tiles: tiles,
      random: _random,
      buttonSprites: _spritesFromSheet(
        buttonSheet,
        columns: 3,
        rows: 2,
        cellSize: 56,
      ),
      fxSprites: _spritesFromSheet(fxSheet, columns: 4, rows: 2, cellSize: 64),
    );
    await world.add(_board);

    if (countdownDuration == Duration.zero) {
      _phase = MiniGamePhase.playing;
      _board.isPlaying = true;
      _publishHud(force: true);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    switch (_phase) {
      case MiniGamePhase.countdown:
        _countdownElapsed += dt;
        final countdownSeconds =
            countdownDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_countdownElapsed >= countdownSeconds) {
          _phase = MiniGamePhase.playing;
          _board.isPlaying = true;
          _publishHud(force: true);
        } else {
          _publishHud();
        }
      case MiniGamePhase.playing:
        _playingElapsed += dt;
        final maxSeconds =
            maxDuration.inMicroseconds / Duration.microsecondsPerSecond;
        if (_playingElapsed >= maxSeconds) {
          _playingElapsed = maxSeconds;
          _board.elapsedSeconds = _playingElapsed;
          unawaited(HapticFeedback.mediumImpact());
          _finishGame(timedOut: true);
          return;
        }
        _board.elapsedSeconds = _playingElapsed;
        _publishHud();
      case MiniGamePhase.finished:
        return;
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (_phase != MiniGamePhase.playing) return;
    final position = camera.viewport.globalToLocal(event.canvasPosition);
    tapLogicalPosition(position);
  }

  @visibleForTesting
  void tapLogicalPosition(Vector2 position) {
    if (_phase != MiniGamePhase.playing) return;
    final result = _board.tap(position);
    switch (result) {
      case _TapResult.miss:
        return;
      case _TapResult.wrong:
        unawaited(HapticFeedback.heavyImpact());
      case _TapResult.correct:
        unawaited(HapticFeedback.mediumImpact());
      case _TapResult.completed:
        unawaited(HapticFeedback.heavyImpact());
        _finishGame(timedOut: false);
    }
  }

  void _finishGame({required bool timedOut}) {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    final elapsedMs = max(1, (_playingElapsed * 1000).round());
    _board.complete(elapsedMs, timedOut: timedOut);
    _publishHud(force: true);
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (!isMounted) return;
      pauseEngine();
      onFinished(
        GameResult(
          score: NumberRushRules.rankingScoreFromElapsedMs(elapsedMs),
          starsCollected: 0,
          collisions: timedOut ? 1 : 0,
          duration: Duration(milliseconds: elapsedMs),
        ),
      );
    });
  }

  void _publishHud({bool force = false}) {
    final centisecond = (_playingElapsed * 100).floor();
    final countdown = max(
      0,
      (countdownDuration.inMicroseconds / Duration.microsecondsPerSecond -
              _countdownElapsed)
          .ceil(),
    );
    if (!force &&
        centisecond == _lastPublishedCentisecond &&
        hud.value.countdownNumber == countdown) {
      return;
    }
    _lastPublishedCentisecond = centisecond;
    hud.value = MiniGameHudState(
      phase: _phase,
      score: _board.nextNumber - 1,
      elapsedSeconds: _playingElapsed.floor(),
      remainingSeconds: null,
      countdownNumber: countdown,
    );
  }

  @override
  void interrupt() {
    if (_hasFinished) return;
    _hasFinished = true;
    _phase = MiniGamePhase.finished;
    _board.isPlaying = false;
    _publishHud(force: true);
    pauseEngine();
  }

  @override
  void disposeController() => hud.dispose();

  List<Sprite> _spritesFromSheet(
    ui.Image image, {
    required int columns,
    required int rows,
    required double cellSize,
  }) {
    return [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          Sprite(
            image,
            srcPosition: Vector2(column * cellSize, row * cellSize),
            srcSize: Vector2.all(cellSize),
          ),
    ];
  }
}

enum _TapResult { miss, wrong, correct, completed }

class _IgnitionState {
  _IgnitionState({required this.delayRemaining});

  double delayRemaining;
  double elapsed = 0;
}

class _NumberRushBoard extends PositionComponent {
  _NumberRushBoard({
    required this.tiles,
    required this.random,
    required this.buttonSprites,
    required this.fxSprites,
  }) : assert(tiles.length == NumberRushRules.boardSlotCount),
       assert(buttonSprites.length == 6),
       assert(fxSprites.length == 8),
       super(position: Vector2.zero(), size: NumberRushGame.logicalSize);

  static const _boardLeft = 27.0;
  static const _boardTop = 166.0;
  static const _tileSize = 56.0;
  static const _gap = 4.0;
  static const _step = _tileSize + _gap;
  static const _shutdownDuration = 0.34;
  static const _ignitionDuration = 0.48;

  final List<int> tiles;
  final Random random;
  final List<Sprite> buttonSprites;
  final List<Sprite> fxSprites;
  final Set<int> _cleared = {};
  final Map<int, double> _shutdownRemaining = {};
  final Map<int, _IgnitionState> _ignitions = {};
  final Paint _fill = Paint()..isAntiAlias = false;
  final Paint _stroke = Paint()
    ..isAntiAlias = false
    ..style = PaintingStyle.stroke;

  var nextNumber = 1;
  var _nextReserveNumber = NumberRushRules.firstReserveNumber;
  var elapsedSeconds = 0.0;
  var isPlaying = false;
  var _wrongIndex = -1;
  var _wrongTime = 0.0;
  var _timedOut = false;
  int? _finalElapsedMs;

  _TapResult tap(Vector2 point) {
    final index = _tileIndexAt(point);
    if (!isPlaying || index == null || _cleared.contains(index)) {
      return _TapResult.miss;
    }
    if (!NumberRushRules.isCorrectTap(
      expected: nextNumber,
      tapped: tiles[index],
    )) {
      _wrongIndex = index;
      _wrongTime = 0.16;
      return _TapResult.wrong;
    }

    _cleared.add(index);
    _shutdownRemaining[index] = _shutdownDuration;
    nextNumber++;
    _refillIfNeeded(excludingIndex: index);
    if (nextNumber > NumberRushRules.maximumNumber) {
      isPlaying = false;
      return _TapResult.completed;
    }
    return _TapResult.correct;
  }

  void _refillIfNeeded({required int excludingIndex}) {
    final activeCount = tiles.length - _cleared.length + _ignitions.length;
    if (!NumberRushRules.shouldRefill(
      activeCount: activeCount,
      nextReserveNumber: _nextReserveNumber,
    )) {
      return;
    }

    final fullyOffCandidates = _cleared
        .where(
          (index) =>
              index != excludingIndex &&
              !_shutdownRemaining.containsKey(index) &&
              !_ignitions.containsKey(index),
        )
        .toList();
    final candidates = fullyOffCandidates.isNotEmpty
        ? fullyOffCandidates
        : _cleared
              .where(
                (index) =>
                    index != excludingIndex && !_ignitions.containsKey(index),
              )
              .toList();
    if (candidates.isEmpty) return;

    final slotIndex = candidates[random.nextInt(candidates.length)];
    tiles[slotIndex] = _nextReserveNumber;
    _nextReserveNumber++;
    _shutdownRemaining.remove(slotIndex);
    _ignitions[slotIndex] = _IgnitionState(
      delayRemaining: NumberRushRules.refillDelaySeconds(random),
    );
  }

  void complete(int elapsedMs, {required bool timedOut}) {
    _finalElapsedMs = elapsedMs;
    _timedOut = timedOut;
  }

  int? _tileIndexAt(Vector2 point) {
    final localX = point.x - _boardLeft;
    final localY = point.y - _boardTop;
    if (localX < 0 || localY < 0) return null;
    final column = localX ~/ _step;
    final row = localY ~/ _step;
    if (column >= 5 || row >= 5) return null;
    if (localX % _step > _tileSize || localY % _step > _tileSize) return null;
    return row * 5 + column;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _wrongTime = max(0, _wrongTime - dt);
    for (final index in _shutdownRemaining.keys.toList()) {
      final remaining = _shutdownRemaining[index]! - dt;
      if (remaining <= 0) {
        _shutdownRemaining.remove(index);
      } else {
        _shutdownRemaining[index] = remaining;
      }
    }
    for (final entry in _ignitions.entries.toList()) {
      final ignition = entry.value;
      if (ignition.delayRemaining > 0) {
        ignition.delayRemaining = max(0, ignition.delayRemaining - dt);
        continue;
      }
      ignition.elapsed += dt;
      if (ignition.elapsed >= _ignitionDuration) {
        _ignitions.remove(entry.key);
        _cleared.remove(entry.key);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderMachineShell(canvas);
    _renderTopPanel(canvas);
    _renderGridFrame(canvas);
    for (var index = 0; index < tiles.length; index++) {
      _renderTile(canvas, index);
    }
    _renderFooter(canvas);
  }

  void _renderMachineShell(Canvas canvas) {
    final body = Path()
      ..moveTo(28, 8)
      ..lineTo(332, 8)
      ..lineTo(352, 28)
      ..lineTo(352, 602)
      ..lineTo(336, 628)
      ..lineTo(24, 628)
      ..lineTo(8, 602)
      ..lineTo(8, 28)
      ..close();
    _fill.color = const Color(0xF5080B1A);
    canvas.drawPath(body, _fill);
    _stroke
      ..color = const Color(0xFF1C0D33)
      ..strokeWidth = 12;
    canvas.drawPath(body, _stroke);
    _stroke
      ..color = const Color(0xFF64268F)
      ..strokeWidth = 3;
    canvas.drawPath(body, _stroke);

    final screenBezel = Path()
      ..moveTo(30, 14)
      ..lineTo(330, 14)
      ..lineTo(346, 30)
      ..lineTo(346, 480)
      ..lineTo(332, 496)
      ..lineTo(28, 496)
      ..lineTo(14, 480)
      ..lineTo(14, 30)
      ..close();
    _fill.color = const Color(0xFF090D20);
    canvas.drawPath(screenBezel, _fill);
    _stroke
      ..color = const Color(0xFF261240)
      ..strokeWidth = 10;
    canvas.drawPath(screenBezel, _stroke);
    _stroke
      ..color = const Color(0xFFFF4FC3)
      ..strokeWidth = 2;
    canvas.drawPath(screenBezel, _stroke);

    final glass = RRect.fromRectAndRadius(
      const Rect.fromLTWH(22, 24, 316, 462),
      const Radius.circular(10),
    );
    _fill.color = const Color(0xF2020715);
    canvas.drawRRect(glass, _fill);
    _stroke
      ..color = const Color(0xFF39F3FF)
      ..strokeWidth = 1;
    canvas.drawRRect(glass, _stroke);

    _fill.color = const Color(0x1000EFFF);
    for (var y = 30.0; y < 482; y += 4) {
      canvas.drawRect(Rect.fromLTWH(25, y, 310, 1), _fill);
    }
    final reflection = Path()
      ..moveTo(30, 32)
      ..lineTo(132, 32)
      ..lineTo(72, 168)
      ..lineTo(30, 198)
      ..close();
    _fill.color = const Color(0x0900EFFF);
    canvas.drawPath(reflection, _fill);

    _drawRail(
      canvas,
      const Offset(34, 12),
      const Offset(326, 12),
      const Color(0xFFFF4FC3),
    );
    _drawRail(
      canvas,
      const Offset(12, 44),
      const Offset(12, 462),
      const Color(0xFF39F3FF),
    );
    _drawRail(
      canvas,
      const Offset(348, 44),
      const Offset(348, 462),
      const Color(0xFFFF4FC3),
    );
  }

  void _renderTopPanel(Canvas canvas) {
    _drawText(
      canvas,
      'NUMBER RUSH',
      const Offset(203, 38),
      fontSize: 19,
      color: const Color(0xFF39F3FF),
      anchor: _TextAnchor.topCenter,
    );
    _stroke
      ..color = const Color(0xFF352057)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(45, 64), const Offset(315, 64), _stroke);
    canvas.drawLine(const Offset(180, 72), const Offset(180, 130), _stroke);
    _drawText(
      canvas,
      'TIME',
      const Offset(110, 78),
      fontSize: 9,
      color: const Color(0xFF7AF8FF),
      anchor: _TextAnchor.topCenter,
    );
    _drawText(
      canvas,
      'NEXT',
      const Offset(250, 78),
      fontSize: 9,
      color: const Color(0xFFFF77CE),
      anchor: _TextAnchor.topCenter,
    );
    final elapsedMs = _finalElapsedMs ?? (elapsedSeconds * 1000).round();
    _drawText(
      canvas,
      NumberRushRules.formatElapsedMs(elapsedMs).replaceAll('초', ''),
      const Offset(110, 96),
      fontSize: 21,
      color: const Color(0xFF39F3FF),
      anchor: _TextAnchor.topCenter,
    );
    _drawText(
      canvas,
      nextNumber <= NumberRushRules.maximumNumber ? '$nextNumber' : 'CLEAR',
      const Offset(250, 96),
      fontSize: nextNumber <= NumberRushRules.maximumNumber ? 21 : 14,
      color: nextNumber <= NumberRushRules.maximumNumber
          ? const Color(0xFFFF77CE)
          : const Color(0xFFFFD84A),
      anchor: _TextAnchor.topCenter,
    );
  }

  void _renderGridFrame(Canvas canvas) {
    _stroke
      ..color = const Color(0xFF352057)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(36, 146), const Offset(324, 146), _stroke);
    _fill.color = const Color(0x1800EFFF);
    canvas.drawRect(const Rect.fromLTWH(24, 154, 312, 318), _fill);
  }

  void _renderTile(Canvas canvas, int index) {
    final row = index ~/ 5;
    final column = index % 5;
    final x = _boardLeft + column * _step;
    final y = _boardTop + row * _step;
    final isCleared = _cleared.contains(index);
    final isWrong = index == _wrongIndex && _wrongTime > 0;
    final ignition = _ignitions[index];
    final isIgniting = ignition != null && ignition.delayRemaining <= 0;
    final ignitionElapsed = isIgniting ? ignition.elapsed : 0.0;
    final shutdownRemaining = _shutdownRemaining[index];
    final isShuttingDown = shutdownRemaining != null;
    final shutdownElapsed = isShuttingDown
        ? _shutdownDuration - shutdownRemaining
        : 0.0;
    final firstGlow = shutdownElapsed < 0.05;
    final relapseGlow = shutdownElapsed >= 0.11 && shutdownElapsed < 0.17;
    final neonOn = firstGlow || relapseGlow;
    final ignitionGlow =
        isIgniting &&
        ((ignitionElapsed < 0.07) ||
            (ignitionElapsed >= 0.14 && ignitionElapsed < 0.23) ||
            ignitionElapsed >= 0.31);
    final ignitionStableGlow = isIgniting && ignitionElapsed >= 0.31;
    final shake = isWrong ? sin(_wrongTime * 120) * 2.2 : 0.0;
    final rect = Rect.fromLTWH(x + shake, y, _tileSize, _tileSize);
    final spriteIndex = isWrong
        ? 3
        : isShuttingDown
        ? neonOn
              ? tiles[index] == 25
                    ? 4
                    : 0
              : 2
        : ignitionGlow
        ? tiles[index] == NumberRushRules.maximumNumber
              ? 4
              : 0
        : isCleared
        ? 2
        : tiles[index] == NumberRushRules.maximumNumber
        ? 4
        : 0;
    buttonSprites[spriteIndex].render(
      canvas,
      position: Vector2(rect.left, rect.top),
      size: Vector2(rect.width, rect.height),
    );
    if (isShuttingDown && shutdownElapsed >= 0.17 && shutdownElapsed < 0.26) {
      _renderNeonFaultArcs(canvas, rect, shutdownElapsed);
    } else if (isWrong) {
      fxSprites[4].render(
        canvas,
        position: Vector2(rect.left - 3, rect.top - 3),
        size: Vector2.all(rect.width + 6),
      );
    }
    final showNumber = ignition != null
        ? isIgniting && ignitionGlow
        : !isShuttingDown || neonOn || shutdownElapsed >= 0.26;
    if (showNumber) {
      _drawText(
        canvas,
        '${tiles[index]}',
        Offset(rect.center.dx, rect.center.dy - (tiles[index] >= 10 ? 13 : 15)),
        fontSize: tiles[index] >= 10 ? 20 : 24,
        color: isIgniting
            ? ignitionStableGlow
                  ? const Color(0xFF5DF5FF)
                  : const Color(0xFF58BBC8)
            : isShuttingDown
            ? shutdownElapsed < 0.06
                  ? const Color(0xFFE9FFFF)
                  : relapseGlow
                  ? const Color(0xFF9FFFFF)
                  : const Color(0xFF183348)
            : isCleared
            ? const Color(0xFF183348)
            : tiles[index] == NumberRushRules.maximumNumber
            ? const Color(0xFFFFD84A)
            : const Color(0xFF5DF5FF),
        anchor: _TextAnchor.topCenter,
      );
    }
  }

  void _renderNeonFaultArcs(Canvas canvas, Rect rect, double elapsed) {
    final phase = ((elapsed - 0.17) / 0.03).floor();
    final successCracklePaint = Paint()
      ..isAntiAlias = false
      ..colorFilter = ColorFilter.mode(
        phase.isEven ? const Color(0xFFE8FFFF) : const Color(0xFF39F3FF),
        BlendMode.srcIn,
      );
    fxSprites[4].render(
      canvas,
      position: Vector2(rect.left - 3, rect.top - 3),
      size: Vector2.all(rect.width + 6),
      overridePaint: successCracklePaint,
    );
  }

  void _renderFooter(Canvas canvas) {
    _drawText(
      canvas,
      _finalElapsedMs == null
          ? '1 → 50  순서대로 터치'
          : _timedOut
          ? 'TIME UP'
          : 'CLEAR!',
      const Offset(180, 472),
      fontSize: _finalElapsedMs == null ? 9 : 14,
      color: _finalElapsedMs == null
          ? const Color(0xFF9FFBFF)
          : const Color(0xFFFFD84A),
      anchor: _TextAnchor.topCenter,
    );

    final deck = Path()
      ..moveTo(24, 504)
      ..lineTo(336, 504)
      ..lineTo(350, 524)
      ..lineTo(336, 610)
      ..lineTo(24, 610)
      ..lineTo(10, 524)
      ..close();
    _fill.color = const Color(0xF00A0D1E);
    canvas.drawPath(deck, _fill);
    _stroke
      ..color = const Color(0xFF64268F)
      ..strokeWidth = 3;
    canvas.drawPath(deck, _stroke);
    _drawVent(canvas, const Rect.fromLTWH(30, 526, 62, 54), horizontal: true);
    _drawVent(canvas, const Rect.fromLTWH(268, 526, 62, 54), horizontal: true);
    _drawScrew(canvas, const Offset(22, 522), const Color(0xFF39F3FF));
    _drawScrew(canvas, const Offset(338, 522), const Color(0xFFFF4FC3));

    _fill.color = const Color(0xFF02050E);
    canvas.drawRect(const Rect.fromLTWH(154, 534, 52, 54), _fill);
    _stroke
      ..color = const Color(0xFF3C255D)
      ..strokeWidth = 2;
    canvas.drawRect(const Rect.fromLTWH(154, 534, 52, 54), _stroke);
    _fill.color = const Color(0xFFFFD84A);
    canvas.drawRect(const Rect.fromLTWH(167, 542, 26, 6), _fill);
    _fill.color = const Color(0xFF10182B);
    canvas.drawRect(const Rect.fromLTWH(174, 555, 12, 25), _fill);

    _drawText(
      canvas,
      _finalElapsedMs == null
          ? 'TAP FAST · BEAT YOUR BEST'
          : _timedOut
          ? 'LIMIT 120.00'
          : 'NEW RECORD?',
      const Offset(180, 512),
      fontSize: 8,
      color: const Color(0xFFFF77CE),
      anchor: _TextAnchor.topCenter,
    );
  }

  void _drawRail(Canvas canvas, Offset start, Offset end, Color color) {
    _stroke
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(start, end, _stroke);
    _stroke
      ..color = color.withValues(alpha: 0.28)
      ..strokeWidth = 5;
    canvas.drawLine(start, end, _stroke);
  }

  void _drawScrew(Canvas canvas, Offset center, Color accent) {
    _fill.color = const Color(0xFF020611);
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 6, height: 6),
      _fill,
    );
    _stroke
      ..color = accent
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 6, height: 6),
      _stroke,
    );
    canvas.drawLine(
      center - const Offset(2, 0),
      center + const Offset(2, 0),
      _stroke,
    );
  }

  void _drawVent(Canvas canvas, Rect rect, {bool horizontal = false}) {
    _fill.color = const Color(0xE0020611);
    canvas.drawRect(rect, _fill);
    _stroke
      ..color = const Color(0xFF20395A)
      ..strokeWidth = 1;
    final count = horizontal ? 5 : 6;
    for (var index = 1; index <= count; index++) {
      if (horizontal) {
        final y = rect.top + rect.height * index / (count + 1);
        canvas.drawLine(
          Offset(rect.left + 5, y),
          Offset(rect.right - 5, y),
          _stroke,
        );
      } else {
        final y = rect.top + rect.height * index / (count + 1);
        canvas.drawLine(
          Offset(rect.left + 3, y),
          Offset(rect.right - 3, y),
          _stroke,
        );
      }
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position, {
    required double fontSize,
    required Color color,
    _TextAnchor anchor = _TextAnchor.topLeft,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Galmuri',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: color,
          shadows: const [
            Shadow(color: Color(0xFF06101E), offset: Offset(2, 2)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = switch (anchor) {
      _TextAnchor.topLeft => position,
      _TextAnchor.topCenter => position - Offset(painter.width / 2, 0),
    };
    painter.paint(canvas, offset);
  }
}

enum _TextAnchor { topLeft, topCenter }
