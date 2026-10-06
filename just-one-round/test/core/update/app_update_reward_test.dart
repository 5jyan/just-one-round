import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/core/update/app_update_reward.dart';

void main() {
  test('parses a server-granted challenge ticket reward', () {
    final reward = AppUpdateReward.fromJson({
      'granted': true,
      'campaign_id': 'ios-build-23',
      'message': '새 버전 고마워요!',
      'tickets_granted': 1,
      'challenge_tickets': 4,
    });

    expect(reward.hasReward, isTrue);
    expect(reward.campaignId, 'ios-build-23');
    expect(reward.message, '새 버전 고마워요!');
    expect(reward.ticketsGranted, 1);
    expect(reward.challengeTickets, 4);
  });

  test('defaults an empty server response to no reward', () {
    final reward = AppUpdateReward.fromJson(const {});

    expect(reward.hasReward, isFalse);
    expect(reward.ticketsGranted, 0);
  });

  test('migration keeps the reward campaign disabled and server-authoritative', () {
    final sql = File(
      'supabase/migrations/20260915000100_forced_update_challenge_ticket_reward.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains('update_reward_enabled boolean not null default false'),
    );
    expect(sql, contains('create table public.app_update_reward_claims'));
    expect(sql, contains('create function public.observe_client_build'));
    expect(
      sql,
      contains('create or replace function public.get_client_compatibility'),
    );
    expect(sql, contains('create function public.claim_app_update_reward()'));
    expect(sql, contains('unique (user_id, campaign_id)'));
    expect(
      sql,
      contains(
        'grant execute on function public.claim_app_update_reward() to authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.set_app_update_reward_campaign',
      ),
    );
  });

  test(
    'release migration activates the build 22 campaign after store launch',
    () {
      final sql = File(
        'supabase/migrations/20260916000100_activate_build_22_forced_update_reward.sql',
      ).readAsStringSync();

      expect(
        sql,
        contains(
          'minimum_supported_build = greatest(minimum_supported_build, 22)',
        ),
      );
      expect(sql, contains('ios_minimum_supported_build'));
      expect(sql, contains('android_minimum_supported_build'));
      expect(sql, contains("'build-22-update-reward'"));
      expect(sql, contains("true,\n  'build-22-update-reward',\n  22"));
    },
  );

  test('approved build 25 becomes the forced-update and reward target', () {
    final sql = File(
      'supabase/migrations/20260925000100_activate_build_25_forced_update_reward.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains(
        'minimum_supported_build = greatest(minimum_supported_build, 25)',
      ),
    );
    expect(sql, contains("'build-25-update-reward'"));
    expect(sql, contains('update_reward_target_build = 25'));
    expect(sql, contains('update_reward_enabled = true'));
  });
}
