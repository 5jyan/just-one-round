import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/dung_dodge_v2/domain/dung_dodge_v2_rules.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

class NearbyRanking extends ConsumerWidget {
  const NearbyRanking({
    required this.result,
    this.formatScore = DungDodgeV2Rules.formatSurvival,
    super.key,
  });

  final DailyRankResult result;
  final String Function(int score) formatScore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (result.nearby.isEmpty) return const SizedBox.shrink();
    return PixelPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    child: Text(
                      item.nickname,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    formatScore(item.score),
                    style: const TextStyle(
                      fontFamily: 'Galmuri',
                      color: AppColors.reward,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!item.isMe && !item.isNpc && item.userId != null)
                    PopupMenuButton<_NearbyModerationAction>(
                      tooltip: '사용자 신고 또는 차단',
                      onSelected: (action) =>
                          _moderate(context, ref, item, action),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _NearbyModerationAction.report,
                          child: Text('닉네임 신고'),
                        ),
                        PopupMenuItem(
                          value: _NearbyModerationAction.block,
                          child: Text('사용자 차단'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _moderate(
    BuildContext context,
    WidgetRef ref,
    NearbyRank item,
    _NearbyModerationAction action,
  ) async {
    final userId = item.userId;
    if (userId == null) return;
    try {
      final repository = ref.read(dailyGameRepositoryProvider);
      if (action == _NearbyModerationAction.report) {
        await repository.reportNickname(userId);
      } else {
        await repository.blockUser(userId);
      }
      ref.invalidate(todayStateProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == _NearbyModerationAction.report
                  ? '닉네임을 신고했어요.'
                  : '이 사용자의 닉네임을 숨겼어요.',
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('처리하지 못했어요.')));
      }
    }
  }
}

enum _NearbyModerationAction { report, block }
