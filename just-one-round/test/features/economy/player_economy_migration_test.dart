import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('코인과 경험치를 서버 원장으로 지급하고 지출한다', () {
    final sql = File(
      'supabase/migrations/20260802000600_player_economy.sql',
    ).readAsStringSync();

    expect(sql, contains('coin_balance bigint not null default 0'));
    expect(sql, contains('experience_points bigint not null default 0'));
    expect(sql, contains('create table public.coin_transactions'));
    expect(sql, contains('coin_transactions_user_reference_idx'));
    expect(
      sql,
      contains('create or replace function public.apply_coin_transaction'),
    );
    expect(sql, contains('daily_result_reward_coins'));
    expect(
      File(
        'supabase/migrations/20260802000900_update_daily_reward_tiers.sql',
      ).readAsStringSync(),
      contains('if result_rank = 2 then return 80;'),
    );
    expect(
      File(
        'supabase/migrations/20260802000900_update_daily_reward_tiers.sql',
      ).readAsStringSync(),
      contains('if top_percent <= 70 then return 10;'),
    );
    expect(
      File(
        'supabase/migrations/20260802000900_update_daily_reward_tiers.sql',
      ).readAsStringSync(),
      contains('return 5;'),
    );
    expect(sql, contains('coins_granted'));
    expect(sql, contains('create function public.spend_coins'));
    expect(sql, contains('insufficient coin balance'));
    expect(
      sql,
      contains(
        'revoke update on public.profiles from public, anon, authenticated',
      ),
    );
    expect(
      sql,
      contains("'daily_result:' || target_date::text || ':' || target_game_id"),
    );
    expect(sql, contains('on conflict do nothing'));
  });
}
