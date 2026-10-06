import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server migration validates the ten-pitch maximum distance contract', () {
    final migration = File(
      'supabase/migrations/20260808000700_ten_pitch_slugger_stronger_late_bonus_v7.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("'ten_pitch_slugger'"));
    expect(
      sql,
      contains("active_attempt.game_version not in (1, 2, 3, 4, 5, 6, 7)"),
    );
    expect(sql, contains('active_attempt.game_version in (2, 3, 4, 5, 6, 7)'));
    expect(sql, contains('submitted_score not between 0 and 15000'));
    expect(sql, contains('stars_collected + collisions <> 10'));
    expect(sql, contains('submitted_score < 3500'));
    expect(sql, contains('duration_ms not between 25000'));
    expect(sql, contains('active_attempt.game_duration_seconds'));
  });

  test('server copy renames the game to 홈런왕', () {
    final migration = File(
      'supabase/migrations/20260808001000_rename_ten_pitch_slugger.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("display_name = '홈런왕'"));
    expect(sql, contains("where game_id = 'ten_pitch_slugger'"));
    expect(sql, contains("where id = 'ten_pitch_slugger'"));
  });

  test('v8 migration raises only the new slugger score ceiling', () {
    final migration = File(
      'supabase/migrations/20260921000100_ten_pitch_slugger_stronger_batter_v8.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("'ten_pitch_slugger'"));
    expect(sql, contains("  8,"));
    expect(sql, contains('submitted_score not between 0 and 16875'));
    expect(sql, isNot(contains('submitted_score not between 0 and 16876')));
    expect(sql, contains('submit_daily_score_before_ten_pitch_slugger_v8'));
    expect(sql, contains('to_regprocedure'));
    expect(sql, contains('on conflict (id) do update'));
    expect(sql, contains('참조 중이 아닐 때에만'));
    expect(
      sql,
      contains(
        "if active_attempt.game_id is distinct from 'ten_pitch_slugger'",
      ),
    );
    expect(sql, contains('active_attempt.game_version is distinct from 8'));
    expect(
      sql,
      contains('return public.submit_daily_score_before_ten_pitch_slugger_v8'),
    );
  });

  test('v8 leaves the historical v1-v7 validator bound untouched', () {
    final previous = File(
      'supabase/migrations/20260808000700_ten_pitch_slugger_stronger_late_bonus_v7.sql',
    );
    final sql = previous.readAsStringSync();

    expect(
      sql,
      contains('active_attempt.game_version not in (1, 2, 3, 4, 5, 6, 7)'),
    );
    expect(sql, contains('submitted_score not between 0 and 15000'));
    expect(sql, contains('active_attempt.game_version in (2, 3, 4, 5, 6, 7)'));
  });

  test('v8 aligns only future slugger daily snapshots', () {
    final migration = File(
      'supabase/migrations/20260921000100_ten_pitch_slugger_stronger_batter_v8.sql',
    );
    final sql = migration.readAsStringSync();

    expect(sql, contains('update public.daily_games as scheduled'));
    expect(sql, contains('set game_version = catalog.version'));
    expect(sql, contains('scheduled.play_date > public.current_play_date()'));
    expect(sql, contains("scheduled.game_id = 'ten_pitch_slugger'"));
    expect(sql, contains('scheduled.game_id = catalog.id'));
    expect(sql, contains('and catalog.is_active'));
    expect(
      sql,
      isNot(contains('scheduled.play_date >= public.current_play_date()')),
    );
  });
}
