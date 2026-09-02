import 'dart:typed_data';

import 'package:drift/wasm.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:web/web.dart' as web;

import '../database/connection/connection_web.dart' as connection;
import '../web/browser_download.dart';
import 'sqlite_file_header.dart';

final _fileStampFormat = DateFormat('yyyy-MM-dd_HHmmss');

Future<WasmProbeResult> _probe() {
  return WasmDatabase.probe(
    sqlite3Uri: connection.sqlite3Uri,
    driftWorkerUri: connection.driftWorkerUri,
    databaseName: connection.databaseName,
  );
}

ExistingDatabase? _findStoredDatabase(WasmProbeResult probed) {
  for (final db in probed.existingDatabases) {
    if (db.$2 == connection.databaseName) return db;
  }
  return null;
}

/// Reads the raw bytes of the stored `duka_pos` database out of whatever web
/// storage drift chose for it (OPFS or IndexedDB).
///
/// This re-probes the browser rather than reusing anything from
/// [connection.openConnection]'s original [WasmDatabaseResult], since that
/// result doesn't expose the storage handle needed to read the file back —
/// only [WasmProbeResult.exportDatabase] does, and finding out which
/// [WebStorageApi] the database actually lives under is exactly what
/// [WasmProbeResult.existingDatabases] is for.
Future<Uint8List> exportDatabaseBytes() async {
  final probed = await _probe();

  final existing = _findStoredDatabase(probed);
  if (existing == null) {
    throw StateError(
      'No stored "${connection.databaseName}" database found to back up.',
    );
  }

  final bytes = await probed.exportDatabase(existing);
  if (bytes == null) {
    throw StateError('Failed to read the "${connection.databaseName}" database.');
  }
  return bytes;
}

/// Exports the live database and immediately downloads it as
/// `duka_pos_backup_<timestamp>.db` — the single entry point the "Backup
/// now" button calls.
Future<void> downloadDatabaseBackup() async {
  final bytes = await exportDatabaseBytes();
  final filename = 'duka_pos_backup_${_fileStampFormat.format(DateTime.now())}.db';
  triggerBrowserDownload(bytes, filename, mimeType: 'application/x-sqlite3');
  _recordBackupTaken();
}

/// Where the last-backup timestamp lives.
///
/// localStorage rather than the database itself, deliberately: this records
/// when *this device* last wrote a backup file, and it must survive the
/// database being replaced by a restore. Storing it in the database would
/// mean a restored backup overwrote the fact that a backup had been taken.
const _lastBackupKey = 'duka_pos.last_backup_at';

void _recordBackupTaken() {
  try {
    web.window.localStorage.setItem(
      _lastBackupKey,
      DateTime.now().toIso8601String(),
    );
  } catch (_) {
    // Private browsing and blocked site data both throw here. Losing the
    // reminder is not a reason to fail a backup that already downloaded.
  }
}

/// When this device last downloaded a backup, or null if it never has (or
/// the browser will not let us remember).
DateTime? lastBackupAt() {
  try {
    final stored = web.window.localStorage.getItem(_lastBackupKey);
    return stored == null ? null : DateTime.tryParse(stored);
  } catch (_) {
    return null;
  }
}

/// What a restore attempt ended up doing, so the UI can tell "user changed
/// their mind" apart from "it worked" without treating a cancel as an error.
enum RestoreOutcome { cancelled, restored }

/// Thrown when a restore is abandoned *before* the live database is touched.
/// Every throw site below is deliberately on the safe side of that line: if
/// this is what comes back, the existing data is still intact.
class RestoreAbortedException implements Exception {
  RestoreAbortedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Replaces the live database with a previously-downloaded backup file.
///
/// Ordering here is the whole point, and it is deliberately paranoid:
///
///  1. Let the user pick a `.db` file (file_picker's web implementation is a
///     native file-input dialog, and hands back bytes directly — no path).
///  2. Sanity-check those bytes actually look like a SQLite file.
///  3. **Export the current database and download it first**, so a fresh
///     "state right before this restore" copy is sitting in Downloads even
///     if the restore turns out to have been a mistake. If that safety
///     export fails for any reason, the restore is abandoned here and the
///     live data is never touched.
///  4. Only then close the live connection, delete the stored database and
///     re-open it seeded from the uploaded bytes.
///  5. Reload the page, since every provider in the app is holding the old,
///     now-closed [connection.openConnection] executor.
///
/// [closeDatabase] must close the app's live [DukaDatabase]; drift can't
/// delete a database out from under an open connection.
Future<RestoreOutcome> restoreDatabaseFromPickedFile({
  required Future<void> Function() closeDatabase,
  required int currentSchemaVersion,
}) async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Choose a duka_pos backup',
    type: FileType.custom,
    allowedExtensions: ['db'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return RestoreOutcome.cancelled;

  final bytes = picked.files.single.bytes;
  if (bytes == null || bytes.isEmpty) {
    throw RestoreAbortedException('That file is empty — nothing was restored.');
  }

  await restoreDatabaseFromBytes(
    bytes,
    closeDatabase: closeDatabase,
    currentSchemaVersion: currentSchemaVersion,
  );
  return RestoreOutcome.restored;
}

/// Steps 2-5 above, given bytes from anywhere. Split out from
/// [restoreDatabaseFromPickedFile] so where the bytes came from stays
/// separate from what gets done with them.
Future<void> restoreDatabaseFromBytes(
  Uint8List bytes, {
  required Future<void> Function() closeDatabase,
  required int currentSchemaVersion,
}) async {
  if (!looksLikeSqliteFile(bytes)) {
    throw RestoreAbortedException(
      'That file is not a duka_pos backup — nothing was restored.',
    );
  }

  // A backup from a newer version of the app carries tables and columns this
  // build does not know about, and drift only migrates forwards. Restoring
  // it would leave a database the app cannot open — with the old data
  // already gone. Refuse while everything is still intact.
  final backupVersion = readSchemaVersion(bytes);
  if (backupVersion != null && backupVersion > currentSchemaVersion) {
    throw RestoreAbortedException(
      'That backup was made by a newer version of Duka POS. Update the app '
      'first — nothing was restored.',
    );
  }

  // The safety net. Anything that goes wrong here aborts the restore while
  // the live database is still untouched.
  try {
    await downloadDatabaseBackup();
  } catch (e) {
    throw RestoreAbortedException(
      'Could not save a safety backup first ($e) — nothing was restored.',
    );
  }

  // Past this line the live database is being replaced.
  await closeDatabase();

  final probed = await _probe();
  final existing = _findStoredDatabase(probed);
  if (existing != null) {
    await probed.deleteDatabase(existing);
  }

  // With the old database deleted, `initializeDatabase` is what seeds the
  // new one — this is drift's supported way to open a database from bytes.
  final restored = await connection.openWasmDatabase(
    initializeDatabase: () => bytes,
  );
  await restored.resolvedExecutor.close();

  web.window.location.reload();
}
