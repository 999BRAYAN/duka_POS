import 'package:sqlite3/common.dart';

// SQLite has foreign key enforcement off by default. It must be set via
// setup on the raw connection (outside any transaction) - setting it in
// MigrationStrategy.beforeOpen via customStatement is silently ineffective.
// CommonDatabase covers both the native (dart:ffi) and web (wasm) database
// types, so this one function works as the setup callback for both.
void enableForeignKeys(CommonDatabase database) {
  database.execute('PRAGMA foreign_keys = ON');
}
