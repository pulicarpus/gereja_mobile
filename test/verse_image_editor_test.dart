import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot/screenshot.dart';
import '../lib/buat_gambar_page.dart';
import '../lib/verse_image_design.dart';

void main() {
  test('Undo groups slider movement and redo is cleared by a new edit', () {
    final history = VerseImageHistory(
      initialVerseImageDesign('Ayat', 'Referensi'),
    );
    history.remember();
    history.change('fontSize', 30.0, rememberChange: false);
    history.change('fontSize', 38.0, rememberChange: false);
    history.undo();
    expect(history.value['fontSize'], 24.0);
    history.redo();
    expect(history.value['fontSize'], 38.0);
    history.undo();
    history.change('italic', true);
    expect(history.canRedo, isFalse);
    expect(history.value['verse'], 'Ayat');
  });
  testWidgets(
    'Editing text updates preview and undo restores verse and caption together',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: BuatGambarPage(
            ayatTeks: 'Ayat asli',
            referensi: 'Yohanes 3:16',
            loadOnlineBackgrounds: false,
          ),
        ),
      );
      await tester.tap(find.text('Edit ayat & teks tambahan'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Ayat yang disunting');
      await tester.enterText(fields.at(2), 'Renungan keluarga');
      await tester.tap(find.text('Terapkan'));
      await tester.pumpAndSettle();
      expect(find.text('Ayat yang disunting'), findsOneWidget);
      expect(find.text('Renungan keluarga'), findsOneWidget);
      await tester.tap(find.byTooltip('Urungkan'));
      await tester.pumpAndSettle();
      expect(find.text('Ayat asli'), findsOneWidget);
      expect(find.text('Renungan keluarga'), findsNothing);
      await tester.tap(find.byTooltip('Ulangi'));
      await tester.pumpAndSettle();
      expect(find.text('Renungan keluarga'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Small screen handles long verses, layout formats and background controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: BuatGambarPage(
            ayatTeks: List.filled(100, 'Kasih Allah kepada dunia.').join(' '),
            referensi: 'Yohanes 3:16',
            loadOnlineBackgrounds: false,
          ),
        ),
      );
      await tester.tap(find.text('Tata letak'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kotak 1:1'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VerseImageCanvas>(find.byType(VerseImageCanvas))
            .design['ratio'],
        1.0,
      );
      await tester.tap(find.text('Latar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warna polos'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VerseImageCanvas>(find.byType(VerseImageCanvas))
            .design['background'],
        'solid',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Export renderer produces a 1080px PNG at the selected aspect ratio',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      for (final ratio in [1.0, 9 / 16, 16 / 9]) {
        final design = initialVerseImageDesign('Kasih Allah', 'Yohanes 3:16')
          ..['ratio'] = ratio;
        final bytes = await tester.runAsync(
          () => ScreenshotController().captureFromWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox(
                width: 360,
                height: 360 / ratio,
                child: VerseImageCanvas(design: design),
              ),
            ),
            targetSize: Size(360, 360 / ratio),
            pixelRatio: 3,
            delay: const Duration(milliseconds: 1),
          ),
        );
        expect(bytes!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
        final dimensions = await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final size = Size(
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          );
          frame.image.dispose();
          codec.dispose();
          return size;
        });
        expect(dimensions!.width, 1080);
        expect(dimensions.height, closeTo(1080 / ratio, 1));
      }
    },
  );
}
