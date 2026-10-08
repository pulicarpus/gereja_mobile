import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/pengurus_support.dart';
import '../lib/pengurus_widgets.dart';

void main() {
  test('Regional storage IDs cannot confuse separators and escaped names', () {
    expect(pengurusRegionId(' Belitang '), 'Belitang');
    expect(pengurusRegionId('Area/A'), isNot(pengurusRegionId('Area%2FA')));
    expect(pengurusRegionId('Area/A'), isNot(contains('/')));
    expect(() => pengurusRegionId('  '), throwsStateError);
  });
  test(
    'Regional editors require the same live session and the selected area',
    () {
      bool access({
        String? signedIn = 'A',
        String? manager = 'A',
        String role = 'user',
        String? adminArea = 'Belitang',
        String area = 'Belitang',
        bool readOnly = false,
      }) => pengurusDaerahCanEdit(
        userId: manager,
        signedInId: signedIn,
        sessionId: 'A',
        role: role,
        area: area,
        adminArea: adminArea,
        readOnly: readOnly,
      );
      expect(access(), isTrue);
      expect(access(adminArea: 'Lainnya'), isFalse);
      expect(access(signedIn: 'B'), isFalse);
      expect(access(manager: 'B'), isFalse);
      expect(access(signedIn: null), isFalse);
      expect(access(readOnly: true), isFalse);
      expect(access(role: 'gembala', adminArea: null), isFalse);
      expect(access(role: 'superadmin', adminArea: null), isTrue);
      expect(access(role: 'superadmin', area: ''), isFalse);
    },
  );

  test('Only the signed in administrator in the same church may edit', () {
    bool access({
      String? uid = 'u',
      String? auth = 'u',
      String? church = 'A',
      String? view = 'A',
      String role = 'admin',
      bool readOnly = false,
    }) => pengurusCanEdit(
      userId: uid,
      signedInId: auth,
      role: role,
      churchId: church,
      currentChurchId: view,
      readOnly: readOnly,
    );
    expect(access(), isTrue);
    expect(access(role: 'superadmin'), isTrue);
    expect(access(view: 'B'), isFalse);
    expect(access(readOnly: true), isFalse);
    expect(access(auth: 'other'), isFalse);
    expect(access(auth: null), isFalse);
    expect(access(church: null), isFalse);
    expect(access(church: ''), isFalse);
    expect(access(role: 'user'), isFalse);
  });
  test('WhatsApp handles common formatting and rejects invalid numbers', () {
    expect(pengurusWa('0812-3456-7890'), '6281234567890');
    expect(pengurusWa('+62 (812) 3456.7890'), '6281234567890');
    for (final bad in [
      '',
      '0812abc3456',
      '123',
      '++6281234567890',
      '00000',
      'https://example.com',
    ]) {
      expect(pengurusWa(bad), isNull);
    }
  });
  test('Legacy strings and malformed field types are read safely', () {
    expect(pengurusMember('Rina')['nama'], 'Rina');
    expect(pengurusMember({'nama': 'Rina', 'extra': true})['extra'], isTrue);
    expect(pengurusText(8123456789), '8123456789');
    expect(pengurusText(['bad']), '');
    expect(pengurusMembers({'wrong': 'type'}), isEmpty);
    expect(pengurusPhoto('javascript:alert(1)'), isNull);
    expect(pengurusPhoto('https://example.com/photo.jpg'), isNotNull);
  });
  test('Concurrent edits preserve unrelated additions and removals', () {
    const original = [
      'Ana',
      {'nama': 'Budi', 'wa': '', 'img': '', 'extra': 7},
    ];
    const replacement = {'nama': 'Budi Baru', 'wa': '', 'img': '', 'extra': 7};
    final result = changePengurusMember(
      latest: [original[1], 'Cici'],
      original: original,
      index: 1,
      replacement: replacement,
    );
    expect(result, [replacement, 'Cici']);
    expect(original[1], {'nama': 'Budi', 'wa': '', 'img': '', 'extra': 7});
    expect(
      changePengurusMember(
        latest: ['Cici', ...original],
        original: original,
        index: 0,
      ),
      ['Cici', original[1]],
    );
  });
  test(
    'Conflicting edit and ambiguous duplicate never target another person',
    () {
      expect(
        () => changePengurusMember(
          latest: ['Ana Baru', 'Budi'],
          original: ['Ana', 'Budi'],
          index: 0,
          replacement: {'nama': 'X'},
        ),
        throwsStateError,
      );
      expect(
        () => changePengurusMember(
          latest: ['Cici', 'Ana', 'Ana'],
          original: ['Ana', 'Ana'],
          index: 0,
        ),
        throwsStateError,
      );
      expect(
        changePengurusMember(
          latest: ['Ana', 'Ana'],
          original: ['Ana', 'Ana'],
          index: 1,
        ),
        ['Ana'],
      );
    },
  );
  test(
    'Adding preserves legacy entries and retry does not duplicate identical save',
    () {
      const person = {'nama': 'Budi', 'wa': '', 'img': ''};
      final first = changePengurusMember(
        latest: ['Ana', 'Cici'],
        original: ['Ana'],
        index: null,
        replacement: person,
      );
      expect(first, ['Ana', 'Cici', person]);
      expect(
        changePengurusMember(
          latest: first,
          original: ['Ana'],
          index: null,
          replacement: person,
        ),
        first,
      );
      expect(
        samePengurusData(
          {
            'a': 1,
            'b': [2],
          },
          {
            'b': [2],
            'a': 1,
          },
        ),
        isTrue,
      );
    },
  );

  Future<void> openEditor(
    WidgetTester tester,
    Future<void> Function(PengurusPersonInput) save, {
    String name = 'Rina',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPengurusPersonEditor(
                context,
                title: 'Edit pengurus',
                name: name,
                save: save,
              ),
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
  }

  testWidgets('Validation prevents blank name and bad WhatsApp save', (
    tester,
  ) async {
    var calls = 0;
    await openEditor(tester, (_) async {
      calls++;
    }, name: '');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Nama wajib diisi.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Rina');
    await tester.enterText(find.byType(TextField).last, 'bad');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Nomor WhatsApp tidak valid.'), findsOneWidget);
    expect(calls, 0);
  });
  testWidgets('Pending save is locked and closes only after success', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await openEditor(tester, (_) {
      calls++;
      return pending.future;
    });
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Simpan'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Simpan'));
    await tester.pump();
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Failed save preserves input and can retry', (tester) async {
    var calls = 0;
    await openEditor(tester, (input) async {
      calls++;
      if (calls == 1) throw StateError('Izin berubah');
      expect(input.name, 'Rina');
    });
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Izin berubah'), findsOneWidget);
    expect(find.text('Rina'), findsOneWidget);
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Uncertain timeout prevents blindly repeating a write', (
    tester,
  ) async {
    await openEditor(tester, (_) async {
      throw TimeoutException('pending');
    });
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Simpan'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Long details fit small screen and absent WhatsApp is disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPengurusDetail(
                context,
                List.filled(20, 'Nama Panjang').join(' '),
                'Pengurus',
                null,
                '',
              ),
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Hubungi via WhatsApp'),
          )
          .onPressed,
      isNull,
    );
  });
}
