import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gereja_mobile/bible_number_grid.dart';
import 'package:gereja_mobile/bible_support.dart';
import 'package:gereja_mobile/bible_local_store.dart';

void main() {
  test('Range and non-contiguous selections have only one note anchor', () {
    expect(
      bibleNoteAnchor(const BibleReference(230, 3, [1, 2, 3, 4, 5, 6])),
      6,
    );
    expect(bibleNoteAnchor(const BibleReference(230, 3, [6, 1, 3])), 6);
    expect(bibleNoteAnchor(const BibleReference(230, 3, [6])), 6);
    expect(bibleNoteAnchor(const BibleReference(230, 3, [])), isNull);
  });
  test(
    'Two notes on one verse remain independent when edited or deleted',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = BibleLocalStore(
        await SharedPreferences.getInstance(),
        'reader',
      );
      await store.saveNote('one', 'Mazmur 3:6~|~Pertama');
      await store.saveNote('two', 'Mazmur 3:6~|~Kedua');
      await store.saveNote('one', 'Mazmur 3:6~|~Diubah');
      expect(store.noteKeys.toSet(), {'one', 'two'});
      expect(store.readNote('two'), 'Mazmur 3:6~|~Kedua');
      await store.deleteNote('one');
      expect(store.noteKeys, ['two']);
    },
  );
  testWidgets('Three-digit numbers fit at narrow width and large text', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                height: 350,
                child: BibleNumberGrid(
                  values: const [1, 99, 100, 119, 150, 176],
                  onSelected: (v) => selected = v,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('150'), 180);
    final text = tester.widget<Text>(find.text('150'));
    expect(text.maxLines, 1);
    expect(text.softWrap, false);
    await tester.tap(find.text('150'));
    expect(selected, 150);
  });
}
