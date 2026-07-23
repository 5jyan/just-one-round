import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/game_registry.dart';
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
  var _isRunningDeveloperAction = false;
  var _isLoadingRank = false;
  _RankFilter _rankFilter = _RankFilter.all;
  DailyRankResult? _filteredResult;

  Future<void> _openSettings(TodayState state) async {
    final action = await showDialog<_SettingsAction>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('설정'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_SettingsAction.profile),
            child: const ListTile(
              leading: Icon(Icons.person_outline, color: AppColors.text),
              title: Text('프로필 설정'),
            ),
          ),
          if (state.testMode)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(_SettingsAction.developer),
              child: const ListTile(
                key: Key('developer-mode-menu'),
                leading: Icon(Icons.developer_mode, color: AppColors.reward),
                title: Text('개발자 모드'),
                subtitle: Text('게임 변경 및 횟수 초기화'),
              ),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _SettingsAction.profile:
        await _editProfile(state.profile);
      case _SettingsAction.developer:
        await _openDeveloperTools(state);
      case null:
        return;
    }
  }

  Future<void> _openDeveloperTools(TodayState state) async {
    setState(() => _isRunningDeveloperAction = true);
    try {
      final repository = ref.read(dailyGameRepositoryProvider);
      final games = await repository.fetchDeveloperGames();
      if (!mounted) return;
      final action = await showDialog<_DeveloperAction>(
        context: context,
        builder: (context) =>
            _DeveloperToolsDialog(games: games, currentGameId: state.game?.id),
      );
      if (action == null || !mounted) return;
      if (action.resetProgress) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('오늘 기록을 초기화할까요?'),
            content: const Text('테스트 계정의 오늘 시도와 점수만 삭제됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('초기화'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await repository.resetDeveloperDailyProgress();
      } else {
        await repository.setDeveloperGame(action.gameId!);
      }
      _rankFilter = _RankFilter.all;
      _filteredResult = null;
      ref.invalidate(todayStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action.resetProgress ? '오늘 기록을 초기화했어요.' : '테스트 게임을 변경했어요.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('개발자 기능을 실행하지 못했어요: $error')));
    } finally {
      if (mounted) setState(() => _isRunningDeveloperAction = false);
    }
  }

  Future<void> _start({required bool rewarded}) async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);
    try {
      final repository = ref.read(dailyGameRepositoryProvider);
      final attempt = rewarded
          ? await repository.claimRewardedAttempt()
          : await repository.claimDailyAttempt();
      if (!mounted) return;
      setState(() => _isClaiming = false);
      await context.push('/play', extra: attempt);
      if (!mounted) return;
      ref.invalidate(todayStateProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('시작하지 못했어요: $error')));
    } finally {
      if (mounted && _isClaiming) setState(() => _isClaiming = false);
    }
  }

  Future<void> _editProfile(UserProfile profile) async {
    var draft = await showProfileDialog(context, profile: profile);
    while (draft != null && mounted) {
      setState(() => _isSavingProfile = true);
      try {
        final repository = ref.read(dailyGameRepositoryProvider);
        await repository.setNickname(draft.nickname);
        await repository.updateDemographics(
          birthYear: draft.birthYear,
          birthMonth: draft.birthMonth,
          gender: draft.gender,
        );
        _rankFilter = _RankFilter.all;
        _filteredResult = null;
        ref.invalidate(todayStateProvider);
        if (!mounted) return;
        setState(() => _isSavingProfile = false);
        await _showProfileResultDialog(title: '저장 완료', message: '프로필이 저장됐어요.');
        return;
      } catch (error) {
        if (!mounted) return;
        setState(() => _isSavingProfile = false);
        final retryDraft = showProfileDialog(
          context,
          profile: UserProfile(
            nickname: draft.nickname,
            birthYear: draft.birthYear,
            birthMonth: draft.birthMonth,
            gender: draft.gender,
          ),
        );
        await _showProfileResultDialog(
          title: '저장 오류',
          message: _profileSaveErrorMessage(error),
        );
        draft = await retryDraft;
      }
    }
  }

  String _profileSaveErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('nickname already taken')) {
      return '이미 사용 중인 닉네임이에요. 다른 닉네임을 입력해 주세요.';
    }
    return '프로필을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
  }

  Future<void> _showProfileResultDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
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
                          isSaving:
                              _isSavingProfile || _isRunningDeveloperAction,
                          onHistory: () => context.push('/history'),
                          onSettings: () => _openSettings(state),
                        ),
                        const SizedBox(height: 32),
                        PixelPanel(
                          child: Column(
                            children: [
                              _GamePreview(gameId: state.game?.id),
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
                              _GameMeta(game: state.game),
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
                            gameId: state.game?.id,
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
    if (state.testMode) return '테스트 모드 · 제한 없이 계속 플레이할 수 있어요';
    if (state.canClaimDaily) return '아직 플레이하지 않았어요 · 기회 1회';
    if (state.adAttemptAvailable) return '첫 판 완료 · 광고로 기회 1회 추가 가능';
    if (state.hasPlayed) return '오늘의 플레이를 모두 마쳤어요';
    return '중단된 게임은 다시 시작할 수 없어요';
  }
}

enum _SettingsAction { profile, developer }

class _DeveloperAction {
  const _DeveloperAction.changeGame(this.gameId) : resetProgress = false;
  const _DeveloperAction.reset() : gameId = null, resetProgress = true;

  final String? gameId;
  final bool resetProgress;
}

class _DeveloperToolsDialog extends StatefulWidget {
  const _DeveloperToolsDialog({
    required this.games,
    required this.currentGameId,
  });

  final List<DeveloperGame> games;
  final String? currentGameId;

  @override
  State<_DeveloperToolsDialog> createState() => _DeveloperToolsDialogState();
}

class _DeveloperToolsDialogState extends State<_DeveloperToolsDialog> {
  late String? _selectedGameId =
      widget.games.any((game) => game.id == widget.currentGameId)
      ? widget.currentGameId
      : widget.games.firstOrNull?.id;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('개발자 모드'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('developer-game-dropdown'),
            initialValue: _selectedGameId,
            decoration: const InputDecoration(
              labelText: '테스트할 게임',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final game in widget.games)
                DropdownMenuItem(
                  value: game.id,
                  child: Text('${game.displayName} v${game.version}'),
                ),
            ],
            onChanged: (value) => setState(() => _selectedGameId = value),
          ),
          const SizedBox(height: 12),
          const Text(
            '게임 변경은 현재 테스트 계정에만 적용됩니다.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('reset-daily-progress'),
          onPressed: () =>
              Navigator.of(context).pop(const _DeveloperAction.reset()),
          child: const Text('게임 횟수 초기화'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(
          key: const Key('apply-developer-game'),
          onPressed: _selectedGameId == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_DeveloperAction.changeGame(_selectedGameId)),
          child: const Text('게임 적용'),
        ),
      ],
    );
  }
}

enum _RankFilter { all, age, gender }

class _RankSection extends StatelessWidget {
  const _RankSection({
    required this.result,
    required this.score,
    required this.gameId,
    required this.profile,
    required this.selectedFilter,
    required this.isLoading,
    required this.onSelect,
  });

  final DailyRankResult result;
  final int score;
  final String? gameId;
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
            if (profile.gender case final gender?)
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
                _RankValue(
                  label: gameId == 'failed_bakery' ? '최고 층수' : '최고 생존',
                  value: GameRegistry.formatScore(gameId, score),
                ),
                _RankValue(
                  label: '오늘 순위',
                  value: result.rank == null ? '-' : '${result.rank}등',
                ),
                _RankValue(label: '참가자', value: '${result.participants}명'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          NearbyRanking(
            result: result,
            formatScore: (value) => GameRegistry.formatScore(gameId, value),
          ),
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
              tooltip: '설정',
              onPressed: isSaving ? null : onSettings,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.settings_outlined, color: AppColors.text),
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
  const _GamePreview({required this.gameId});

  final String? gameId;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.backgroundDeep,
          border: Border.all(color: AppColors.surfaceLight, width: 2),
        ),
        child: switch (gameId) {
          'gravity_switch' => const _GravityGamePreview(),
          'failed_bakery' => const _FailedBakeryPreview(),
          'apple_game' => const _AppleGamePreview(),
          'number_rush' => const _NumberRushPreview(),
          _ => Stack(
            children: [
              const Positioned(left: 30, top: 24, child: _PixelStar(size: 18)),
              const Positioned(right: 38, top: 44, child: _PixelStar(size: 12)),
              Center(
                child: Image.asset(
                  'assets/images/dinosaur_side_left_1_uniform.png',
                  width: 72,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _NumberRushPreview extends StatelessWidget {
  const _NumberRushPreview();

  static const _numbers = [
    12,
    3,
    19,
    7,
    24,
    15,
    1,
    21,
    9,
    5,
    18,
    11,
    25,
    2,
    14,
    6,
    23,
    10,
    17,
    4,
    20,
    8,
    16,
    22,
    13,
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/number_rush/arcade_background.png'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE8071025),
            border: Border.all(color: const Color(0xFF7B2FB0), width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0xAAFF3EBC), blurRadius: 8),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 3,
                          crossAxisSpacing: 3,
                        ),
                    itemCount: _numbers.length,
                    itemBuilder: (context, index) {
                      final number = _numbers[index];
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A1938),
                          border: Border.all(
                            color: number == 25
                                ? const Color(0xFFFFD84A)
                                : number == 1
                                ? const Color(0xFFFF4FC3)
                                : const Color(0xFF633094),
                            width: number == 1 || number == 25 ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$number',
                            style: TextStyle(
                              fontFamily: 'Galmuri',
                              color: number == 25
                                  ? const Color(0xFFFFD84A)
                                  : const Color(0xFF5DF5FF),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'NUMBER\nRUSH',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Galmuri',
                          color: Color(0xFF39F3FF),
                          fontSize: 15,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 10),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFF071025),
                          border: Border.fromBorderSide(
                            BorderSide(color: Color(0xFFFF3EBC), width: 2),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Text(
                            '12.45',
                            style: TextStyle(
                              fontFamily: 'Galmuri',
                              color: Color(0xFFFF77CE),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppleGamePreview extends StatelessWidget {
  const _AppleGamePreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/apple_game/apple_game_background.png',
          ),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xDD24181B),
            border: Border.all(color: const Color(0xFFE6B94E), width: 3),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/images/apple_game/apple_faces_atlas.png',
              width: 116,
              height: 116,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _FailedBakeryPreview extends StatefulWidget {
  const _FailedBakeryPreview();

  @override
  State<_FailedBakeryPreview> createState() => _FailedBakeryPreviewState();
}

class _FailedBakeryPreviewState extends State<_FailedBakeryPreview> {
  late final Future<List<ui.Image>> _cakeImages;

  @override
  void initState() {
    super.initState();
    _cakeImages = Future.wait([
      _loadPreviewImage('assets/images/failed_bakery_25d/cake_top_atlas.png'),
      _loadPreviewImage(
        'assets/images/failed_bakery_25d/cake_side_face_atlas.png',
      ),
      _loadPreviewImage(
        'assets/images/failed_bakery_25d/cake_side_plain_atlas.png',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/failed_bakery_25d/bakery_background_3q.png',
          ),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: FutureBuilder<List<ui.Image>>(
        future: _cakeImages,
        builder: (context, snapshot) => CustomPaint(
          painter: snapshot.hasData
              ? _FailedBakeryPreviewPainter(
                  topAtlas: snapshot.data![0],
                  faceSideAtlas: snapshot.data![1],
                  plainSideAtlas: snapshot.data![2],
                )
              : null,
        ),
      ),
    );
  }
}

Future<ui.Image> _loadPreviewImage(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

class _FailedBakeryPreviewPainter extends CustomPainter {
  const _FailedBakeryPreviewPainter({
    required this.topAtlas,
    required this.faceSideAtlas,
    required this.plainSideAtlas,
  });

  final ui.Image topAtlas;
  final ui.Image faceSideAtlas;
  final ui.Image plainSideAtlas;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.73);
    const skins = [0, 4, 1, 3, 2];
    for (var layer = 0; layer < skins.length; layer++) {
      final width = 82.0 - layer * 3;
      final halfWidth = width / 2;
      final halfHeight = width / 4;
      final y = center.dy - layer * 8;
      final back = Offset(center.dx, y - halfHeight);
      final right = Offset(center.dx + halfWidth, y);
      final front = Offset(center.dx, y + halfHeight);
      final left = Offset(center.dx - halfWidth, y);
      _drawPreviewCakeFace(
        canvas,
        origin: left,
        horizontal: front - left,
        skin: skins[layer],
        image: faceSideAtlas,
      );
      _drawPreviewCakeFace(
        canvas,
        origin: front,
        horizontal: right - front,
        skin: skins[layer],
        image: plainSideAtlas,
      );
      final topRow = skins[layer] ~/ 3;
      final topColumn = skins[layer] % 3;
      _drawPreviewImage(
        canvas,
        image: topAtlas,
        source: Rect.fromLTWH(topColumn * 40.0, topRow * 40.0, 40, 40),
        origin: back,
        horizontal: right - back,
        vertical: left - back,
      );
    }
  }

  void _drawPreviewCakeFace(
    Canvas canvas, {
    required Offset origin,
    required Offset horizontal,
    required int skin,
    required ui.Image image,
  }) {
    final row = skin ~/ 2;
    final column = skin % 2;
    _drawPreviewImage(
      canvas,
      image: image,
      source: Rect.fromLTWH(column * 40.0, row * 8.0, 40, 8),
      origin: origin,
      horizontal: horizontal,
      vertical: const Offset(0, 8),
    );
  }

  void _drawPreviewImage(
    Canvas canvas, {
    required ui.Image image,
    required Rect source,
    required Offset origin,
    required Offset horizontal,
    required Offset vertical,
  }) {
    final matrix = Float64List.fromList([
      horizontal.dx / source.width,
      horizontal.dy / source.width,
      0,
      0,
      vertical.dx / source.height,
      vertical.dy / source.height,
      0,
      0,
      0,
      0,
      1,
      0,
      origin.dx,
      origin.dy,
      0,
      1,
    ]);
    canvas
      ..save()
      ..transform(matrix)
      ..drawImageRect(
        image,
        source,
        Rect.fromLTWH(0, 0, source.width, source.height),
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _FailedBakeryPreviewPainter oldDelegate) =>
      oldDelegate.topAtlas != topAtlas ||
      oldDelegate.faceSideAtlas != faceSideAtlas ||
      oldDelegate.plainSideAtlas != plainSideAtlas;
}

class _GravityGamePreview extends StatelessWidget {
  const _GravityGamePreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/gravity_switch_v2/space_background.png',
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            width: 56,
            height: 40,
            child: _GravityPreviewPlatform(ceiling: true),
          ),
          const Positioned(
            left: 56,
            top: 0,
            width: 56,
            height: 72,
            child: _GravityPreviewPlatform(ceiling: true),
          ),
          const Positioned(
            left: 112,
            top: 0,
            width: 56,
            height: 104,
            child: _GravityPreviewPlatform(ceiling: true),
          ),
          const Positioned(
            right: 168,
            bottom: 0,
            width: 56,
            height: 48,
            child: _GravityPreviewPlatform(),
          ),
          const Positioned(
            right: 112,
            bottom: 0,
            width: 56,
            height: 76,
            child: _GravityPreviewPlatform(),
          ),
          const Positioned(
            right: 56,
            bottom: 0,
            width: 56,
            height: 104,
            child: _GravityPreviewPlatform(),
          ),
          const Positioned(
            right: 0,
            bottom: 0,
            width: 56,
            height: 132,
            child: _GravityPreviewPlatform(),
          ),
          Positioned(
            left: 70,
            bottom: 48,
            child: SizedBox.square(
              dimension: 42,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 84,
                  maxWidth: 84,
                  minHeight: 84,
                  maxHeight: 84,
                  child: Image.asset(
                    'assets/images/gravity_switch_v2/player_sheet.png',
                    width: 84,
                    height: 84,
                    filterQuality: FilterQuality.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GravityPreviewPlatform extends StatelessWidget {
  const _GravityPreviewPlatform({this.ceiling = false});

  final bool ceiling;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              'assets/images/gravity_switch_v2/platform_fill.png',
            ),
            repeat: ImageRepeat.repeat,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: ceiling ? null : 0,
        bottom: ceiling ? 0 : null,
        height: 12,
        child: Transform.flip(
          flipY: ceiling,
          child: Image.asset(
            'assets/images/gravity_switch_v2/platform_surface.png',
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    ],
  );
}

class _PixelStar extends StatelessWidget {
  const _PixelStar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.warning_amber_rounded,
      size: size,
      color: AppColors.danger,
    );
  }
}

class _GameMeta extends StatelessWidget {
  const _GameMeta({required this.game});

  final TodayGame? game;

  @override
  Widget build(BuildContext context) {
    final durationLabel = switch (game?.id) {
      'gravity_switch' => '제한 없음',
      'failed_bakery' => '실수할 때까지',
      'apple_game' => '2분',
      'number_rush' => '최대 2분',
      _ => '${game?.durationSeconds ?? 60}초',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MetaItem(icon: Icons.timer_outlined, label: durationLabel),
        const SizedBox(width: 24),
        const _MetaItem(icon: Icons.touch_app_outlined, label: '한 손'),
        const SizedBox(width: 24),
        const _MetaItem(icon: Icons.public, label: '전체 순위'),
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
