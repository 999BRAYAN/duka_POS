import 'dart:typed_data';

import 'package:duka_pos/core/backup/sqlite_file_header.dart';
import 'package:flutter_test/flutter_test.dart';

/// The guard that stands between "user picked the wrong file" and "the live
/// database is gone", so it's worth testing the near-misses, not just the
/// obvious pass/fail.
void main() {
  Uint8List headerOf(String text, {int totalLength = 64}) {
    final bytes = Uint8List(totalLength);
    for (var i = 0; i < text.length && i < totalLength; i++) {
      bytes[i] = text.codeUnitAt(i);
    }
    return bytes;
  }

  test('accepts a real SQLite header (15 chars then a zero byte)', () {
    expect(looksLikeSqliteFile(headerOf('SQLite format 3')), isTrue);
  });

  test('rejects a file whose 16th byte is not zero', () {
    // A space instead of the required NUL — the exact way this check is
    // easiest to get subtly wrong.
    final almost = headerOf('SQLite format 3');
    almost[15] = ' '.codeUnitAt(0);
    expect(looksLikeSqliteFile(almost), isFalse);
  });

  test('rejects a file that is too short to hold the header', () {
    expect(looksLikeSqliteFile(headerOf('SQLite format 3', totalLength: 15)), isFalse);
    expect(looksLikeSqliteFile(Uint8List(0)), isFalse);
  });

  test('rejects unrelated files', () {
    expect(looksLikeSqliteFile(headerOf('%PDF-1.7')), isFalse);
    expect(looksLikeSqliteFile(headerOf('{"not":"a database"}')), isFalse);
  });

  test('accepts the real backup bytes shape: header plus arbitrary page data', () {
    final withPages = headerOf('SQLite format 3', totalLength: 4096);
    for (var i = 16; i < withPages.length; i++) {
      withPages[i] = i % 256;
    }
    expect(looksLikeSqliteFile(withPages), isTrue);
  });
}
