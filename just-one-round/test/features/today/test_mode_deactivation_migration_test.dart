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
}
