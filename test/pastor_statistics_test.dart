import 'package:flutter_test/flutter_test.dart';
import '../lib/pastor_statistics.dart';

void main() {
  test('counts every pastor and does not double count the legacy mirror', () {
    final stats = PastorStatistics();
    stats.addChurch({
      'namaGembala': 'Vic. Pertama',
      'gembalaProfiles': [
        {'id': '1', 'name': 'Vic. Pertama'},
        {'id': '2', 'name': 'Pdt. Kedua'},
        {'id': '3', 'name': 'Ev. Ketiga'},
        {'id': '4', 'name': 'Gembala tanpa gelar'},
      ],
    });
    stats.addChurch({'namaGembala': 'Vik. Format Lama'});
    expect(stats.total, 5);
    expect(stats.pendeta, 1);
    expect(stats.vicaris, 2);
    expect(stats.penginjil, 1);
  });

  test('empty profiles and legacy placeholders do not add workers', () {
    final stats = PastorStatistics();
    stats.addChurch({});
    stats.addChurch({'namaGembala': 'Belum ada data Gembala'});
    stats.addChurch({
      'namaGembala': 'Pdt. Sudah Dihapus',
      'gembalaProfiles': [],
    });
    expect(stats.total, 0);
    expect(stats.pendeta, 0);
    expect(stats.vicaris, 0);
    expect(stats.penginjil, 0);
  });
}
