import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/duels/data/duel_repository.dart';
import 'package:just_one_round/features/duels/domain/duel_state.dart';
import 'package:just_one_round/features/duels/presentation/duel_error_message.dart';
import 'package:just_one_round/features/duels/presentation/duel_room_screen.dart';
import 'package:just_one_round/features/gameplay/domain/duel_play_context.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';

/// Entry point for the 1:1 duel feature.
///
/// A ranking action can pass [initialOpponentUserId] and
/// [initialOpponentNickname]. When they are omitted the screen remains a
/// reusable inbox/list surface; the host can open [DuelCreateSheet] after it
/// has selected a player from its own ranking UI.
class DuelLobbyScreen extends ConsumerStatefulWidget {
  const DuelLobbyScreen({
    this.initialOpponentUserId,
    this.initialOpponentNickname,
    this.onCreated,
    this.onStarted,
    this.onLaunchGame,
    super.key,
  });

  final String? initialOpponentUserId;
  final String? initialOpponentNickname;
  final ValueChanged<DuelMatch>? onCreated;
  final ValueChanged<DuelStartContext>? onStarted;
  final ValueChanged<DuelPlayContext>? onLaunchGame;

  @override
  ConsumerState<DuelLobbyScreen> createState() => _DuelLobbyScreenState();
}

class _DuelLobbyScreenState extends ConsumerState<DuelLobbyScreen> {
  DuelOptions _options = DuelOptions.defaults();
  List<DuelMatch> _matches = const [];
  DuelGameOption? _selectedGame;
  int _stake = 100;
  String? _error;
  var _loading = true;
  var _creating = false;

  bool get _hasPresetOpponent =>
      widget.initialOpponentUserId?.trim().isNotEmpty == true;

  int _maxStakeForBalance(int? balance) {
    if (balance == null || balance >= _options.maxStake) {
      return _options.maxStake;
    }
    return balance;
  }

  int _stakeForBalance(int? balance) {
    if (balance == null) return _stake;
    final maxStake = _maxStakeForBalance(balance);
    if (maxStake < _options.minStake) return 0;
    final capped = _stake > maxStake ? maxStake : _stake;
    return _options.clampStake(capped);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(duelRepositoryProvider);
      final response = await Future.wait<Object>([
        repository.fetchDuelOptions(),
        repository.fetchDuels(),
      ]);
      final options = response[0] as DuelOptions;
      final selectedGameId = _selectedGame?.id;
      DuelGameOption? nextGame;
      if (selectedGameId != null) {
        for (final game in options.games) {
          if (game.id == selectedGameId) {
            nextGame = game;
            break;
          }
        }
      }
      nextGame ??= options.games.isEmpty ? null : options.games.first;
      if (!mounted) return;
      setState(() {
        _options = options;
        _matches = response[1] as List<DuelMatch>;
        _selectedGame = nextGame;
        _stake = options.clampStake(
          _stake == 100 ? options.defaultStake : _stake,
        );
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _create() async {
    final opponentUserId = widget.initialOpponentUserId?.trim() ?? '';
    final game = _selectedGame;
    if (opponentUserId.isEmpty) {
      _showMessage('랭킹에서 상대를 선택한 뒤 요청해 주세요.');
      return;
    }
    if (game == null) {
      _showMessage('지금 대결할 수 있는 게임이 없어요.');
      return;
    }
    final coinBalance = ref.read(todayStateProvider).value?.economy.coins;
    if (coinBalance == null) {
      _showMessage('코인 잔액을 확인하는 중이에요. 잠시 후 다시 시도해 주세요.');
      return;
    }
    final stake = _stakeForBalance(coinBalance);
    if (stake < _options.minStake || stake > coinBalance) {
      _showMessage('최소 ${_options.minStake}코인이 있어야 대결을 신청할 수 있어요.');
      return;
    }
    setState(() => _creating = true);
    try {
      final match = await ref
          .read(duelRepositoryProvider)
          .createDuel(
            opponentUserId: opponentUserId,
            gameId: game.id,
            gameVersion: game.version,
            stake: stake,
            clientRequestId: createDuelRequestId(),
          );
      if (!mounted) return;
      widget.onCreated?.call(match);
      await _openRoom(match);
      await _load();
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _joinAndOpen(DuelMatch match) async {
    try {
      final joined = await ref.read(duelRepositoryProvider).joinDuel(match.id);
      if (!mounted) return;
      await _openRoom(joined);
      await _load();
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    }
  }

  Future<void> _openSettledResult(DuelMatch match) async {
    await _openRoom(match, readOnly: true);
    if (mounted) await _load();
  }

  Future<void> _openRoom(DuelMatch match, {bool readOnly = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DuelRoomScreen(
          matchId: match.id,
          readOnly: readOnly,
          onStarted: widget.onStarted,
          onLaunchGame: widget.onLaunchGame,
        ),
      ),
    );
    await _refreshEconomyAfterRoom();
  }

  Future<void> _refreshEconomyAfterRoom() async {
    if (!mounted) return;
    try {
      // Room settlement can change the wallet while this lobby is covered by
      // the room route. Refresh the provider before rebuilding the create
      // panel so stake limits never use the pre-settlement balance.
      await ref.refresh(todayStateProvider.future).then<void>((_) {});
    } on Object {
      // The room/list itself remains usable during a transient economy fetch
      // failure. A later provider watch or manual pull-to-refresh can retry.
      if (mounted) ref.invalidate(todayStateProvider);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: WordSafeText(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const WordSafeText('1:1 대결', singleLine: true),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (_error != null) _ErrorPanel(message: _error!),
                  if (_hasPresetOpponent) ...[
                    _buildCreatePanel(
                      ref.watch(todayStateProvider).value?.economy.coins,
                    ),
                    const SizedBox(height: 20),
                  ],
                  _SectionTitle(
                    title: '내 대결방',
                    trailing: '${_matches.length}개',
                  ),
                  const SizedBox(height: 8),
                  if (_matches.isEmpty)
                    const PixelPanel(
                      child: WordSafeText(
                        '아직 대결방이 없어요.\n랭킹에서 상대를 선택해 1:1 대결을 신청해 보세요.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          height: 1.5,
                        ),
                      ),
                    )
                  else
                    for (final match in _matches) ...[
                      _DuelMatchTile(
                        match: match,
                        onTap: match.isFinished
                            ? match.status == 'settled'
                                  ? () => _openSettledResult(match)
                                  : null
                            : () => _joinAndOpen(match),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
      ),
    );
  }

  Widget _buildCreatePanel(int? coinBalance) {
    final game = _selectedGame;
    final stake = _stakeForBalance(coinBalance);
    final maxStake = _maxStakeForBalance(coinBalance);
    final canAffordStake =
        coinBalance != null &&
        stake >= _options.minStake &&
        stake <= coinBalance;
    return PixelPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WordSafeText(
            '새 대결 만들기',
            style: TextStyle(
              color: AppColors.text,
              fontFamily: 'Galmuri',
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          WordSafeText(
            '${widget.initialOpponentNickname ?? '상대'}님에게 방을 만들어요.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          if (_options.games.isEmpty)
            const WordSafeText(
              '서버가 대결 가능한 게임을 준비 중이에요.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            DropdownButtonFormField<DuelGameOption>(
              initialValue: game,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                labelText: '게임',
                labelStyle: TextStyle(color: AppColors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
              items: [
                for (final option in _options.games)
                  DropdownMenuItem(
                    value: option,
                    child: WordSafeText(option.displayName, singleLine: true),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedGame = value),
            ),
          const SizedBox(height: 14),
          _StakePicker(
            value: stake,
            min: _options.minStake,
            max: maxStake,
            step: _options.stakeStep,
            onChanged: (value) => setState(() => _stake = value),
          ),
          WordSafeText(
            coinBalance == null
                ? '코인 잔액 확인 중...'
                : coinBalance < _options.minStake
                ? '보유 코인 $coinBalance · 최소 ${_options.minStake}코인이 필요해요.'
                : '보유 코인 $coinBalance · 최대 $maxStake코인까지 걸 수 있어요.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          PixelButton(
            label: _creating ? '방 만드는 중...' : '대결방 만들기',
            icon: Icons.sports_esports_outlined,
            onPressed: _creating || game == null || !canAffordStake
                ? null
                : _create,
          ),
        ],
      ),
    );
  }
}

/// A compact create surface for a host that already selected a player.
class DuelCreateSheet extends StatelessWidget {
  const DuelCreateSheet({
    required this.opponentUserId,
    this.opponentNickname,
    super.key,
  });

  final String opponentUserId;
  final String? opponentNickname;

  @override
  Widget build(BuildContext context) => DuelLobbyScreen(
    initialOpponentUserId: opponentUserId,
    initialOpponentNickname: opponentNickname,
  );
}

class _StakePicker extends StatelessWidget {
  const _StakePicker({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: WordSafeText(
          '내기 코인',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
      IconButton(
        tooltip: '10코인 내리기',
        onPressed: max < min || value <= min
            ? null
            : () => onChanged(value - step),
        icon: const Icon(Icons.remove_circle_outline),
        color: AppColors.text,
      ),
      SizedBox(
        width: 76,
        child: Center(
          child: WordSafeText(
            '$value',
            singleLine: true,
            style: const TextStyle(
              color: AppColors.reward,
              fontFamily: 'Galmuri',
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: '10코인 올리기',
        onPressed: max < min || value >= max
            ? null
            : () => onChanged(value + step),
        icon: const Icon(Icons.add_circle_outline),
        color: AppColors.text,
      ),
    ],
  );
}

class _DuelMatchTile extends StatelessWidget {
  const _DuelMatchTile({required this.match, required this.onTap});

  final DuelMatch match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PixelPanel(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WordSafeText(
                match.opponentNickname == null
                    ? match.gameName
                    : '${match.opponentNickname} · ${match.gameName}',
                style: const TextStyle(
                  color: AppColors.text,
                  fontFamily: 'Galmuri',
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              WordSafeText(
                '${match.stake}코인 · ${_statusLabel(match.status)}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        if (onTap != null)
          match.status == 'settled'
              ? TextButton(
                  onPressed: onTap,
                  child: const WordSafeText(
                    '결과 보기',
                    singleLine: true,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: match.isWaiting ? '방 입장' : '대결 보기',
                  onPressed: onTap,
                  color: AppColors.primary,
                  icon: const Icon(Icons.chevron_right),
                )
        else
          const Icon(Icons.check_circle_outline, color: AppColors.reward),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: WordSafeText(
          title,
          style: const TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      WordSafeText(
        trailing,
        style: const TextStyle(color: AppColors.textMuted),
      ),
    ],
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PixelPanel(
    color: AppColors.surfaceLight,
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: WordSafeText(
            message,
            style: const TextStyle(color: AppColors.text),
          ),
        ),
      ],
    ),
  );
}

String _statusLabel(String status) => switch (status) {
  'waiting' => '입장 대기',
  'starting' => '곧 시작',
  'playing' => '플레이 중',
  'settled' => '결과 확인',
  'cancelled' || 'declined' || 'expired' => '종료',
  _ => status,
};

String _friendlyError(Object error) {
  return duelFriendlyError(error);
}
