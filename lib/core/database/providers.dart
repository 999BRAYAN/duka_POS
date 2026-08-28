import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// The single, app-wide [DukaDatabase] instance. Opens lazily on first
/// read and is closed automatically when the provider is disposed.
final databaseProvider = Provider<DukaDatabase>((ref) {
  final db = DukaDatabase();
  ref.onDispose(db.close);
  return db;
});
