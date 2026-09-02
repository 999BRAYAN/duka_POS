import 'dart:convert';

import 'package:duka_pos/core/export/csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildCsv', () {
    test('plain fields are written without quoting', () {
      final csv = buildCsv(
        ['Name', 'Qty'],
        [
          ['Soda', 5],
        ],
      );

      expect(csv, 'Name,Qty\nSoda,5\n');
    });

    test('a field containing a comma is quoted', () {
      final csv = buildCsv(
        ['Name'],
        [
          ['Elbow, 90deg'],
        ],
      );

      expect(csv, 'Name\n"Elbow, 90deg"\n');
    });

    test('a field containing a quote is quoted, with the quote doubled', () {
      final csv = buildCsv(
        ['Name'],
        [
          ['12" pipe'],
        ],
      );

      expect(csv, 'Name\n"12"" pipe"\n');
    });

    test('a field containing a newline is quoted', () {
      final csv = buildCsv(
        ['Notes'],
        [
          ['line one\nline two'],
        ],
      );

      expect(csv, 'Notes\n"line one\nline two"\n');
    });

    test('a null field becomes an empty field, not the text "null"', () {
      final csv = buildCsv(
        ['Value'],
        [
          [null],
        ],
      );

      expect(csv, 'Value\n\n');
    });
  });

  group('encodeCsvForExcel', () {
    test('prepends a UTF-8 byte-order mark before the encoded text', () {
      final bytes = encodeCsvForExcel('Name\nSoda\n');

      // EF BB BF is the UTF-8 encoding of U+FEFF, the byte-order mark.
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), 'Name\nSoda\n');
    });
  });
}
