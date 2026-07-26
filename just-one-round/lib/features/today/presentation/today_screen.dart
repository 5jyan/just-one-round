import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/profile/presentation/profile_dialog.dart';
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
  Timer? _settingsTapWindowTimer;
  Timer? _settingsOpenTimer;
  var _settingsTapCount = 0;

  @override
  void dispose() {
    _settingsTapWindowTimer?.cancel();
    _settingsOpenTimer?.cancel();
    super.dispose();
  }

  void _handleSettingsTap(TodayState state) {
    if (_isSavingProfile || _isRunningDeveloperAction) return;
    _settingsTapCount++;
    _settingsTapWindowTimer ??= Timer(
      const Duration(seconds: 5),
      _resetSettingsTapSequence,
    );
    _settingsOpenTimer?.cancel();

    if (_settingsTapCount >= 10) {
      _resetSettingsTapSequence();
      _enableTestMode();
      return;
    }

    _settingsOpenTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _resetSettingsTapSequence();
      _openSettings(state);
    });
  }

  void _resetSettingsTapSequence() {
    _settingsTapWindowTimer?.cancel();
    _settingsOpenTimer?.cancel();
    _settingsTapWindowTimer = null;
    _settingsOpenTimer = null;
    _settingsTapCount = 0;
  }

  Future<void> _enableTestMode() async {
    setState(() => _isRunningDeveloperAction = true);
    try {
      await ref.read(dailyGameRepositoryProvider).enableTestMode();
      ref.invalidate(todayStateProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('테스터 계정이 활성화됐어요.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('테스터 계정을 활성화하지 못했어요: $error')));
    } finally {
      if (mounted) setState(() => _isRunningDeveloperAction = false);
    }
  }

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

  Future<void> _showGuide(TodayState state) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GameGuideSheet(game: state.game),
    );
  }

  Future<void> _showRanking(TodayState state) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RankingSheet(
        initialResult:
            state.result ??
            const DailyRankResult(
              score: null,
              rank: null,
              participants: 0,
              topPercent: null,
              nickname: null,
              nearby: [],
            ),
        gameId: state.game?.id,
      ),
    );
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
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          isSaving:
                              _isSavingProfile || _isRunningDeveloperAction,
                          onHistory: () => context.push('/history'),
                          onSettings: () => _handleSettingsTap(state),
                        ),
                        const SizedBox(height: 12),
                        _GamePreview(gameId: state.game?.id),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                state.game?.displayName ?? '오늘의 게임 준비 중',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            if (state.testMode)
                              const _StatusBadge(label: 'TEST MODE'),
                          ],
                        ),
                        const SizedBox(height: 9),
                        _TodaySummary(
                          gameId: state.game?.id,
                          result: state.result,
                        ),
                        if (state.result?.score case final score?) ...[
                          const SizedBox(height: 10),
                          Text(
                            '내 기록 ${GameRegistry.formatScore(state.game?.id, score)}'
                            '${state.result?.rank == null ? '' : ' · ${state.result!.rank}등'}',
                            style: const TextStyle(
                              color: AppColors.reward,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _HomeActionButton(
                                key: const Key('game-guide-button'),
                                label: '게임 설명',
                                icon: Icons.menu_book_outlined,
                                onPressed: () => _showGuide(state),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _HomeActionButton(
                                key: const Key('ranking-button'),
                                label: '오늘의 랭킹',
                                icon: Icons.emoji_events_outlined,
                                onPressed: () => _showRanking(state),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (state.canClaimDaily)
                          PixelButton(
                            label: _isClaiming
                                ? '기회 받는 중...'
                                : state.testMode
                                ? '오늘의 한 판 시작'
                                : '오늘의 한 판 시작 · 1회 남음',
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
                        const SizedBox(height: 14),
                        Text(
                          _statusText(state),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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

class _RankingSheet extends StatelessWidget {
  const _RankingSheet({required this.initialResult, required this.gameId});

  final DailyRankResult initialResult;
  final String? gameId;

  @override
  Widget build(BuildContext context) {
    final result = initialResult;
    final rankingItems = _mergeRankingEntries(
      leaders: result.leaders,
      nearby: result.nearby,
      participants: result.participants,
    );
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(
            eyebrow: 'DAILY LEADERBOARD',
            title: '오늘의 랭킹',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _RankSummaryValue(
                  value: '${result.participants}명',
                  label: '오늘 도전자',
                ),
              ),
              Container(width: 1, height: 42, color: AppColors.surfaceLight),
              Expanded(
                child: _RankSummaryValue(
                  value: result.bestScore == null
                      ? '-'
                      : GameRegistry.formatScore(gameId, result.bestScore!),
                  label: '현재 최고',
                ),
              ),
              if (result.rank case final rank?) ...[
                Container(width: 1, height: 42, color: AppColors.surfaceLight),
                Expanded(
                  child: _RankSummaryValue(value: '$rank등', label: '내 순위'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const _RankingSectionTitle(eyebrow: 'ALL PLAYERS', title: '전체 랭킹'),
          const SizedBox(height: 10),
          Expanded(
            child: rankingItems.isEmpty
                ? const Center(
                    child: Text(
                      '아직 등록된 기록이 없어요.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView(
                    key: const Key('overall-leaderboard'),
                    children: [
                      for (
                        var index = 0;
                        index < rankingItems.length;
                        index++
                      ) ...[
                        if (rankingItems[index].entry == null)
                          const _LeaderboardGapRow()
                        else
                          _LeaderboardRow(
                            entry: rankingItems[index].entry!,
                            gameId: gameId,
                          ),
                        if (index < rankingItems.length - 1)
                          const SizedBox(height: 6),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

List<_LeaderboardListItem> _mergeRankingEntries({
  required List<NearbyRank> leaders,
  required List<NearbyRank> nearby,
  required int participants,
}) {
  const targetEntryCount = 8;
  final sortedLeaders = [...leaders]..sort((a, b) => a.rank.compareTo(b.rank));
  final entriesByRank = <int, NearbyRank>{};

  void addEntry(NearbyRank entry) {
    final existing = entriesByRank[entry.rank];
    if (existing == null || entry.isMe) {
      entriesByRank[entry.rank] = entry;
    }
  }

  for (final entry in sortedLeaders.take(5)) {
    addEntry(entry);
  }
  for (final entry in nearby) {
    addEntry(entry);
  }
  for (final entry in sortedLeaders) {
    if (entriesByRank.length >= targetEntryCount) break;
    addEntry(entry);
  }

  final entries = entriesByRank.values.toList()
    ..sort((a, b) => a.rank.compareTo(b.rank));
  if (entries.isEmpty) return const [];

  final items = <_LeaderboardListItem>[];
  var previousRank = 0;
  for (final entry in entries) {
    if (entry.rank > previousRank + 1) {
      items.add(const _LeaderboardListItem.gap());
    }
    items.add(_LeaderboardListItem.entry(entry));
    previousRank = entry.rank;
  }
  if (previousRank < participants) {
    items.add(const _LeaderboardListItem.gap());
  }
  return items;
}

class _LeaderboardListItem {
  const _LeaderboardListItem.entry(this.entry);
  const _LeaderboardListItem.gap() : entry = null;

  final NearbyRank? entry;
}

class _LeaderboardGapRow extends StatelessWidget {
  const _LeaderboardGapRow();

  @override
  Widget build(BuildContext context) => const SizedBox(
    key: Key('leaderboard-gap'),
    height: 22,
    child: Center(
      child: Text(
        '•••',
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
    ),
  );
}

class _RankingSectionTitle extends StatelessWidget {
  const _RankingSectionTitle({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Galmuri',
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      Text(
        eyebrow,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    ],
  );
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.gameId});

  final NearbyRank entry;
  final String? gameId;

  @override
  Widget build(BuildContext context) {
    final accent = switch (entry.rank) {
      1 => AppColors.primary,
      2 => AppColors.border,
      3 => AppColors.primaryShadow,
      _ => AppColors.textMuted,
    };
    return Container(
      key: entry.isMe ? const Key('my-leaderboard-rank') : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: entry.isMe
            ? AppColors.primary.withValues(alpha: 0.16)
            : AppColors.backgroundDeep,
        border: Border.all(
          color: entry.isMe ? AppColors.primary : AppColors.surfaceLight,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontFamily: 'Galmuri',
                color: accent,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.nickname,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (entry.isMe) ...[
                  const SizedBox(width: 7),
                  Container(
                    key: const Key('my-rank-badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    color: AppColors.primary,
                    child: const Text(
                      '나',
                      style: TextStyle(
                        color: AppColors.backgroundDeep,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            GameRegistry.formatScore(gameId, entry.score),
            style: const TextStyle(
              fontFamily: 'Galmuri',
              color: AppColors.reward,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankSummaryValue extends StatelessWidget {
  const _RankSummaryValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'Galmuri',
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
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

class _GameGuideSheet extends StatefulWidget {
  const _GameGuideSheet({required this.game});

  final TodayGame? game;

  @override
  State<_GameGuideSheet> createState() => _GameGuideSheetState();
}

class _GameGuideSheetState extends State<_GameGuideSheet> {
  late final PageController _pageController;
  var _pageIndex = 0;

  List<_GuidePageData> get _pages => widget.game?.id == 'dung_dodge_v2'
      ? const [
          _GuidePageData(
            step: '01',
            title: '누른 채로 좌우로 드래그',
            description:
                '화면의 아무 곳이나 손가락으로 누른 뒤, 떼지 않고 왼쪽이나 오른쪽으로 밀어보세요. '
                '캐릭터는 손가락을 움직인 거리만큼 따라갑니다.',
            detail:
                '가볍게 터치만 하면 움직이지 않아요. 손가락을 뗀 뒤 다른 곳에서 다시 드래그해도 바로 이어서 움직일 수 있어요.',
            visual: _GuideVisualKind.swipe,
          ),
          _GuidePageData(
            step: '02',
            title: '떨어지는 똥 사이로 피하기',
            description: '화면 위에서 떨어지는 똥의 위치를 먼저 보고, 빈 공간을 향해 짧고 정확하게 움직이세요.',
            detail: '한 방향으로 계속 달리기보다 가까운 안전지대로 조금씩 이동하면 다음 장애물에 대응하기 쉬워요.',
            visual: _GuideVisualKind.gameplay,
          ),
          _GuidePageData(
            step: '03',
            title: '시간이 갈수록 더 어려워져요',
            description:
                '처음에는 천천히 떨어지지만, 생존 시간이 길어질수록 똥이 더 자주 나타나고 낙하 속도도 빨라집니다.',
            detail:
                '후반에는 화면 전체를 한 번에 보고 미리 움직여야 해요. 눈앞의 한 개만 따라가면 퇴로가 막힐 수 있습니다.',
            visual: _GuideVisualKind.difficulty,
          ),
          _GuidePageData(
            step: '04',
            title: '한 번 부딪히면 즉시 종료',
            description: '캐릭터에게 똥이 닿는 순간 그 판은 끝나고, 그때까지 살아남은 시간이 기록됩니다.',
            detail: '게임 도중 홈으로 이동하거나 앱을 종료해도 기회가 소진되니, 시작하기 전에 집중할 시간을 확보하세요.',
            visual: _GuideVisualKind.collision,
          ),
          _GuidePageData(
            step: '05',
            title: '최대한 오래 살아남으세요',
            description: '최대 5분 동안 버틸 수 있습니다. 생존 시간이 길수록 오늘의 랭킹이 올라갑니다.',
            detail: '기록은 0.01초 단위로 비교돼요. 마지막까지 침착하게 빈 공간을 찾는 것이 최고 기록의 핵심입니다.',
            visual: _GuideVisualKind.survival,
          ),
        ]
      : [
          _GuidePageData(
            step: '01',
            title: widget.game?.displayName ?? '오늘의 게임',
            description: widget.game?.description ?? '게임 설명을 준비하고 있어요.',
            detail: '',
            visual: _GuideVisualKind.generic,
          ),
        ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_pageIndex == _pages.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetHeader(
            eyebrow: 'HOW TO PLAY · ${_pageIndex + 1}/${pages.length}',
            title: '게임 설명',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PageView.builder(
              key: const Key('game-guide-pages'),
              controller: _pageController,
              itemCount: pages.length,
              onPageChanged: (value) => setState(() => _pageIndex = value),
              itemBuilder: (context, index) => _GuidePage(page: pages[index]),
            ),
          ),
          if (pages.length == 1) ...[
            const SizedBox(height: 10),
            _GuideNotice(game: widget.game),
          ],
          const SizedBox(height: 12),
          if (pages.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < pages.length; index++)
                  AnimatedContainer(
                    key: Key('guide-page-dot-$index'),
                    duration: const Duration(milliseconds: 180),
                    width: index == _pageIndex ? 22 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    color: index == _pageIndex
                        ? AppColors.primary
                        : AppColors.surfaceLight,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    key: const Key('guide-previous-button'),
                    onPressed: _pageIndex == 0
                        ? null
                        : () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                          ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: AppColors.text,
                      disabledForegroundColor: AppColors.textMuted,
                      side: BorderSide(
                        color: _pageIndex == 0
                            ? AppColors.surfaceLight
                            : AppColors.border,
                        width: 2,
                      ),
                      shape: const RoundedRectangleBorder(),
                      textStyle: const TextStyle(
                        fontFamily: 'Galmuri',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('이전'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PixelButton(
                  key: const Key('guide-next-button'),
                  label: _pageIndex == pages.length - 1 ? '설명 끝' : '다음',
                  icon: _pageIndex == pages.length - 1
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _GuideVisualKind {
  swipe,
  gameplay,
  difficulty,
  collision,
  survival,
  generic,
}

class _GuidePageData {
  const _GuidePageData({
    required this.step,
    required this.title,
    required this.description,
    required this.detail,
    required this.visual,
  });

  final String step;
  final String title;
  final String description;
  final String detail;
  final _GuideVisualKind visual;
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({required this.page});

  final _GuidePageData page;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 268,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.backgroundDeep,
              border: Border.all(color: AppColors.surfaceLight, width: 2),
            ),
            child: ClipRect(child: _GuideVisual(kind: page.visual)),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          page.step,
          style: const TextStyle(
            color: AppColors.primary,
            fontFamily: 'Galmuri',
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          page.title,
          style: const TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          page.description,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
        if (page.detail.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.primary.withValues(alpha: 0.1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    page.detail,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _GuideVisual extends StatelessWidget {
  const _GuideVisual({required this.kind});

  final _GuideVisualKind kind;

  @override
  Widget build(BuildContext context) => switch (kind) {
    _GuideVisualKind.swipe => const _SwipeGuideVisual(),
    _GuideVisualKind.gameplay => const _GameplayGuideVisual(),
    _GuideVisualKind.difficulty => const _DifficultyGuideVisual(),
    _GuideVisualKind.collision => const _CollisionGuideVisual(),
    _GuideVisualKind.survival => const _SurvivalGuideVisual(),
    _GuideVisualKind.generic => const Center(
      child: Icon(
        Icons.sports_esports_outlined,
        color: AppColors.reward,
        size: 72,
      ),
    ),
  };
}

class _SwipeGuideVisual extends StatelessWidget {
  const _SwipeGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.72),
        filterQuality: FilterQuality.none,
      ),
      const Positioned(
        bottom: 40,
        left: 0,
        right: 0,
        child: Center(
          child: _AtlasPreviewFrame(
            assetPath: 'assets/images/dung_dodge_v2/player_run_sheet.png',
            frameSize: 82,
          ),
        ),
      ),
      Positioned(
        left: 34,
        right: 34,
        bottom: 22,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(
              Icons.keyboard_double_arrow_left_rounded,
              color: AppColors.primary,
              size: 38,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              color: AppColors.backgroundDeep.withValues(alpha: 0.8),
              child: const Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    color: AppColors.text,
                    size: 22,
                  ),
                  SizedBox(width: 5),
                  Text(
                    '누르고 드래그',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_double_arrow_right_rounded,
              color: AppColors.primary,
              size: 38,
            ),
          ],
        ),
      ),
    ],
  );
}

class _GameplayGuideVisual extends StatelessWidget {
  const _GameplayGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/home_gameplay_hero.png',
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        filterQuality: FilterQuality.none,
      ),
      const Positioned(left: 10, top: 10, child: _VisualLabel(label: '인게임 화면')),
    ],
  );
}

class _DifficultyGuideVisual extends StatelessWidget {
  const _DifficultyGuideVisual();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: _DifficultyLane(
          label: '초반',
          color: AppColors.reward,
          poopPositions: [Alignment(0.35, -0.45), Alignment(-0.55, 0.05)],
        ),
      ),
      Container(width: 2, color: AppColors.border),
      const Expanded(
        child: _DifficultyLane(
          label: '후반',
          color: AppColors.danger,
          poopPositions: [
            Alignment(-0.65, -0.75),
            Alignment(0.45, -0.55),
            Alignment(-0.1, -0.15),
            Alignment(0.7, 0.08),
            Alignment(-0.7, 0.38),
            Alignment(0.08, 0.62),
          ],
        ),
      ),
    ],
  );
}

class _DifficultyLane extends StatelessWidget {
  const _DifficultyLane({
    required this.label,
    required this.color,
    required this.poopPositions,
  });

  final String label;
  final Color color;
  final List<Alignment> poopPositions;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.55),
        filterQuality: FilterQuality.none,
      ),
      for (final position in poopPositions)
        Align(
          alignment: position,
          child: const _AtlasPreviewFrame(
            assetPath: 'assets/images/dung_dodge_v2/poop_fall_sheet.png',
            frameSize: 35,
          ),
        ),
      Positioned(
        left: 8,
        top: 8,
        child: _VisualLabel(label: label, color: color),
      ),
    ],
  );
}

class _CollisionGuideVisual extends StatelessWidget {
  const _CollisionGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/background_map.png',
        fit: BoxFit.cover,
        alignment: const Alignment(0, 0.75),
        filterQuality: FilterQuality.none,
      ),
      const Positioned(
        bottom: 36,
        left: 92,
        child: _AtlasPreviewFrame(
          assetPath: 'assets/images/dung_dodge_v2/player_idle_sheet.png',
          frameSize: 86,
        ),
      ),
      const Positioned(
        bottom: 116,
        left: 111,
        child: _AtlasPreviewFrame(
          assetPath: 'assets/images/dung_dodge_v2/poop_fall_sheet.png',
          frameSize: 48,
        ),
      ),
      Positioned(
        right: 16,
        top: 18,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          color: AppColors.danger.withValues(alpha: 0.92),
          child: const Text(
            '한 번 충돌 = 종료',
            style: TextStyle(
              color: AppColors.backgroundDeep,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    ],
  );
}

class _SurvivalGuideVisual extends StatelessWidget {
  const _SurvivalGuideVisual();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/dung_dodge_v2/home_gameplay_hero.png',
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        color: AppColors.backgroundDeep.withValues(alpha: 0.35),
        colorBlendMode: BlendMode.srcOver,
        filterQuality: FilterQuality.none,
      ),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          color: AppColors.backgroundDeep.withValues(alpha: 0.88),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: AppColors.primary,
                size: 34,
              ),
              SizedBox(height: 8),
              Text(
                '최대 5:00',
                style: TextStyle(
                  fontFamily: 'Galmuri',
                  color: AppColors.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 5),
              Text(
                '0.01초 단위로 랭킹 경쟁',
                style: TextStyle(
                  color: AppColors.reward,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _VisualLabel extends StatelessWidget {
  const _VisualLabel({required this.label, this.color = AppColors.primary});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    color: AppColors.backgroundDeep.withValues(alpha: 0.86),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
}

class _GuideNotice extends StatelessWidget {
  const _GuideNotice({required this.game});

  final TodayGame? game;

  @override
  Widget build(BuildContext context) {
    final durationText = game?.id == 'gravity_switch'
        ? '시간 제한 없이 도전할 수 있어요.'
        : '${_durationLabel(game)} 동안 도전할 수 있어요.';
    return Container(
      padding: const EdgeInsets.all(14),
      color: AppColors.primary.withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$durationText 게임 중 홈 이동이나 앱 종료 시 이번 기회가 소진됩니다.',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: SafeArea(top: false, child: child),
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.eyebrow,
    required this.title,
    required this.onClose,
  });

  final String eyebrow;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 44,
        height: 4,
        color: AppColors.border.withValues(alpha: 0.6),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppColors.text),
          ),
        ],
      ),
    ],
  );
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.gameId, required this.result});

  final String? gameId;
  final DailyRankResult? result;

  @override
  Widget build(BuildContext context) {
    final participants = result?.participants ?? 0;
    final bestScore = result?.bestScore;
    final challengeText = participants == 0
        ? '오늘 첫 기록에 도전해 보세요'
        : '오늘 $participants명 도전 중';
    final bestText = bestScore == null
        ? null
        : '현재 최고 ${GameRegistry.formatScore(gameId, bestScore)}';
    return Text(
      bestText == null ? challengeText : '$challengeText · $bestText',
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.reward.withValues(alpha: 0.16),
      border: Border.all(color: AppColors.reward),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.reward,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    ),
  );
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.text,
      minimumSize: const Size.fromHeight(50),
      side: const BorderSide(color: AppColors.border, width: 2),
      shape: const RoundedRectangleBorder(),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
    ),
  );
}

String _durationLabel(TodayGame? game) {
  return switch (game?.id) {
    'gravity_switch' => '제한 없이',
    'failed_bakery' => '실수할 때까지',
    'apple_game' || 'apple_game_v2' => '2분',
    'dung_dodge_v2' => '최대 5분',
    'number_rush' => '최대 3분',
    _ => '${game?.durationSeconds ?? 60}초',
  };
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '오늘의 게임',
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_monthName(DateTime.now().month)} ${DateTime.now().day}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
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
              visualDensity: VisualDensity.compact,
              onPressed: onHistory,
              icon: const Icon(Icons.history, color: AppColors.text),
            ),
            IconButton(
              tooltip: '설정',
              visualDensity: VisualDensity.compact,
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
    final isDungDodgeV2 = gameId == 'dung_dodge_v2';
    return AspectRatio(
      aspectRatio: isDungDodgeV2 ? 0.78 : 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.backgroundDeep,
          border: Border.all(color: AppColors.border, width: 2),
          boxShadow: const [
            BoxShadow(color: AppColors.backgroundDeep, offset: Offset(6, 6)),
          ],
        ),
        child: switch (gameId) {
          'dung_dodge_v2' => const _DungDodgeV2Preview(),
          'gravity_switch' => const _GravityGamePreview(),
          'failed_bakery' => const _FailedBakeryPreview(),
          'apple_game' => const _AppleGamePreview(),
          'apple_game_v2' => const _AppleGameV2Preview(),
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

class _DungDodgeV2Preview extends StatelessWidget {
  const _DungDodgeV2Preview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('dung-dodge-v2-preview'),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/dung_dodge_v2/home_gameplay_hero.png',
          ),
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _AtlasPreviewFrame extends StatelessWidget {
  const _AtlasPreviewFrame({required this.assetPath, required this.frameSize});

  final String assetPath;
  final double frameSize;

  @override
  Widget build(BuildContext context) {
    final sheetSize = frameSize * 2;
    return SizedBox.square(
      dimension: frameSize,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sheetSize,
          maxWidth: sheetSize,
          minHeight: sheetSize,
          maxHeight: sheetSize,
          child: Image.asset(
            assetPath,
            width: sheetSize,
            height: sheetSize,
            filterQuality: FilterQuality.none,
          ),
        ),
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
                            color: number == 1
                                ? const Color(0xFFFF4FC3)
                                : const Color(0xFF633094),
                            width: number == 1 ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$number',
                            style: TextStyle(
                              fontFamily: 'Galmuri',
                              color: const Color(0xFF5DF5FF),
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
                            '1 → 50',
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

class _AppleGameV2Preview extends StatelessWidget {
  const _AppleGameV2Preview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            'assets/images/apple_game_v2/apple_game_background.png',
          ),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.none,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0x42010B27))),
          Image.asset(
            'assets/images/apple_game_v2/apple_faces_atlas.png',
            width: 126,
            height: 126,
            filterQuality: FilterQuality.none,
          ),
        ],
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
                    'assets/images/gravity_switch_v2/player_magnet_mite_sheet_v3.png',
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
      'apple_game_v2' => '2분',
      'dung_dodge_v2' => '최대 5분',
      'number_rush' => '최대 3분',
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
