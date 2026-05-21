// Tests for saveLocalParticipatingChannels / loadLocalParticipatingChannels.
//
// Contract:
//   - Round-trip: save([0,1]) → load() == [0,1].
//   - Absent key: load() == null (NOT []). Null means "no preference,
//     fall back to default policy"; empty list is the explicit
//     "no channels" choice.
//   - Empty list round-trip: save([]) → load() == [] (distinct from null).
//   - save(null) clears the key; subsequent load() == null.
//   - Overwrite: save([0,1]) then save([2]) → load() == [2].

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('local participating-channels persistence', () {
    test('round-trip: save [0,1] then load returns [0,1]', () async {
      await saveLocalParticipatingChannels([0, 1]);
      final loaded = await loadLocalParticipatingChannels();
      expect(loaded, equals([0, 1]));
    });

    test('absent key: load returns null (NOT empty list)', () async {
      final loaded = await loadLocalParticipatingChannels();
      expect(loaded, isNull);
    });

    test(
        'empty list round-trip: save [] then load returns [] '
        '(distinct from null)', () async {
      await saveLocalParticipatingChannels(const []);
      final loaded = await loadLocalParticipatingChannels();
      expect(loaded, isNotNull);
      expect(loaded, isEmpty);
    });

    test('save(null) clears the key; subsequent load returns null', () async {
      await saveLocalParticipatingChannels([0, 1]);
      expect(await loadLocalParticipatingChannels(), equals([0, 1]));
      await saveLocalParticipatingChannels(null);
      expect(await loadLocalParticipatingChannels(), isNull);
    });

    test('overwrite: save [0,1] then save [2] returns [2]', () async {
      await saveLocalParticipatingChannels([0, 1]);
      await saveLocalParticipatingChannels([2]);
      final loaded = await loadLocalParticipatingChannels();
      expect(loaded, equals([2]));
    });

    test('preserves channel-id order as given (no implicit sort)', () async {
      // The resolver sorts its default-policy output, but persistence
      // is a verbatim mirror — explicit lists keep their order. This
      // matches Bundle 1's resolver contract.
      await saveLocalParticipatingChannels([2, 0, 1]);
      final loaded = await loadLocalParticipatingChannels();
      expect(loaded, equals([2, 0, 1]));
    });
  });
}
