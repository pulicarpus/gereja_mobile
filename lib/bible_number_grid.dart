import 'package:flutter/material.dart';

class BibleNumberGrid extends StatelessWidget {
  final List<int> values;
  final ValueChanged<int> onSelected;
  const BibleNumberGrid({
    super.key,
    required this.values,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns =
          ((bounds.maxWidth - 24 + 8) / (64 * scale.clamp(1, 3) + 8))
              .floor()
              .clamp(1, 12);
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 56 * scale.clamp(1, 3),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: values.length,
        itemBuilder: (context, index) => OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => onSelected(values[index]),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${values[index]}',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    },
  );
}
