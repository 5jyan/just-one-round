import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test mode deactivation migration clears tester-only profile flags', () {
    final migration = File(
      'supabase/migrations/20260802000500_deactivate_test_mode_gesture.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains('create function public.deactivate_test_mode()'));
    expect(sql, contains('is_test_account = false'));
    expect(sql, contains('test_game_id = null'));
    expect(
      sql,
      contains('revoke all on function public.deactivate_test_mode()'),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.deactivate_test_mode() to authenticated',
      ),
    );
  });

  test('test mode deactivation clears only unlinked test attempts', () {
    final migration = File(
      'supabase/migrations/'
      '20260813000100_clean_test_attempts_on_deactivation.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(
      sql,
      contains('create or replace function public.deactivate_test_mode()'),
    );
    expect(sql, contains('play_day date := public.current_play_date()'));
    expect(sql, contains('delete from public.attempts attempt'));
    expect(sql, contains('where session.attempt_id = attempt.id'));
    expect(sql, contains('is_test_account = false'));
    expect(sql, contains('test_game_id = null'));
  });

  test('existing normal-mode tester residue is repaired once', () {
    final migration = File(
      'supabase/migrations/'
      '20260813000200_clean_existing_test_attempt_residue.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains('delete from public.attempts attempt'));
    expect(sql, contains('using public.profiles profile'));
    expect(sql, contains('not coalesce(profile.is_test_account, false)'));
    expect(sql, contains('attempt.play_date = public.current_play_date()'));
    expect(sql, contains('where session.attempt_id = attempt.id'));
  });

  test('final test mode deactivation keeps device daily limits intact', () {
    final migration = File(
      'supabase/migrations/'
      '20260813000500_keep_device_claims_on_test_deactivation.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains('delete from public.attempts attempt'));
    expect(sql, isNot(contains('delete from public.device_daily_claims')));
    expect(sql, contains('is_test_account = false'));
  });
}
