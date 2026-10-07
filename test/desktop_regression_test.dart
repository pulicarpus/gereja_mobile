import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/desktop_google_login.dart';
import '../lib/mobile_notifications.dart';

void main() {
  test('SQLite FFI opens bundled Bible read-only on Windows and preserves source', () async {
    sqfliteFfiInit();
    final file = File('assets/TB.SQLite3');
    final before = await file.length();
    final db = await databaseFactoryFfi.openDatabase(file.absolute.path,
      options: OpenDatabaseOptions(readOnly: true));
    try {
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      expect(tables, isNotEmpty);
      final table = tables.first['name'] as String;
      expect(await db.rawQuery('SELECT COUNT(*) AS total FROM "$table"'), isNotEmpty);
    } finally { await db.close(); }
    expect(await file.length(), before);
  });
  test('desktop mobile push calls do not require unsupported plugins', () {
    if (Platform.isWindows || Platform.isLinux) {
      expect(MobilePush.supported, isFalse);
      MobilePush.login('fixture'); MobilePush.tag('role', 'user'); MobilePush.logout();
    }
  });
  test('browser login rejects forged callback then exchanges valid PKCE code', () async {
    final login = DesktopGoogleLogin();
    Uri? authorize;
    final client = MockClient((request) async {
      final body = Uri.splitQueryString(request.body);
      expect(body['code'], 'fixture-code');
      expect(DesktopGoogleLogin.challenge(body['code_verifier']!), authorize!.queryParameters['code_challenge']);
      expect(body['redirect_uri'], authorize!.queryParameters['redirect_uri']);
      final claims = {'aud': 'fixture.apps.googleusercontent.com',
        'nonce': authorize!.queryParameters['nonce'], 'iss': 'https://accounts.google.com',
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60};
      final token = 'header.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.signature';
      return http.Response(jsonEncode({'id_token': token, 'access_token': 'fixture-access'}), 200);
    });
    final tokens = await login.signIn(clientId: 'fixture.apps.googleusercontent.com', client: client,
      openBrowser: (url) async {
        authorize = url;
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        final forged = await http.get(redirect.replace(queryParameters: {'state':'wrong', 'code':'forged'}));
        expect(forged.statusCode, 400);
        final valid = await http.get(redirect.replace(queryParameters: {'state':url.queryParameters['state']!, 'code':'fixture-code'}));
        expect(valid.statusCode, 200);
        return true;
      });
    expect(tokens.accessToken, 'fixture-access'); client.close();
  });
  test('browser refusal and cancelled login release listener for retry', () async {
    final login = DesktopGoogleLogin();
    await expectLater(login.signIn(clientId: 'fixture', openBrowser: (_) async => false), throwsStateError);
    await expectLater(login.signIn(clientId: 'fixture', openBrowser: (_) async { login.cancel(); return true; }), throwsStateError);
    await expectLater(login.signIn(clientId: 'fixture', timeout: const Duration(milliseconds: 50), openBrowser: (_) async => true), throwsA(isA<Exception>()));
  });
  test('OAuth token nonce mismatch is rejected before Firebase sign-in', () async {
    final login = DesktopGoogleLogin();
    final client = MockClient((request) async {
      final claims = {'aud':'fixture', 'nonce':'wrong', 'iss':'https://accounts.google.com',
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60};
      return http.Response(jsonEncode({'id_token':'h.${base64Url.encode(utf8.encode(jsonEncode(claims)))}.s', 'access_token':'fixture'}), 200);
    });
    await expectLater(login.signIn(clientId:'fixture', client:client, openBrowser:(url) async {
      await http.get(Uri.parse(url.queryParameters['redirect_uri']!).replace(queryParameters:{'state':url.queryParameters['state']!, 'code':'fixture'}));
      return true;
    }), throwsStateError);
    client.close();
  });
}
