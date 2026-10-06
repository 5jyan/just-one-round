import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버는 남탕 여탕 v1과 60초 점수 계약만 허용한다', () {
    final migration = File(
      'supabase/migrations/20260815000200_add_bathhouse_sort.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();

    expect(sql, contains("'bathhouse_sort'"));
    expect(sql, contains("'남탕! 여탕!'"));
    expect(sql, contains('active_attempt.game_version <> 1'));
    expect(sql, contains('active_attempt.game_duration_seconds <> 60'));
    expect(sql, contains('duration_ms <> 60000'));
    expect(sql, contains('submitted_score not between 0 and 1000000'));
    expect(sql, contains('submitted_score % 20 <> 0'));
    expect(sql, contains('collisions not between 0 and 172'));
    expect(sql, contains("raise exception 'invalid bathhouse sort result'"));
  });

  test('첫 등록은 개발자 검증용으로 일일 로테이션에서 비활성화한다', () {
    final sql = File(
      'supabase/migrations/20260815000200_add_bathhouse_sort.sql',
    ).readAsStringSync();

    expect(sql, contains("'남탕! 여탕!',"));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('드래그 큐 v2도 비활성 상태로 등록하고 새 오답 상한을 검증한다', () {
    final sql = File(
      'supabase/migrations/20260815000300_bathhouse_sort_drag_queue_v2.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  2,"));
    expect(sql, contains('active_attempt.game_version not in (1, 2)'));
    expect(sql, contains('active_attempt.game_version = 2'));
    expect(sql, contains('collisions between 0 and 241'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('동물 해금 v3도 기존 버전과 함께 점수 제출을 허용한다', () {
    final sql = File(
      'supabase/migrations/20260815000500_bathhouse_sort_species_unlock_v3.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  3,"));
    expect(sql, contains('active_attempt.game_version not in (1, 2, 3)'));
    expect(sql, contains('active_attempt.game_version in (2, 3)'));
    expect(sql, contains('collisions between 0 and 241'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('탭 전용·색상 구분 v4도 기존 버전과 함께 점수 제출을 허용한다', () {
    final sql = File(
      'supabase/migrations/20260815000600_bathhouse_sort_tap_red_v4.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  4,"));
    expect(sql, contains('active_attempt.game_version not in (1, 2, 3, 4)'));
    expect(sql, contains('active_attempt.game_version in (2, 3, 4)'));
    expect(sql, contains('collisions between 0 and 241'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('세로 얼굴표·예약 입력 v5도 기존 버전과 함께 점수 제출을 허용한다', () {
    final sql = File(
      'supabase/migrations/20260815000700_bathhouse_sort_buffered_roster_v5.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  5,"));
    expect(sql, contains('active_attempt.game_version not in (1, 2, 3, 4, 5)'));
    expect(sql, contains('active_attempt.game_version in (2, 3, 4, 5)'));
    expect(sql, contains('collisions between 0 and 241'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('콤보 점수·성공 이펙트 v6도 기존 버전과 함께 점수 제출을 허용한다', () {
    final sql = File(
      'supabase/migrations/20260815001000_bathhouse_sort_combo_fx_v6.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  6,"));
    expect(
      sql,
      contains('active_attempt.game_version not in (1, 2, 3, 4, 5, 6)'),
    );
    expect(sql, contains('active_attempt.game_version in (2, 3, 4, 5, 6)'));
    expect(sql, contains('collisions between 0 and 241'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('매 콤보 10점 상승 v7은 10점 단위 점수를 허용한다', () {
    final sql = File(
      'supabase/migrations/20260815001100_bathhouse_sort_rising_combo_v7.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  7,"));
    expect(
      sql,
      contains('active_attempt.game_version not in (1, 2, 3, 4, 5, 6, 7)'),
    );
    expect(sql, contains('active_attempt.game_version = 7'));
    expect(sql, contains('submitted_score % 10 = 0'));
    expect(sql, contains('submitted_score % 20 = 0'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('반응형 7명 큐 v8도 기존 점수 계약과 함께 제출을 허용한다', () {
    final sql = File(
      'supabase/migrations/20260815001200_bathhouse_sort_adaptive_queue_v8.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  8,"));
    expect(
      sql,
      contains('active_attempt.game_version not in (1, 2, 3, 4, 5, 6, 7, 8)'),
    );
    expect(sql, contains('active_attempt.game_version in (7, 8)'));
    expect(sql, contains('submitted_score % 10 = 0'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('초고속 연타 v9도 기존 점수 계약과 함께 제출을 허용한다', () {
    final sql = File(
      'supabase/migrations/20260815001300_bathhouse_sort_rapid_tap_v9.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  9,"));
    expect(
      sql,
      contains(
        'active_attempt.game_version not in (1, 2, 3, 4, 5, 6, 7, 8, 9)',
      ),
    );
    expect(sql, contains('active_attempt.game_version in (7, 8, 9)'));
    expect(sql, contains('submitted_score % 10 = 0'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('버튼 확대 v10도 기존 점수 계약과 함께 제출을 허용한다', () {
    final sql = File(
      'supabase/migrations/20260816000100_bathhouse_sort_taller_buttons_v10.sql',
    ).readAsStringSync();

    expect(sql, contains("'bathhouse_sort',\n  10,"));
    expect(
      sql,
      contains(
        'active_attempt.game_version not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)',
      ),
    );
    expect(sql, contains('active_attempt.game_version in (7, 8, 9, 10)'));
    expect(sql, contains('submitted_score % 10 = 0'));
    expect(sql, contains("60,\n  false,\n  13"));
  });

  test('콤보 상한 v11은 50콤보 규칙의 점수 제출을 허용한다', () {
    final sql = File(
      'supabase/migrations/20260907000300_bathhouse_sort_max_combo_v11.sql',
    ).readAsStringSync();

    expect(sql, contains('version = 11'));
    expect(
      sql,
      contains(
        'active_attempt.game_version not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)',
      ),
    );
    expect(sql, contains('active_attempt.game_version in (7, 8, 9, 10, 11)'));
    expect(sql, contains('combo counter is capped at 50'));
  });
}
