const noteListStartKey = 'gkii-list-start';

class NoteListNumber {
  final int value, indent;
  const NoteListNumber(this.value, this.indent);
  String get label {
    if (indent % 3 == 1) {
      var n = value;
      var result = '';
      while (n > 0) {
        n--;
        result = String.fromCharCode(97 + n % 26) + result;
        n ~/= 26;
      }
      return result;
    }
    if (indent % 3 == 2) {
      var n = value;
      var result = '';
      const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
      const roman = [
        'm',
        'cm',
        'd',
        'cd',
        'c',
        'xc',
        'l',
        'xl',
        'x',
        'ix',
        'v',
        'iv',
        'i',
      ];
      for (var i = 0; i < values.length; i++) {
        while (n >= values[i]) {
          result += roman[i];
          n -= values[i];
        }
      }
      return result;
    }
    return '$value';
  }
}

/// Markers live on newline operations, so normal Quill editing moves them with
/// their paragraphs. Repeated inherited markers continue numbering after Enter.
Map<int, NoteListNumber> noteListNumbers(List<dynamic> delta) {
  final labels = <int, NoteListNumber>{};
  final counters = <int, int>{};
  final anchors = <int, String>{};
  var offset = 0, lineStart = 0;
  for (final operation in delta) {
    if (operation is! Map || operation['insert'] is! String) continue;
    final text = operation['insert'] as String;
    final attrs = operation['attributes'] is Map
        ? operation['attributes'] as Map
        : const {};
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 10) continue;
      final list = attrs['list'];
      final indent = attrs['indent'] is int
          ? (attrs['indent'] as int).clamp(0, 8).toInt()
          : 0;
      if (list == 'ordered') {
        counters.removeWhere((level, _) => level > indent);
        anchors.removeWhere((level, _) => level > indent);
        var number = (counters[indent] ?? 0) + 1;
        final marker = attrs[noteListStartKey];
        final match = marker is String
            ? RegExp(r'^(\d+):(\d{1,4})$').firstMatch(marker)
            : null;
        if (match != null && anchors[indent] != match[1]) {
          final start = int.parse(match[2]!);
          if (start > 0) {
            number = start;
            anchors[indent] = match[1]!;
          }
        }
        counters[indent] = number;
        labels[lineStart] = NoteListNumber(number, indent);
      } else if (list == null) {
        counters.clear();
        anchors.clear();
      }
      lineStart = offset + i + 1;
    }
    offset += text.length;
  }
  return labels;
}

String notePlainText(List<dynamic> delta) {
  final labels = noteListNumbers(delta);
  final text = delta
      .whereType<Map>()
      .map((op) => op['insert'] is String ? op['insert'] as String : '')
      .join();
  final result = StringBuffer();
  var start = 0;
  while (start < text.length) {
    final end = text.indexOf('\n', start);
    final label = labels[start];
    if (label != null) result.write('${label.label}. ');
    if (end < 0) {
      result.write(text.substring(start));
      break;
    }
    result.writeln(text.substring(start, end));
    start = end + 1;
  }
  return result.toString();
}
