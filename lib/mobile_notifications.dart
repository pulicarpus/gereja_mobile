import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart';

// OneSignal Flutter has no Windows implementation. Keep desktop navigation
// independent of mobile-only push services.
class MobilePush {
  static bool get supported => Platform.isAndroid || Platform.isIOS;
  static void login(String uid) { if (supported) OneSignal.login(uid); }
  static void logout() { if (supported) OneSignal.logout(); }
  static void tag(String key, String value) { if (supported) OneSignal.User.addTagWithKey(key, value); }
}
