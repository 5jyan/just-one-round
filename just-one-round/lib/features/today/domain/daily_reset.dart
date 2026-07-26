const dailyResetHourInSeoul = 6;
const previousDailyResultMinuteInSeoul = 10;
const _seoulUtcOffset = Duration(hours: 9);

DateTime dailyPlayDateAt(DateTime instant) {
  final shiftedSeoulTime = instant
      .toUtc()
      .add(_seoulUtcOffset)
      .subtract(const Duration(hours: dailyResetHourInSeoul));
  return DateTime(
    shiftedSeoulTime.year,
    shiftedSeoulTime.month,
    shiftedSeoulTime.day,
  );
}

Duration durationUntilNextDailyReset(DateTime instant) {
  final seoulTime = instant.toUtc().add(_seoulUtcOffset);
  var nextResetInSeoul = DateTime.utc(
    seoulTime.year,
    seoulTime.month,
    seoulTime.day,
    dailyResetHourInSeoul,
  );
  if (!nextResetInSeoul.isAfter(seoulTime)) {
    nextResetInSeoul = nextResetInSeoul.add(const Duration(days: 1));
  }
  return nextResetInSeoul.difference(seoulTime);
}

Duration durationUntilNextPreviousResultAvailability(DateTime instant) {
  final seoulTime = instant.toUtc().add(_seoulUtcOffset);
  var nextAvailabilityInSeoul = DateTime.utc(
    seoulTime.year,
    seoulTime.month,
    seoulTime.day,
    dailyResetHourInSeoul,
    previousDailyResultMinuteInSeoul,
  );
  if (!nextAvailabilityInSeoul.isAfter(seoulTime)) {
    nextAvailabilityInSeoul = nextAvailabilityInSeoul.add(
      const Duration(days: 1),
    );
  }
  return nextAvailabilityInSeoul.difference(seoulTime);
}

bool isSamePlayDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String playDateParameter(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
