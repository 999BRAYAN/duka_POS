import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

// Browsers can silently evict "best-effort" origin storage (which is what
// our IndexedDB/OPFS-backed sqlite database uses by default) under disk
// pressure — persistent mode is exempt from that. navigator.storage.persist()
// is the only way to ask for it; whether it's granted is entirely up to the
// browser's own heuristics (e.g. Chrome largely bases it on site engagement)
// with no user prompt in most browsers, so there's nothing for us to drive
// here beyond asking and recording what came back.
Future<void> requestPersistentStorage() async {
  try {
    final granted = (await web.window.navigator.storage.persist().toDart).toDart;
    debugPrint(
      'duka_pos: persistent storage ${granted ? 'granted' : 'denied'} by browser',
    );
  } catch (e) {
    debugPrint('duka_pos: persistent storage request failed: $e');
  }
}
