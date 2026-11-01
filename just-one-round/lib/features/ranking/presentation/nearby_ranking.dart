import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/domain/dung_dodge_v2_rules.dart';
import 'package:just_one_round/features/profile/domain/nickname_color.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

class NearbyRanking extends StatelessWidget {
  const NearbyRanking({
    required this.result,
    this.formatScore = DungDodgeV2Rules.formatSurvival,
    super.key,
  });

  final DailyRankResult result;
  final String Function(int score) formatScore;

  @override
  Widget build(BuildContext context) {
    if (result.nearby.isEmpty) return const SizedBox.shrink();
    return PixelPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WordSafeText(
            '내 주변 랭킹',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in result.nearby)
            Container(
              key: item.isMe ? const Key('my-nearby-rank') : null,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              color: item.isMe
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.backgroundDeep,
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: WordSafeText(
                      '${item.rank}등',
                      style: TextStyle(
                        color: item.isMe
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: WordSafeText(
                      item.nickname,
                      style: TextStyle(
                        color: NicknameColors.forLevel(item.level),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  WordSafeText(
                    formatScore(item.score),
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.reward,
                      fontWeight: FontWeight.w700,
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
