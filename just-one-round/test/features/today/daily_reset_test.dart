import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/today/domain/daily_reset.dart';

void main() {
  test('서울 오전 6시 직전에 전날 플레이 날짜를 반환한다', () {
    final instant = DateTime.parse('2026-07-26T20:59:59Z');

    expect(dailyPlayDateAt(instant), DateTime(2026, 7, 26));
    expect(durationUntilNextDailyReset(instant), const Duration(seconds: 1));
  });

  test('서울 오전 6시부터 새 플레이 날짜를 반환한다', () {
    final instant = DateTime.parse('2026-07-26T21:00:00Z');

    expect(dailyPlayDateAt(instant), DateTime(2026, 7, 27));
    expect(durationUntilNextDailyReset(instant), const Duration(days: 1));
  });

  test('기기 시간대와 관계없이 서울 시간을 기준으로 계산한다', () {
    final instant = DateTime.parse('2026-07-27T05:59:59+09:00');

    expect(dailyPlayDateAt(instant), DateTime(2026, 7, 26));
    expect(playDateParameter(DateTime(2026, 7, 6)), '2026-07-06');
  });

  test('오전 6시 10분 전에는 전날 결과 공개 시각까지 계산한다', () {
    final instant = DateTime.parse('2026-07-26T21:09:59Z');

    expect(
      durationUntilNextPreviousResultAvailability(instant),
      const Duration(seconds: 1),
    );
  });

  test('오전 6시 10분부터는 다음 날 결과 공개 시각을 계산한다', () {
    final instant = DateTime.parse('2026-07-26T21:10:00Z');

    expect(
      durationUntilNextPreviousResultAvailability(instant),
      const Duration(days: 1),
    );
  });

  test('랭킹 표시 날짜보다 실제 플레이 날짜를 우선해 지난 날짜를 정한다', () {
    final now = DateTime.parse('2026-07-26T21:05:00Z');

    expect(
      previousDailyPlayDate(DateTime(2026, 7, 28), now: now),
      DateTime(2026, 7, 26),
    );
    expect(
      previousDailyPlayDate(DateTime(2026, 7, 25), now: now),
      DateTime(2026, 7, 24),
    );
  });

  test('전날 결과는 서울 오전 6시 10분에 공개된다', () {
    final playDate = DateTime(2026, 7, 26);

    expect(
      isDailyResultAvailable(
        playDate,
        now: DateTime.parse('2026-07-26T21:09:59Z'),
      ),
      isFalse,
    );
    expect(
      isDailyResultAvailable(
        playDate,
        now: DateTime.parse('2026-07-26T21:10:00Z'),
      ),
      isTrue,
    );
  });
}
