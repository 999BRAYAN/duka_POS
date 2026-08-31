// Requests upgraded ("persistent") storage from the host platform, so it's
// exempt from eviction under storage pressure. Only meaningful on web — see
// persistent_storage_web.dart for what it actually does there.
export 'persistent_storage_stub.dart'
    if (dart.library.js_interop) 'persistent_storage_web.dart';
