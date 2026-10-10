import 'package:flutter_test/flutter_test.dart';
import '../lib/region_names.dart';

void main() {
  test(
    'Matching region spellings share one card and combined church count',
    () {
      final groups = groupRegionNames([
        'Daerah Belitang',
        'Daerah Belitang',
        'Daerah Belitang',
        ' DAERAH   BELITANG ',
        'Daerah Ketungau',
      ]);
      expect(groups.length, 2);
      expect(groups.first.name, 'Daerah Belitang');
      expect(groups.first.count, 4);
      expect(
        regionNameKey('Daerah Pontianak'),
        isNot(regionNameKey('Daerah Belitang')),
      );
    },
  );
  test(
    'New church reuses established region spelling, retains distinct new regions',
    () {
      expect(
        existingRegionName(' daerah  BELITANG ', ['Daerah Belitang']),
        'Daerah Belitang',
      );
      expect(
        existingRegionName('  Daerah Baru  ', ['Daerah Belitang']),
        'Daerah Baru',
      );
    },
  );
  test('Missing names form one unassigned group', () {
    final groups = groupRegionNames([null, '', '  ', 'Belum Diatur']);
    expect(groups.single.name, 'Belum Diatur');
    expect(groups.single.count, 4);
  });
  test(
    'Canonical spelling is deterministic and keeps the existing regional identifier',
    () {
      const names = ['BELITANG', 'Belitang', 'Belitang'];
      expect(groupRegionNames(names).single.name, 'Belitang');
      expect(groupRegionNames(names.reversed).single.name, 'Belitang');
    },
  );
}
