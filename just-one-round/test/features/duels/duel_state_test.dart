import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/duels/domain/duel_state.dart';

void main() {
  test('duel options clamp stake to the configured ten coin step', () {
    const options = DuelOptions(
      games: [],
      minStake: 10,
      maxStake: 200,
      stakeStep: 10,
      defaultStake: 100,
    );

    expect(options.clampStake(1), 10);
    expect(options.clampStake(109), 100);
    expect(options.clampStake(199), 190);
    expect(options.clampStake(900), 200);
  });

  test('parses a server-gated local duel test player', () {
    final player = DuelTestPlayer.fromJson({
      'user_id': 'test-opponent',
      'nickname': '시뮬 상대',
      'test_game_id': 'dung_dodge_v2',
    });

    expect(player.userId, 'test-opponent');
    expect(player.nickname, '시뮬 상대');
    expect(player.testGameId, 'dung_dodge_v2');
  });

  test('duel options never expose linked or excluded games', () {
    final options = DuelOptions.fromJson({
      'games': [
        {'game_id': 'number_rush', 'display_name': '탭50', 'game_version': 1},
        {'game_id': 'wind_darts', 'display_name': '펍다트', 'game_version': 1},
        {'game_id': 'western_duel', 'display_name': '딱한발만', 'game_version': 1},
      ],
    });

    expect(options.games.map((game) => game.id), ['number_rush']);
  });

  test(
    'duel match parses room and player state without exposing unknown data',
    () {
      final match = DuelMatch.fromJson({
        'id': 'match-1',
        'requester_id': 'user-a',
        'opponent_id': 'user-b',
        'game_id': 'number_rush',
        'game_name': '탭50',
        'game_version': 1,
        'stake': 30,
        'status': 'waiting',
        'created_at': '2026-11-01T00:00:00Z',
        'expires_at': '2026-11-01T00:10:00Z',
        'server_now': '2026-11-01T00:00:01Z',
        'runs': [
          {
            'user_id': 'user-a',
            'run_id': 'run-a',
            'joined': true,
            'loading_complete': true,
            'ready': true,
            'session_generation': 3,
            'seed': 123456,
          },
          {'user_id': 'user-b'},
        ],
      });

      expect(match.isWaiting, isTrue);
      expect(match.joinedCount, 1);
      expect(match.readyCount, 1);
      expect(match.runFor('user-a')?.runId, 'run-a');
      expect(match.runFor('user-a')?.challengeSeed, 123456);
      expect(match.runFor('user-b')?.joined, isFalse);
      expect(match.serverNow, DateTime.utc(2026, 11, 1, 0, 0, 1));
    },
  );

  test('uses a Korean local game name when a snapshot only has game_id', () {
    final match = DuelMatch.fromJson({
      'id': 'duel-legacy-name',
      'requester_id': 'requester',
      'opponent_id': 'opponent',
      'game_id': 'dung_dodge_v2',
      'game_version': 1,
      'stake': 100,
      'status': 'waiting',
      'created_at': '2026-11-02T00:00:00Z',
      'waiting_expires_at': '2026-11-02T00:10:00Z',
      'opponent_nickname': '도전자',
      'runs': const [],
    });

    expect(match.gameName, '똥피하기');
    expect(match.opponentNickname, '도전자');
  });

  test('terminal room states are not reopenable from the duel list', () {
    for (final status in [
      'settled',
      'declined',
      'cancelled',
      'expired',
      'voided',
    ]) {
      final match = DuelMatch.fromJson({
        'id': 'match-$status',
        'requester_id': 'user-a',
        'opponent_id': 'user-b',
        'game_id': 'number_rush',
        'stake': 10,
        'status': status,
        'created_at': '2026-11-01T00:00:00Z',
        'waiting_expires_at': '2026-11-01T00:10:00Z',
      });
      expect(match.isFinished, isTrue, reason: status);
    }
  });

  test('start failure metadata preserves insufficient coin reason', () {
    final match = DuelMatch.fromJson({
      'id': 'match-1',
      'requester_id': 'user-a',
      'opponent_id': 'user-b',
      'game_id': 'number_rush',
      'stake': 100,
      'status': 'waiting',
      'start_failed': true,
      'start_failure_reason': 'insufficient_coin_balance',
      'created_at': '2026-11-01T00:00:00Z',
      'waiting_expires_at': '2026-11-01T00:10:00Z',
    });
    expect(match.startFailed, isTrue);
    expect(match.startFailureReason, 'insufficient_coin_balance');
  });

  test('summarizes settled duel outcome, scores, and coin delta', () {
    final match = DuelMatch.fromJson({
      'id': 'settled-1',
      'requester_id': 'me',
      'opponent_id': 'other',
      'game_id': 'number_rush',
      'game_name': '탭50',
      'game_version': 1,
      'stake': 100,
      'status': 'settled',
      'outcome': 'requester_win',
      'winner_id': 'me',
      'created_at': '2026-11-02T00:00:00Z',
      'waiting_expires_at': '2026-11-02T00:10:00Z',
      'runs': [
        {'user_id': 'me', 'raw_score': 90},
        {'user_id': 'other', 'raw_score': 70},
      ],
    });

    final summary = duelResultSummary(match, 'me');
    expect(summary.outcomeLabel, '승리');
    expect(summary.ownScore, 90);
    expect(summary.opponentScore, 70);
    expect(summary.coinLabel, '200코인 수령 · 순이익 +100코인');
    expect(summary.viewerWon, isTrue);
  });

  test('summarizes a settled refund as a draw', () {
    final match = DuelMatch.fromJson({
      'id': 'settled-refund',
      'requester_id': 'me',
      'opponent_id': 'other',
      'game_id': 'number_rush',
      'game_version': 1,
      'stake': 30,
      'status': 'settled',
      'outcome': 'refund',
      'created_at': '2026-11-02T00:00:00Z',
      'waiting_expires_at': '2026-11-02T00:10:00Z',
      'runs': [
        {'user_id': 'me', 'raw_score': 0},
        {'user_id': 'other', 'raw_score': 0},
      ],
    });

    final summary = duelResultSummary(match, 'me');
    expect(summary.outcomeLabel, '무승부 · 환불');
    expect(summary.coinLabel, '30코인 환불 · 순이익 0코인');
    expect(summary.viewerWon, isNull);
  });

  test('summarizes a settled loss with an explicit coin loss', () {
    final match = DuelMatch.fromJson({
      'id': 'settled-loss',
      'requester_id': 'me',
      'opponent_id': 'other',
      'game_id': 'number_rush',
      'game_version': 1,
      'stake': 50,
      'status': 'settled',
      'outcome': 'opponent_win',
      'winner_id': 'other',
      'created_at': '2026-11-02T00:00:00Z',
      'waiting_expires_at': '2026-11-02T00:10:00Z',
      'runs': [
        {'user_id': 'me', 'raw_score': 40},
        {'user_id': 'other', 'raw_score': 80},
      ],
    });

    final summary = duelResultSummary(match, 'me');
    expect(summary.outcomeLabel, '패배');
    expect(summary.coinLabel, '0코인 수령 · 순손실 -50코인');
    expect(summary.viewerWon, isFalse);
  });
}
