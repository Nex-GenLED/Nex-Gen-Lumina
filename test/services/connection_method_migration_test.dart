import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/connection_method_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ConnectionMethodMigration.migrationPatchFor', () {
    test('legacy "ethernet_wifi" → "ethernet_wifi_active"', () {
      final patch = ConnectionMethodMigration.migrationPatchFor({
        'connectionType': 'ethernet_wifi',
      });
      expect(patch, {'connectionMethod': 'ethernet_wifi_active'});
    });

    test('legacy "wifi" → "wifi"', () {
      final patch = ConnectionMethodMigration.migrationPatchFor({
        'connectionType': 'wifi',
      });
      expect(patch, {'connectionMethod': 'wifi'});
    });

    test('missing connectionType → "unknown"', () {
      final patch = ConnectionMethodMigration.migrationPatchFor({
        'ip': '192.168.1.50',
      });
      expect(patch, {'connectionMethod': 'unknown'});
    });

    test('unrecognised legacy value → "unknown"', () {
      final patch = ConnectionMethodMigration.migrationPatchFor({
        'connectionType': 'cellular',
      });
      expect(patch, {'connectionMethod': 'unknown'});
    });

    test('doc with valid connectionMethod is skipped (no-op)', () {
      final patch = ConnectionMethodMigration.migrationPatchFor({
        'connectionType': 'ethernet_wifi',
        'connectionMethod': 'ethernet',
      });
      expect(patch, isNull);
    });

    test('doc with garbage connectionMethod is reprocessed', () {
      // If a previous version wrote a bad value, the migration should
      // overwrite it rather than leaving the doc in an invalid state.
      final patch = ConnectionMethodMigration.migrationPatchFor({
        'connectionType': 'wifi',
        'connectionMethod': 'not-a-real-value',
      });
      expect(patch, {'connectionMethod': 'wifi'});
    });
  });

  group('ConnectionMethodMigration.runOnce SharedPreferences guard', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('short-circuits when already-migrated flag is set', () async {
      SharedPreferences.setMockInitialValues({
        ConnectionMethodMigration.prefsKey: true,
      });

      // Empty uid is also a short-circuit, but the flag check should beat
      // any Firestore call. We pass a non-empty uid to prove that — and
      // because there's no Firestore plugin attached, ANY attempt to reach
      // it would throw. The fact that this completes without error proves
      // the function returned before touching Firestore.
      await ConnectionMethodMigration.runOnce('some-uid');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ConnectionMethodMigration.prefsKey), isTrue);
    });

    test('empty uid is a no-op', () async {
      await ConnectionMethodMigration.runOnce('');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ConnectionMethodMigration.prefsKey), isNull,
          reason: 'empty uid must not set the migrated flag — that would '
              'block a later real-user run on the same device');
    });
  });
}
