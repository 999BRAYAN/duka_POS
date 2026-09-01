import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Period.today', () {
    test('spans just the reference date, start to end of day', () {
      final range = DateRange.forPeriod(Period.today, DateTime(2026, 3, 15, 14, 30, 45, 123));

      expect(range.start, DateTime(2026, 3, 15));
      expect(range.end, DateTime(2026, 3, 15, 23, 59, 59, 999));
    });
  });

  group('Period.week', () {
    test('a Monday reference starts its own week', () {
      final range = DateRange.forPeriod(Period.week, DateTime(2026, 3, 16, 9)); // a Monday

      expect(range.start, DateTime(2026, 3, 16));
      expect(range.end, DateTime(2026, 3, 22, 23, 59, 59, 999));
    });

    test('a Sunday belongs only to the week that just ended, not the next one too', () {
      final sunday = DateTime(2026, 3, 15, 18); // a Sunday
      final followingMonday = DateTime(2026, 3, 16, 9);

      final thisWeek = DateRange.forPeriod(Period.week, sunday);
      final nextWeek = DateRange.forPeriod(Period.week, followingMonday);

      expect(thisWeek.start, DateTime(2026, 3, 9));
      expect(thisWeek.end, DateTime(2026, 3, 15, 23, 59, 59, 999));
      expect(nextWeek.start, DateTime(2026, 3, 16));

      // No gap, no overlap: the millisecond right after one week ends is
      // exactly when the next one starts — the classic bug this exists to
      // prevent.
      expect(thisWeek.end.add(const Duration(milliseconds: 1)), nextWeek.start);
    });

    test('a mid-week reference still resolves to the same Monday-Sunday span', () {
      final range = DateRange.forPeriod(Period.week, DateTime(2026, 3, 12)); // a Thursday

      expect(range.start, DateTime(2026, 3, 9));
      expect(range.end, DateTime(2026, 3, 15, 23, 59, 59, 999));
    });
  });

  group('Period.month', () {
    test('a mid-month reference spans the 1st through the last day', () {
      final range = DateRange.forPeriod(Period.month, DateTime(2026, 4, 15));

      expect(range.start, DateTime(2026, 4, 1));
      expect(range.end, DateTime(2026, 4, 30, 23, 59, 59, 999));
    });

    test('rolls over correctly for a December reference, not spilling into January', () {
      final range = DateRange.forPeriod(Period.month, DateTime(2026, 12, 10));

      expect(range.start, DateTime(2026, 12, 1));
      expect(range.end, DateTime(2026, 12, 31, 23, 59, 59, 999));
    });

    test('resolves a leap February to the 29th', () {
      final range = DateRange.forPeriod(Period.month, DateTime(2028, 2, 10));
      expect(range.end, DateTime(2028, 2, 29, 23, 59, 59, 999));
    });

    test('resolves a non-leap February to the 28th', () {
      final range = DateRange.forPeriod(Period.month, DateTime(2026, 2, 10));
      expect(range.end, DateTime(2026, 2, 28, 23, 59, 59, 999));
    });
  });

  group('Period.year', () {
    test('spans January 1st through December 31st', () {
      final range = DateRange.forPeriod(Period.year, DateTime(2026, 6, 15));

      expect(range.start, DateTime(2026, 1, 1));
      expect(range.end, DateTime(2026, 12, 31, 23, 59, 59, 999));
    });
  });

  test('defaults to now when no reference is given', () {
    final range = DateRange.forPeriod(Period.today);
    final now = DateTime.now();

    expect(now.isBefore(range.start), isFalse);
    expect(now.isAfter(range.end), isFalse);
  });
}
