import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/church_pastors.dart';
import '../lib/data_gereja_daerah_page.dart';
import '../lib/pastor_profile_page.dart';
import '../lib/jemaat_photo_page.dart';

void main() {
  testWidgets(
    'Regional church shows every pastor and opens the chosen profile',
    (tester) async {
      var statisticsOpened = false;
      const first = ChurchPastor(id: 'one', name: 'Gembala Pertama');
      const second = ChurchPastor(
        id: 'two',
        name: 'Gembala Kedua',
        wa: '08123456789',
        fb: 'https://facebook.com/dua',
      );
      const third = ChurchPastor(id: 'three', name: 'Gembala Ketiga');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RegionChurchCard(
                churchId: 'smirna',
                churchName: 'GKII Smirna',
                address: 'Balai Sepuak',
                pastors: const [first, second, third],
                onStatistics: () => statisticsOpened = true,
              ),
            ),
          ),
        ),
      );
      for (final name in [first.name, second.name, third.name]) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Statistik GKII Smirna'));
      expect(statisticsOpened, isTrue);
      await tester.tap(find.text(second.name));
      await tester.pumpAndSettle();
      final page = tester.widget<PastorProfilePage>(
        find.byType(PastorProfilePage),
      );
      expect(page.pastor.id, 'two');
      expect(page.churchName, 'GKII Smirna');
      expect(find.text(second.wa), findsOneWidget);
      expect(find.text(second.fb), findsOneWidget);
      expect(find.text('Ketuk foto untuk melihat layar penuh'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(first.name));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PastorProfilePage>(find.byType(PastorProfilePage))
            .pastor
            .id,
        'one',
      );
      expect(find.text('Kontak gembala belum diisi.'), findsOneWidget);
    },
  );
  testWidgets('Pastor photo opens the shared fullscreen viewer with zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openPastorPhoto(
                context,
                'https://example.com/pastor.jpg',
                'pastor-photo-test',
              ),
              child: const Text('Foto gembala'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Foto gembala'));
    await tester.pumpAndSettle();
    final photo = tester.widget<FullScreenImagePage>(
      find.byType(FullScreenImagePage),
    );
    expect(photo.imageUrl, 'https://example.com/pastor.jpg');
    expect(photo.heroTag, 'pastor-photo-test');
    expect(
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).maxScale,
      greaterThan(1),
    );
    expect(tester.takeException(), isNull);
  });
}
