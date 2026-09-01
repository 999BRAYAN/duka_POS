/// A named span a report or the dashboard can be scoped to.
enum Period { today, week, month, year }

/// A period's boundaries, computed once here so every report and the
/// dashboard agree on exactly where one period ends and the next begins.
/// Two call sites independently rounding a boundary slightly differently
/// is how a Sunday's sales end up counted in both "this week" and "last
/// week" — [DateRange.forPeriod] is the single place that decision gets
/// made, so it only has to be made once.
class DateRange {
  const DateRange({required this.start, required this.end});

  /// Inclusive, at 00:00:00.000.
  final DateTime start;

  /// Inclusive, at 23:59:59.999 — not the next period's start minus
  /// nothing, and not midnight of the following day, both of which would
  /// either double-count or drop that last millisecond of the period.
  final DateTime end;

  /// [reference] anchors the period and defaults to [DateTime.now] — pass
  /// an explicit value in tests instead of depending on the real clock.
  ///
  /// Weeks run Monday through Sunday. That specific choice matters less
  /// than that every caller gets it from here rather than picking its own.
  factory DateRange.forPeriod(Period period, [DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final start = switch (period) {
      Period.today => today,
      Period.week => today.subtract(Duration(days: today.weekday - DateTime.monday)),
      Period.month => DateTime(today.year, today.month),
      Period.year => DateTime(today.year),
    };

    final end = switch (period) {
      Period.today => _endOfDay(today),
      Period.week => _endOfDay(start.add(const Duration(days: 6))),
      // Day 0 of next month is the last day of this one — Dart's DateTime
      // normalizes month 13 into January of the following year on its
      // own, so this rolls over a December reference correctly too.
      Period.month => _endOfDay(DateTime(today.year, today.month + 1, 0)),
      Period.year => _endOfDay(DateTime(today.year, 12, 31)),
    };

    return DateRange(start: start, end: end);
  }

  static DateTime _endOfDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
}
