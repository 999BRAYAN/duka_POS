// Downloading arbitrary bytes as a file only makes sense on web (there is
// no "Downloads folder" concept inside a mobile/desktop app the same way) —
// same conditional-export shape as core/database/connection/connection.dart
// and core/backup/backup.dart.
export 'browser_download_stub.dart' if (dart.library.js_interop) 'browser_download_web.dart';
