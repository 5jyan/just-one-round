import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/star_dodge/star_dodge_game.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({
    this.attempt,
    this.gameDuration = const Duration(seconds: 60),
    this.countdownDuration = const Duration(seconds: 3),
    super.key,
  });

  final Duration gameDuration;
  final Duration countdownDuration;
  final PlayAttempt? attempt;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  late final StarDodgeGame _game;
  late final DailyGameRepository _repository;
  GameResult? _result;
  DailyRankResult? _rankResult;
  Object? _submitError;
  var _isSubmitting = false;
  var _wasInterrupted = false;
  var _hasEnded = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(dailyGameRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _game = StarDodgeGame(
      gameDuration: widget.gameDuration,
      countdownDuration: widget.countdownDuration,
      onFinished: (result) {
        if (!mounted) {
          return;
        }
        setState(() {
          _result = result;
          _hasEnded = true;
        });
        unawaited(_submitResult(result));
      },
    );
  }

  Future<void> _submitResult(GameResult result) async {
    final attempt = widget.attempt;
    if (attempt == null) return;
    setState(() => _isSubmitting = true);
    try {
      final rank = await _repository.submitScore(attempt.id, result);
      if (!mounted) return;
      setState(() => _rankResult = rank);
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
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
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
    _returnHome(context);
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
    _game.hud.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GameWidget(game: _game),
            _GameHud(game: _game),
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
            if (_wasInterrupted) const _InterruptedOverlay(),
            if (_result case final result?)
              _ResultOverlay(
                result: result,
                rankResult: _rankResult,
                isSubmitting: _isSubmitting,
                submitError: _submitError,
              ),
          ],
        ),
      ),
    );
  }
}

class _GameHud extends StatelessWidget {
  const _GameHud({required this.game});

  final StarDodgeGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StarDodgeHudState>(
      valueListenable: game.hud,
      builder: (context, state, child) {
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
                    _HudValue(label: 'SCORE', value: '${state.score}'),
                    _HudValue(
                      label: 'TIME',
                      value: '${state.remainingSeconds}'.padLeft(2, '0'),
                      alignEnd: true,
                      isDanger: state.remainingSeconds <= 10,
                    ),
                  ],
                ),
              ),
              if (state.phase == StarDodgePhase.countdown)
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
                      const Text(
                        '화면을 좌우로 드래그하세요',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              if (state.phase == StarDodgePhase.playing)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: Text(
                    '★ ${state.starsCollected}   ·   충돌 ${state.collisions}',
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

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({
    required this.result,
    required this.rankResult,
    required this.isSubmitting,
    required this.submitError,
  });

  final GameResult result;
  final DailyRankResult? rankResult;
  final bool isSubmitting;
  final Object? submitError;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.backgroundDeep.withValues(alpha: 0.88),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: PixelPanel(
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
                    '${result.score}',
                    key: const Key('final-score'),
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.text,
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'FINAL SCORE',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ResultStat(
                        label: '모은 별',
                        value: '${result.starsCollected}',
                      ),
                      _ResultStat(label: '충돌', value: '${result.collisions}'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (isSubmitting)
                    const Text('오늘 순위를 계산하고 있어요...')
                  else if (rankResult case final rank?)
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
                    )
                  else if (submitError != null)
                    const Text(
                      '점수 제출에 실패했어요. 홈에서 기록을 확인해 주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PixelButton(
                      label: '홈으로',
                      icon: Icons.home_outlined,
                      onPressed: () => _returnHome(context),
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

class _InterruptedOverlay extends StatelessWidget {
  const _InterruptedOverlay();

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
                      onPressed: () => _returnHome(context),
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

void _returnHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
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
