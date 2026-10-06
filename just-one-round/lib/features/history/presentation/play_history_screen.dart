import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/history/domain/play_history_statistics.dart';
import 'package:just_one_round/features/history/presentation/recent_percentile_chart.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/daily_reset.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

class PlayHistoryScreen extends ConsumerWidget {
  const PlayHistoryScreen({this.referencePlayDate, super.key});

  final DateTime? referencePlayDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '뒤로',
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.text),
                  ),
                  const SizedBox(width: 8),
                  WordSafeText(
                    '내 기록',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<PlayHistoryEntry>>(
                future: ref.read(dailyGameRepositoryProvider).fetchHistory(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: WordSafeText('기록을 불러오지 못했어요.\n${snapshot.error}'),
                    );
                  }
                  final history = snapshot.data ?? const [];
                  if (history.isEmpty) {
                    return const Center(
                      child: WordSafeText(
                        '아직 완료한 게임이 없어요.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  final anchor =
                      referencePlayDate ?? dailyPlayDateAt(DateTime.now());
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                    itemCount: history.length + 2,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) return _StatsOverview(history: history);
                      if (index == 1) {
                        return RecentPercentileChart(
                          history: history,
                          referencePlayDate: anchor,
                        );
                      }
                      return _HistoryCard(entry: history[index - 2]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsOverview extends StatelessWidget {
  const _StatsOverview({required this.history});
  final List<PlayHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final uniqueDays = history
        .map((entry) => DateUtils.dateOnly(entry.playDate))
        .toSet()
        .length;
    final wins = history.where((entry) => entry.rank == 1).length;
    final bestRank = history
        .map((entry) => entry.rank)
        .reduce((a, b) => a < b ? a : b);
    final averageTop = averageTopPercent(history);
    return PixelPanel(
      key: const Key('personal-stats-overview'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WordSafeText(
            '개인 기록 통계',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatMetric(value: '$uniqueDays일', label: '참여일'),
              _StatMetric(value: '$wins회', label: '1위'),
              _StatMetric(value: '$bestRank등', label: '최고 순위'),
              _StatMetric(
                value: averageTop == null ? '-' : '상위 $averageTop%',
                label: '평균 성적',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatMetric extends StatelessWidget {
  const _StatMetric({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        WordSafeText(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.reward,
            fontFamily: 'Galmuri',
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        WordSafeText(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
      ],
    ),
  );
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final PlayHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final date =
        '${entry.playDate.year}.'
        '${entry.playDate.month.toString().padLeft(2, '0')}.'
        '${entry.playDate.day.toString().padLeft(2, '0')}';
    return PixelPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WordSafeText(
                  date,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                WordSafeText(
                  entry.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                WordSafeText(
                  '${entry.rank}등 / ${entry.participants}명',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          WordSafeText(
            GameRegistry.formatScore(entry.gameId, entry.score),
            style: const TextStyle(
              fontFamily: 'Galmuri',
              color: AppColors.reward,
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
