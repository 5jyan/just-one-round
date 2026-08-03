import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/presentation/game_end_transition.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/domain/mini_game_seed.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/profile/presentation/nickname_dialog.dart';
import 'package:just_one_round/features/ranking/presentation/nearby_ranking.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({
    this.attempt,
    this.gameDuration,
    this.countdownDuration = const Duration(seconds: 3),
    super.key,
  });

  final Duration? gameDuration;
  final Duration countdownDuration;
  final PlayAttempt? attempt;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  late final MiniGameDefinition _definition;
  late final MiniGameController _game;
  late final DailyGameRepository _repository;
  GameResult? _result;
  GameResult? _pendingResult;
  DailyRankResult? _rankResult;
  Object? _submitError;
  var _isSubmitting = false;
  var _wasInterrupted = false;
  var _hasEnded = false;
  var _isSavingNickname = false;
  var _nicknamePromptShown = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(dailyGameRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _definition = GameRegistry.forId(widget.attempt?.gameId ?? 'dung_dodge_v2');
    final attempt = widget.attempt;
    final challengeSeed = MiniGameSeed.forAttempt(
      gameId: _definition.id,
      gameVersion: attempt?.gameVersion ?? 1,
      playDate: attempt?.playDate,
      attemptOrdinal:
          _definition.id == 'beat_the_dealer' && attempt?.isPractice != true
          ? attempt?.ordinal ?? 1
          : null,
    );
    _game = _definition.create(
      gameDuration:
          widget.gameDuration ??
          _issuedAttemptDuration(widget.attempt) ??
          _definition.defaultDuration,
      countdownDuration: widget.countdownDuration,
      attemptOrdinal: attempt?.ordinal ?? 1,
      challengeSeed: challengeSeed,
      onFinished: _handleFinished,
    );
  }

  Duration? _issuedAttemptDuration(PlayAttempt? attempt) {
    final seconds = attempt?.gameDurationSeconds;
    return seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
  }

  void _handleFinished(GameResult result) {
    if (!mounted || _hasEnded) return;
    setState(() {
      _pendingResult = result;
      _hasEnded = true;
    });
    if (widget.attempt?.isPractice != true) {
      unawaited(_submitResult(result));
    }
  }

  void _revealResult() {
    final result = _pendingResult;
    if (!mounted || result == null) return;
    setState(() {
      _result = result;
      _pendingResult = null;
    });
    _maybePromptForNickname();
  }

  void _maybePromptForNickname() {
    final rank = _rankResult;
    if (_result == null ||
        rank == null ||
        rank.nickname != null ||
        _nicknamePromptShown) {
      return;
    }
    _nicknamePromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_chooseNickname());
    });
  }

  Future<void> _chooseNickname() async {
    final nickname = await showNicknameDialog(context);
    if (nickname == null || !mounted) return;
    setState(() => _isSavingNickname = true);
    try {
      await _repository.setNickname(nickname);
      final rank = await _repository.fetchDailyRank(
        playDate: widget.attempt?.playDate,
      );
      if (!mounted) return;
      setState(() => _rankResult = rank);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('닉네임을 저장하지 못했어요: $error')));
    } finally {
      if (mounted) setState(() => _isSavingNickname = false);
    }
  }

  Future<void> _submitResult(GameResult result) async {
    final attempt = await _resolveAttemptForSubmission();
    if (attempt == null || attempt.isPractice) return;
    if (!mounted) return;
    setState(() => _isSubmitting = true);
    try {
      final rank = await _repository.submitScore(attempt.id, result);
      if (!mounted) return;
      setState(() => _rankResult = rank);
      _maybePromptForNickname();
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitError = error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<PlayAttempt?> _resolveAttemptForSubmission() async {
    final attempt = widget.attempt;
    if (attempt == null) return null;
    final resolver = attempt.resolveForSubmission;
    if (resolver == null) return attempt;
    final resolved = await resolver();
    if (resolved != null) return resolved;
    if (mounted) {
      setState(() => _submitError = const DeferredAttemptResolutionException());
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_hasEnded || _wasInterrupted) return;
    if (shouldInterruptGame(state)) {
      _interruptAttempt();
    }
  }

  void _interruptAttempt() {
    if (_hasEnded || _wasInterrupted) return;
    _wasInterrupted = true;
    _hasEnded = true;
    _game.interrupt();
    final attempt = widget.attempt;
    if (attempt != null && !attempt.isPractice) {
      unawaited(_expireActiveAttempt());
    }
    if (mounted) setState(() {});
  }

  void _leaveGame() {
    _interruptAttempt();
    _returnHome();
  }

  void _returnHome() {
    ref.invalidate(todayStateProvider);
    context.go('/');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_hasEnded) {
      _hasEnded = true;
      _game.interrupt();
      final attempt = widget.attempt;
      if (attempt != null && !attempt.isPractice) {
        unawaited(_expireActiveAttempt());
      }
    }
    _game.disposeController();
    super.dispose();
  }

  Future<void> _expireActiveAttempt() async {
    final attempt = widget.attempt;
    if (attempt == null || attempt.isPractice) return;
    try {
      final resolver = attempt.resolveForSubmission;
      final resolved = resolver == null ? attempt : await resolver();
      if (resolved == null || resolved.isPractice) return;
      await _repository.expireAttempt(resolved.id);
    } catch (_) {
      // Expiration is best effort. The server's stale-attempt cleanup is the
      // fallback when the app is interrupted before the claim is resolved.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GameWidget(game: _game.flameGame),
          if (_definition.id == 'number_rush' &&
              !_wasInterrupted &&
              _pendingResult == null &&
              _result == null)
            _NumberRushExitButton(onExit: _leaveGame),
          if (_definition.id == 'beat_the_dealer' &&
              !_wasInterrupted &&
              _pendingResult == null &&
              _result == null)
            _BeatTheDealerExitButton(onExit: _leaveGame),
          SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _GameHud(game: _game, definition: _definition),
                if (_definition.id != 'number_rush' &&
                    _definition.id != 'beat_the_dealer')
                  Positioned(
                    left: 8,
                    top: 13,
                    child: _GameExitButton(onExit: _leaveGame),
                  ),
                if (_wasInterrupted) _InterruptedOverlay(onHome: _returnHome),
              ],
            ),
          ),
          if (_pendingResult != null || _result != null)
            GameEndTransition(
              key: const Key('game-end-scene'),
              endType: (_pendingResult ?? _result)!.endType,
              onCompleted: _revealResult,
              resultPanel: switch (_result) {
                final result? => _ResultPanel(
                  result: result,
                  definition: _definition,
                  isPractice: widget.attempt?.isPractice ?? false,
                  rankResult: _rankResult,
                  isSubmitting: _isSubmitting,
                  submitError: _submitError,
                  isSavingNickname: _isSavingNickname,
                  onChooseNickname: _chooseNickname,
                  onRetrySubmit: () => _submitResult(result),
                  onHome: _returnHome,
                ),
                null => null,
              },
            ),
        ],
      ),
    );
  }
}

class _BeatTheDealerExitButton extends StatelessWidget {
  const _BeatTheDealerExitButton({required this.onExit});

  static const _logicalSize = Size(360, 640);
  static const _touchRect = Rect.fromLTWH(4, 21, 48, 48);

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / _logicalSize.width,
          constraints.maxHeight / _logicalSize.height,
        );
        final viewportLeft =
            (constraints.maxWidth - _logicalSize.width * scale) / 2;
        final viewportTop =
            (constraints.maxHeight - _logicalSize.height * scale) / 2;

        return Stack(
          children: [
            Positioned(
              left: viewportLeft + _touchRect.left * scale,
              top: viewportTop + _touchRect.top * scale,
              width: _touchRect.width * scale,
              height: _touchRect.height * scale,
              child: Tooltip(
                message: '길게 눌러 게임 나가기',
                triggerMode: TooltipTriggerMode.tap,
                child: Semantics(
                  button: true,
                  label: '길게 눌러 게임 나가기',
                  child: GestureDetector(
                    key: const Key('game-exit-button'),
                    behavior: HitTestBehavior.opaque,
                    onLongPress: onExit,
                    child: Center(
                      child: CustomPaint(
                        key: const Key('game-exit-icon'),
                        size: Size.square(32 * scale),
                        painter: const _PixelExitIconPainter(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NumberRushExitButton extends StatefulWidget {
  const _NumberRushExitButton({required this.onExit});

  final VoidCallback onExit;

  @override
  State<_NumberRushExitButton> createState() => _NumberRushExitButtonState();
}

class _NumberRushExitButtonState extends State<_NumberRushExitButton> {
  static const _logicalSize = Size(360, 640);
  static const _touchRect = Rect.fromLTWH(30, 523, 62, 56);
  static const _assetSize = 56.0;

  var _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value || !mounted) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / _logicalSize.width,
          constraints.maxHeight / _logicalSize.height,
        );
        final viewportLeft =
            (constraints.maxWidth - _logicalSize.width * scale) / 2;
        final viewportTop =
            (constraints.maxHeight - _logicalSize.height * scale) / 2;

        return Stack(
          children: [
            Positioned(
              left: viewportLeft + _touchRect.left * scale,
              top: viewportTop + _touchRect.top * scale,
              width: _touchRect.width * scale,
              height: _touchRect.height * scale,
              child: Tooltip(
                message: '길게 눌러 게임 나가기',
                triggerMode: TooltipTriggerMode.tap,
                child: Semantics(
                  button: true,
                  label: '길게 눌러 게임 나가기',
                  child: Listener(
                    onPointerDown: (_) => _setPressed(true),
                    onPointerUp: (_) => _setPressed(false),
                    onPointerCancel: (_) => _setPressed(false),
                    child: GestureDetector(
                      key: const Key('game-exit-button'),
                      behavior: HitTestBehavior.opaque,
                      onLongPress: widget.onExit,
                      child: Center(
                        child: Image.asset(
                          _isPressed
                              ? 'assets/images/number_rush/exit_button_pressed.png'
                              : 'assets/images/number_rush/exit_button_idle.png',
                          key: const Key('number-rush-exit-image'),
                          width: _assetSize * scale,
                          height: _assetSize * scale,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GameExitButton extends StatelessWidget {
  const _GameExitButton({required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '길게 눌러 게임 나가기',
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        button: true,
        label: '길게 눌러 게임 나가기',
        child: GestureDetector(
          key: const Key('game-exit-button'),
          behavior: HitTestBehavior.opaque,
          onLongPress: onExit,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: CustomPaint(
                key: Key('game-exit-icon'),
                size: Size.square(32),
                painter: _PixelExitIconPainter(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelExitIconPainter extends CustomPainter {
  const _PixelExitIconPainter();

  static const _sourceSize = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final door = Paint()
      ..color = Colors.white
      ..isAntiAlias = false;
    final arrow = Paint()
      ..color = Colors.white
      ..isAntiAlias = false;

    const doorParts = [
      Rect.fromLTWH(8, 2, 7, 2),
      Rect.fromLTWH(13, 2, 2, 12),
      Rect.fromLTWH(8, 12, 7, 2),
      Rect.fromLTWH(8, 2, 2, 3),
      Rect.fromLTWH(8, 11, 2, 3),
    ];
    final arrowPath = Path()
      ..moveTo(1, 7)
      ..lineTo(2, 7)
      ..lineTo(2, 6)
      ..lineTo(3, 6)
      ..lineTo(3, 5)
      ..lineTo(4, 5)
      ..lineTo(4, 4)
      ..lineTo(6, 4)
      ..lineTo(6, 6)
      ..lineTo(5, 6)
      ..lineTo(5, 7)
      ..lineTo(12, 7)
      ..lineTo(12, 10)
      ..lineTo(5, 10)
      ..lineTo(5, 11)
      ..lineTo(6, 11)
      ..lineTo(6, 13)
      ..lineTo(4, 13)
      ..lineTo(4, 12)
      ..lineTo(3, 12)
      ..lineTo(3, 11)
      ..lineTo(2, 11)
      ..lineTo(2, 10)
      ..lineTo(1, 10)
      ..close();

    final scale = size.shortestSide / _sourceSize;
    final offset = Offset(
      (size.width - (_sourceSize * scale)) / 2,
      (size.height - (_sourceSize * scale)) / 2,
    );
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);

    for (final part in doorParts) {
      canvas.drawRect(part, door);
    }
    canvas
      ..drawPath(arrowPath, arrow)
      ..restore();
  }

  @override
  bool shouldRepaint(_PixelExitIconPainter oldDelegate) => false;
}

class _GameHud extends StatelessWidget {
  const _GameHud({required this.game, required this.definition});

  final MiniGameController game;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MiniGameHudState>(
      valueListenable: game.hud,
      builder: (context, state, child) {
        if (definition.hudStyle == MiniGameHudStyle.survivalTime) {
          return _SurvivalTimeHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.appleGame) {
          return _AppleGameHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.numberRush) {
          return _NumberRushHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.mamaDuckTrail) {
          return _MamaDuckTrailHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.beatTheDealer) {
          return _BeatTheDealerHud(state: state, definition: definition);
        }
        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 64,
                right: 16,
                top: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _HudValue(
                      label: 'SURVIVE',
                      value: definition.formatScore(state.score),
                    ),
                    _HudValue(
                      label: 'TIME',
                      value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                          .padLeft(2, '0'),
                      alignEnd: true,
                      isDanger:
                          state.remainingSeconds != null &&
                          state.remainingSeconds! <= 10,
                    ),
                  ],
                ),
              ),
              if (state.phase == MiniGamePhase.countdown)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.countdownNumber > 0
                            ? '${state.countdownNumber}'
                            : 'GO!',
                        style: const TextStyle(
                          fontFamily: 'Galmuri',
                          color: AppColors.primary,
                          fontSize: 68,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              color: AppColors.primaryShadow,
                              offset: Offset(5, 5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        definition.countdownInstruction,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              if (state.phase == MiniGamePhase.playing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: Text(
                    definition.playingInstruction,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BeatTheDealerHud extends StatelessWidget {
  const _BeatTheDealerHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    if (state.phase != MiniGamePhase.countdown) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.countdownNumber > 0 ? '${state.countdownNumber}' : 'GO!',
              style: const TextStyle(
                fontFamily: 'Galmuri',
                color: AppColors.primary,
                fontSize: 68,
                fontWeight: FontWeight.w700,
                shadows: [
                  Shadow(color: AppColors.primaryShadow, offset: Offset(5, 5)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              definition.countdownInstruction,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MamaDuckTrailHud extends StatelessWidget {
  const _MamaDuckTrailHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 12,
            top: 10,
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: _HudValue(
                    label: 'SURVIVE',
                    value: definition.formatHudScore(state.score),
                    valueKey: const Key('mama-hud-score'),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'LIVES',
                        key: Key('mama-hud-lives-label'),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 96,
                        height: 48,
                        child: Stack(
                          children: [
                            for (var index = 0; index < 3; index++)
                              Positioned(
                                left: index * 24,
                                child: Opacity(
                                  key: Key('mama-duck-life-$index'),
                                  opacity: index < state.distance ? 1 : 0.18,
                                  child: Image.asset(
                                    'assets/images/mama_duck_trail/'
                                    'duckling_life_face.png',
                                    width: 48,
                                    height: 48,
                                    filterQuality: FilterQuality.none,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: _HudValue(
                    label: 'TIME',
                    value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                        .padLeft(2, '0'),
                    valueKey: const Key('mama-hud-time'),
                    alignEnd: true,
                    isDanger:
                        state.remainingSeconds != null &&
                        state.remainingSeconds! <= 10,
                  ),
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.primary,
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: AppColors.primaryShadow,
                          offset: Offset(5, 5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    definition.countdownInstruction,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          if (state.phase == MiniGamePhase.playing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Text(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberRushHud extends StatelessWidget {
  const _NumberRushHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    if (state.phase != MiniGamePhase.countdown) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ColoredBox(
        color: const Color(0xB8030713),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.countdownNumber > 0 ? '${state.countdownNumber}' : 'GO!',
                style: const TextStyle(
                  fontFamily: 'Galmuri',
                  color: Color(0xFF39F3FF),
                  fontSize: 68,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(color: Color(0xFFFF3EBC), offset: Offset(5, 5)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                definition.countdownInstruction,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleGameHud extends StatelessWidget {
  const _AppleGameHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 64,
            right: 16,
            top: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _HudValue(
                  label: definition.scoreLabel,
                  value: definition.formatScore(state.score),
                  valueKey: const Key('apple-hud-score'),
                ),
                _HudValue(
                  label: 'TIME',
                  value: '${state.remainingSeconds ?? state.elapsedSeconds}'
                      .padLeft(2, '0'),
                  alignEnd: true,
                  isDanger:
                      state.remainingSeconds != null &&
                      state.remainingSeconds! <= 10,
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFFFFD24A),
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0xFF591F2C), offset: Offset(5, 5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SurvivalTimeHud extends StatelessWidget {
  const _SurvivalTimeHud({required this.state, required this.definition});

  final MiniGameHudState state;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Column(
              children: [
                const Text(
                  'TIME',
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  definition.formatHudScore(state.score),
                  key: const Key('survival-time'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Galmuri',
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Color(0x99000000), offset: Offset(3, 3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (state.phase == MiniGamePhase.countdown)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.countdownNumber > 0
                        ? '${state.countdownNumber}'
                        : 'GO!',
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFF4CF4E8),
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0xFF0B6371), offset: Offset(5, 5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    definition.countdownInstruction,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          if (state.phase == MiniGamePhase.playing && state.elapsedSeconds < 5)
            Positioned(
              left: 0,
              right: 0,
              bottom: 26,
              child: Text(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HudValue extends StatelessWidget {
  const _HudValue({
    required this.label,
    required this.value,
    this.valueKey,
    this.alignEnd = false,
    this.isDanger = false,
  });

  final String label;
  final String value;
  final Key? valueKey;
  final bool alignEnd;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          key: valueKey,
          style: TextStyle(
            fontFamily: 'Galmuri',
            color: isDanger ? AppColors.danger : AppColors.text,
            fontSize: 25,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.result,
    required this.definition,
    required this.isPractice,
    required this.rankResult,
    required this.isSubmitting,
    required this.submitError,
    required this.isSavingNickname,
    required this.onChooseNickname,
    required this.onRetrySubmit,
    required this.onHome,
  });

  final GameResult result;
  final MiniGameDefinition definition;
  final bool isPractice;
  final DailyRankResult? rankResult;
  final bool isSubmitting;
  final Object? submitError;
  final bool isSavingNickname;
  final VoidCallback onChooseNickname;
  final VoidCallback onRetrySubmit;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return PixelPanel(
      key: const Key('result-panel'),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '한 판 종료!',
            style: TextStyle(
              fontFamily: 'Galmuri',
              color: AppColors.primary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            definition.formatScore(result.score),
            key: const Key('final-score'),
            style: const TextStyle(
              fontFamily: 'Galmuri',
              color: AppColors.text,
              fontSize: 48,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            definition.scoreLabel,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          if (isPractice)
            const Text(
              '연습 모드 · 이 점수는 랭킹에 반영되지 않아요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (isSubmitting)
            const Text('오늘 순위를 계산하고 있어요...')
          else if (rankResult case final rank?)
            Column(
              children: [
                Text(
                  '${rank.rank}등 / ${rank.participants}명'
                  '${rank.participants >= 10 ? ' · 상위 ${rank.topPercent}%' : ''}',
                  key: const Key('daily-rank'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.reward,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                if (rank.nickname == null)
                  SizedBox(
                    width: double.infinity,
                    child: PixelButton(
                      label: isSavingNickname ? '저장 중...' : '닉네임 정하고 랭킹 보기',
                      icon: Icons.edit_outlined,
                      onPressed: isSavingNickname ? null : onChooseNickname,
                    ),
                  )
                else
                  NearbyRanking(
                    result: rank,
                    formatScore: definition.formatScore,
                  ),
              ],
            )
          else if (submitError != null)
            Column(
              children: [
                Text(
                  submitError is DeferredAttemptResolutionException
                      ? '광고 확인이 늦어 랭킹에 반영하지 못했어요. 잠시 후 다시 시도해 주세요.'
                      : '점수를 기기에 보관했어요. 서버가 복구되면 자동 전송됩니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
                const SizedBox(height: 12),
                PixelButton(
                  label: '지금 다시 전송',
                  icon: Icons.refresh,
                  onPressed: onRetrySubmit,
                ),
              ],
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: PixelButton(
              label: '홈으로',
              icon: Icons.home_outlined,
              onPressed: onHome,
            ),
          ),
        ],
      ),
    );
  }
}

class DeferredAttemptResolutionException implements Exception {
  const DeferredAttemptResolutionException();
}

class _InterruptedOverlay extends StatelessWidget {
  const _InterruptedOverlay({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.backgroundDeep.withValues(alpha: 0.94),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: PixelPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.phone_paused_outlined,
                    color: AppColors.primary,
                    size: 42,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '한 판이 중단됐어요',
                    key: Key('interrupted-title'),
                    style: TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.text,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '전화 수신, 홈 이동, 앱 종료 시\n공정한 순위를 위해 이번 기회가 소진됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PixelButton(
                      label: '홈으로',
                      icon: Icons.home_outlined,
                      onPressed: onHome,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool shouldInterruptGame(AppLifecycleState state) {
  return state != AppLifecycleState.resumed;
}
