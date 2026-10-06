import 'package:just_one_round/features/history/domain/play_history_entry.dart';

int topPercentForRank({required int rank, required int participants}) {
  // Treat this as a percentile rank: first place is the best end of the
  // scale, while last place is the other end. Keep first place at 1% rather
  // than displaying an awkward 0% in the UI.
  if (rank <= 1 || participants <= 1) return 1;

  final percent = ((rank - 1) * 100 / (participants - 1)).ceil();
  return percent.clamp(1, 100).toInt();
}

int topPercentForEntry(PlayHistoryEntry entry) =>
    topPercentForRank(rank: entry.rank, participants: entry.participants);

int? averageTopPercent(Iterable<PlayHistoryEntry> history) {
  var total = 0;
  var count = 0;
  for (final entry in history) {
    final percent = topPercentForEntry(entry);
    total += percent;
    count++;
  }
  return count == 0 ? null : total ~/ count;
}

class RecentPercentileBucket {
  const RecentPercentileBucket({required this.date, this.topPercent});

  final DateTime date;
  final int? topPercent;
}

List<RecentPercentileBucket> recentPercentileBuckets(
  Iterable<PlayHistoryEntry> history,
  DateTime anchor,
) {
  final anchorDate = _calendarDate(anchor);
  final firstDate = anchorDate.subtract(const Duration(days: 6));
  final percentagesByDate = <DateTime, List<int>>{};

  for (final entry in history) {
    final date = _calendarDate(entry.playDate);
    if (date.isBefore(firstDate) || date.isAfter(anchorDate)) continue;

    final percent = topPercentForEntry(entry);
    percentagesByDate.putIfAbsent(date, () => []).add(percent);
  }

  return List<RecentPercentileBucket>.generate(7, (index) {
    final date = firstDate.add(Duration(days: index));
    final percentages = percentagesByDate[date];
    if (percentages == null) {
      return RecentPercentileBucket(date: date);
    }

    var total = 0;
    for (final percent in percentages) {
      total += percent;
    }
    return RecentPercentileBucket(
      date: date,
      topPercent: total ~/ percentages.length,
    );
  });
}

DateTime _calendarDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);
