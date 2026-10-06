import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('두더지 반응속도 v1 migration은 게임·점수 경계를 함께 등록한다', () {
    final sql = File(
      'supabase/migrations/20260910000200_add_mole_reaction.sql',
    ).readAsStringSync();

    expect(sql, contains("'mole_reaction'"));
    expect(sql, contains('  version,'));
    expect(sql, contains('version = excluded.version'));
    expect(sql, contains('  duration_seconds,'));
    expect(sql, contains('  180,'));
    expect(sql, contains('active_attempt.game_id is distinct from'));
    expect(sql, contains('active_attempt.game_version is distinct from 1'));
    expect(sql, contains('stars_collected <> 0'));
    expect(sql, contains('duration_ms not between 1 and 180000'));
    expect(sql, contains('submitted_score not between 1 and 999989'));
    expect(sql, contains('submit_daily_score_before_mole_reaction'));
    expect(sql, contains('assert_score_submission_elapsed'));
  });

  test('미배포 7회 실험은 불변 v2로 승격되어 현재 규칙을 등록한다', () {
    final sql = File(
      'supabase/migrations/20260914000200_update_mole_reaction_event_count.sql',
    ).readAsStringSync();

    expect(sql, contains('version = 2'));
    expect(sql, contains('minimum_app_build = 25'));
    expect(sql, contains('준비 두더지 한 번 뒤 진짜 황금 두더지 한 마리'));
    expect(sql, contains('game_version < 2'));
    expect(sql, contains('submit_daily_score_before_mole_reaction_v2'));
    expect(sql, contains('active_attempt.game_version is distinct from 2'));
    expect(sql, contains('submitted_score not between 1 and 999998'));
  });

  test('후속 migration은 v2가 누락되면 중단하고 v1 metadata를 건드리지 않는다', () {
    final sql = File(
      'supabase/migrations/20260914000300_update_mole_reaction_to_one_warmup.sql',
    ).readAsStringSync();

    expect(sql, contains('version = 2'));
    expect(sql, contains('minimum_app_build = 25'));
    expect(
      sql,
      contains("raise exception 'mole reaction v2 rollout is missing'"),
    );
    expect(sql, isNot(contains('set description')));
  });
}
