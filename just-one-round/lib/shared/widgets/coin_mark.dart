import 'package:flutter/material.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

class CoinMark extends StatelessWidget {
  const CoinMark({
    required this.color,
    required this.inkColor,
    this.size = 18,
    super.key,
  });

  final Color color;
  final Color inkColor;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: inkColor, width: 1.5),
      ),
      child: Center(
        child: WordSafeText(
          'C',
          style: TextStyle(
            color: inkColor,
            fontSize: size * 0.58,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    ),
  );
}
