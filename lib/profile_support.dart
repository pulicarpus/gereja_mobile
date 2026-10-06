String profileText(dynamic value) {
  if (value is String) return value.trim();
  if (value is num) return value.toString();
  if (value is List) return value.map(profileText).where((e) => e.isNotEmpty).join(', ');
  return '';
}
bool profileValidId(String? id) => id != null && id.trim().isNotEmpty && !id.contains('/');
DateTime? profileBirthDate(dynamic value) {
  if (value is DateTime) return DateTime(value.year, value.month, value.day);
  final text = profileText(value);
  var match = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(text);
  int year, month, day;
  if (match != null) {
    day = int.parse(match[1]!); month = int.parse(match[2]!); year = int.parse(match[3]!);
  } else {
    match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ].*)?$').firstMatch(text);
    if (match == null) return null;
    year = int.parse(match[1]!); month = int.parse(match[2]!); day = int.parse(match[3]!);
  }
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day ? date : null;
}
int? profileBirthYear(dynamic value, {int? currentYear}) {
  final date = profileBirthDate(value);
  final text = profileText(value);
  final year = date?.year ?? (RegExp(r'^\d{4}$').hasMatch(text) ? int.tryParse(text) : null);
  return year != null && year >= 1000 && year <= (currentYear ?? DateTime.now().year) ? year : null;
}
bool profileVerifyYear(dynamic birthday, String input, {int? currentYear}) =>
    RegExp(r'^\d{4}$').hasMatch(input) && profileBirthYear(birthday, currentYear: currentYear) == int.tryParse(input);
String profileDateText(dynamic value) {
  final date = profileBirthDate(value);
  if (date == null) return profileText(value);
  return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year.toString().padLeft(4, '0')}';
}
String? profilePhone(String value) {
  var number = value.trim();
  if (number.isEmpty || RegExp(r'[^0-9+\s().-]').hasMatch(number)) return null;
  number = number.replaceAll(RegExp(r'[\s().-]'), '');
  final explicitInternational = number.startsWith('+');
  if (explicitInternational) number = number.substring(1);
  if (number.contains('+')) return null;
  if (number.startsWith('62')) number = '0${number.substring(2)}';
  else if (!explicitInternational && number.startsWith('8')) number = '0$number';
  if (!RegExp(r'^0[1-9][0-9]{7,12}$|^[1-9][0-9]{7,14}$').hasMatch(number)) return null;
  return number;
}
List<Object> profilePhoneVariants(String input) {
  final number = profilePhone(input);
  if (number == null) return [];
  final values = <Object>{input.trim(), number};
  if (number.startsWith('0')) {
    final international = '62${number.substring(1)}';
    values.addAll([international, '+$international', number.substring(1), int.parse(number.substring(1)), int.parse(international)]);
    if (number.length > 8) {
      for (final separator in [' ', '-', '.']) {
        final local = '${number.substring(0, 4)}$separator${number.substring(4, 8)}$separator${number.substring(8)}';
        final national = '${number.substring(1, 4)}$separator${number.substring(4, 8)}$separator${number.substring(8)}';
        values.addAll([local, '62$separator$national', '+62$separator$national']);
      }
    }
  } else { values.addAll(['+$number', int.parse(number)]); }
  return values.toList();
}
String? profilePhoto(dynamic value) {
  final text = profileText(value), uri = Uri.tryParse(profileText(value));
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? text : null;
}
bool profileCustomPhoto(String? url, String uid) {
  if (url == null || !profileValidId(uid)) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  try {
    final path = Uri.decodeComponent(uri.path);
    return path.contains('/users/$uid/') && RegExp('^profil_${RegExp.escape(uid)}(?:_[a-zA-Z0-9-]+)?\\.jpg\$').hasMatch(path.split('/').last);
  } catch (_) { return false; }
}
String? profileDisplayPhoto({required String uid, String? accountPhoto, dynamic bookPhoto}) =>
  profileCustomPhoto(accountPhoto, uid) ? profilePhoto(accountPhoto) : profilePhoto(bookPhoto) ?? profilePhoto(accountPhoto);
String profileMaskedName(dynamic value) {
  final words = profileText(value).split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  return words.isEmpty ? 'Jemaat' : '${words.first}${words.length > 1 ? ' ${words.skip(1).map((e) => '${e[0]}.').join(' ')}' : ''}';
}

// Validates fresh transaction snapshots without adding fields or altering the
// existing users/jemaat schema. Church monitoring must never change ownership.
void validateProfileLink({required String uid, required String churchId, required String jemaatId,
    required String phone, required String inputYear, required Map<String, dynamic> account,
    required Map<String, dynamic> jemaat}) {
  if (account['isBlocked'] == true) throw StateError('Akun sedang dinonaktifkan. Hubungi Admin Gereja.');
  if (profileText(account['churchId']) != churchId) throw StateError('Gereja asal akun sudah berubah. Cari data kembali.');
  final existingId = profileText(account['jemaatId']);
  if (existingId.isNotEmpty && existingId != jemaatId) throw StateError('Akun sudah tertaut ke jemaat lain. Hubungi Admin Gereja.');
  final owner = profileText(jemaat['uid']);
  if (owner.isNotEmpty && owner != uid) throw StateError('Data jemaat sudah tertaut ke akun lain. Hubungi Admin Gereja.');
  if (profilePhone(profileText(jemaat['nomorTelepon'])) != phone) throw StateError('Nomor di buku induk sudah berubah. Cari data kembali.');
  if (profileBirthYear(jemaat['tanggalLahir']) == null) throw StateError('Tanggal lahir belum valid. Hubungi Admin Gereja.');
  if (!profileVerifyYear(jemaat['tanggalLahir'], inputYear)) throw StateError('Tahun lahir tidak cocok. Silakan coba lagi.');
}

Map<String, dynamic> profileAccountChanges(String name, {bool useBookPhoto = false}) => {
  'namaLengkap': name.trim(), if (useBookPhoto) 'photoUrl': null,
};
