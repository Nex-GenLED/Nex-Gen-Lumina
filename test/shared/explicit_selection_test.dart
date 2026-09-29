// P9 — the app never picks a device, controller or pattern for the customer.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/shared/explicit_selection.dart';

void main() {
  group('requireExplicitSelection', () {
    test('nothing tapped, several candidates → no selection, never .first',
        () {
      final d = requireExplicitSelection<String>(
        candidates: ['front', 'back'],
        tapped: null,
        noun: 'controller',
      );
      expect(d.value, isNull);
      expect(d.hasSelection, isFalse);
      expect(d.reason, 'Choose a controller to continue.');
    });

    test('nothing tapped, several candidates, sole-candidate allowed → still '
        'no selection', () {
      final d = requireExplicitSelection<String>(
        candidates: ['front', 'back'],
        tapped: null,
        noun: 'device',
        allowSoleCandidate: true,
      );
      expect(d.value, isNull);
      expect(d.reason, isNotEmpty);
    });

    test('nothing tapped, exactly one candidate → not chosen by default', () {
      final d = requireExplicitSelection<String>(
        candidates: ['front'],
        tapped: null,
        noun: 'controller',
      );
      expect(d.value, isNull);
      expect(d.reason, 'Tap the controller to choose it.');
    });

    test('exactly one candidate is taken only when the caller allows it', () {
      final d = requireExplicitSelection<String>(
        candidates: ['front'],
        tapped: null,
        noun: 'device',
        allowSoleCandidate: true,
      );
      expect(d.value, 'front');
      expect(d.reason, isNull);
    });

    test('the tapped one is returned', () {
      final d = requireExplicitSelection<String>(
        candidates: ['front', 'back'],
        tapped: 'back',
        noun: 'controller',
      );
      expect(d.value, 'back');
      expect(d.hasSelection, isTrue);
    });

    test('a tapped one that has gone is not replaced by another', () {
      final d = requireExplicitSelection<String>(
        candidates: ['front', 'back'],
        tapped: 'shed',
        noun: 'controller',
      );
      expect(d.value, isNull);
      expect(d.reason, contains('no longer available'));
    });

    test('no candidates → says so', () {
      final d = requireExplicitSelection<String>(
        candidates: const [],
        tapped: null,
        noun: 'device',
        allowSoleCandidate: true,
      );
      expect(d.value, isNull);
      expect(d.reason, 'No device found yet.');
    });

    test('equals lets records be matched by id', () {
      final d = requireExplicitSelection<Map<String, String>>(
        candidates: [
          {'id': 'a', 'name': 'Front'},
          {'id': 'b', 'name': 'Back'},
        ],
        tapped: {'id': 'b', 'name': 'stale name'},
        noun: 'controller',
        equals: (x, y) => x['id'] == y['id'],
      );
      expect(d.value?['name'], 'Back', reason: 'the live record is returned');
    });
  });

  group('requireExactMatch', () {
    test('a match is returned', () {
      final d = requireExactMatch<String>(
        candidates: ['Warm White', 'Candy Cane'],
        matches: (c) => c == 'Candy Cane',
        noun: 'pattern',
      );
      expect(d.value, 'Candy Cane');
    });

    test('no match → unavailable, never the first catalog entry', () {
      final d = requireExactMatch<String>(
        candidates: ['Warm White', 'Candy Cane'],
        matches: (c) => c == 'Harvest Glow',
        noun: 'pattern',
        requested: 'Harvest Glow',
      );
      expect(d.value, isNull);
      expect(d.reason, '"Harvest Glow" isn\'t available.');
    });

    test('no match and no name → a plain sentence', () {
      final d = requireExactMatch<String>(
        candidates: const [],
        matches: (_) => true,
        noun: 'pattern',
      );
      expect(d.reason, "That pattern isn't available.");
    });
  });
}
