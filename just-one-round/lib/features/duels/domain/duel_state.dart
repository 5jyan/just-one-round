import 'package:flutter/foundation.dart';

/// A game explicitly enabled by the server for duel rooms.
@immutable
class DuelGameOption {
  const DuelGameOption({
    required this.id,
    required this.displayName,
    required this.version,
    this.runtimeRevision,
    this.durationSeconds,
  });

  factory DuelGameOption.fromJson(Map<String, dynamic> json) => DuelGameOption(
    id: _string(json, 'game_id', fallback: json['id']),
    displayName: _string(
      json,
      'display_name',
      fallback: json['name'] ?? json['game_name'],
    ),
    version: _integer(json, 'game_version', fallback: json['version']) ?? 1,
    runtimeRevision: _stringOrNull(
      json,
      'runtime_revision',
      fallback: json['duel_rules_revision'],
    ),
    durationSeconds: _integer(json, 'duration_seconds'),
  );

  final String id;
  final String displayName;
  final int version;
  final String? runtimeRevision;
  final int? durationSeconds;
}

/// A server-approved opponent used only by local test accounts.
///
/// The server returns an empty list for normal accounts and production
/// environments. Keeping this as a separate type prevents the test-only
/// picker from being mixed into the ordinary ranking/social player list.
@immutable
class DuelTestPlayer {
  const DuelTestPlayer({
    required this.userId,
    required this.nickname,
    this.testGameId,
  });

  factory DuelTestPlayer.fromJson(Map<String, dynamic> json) => DuelTestPlayer(
    userId: _string(json, 'user_id', fallback: json['id']),
    nickname: _string(
      json,
      'nickname',
      fallback: json['display_name'] ?? json['name'] ?? '테스트 상대',
    ),
    testGameId: _stringOrNull(json, 'test_game_id'),
  );

  final String userId;
  final String nickname;
  final String? testGameId;
}

@immutable
class DuelOptions {
  const DuelOptions({
    required this.games,
    required this.minStake,
    required this.maxStake,
    required this.stakeStep,
    required this.defaultStake,
  });

  factory DuelOptions.fromJson(Map<String, dynamic> json) {
    final rawGames = json['games'] ?? json['game_options'] ?? const [];
    final games = rawGames is List
        ? rawGames
              .whereType<Map>()
              .map(
                (item) =>
                    DuelGameOption.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((game) => isGameEligible(game.id))
              .toList(growable: false)
        : const <DuelGameOption>[];
    return DuelOptions(
      games: games,
      minStake: _integer(json, 'min_stake') ?? 10,
      maxStake: _integer(json, 'max_stake') ?? 200,
      stakeStep: _integer(json, 'stake_step') ?? 10,
      defaultStake: _integer(json, 'default_stake') ?? 100,
    );
  }

  factory DuelOptions.defaults() => const DuelOptions(
    games: <DuelGameOption>[],
    minStake: 10,
    maxStake: 200,
    stakeStep: 10,
    defaultStake: 100,
  );

  final List<DuelGameOption> games;
  final int minStake;
  final int maxStake;
  final int stakeStep;
  final int defaultStake;

  static bool isGameEligible(String gameId) =>
      gameId != 'wind_darts' && gameId != 'western_duel';

  int clampStake(int value) {
    final clamped = value.clamp(minStake, maxStake).toInt();
    if (stakeStep <= 1) return clamped;
    final offset = clamped - minStake;
    return minStake + (offset ~/ stakeStep) * stakeStep;
  }
}

@immutable
class DuelRun {
  const DuelRun({
    required this.userId,
    this.runId,
    this.nickname,
    this.joined = false,
    this.loadingComplete = false,
    this.ready = false,
    this.sessionGeneration,
    this.status,
    this.score,
    this.resultType,
    this.startedAt,
    this.submitDeadline,
    this.challengeSeed,
    this.presenceExpiresAt,
  });

  factory DuelRun.fromJson(Map<String, dynamic> json) => DuelRun(
    userId: _string(json, 'user_id', fallback: json['id']),
    runId: _stringOrNull(json, 'run_id', fallback: json['entry_id']),
    nickname: _stringOrNull(
      json,
      'nickname',
      fallback: json['display_name'] ?? json['name'],
    ),
    joined:
        _boolean(
          json,
          'joined',
          fallback: json['entered'] ?? json['in_room'],
        ) ??
        false,
    loadingComplete:
        _boolean(
          json,
          'loading_complete',
          fallback: json['loaded'] ?? json['assets_loaded'],
        ) ??
        false,
    ready: _boolean(json, 'ready') ?? false,
    sessionGeneration: _integer(json, 'session_generation'),
    status: _stringOrNull(json, 'status', fallback: json['run_status']),
    score: _integer(json, 'score', fallback: json['raw_score']),
    resultType: _stringOrNull(
      json,
      'result_type',
      fallback: json['result_kind'],
    ),
    startedAt: _dateTime(json, 'started_at'),
    submitDeadline: _dateTime(json, 'submit_deadline'),
    challengeSeed: _integer(json, 'challenge_seed', fallback: json['seed']),
    presenceExpiresAt: _dateTime(json, 'presence_expires_at'),
  );

  final String userId;
  final String? runId;
  final String? nickname;
  final bool joined;
  final bool loadingComplete;
  final bool ready;
  final int? sessionGeneration;
  final String? status;
  final int? score;
  final String? resultType;
  final DateTime? startedAt;
  final DateTime? submitDeadline;
  final int? challengeSeed;
  final DateTime? presenceExpiresAt;

  bool isPresentAt(DateTime now) =>
      joined &&
      (presenceExpiresAt == null || presenceExpiresAt!.isAfter(now.toUtc()));

  bool get canReady => joined && loadingComplete;
  bool get isTerminal => switch (status) {
    'submitted' || 'forfeited' || 'no_result' || 'settled' => true,
    _ => false,
  };
}

@immutable
class DuelStartContext {
  const DuelStartContext({
    required this.matchId,
    required this.runId,
    required this.gameId,
    required this.gameVersion,
    required this.startAt,
    required this.submitDeadline,
    this.challengeSeed,
    this.runtimeRevision,
    this.gameDurationSeconds,
    this.serverClockOffset = Duration.zero,
  });

  factory DuelStartContext.fromJson(Map<String, dynamic> json) =>
      DuelStartContext(
        matchId: _string(json, 'match_id', fallback: json['id']),
        runId: _string(json, 'run_id'),
        gameId: _string(json, 'game_id'),
        gameVersion: _integer(json, 'game_version') ?? 1,
        startAt: _dateTime(json, 'start_at') ?? DateTime.now().toUtc(),
        submitDeadline:
            _dateTime(json, 'submit_deadline') ?? DateTime.now().toUtc(),
        challengeSeed: _integer(json, 'challenge_seed', fallback: json['seed']),
        runtimeRevision: _stringOrNull(json, 'runtime_revision'),
        gameDurationSeconds: _integer(json, 'game_duration_seconds'),
      );

  final String matchId;
  final String runId;
  final String gameId;
  final int gameVersion;
  final DateTime startAt;
  final DateTime submitDeadline;
  final int? challengeSeed;
  final String? runtimeRevision;
  final int? gameDurationSeconds;
  final Duration serverClockOffset;
}

@immutable
class DuelMatch {
  const DuelMatch({
    required this.id,
    required this.requesterUserId,
    required this.opponentUserId,
    required this.gameId,
    required this.gameName,
    required this.gameVersion,
    required this.stake,
    required this.status,
    required this.createdAt,
    required this.waitingExpiresAt,
    required this.runs,
    this.runtimeRevision,
    this.gameDurationSeconds,
    this.viewerSessionToken,
    this.viewerRunId,
    this.viewerRunToken,
    this.viewerSeed,
    this.viewerSubmitDeadline,
    this.roomRevision,
    this.startAt,
    this.outcome,
    this.winnerUserId,
    this.resultScore,
    this.updatedAt,
    this.startFailed = false,
    this.startFailureReason,
    this.serverNow,
    this.requesterNickname,
    this.opponentNickname,
  });

  factory DuelMatch.fromJson(Map<String, dynamic> json) {
    final gameId = _string(json, 'game_id');
    return DuelMatch(
      id: _string(json, 'match_id', fallback: json['id']),
      requesterUserId: _string(
        json,
        'requester_user_id',
        fallback: json['requester_id'],
      ),
      opponentUserId: _string(
        json,
        'opponent_user_id',
        fallback: json['opponent_id'],
      ),
      gameId: gameId,
      gameName: _gameDisplayName(json, gameId),
      gameVersion: _integer(json, 'game_version') ?? 1,
      stake: _integer(json, 'stake', fallback: json['stake_coins']) ?? 0,
      status: _string(json, 'status', fallback: 'waiting'),
      createdAt: _dateTime(json, 'created_at') ?? DateTime.now().toUtc(),
      waitingExpiresAt:
          _dateTime(json, 'waiting_expires_at', fallback: json['expires_at']) ??
          DateTime.now().toUtc(),
      runs: _readRuns(json),
      runtimeRevision: _stringOrNull(json, 'runtime_revision'),
      gameDurationSeconds: _integer(json, 'game_duration_seconds'),
      viewerSessionToken: _stringOrNull(json, 'viewer_session_token'),
      viewerRunId: _stringOrNull(json, 'viewer_run_id'),
      viewerRunToken: _stringOrNull(json, 'viewer_run_token'),
      viewerSeed: _integer(json, 'seed'),
      viewerSubmitDeadline: _dateTime(json, 'submit_deadline'),
      roomRevision: _integer(json, 'room_revision'),
      startAt: _dateTime(json, 'start_at'),
      outcome: _stringOrNull(json, 'outcome'),
      winnerUserId: _stringOrNull(json, 'winner_id'),
      resultScore: _integer(json, 'result_score'),
      updatedAt: _dateTime(json, 'updated_at'),
      startFailed: _boolean(json, 'start_failed') ?? false,
      startFailureReason: _stringOrNull(json, 'start_failure_reason'),
      serverNow: _dateTime(json, 'server_now', fallback: json['server_time']),
      requesterNickname: _stringOrNull(
        json,
        'requester_nickname',
        fallback: json['requester_display_name'] ?? json['requester_name'],
      ),
      opponentNickname: _stringOrNull(
        json,
        'opponent_nickname',
        fallback: json['opponent_display_name'] ?? json['opponent_name'],
      ),
    );
  }

  final String id;
  final String requesterUserId;
  final String opponentUserId;
  final String gameId;
  final String gameName;
  final int gameVersion;
  final int stake;
  final String status;
  final DateTime createdAt;
  final DateTime waitingExpiresAt;
  final List<DuelRun> runs;
  final String? runtimeRevision;
  final int? gameDurationSeconds;
  final String? viewerSessionToken;
  final String? viewerRunId;
  final String? viewerRunToken;
  final int? viewerSeed;
  final DateTime? viewerSubmitDeadline;
  final int? roomRevision;
  final DateTime? startAt;
  final String? outcome;
  final String? winnerUserId;
  final int? resultScore;
  final DateTime? updatedAt;
  final bool startFailed;
  final String? startFailureReason;
  final DateTime? serverNow;
  final String? requesterNickname;
  final String? opponentNickname;

  bool get isWaiting => status == 'waiting';
  bool get isStarting => status == 'starting';
  bool get isPlaying => status == 'playing';
  bool get isFinished => switch (status) {
    'settled' || 'declined' || 'cancelled' || 'expired' || 'voided' => true,
    _ => false,
  };
  bool get canLeave => isWaiting;

  DuelRun? runFor(String userId) {
    for (final run in runs) {
      if (run.userId == userId) return run;
    }
    return null;
  }

  int get joinedCount => runs.where((run) => run.joined).length;
  int get readyCount => runs.where((run) => run.ready).length;
}

/// The read-only result summary shown after a settled duel.
@immutable
class DuelResultSummary {
  const DuelResultSummary({
    required this.outcomeLabel,
    required this.coinLabel,
    required this.ownScore,
    required this.opponentScore,
    required this.viewerWon,
  });

  final String outcomeLabel;
  final String coinLabel;
  final int? ownScore;
  final int? opponentScore;
  final bool? viewerWon;
}

DuelResultSummary duelResultSummary(DuelMatch match, String viewerUserId) {
  final viewerId = viewerUserId.trim();
  DuelRun? ownRun = viewerId.isEmpty ? null : match.runFor(viewerId);
  ownRun ??= _runForViewerToken(match);
  ownRun ??= match.runs.isEmpty ? null : match.runs.first;
  final opponentRun = ownRun == null
      ? (match.runs.length > 1 ? match.runs[1] : null)
      : match.runs.cast<DuelRun?>().firstWhere(
          (run) => run?.userId != ownRun!.userId,
          orElse: () => null,
        );
  final viewerWon = _viewerWon(match, ownRun);
  final outcomeLabel = switch (match.outcome) {
    'requester_win' || 'opponent_win' => viewerWon == true ? '승리' : '패배',
    'tie' => '무승부',
    'refund' => '무승부 · 환불',
    _ => '결과 확인',
  };
  final coinLabel = switch (match.outcome) {
    'requester_win' || 'opponent_win' =>
      viewerWon == true
          ? '${match.stake * 2}코인 수령 · 순이익 +${match.stake}코인'
          : '0코인 수령 · 순손실 -${match.stake}코인',
    'tie' || 'refund' => '${match.stake}코인 환불 · 순이익 0코인',
    _ => '코인 정산을 확인하고 있어요.',
  };
  return DuelResultSummary(
    outcomeLabel: outcomeLabel,
    coinLabel: coinLabel,
    ownScore: ownRun?.score,
    opponentScore: opponentRun?.score,
    viewerWon: viewerWon,
  );
}

DuelRun? _runForViewerToken(DuelMatch match) {
  final viewerRunId = match.viewerRunId;
  if (viewerRunId == null || viewerRunId.isEmpty) return null;
  return match.runs.cast<DuelRun?>().firstWhere(
    (run) => run?.runId == viewerRunId,
    orElse: () => null,
  );
}

bool? _viewerWon(DuelMatch match, DuelRun? ownRun) {
  if (ownRun == null) return null;
  if (match.winnerUserId != null) {
    return match.winnerUserId == ownRun.userId;
  }
  return switch (match.outcome) {
    'requester_win' => ownRun.userId == match.requesterUserId,
    'opponent_win' => ownRun.userId == match.opponentUserId,
    _ => null,
  };
}

List<DuelRun> _readRuns(Map<String, dynamic> json) {
  final raw = json['runs'] ?? json['entries'] ?? json['players'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => DuelRun.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

String _gameDisplayName(Map<String, dynamic> json, String gameId) {
  final serverName = _stringOrNull(
    json,
    'game_name',
    fallback: json['display_name'] ?? json['game_display_name'],
  );
  // Some snapshots only have game_id and the old UI used to expose that
  // identifier verbatim. Keep server-provided localized names, but provide a
  // local fallback when an older snapshot has no display_name field.
  if (serverName != null && serverName != gameId) return serverName;
  return _knownDuelGameNames[gameId] ?? gameId;
}

const _knownDuelGameNames = <String, String>{
  'dung_dodge_v2': '똥피하기',
  'gravity_switch': '중력 스위치',
  'apple_game_v2': '사과게임',
  'number_rush': '탭50',
  'mole_reaction': '두더지 반응속도',
  'mama_duck_trail': '엄마, 어디가',
  'ramen_timer': '30초 컵라면',
  'midnight_snake': '야식털이 뱀',
  'beat_the_dealer': '블랙잭',
  'ten_pitch_slugger': '홈런왕',
  'bathhouse_sort': '남탕! 여탕!',
  'lily_frog': '빙글개굴',
  'net_boat': '만선호',
  'temple_run': '집에 좀 가자',
  'wind_darts': '펍 다트',
  'western_duel': '딱 한 발만',
};

String _string(Map<String, dynamic> json, String key, {Object? fallback}) =>
    (json[key] ?? fallback)?.toString() ?? '';

String? _stringOrNull(
  Map<String, dynamic> json,
  String key, {
  Object? fallback,
}) {
  final value = json[key] ?? fallback;
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}

int? _integer(Map<String, dynamic> json, String key, {Object? fallback}) {
  final value = json[key] ?? fallback;
  return value is num ? value.toInt() : int.tryParse('$value');
}

bool? _boolean(Map<String, dynamic> json, String key, {Object? fallback}) {
  final value = json[key] ?? fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return switch (value.toLowerCase()) {
      'true' || '1' || 'yes' => true,
      'false' || '0' || 'no' => false,
      _ => null,
    };
  }
  return null;
}

DateTime? _dateTime(Map<String, dynamic> json, String key, {Object? fallback}) {
  final value = json[key] ?? fallback;
  if (value is DateTime) return value.toUtc();
  return value == null ? null : DateTime.tryParse('$value')?.toUtc();
}
