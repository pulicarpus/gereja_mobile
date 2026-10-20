import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'region_birthdays.dart';
import 'region_label.dart';
import 'user_manager.dart';
import 'pengurus_widgets.dart';
import 'detail_jemaat_page.dart';

class RegionBirthdaysPage extends StatelessWidget {
  final String area;
  const RegionBirthdaysPage({super.key, required this.area});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: RegionLabel(area: area, prefix: 'Ulang Tahun • '),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: RegionBirthdaysSection(area: area),
    ),
  );
}

/// Embedded in the regional home; it does not require opening a submenu.
class RegionBirthdaysSection extends StatefulWidget {
  final String area;
  const RegionBirthdaysSection({super.key, required this.area});
  @override
  State<RegionBirthdaysSection> createState() => _RegionBirthdaysSectionState();
}

class _RegionBirthdaysSectionState extends State<RegionBirthdaysSection> {
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

  @override
  void didUpdateWidget(covariant RegionBirthdaysSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area != widget.area) _reload();
  }

  void _reload() {
    _data = _allowed
        ? loadRegionalBirthdays(
            FirebaseFirestore.instance,
            widget.area,
            DateTime.now(),
            includeAliases:
                UserManager().isGembala() || UserManager().isSuperAdmin(),
          )
        : Future.value([]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const SizedBox.shrink();
    final now = DateTime.now();
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cake_outlined, color: Colors.pink),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Ulang Tahun Bulan Ini',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Muat ulang ulang tahun',
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text(
          'Gembala dan pengurus daerah',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<RegionalBirthday>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return pengurusMessage(
                pengurusError(snapshot.error!),
                retry: () => setState(_reload),
              );
            }
            final people = (snapshot.data ?? [])
                .where(
                  (p) => p.birth.month == now.month && p.birth.day >= now.day,
                )
                .toList();
            if (people.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Tidak ada ulang tahun gembala atau pengurus daerah tersisa bulan ini.',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            return SizedBox(
              height: 185.0 + (scale - 1).clamp(0, double.infinity) * 95,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: people.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final person = people[index];
                  final today = person.birth.day == now.day;
                  return SizedBox(
                    width: 155.0 * scale.clamp(1, 2),
                    child: Material(
                      color: today ? Colors.orange.shade50 : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(
                          color: today
                              ? Colors.orange.shade300
                              : Colors.grey.shade200,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailJemaatPage(
                              jemaatData: person.person,
                              showBirthdayGreeting: today,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              pengurusAvatar(
                                person.person['fotoProfil']?.toString(),
                                radius: 24,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                person.person['namaLengkap']?.toString() ??
                                    'Tanpa nama',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                person.roles.join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                today
                                    ? 'Hari ini 🎉'
                                    : DateFormat(
                                        'dd MMMM',
                                        'id_ID',
                                      ).format(person.birth),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: today
                                      ? Colors.orange.shade900
                                      : Colors.indigo,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
