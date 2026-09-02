import 'dart:convert';
import 'dart:typed_data';

/// Encodes [headers] and [rows] as CSV text (RFC 4180 quoting): a field
/// containing a comma, a quote, or a newline is wrapped in quotes with any
/// internal quote doubled. Every other field is written as plain text, so a
/// spreadsheet reads a number as a number rather than as quoted text.
///
/// Values are stringified with [Object.toString]; format numbers as plain
/// decimals before passing them in (no thousands separators) — those read
/// as text once quoted, which defeats the point of exporting to a
/// spreadsheet. Formatted display strings belong in the PDF export instead.
String buildCsv(List<String> headers, Iterable<List<Object?>> rows) {
  final buffer = StringBuffer()..writeln(headers.map(_csvField).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(_csvField).join(','));
  }
  return buffer.toString();
}

/// Encodes CSV text as UTF-8 bytes for a file download, with a leading
/// byte-order mark. Excel on Windows guesses a CSV's encoding from its
/// first bytes rather than trusting UTF-8 by default, and without the BOM
/// it misreads anything outside plain ASCII (accented names, the £/€
/// signs) as the wrong codepage — the BOM is what tells it this file is
/// actually UTF-8.
Uint8List encodeCsvForExcel(String csv) => Uint8List.fromList(utf8.encode('﻿$csv'));

final _needsQuoting = RegExp(r'[",\r\n]');

String _csvField(Object? value) {
  final text = value?.toString() ?? '';
  if (_needsQuoting.hasMatch(text)) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}
