import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'region_birthdays.dart';
import 'region_label.dart';
import 'user_manager.dart';
import 'pengurus_widgets.dart';
import 'detail_jemaat_page.dart';

class RegionBirthdaysPage extends StatefulWidget {
  final String area;
  const RegionBirthdaysPage({super.key, required this.area});
  @override
  State<RegionBirthdaysPage> createState() => _RegionBirthdaysPageState();
}

class _RegionBirthdaysPageState extends State<RegionBirthdaysPage> {
  late Future<List<RegionalBirthday>> _data;
  bool get _allowed =>
      UserManager().canViewRegion(widget.area) &&
      (UserManager().isGembala() ||
          UserManager().isAdminDaerah() ||
          UserManager().isSuperAdmin());
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _allowed
        ? loadRegionalBirthdays(
            FirebaseFirestore.instance,
            widget.area,
            DateTime.now(),
          )
        : Future.value([]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: RegionLabel(area: widget.area, prefix: 'Ulang Tahun • '),
    ),
    body: !_allowed
        ? const Center(child: Text('Akses khusus gembala dan pengurus daerah.'))
        : FutureBuilder<List<RegionalBirthday>>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(
                  child: pengurusMessage(
                    pengurusError(snapshot.error!),
                    retry: () => setState(_reload),
                  ),
                );
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final people = snapshot.data!;
              final now = DateTime.now();
              return RefreshIndicator(
                onRefresh: () async {
                  setState(_reload);
                  await _data;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Ulang Tahun ${DateFormat('MMMM yyyy', 'id_ID').format(now)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Gembala dan pengurus daerah. Tanggal lahir mengikuti data jemaat atau data pengurus yang telah diisi.',
                    ),
                    const SizedBox(height: 16),
                    if (people.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Belum ada ulang tahun gembala atau pengurus daerah yang tercatat bulan ini.',
                        ),
                      ),
                    for (final person in people)
                      Card(
                        color: person.birth.day == now.day
                            ? Colors.orange.shade50
                            : null,
                        child: ListTile(
                          leading: pengurusAvatar(
                            person.person['fotoProfil']?.toString(),
                          ),
                          title: Text(person.person['namaLengkap'].toString()),
                          subtitle: Text(
                            '${person.roles.join(' • ')}\n${DateFormat('dd MMMM', 'id_ID').format(person.birth)}${person.birth.day == now.day ? ' • Hari ini' : ''}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetailJemaatPage(
                                jemaatData: person.person,
                                showBirthdayGreeting:
                                    person.birth.day == now.day,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
  );
}
