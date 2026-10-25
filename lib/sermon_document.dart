import 'bible_models.dart';
import 'note_numbering.dart';

class SermonRun {
  final String text;
  final Map<String, dynamic> attributes;
  const SermonRun(this.text, this.attributes);
}

class SermonParagraph {
  final List<SermonRun> runs;
  final Map<String, dynamic> attributes;
  final String? marker;
  const SermonParagraph(this.runs, this.attributes, this.marker);
  String get text => runs.map((run) => run.text).join();
  bool get isHeading =>
      attributes['header'] is num ||
      (text.trim().isNotEmpty &&
          text.length < 180 &&
          runs.isNotEmpty &&
          runs.every((r) => r.attributes['bold'] == true)) ||
      RegExp(
        r'^(pendahuluan|penutup|kesimpulan|poin\s+\d+)(\s|:|$)',
        caseSensitive: false,
      ).hasMatch(text.trim());
}

List<SermonParagraph> sermonParagraphs(NoteModel note) {
  final delta =
      NoteModel.validTextDelta(note.richDelta) ??
      [
        {'insert': '${note.content}\n'},
      ];
  final numbers = noteListNumbers(delta);
  final result = <SermonParagraph>[];
  var runs = <SermonRun>[];
  var offset = 0, lineStart = 0;
  for (final op in delta) {
    final text = op['insert'] as String;
    final attrs = op['attributes'] is Map
        ? Map<String, dynamic>.from(op['attributes'])
        : <String, dynamic>{};
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 10) continue;
      if (i > start) runs.add(SermonRun(text.substring(start, i), attrs));
      final number = numbers[lineStart];
      final marker = number != null
          ? '${number.label}.'
          : attrs['list'] == 'bullet'
          ? '•'
          : attrs['list'] == 'checked'
          ? '☑'
          : attrs['list'] == 'unchecked'
          ? '☐'
          : null;
      result.add(SermonParagraph(List.unmodifiable(runs), attrs, marker));
      runs = [];
      start = i + 1;
      lineStart = offset + start;
    }
    if (start < text.length) runs.add(SermonRun(text.substring(start), attrs));
    offset += text.length;
  }
  if (runs.isNotEmpty) result.add(SermonParagraph(runs, const {}, null));
  return result;
}
