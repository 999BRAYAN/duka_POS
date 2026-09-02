import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [bytes] as a browser download named [filename] — the standard
/// "Blob + hidden anchor click" pattern, since there is no other way to
/// hand a Flutter-web app's in-memory bytes to the user as a file. Shared
/// by every export (reports, sale history, PDF, CSV) and by
/// core/backup/backup_web.dart, which used to carry its own copy of this
/// with the MIME type hardcoded to the database backup's own type.
void triggerBrowserDownload(
  Uint8List bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);

  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';

  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
