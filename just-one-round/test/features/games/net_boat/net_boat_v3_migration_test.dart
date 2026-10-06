import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Net Boat v3 migration publishes the five-minute validator contract',
    () {
      final sql = File(
        'supabase/migrations/20260908000100_net_boat_five_minute_v3.sql',
      ).readAsStringSync();

      expect(sql, contains("where id = 'net_boat'"));
      expect(sql, contains('version = 3'));
      expect(sql, contains('duration_seconds = 300'));
      expect(
        sql,
        contains("active_attempt.game_id is distinct from 'net_boat'"),
      );
      expect(sql, contains('active_attempt.game_version is distinct from 3'));
      expect(sql, contains('submit_daily_score_before_net_boat_v3'));
      expect(sql, isNot(contains('submit_daily_score_before_net_boat_v2')));
      expect(sql, contains('active_attempt.game_duration_seconds is null'));
      expect(sql, contains('active_attempt.game_duration_seconds <> 300'));
      expect(sql, contains('duration_ms not between 3000 and 300000'));
      expect(sql, contains('collisions = 0 and duration_ms <> 300000'));
      expect(sql, contains('collisions = 1 and duration_ms >= 300000'));
      expect(sql, contains('submitted_score not between 0 and 1000000'));
      expect(sql, contains('submitted_score % 10 <> 0'));

      for (final field in [
        'submitted_score',
        'stars_collected',
        'collisions',
        'duration_ms',
      ]) {
        expect(sql, contains('$field is null'));
      }

      final nullSafeValidation = sql.indexOf(
        'if active_attempt.game_duration_seconds is null',
      );
      final elapsedAssertion = sql.indexOf(
        'perform public.assert_score_submission_elapsed',
      );
      expect(nullSafeValidation, greaterThanOrEqualTo(0));
      expect(elapsedAssertion, greaterThan(nullSafeValidation));
    },
  );
}
