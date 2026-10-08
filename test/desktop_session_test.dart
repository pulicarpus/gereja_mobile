import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/desktop_session.dart';

void main() {
  test('Desktop startup waits for restored user instead of initial null', () async {
    final events = StreamController<String?>();
    var finished = false;
    final restore = waitForDesktopSession(events.stream).then((user) {
      finished = true;
      return user;
    });
    events.add(null); // Initial Dart snapshot, before native cache loading.
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    events.add('saved-user'); // Credential Manager restoration completes.
    expect(await restore, 'saved-user');
    await events.close();
  });

  test('First launch or explicit logout resolves native signed-out state', () async {
    final result = await waitForDesktopSession(
      Stream<String?>.fromIterable([null, null]),
    );
    expect(result, isNull);
  });

  test('Native restore error is not silently treated as logout', () async {
    final events = StreamController<String?>();
    final restore = waitForDesktopSession(events.stream);
    final assertion = expectLater(restore, throwsStateError);
    events.add(null);
    events.addError(StateError('Native restore unavailable'));
    await assertion;
    await events.close();
  });
}
