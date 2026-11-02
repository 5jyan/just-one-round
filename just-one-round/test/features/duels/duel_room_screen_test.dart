import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/duels/data/duel_repository.dart';
import 'package:just_one_round/features/duels/domain/duel_state.dart';
import 'package:just_one_round/features/duels/presentation/duel_room_screen.dart';

void main() {
  testWidgets('read-only settled room never joins or starts another run', (
    tester,
  ) async {
    final repository = _SettledDuelRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [duelRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: DuelRoomScreen(
            matchId: 'settled-1',
            currentUserId: 'me',
            readOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('대결 결과'), findsOneWidget);
    expect(find.text('승리'), findsOneWidget);
    expect(find.text('내 점수'), findsOneWidget);
    expect(find.text('3.53초'), findsOneWidget);
    expect(find.text('상대 점수'), findsOneWidget);
    expect(find.text('1.00초'), findsOneWidget);
    expect(find.text('200코인 수령 · 순이익 +100코인'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('기권'), findsOneWidget);
    expect(repository.joinCalls, 0);
    expect(repository.heartbeatCalls, 0);
    expect(repository.readyCalls, 0);
  });
}

class _SettledDuelRepository extends NoopDuelRepository {
  int joinCalls = 0;
  int heartbeatCalls = 0;
  int readyCalls = 0;

  @override
  Future<DuelMatch> fetchDuel(String matchId) async => DuelMatch.fromJson({
    'id': matchId,
    'requester_id': 'me',
    'opponent_id': 'other',
    'game_id': 'dung_dodge_v2',
    'game_name': '똥피하기',
    'game_version': 1,
    'stake': 100,
    'status': 'settled',
    'outcome': 'requester_win',
    'winner_id': 'me',
    'created_at': '2026-11-02T00:00:00Z',
    'waiting_expires_at': '2026-11-02T00:10:00Z',
    'runs': [
      {
        'user_id': 'me',
        'nickname': '나',
        'raw_score': 3533,
        'run_status': 'submitted',
        'joined': true,
      },
      {
        'user_id': 'other',
        'nickname': '상대',
        'raw_score': 1000,
        'run_status': 'forfeited',
        'joined': true,
      },
    ],
  });

  @override
  Future<DuelMatch> joinDuel(
    String matchId, {
    String? deviceSessionId,
    String? clientRuntimeRevision,
  }) async {
    joinCalls++;
    return fetchDuel(matchId);
  }

  @override
  Future<DuelMatch> heartbeatDuel({
    required String matchId,
    required String deviceSessionId,
  }) async {
    heartbeatCalls++;
    return fetchDuel(matchId);
  }

  @override
  Future<DuelMatch> setDuelReady({
    required String matchId,
    required bool ready,
    required bool loadingComplete,
    required String deviceSessionId,
    String? clientRuntimeRevision,
  }) async {
    readyCalls++;
    return fetchDuel(matchId);
  }
}
