import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'church_pastors.dart';
import 'pengurus_widgets.dart';
import 'jemaat_photo_page.dart';

Future<void> openPastorLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  try {
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Tautan tidak dapat dibuka.');
    }
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tautan tidak dapat dibuka.')),
      );
  }
}

void openPastorProfile(
  BuildContext context,
  ChurchPastor pastor,
  String churchId,
  String churchName,
) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PastorProfilePage(
        pastor: pastor,
        churchId: churchId,
        churchName: churchName,
      ),
    ),
  );
}

void openPastorPhoto(BuildContext context, String imageUrl, String heroTag) {
  if (imageUrl.trim().isEmpty) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FullScreenImagePage(imageUrl: imageUrl, heroTag: heroTag),
    ),
  );
}

class ChurchPastorAvatar extends StatelessWidget {
  final ChurchPastor pastor;
  final String churchId;
  final double radius;
  const ChurchPastorAvatar({
    super.key,
    required this.pastor,
    required this.churchId,
    this.radius = 32,
  });
  @override
  Widget build(BuildContext context) {
    final avatar = pengurusAvatar(
      pastor.photo.isEmpty ? null : pastor.photo,
      radius: radius,
    );
    if (pastor.photo.isEmpty) return avatar;
    final tag = 'pastor-photo-$churchId-${pastor.id}';
    return Tooltip(
      message: 'Lihat foto layar penuh',
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: () => openPastorPhoto(context, pastor.photo, tag),
        child: Hero(tag: tag, child: avatar),
      ),
    );
  }
}

class PastorProfilePage extends StatelessWidget {
  final ChurchPastor pastor;
  final String churchId, churchName;
  const PastorProfilePage({
    super.key,
    required this.pastor,
    required this.churchId,
    required this.churchName,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Profil Gembala'),
      backgroundColor: Colors.indigo.shade900,
      foregroundColor: Colors.white,
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ChurchPastorAvatar(
            pastor: pastor,
            churchId: churchId,
            radius: 65,
          ),
        ),
        if (pastor.photo.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Ketuk foto untuk melihat layar penuh',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        SelectableText(
          pastor.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Gembala Sidang • $churchName',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.indigo),
        ),
        const SizedBox(height: 24),
        const Text(
          'Kontak & media sosial',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        const SizedBox(height: 8),
        if ([
          pastor.wa,
          pastor.fb,
          pastor.ig,
          pastor.tiktok,
          pastor.yt,
        ].every((v) => v.isEmpty))
          const Text('Kontak gembala belum diisi.'),
        if (pastor.wa.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone, color: Colors.green),
              title: const Text('WhatsApp'),
              subtitle: Text(pastor.wa),
              onTap: () => pengurusWhatsApp(context, pastor.wa),
            ),
          ),
        for (final entry in [
          (pastor.fb, 'Facebook', Icons.facebook),
          (pastor.ig, 'Instagram', Icons.camera_alt),
          (pastor.tiktok, 'TikTok', Icons.music_note),
          (pastor.yt, 'YouTube', Icons.play_circle_fill),
        ])
          if (entry.$1.isNotEmpty)
            Card(
              child: ListTile(
                leading: Icon(entry.$3, color: Colors.indigo),
                title: Text(entry.$2),
                subtitle: Text(entry.$1),
                onTap: () => openPastorLink(context, entry.$1),
              ),
            ),
      ],
    ),
  );
}
