import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/profile/domain/nickname_color.dart';
import 'package:just_one_round/features/today/domain/level_up_reward.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

/// Holds level-up celebrations until startup and its existing modals finish.
class LevelUpCelebrationGate extends InheritedWidget {
  const LevelUpCelebrationGate({
    required this.ready,
    required super.child,
    super.key,
  });
  final bool ready;
  static bool readyOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LevelUpCelebrationGate>()
          ?.ready ??
      true;
  @override
  bool updateShouldNotify(LevelUpCelebrationGate oldWidget) =>
      ready != oldWidget.ready;
}

Future<bool?> showLevelUpRewardDialog(
  BuildContext context, {
  required LevelUpReward reward,
  required Future<void> Function() onConfirm,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => LevelUpRewardDialog(reward: reward, onConfirm: onConfirm),
);

class LevelUpRewardDialog extends StatefulWidget {
  const LevelUpRewardDialog({
    required this.reward,
    required this.onConfirm,
    super.key,
  });

  final LevelUpReward reward;
  final Future<void> Function() onConfirm;

  @override
  State<LevelUpRewardDialog> createState() => _LevelUpRewardDialogState();
}

class _LevelUpRewardDialogState extends State<LevelUpRewardDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '보상을 확인하지 못했어요. 잠시 후 다시 눌러 주세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = NicknameColors.forLevel(widget.reward.toLevel);
    final size = MediaQuery.sizeOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final compact = size.height < 680;
    final titleSize = (28 / textScaler.scale(1)).clamp(20.0, 28.0);
    final tickets = widget.reward.challengeTickets;
    return Dialog(
      key: const Key('level-up-reward-dialog'),
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: compact ? 12 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: size.height * .88,
        ),
        child: SingleChildScrollView(
          child: PixelPanel(
            padding: EdgeInsets.fromLTRB(18, compact ? 16 : 22, 18, 18),
            color: AppColors.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: compact ? 154 : 192,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      key: const Key('level-up-celebration'),
                      painter: _LevelUpCelebrationPainter(
                        progress: _controller.value,
                        accent: accent,
                      ),
                      child: Center(
                        child: Transform.scale(
                          scale:
                              0.82 +
                              Curves.easeOutBack.transform(_controller.value) *
                                  .18,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              WordSafeText(
                                'LEVEL UP',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              WordSafeText(
                                'LV.${widget.reward.toLevel}',
                                key: const Key('level-up-new-level'),
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(color: accent, blurRadius: 14),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                WordSafeText(
                  widget.reward.fromLevel == widget.reward.toLevel
                      ? '새 레벨에 도달했어요'
                      : 'LV.${widget.reward.fromLevel} → LV.${widget.reward.toLevel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: compact ? 12 : 16),
                DecoratedBox(
                  key: const Key('level-up-reward-tickets'),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .13),
                    border: Border.all(color: accent, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.confirmation_num_outlined,
                          color: accent,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: WordSafeText(
                            '도전권 +$tickets장',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: accent,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 10),
                  WordSafeText(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                SizedBox(height: compact ? 14 : 20),
                PixelButton(
                  key: const Key('level-up-reward-confirm'),
                  label: _busy ? '확인 중…' : '확인',
                  icon: _busy ? null : Icons.check,
                  onPressed: _busy ? null : _confirm,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelUpCelebrationPainter extends CustomPainter {
  const _LevelUpCelebrationPainter({
    required this.progress,
    required this.accent,
  });

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rayProgress = Curves.easeOut.transform(progress.clamp(0, 1));
    final rayPaint = Paint()
      ..color = accent.withValues(alpha: (1 - progress * .55).clamp(0, 1))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 12; i++) {
      final angle = (math.pi * 2 * i / 12) - math.pi / 2;
      final start = center + Offset(math.cos(angle), math.sin(angle)) * 44;
      final end =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (72 + 14 * rayProgress);
      canvas.drawLine(start, end, rayPaint);
    }

    final particlePaint = Paint()..color = accent.withValues(alpha: .75);
    for (var i = 0; i < 8; i++) {
      final angle = (math.pi * 2 * i / 8) + .24;
      final distance = 52 + 18 * rayProgress + (i.isEven ? 5 : 0);
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      canvas.drawRect(
        Rect.fromCenter(center: point, width: 4, height: 4),
        particlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelUpCelebrationPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}
