import 'dart:typed_data';

/// Non-web fallback — see browser_download.dart. Android has no export UI
/// wired up (see project notes on it being unmaintained/secondary), so this
/// only exists to keep a non-web build compiling if it's ever reached.
void triggerBrowserDownload(
  Uint8List bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('Downloading files is only supported on web.');
}
