import 'package:flutter/material.dart';

Map<String, Object> initialVerseImageDesign(String verse, String reference) => {
  'verse': verse,
  'reference': reference,
  'caption': '',
  'ratio': 9 / 16,
  'background': 'gradient',
  'image': '',
  'backgroundColor': const Color(0xff172554),
  'secondColor': const Color(0xff6d28d9),
  'textColor': Colors.white,
  'referenceColor': Colors.orangeAccent,
  'fontSize': 24.0,
  'lineHeight': 1.5,
  'font': 'Standar',
  'bold': true,
  'italic': false,
  'shadow': true,
  'watermark': true,
  'align': TextAlign.center,
  'textX': 0.0,
  'textY': 0.0,
  'textWidth': .85,
  'overlay': .35,
  'zoom': 1.0,
  'imageX': 0.0,
  'imageY': 0.0,
};

class VerseImageHistory {
  Map<String, Object> value;
  final List<Map<String, Object>> _undo = [], _redo = [];
  VerseImageHistory(Map<String, Object> initial) : value = Map.of(initial);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void remember() {
    _undo.add(Map.of(value));
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
  }

  void change(String key, Object next, {bool rememberChange = true}) {
    if (value[key] == next) return;
    if (rememberChange) remember();
    value = {...value, key: next};
  }

  void replace(Map<String, Object> next) {
    remember();
    value = Map.of(next);
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(Map.of(value));
    value = _undo.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(Map.of(value));
    value = _redo.removeLast();
  }
}

class VerseImageCanvas extends StatelessWidget {
  final Map<String, Object> design;
  final ImageProvider? backgroundImage;
  const VerseImageCanvas({
    super.key,
    required this.design,
    this.backgroundImage,
  });
  @override
  Widget build(BuildContext context) {
    final background = design['background'] as String;
    final color = design['backgroundColor'] as Color;
    final textColor = design['textColor'] as Color;
    final family = switch (design['font']) {
      'Serif' => 'Georgia',
      'Monospace' => 'monospace',
      _ => null,
    };
    final style = TextStyle(
      color: textColor,
      fontSize: design['fontSize'] as double,
      height: design['lineHeight'] as double,
      fontFamily: family,
      fontWeight: design['bold'] == true ? FontWeight.bold : FontWeight.normal,
      fontStyle: design['italic'] == true ? FontStyle.italic : FontStyle.normal,
      shadows: design['shadow'] == true
          ? const [
              Shadow(
                color: Colors.black87,
                blurRadius: 5,
                offset: Offset(1, 2),
              ),
            ]
          : null,
    );
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              gradient: background == 'gradient'
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color, design['secondColor'] as Color],
                    )
                  : null,
            ),
          ),
          if (background == 'photo' && backgroundImage != null)
            Transform.scale(
              scale: design['zoom'] as double,
              child: LayoutBuilder(
                builder: (_, constraints) => Transform.translate(
                  offset: Offset(
                    -(design['imageX'] as double) *
                        ((design['zoom'] as double) - 1) *
                        constraints.maxWidth /
                        (2 * (design['zoom'] as double)),
                    -(design['imageY'] as double) *
                        ((design['zoom'] as double) - 1) *
                        constraints.maxHeight /
                        (2 * (design['zoom'] as double)),
                  ),
                  child: Image(
                    image: backgroundImage!,
                    fit: BoxFit.cover,
                    alignment: Alignment(
                      design['imageX'] as double,
                      design['imageY'] as double,
                    ),
                    errorBuilder: (_, error, stack) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ColoredBox(
            color: Colors.black.withOpacity(design['overlay'] as double),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Align(
              alignment: Alignment(
                design['textX'] as double,
                design['textY'] as double,
              ),
              child: FractionallySizedBox(
                widthFactor: design['textWidth'] as double,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 324 * (design['textWidth'] as double),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          design['verse'] as String,
                          textAlign: design['align'] as TextAlign,
                          style: style,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          design['reference'] as String,
                          textAlign: design['align'] as TextAlign,
                          style: style.copyWith(
                            color: design['referenceColor'] as Color,
                            fontSize: (design['fontSize'] as double) * .7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if ((design['caption'] as String)
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            design['caption'] as String,
                            textAlign: design['align'] as TextAlign,
                            style: style.copyWith(fontSize: 14),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (design['watermark'] == true)
            const Positioned(
              bottom: 12,
              right: 14,
              child: Text(
                'GKII Mobile',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
