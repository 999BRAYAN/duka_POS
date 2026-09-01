import 'dart:io';

import 'package:drift/native.dart';
import 'package:duka_pos/core/backup/sqlite_file_header.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// The restore guard reads a backup's schema version straight out of the
/// SQLite header, on the assumption that drift writes `schemaVersion` into
/// `user_version`. That assumption is load-bearing — if it were wrong the
/// guard would compare against zero and never fire — so it is checked
/// against a real database file rather than a hand-built header.
void main() {
  test('a real drift database carries its schemaVersion in the file header', () async {
    final directory = await Directory.systemTemp.createTemp('duka_pos_header_test');
    addTearDown(() => directory.delete(recursive: true));

    final file = File('${directory.path}/duka_pos.sqlite');
    final db = DukaDatabase.forTesting(
      NativeDatabase(file, setup: enableForeignKeys),
    );

    // Force the schema to be created and the version stamped.
    await db.select(db.products).get();
    final expectedVersion = db.schemaVersion;
    await db.close();

    final bytes = await file.readAsBytes();

    expect(looksLikeSqliteFile(bytes), isTrue);
    expect(
      readSchemaVersion(bytes),
      expectedVersion,
      reason: 'the restore guard depends on this being the schema version',
    );
  });
}
