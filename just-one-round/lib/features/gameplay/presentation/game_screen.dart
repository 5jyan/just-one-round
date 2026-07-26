import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/gameplay/presentation/game_end_transition.dart';
import 'package:just_one_round/features/games/domain/mini_game.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/games/gravity_switch/domain/gravity_switch_rules.dart';
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
    _game = _definition.create(
      gameDuration: widget.gameDuration ?? _definition.defaultDuration,
      countdownDuration: widget.countdownDuration,
      onFinished: _handleFinished,
    );
  }

  void _handleFinished(GameResult result) {
    if (!mounted || _hasEnded) return;
    setState(() {
      _pendingResult = result;
      _hasEnded = true;
    });
    unawaited(_submitResult(result));
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
      final rank = await _repository.fetchDailyRank();
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
    final attempt = widget.attempt;
    if (attempt == null) return;
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
    if (attempt != null) {
      unawaited(_repository.expireAttempt(attempt.id).catchError((_) {}));
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
      if (attempt != null) {
        unawaited(_repository.expireAttempt(attempt.id).catchError((_) {}));
      }
    }
    _game.disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GameWidget(game: _game.flameGame),
          SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _GameHud(game: _game, definition: _definition),
                Positioned(
                  left: 8,
                  top: 8,
                  child: IconButton(
                    tooltip: '게임 나가기',
                    onPressed: _leaveGame,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.backgroundDeep.withValues(
                        alpha: 0.75,
                      ),
                      side: const BorderSide(color: AppColors.border, width: 2),
                    ),
                    icon: const Icon(Icons.close, color: AppColors.text),
                  ),
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

class _GameHud extends StatelessWidget {
  const _GameHud({required this.game, required this.definition});

  final MiniGameController game;
  final MiniGameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MiniGameHudState>(
      valueListenable: game.hud,
      builder: (context, state, child) {
        if (definition.hudStyle == MiniGameHudStyle.gravitySwitch) {
          return _GravitySwitchHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.failedBakery) {
          return _FailedBakeryHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.appleGame) {
          return _AppleGameHud(state: state, definition: definition);
        }
        if (definition.hudStyle == MiniGameHudStyle.numberRush) {
          return _NumberRushHud(state: state, definition: definition);
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

class _FailedBakeryHud extends StatelessWidget {
  const _FailedBakeryHud({required this.state, required this.definition});

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
            top: 16,
            child: Column(
              children: [
                Text(
                  definition.formatScore(state.score),
                  key: const Key('failed-bakery-score'),
                  style: const TextStyle(
                    fontFamily: 'Galmuri',
                    color: Color(0xFFFFF0C7),
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Color(0xB0120B1C), offset: Offset(3, 3)),
                    ],
                  ),
                ),
                if (state.combo >= 2)
                  Text(
                    'PERFECT ×${state.combo}',
                    key: const Key('failed-bakery-combo'),
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: Color(0xFFFF91A8),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
                      color: Color(0xFFFFD36A),
                      fontSize: 68,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0xFF7D3B3E), offset: Offset(5, 5)),
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
          if (state.phase == MiniGamePhase.playing && state.elapsedSeconds < 6)
            Positioned(
              left: 20,
              right: 20,
              bottom: 22,
              child: Text(
                definition.playingInstruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xDDFFF4D6),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GravitySwitchHud extends StatelessWidget {
  const _GravitySwitchHud({required this.state, required this.definition});

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
            top: 18,
            child: Text(
              GravitySwitchRules.formatHudTime(state.score),
              key: const Key('gravity-survival-time'),
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
    this.alignEnd = false,
    this.isDanger = false,
  });

  final String label;
  final String value;
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
          _ResultStat(label: '기록 단위', value: definition.resultUnitLabel),
          const SizedBox(height: 24),
          if (isSubmitting)
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
                const Text(
                  '점수를 기기에 보관했어요. 서버가 복구되면 자동 전송됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
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

class _ResultStat extends StatelessWidget {
  const _ResultStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: AppColors.reward,
            fontSize: 23,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
