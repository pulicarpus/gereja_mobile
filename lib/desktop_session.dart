/// Wait for the native Windows auth listener to load Credential Manager data.
/// FlutterFire 5.x first emits the Dart-side snapshot (initially null on
/// Windows), then emits the native result, including null for a signed-out user.
/// Call this immediately after Firebase initialization, before other consumers
/// initialize FirebaseAuth. Firebase itself owns persistence and token refresh.
Future<T?> waitForDesktopSession<T>(Stream<T?> authEvents) {
  return authEvents.skip(1).first;
}
