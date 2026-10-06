bool pengurusValidId(String? id) =>
    id != null && id.trim().isNotEmpty && !id.contains('/');

String pengurusText(dynamic value) => value is String
    ? value.trim()
    : value is num
    ? value.toString()
    : '';
List<dynamic> pengurusMembers(dynamic value) =>
    value is List ? List<dynamic>.from(value) : <dynamic>[];
Map<String, dynamic> pengurusMember(dynamic value) => value is Map
    ? Map<String, dynamic>.fromEntries(
        value.entries
            .where((e) => e.key is String)
            .map((e) => MapEntry(e.key as String, e.value)),
      )
    : {'nama': pengurusText(value), 'wa': '', 'img': ''};
String? pengurusPhoto(dynamic value) {
  final text = pengurusText(value);
  final uri = Uri.tryParse(text);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? text
      : null;
}

String? pengurusWa(String input) {
  final text = input.trim();
  if (text.isEmpty || RegExp(r'[^0-9+\s().-]').hasMatch(text)) return null;
  var number = text.replaceAll(RegExp(r'[\s().-]'), '');
  if (number.startsWith('+')) number = number.substring(1);
  if (number.contains('+')) return null;
  if (number.startsWith('0')) number = '62${number.substring(1)}';
  if (!RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(number)) return null;
  return number;
}

bool samePengurusData(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && samePengurusData(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => samePengurusData(a[i], b[i]));
  }
  return a == b;
}

// Keep the existing mixed String/Map array format. Never select a changed
// member by a stale numeric index after another administrator updates it.
List<dynamic> changePengurusMember({
  required List<dynamic> latest,
  required List<dynamic> original,
  required int? index,
  Map<String, dynamic>? replacement,
}) {
  final next = List<dynamic>.from(latest);
  if (index == null) {
    if (replacement == null) throw StateError('Anggota baru belum diisi.');
    final previousCount = original
        .where((e) => samePengurusData(e, replacement))
        .length;
    final currentCount = latest
        .where((e) => samePengurusData(e, replacement))
        .length;
    if (currentCount <= previousCount) next.add(replacement);
    return next;
  }
  if (index < 0 || index >= original.length)
    throw StateError('Anggota tidak ditemukan.');
  var target = index;
  if (!samePengurusData(latest, original)) {
    final matches = <int>[
      for (var i = 0; i < latest.length; i++)
        if (samePengurusData(latest[i], original[index])) i,
    ];
    if (matches.length != 1)
      throw StateError(
        'Anggota sudah berubah. Tutup dialog dan buka data terbaru.',
      );
    target = matches.single;
  }
  if (replacement == null) {
    next.removeAt(target);
  } else {
    next[target] = replacement;
  }
  return next;
}

bool pengurusCanEdit({
  required String? userId,
  required String? signedInId,
  required String? role,
  required String? churchId,
  required String? currentChurchId,
  bool readOnly = false,
}) =>
    !readOnly &&
    userId != null &&
    userId == signedInId &&
    (role == 'admin' || role == 'superadmin') &&
    pengurusValidId(churchId) &&
    churchId == currentChurchId;
