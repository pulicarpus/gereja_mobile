import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'sermon_document.dart';
import 'sermon_references.dart';

class SermonParagraphView extends StatefulWidget {
  final SermonParagraph paragraph;
  final SermonReferenceMatcher matcher;
  final double fontSize;
  final Color foreground, linkColor;
  final bool dark;
  final ValueChanged<SermonVerseLink> onVerse;
  const SermonParagraphView({
    super.key,
    required this.paragraph,
    required this.matcher,
    required this.fontSize,
    required this.foreground,
    required this.linkColor,
    required this.dark,
    required this.onVerse,
  });
  @override
  State<SermonParagraphView> createState() => _SermonParagraphViewState();
}

class _SermonParagraphViewState extends State<SermonParagraphView> {
  List<SermonVerseLink> _links = [];
  final List<TapGestureRecognizer> _taps = [];
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant SermonParagraphView old) {
    super.didUpdateWidget(old);
    if (old.paragraph != widget.paragraph || old.matcher != widget.matcher)
      _prepare();
  }

  void _prepare() {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
    _links = widget.matcher.find(widget.paragraph.text);
    for (final link in _links) {
      _taps.add(TapGestureRecognizer()..onTap = () => widget.onVerse(link));
    }
  }

  @override
  void dispose() {
    for (final tap in _taps) {
      tap.dispose();
    }
    super.dispose();
  }

  Color _textColor(Object? raw) {
    if (raw is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw))
      return widget.foreground;
    final color = Color(0xFF000000 | int.parse(raw.substring(1), radix: 16));
    if (widget.dark && color.computeLuminance() < .15) return widget.foreground;
    if (!widget.dark && color.computeLuminance() > .75)
      return widget.foreground;
    return color;
  }

  @override
  Widget build(BuildContext context) {
    final paragraph = widget.paragraph;
    final text = paragraph.text;
    final heading = paragraph.attributes['header'];
    final size =
        widget.fontSize *
        (heading == 1
            ? 1.5
            : heading == 2
            ? 1.3
            : paragraph.isHeading
            ? 1.15
            : 1);
    final spans = <InlineSpan>[];
    var position = 0;
    for (final run in paragraph.runs) {
      final end = position + run.text.length;
      var cursor = position;
      while (cursor < end) {
        final index = _links.indexWhere(
          (link) => link.start <= cursor && cursor < link.end,
        );
        final next = index >= 0
            ? math.min(end, _links[index].end)
            : _links
                  .where((link) => link.start > cursor)
                  .fold<int>(end, (value, link) => math.min(value, link.start));
        final attrs = run.attributes;
        final decorations = [
          if (attrs['underline'] == true || index >= 0)
            TextDecoration.underline,
          if (attrs['strike'] == true) TextDecoration.lineThrough,
        ];
        spans.add(
          TextSpan(
            text: text.substring(cursor, next),
            style: TextStyle(
              fontWeight: attrs['bold'] == true || paragraph.isHeading
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontStyle: attrs['italic'] == true
                  ? FontStyle.italic
                  : FontStyle.normal,
              decoration: decorations.isEmpty
                  ? TextDecoration.none
                  : TextDecoration.combine(decorations),
              color: index >= 0 ? widget.linkColor : _textColor(attrs['color']),
              fontFamily:
                  attrs['code'] == true ||
                      paragraph.attributes['code-block'] == true
                  ? 'monospace'
                  : null,
            ),
            recognizer: index >= 0 ? _taps[index] : null,
          ),
        );
        cursor = next;
      }
      position = end;
    }
    if (spans.isEmpty) spans.add(const TextSpan(text: ' '));
    final align = paragraph.attributes['align'];
    final indent = paragraph.attributes['indent'] is int
        ? (paragraph.attributes['indent'] as int).clamp(0, 8).toInt()
        : 0;
    return Padding(
      padding: EdgeInsets.only(
        left: 14.0 * indent,
        top: paragraph.isHeading ? 20 : 0,
        bottom: paragraph.text.isEmpty ? 8 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (paragraph.marker != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                paragraph.marker!,
                style: TextStyle(
                  fontSize: size,
                  height: 1.5,
                  color: widget.foreground,
                ),
              ),
            ),
          Expanded(
            child: RichText(
              textAlign: align == 'center'
                  ? TextAlign.center
                  : align == 'right'
                  ? TextAlign.right
                  : align == 'justify'
                  ? TextAlign.justify
                  : TextAlign.start,
              textScaler: MediaQuery.textScalerOf(context),
              text: TextSpan(
                style: TextStyle(
                  fontSize: size,
                  height: 1.5,
                  color: widget.foreground,
                ),
                children: spans,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
