import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/profile/presentation/profile_dialog.dart';
import 'package:just_one_round/features/ranking/presentation/nearby_ranking.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/features/today/domain/today_state.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  var _isClaiming = false;
  var _isSavingProfile = false;
  var _isLoadingRank = false;
  _RankFilter _rankFilter = _RankFilter.all;
  DailyRankResult? _filteredResult;

  Future<void> _start({required bool rewarded}) async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);
    try {
      final repository = ref.read(dailyGameRepositoryProvider);
      final attempt = rewarded
          ? await repository.claimRewardedAttempt()
          : await repository.claimDailyAttempt();
      if (!mounted) return;
      await context.push('/play', extra: attempt);
      ref.invalidate(todayStateProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('시작하지 못했어요: $error')));
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  Future<void> _editProfile(UserProfile profile) async {
    final draft = await showProfileDialog(context, profile: profile);
    if (draft == null || !mounted) return;
    setState(() => _isSavingProfile = true);
    try {
      final repository = ref.read(dailyGameRepositoryProvider);
      await repository.setNickname(draft.nickname);
      await repository.updateDemographics(
        birthDecade: draft.birthDecade,
        gender: draft.gender,
      );
      _rankFilter = _RankFilter.all;
      _filteredResult = null;
      ref.invalidate(todayStateProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('프로필을 저장하지 못했어요: $error')));
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _selectRankFilter(
    _RankFilter filter,
    UserProfile profile,
  ) async {
    if (_isLoadingRank || filter == _rankFilter) return;
    if (filter == _RankFilter.all) {
      setState(() {
        _rankFilter = filter;
        _filteredResult = null;
      });
      return;
    }
    setState(() => _isLoadingRank = true);
    try {
      final result = await ref
          .read(dailyGameRepositoryProvider)
          .fetchFilteredRank(
            birthDecade: filter == _RankFilter.age ? profile.birthDecade : null,
            gender: filter == _RankFilter.gender ? profile.gender : null,
          );
      if (!mounted) return;
      setState(() {
        _rankFilter = filter;
        _filteredResult = result;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('필터 순위를 불러오지 못했어요: $error')));
    } finally {
      if (mounted) setState(() => _isLoadingRank = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayStateProvider);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _PixelGridBackground()),
            today.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: PixelPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('서버에 연결하지 못했어요.'),
                        const SizedBox(height: 16),
                        PixelButton(
                          label: '다시 연결',
                          onPressed: () => ref.invalidate(todayStateProvider),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              data: (state) => Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          isSaving: _isSavingProfile,
                          onHistory: () => context.push('/history'),
                          onSettings: () => _editProfile(state.profile),
                        ),
                        const SizedBox(height: 32),
                        PixelPanel(
                          child: Column(
                            children: [
                              const _GamePreview(),
                              const SizedBox(height: 24),
                              Text(
                                state.game?.displayName ?? '오늘의 게임 준비 중',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                state.game?.description ?? '잠시 후 다시 확인해 주세요.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 20),
                              const _GameMeta(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (state.canClaimDaily)
                          PixelButton(
                            label: _isClaiming ? '기회 받는 중...' : '오늘의 한 판 시작',
                            icon: Icons.play_arrow_rounded,
                            onPressed: _isClaiming
                                ? null
                                : () => _start(rewarded: false),
                          )
                        else if (state.adAttemptAvailable)
                          PixelButton(
                            label: _isClaiming
                                ? '기회 받는 중...'
                                : '광고 테스트 · 한 판 더',
                            icon: Icons.ondemand_video_outlined,
                            onPressed: _isClaiming
                                ? null
                                : () => _start(rewarded: true),
                          )
                        else
                          const PixelButton(
                            label: '오늘의 플레이 완료',
                            icon: Icons.check_rounded,
                            onPressed: null,
                          ),
                        const SizedBox(height: 20),
                        Text(
                          _statusText(state),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (state.result?.score case final score?) ...[
                          const SizedBox(height: 20),
                          _RankSection(
                            result: _filteredResult ?? state.result!,
                            score: score,
                            profile: state.profile,
                            selectedFilter: _rankFilter,
                            isLoading: _isLoadingRank,
                            onSelect: (filter) =>
                                _selectRankFilter(filter, state.profile),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(TodayState state) {
    if (state.canClaimDaily) return '아직 플레이하지 않았어요 · 기회 1회';
    if (state.adAttemptAvailable) return '첫 판 완료 · 광고로 기회 1회 추가 가능';
    if (state.hasPlayed) return '오늘의 플레이를 모두 마쳤어요';
    return '중단된 게임은 다시 시작할 수 없어요';
  }
}

enum _RankFilter { all, age, gender }

class _RankSection extends StatelessWidget {
  const _RankSection({
    required this.result,
    required this.score,
    required this.profile,
    required this.selectedFilter,
    required this.isLoading,
    required this.onSelect,
  });

  final DailyRankResult result;
  final int score;
  final UserProfile profile;
  final _RankFilter selectedFilter;
  final bool isLoading;
  final ValueChanged<_RankFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('전체'),
              selected: selectedFilter == _RankFilter.all,
              onSelected: (_) => onSelect(_RankFilter.all),
            ),
            if (profile.birthDecade case final decade?)
              ChoiceChip(
                label: Text('$decade년대생'),
                selected: selectedFilter == _RankFilter.age,
                onSelected: (_) => onSelect(_RankFilter.age),
              ),
            if (profile.gender case final gender?
                when gender != ProfileGender.preferNotToSay)
              ChoiceChip(
                label: Text(gender.label),
                selected: selectedFilter == _RankFilter.gender,
                onSelected: (_) => onSelect(_RankFilter.gender),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: AppColors.primary),
          )
        else ...[
          PixelPanel(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _RankValue(label: '최고 점수', value: '$score'),
                _RankValue(
                  label: '오늘 순위',
                  value: result.rank == null ? '-' : '${result.rank}등',
                ),
                _RankValue(label: '참가자', value: '${result.participants}명'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          NearbyRanking(result: result),
        ],
      ],
    );
  }
}

class _RankValue extends StatelessWidget {
  const _RankValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onSettings,
    required this.onHistory,
    required this.isSaving,
  });

  final VoidCallback onSettings;
  final VoidCallback onHistory;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('딱한판만', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text(
                '${_monthName(DateTime.now().month)} ${DateTime.now().day} · 오늘의 게임',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '내 기록',
              onPressed: onHistory,
              icon: const Icon(Icons.history, color: AppColors.text),
            ),
            IconButton(
              tooltip: '프로필 설정',
              onPressed: isSaving ? null : onSettings,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_outline, color: AppColors.text),
            ),
          ],
        ),
      ],
    );
  }
}

String _monthName(int month) {
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return months[month - 1];
}

class _GamePreview extends StatelessWidget {
  const _GamePreview();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.backgroundDeep,
          border: Border.all(color: AppColors.surfaceLight, width: 2),
        ),
        child: const Stack(
          children: [
            Positioned(left: 30, top: 24, child: _PixelStar(size: 18)),
            Positioned(right: 38, top: 44, child: _PixelStar(size: 12)),
            Positioned(left: 84, bottom: 24, child: _PixelStar(size: 10)),
            Center(
              child: Icon(
                Icons.rocket_launch_rounded,
                color: AppColors.reward,
                size: 62,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelStar extends StatelessWidget {
  const _PixelStar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.star, size: size, color: AppColors.primary);
  }
}

class _GameMeta extends StatelessWidget {
  const _GameMeta();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MetaItem(icon: Icons.timer_outlined, label: '60초'),
        SizedBox(width: 24),
        _MetaItem(icon: Icons.touch_app_outlined, label: '한 손'),
        SizedBox(width: 24),
        _MetaItem(icon: Icons.public, label: '전체 순위'),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.reward, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PixelGridBackground extends StatelessWidget {
  const _PixelGridBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.surface.withValues(alpha: 0.28);
    const gap = 24.0;

    for (var x = 0.0; x < size.width; x += gap) {
      for (var y = 0.0; y < size.height; y += gap) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
