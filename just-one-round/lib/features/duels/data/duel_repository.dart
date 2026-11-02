import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_one_round/features/duels/domain/duel_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class DuelRepository {
  Future<DuelOptions> fetchDuelOptions();

  /// Returns local test opponents only when the server-side test gate allows
  /// it. Production/normal accounts receive an empty list.
  Future<List<DuelTestPlayer>> fetchDuelTestPlayers();

  Future<List<DuelMatch>> fetchDuels();

  Future<DuelMatch> fetchDuel(String matchId);

  Future<DuelMatch> createDuel({
    required String opponentUserId,
    required String gameId,
    required int gameVersion,
    required int stake,
    required String clientRequestId,
    String? clientRuntimeRevision,
  });

  Future<DuelMatch> joinDuel(
    String matchId, {
    String? deviceSessionId,
    String? clientRuntimeRevision,
  });

  Future<DuelMatch> heartbeatDuel({
    required String matchId,
    required String deviceSessionId,
  });

  Future<DuelMatch> setDuelReady({
    required String matchId,
    required bool ready,
    required bool loadingComplete,
    required String deviceSessionId,
    String? clientRuntimeRevision,
  });

  Future<DuelMatch> leaveDuel({
    required String matchId,
    required String deviceSessionId,
  });

  Future<void> submitDuelResult({
    required String matchId,
    required String runId,
    required String runToken,
    required int rawScore,
    required int durationMs,
    String resultKind = 'valid',
    int starsCollected = 0,
    int collisions = 0,
    List<int>? windDartsShotScores,
  });

  Future<void> forfeitDuel({
    required String matchId,
    required String runId,
    required String runToken,
    String reason = 'client_interrupted',
  });
}

class SupabaseDuelRepository implements DuelRepository {
  SupabaseDuelRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<DuelOptions> fetchDuelOptions() async {
    final response = await _client.rpc('get_duel_options');
    if (response is List) {
      return DuelOptions(
        games: response
            .whereType<Map>()
            .map(
              (item) =>
                  DuelGameOption.fromJson(Map<String, dynamic>.from(item)),
            )
            .where((game) => DuelOptions.isGameEligible(game.id))
            .toList(growable: false),
        minStake: 10,
        maxStake: 200,
        stakeStep: 10,
        defaultStake: 100,
      );
    }
    return DuelOptions.fromJson(_asMap(response));
  }

  @override
  Future<List<DuelTestPlayer>> fetchDuelTestPlayers() async {
    final response = await _client.rpc('get_duel_test_players');
    return _asList(response)
        .map(DuelTestPlayer.fromJson)
        .where((player) => player.userId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<DuelMatch>> fetchDuels() async {
    final response = await _client.rpc('get_duels');
    return _asList(
      response,
    ).map((item) => DuelMatch.fromJson(item)).toList(growable: false);
  }

  @override
  Future<DuelMatch> fetchDuel(String matchId) async {
    final response = await _client.rpc(
      'get_duel',
      params: {'target_duel_id': matchId},
    );
    return DuelMatch.fromJson(_asMap(response));
  }

  @override
  Future<DuelMatch> createDuel({
    required String opponentUserId,
    required String gameId,
    required int gameVersion,
    required int stake,
    required String clientRequestId,
    String? clientRuntimeRevision,
  }) async {
    final response = await _client.rpc(
      'create_duel',
      params: {
        'target_user_id': opponentUserId,
        'target_game_id': gameId,
        'target_game_version': gameVersion,
        'target_stake': stake,
        'target_request_id': clientRequestId,
        if (clientRuntimeRevision != null)
          'client_runtime_revision': clientRuntimeRevision,
      },
    );
    return DuelMatch.fromJson(_asMap(response));
  }

  @override
  Future<DuelMatch> joinDuel(
    String matchId, {
    String? deviceSessionId,
    String? clientRuntimeRevision,
  }) async {
    final response = await _client.rpc(
      'join_duel',
      params: {
        'target_duel_id': matchId,
        'device_session_id': deviceSessionId ?? createDuelRequestId(),
        if (clientRuntimeRevision != null)
          'client_runtime_revision': clientRuntimeRevision,
      },
    );
    return DuelMatch.fromJson(_asMap(response));
  }

  @override
  Future<DuelMatch> heartbeatDuel({
    required String matchId,
    required String deviceSessionId,
  }) async {
    final response = await _client.rpc(
      'heartbeat_duel',
      params: {'target_duel_id': matchId, 'device_session_id': deviceSessionId},
    );
    return DuelMatch.fromJson(_asMap(response));
  }

  @override
  Future<DuelMatch> setDuelReady({
    required String matchId,
    required bool ready,
    required bool loadingComplete,
    required String deviceSessionId,
    String? clientRuntimeRevision,
  }) async {
    final response = await _client.rpc(
      'set_duel_ready',
      params: {
        'target_duel_id': matchId,
        'desired_ready': ready,
        'is_loading_complete': loadingComplete,
        'device_session_id': deviceSessionId,
        if (clientRuntimeRevision != null)
          'client_runtime_revision': clientRuntimeRevision,
      },
    );
    return DuelMatch.fromJson(_asMap(response));
  }

  @override
  Future<DuelMatch> leaveDuel({
    required String matchId,
    required String deviceSessionId,
  }) async {
    final response = await _client.rpc(
      'leave_duel',
      params: {'target_duel_id': matchId, 'device_session_id': deviceSessionId},
    );
    return DuelMatch.fromJson(_asMap(response));
  }

  @override
  Future<void> submitDuelResult({
    required String matchId,
    required String runId,
    required String runToken,
    required int rawScore,
    required int durationMs,
    String resultKind = 'valid',
    int starsCollected = 0,
    int collisions = 0,
    List<int>? windDartsShotScores,
  }) async {
    await _client.rpc(
      'submit_duel_result',
      params: {
        'target_duel_id': matchId,
        'target_run_id': runId,
        'target_run_token': runToken,
        'submitted_score': rawScore,
        'submitted_duration_ms': durationMs,
        'target_result_kind': resultKind,
        'client_request_id': createDuelRequestId(),
      },
    );
  }

  @override
  Future<void> forfeitDuel({
    required String matchId,
    required String runId,
    required String runToken,
    String reason = 'client_interrupted',
  }) async {
    await _client.rpc(
      'forfeit_duel',
      params: {
        'target_duel_id': matchId,
        'target_run_id': runId,
        'target_run_token': runToken,
        'reason': reason,
      },
    );
  }
}

class NoopDuelRepository implements DuelRepository {
  const NoopDuelRepository();

  @override
  Future<DuelOptions> fetchDuelOptions() async => DuelOptions.defaults();

  @override
  Future<List<DuelTestPlayer>> fetchDuelTestPlayers() async => const [];

  @override
  Future<List<DuelMatch>> fetchDuels() async => const [];

  @override
  Future<DuelMatch> fetchDuel(String matchId) =>
      Future<DuelMatch>.error(StateError('대결 서버에 연결할 수 없어요.'));

  @override
  Future<DuelMatch> createDuel({
    required String opponentUserId,
    required String gameId,
    required int gameVersion,
    required int stake,
    required String clientRequestId,
    String? clientRuntimeRevision,
  }) => Future<DuelMatch>.error(StateError('대결 서버에 연결할 수 없어요.'));

  @override
  Future<DuelMatch> joinDuel(
    String matchId, {
    String? deviceSessionId,
    String? clientRuntimeRevision,
  }) => Future<DuelMatch>.error(StateError('대결 서버에 연결할 수 없어요.'));

  @override
  Future<DuelMatch> heartbeatDuel({
    required String matchId,
    required String deviceSessionId,
  }) => Future<DuelMatch>.error(StateError('대결 서버에 연결할 수 없어요.'));

  @override
  Future<DuelMatch> setDuelReady({
    required String matchId,
    required bool ready,
    required bool loadingComplete,
    required String deviceSessionId,
    String? clientRuntimeRevision,
  }) => Future<DuelMatch>.error(StateError('대결 서버에 연결할 수 없어요.'));

  @override
  Future<DuelMatch> leaveDuel({
    required String matchId,
    required String deviceSessionId,
  }) => Future<DuelMatch>.error(StateError('대결 서버에 연결할 수 없어요.'));

  @override
  Future<void> submitDuelResult({
    required String matchId,
    required String runId,
    required String runToken,
    required int rawScore,
    required int durationMs,
    String resultKind = 'valid',
    int starsCollected = 0,
    int collisions = 0,
    List<int>? windDartsShotScores,
  }) async {
    throw StateError('대결 서버에 연결할 수 없어요.');
  }

  @override
  Future<void> forfeitDuel({
    required String matchId,
    required String runId,
    required String runToken,
    String reason = 'client_interrupted',
  }) async {
    throw StateError('대결 서버에 연결할 수 없어요.');
  }
}

final duelRepositoryProvider = Provider<DuelRepository>((ref) {
  try {
    return SupabaseDuelRepository(Supabase.instance.client);
  } on Object {
    return const NoopDuelRepository();
  }
});

String createDuelRequestId({Random? random}) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  throw const FormatException('대결 서버 응답 형식이 올바르지 않아요.');
}

List<Map<String, dynamic>> _asList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
  if (value is Map) {
    final nested = value['duels'] ?? value['matches'] ?? value['items'];
    if (nested is List) return _asList(nested);
  }
  return const [];
}
