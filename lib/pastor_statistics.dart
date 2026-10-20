import 'church_pastors.dart';

class PastorStatistics {
  int total = 0;
  int pendeta = 0;
  int vicaris = 0;
  int penginjil = 0;

  void addChurch(Map<String, dynamic> church) {
    for (final pastor in churchPastors(church)) {
      final name = pastor.name.toLowerCase();
      if (name.isEmpty || name.contains('belum ada')) continue;
      total++;
      if (name.contains('pdt') || name.contains('pendeta')) {
        pendeta++;
      } else if (name.contains('vic') || name.contains('vik')) {
        vicaris++;
      } else if (name.contains('ev') || name.contains('penginjil')) {
        penginjil++;
      }
    }
  }
}
