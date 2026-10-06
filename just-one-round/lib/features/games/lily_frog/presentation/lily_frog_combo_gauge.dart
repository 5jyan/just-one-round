import 'package:flutter/material.dart';

class LilyFrogComboGauge extends StatelessWidget {
  const LilyFrogComboGauge({
    required this.remainingPercent,
    required this.combo,
    this.compact = false,
    super.key,
  });

  final int remainingPercent;
  final int combo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final urgent = remainingPercent <= 15;
    final accent = combo >= 71
        ? const Color(0xFFB878FF)
        : combo >= 41
        ? const Color(0xFFFF4ECA)
        : combo >= 21
        ? const Color(0xFFFF853F)
        : combo >= 11
        ? const Color(0xFFFFCF45)
        : const Color(0xFF54EFFF);
    return Semantics(
      label: '콤보 기회 $remainingPercent% 남음',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 70),
        opacity: urgent && (remainingPercent ~/ 2).isOdd ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            key: const Key('lily-frog-combo-track'),
            width: compact ? 66 : 82,
            height: compact ? 9 : 11,
            decoration: BoxDecoration(
              color: const Color(0xFF102332),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: LinearProgressIndicator(
              value: remainingPercent / 100,
              color: accent,
              backgroundColor: Colors.transparent,
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
      ),
    );
  }
}
