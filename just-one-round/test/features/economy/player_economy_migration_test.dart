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
    final currentRewardSql = File(
      'supabase/migrations/20260822000300_daily_reward_base_and_bonuses.sql',
    ).readAsStringSync();
    expect(currentRewardSql, contains('ranking_bonus := 100;'));
    expect(currentRewardSql, contains('ranking_bonus := 80;'));
    expect(currentRewardSql, contains('ranking_bonus := 60;'));
    expect(currentRewardSql, contains('ranking_bonus := 40;'));
    expect(currentRewardSql, contains('ranking_bonus := 20;'));
    expect(currentRewardSql, contains('ranking_bonus := 10;'));
    expect(currentRewardSql, contains('return 30 + ranking_bonus;'));
    final firstPlaceRewardSql = File(
      'supabase/migrations/20260907000100_update_first_place_daily_reward.sql',
    ).readAsStringSync();
    expect(firstPlaceRewardSql, contains('ranking_bonus := 250;'));
    expect(firstPlaceRewardSql, contains('return 30 + ranking_bonus;'));
    final latestRewardSql = File(
      'supabase/migrations/20260907000200_update_daily_reward_tiers.sql',
    ).readAsStringSync();
    expect(latestRewardSql, contains('ranking_bonus := 250;'));
    expect(latestRewardSql, contains('ranking_bonus := 120;'));
    expect(latestRewardSql, contains('ranking_bonus := 80;'));
    expect(latestRewardSql, contains('ranking_bonus := 50;'));
    expect(latestRewardSql, contains('ranking_bonus := 20;'));
    expect(latestRewardSql, contains('ranking_bonus := 0;'));
    expect(latestRewardSql, contains('return 30 + ranking_bonus;'));
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
