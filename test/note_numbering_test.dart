import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../lib/note_numbering.dart';
import '../lib/bible_models.dart';

void main() {
  test('Custom list starts survive Quill edits, JSON and backup plain text', () {
    final doc = quill.Document()..insert(0, 'Satu\nDua\nTiga');
    doc.format(0, doc.length - 1, quill.Attribute.ol);
    doc.format(
      0,
      0,
      const quill.Attribute<String>(
        noteListStartKey,
        quill.AttributeScope.block,
        '100:2',
      ),
    );
    var delta = doc.toDelta().toJson();
    expect(noteListNumbers(delta).values.map((n) => n.value), [2, 3, 4]);
    expect(notePlainText(delta), '2. Satu\n3. Dua\n4. Tiga\n');
    final note = NoteModel(
      key: 'n',
      nas: 'Mazmur 1:1',
      title: 'Daftar',
      date: '',
      content: notePlainText(delta),
      richDelta: delta,
      rawData: '',
    );
    final restored = NoteModel.fromRaw('n', note.toLocalJson());
    final reopened = quill.Document.fromJson(restored.richDelta!);
    expect(
      noteListNumbers(reopened.toDelta().toJson()).values.map((n) => n.value),
      [2, 3, 4],
    );
    expect(
      NoteModel.fromRaw('n', note.toLegacyRaw()).content,
      contains('2. Satu'),
    );
    // Enter inherits paragraph attributes; the same anchor must not restart each line.
    reopened.insert(4, '\nBaru');
    delta = reopened.toDelta().toJson();
    expect(noteListNumbers(delta).values.map((n) => n.value), [2, 3, 4, 5]);
    doc.close();
    reopened.close();
  });
  test(
    'Restarts affect subsequent numbers and indent counters remain independent',
    () {
      final delta = [
        {'insert': 'A'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'B'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered', noteListStartKey: '101:5'},
        },
        {'insert': 'C'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered', noteListStartKey: '101:5'},
        },
        {'insert': 'Child'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered', 'indent': 1},
        },
        {'insert': 'D'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
        {'insert': 'Paragraph\n'},
        {'insert': 'New'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
      ];
      final labels = noteListNumbers(delta).values.toList();
      expect(labels.map((n) => n.value), [1, 5, 6, 1, 7, 1]);
      expect(labels[3].label, 'a');
    },
  );
}
