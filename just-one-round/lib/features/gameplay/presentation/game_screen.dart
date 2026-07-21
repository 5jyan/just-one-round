import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/gameplay/domain/game_result.dart';
import 'package:just_one_round/features/games/star_dodge/star_dodge_game.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    this.gameDuration = const Duration(seconds: 60),
    this.countdownDuration = const Duration(seconds: 3),
    super.key,
  });

  final Duration gameDuration;
  final Duration countdownDuration;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final StarDodgeGame _game;
  GameResult? _result;

  @override
  void initState() {
    super.initState();
    _game = StarDodgeGame(
      gameDuration: widget.gameDuration,
      countdownDuration: widget.countdownDuration,
      onFinished: (result) {
        if (!mounted) {
          return;
        }
        setState(() => _result = result);
      },
    );
  }

  @override
  void dispose() {
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
                onPressed: () => context.go('/'),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.backgroundDeep.withValues(
                    alpha: 0.75,
                  ),
                  side: const BorderSide(color: AppColors.border, width: 2),
                ),
                icon: const Icon(Icons.close, color: AppColors.text),
              ),
            ),
            if (_result case final result?) _ResultOverlay(result: result),
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
  const _ResultOverlay({required this.result});

  final GameResult result;

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
                  const Text(
                    '랭킹 제출은 다음 서버 연결 단계에서 활성화됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PixelButton(
                      label: '홈으로',
                      icon: Icons.home_outlined,
                      onPressed: () => context.go('/'),
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
