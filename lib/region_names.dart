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
  const RegionNameGroup(this.name, this.count);
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
