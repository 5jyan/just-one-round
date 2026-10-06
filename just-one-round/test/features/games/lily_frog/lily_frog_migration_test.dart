import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빙글개굴 카탈로그와 점수 검증 계약을 함께 추가한다', () {
    final sql = File(
      'supabase/migrations/20260815000400_add_lily_frog.sql',
    ).readAsStringSync();

    expect(sql, contains("'lily_frog'"));
    expect(sql, contains("'빙글개굴'"));
    expect(sql, contains('game_version <> 1'));
    expect(sql, contains('game_duration_seconds <> 120'));
    expect(sql, contains('duration_ms not between 3000 and 120000'));
    expect(sql, contains('collisions not between 0 and 1'));
    expect(sql, contains('submitted_score not between 0 and 200000'));
    expect(sql, contains('submitted_score % 10 <> 0'));
    expect(sql, contains('submit_daily_score_before_lily_frog'));
  });

  test('빙글개굴 v2는 콤보 없이 300초 결과만 받는다', () {
    final sql = File(
      'supabase/migrations/20260815000550_update_lily_frog_300s.sql',
    ).readAsStringSync();

    expect(sql, contains("version = 2"));
    expect(sql, contains('duration_seconds = 300'));
    expect(sql, contains('game_version <> 2'));
    expect(sql, contains('game_duration_seconds <> 300'));
    expect(sql, contains('duration_ms not between 3000 and 300000'));
    expect(sql, contains('collisions = 0 and duration_ms <> 300000'));
    expect(sql, contains('submit_daily_score_before_lily_frog_v2'));
  });

  test('빙글개굴 v3는 착지 즉시 점프 규칙을 사용하는 300초 결과만 받는다', () {
    final sql = File(
      'supabase/migrations/20260907000400_update_lily_frog_instant_jump.sql',
    ).readAsStringSync();

    expect(sql, contains('version = 3'));
    expect(sql, contains('game_version <> 3'));
    expect(sql, contains('game_duration_seconds <> 300'));
    expect(sql, contains('duration_ms not between 3000 and 300000'));
    expect(sql, contains('submit_daily_score_before_lily_frog_v3'));
  });

  test('빙글개굴 v4는 150초 결과와 이전 시도 위임을 검증한다', () {
    final sql = File(
      'supabase/migrations/20260923000200_lily_frog_150s_v4.sql',
    ).readAsStringSync();

    expect(sql, contains('version = 4'));
    expect(sql, contains('duration_seconds = 150'));
    expect(sql, contains('game_version <> 4'));
    expect(sql, contains('game_duration_seconds <> 150'));
    expect(sql, contains('duration_ms not between 3000 and 150000'));
    expect(sql, contains('collisions = 0 and duration_ms <> 150000'));
    expect(sql, contains('collisions = 1 and duration_ms >= 150000'));
    expect(sql, contains('stars_collected not between 0 and 1000'));
    expect(sql, contains('submitted_score not between 0 and 200000'));
    expect(sql, contains('submitted_score % 10 <> 0'));
    expect(sql, contains('submitted_score < stars_collected * 30'));
    expect(sql, contains('submit_daily_score_before_lily_frog_v4'));
    expect(
      sql,
      contains('grant execute on function public.submit_daily_score'),
    );
  });

  test('빙글개굴 v5는 점수 규칙을 갱신하고 v4 시도를 이전 검증기로 위임한다', () {
    final sql = File(
      'supabase/migrations/20260923000300_lily_frog_scoring_v5.sql',
    ).readAsStringSync();

    expect(sql, contains('version = 5'));
    expect(sql, contains('duration_seconds = 150'));
    expect(sql, contains('set game_version = 5'));
    expect(sql, contains('scheduled.play_date > public.current_play_date()'));
    expect(sql, contains('game_version <> 5'));
    expect(sql, contains('game_duration_seconds <> 150'));
    expect(sql, contains('duration_ms not between 3000 and 150000'));
    expect(sql, contains('collisions = 0 and duration_ms <> 150000'));
    expect(sql, contains('collisions = 1 and duration_ms >= 150000'));
    expect(sql, contains('stars_collected not between 0 and 1000'));
    expect(sql, contains('submitted_score not between 0 and 200000'));
    expect(sql, contains('submitted_score % 10 <> 0'));
    expect(sql, contains('submitted_score < stars_collected * 100'));
    expect(sql, contains('submit_daily_score_before_lily_frog_v5'));
    expect(
      sql,
      contains('grant execute on function public.submit_daily_score'),
    );
  });
}
