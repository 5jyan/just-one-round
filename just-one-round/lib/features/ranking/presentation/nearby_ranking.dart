import 'package:flutter/material.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/star_dodge/domain/star_dodge_rules.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

class NearbyRanking extends StatelessWidget {
  const NearbyRanking({required this.result, super.key});

  final DailyRankResult result;

  @override
  Widget build(BuildContext context) {
    if (result.nearby.isEmpty) return const SizedBox.shrink();
    return PixelPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          const Text(
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
                    child: Text(
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
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.nickname,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (item.isNpc) ...[
                          const SizedBox(width: 5),
                          Container(
                            key: const Key('npc-rank-badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.textMuted),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'NPC',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    StarDodgeRules.formatSurvival(item.score),
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
