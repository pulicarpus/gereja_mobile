import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'region_names.dart';

class RegionLabel extends StatelessWidget {
  final String area, prefix;
  final TextStyle? style;
  const RegionLabel({
    super.key,
    required this.area,
    this.prefix = '',
    this.style,
  });
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('churches').snapshots(),
        builder: (context, snapshot) {
          var label = cleanRegionName(area);
          for (final group in groupChurchRegions(
            snapshot.data?.docs.map((doc) => doc.data()) ?? [],
          )) {
            if (regionNameKey(group.name) == regionNameKey(area)) {
              label = group.displayName;
              break;
            }
          }
          return Text('$prefix$label', style: style);
        },
      );
}
