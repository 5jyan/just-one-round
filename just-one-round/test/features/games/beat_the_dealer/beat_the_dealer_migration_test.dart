import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v4 schedules only future games and accepts the same score bounds', () {
    final sql = File(
      'supabase/migrations/20260923000100_blackjack_seventh_round_ace_v4.sql',
    ).readAsStringSync();
    expect(sql, contains('scheduled.play_date > public.current_play_date()'));
    expect(sql, contains('active_attempt.game_version is distinct from 4'));
    expect(sql, contains('raw_score not between 0 and 925'));
    expect(sql, contains('raw_score % 5 <> 0'));
  });

  test('v3 server migration validates the blackjack score contract', () {
    final migration = File(
      'supabase/migrations/20260731000200_beat_the_dealer_v3.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();
    expect(sql, contains("active_attempt.game_version <> 3"));
    expect(sql, contains('submitted_score not between 0 and 925'));
    expect(sql, contains('submitted_score % 5 <> 0'));
    expect(sql, contains("'beat_the_dealer'"));
  });

  test('player-facing game name is migrated to 블랙잭', () {
    final migration = File(
      'supabase/migrations/20260808001100_rename_beat_the_dealer_to_blackjack.sql',
    );
    expect(migration.existsSync(), isTrue);

    final sql = migration.readAsStringSync();
    expect(sql, contains("update public.game_rule_versions"));
    expect(sql, contains("update public.games"));
    expect(sql, contains("set display_name = '블랙잭'"));
    expect(sql, contains("where game_id = 'beat_the_dealer'"));
    expect(sql, contains("where id = 'beat_the_dealer'"));
  });
}
