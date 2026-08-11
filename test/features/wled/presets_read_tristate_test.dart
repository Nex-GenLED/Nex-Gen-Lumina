// fetchPresets tri-state — P1-52 amplifier.
//
// `fetchPresets` folded FIVE conditions into one `const {}`: sim mode, an empty
// controller, a non-2xx, an unreachable device, and an unparseable
// presets.json. The caller could not tell them apart, so an unreadable read
// made psaveIfChanged believe every slot was missing and re-save the whole
// block — and each psave applies its inline state live, flashing the lights on
// every sync.
//
// Same bug class as activeLeaseTimers() returning [] for both "no leases" and
// "don't know yet" (→ P0-9a).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart'
    show PresetsRead, PresetsReadState;

void main() {
  group('the three states are distinct', () {
    test('deviceEmpty is KNOWN — a first write is legitimate', () {
      const r = PresetsRead.deviceEmpty();
      expect(r.state, PresetsReadState.deviceEmpty);
      expect(r.presets, isEmpty);
      expect(r.isKnown, isTrue,
          reason: 'an empty controller must still permit a first write');
    });

    test('unreadable is NOT known — callers must refuse', () {
      const r = PresetsRead.unreadable('parse');
      expect(r.state, PresetsReadState.unreadable);
      expect(r.presets, isEmpty);
      expect(r.isKnown, isFalse);
      expect(r.reason, 'parse');
    });

    test('available is known and carries the presets', () {
      final r = PresetsRead.available({
        1: {'n': 'NGL On'},
      });
      expect(r.state, PresetsReadState.available);
      expect(r.isKnown, isTrue);
      expect(r.presets[1]!['n'], 'NGL On');
    });

    test('THE COLLAPSE: empty and unreadable both have an empty map — only '
        'the STATE separates them', () {
      const empty = PresetsRead.deviceEmpty();
      const bad = PresetsRead.unreadable('parse');
      expect(empty.presets, bad.presets,
          reason: 'this is why a bare map could never distinguish them');
      expect(empty.isKnown, isNot(bad.isKnown));
    });
  });

  group('the naming must survive a tidy-up', () {
    test('members are pinned so unreadable cannot be renamed to read like '
        'a legitimate empty', () {
      // The BaseLayerStatus.absentInFirestore lesson: a name that states the
      // CAUSE survives a future cleanup; a comment does not.
      expect(
        PresetsReadState.values.map((e) => e.name).toList(),
        ['available', 'deviceEmpty', 'unreadable'],
      );
    });

    test('every unreadable cause is carried for the support call', () {
      for (final why in ['http', 'parse', 'shape', 'io']) {
        expect(PresetsRead.unreadable(why).reason, why);
        expect(PresetsRead.unreadable(why).isKnown, isFalse);
      }
    });
  });
}
