// Non-web platforms (native Android via dart:ffi) don't have a browser
// storage-eviction concept to opt out of, so this is a no-op.
Future<void> requestPersistentStorage() async {}
