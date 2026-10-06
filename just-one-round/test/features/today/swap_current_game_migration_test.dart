import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('현재 ramen v3만 사과게임 v1로 안전하게 교체한다', () {
    final migration = File(
      'supabase/migrations/20260928000200_swap_current_ramen_to_apple_game.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains('public.current_play_date()'));
    expect(sql, contains("scheduled_game.game_id = 'apple_game_v2'"));
    expect(sql, contains('scheduled_game.game_version = 1'));
    expect(sql, contains("target_game.is_active"));
    expect(sql, contains('target_game.version is distinct from 1'));
    expect(sql, contains("game_id = 'apple_game_v2'"));
    expect(sql, contains('version = 1'));
    expect(sql, contains("set game_id = 'apple_game_v2'"));
    expect(sql, contains("game_id = 'ramen_timer'"));
    expect(sql, contains('game_version = 3'));
    expect(sql, contains('rule snapshot is missing'));
    expect(sql, contains('Retry-safe no-op'));
    expect(sql, contains('Manual rollback path'));
    expect(sql, isNot(contains('update public.attempts')));
    expect(sql, isNot(contains('update public.scores')));
    expect(sql, isNot(contains('delete from public.daily_game_rotation_entries')));
  });
}
