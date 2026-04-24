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
  static const String _keyIsPengurus = "is_pengurus";
  static const String _keyJemaatId = "jemaat_id";
  
  // KUNCI UNTUK ADMIN DAERAH
  static const String _keyAdminDaerahArea = "admin_daerah_area";

  // Variabel Data
  String? userRole; // 👈 BERISI: "user", "admin", "superadmin", "gembala", "bpj" dll
  String? userId;
  String? userNama;
  String? userFotoUrl;
  String? userKomisi = "Umum";
  String? originalChurchId;
  String? originalChurchName;
  String? activeChurchId;
  String? activeChurchName;
  bool isPengurus = false;
  String? jemaatId;
  
  // VARIABEL JABATAN TAMBAHAN (BISA DIRANGKAP)
  String? adminDaerahArea;

  // Singleton pattern
  static final UserManager _instance = UserManager._internal();
  factory UserManager() => _instance;
  UserManager._internal();

  Future<void> saveToPrefsWithId(String uId) async {
    userId = uId;
    await saveToPrefs();
  }

  // Fungsi untuk menyimpan data User (Login)
  Future<void> setUser({
    required String? role,
    required String? churchId,
    required String? churchName,
    required String? uId,
    required String? uNama,
    String? uFoto,
    String uKomisi = "Umum",
    bool uIsPengurus = false,
    String? uJemaatId, 
    String? uAdminDaerahArea, 
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
    isPengurus = uIsPengurus; 
    jemaatId = uJemaatId; 
    adminDaerahArea = uAdminDaerahArea; 
    await saveToPrefs();
  }

  // Simpan ke SharedPreferences
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
    await prefs.setBool(_keyIsPengurus, isPengurus); 
    await prefs.setString(_keyJemaatId, jemaatId ?? ""); 
    await prefs.setString(_keyAdminDaerahArea, adminDaerahArea ?? ""); 
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
    isPengurus = prefs.getBool(_keyIsPengurus) ?? false; 
    
    String? loadedJemaatId = prefs.getString(_keyJemaatId);
    jemaatId = (loadedJemaatId != null && loadedJemaatId.isNotEmpty) ? loadedJemaatId : null;

    String? loadedArea = prefs.getString(_keyAdminDaerahArea);
    adminDaerahArea = (loadedArea != null && loadedArea.isNotEmpty) ? loadedArea : null;
    
    return true;
  }

  // 👇 PENGECEKAN HAK AKSES YANG SUDAH DILENGKAPI 👇
  
  // 1. HAK AKSES LOKAL 
  bool isAdmin() => userRole == "admin" || userRole == "superadmin";
  
  // 2. HAK AKSES SUPERADMIN PUSAT
  bool isSuperAdmin() => userRole == "superadmin";
  
  // 3. HAK AKSES DAERAH (Pembuat Postingan)
  bool isAdminDaerah() => adminDaerahArea != null && adminDaerahArea!.trim().isNotEmpty;

  // 👇 4. HAK AKSES TAMBAHAN UNTUK GEMBALA & BPJ 👇
  bool isGembala() => userRole == "gembala";
  
  bool isBPJ() => userRole == "bpj";

  // Cek apakah akun tertaut dengan database jemaat
  bool isLinked() => jemaatId != null && jemaatId!.trim().isNotEmpty;

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

  Future<void> updateProfil(String namaBaru, String? fotoBaru) async {
    userNama = namaBaru;
    userFotoUrl = fotoBaru;
    await saveToPrefs();
  }

  Future<void> updateKomisi(String komisiBaru) async {
    userKomisi = komisiBaru;
    await saveToPrefs();
  }

  Future<void> linkJemaatId(String newJemaatId) async {
    jemaatId = newJemaatId;
    await saveToPrefs();
  }

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
    isPengurus = false; 
    jemaatId = null; 
    adminDaerahArea = null; 
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}