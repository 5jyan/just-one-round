import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v3 server migration validates the blackjack score contract', () {
    final migration = File(
      'supabase/migrations/20260731000200_beat_the_dealer_v3.sql',
    );
    expect(migration.existsSync(), isTrue);
    final sql = migration.readAsStringSync();
    expect(sql, contains("active_attempt.game_version <> 3"));
    expect(sql, contains('submitted_score not between 0 and 925'));
    expect(sql, contains('submitted_score % 5 <> 0'));
    expect(sql, contains("'beat_the_dealer'"));
  });
}
