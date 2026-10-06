import 'package:flutter_test/flutter_test.dart';
import 'package:just_one_round/features/history/domain/play_history_entry.dart';
import 'package:just_one_round/features/history/domain/play_history_statistics.dart';

PlayHistoryEntry _entry({
  required DateTime playDate,
  int rank = 1,
  int participants = 100,
}) {
  return PlayHistoryEntry(
    playDate: playDate,
    gameId: 'dung_dodge_v2',
    displayName: '똥피하기',
    score: 100,
    rank: rank,
    participants: participants,
  );
}

void main() {
  test('상위 퍼센트는 1위를 1%로 표시하고 순위 구간을 계산한다', () {
    expect(topPercentForRank(rank: 1, participants: 200), 1);
    expect(topPercentForRank(rank: 1, participants: 30), 1);
    expect(topPercentForRank(rank: 2, participants: 13), 9);
    expect(topPercentForRank(rank: 3, participants: 9), 25);
    expect(topPercentForRank(rank: 200, participants: 100), 100);
    expect(topPercentForRank(rank: 1, participants: 1), 1);
  });

  test('평균 성적은 참여자 수와 관계없이 모든 기록을 정수 나눗셈으로 평균 낸다', () {
    final history = [
      _entry(playDate: DateTime(2026, 8, 21), rank: 1, participants: 30),
      _entry(playDate: DateTime(2026, 8, 20), rank: 3, participants: 9),
      _entry(playDate: DateTime(2026, 8, 19), rank: 4, participants: 10),
    ];

    expect(averageTopPercent(history), 20);
  });

  test('최근 7일 버킷은 기록이 있는 날의 퍼센트와 결측을 보존한다', () {
    final history = [
      _entry(playDate: DateTime(2026, 8, 15), rank: 1, participants: 10),
      _entry(playDate: DateTime(2026, 8, 16), rank: 1, participants: 9),
      _entry(playDate: DateTime(2026, 8, 17), rank: 1, participants: 20),
      _entry(playDate: DateTime(2026, 8, 17), rank: 2, participants: 20),
      _entry(playDate: DateTime(2026, 8, 17), rank: 1, participants: 9),
      _entry(playDate: DateTime(2026, 8, 19), rank: 5, participants: 100),
      _entry(playDate: DateTime(2026, 8, 20), rank: 1, participants: 100),
      _entry(playDate: DateTime(2026, 8, 21), rank: 1, participants: 100),
      _entry(playDate: DateTime(2026, 8, 14), rank: 1, participants: 100),
    ];

    final buckets = recentPercentileBuckets(
      history,
      DateTime(2026, 8, 21, 23, 59),
    );

    expect(buckets, hasLength(7));
    expect(buckets.map((bucket) => bucket.date), [
      DateTime(2026, 8, 15),
      DateTime(2026, 8, 16),
      DateTime(2026, 8, 17),
      DateTime(2026, 8, 18),
      DateTime(2026, 8, 19),
      DateTime(2026, 8, 20),
      DateTime(2026, 8, 21),
    ]);
    expect(buckets.map((bucket) => bucket.topPercent), [
      1,
      1,
      2,
      null,
      5,
      1,
      1,
    ]);
  });
}
