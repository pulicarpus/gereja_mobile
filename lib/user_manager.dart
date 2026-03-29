import 'package:shared_preferences/shared_preferences.dart';

class UserManager {
  static const String _prefsName = "GerejaAppSession";
  
  // Kunci Penyimpanan (Keys)
  static const String _keyRole = "user_role";
  static const String _keyUserId = "user_id";
  static const String _keyUserNama = "user_nama";
  static const String _keyUserFoto = "user_foto";
  static const String _keyUserKomisi = "user_komisi";
  static const String _keyOriginalChurchId = "original_church_id";
  static const String _keyOriginalChurchName = "original_church_name";
  static const String _keyActiveChurchId = "active_church_id";
  static const String _keyActiveChurchName = "active_church_name";

  // Variabel Data
  String? userRole;
  String? userId;
  String? userNama;
  String? userFotoUrl;
  String? userKomisi = "Umum";
  String? originalChurchId;
  String? originalChurchName;
  String? activeChurchId;
  String? activeChurchName;

  // Singleton pattern agar Manager ini bisa dipanggil di mana saja
  static final UserManager _instance = UserManager._internal();
  factory UserManager() => _instance;
  UserManager._internal();

  // Fungsi untuk menyimpan data User (Login)
  Future<void> setUser({
    required String? role,
    required String? churchId,
    required String? churchName,
    required String? uId,
    required String? uNama,
    String? uFoto,
    String uKomisi = "Umum",
  }) async {
    userRole = role;
    userId = uId;
    userNama = uNama;
    userFotoUrl = uFoto;
    userKomisi = uKomisi;
    originalChurchId = churchId;
    originalChurchName = churchName;
    activeChurchId = churchId;
    activeChurchName = churchName;
    await saveToPrefs();
  }

  // Simpan ke SharedPreferences (Android/iOS)
  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRole, userRole ?? "");
    await prefs.setString(_keyUserId, userId ?? "");
    await prefs.setString(_keyUserNama, userNama ?? "");
    await prefs.setString(_keyUserFoto, userFotoUrl ?? "");
    await prefs.setString(_keyUserKomisi, userKomisi ?? "Umum");
    await prefs.setString(_keyOriginalChurchId, originalChurchId ?? "");
    await prefs.setString(_keyOriginalChurchName, originalChurchName ?? "");
    await prefs.setString(_keyActiveChurchId, activeChurchId ?? "");
    await prefs.setString(_keyActiveChurchName, activeChurchName ?? "");
  }

  // Load data saat aplikasi baru dibuka
  Future<bool> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    userRole = prefs.getString(_keyRole);
    
    if (userRole == null || userRole!.isEmpty) return false;

    userId = prefs.getString(_keyUserId);
    userNama = prefs.getString(_keyUserNama) ?? "Jemaat";
    userFotoUrl = prefs.getString(_keyUserFoto);
    userKomisi = prefs.getString(_keyUserKomisi) ?? "Umum";
    originalChurchId = prefs.getString(_keyOriginalChurchId);
    originalChurchName = prefs.getString(_keyOriginalChurchName);
    activeChurchId = prefs.getString(_keyActiveChurchId);
    activeChurchName = prefs.getString(_keyActiveChurchName);
    
    return true;
  }

  // Cek Role
  bool isAdmin() => userRole == "admin" || userRole == "superadmin";
  bool isSuperAdmin() => userRole == "superadmin";

  String? getChurchIdForCurrentView() => activeChurchId ?? originalChurchId;

  // Pindah Konteks Gereja (Khusus Superadmin)
  Future<void> enterChurchContext(String churchId, String churchName) async {
    if (isSuperAdmin()) {
      activeChurchId = churchId;
      activeChurchName = churchName;
      await saveToPrefs();
    }
  }

  Future<void> exitChurchContext() async {
    if (isSuperAdmin()) {
      activeChurchId = originalChurchId;
      activeChurchName = originalChurchName;
      await saveToPrefs();
    }
  }

  // Update Data Profil
  Future<void> updateProfil(String namaBaru, String? fotoBaru) async {
    userNama = namaBaru;
    userFotoUrl = fotoBaru;
    await saveToPrefs();
  }

  Future<void> updateKomisi(String komisiBaru) async {
    userKomisi = komisiBaru;
    await saveToPrefs();
  }

  // Logout / Reset
  Future<void> reset() async {
    userRole = null;
    userId = null;
    userNama = null;
    userFotoUrl = null;
    userKomisi = "Umum";
    originalChurchId = null;
    originalChurchName = null;
    activeChurchId = null;
    activeChurchName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}