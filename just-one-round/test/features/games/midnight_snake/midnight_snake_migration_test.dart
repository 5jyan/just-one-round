import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v3 score validation accepts the increased mouse score ceiling', () {
    final sql = File(
      'supabase/migrations/20261019000100_midnight_snake_mouse_score.sql',
    ).readAsStringSync();

    expect(sql, contains('active_attempt.game_version is distinct from 3'));
    expect(sql, contains('submitted_score not between 0 and 149'));
    expect(sql, isNot(contains('submitted_score not between 0 and 145')));
    expect(
      sql,
      contains('submit_daily_score_before_midnight_snake_mouse_score'),
    );
    expect(
      sql,
      contains(
        "to_regprocedure(\n    'public.submit_daily_score(uuid,integer,integer,integer,integer)'",
      ),
    );
    expect(
      sql,
      contains(
        "'public.submit_daily_score_before_midnight_snake_mouse_score(uuid,integer,integer,integer,integer)'",
      ),
    );
    expect(
      sql,
      contains(
        'rename to submit_daily_score_before_midnight_snake_mouse_score',
      ),
    );
    expect(sql, contains('from public, anon, authenticated'));
    expect(
      sql,
      isNot(contains('submit_daily_score_before_midnight_snake_repeat')),
    );
  });
}
