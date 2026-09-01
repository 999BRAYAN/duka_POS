import 'dart:typed_data';

/// Every SQLite file starts with these 15 characters followed by a zero byte.
const _sqliteMagic = 'SQLite format 3';

/// Whether [bytes] begin with SQLite's file-header magic.
///
/// Checked before a restore so picking the wrong file fails loudly and early,
/// rather than after the live database has already been replaced. Platform
/// neutral (and so unit-testable) on purpose — the restore itself is web-only,
/// but this guard is the part that protects real data.
bool looksLikeSqliteFile(Uint8List bytes) {
  if (bytes.length < 16) return false;
  for (var i = 0; i < _sqliteMagic.length; i++) {
    if (bytes[i] != _sqliteMagic.codeUnitAt(i)) return false;
  }
  return bytes[15] == 0;
}

/// The `user_version` a SQLite file carries, which is where drift stores the
/// schema version — a 4-byte big-endian integer at offset 60 of the file
/// header. Reading it straight out of the bytes means a backup can be
/// checked for compatibility before anything is opened or replaced.
///
/// Returns null when [bytes] is too short to hold a header.
int? readSchemaVersion(Uint8List bytes) {
  if (bytes.length < 64) return null;
  return (bytes[60] << 24) | (bytes[61] << 16) | (bytes[62] << 8) | bytes[63];
}
