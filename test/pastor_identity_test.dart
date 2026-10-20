import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/pastor_identity.dart';
import '../lib/user_manager.dart';

void main() {
  test(
    'Pastor can retain church admin and read region after restoring session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = UserManager();
      try {
        await manager.setUser(
          role: 'admin',
          churchId: 'B',
          churchName: 'Tujuan',
          uId: 'pastor',
          uNama: 'Gembala',
          uJemaatId: 'member',
          uIsPastor: true,
          uDaerah: 'Baru',
        );
        expect(manager.isAdmin(), true);
        expect(manager.isGembala(), true);
        expect(manager.canViewRegion('Baru'), true);
        expect(manager.canViewRegion('Lama'), false);
        expect(manager.canEditRegion('Baru'), false);
        manager.isPastorAccount = false;
        await manager.loadFromPrefs();
        expect(manager.isGembala(), true);
        expect(manager.isAdmin(), true);
        expect(accountIsPastor({'role': 'admin', 'isPastor': true}), true);
        expect(accountIsPastor({'role': 'admin'}), false);
        expect(accountIsPastor({'role': 'gembala'}), true);
      } finally {
        await manager.reset();
      }
      expect(manager.isGembala(), false);
    },
  );
}
