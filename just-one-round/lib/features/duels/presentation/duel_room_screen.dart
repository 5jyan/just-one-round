import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/app/theme/app_colors.dart';
import 'package:just_one_round/features/duels/data/duel_asset_preloader.dart';
import 'package:just_one_round/features/duels/data/duel_result_retry.dart';
import 'package:just_one_round/features/gameplay/domain/duel_play_context.dart';
import 'package:just_one_round/features/gameplay/presentation/game_screen.dart';
import 'package:just_one_round/features/games/game_registry.dart';
import 'package:just_one_round/features/duels/data/duel_repository.dart';
import 'package:just_one_round/features/duels/domain/duel_state.dart';
import 'package:just_one_round/features/duels/presentation/duel_error_message.dart';
import 'package:just_one_round/features/today/data/daily_game_repository.dart';
import 'package:just_one_round/shared/widgets/pixel_button.dart';
import 'package:just_one_round/shared/widgets/pixel_panel.dart';
import 'package:just_one_round/shared/widgets/word_safe_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DuelRoomScreen extends ConsumerStatefulWidget {
  const DuelRoomScreen({
    required this.matchId,
    this.readOnly = false,
    this.currentUserId,
    this.onStarted,
    this.onLaunchGame,
    this.onClosed,
    this.prepareAssets,
    super.key,
  });

  final String matchId;

  /// Opens a settled room as a result viewer. It must never join, heartbeat,
  /// preload, toggle READY, or launch a second game run.
  final bool readOnly;
  final String? currentUserId;
  final ValueChanged<DuelStartContext>? onStarted;

  /// Optional direct bridge to [GameScreen]. The callback receives the
  /// repository-backed submit/forfeit closures for this exact run.
  final ValueChanged<DuelPlayContext>? onLaunchGame;
  final VoidCallback? onClosed;
  final Future<void> Function()? prepareAssets;

  @override
  ConsumerState<DuelRoomScreen> createState() => _DuelRoomScreenState();
}

class _DuelRoomScreenState extends ConsumerState<DuelRoomScreen> {
  DuelMatch? _match;
  Timer? _heartbeat;
  Timer? _roomPoll;
  String? _error;
  var _loading = true;
  var _joining = false;
  var _preparing = false;
  var _readyBusy = false;
  var _assetsReady = false;
  var _startedSent = false;
  var _pollInFlight = false;
  var _serverClockOffset = Duration.zero;
  late final String _userId;
  late final String _deviceSessionId;

  @override
  void initState() {
    super.initState();
    _userId = widget.currentUserId ?? _readCurrentUserId();
    _deviceSessionId = createDuelRequestId();
    if (!widget.readOnly) {
      unawaited(ref.read(duelResultRetryServiceProvider).retry());
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _roomPoll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(duelRepositoryProvider);
      final fetchStartedAt = DateTime.now().toUtc();
      var match = await repository.fetchDuel(widget.matchId);
      final fetchFinishedAt = DateTime.now().toUtc();
      _updateServerClock(match, fetchStartedAt, fetchFinishedAt);
      if (widget.readOnly) {
        if (!mounted) return;
        setState(() {
          _match = match;
          _loading = false;
          _joining = false;
        });
        return;
      }
      setState(() => _joining = true);
      final joinStartedAt = DateTime.now().toUtc();
      match = await repository.joinDuel(
        widget.matchId,
        deviceSessionId: _deviceSessionId,
      );
      final joinFinishedAt = DateTime.now().toUtc();
      _updateServerClock(match, joinStartedAt, joinFinishedAt);
      if (!mounted) return;
      setState(() {
        _match = match;
        _loading = false;
        _joining = false;
      });
      _startHeartbeat();
      _startRoomPolling();
      unawaited(_prepareAssets());
      _maybeLaunch(match);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _joining = false;
        _error = _friendlyError(error);
      });
    }
  }

  DuelRun? _currentRun(DuelMatch match) {
    if (_userId.isNotEmpty) {
      final own = match.runFor(_userId);
      if (own != null) return _withViewerRunId(match, own);
    }
    for (final run in match.runs) {
      if (run.joined) return _withViewerRunId(match, run);
    }
    return null;
  }

  DuelRun _withViewerRunId(DuelMatch match, DuelRun run) => DuelRun(
    userId: run.userId,
    runId: run.runId ?? match.viewerRunId,
    nickname: run.nickname,
    joined: run.joined,
    loadingComplete: run.loadingComplete,
    ready: run.ready,
    sessionGeneration: run.sessionGeneration,
    status: run.status,
    score: run.score,
    resultType: run.resultType,
    startedAt: run.startedAt,
    submitDeadline: run.submitDeadline,
    challengeSeed: run.challengeSeed ?? match.viewerSeed,
    presenceExpiresAt: run.presenceExpiresAt,
  );

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) async {
      final match = _match;
      final run = match == null ? null : _currentRun(match);
      if (match == null || run == null || match.isFinished) return;
      try {
        final requestStartedAt = DateTime.now().toUtc();
        final updated = await ref
            .read(duelRepositoryProvider)
            .heartbeatDuel(
              matchId: match.id,
              deviceSessionId: _deviceSessionId,
            );
        _updateServerClock(updated, requestStartedAt, DateTime.now().toUtc());
        if (!mounted) return;
        setState(() => _match = updated);
        _maybeLaunch(updated);
      } on Object {
        // A short network outage must not become an immediate loss.
      }
    });
  }

  /// Heartbeats keep the device session alive, but they are intentionally
  /// slower than the room-state poll. The server starts the match three
  /// seconds after the second READY, so a five-second heartbeat alone can
  /// leave the first READY player stale until after the common start time.
  void _startRoomPolling() {
    _roomPoll?.cancel();
    _roomPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollRoom());
    });
  }

  Future<void> _pollRoom() async {
    // Keep polling after the game is launched so the room underneath the
    // result screen can observe settlement. `_startedSent` is intentionally
    // checked only by _maybeLaunch; a settled snapshot can never relaunch the
    // runtime and the existing run identity remains immutable.
    if (!mounted || _pollInFlight) return;
    final match = _match;
    if (match == null || match.isFinished) {
      _roomPoll?.cancel();
      return;
    }
    _pollInFlight = true;
    try {
      final requestStartedAt = DateTime.now().toUtc();
      final updated = await ref
          .read(duelRepositoryProvider)
          .fetchDuel(widget.matchId);
      _updateServerClock(updated, requestStartedAt, DateTime.now().toUtc());
      if (!mounted) return;
      setState(() => _match = updated);
      _maybeLaunch(updated);
      if (updated.isFinished) {
        _roomPoll?.cancel();
        // Settlement changes the wallet independently of the room snapshot.
        // Refresh while the result room is visible so returning to the lobby
        // cannot reuse the pre-settlement TodayState cache.
        unawaited(_refreshEconomyAfterSettlement());
      }
    } on Object {
      // A short network outage must not become an immediate loss. The next
      // tick retries and the heartbeat continues independently.
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _refreshEconomyAfterSettlement() async {
    try {
      await ref.refresh(todayStateProvider.future).then<void>((_) {});
    } on Object {
      // The room result remains visible even if the wallet refresh is
      // temporarily unavailable; the lobby retries when it is reopened.
    }
  }

  Future<void> _prepareAssets() async {
    if (_assetsReady || _preparing) return;
    final match = _match;
    if (match == null) return;
    setState(() => _preparing = true);
    try {
      await (widget.prepareAssets?.call() ??
          ref
              .read(duelAssetPreloaderProvider)
              .preload(gameId: match.gameId, gameVersion: match.gameVersion));
      if (!mounted) return;
      setState(() => _assetsReady = true);
      _maybeLaunch(match);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _setReady(bool value) async {
    final match = _match;
    final run = match == null ? null : _currentRun(match);
    if (match == null || run == null || !_assetsReady || _readyBusy) return;
    setState(() {
      _readyBusy = true;
      _error = null;
    });
    try {
      final requestStartedAt = DateTime.now().toUtc();
      final updated = await ref
          .read(duelRepositoryProvider)
          .setDuelReady(
            matchId: match.id,
            ready: value,
            loadingComplete: true,
            deviceSessionId: _deviceSessionId,
          );
      _updateServerClock(updated, requestStartedAt, DateTime.now().toUtc());
      if (!mounted) return;
      setState(() {
        _match = updated;
        _error = updated.startFailed
            ? _startFailureMessage(updated.startFailureReason)
            : null;
      });
      _maybeLaunch(updated);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _readyBusy = false);
    }
  }

  void _maybeLaunch(DuelMatch match) {
    if (_startedSent ||
        !_assetsReady ||
        (!match.isStarting && !match.isPlaying)) {
      return;
    }
    final run = _currentRun(match);
    final runId = run?.runId;
    final runToken = match.viewerRunToken;
    if (run == null ||
        runId == null ||
        runId.isEmpty ||
        runToken == null ||
        runToken.isEmpty) {
      return;
    }
    if (run.challengeSeed == null) {
      if (mounted) {
        setState(() => _error = '게임 준비 정보를 받지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
      return;
    }
    _startedSent = true;
    widget.onStarted?.call(
      DuelStartContext(
        matchId: match.id,
        runId: runId,
        gameId: match.gameId,
        gameVersion: match.gameVersion,
        startAt: match.startAt ?? DateTime.now().toUtc(),
        submitDeadline:
            run.submitDeadline ??
            match.viewerSubmitDeadline ??
            DateTime.now().toUtc(),
        challengeSeed: run.challengeSeed ?? match.viewerSeed,
        runtimeRevision: match.runtimeRevision,
        gameDurationSeconds: match.gameDurationSeconds,
        serverClockOffset: _serverClockOffset,
      ),
    );
    final repository = ref.read(duelRepositoryProvider);
    final retryService = ref.read(duelResultRetryServiceProvider);
    // Persist before the network call. GameScreen can call this same
    // idempotent callback again after a response loss, and the queue can be
    // retried by the next room foreground.
    late final DuelPlayContext durableContext;
    durableContext = DuelPlayContext(
      matchId: match.id,
      runId: runId,
      gameId: match.gameId,
      gameVersion: match.gameVersion,
      challengeSeed: run.challengeSeed!,
      startAt: match.startAt ?? DateTime.now().toUtc(),
      gameDuration: _gameDuration(match),
      serverClockOffset: _serverClockOffset,
      submitResult: (result) {
        final kind = durableContext.submissionKindFor(result);
        final isNoResult = kind == DuelSubmissionKind.noResult;
        return retryService.submit(
          DuelResultSubmission(
            matchId: match.id,
            runId: runId,
            runToken: runToken,
            resultKind: kind.wireValue,
            rawScore: isNoResult ? 0 : result.score,
            durationMs: result.duration.inMilliseconds,
            starsCollected: result.starsCollected,
            collisions: result.collisions,
            windDartsShotScores: result.windDartsShotScores,
          ),
        );
      },
      forfeit: () => repository.forfeitDuel(
        matchId: match.id,
        runId: runId,
        runToken: runToken,
      ),
    );
    final launch = widget.onLaunchGame;
    if (launch != null) {
      launch(durableContext);
    } else if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Keep the room underneath the game so GameScreen's duel result
        // action can pop back to this read-only/live room. `_startedSent`
        // remains true on this state and therefore prevents a second launch
        // when the room becomes visible again.
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GameScreen(duelContext: durableContext),
          ),
        );
      });
    }
  }

  Future<bool> _close() async {
    final match = _match;
    if (!widget.readOnly && match != null && match.canLeave) {
      try {
        final requestStartedAt = DateTime.now().toUtc();
        final updated = await ref
            .read(duelRepositoryProvider)
            .leaveDuel(matchId: match.id, deviceSessionId: _deviceSessionId);
        _updateServerClock(updated, requestStartedAt, DateTime.now().toUtc());
        if (mounted) setState(() => _match = updated);
      } on Object catch (error) {
        if (mounted) {
          _showMessage(_friendlyError(error));
          return false;
        }
      }
    }
    widget.onClosed?.call();
    return true;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: WordSafeText(message)));
  }

  void _updateServerClock(
    DuelMatch match,
    DateTime requestStartedAt,
    DateTime requestFinishedAt,
  ) {
    final serverNow = match.serverNow;
    if (serverNow == null) return;
    final midpointMicros =
        (requestStartedAt.microsecondsSinceEpoch +
            requestFinishedAt.microsecondsSinceEpoch) ~/
        2;
    _serverClockOffset = Duration(
      microseconds: serverNow.microsecondsSinceEpoch - midpointMicros,
    );
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    return WillPopScope(
      onWillPop: _close,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const WordSafeText('대결방', singleLine: true),
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.text,
          leading: IconButton(
            tooltip: '닫기',
            onPressed: () async {
              if (await _close() && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.close),
          ),
        ),
        body: _loading || _joining
            ? const Center(child: CircularProgressIndicator())
            : _error != null && match == null
            ? _ErrorBody(message: _error!, onRetry: _load)
            : match == null
            ? _ErrorBody(message: '대결방을 찾을 수 없어요.', onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _RoomHeader(match: match),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      _ErrorPanel(message: _error!),
                    ],
                    const SizedBox(height: 14),
                    _PlayersPanel(
                      match: match,
                      currentUserId: _userId,
                      localAssetsReady: _assetsReady,
                    ),
                    const SizedBox(height: 14),
                    if (!widget.readOnly && match.isWaiting)
                      _buildReadyPanel(match),
                    if (!widget.readOnly &&
                        (match.isStarting || match.isPlaying))
                      _StartPanel(match: match),
                    if (match.isFinished)
                      _ResultPanel(match: match, currentUserId: _userId),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildReadyPanel(DuelMatch match) {
    final run = _currentRun(match);
    final opponent = run == null
        ? null
        : match.runs.cast<DuelRun?>().firstWhere(
            (candidate) => candidate?.userId != run.userId,
            orElse: () => null,
          );
    final bothPlayersPresent =
        run?.isPresentAt(DateTime.now().toUtc()) == true &&
        opponent?.isPresentAt(DateTime.now().toUtc()) == true;
    // `loading_complete` is persisted by set_duel_ready. Before the first
    // READY call the snapshot is expected to be false even though this device
    // has already finished its local preload, so use the local state to enable
    // the first READY action.
    final canReady = bothPlayersPresent && _assetsReady;
    final ready = run?.ready == true;
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordSafeText(
            !_assetsReady
                ? (_preparing ? '게임 준비 중...' : '게임을 준비해 주세요')
                : !bothPlayersPresent
                ? '두 사람이 모두 입장하면 READY를 누를 수 있어요.'
                : ready
                ? '상대방을 기다리는 중...'
                : '준비가 끝났다면 READY를 눌러 주세요.',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          PixelButton(
            label: _readyBusy
                ? '확인 중...'
                : ready
                ? 'READY 취소'
                : 'READY',
            icon: ready ? Icons.undo : Icons.check_circle_outline,
            onPressed: _readyBusy || !canReady ? null : () => _setReady(!ready),
          ),
        ],
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.match});

  final DuelMatch match;

  @override
  Widget build(BuildContext context) => PixelPanel(
    color: AppColors.surfaceLight,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WordSafeText(
          match.gameName,
          style: const TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        WordSafeText(
          '${match.stake}코인 내기 · 총 ${match.stake * 2}코인',
          style: const TextStyle(color: AppColors.reward),
        ),
        const SizedBox(height: 7),
        WordSafeText(
          _roomStatus(match.status),
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _PlayersPanel extends StatelessWidget {
  const _PlayersPanel({
    required this.match,
    required this.currentUserId,
    required this.localAssetsReady,
  });

  final DuelMatch match;
  final String currentUserId;
  final bool localAssetsReady;

  @override
  Widget build(BuildContext context) => PixelPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WordSafeText(
          '플레이어',
          style: TextStyle(
            color: AppColors.text,
            fontFamily: 'Galmuri',
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < match.runs.length; index++) ...[
          if (index > 0) const Divider(color: AppColors.border),
          _PlayerRow(
            run: match.runs[index],
            isMe: match.runs[index].userId == currentUserId,
            localAssetsReady: localAssetsReady,
            fallbackNickname: match.opponentNickname,
          ),
        ],
        if (match.runs.isEmpty)
          const WordSafeText(
            '플레이어 정보를 불러오는 중이에요.',
            style: TextStyle(color: AppColors.textMuted),
          ),
      ],
    ),
  );
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.run,
    required this.isMe,
    required this.localAssetsReady,
    this.fallbackNickname,
  });

  final DuelRun run;
  final bool isMe;
  final bool localAssetsReady;
  final String? fallbackNickname;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: WordSafeText(
          '${run.nickname ?? (isMe ? '나' : fallbackNickname ?? '상대')}${isMe ? ' (나)' : ''}',
          style: const TextStyle(color: AppColors.text),
        ),
      ),
      _StateChip(
        label: switch (run.status) {
          'submitted' || 'settled' => '완료',
          'forfeited' => '기권',
          'no_result' => '결과 없음',
          _ when !run.joined => '입장 대기',
          _ when run.ready => 'READY',
          _ when run.loadingComplete || (isMe && localAssetsReady) => '준비 완료',
          _ => '로딩 중',
        },
      ),
    ],
  );
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.background,
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: WordSafeText(
        label,
        singleLine: true,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
      ),
    ),
  );
}

class _StartPanel extends StatelessWidget {
  const _StartPanel({required this.match});

  final DuelMatch match;

  @override
  Widget build(BuildContext context) => PixelPanel(
    color: AppColors.surfaceLight,
    child: Column(
      children: [
        const Icon(
          Icons.play_circle_outline,
          color: AppColors.primary,
          size: 38,
        ),
        const SizedBox(height: 8),
        WordSafeText(
          match.isStarting ? '둘 다 준비됐어요. 곧 시작합니다.' : '게임이 진행 중이에요.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.text),
        ),
      ],
    ),
  );
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.match, required this.currentUserId});

  final DuelMatch match;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final summary = duelResultSummary(match, currentUserId);
    String scoreLabel(int? score) {
      if (score == null) return '결과 없음';
      try {
        return GameRegistry.formatScore(match.gameId, score);
      } on Object {
        return '$score점';
      }
    }

    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WordSafeText(
            '대결 결과',
            style: TextStyle(
              color: AppColors.text,
              fontFamily: 'Galmuri',
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          WordSafeText(
            summary.outcomeLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: summary.viewerWon == true
                  ? AppColors.reward
                  : summary.viewerWon == false
                  ? AppColors.danger
                  : AppColors.primary,
              fontFamily: 'Galmuri',
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ResultScoreCell(
                  label: '내 점수',
                  value: scoreLabel(summary.ownScore),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResultScoreCell(
                  label: '상대 점수',
                  value: scoreLabel(summary.opponentScore),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WordSafeText(
            summary.coinLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.reward,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultScoreCell extends StatelessWidget {
  const _ResultScoreCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.background,
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(
        children: [
          WordSafeText(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          WordSafeText(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontFamily: 'Galmuri',
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ErrorPanel(message: message),
          const SizedBox(height: 14),
          PixelButton(label: '다시 시도', onPressed: onRetry),
        ],
      ),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PixelPanel(
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: AppColors.primary),
        const SizedBox(width: 8),
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

String _readCurrentUserId() {
  try {
    return Supabase.instance.client.auth.currentUser?.id ?? '';
  } on Object {
    return '';
  }
}

Duration _gameDuration(DuelMatch match) => Duration(
  seconds:
      match.gameDurationSeconds ??
      GameRegistry.tryForId(match.gameId)?.defaultDuration.inSeconds ??
      60,
);

String _roomStatus(String status) => switch (status) {
  'waiting' => '상대방 입장과 READY를 기다리는 중',
  'starting' => '둘 다 READY · 곧 시작',
  'playing' => '플레이 중',
  'settled' => '결과가 확정됐어요',
  'cancelled' || 'declined' || 'expired' => '방이 종료됐어요',
  _ => status,
};

String _friendlyError(Object error) {
  return duelFriendlyError(error);
}

String _startFailureMessage(String? reason) => switch (reason) {
  'insufficient_coin_balance' => '코인이 부족해서 대결을 시작할 수 없어요.',
  'opponent_not_ready' => '상대방 준비 상태가 바뀌었어요. 두 사람 모두 다시 READY를 눌러 주세요.',
  'runtime_mismatch' => '두 사람의 게임 버전이 달라 대결을 시작할 수 없어요.',
  'room_expired' => '대결 요청이 만료됐어요. 새 대결을 신청해 주세요.',
  'game_unavailable' => '현재 이 게임으로 대결할 수 없어요. 다른 게임을 골라 주세요.',
  'opponent_unavailable' => '상대방과 대결할 수 없어요. 새 대결을 신청해 주세요.',
  _ => '대결을 시작하지 못했어요. 두 사람 모두 다시 READY를 눌러 주세요.',
};
