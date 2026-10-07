import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class DesktopGoogleTokens {
  final String idToken, accessToken;
  const DesktopGoogleTokens(this.idToken, this.accessToken);
}

class DesktopGoogleLogin {
  HttpServer? _server;
  Completer<Uri>? _callback;
  bool _running = false;

  static Future<Map<String, String>> readConfig(String projectId) async {
    final file = File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}oauth-desktop.json');
    if (!await file.exists()) {
      throw StateError('Login Windows belum dikonfigurasi. Letakkan file OAuth Desktop bernama oauth-desktop.json di folder aplikasi. Alkitab lokal tetap bisa dibuka.');
    }
    final raw = jsonDecode(await file.readAsString());
    final installed = raw is Map ? raw['installed'] : null;
    if (installed is! Map || installed['client_id'] is! String ||
        !(installed['client_id'] as String).endsWith('.apps.googleusercontent.com') ||
        (installed['project_id'] != null && installed['project_id'] != projectId)) {
      throw StateError('Gunakan konfigurasi OAuth jenis Desktop dari proyek aplikasi yang sama.');
    }
    return {'client_id': installed['client_id'] as String,
      if (installed['client_secret'] is String) 'client_secret': installed['client_secret'] as String};
  }

  static String _random() => base64Url.encode(List.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
  static String challenge(String verifier) => base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

  Future<DesktopGoogleTokens> signIn({required String clientId, String? clientSecret,
      Future<bool> Function(Uri)? openBrowser, http.Client? client,
      Duration timeout = const Duration(minutes: 3)}) async {
    if (_running) throw StateError('Login sedang berlangsung.');
    _running = true;
    final transport = client ?? http.Client();
    StreamSubscription<HttpRequest>? subscription;
    try {
      final verifier = _random(), state = _random(), nonce = _random();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      final callback = Completer<Uri>();
      _callback = callback;
      // Attach error handling before any callback/cancel can complete the future.
      final responseFuture = callback.future.timeout(timeout);
      responseFuture.ignore();
      final redirect = Uri(scheme: 'http', host: '127.0.0.1', port: server.port, path: '/oauth2callback');
      subscription = server.listen((request) async {
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('Content-Security-Policy', "default-src 'none'");
        if (request.method != 'GET' || request.uri.path != redirect.path ||
            request.uri.queryParameters['state'] != state || callback.isCompleted) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Permintaan tidak valid.');
        } else {
          request.response.write('Silakan kembali ke aplikasi GKII Mobile.');
          callback.complete(request.uri);
        }
        await request.response.close();
      }, onError: (Object error) {
        if (!callback.isCompleted) callback.completeError(StateError('Login browser terputus. Coba lagi.'));
      });
      final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId, 'redirect_uri': redirect.toString(),
        'response_type': 'code', 'scope': 'openid email profile',
        'state': state, 'nonce': nonce, 'code_challenge': challenge(verifier),
        'code_challenge_method': 'S256', 'prompt': 'select_account',
      });
      final opened = await (openBrowser?.call(uri) ?? launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened && !callback.isCompleted) callback.completeError(StateError('Browser tidak dapat dibuka.'));
      final response = await responseFuture;
      if (response.queryParameters.containsKey('error')) throw StateError('Login dibatalkan atau ditolak oleh Google.');
      final code = response.queryParameters['code'];
      if (code == null || code.isEmpty) throw StateError('Kode login tidak tersedia. Coba lagi.');
      final tokenResponse = await transport.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'client_id': clientId, if (clientSecret != null && clientSecret.isNotEmpty) 'client_secret': clientSecret,
        'code': code, 'code_verifier': verifier, 'grant_type': 'authorization_code',
        'redirect_uri': redirect.toString(),
      }).timeout(const Duration(seconds: 30));
      if (tokenResponse.statusCode != 200) throw StateError('Google belum dapat menyelesaikan login. Periksa konfigurasi Desktop atau coba kembali.');
      final tokens = jsonDecode(tokenResponse.body);
      if (tokens is! Map || tokens['id_token'] is! String || tokens['access_token'] is! String) {
        throw StateError('Hasil login tidak lengkap. Coba kembali.');
      }
      final idToken = tokens['id_token'] as String;
      final parts = idToken.split('.');
      if (parts.length != 3) throw StateError('Hasil login tidak valid.');
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (claims is! Map || claims['nonce'] != nonce || claims['aud'] != clientId ||
          !['accounts.google.com', 'https://accounts.google.com'].contains(claims['iss']) ||
          claims['exp'] is! num || (claims['exp'] as num) <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        throw StateError('Sesi Google tidak cocok atau kedaluwarsa. Coba kembali.');
      }
      // Claim checks bind this response to the request; Firebase validates the
      // token signature and account when signInWithCredential is called.
      return DesktopGoogleTokens(idToken, tokens['access_token'] as String);
    } finally {
      await subscription?.cancel();
      await _server?.close(force: true);
      _server = null; _callback = null; _running = false;
      if (client == null) transport.close();
    }
  }

  void cancel() {
    final callback = _callback;
    if (callback != null && !callback.isCompleted) callback.completeError(StateError('Login dibatalkan.'));
  }
}
