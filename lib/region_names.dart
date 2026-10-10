String cleanRegionName(Object? value) => (value?.toString() ?? '')
    .replaceAll(RegExp(r'[\s\u200B\uFEFF]+'), ' ')
    .trim();

String regionNameKey(Object? value) {
  final name = cleanRegionName(value);
  return (name.isEmpty ? 'Belum Diatur' : name).toLowerCase();
}

class RegionNameGroup {
  final String name;
  final int count;
  final String displayName;
  const RegionNameGroup(this.name, this.count, {String? displayName})
    : displayName = displayName ?? name;
}

// Keep the most-used stored spelling for navigation and existing regional data.
List<RegionNameGroup> groupRegionNames(Iterable<Object?> values) {
  final groups = <String, Map<String, int>>{};
  for (final value in values) {
    final raw = value?.toString() ?? '';
    final name = cleanRegionName(raw).isEmpty ? 'Belum Diatur' : raw;
    final variants = groups.putIfAbsent(regionNameKey(name), () => {});
    variants[name] = (variants[name] ?? 0) + 1;
  }
  return groups.values.map((variants) {
      final names = variants.keys.toList()
        ..sort((a, b) {
          final frequency = variants[b]!.compareTo(variants[a]!);
          if (frequency != 0) return frequency;
          final aClean = a == cleanRegionName(a),
              bClean = b == cleanRegionName(b);
          if (aClean != bClean) return aClean ? -1 : 1;
          return a.compareTo(b);
        });
      return RegionNameGroup(
        names.first,
        variants.values.fold(0, (sum, n) => sum + n),
      );
    }).toList()
    ..sort((a, b) => regionNameKey(a.name).compareTo(regionNameKey(b.name)));
}

String existingRegionName(Object? input, Iterable<Object?> existing) {
  final key = regionNameKey(input);
  for (final group in groupRegionNames(existing)) {
    if (regionNameKey(group.name) == key) return group.name;
  }
  return cleanRegionName(input);
}

List<RegionNameGroup> groupChurchRegions(
  Iterable<Map<String, dynamic>> records,
) {
  final active = records.where((data) => data['isArchived'] != true).toList();
  return groupRegionNames(active.map((data) => data['daerah'])).map((group) {
    final labels = active
        .where(
          (data) => regionNameKey(data['daerah']) == regionNameKey(group.name),
        )
        .map((data) => cleanRegionName(data['namaDaerah']))
        .where((name) => name.isNotEmpty);
    final labelGroups = groupRegionNames(labels);
    labelGroups.sort((a, b) => b.count.compareTo(a.count));
    return RegionNameGroup(
      group.name,
      group.count,
      displayName: labelGroups.isEmpty
          ? cleanRegionName(group.name)
          : labelGroups.first.name,
    );
  }).toList();
}

String churchRegionIdentifier(
  Object? input,
  Iterable<Map<String, dynamic>> records,
) {
  final key = regionNameKey(input);
  for (final group in groupChurchRegions(records)) {
    if (regionNameKey(group.name) == key ||
        regionNameKey(group.displayName) == key)
      return group.name;
  }
  return cleanRegionName(input);
}
