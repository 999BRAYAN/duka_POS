import 'dart:typed_data';

// Non-web platforms (native Android via dart:ffi) store the database as a
// plain file on disk already — there's no browser download/upload flow to
// drive, so backup and restore are web-only for now.
const _unsupported = 'Database backup is only supported on web.';

Future<Uint8List> exportDatabaseBytes() => throw UnsupportedError(_unsupported);

void triggerBrowserDownload(Uint8List bytes, String filename) =>
    throw UnsupportedError(_unsupported);

Future<void> downloadDatabaseBackup() => throw UnsupportedError(_unsupported);

enum RestoreOutcome { cancelled, restored }

class RestoreAbortedException implements Exception {
  RestoreAbortedException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<RestoreOutcome> restoreDatabaseFromPickedFile({
  required Future<void> Function() closeDatabase,
  required int currentSchemaVersion,
}) => throw UnsupportedError(_unsupported);

Future<void> restoreDatabaseFromBytes(
  Uint8List bytes, {
  required Future<void> Function() closeDatabase,
  required int currentSchemaVersion,
}) => throw UnsupportedError(_unsupported);

DateTime? lastBackupAt() => null;
