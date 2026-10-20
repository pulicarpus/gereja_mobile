import 'pastor_identity.dart';
import 'church_pastors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'region_names.dart';
import 'region_posts.dart';

DateTime? regionalBirthDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  for (final format in ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd', 'dd/MM/yy']) {
    try {
      return DateFormat(format).parseStrict(value?.toString().trim() ?? '');
    } catch (_) {}
  }
  return null;
}

class RegionalBirthday {
  final Map<String, dynamic> person;
  final DateTime birth;
  final Set<String> roles;
  RegionalBirthday(this.person, this.birth, String role) : roles = {role};
}

Future<List<RegionalBirthday>> loadRegionalBirthdays(
  FirebaseFirestore db,
  String area,
  DateTime now, {
  bool includeAliases = true,
}) async {
  final allChurches = await db.collection('churches').get();
  final aliases = regionPostAliases(
    area,
    allChurches.docs.map((d) => d.data()),
  );
  if (aliases.isEmpty || aliases.length > 30)
    throw StateError('Nama daerah perlu diperiksa.');
  final churches = allChurches.docs
      .where(
        (d) =>
            d.data()['isArchived'] != true &&
            regionNameKey(d.data()['daerah']) == regionNameKey(area),
      )
      .toList();
  final members = <Map<String, dynamic>>[];
  await Future.wait(
    churches.map((church) async {
      final people = await church.reference.collection('jemaat').get();
      for (final doc in people.docs) {
        members.add({
          ...doc.data(),
          'id': doc.id,
          'churchId': church.id,
          'churchName':
              church.data()['name'] ?? church.data()['namaGereja'] ?? '',
        });
      }
    }),
  );
  final results = <String, RegionalBirthday>{};
  String nameKey(Object? v) => cleanRegionName(v).toLowerCase();
  void add(
    Map<String, dynamic> source,
    String role, {
    Map<String, dynamic>? linked,
  }) {
    final name = source['nama'] ?? source['namaLengkap'];
    final matches = members
        .where((m) => nameKey(m['namaLengkap']) == nameKey(name))
        .toList();
    final member = linked ?? (matches.length == 1 ? matches.single : null);
    final date =
        regionalBirthDate(source['tanggalLahir']) ??
        regionalBirthDate(member?['tanggalLahir']);
    if (date == null ||
        date.month != now.month ||
        date.isAfter(now) ||
        nameKey(name).isEmpty)
      return;
    final person = {
      ...?member,
      ...source,
      'namaLengkap': name,
      'tanggalLahir': Timestamp.fromDate(date),
    };
    final key = member != null
        ? '${member['churchId']}/${member['id']}'
        : '${nameKey(name)}/${date.toIso8601String()}';
    if (results.containsKey(key)) {
      results[key]!.roles.add(role);
    } else {
      results[key] = RegionalBirthday(person, date, role);
    }
  }

  final accounts = await db
      .collection('users')
      .where('role', whereIn: ['gembala', 'admin'])
      .get();
  for (final account in accounts.docs) {
    final data = account.data();
    if (data['isBlocked'] == true || !accountIsPastor(data)) continue;
    final matches = members.where(
      (m) =>
          m['churchId'] == data['churchId'] &&
          m['id'] == data['jemaatId'] &&
          m['uid'] == account.id,
    );
    if (matches.isNotEmpty)
      add(matches.first, 'Gembala', linked: matches.first);
  }
  // Gembala recorded on a church can appear even before linking a login account.
  for (final church in churches) {
    for (final pastor in churchPastors(church.data())) {
      final matches = members
          .where(
            (member) =>
                member['churchId'] == church.id &&
                nameKey(member['namaLengkap']) == nameKey(pastor.name),
          )
          .toList();
      if (matches.length == 1)
        add(matches.single, 'Gembala', linked: matches.single);
    }
  }
  final boards = await db
      .collection('struktur_pengurus_daerah')
      .where('daerah', whereIn: includeAliases ? aliases : [area])
      .get();
  for (final board in boards.docs) {
    final data = board.data();
    for (final entry in const {
      'ketua': 'Ketua BPHD',
      'wakil': 'Wakil Ketua',
      'sek1': 'Sekretaris 1',
      'sek2': 'Sekretaris 2',
      'bend1': 'Bendahara 1',
      'bend2': 'Bendahara 2',
    }.entries) {
      add({
        'nama': data['bphd_${entry.key}'],
        'tanggalLahir': data['lahir_${entry.key}'],
        'fotoProfil': data['img_${entry.key}'],
        'nomorTelepon': data['wa_${entry.key}'],
      }, entry.value);
    }
    for (final section in ['penasehat', 'mkdp', 'bpk', 'komisi']) {
      final people = await board.reference.collection(section).get();
      for (final doc in people.docs) {
        final person = doc.data();
        if (section != 'komisi')
          add({
            ...person,
            'fotoProfil': person['fotoUrl'],
            'nomorTelepon': person['wa'],
          }, section.toUpperCase());
        else {
          for (final role in ['ketua', 'sek', 'bend']) {
            add({
              'nama':
                  person['${role}_nama'] ??
                  (role == 'ketua' ? person['namaPengurus'] : null),
              'tanggalLahir': person['${role}_lahir'],
              'fotoProfil': person['${role}_img'],
              'nomorTelepon': person['${role}_wa'],
            }, '${role.toUpperCase()} Komisi ${person['namaKomisi'] ?? ''}');
          }
          for (final member
              in (person['anggota'] is List ? person['anggota'] as List : [])) {
            if (member is Map)
              add({
                ...Map<String, dynamic>.from(member),
                'fotoProfil': member['img'],
                'nomorTelepon': member['wa'],
              }, 'Komisi ${person['namaKomisi'] ?? ''}');
          }
        }
      }
    }
  }
  return results.values.toList()
    ..sort((a, b) => a.birth.day.compareTo(b.birth.day));
}
