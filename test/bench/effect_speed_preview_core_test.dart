// The per-effect speed preview's safety rules (bench/src/effect_speed_preview_core.dart).
//
// Same rules as the team LED preview: never the live home controller, live
// state only, restore exactly what was touched — plus one of its own: a
// full-field strobe is never previewed faster than ~3 Hz.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

import '../../bench/src/effect_speed_preview_core.dart';

void main() {
  group('never the live home controller', () {
    test('by address', () {
      expect(refuseHost('192.168.1.150'), isNotNull);
      expect(refuseHost(' 192.168.1.150 '), isNotNull);
      expect(refuseHost('192.168.1.173'), isNull);
    });
    test('by resolved address', () {
      expect(refuseHost('bench.local', resolved: ['192.168.1.150']), isNotNull);
    });
    test('by the controller\'s own reported ip', () {
      expect(refuseInfo({'ip': '192.168.1.150'}), isNotNull);
      expect(refuseInfo({'ip': '192.168.1.173'}), isNull);
    });
  });

  group('live state only', () {
    for (final k in ['psave', 'pdel', 'ps', 'pl', 'playlist', 'rb']) {
      test('"$k" anywhere is refused', () {
        expect(() => assertLiveStateOnly({k: 1}), throwsStateError);
        expect(
            () => assertLiveStateOnly({
                  'seg': [
                    {'id': 0, k: 1}
                  ]
                }),
            throwsStateError);
      });
    }
    for (final k in ['ib', 'sb', 'n', 'ql', 'np']) {
      test('top-level "$k" is refused', () {
        expect(() => assertLiveStateOnly({k: 1}), throwsStateError);
      });
    }
    test('a preview payload passes, and states the table speed', () {
      final p = buildPreviewPayload(
          segIds: const [0, 1], fx: 64, sx: effectDefaultSpeed(64)!, ix: 128,
          bri: 128);
      assertLiveStateOnly(p);
      final segs = p['seg'] as List;
      expect(segs, hasLength(2));
      expect((segs.first as Map)['sx'], effectDefaultSpeed(64));
      expect((segs.first as Map)['pal'], WledEffectsCatalog.paletteForEffect(64));
    });
  });

  group('flash effects are never previewed at an unsafe rate', () {
    test('Strobe above 240 is capped', () {
      final c = clampFlashForPreview(23, 255, 128);
      expect(c.sx, kFlashPreviewMaxSpeed);
      expect(c.capped, isTrue);
    });
    test('Strobe Mega is one flash per burst', () {
      final c = clampFlashForPreview(25, 100, 128);
      expect(c.ix, lessThanOrEqualTo(kStrobeMegaPreviewMaxIntensity));
      expect(c.capped, isTrue);
    });
    test('a non-flash effect is untouched', () {
      final c = clampFlashForPreview(64, 255, 255);
      expect((c.sx, c.ix, c.capped), (255, 255, false));
    });
    test('the builder refuses an uncapped flash payload', () {
      expect(
          () => buildPreviewPayload(
              segIds: const [0], fx: 23, sx: 250, ix: 0, bri: 128),
          throwsStateError);
    });
  });

  group('the review list', () {
    test('the owner\'s nine come first (flash included on request)', () {
      final list = previewEffects(includeFlash: true);
      expect(list.take(kOwnerReportedTooFast.length).map((e) => e.id).toList(),
          kOwnerReportedTooFast);
    });
    test('flash effects are left out unless asked for', () {
      expect(previewEffects().where((e) => e.isFlash), isEmpty);
    });
    test('every 1D, non-audio catalog effect is reviewable', () {
      final ids = {for (final e in previewEffects(includeFlash: true)) e.id};
      for (final e in WledEffectsCatalog.allEffects) {
        if (e.requires2D || e.requiresAudio) continue;
        expect(ids, contains(e.id), reason: 'fx ${e.id} ${e.name}');
      }
    });
    test('notes are read from the table source', () {
      final notes = parseTableNotes(
          '  64: 32, // too fast (owner 09-29) · beatsin88 · Juggle\n');
      expect(notes[64], 'too fast (owner 09-29) · beatsin88');
    });
  });

  group('restore', () {
    final captured = <String, dynamic>{
      'on': true,
      'bri': 77,
      'seg': [
        {'id': 0, 'on': true, 'fx': 9, 'sx': 200, 'ix': 50, 'pal': 3,
         'col': [[1, 2, 3, 0]], 'start': 0, 'stop': 30, 'rev': true},
        {'id': 1, 'on': false, 'fx': 0, 'sx': 128},
      ],
    };

    test('puts back exactly what a preview touches — never geometry', () {
      final r = buildRestorePayload(captured);
      assertLiveStateOnly(r);
      expect(r['bri'], 77);
      final s0 = (r['seg'] as List).first as Map;
      expect(s0['fx'], 9);
      expect(s0['sx'], 200);
      expect(s0.containsKey('start'), isFalse);
      expect(s0.containsKey('rev'), isFalse);
    });

    test('the diff is empty when the readback matches, and names what differs',
        () {
      expect(restoreDiff(captured, captured), isEmpty);
      final drifted = {
        ...captured,
        'seg': [
          {...(captured['seg'] as List).first as Map, 'sx': 32},
          (captured['seg'] as List)[1],
        ],
      };
      expect(restoreDiff(captured, drifted), ['seg 0.sx: 200 → 32']);
    });
  });
}
