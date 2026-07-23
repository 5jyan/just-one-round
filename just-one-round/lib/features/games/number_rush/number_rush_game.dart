import 'dart:async';
import 'dart:math';

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
    await world.add(
      SpriteComponent(
        sprite: Sprite(background),
        size: logicalSize.clone(),
        priority: -20,
      ),
    );

    final tiles = NumberRushRules.shuffledTiles(_random);
    _board = _NumberRushBoard(tiles: tiles);
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
        unawaited(HapticFeedback.lightImpact());
      case _TapResult.correct:
        unawaited(HapticFeedback.selectionClick());
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
}

enum _TapResult { miss, wrong, correct, completed }

class _NumberRushBoard extends PositionComponent {
  _NumberRushBoard({required this.tiles})
    : assert(tiles.length == NumberRushRules.tileCount),
      super(position: Vector2.zero(), size: NumberRushGame.logicalSize);

  static const _boardLeft = 27.0;
  static const _boardTop = 166.0;
  static const _tileSize = 56.0;
  static const _gap = 4.0;
  static const _step = _tileSize + _gap;

  final List<int> tiles;
  final List<_Burst> _bursts = [];
  final Set<int> _cleared = {};
  final Paint _fill = Paint()..isAntiAlias = false;
  final Paint _stroke = Paint()
    ..isAntiAlias = false
    ..style = PaintingStyle.stroke;

  var nextNumber = 1;
  var elapsedSeconds = 0.0;
  var isPlaying = false;
  var _wrongIndex = -1;
  var _wrongTime = 0.0;
  var _pressedIndex = -1;
  var _pressedTime = 0.0;
  var _completedTime = 0.0;
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

    _pressedIndex = index;
    _pressedTime = 0.18;
    _cleared.add(index);
    _addBurst(_centerOf(index), completion: nextNumber == 25);
    nextNumber++;
    if (nextNumber > NumberRushRules.tileCount) {
      isPlaying = false;
      return _TapResult.completed;
    }
    return _TapResult.correct;
  }

  void complete(int elapsedMs, {required bool timedOut}) {
    _finalElapsedMs = elapsedMs;
    _timedOut = timedOut;
    _completedTime = 0.52;
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

  Vector2 _centerOf(int index) {
    final row = index ~/ 5;
    final column = index % 5;
    return Vector2(
      _boardLeft + column * _step + _tileSize / 2,
      _boardTop + row * _step + _tileSize / 2,
    );
  }

  void _addBurst(Vector2 center, {required bool completion}) {
    final count = completion ? 28 : 9;
    for (var index = 0; index < count; index++) {
      final angle = (pi * 2 * index / count) + (index.isOdd ? 0.11 : 0);
      final speed = completion
          ? 72.0 + (index % 4) * 13
          : 38.0 + (index % 3) * 9;
      _bursts.add(
        _Burst(
          position: center.clone(),
          velocity: Vector2(cos(angle), sin(angle)) * speed,
          color: index % 5 == 0
              ? const Color(0xFFFFD84A)
              : index.isEven
              ? const Color(0xFF39F3FF)
              : const Color(0xFFFF4FC3),
          life: completion ? 0.52 : 0.28,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _wrongTime = max(0, _wrongTime - dt);
    _pressedTime = max(0, _pressedTime - dt);
    _completedTime = max(0, _completedTime - dt);
    for (final burst in _bursts) {
      burst.life -= dt;
      burst.position += burst.velocity * dt;
      burst.velocity *= pow(0.02, dt).toDouble();
    }
    _bursts.removeWhere((burst) => burst.life <= 0);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderTopPanel(canvas);
    _renderGridFrame(canvas);
    for (var index = 0; index < tiles.length; index++) {
      _renderTile(canvas, index);
    }
    for (final burst in _bursts) {
      _fill.color = burst.color.withValues(alpha: min(1, burst.life * 4));
      final size = burst.life > 0.2 ? 3.0 : 2.0;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(burst.position.x, burst.position.y),
          width: size,
          height: size,
        ),
        _fill,
      );
    }
    _renderFooter(canvas);
  }

  void _renderTopPanel(Canvas canvas) {
    _drawPanel(canvas, const Rect.fromLTWH(62, 18, 282, 118));
    _drawText(
      canvas,
      'NUMBER RUSH',
      const Offset(203, 34),
      fontSize: 19,
      color: const Color(0xFF39F3FF),
      anchor: _TextAnchor.topCenter,
    );
    _drawPanel(canvas, const Rect.fromLTWH(78, 65, 122, 58), compact: true);
    _drawPanel(canvas, const Rect.fromLTWH(208, 65, 122, 58), compact: true);
    _drawText(
      canvas,
      'TIME',
      const Offset(139, 72),
      fontSize: 9,
      color: const Color(0xFF7AF8FF),
      anchor: _TextAnchor.topCenter,
    );
    _drawText(
      canvas,
      'NEXT',
      const Offset(269, 72),
      fontSize: 9,
      color: const Color(0xFFFF77CE),
      anchor: _TextAnchor.topCenter,
    );
    final elapsedMs = _finalElapsedMs ?? (elapsedSeconds * 1000).round();
    _drawText(
      canvas,
      NumberRushRules.formatElapsedMs(elapsedMs).replaceAll('초', ''),
      const Offset(139, 91),
      fontSize: 20,
      color: const Color(0xFF39F3FF),
      anchor: _TextAnchor.topCenter,
    );
    _drawText(
      canvas,
      nextNumber <= 25 ? '$nextNumber' : 'CLEAR',
      const Offset(269, 91),
      fontSize: nextNumber <= 25 ? 21 : 14,
      color: nextNumber <= 25
          ? const Color(0xFFFF77CE)
          : const Color(0xFFFFD84A),
      anchor: _TextAnchor.topCenter,
    );
  }

  void _renderGridFrame(Canvas canvas) {
    _fill.color = const Color(0xD9050A1B);
    canvas.drawRect(const Rect.fromLTWH(16, 148, 328, 338), _fill);
    _stroke
      ..color = const Color(0xFF6E2D9F)
      ..strokeWidth = 2;
    canvas.drawRect(const Rect.fromLTWH(17, 149, 326, 336), _stroke);
    _stroke
      ..color = const Color(0xFFEC3EB8)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(25, 155), const Offset(335, 155), _stroke);
  }

  void _renderTile(Canvas canvas, int index) {
    final row = index ~/ 5;
    final column = index % 5;
    final x = _boardLeft + column * _step;
    final y = _boardTop + row * _step;
    final isCleared = _cleared.contains(index);
    final isPressed = index == _pressedIndex && _pressedTime > 0;
    final isWrong = index == _wrongIndex && _wrongTime > 0;
    final shake = isWrong ? sin(_wrongTime * 120) * 2.2 : 0.0;
    final inset = isPressed ? 3.0 : 0.0;
    final rect = Rect.fromLTWH(
      x + shake + inset,
      y + inset,
      _tileSize - inset * 2,
      _tileSize - inset * 2,
    );
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    _fill.color = isCleared ? const Color(0xB0071024) : const Color(0xF20A1938);
    canvas.drawRRect(outer, _fill);
    _stroke
      ..strokeWidth = isPressed || isWrong ? 3 : 2
      ..color = isWrong
          ? const Color(0xFFFF315E)
          : isPressed
          ? const Color(0xFFFF4FC3)
          : isCleared
          ? const Color(0xFF281B4A)
          : const Color(0xFF7B2FB0);
    canvas.drawRRect(outer, _stroke);
    _stroke
      ..strokeWidth = 1
      ..color = isPressed ? const Color(0xFFFFFFFF) : const Color(0xFF39F3FF);
    canvas.drawLine(
      Offset(rect.left + 6, rect.top + 5),
      Offset(rect.right - 6, rect.top + 5),
      _stroke,
    );
    if (tiles[index] == 25 && !isCleared) {
      _stroke
        ..color = const Color(0xFFFFD84A)
        ..strokeWidth = 2;
      canvas.drawRRect(outer.inflate(1), _stroke);
    }
    _drawText(
      canvas,
      '${tiles[index]}',
      Offset(rect.center.dx, rect.center.dy - (tiles[index] >= 10 ? 13 : 15)),
      fontSize: tiles[index] >= 10 ? 20 : 24,
      color: isCleared
          ? const Color(0xFF23435A)
          : tiles[index] == 25
          ? const Color(0xFFFFD84A)
          : isPressed
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF5DF5FF),
      anchor: _TextAnchor.topCenter,
    );
  }

  void _renderFooter(Canvas canvas) {
    _drawText(
      canvas,
      _finalElapsedMs == null
          ? '1 → 25  순서대로 터치'
          : _timedOut
          ? 'TIME UP'
          : 'CLEAR!',
      const Offset(180, 510),
      fontSize: _finalElapsedMs == null ? 13 : 23,
      color: _finalElapsedMs == null
          ? const Color(0xFF9FFBFF)
          : const Color(0xFFFFD84A),
      anchor: _TextAnchor.topCenter,
    );
    _stroke
      ..color = _completedTime > 0
          ? const Color(0xFFFFD84A)
          : const Color(0xFFEC3EB8)
      ..strokeWidth = _completedTime > 0 ? 3 : 1;
    canvas.drawLine(const Offset(58, 548), const Offset(302, 548), _stroke);
    _drawText(
      canvas,
      _finalElapsedMs == null
          ? 'TAP FAST · BEAT YOUR BEST'
          : _timedOut
          ? 'LIMIT 120.00'
          : 'NEW RECORD?',
      const Offset(180, 559),
      fontSize: 10,
      color: const Color(0xFFFF77CE),
      anchor: _TextAnchor.topCenter,
    );
  }

  void _drawPanel(Canvas canvas, Rect rect, {bool compact = false}) {
    final panel = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    _fill.color = const Color(0xE8071025);
    canvas.drawRRect(panel, _fill);
    _stroke
      ..color = const Color(0xFF64268F)
      ..strokeWidth = compact ? 2 : 3;
    canvas.drawRRect(panel, _stroke);
    _stroke
      ..color = const Color(0xFFEF3CB5)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(rect.left + 8, rect.top + 4),
      Offset(rect.right - 8, rect.top + 4),
      _stroke,
    );
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

class _Burst {
  _Burst({
    required this.position,
    required this.velocity,
    required this.color,
    required this.life,
  });

  Vector2 position;
  Vector2 velocity;
  final Color color;
  double life;
}
