import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../lib/bible_models.dart';
import '../lib/bible_local_store.dart';
import '../lib/notes_pages.dart';
import '../lib/note_numbering.dart';

class UnusedBibleDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Rich text roundtrips while legacy clients retain the same plain text',
    () {
      final note = NoteModel(
        key: 'one',
        nas: 'Mazmur 3:6',
        title: 'Khotbah',
        date: '25 Oktober 2026',
        content: 'Kasih',
        preacher: 'Nama',
        rawData: '',
        richDelta: [
          {
            'insert': 'Kasih',
            'attributes': {'bold': true},
          },
          {'insert': '\n'},
        ],
      );
      final restored = NoteModel.fromRaw('one', note.toLocalJson());
      expect(restored.richDelta, note.richDelta);
      expect(restored.content, 'Kasih');
      expect(NoteModel.fromRaw('one', restored.toLegacyRaw()).content, 'Kasih');
      expect(
        quill.Document.fromJson(restored.richDelta!).toPlainText(),
        'Kasih\n',
      );
    },
  );
  test(
    'Invalid structured metadata restores legacy backup, invalid Delta keeps text',
    () {
      final invalid = jsonEncode({
        'format': 'bible-note-v3',
        'nas': 'Mazmur 3:6',
        'title': 'Judul',
        'content': 'Isi',
        'date': 123,
      });
      expect(
        NoteModel.backupPayload('one', {
          'structured_data': invalid,
          'raw_data': 'legacy',
        }),
        'legacy',
      );
      final raw = jsonEncode({
        'format': 'bible-note-v3',
        'nas': 'Mazmur 3:6',
        'title': 'Judul',
        'content': 'Teks aman',
        'date': '',
        'richDelta': [
          {'retain': 3},
        ],
      });
      final note = NoteModel.fromRaw('one', raw);
      expect(note.preacher, '');
      expect(note.content, 'Teks aman');
      expect(note.richDelta, isNull);
    },
  );
  testWidgets(
    'Back before debounce flushes text and bold formatting, reopening shows rich text',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'reader'),
        signedIn: true,
      );
      final store = BibleLocalStore(prefs, 'reader');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            quill.FlutterQuillLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NoteEditorPage(
                      nas: 'Mazmur 3:6',
                      prefs: prefs,
                      db: UnusedBibleDatabase(),
                      allBooks: [],
                      auth: auth,
                    ),
                  ),
                ),
                child: const Text('Buka catatan'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buka catatan'));
      await tester.pumpAndSettle();
      final editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor),
      );
      editor.controller.document.insert(0, 'Kasih');
      editor.controller.document.format(0, 5, quill.Attribute.bold);
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
            .focusNode,
        same(editor.focusNode),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(store.noteKeys.length, 1);
      expect(
        NoteModel.fromRaw(
          store.noteKeys.single,
          store.readNote(store.noteKeys.single)!,
        ).content,
        'Kasih',
      );
      editor.controller.document.insert(5, ' baru');
      await tester.pump();
      // Leave before the next three-second autosave timer fires.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Buka catatan'), findsOneWidget);
      expect(store.noteKeys.length, 1);
      final key = store.noteKeys.single;
      final saved = NoteModel.fromRaw(key, store.readNote(key)!);
      expect(saved.content, 'Kasih baru');
      expect(saved.richDelta!.first['attributes']['bold'], true);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            quill.FlutterQuillLocalizations.delegate,
          ],
          home: NoteEditorPage(
            nas: 'Mazmur 3:6',
            existingKey: key,
            prefs: prefs,
            db: UnusedBibleDatabase(),
            allBooks: [],
            auth: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reopened = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor),
      );
      expect(reopened.controller.readOnly, true);
      expect(
        reopened.controller.document
            .toDelta()
            .toJson()
            .first['attributes']['bold'],
        true,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Editor fills screen, toolbar docks above keyboard and double tap edits numbering',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'reader'),
        signedIn: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            quill.FlutterQuillLocalizations.delegate,
          ],
          home: NoteEditorPage(
            nas: 'Mazmur 4:1-9',
            prefs: prefs,
            db: UnusedBibleDatabase(),
            allBooks: [],
            auth: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor),
      );
      editor.controller.document.insert(
        0,
        [
          ...List.generate(40, (i) => 'Baris ${i + 1}'),
          'Akhir catatan',
        ].join('\n'),
      );
      editor.controller.document.format(
        0,
        editor.controller.document.length - 1,
        quill.Attribute.ol,
      );
      await tester.pump();
      await tester.pump();
      final fullHeight = tester
          .getSize(find.byKey(const ValueKey('note-full-editor')))
          .height;
      expect(fullHeight, greaterThan(500));
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('note-keyboard-toolbar')),
      );
      expect(toolbar.bottom, closeTo(640, 1));
      expect(
        tester.getRect(find.byKey(const ValueKey('note-full-editor'))).bottom,
        lessThanOrEqualTo(toolbar.top),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('note-full-editor'))).height,
        lessThan(fullHeight),
      );
      editor.scrollController.jumpTo(
        editor.scrollController.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      final lastLine = find
          .textContaining('Akhir catatan', findRichText: true)
          .last;
      expect(tester.getRect(lastLine).bottom, lessThanOrEqualTo(toolbar.top));
      editor.scrollController.jumpTo(0);
      await tester.pumpAndSettle();
      final marker = find.byKey(const ValueKey('note-list-number-0'));
      await tester.tap(marker);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(marker);
      await tester.pumpAndSettle();
      expect(find.text('Ubah nomor daftar'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('note-list-start-input')),
        '2',
      );
      await tester.tap(find.text('Terapkan'));
      await tester.pumpAndSettle();
      expect(
        noteListNumbers(
          editor.controller.document.toDelta().toJson(),
        ).values.first.value,
        2,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final store = BibleLocalStore(prefs, 'reader');
      final saved = NoteModel.fromRaw(
        store.noteKeys.single,
        store.readNote(store.noteKeys.single)!,
      );
      expect(
        noteListNumbers(
          quill.Document.fromJson(saved.richDelta!).toDelta().toJson(),
        ).values.first.value,
        2,
      );
      expect(saved.content, startsWith('2. Baris 1'));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
