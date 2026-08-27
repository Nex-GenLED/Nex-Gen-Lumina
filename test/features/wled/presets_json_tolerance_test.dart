// #89 / P1-52 — presets.json must survive stray bytes.
//
// The fixture is the REAL body served by bench controller 192.168.1.150 on
// 2026-08-27, byte-for-byte, 0xFF bytes included. It was captured while the
// solar bench gate was running: the app's own schedule sync had just deleted a
// preset, and the next sync could no longer read the file at all.
//
// The regression these tests lock down: ONE stray byte used to make
// readPresets return unreadable('io'), which made syncAll refuse to rewrite the
// preset block, which made the empty-armed guard abort the whole sync. A single
// erased byte in PADDING disabled every schedule on that controller, and the
// only user-visible symptom was "contact support".

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// The captured corrupt body. Read as BYTES — reading it as a string would
/// itself throw, which is the whole point.
List<int> _fixtureBytes() =>
    File('test/features/wled/data/presets_corrupt_0xff.json').readAsBytesSync();

void main() {
  group('fixture — the real corrupt body from the bench', () {
    test('is the captured size and carries seven 0xFF bytes', () {
      final b = _fixtureBytes();
      expect(b.length, 16585);
      expect(b.where((x) => x == 0xFF).length, 7);
      expect(b.where((x) => x == 0x00).length, 0);
    });

    test('THROWS under a strict UTF-8 decode — the old failure', () {
      // This is exactly what wled_service used to do at the read site.
      expect(() => utf8.decode(_fixtureBytes()), throwsFormatException);
    });
  });

  group('sanitizePresetsJson', () {
    test('produces a decodable string instead of throwing', () {
      final text = sanitizePresetsJson(_fixtureBytes());
      expect(text, isNotEmpty);
      expect(text.contains('�'), isFalse,
          reason: 'replacement chars outside strings must be stripped');
      expect(text.codeUnits.contains(0xFF), isFalse);
    });

    test('leaves well-formed input byte-for-byte unchanged', () {
      const clean = '{"1":{"n":"NGL On","bri":200},"2":{"n":"NGL Off"}}';
      expect(sanitizePresetsJson(utf8.encode(clean)), clean);
    });

    test('does not disturb characters INSIDE string literals', () {
      // A preset name with a brace and an escaped quote must survive intact.
      const tricky = r'{"1":{"n":"Bra{ce \" and — dash"}}';
      expect(sanitizePresetsJson(utf8.encode(tricky)), tricky);
    });
  });

  group('salvagePresetEntries — in-band corruption', () {
    // Stripping alone is NOT enough for this file. Two of the seven 0xFF bytes
    // sat in padding (repairable); the other five OVERWROTE real characters
    // inside preset 41 — `[0,0,0,<FF>]` and `"m12":<FF>},<FF>"id"<FF>1`. Those
    // bytes are gone, so a whole-file parse still fails and per-entry salvage
    // is what keeps the other presets.
    late String text;
    setUp(() => text = sanitizePresetsJson(_fixtureBytes()));

    test('whole-file parse still fails — documents why salvage exists', () {
      expect(() => jsonDecode(text), throwsFormatException);
    });

    test('recovers 21 of the 22 presets', () {
      final kept = salvagePresetEntries(text);
      expect(kept.length, 21);
    });

    test('presets on BOTH sides of the first 0xFF run are present', () {
      // The 0xFF at offset 3868 sits in the padding between preset 3 and
      // preset 4. Neither neighbour may be lost to it.
      final kept = salvagePresetEntries(text);
      expect(kept.containsKey('3'), isTrue, reason: 'before the 0xFF run');
      expect(kept.containsKey('4'), isTrue, reason: 'after the 0xFF run');
      expect((kept['3'] as Map)['n'], 'NGL Dim');
      expect((kept['4'] as Map)['n'], 'NGL Low');
    });

    test('keeps the system ladder and the far end of the file', () {
      final kept = salvagePresetEntries(text);
      for (final id in ['1', '2', '3', '4', '5']) {
        expect(kept.containsKey(id), isTrue, reason: 'ladder slot $id');
      }
      expect(kept.containsKey('160'), isTrue, reason: 'last entry in the file');
      expect(kept.containsKey('10'), isTrue);
    });

    test('drops ONLY the slot whose bytes were destroyed', () {
      final kept = salvagePresetEntries(text);
      expect(kept.containsKey('41'), isFalse,
          reason: 'preset 41 had real characters overwritten by 0xFF');
    });

    test('returns empty for a body with nothing salvageable', () {
      expect(salvagePresetEntries('not json at all'), isEmpty);
    });
  });

  group('the arming path is no longer blocked', () {
    test('the salvaged read is AVAILABLE, not unreadable', () {
      final kept = salvagePresetEntries(sanitizePresetsJson(_fixtureBytes()));
      final asInts = <int, Map<String, dynamic>>{
        for (final e in kept.entries)
          if (int.tryParse(e.key) != null && int.parse(e.key) > 0)
            int.parse(e.key): Map<String, dynamic>.from(e.value as Map),
      };
      final read = PresetsRead.available(asInts);

      // This is the exact condition that used to abort the sync.
      expect(read.state, PresetsReadState.available);
      expect(read.state, isNot(PresetsReadState.unreadable));
      expect(read.presets, isNotEmpty);
    });

    test('a schedule still builds a REAL timer — empty-armed guard passes', () {
      // The guard that fired during the gate run was "1 armable schedule but
      // the built payload has zero real timers". Prove a real row is produced.
      final payload = buildCfgPayload(const [
        ScheduleItem(
          id: 's1',
          timeLabel: '7:00 PM',
          offTimeLabel: '11:00 PM',
          repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          actionLabel: 'Turn On',
          enabled: true,
        ),
      ]);
      final ins = (payload['timers'] as Map)['ins'] as List;
      expect(ins, isNotEmpty);
      final real = ins.where((t) => (t as Map)['en'] == 1).toList();
      expect(real.length, 2, reason: 'one ON row and one OFF row');
      expect((real.first as Map)['hour'], 19);
    });
  });
}
