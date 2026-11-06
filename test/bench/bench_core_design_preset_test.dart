// Roofline slice 2 — the bench harness's offline invariant over painted-design
// presets (bench_core.dart checkDesignPresetInvariants), fed by canned
// presets.json shapes. NEW-BEHAVIOUR tests; the check runs inside the
// existing `preset-verify` read with no new device traffic.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';

import '../../bench/src/bench_core.dart';

/// The stored copy of a bounds-first design preset (A1, bench 2026-11-06): a
/// group of {id,start,stop} entries, then one paint entry per bus with no
/// bounds. [bounded] false drops the group (the b4b09f2 shape that painted
/// one bus after a cold boot); [lit] false strips bus 0's picture.
Map<String, dynamic> designPreset({
  bool on = true,
  bool bounded = true,
  bool lit = true,
  int buses = 3,
}) =>
    {
      'n': 'Pattern: Porch stripes',
      'on': on,
      'bri': 180,
      'seg': [
        if (bounded)
          for (var b = 0; b < buses; b++)
            {'id': b, 'start': 100 * b, 'stop': 100 * (b + 1)},
        for (var b = 0; b < buses; b++)
          {
            'id': b,
            if (!bounded) 'start': 100 * b,
            if (!bounded) 'stop': 100 * (b + 1),
            'on': true,
            'fx': 0,
            if (lit || b > 0) 'i': [0, 100, [255, 0, 0, 0]],
          },
      ],
    };

Map<String, dynamic> ladderPreset() => {
      'n': 'NGL On',
      'on': true,
      'seg': [
        {'id': 0, 'on': true},
        {'id': 1, 'on': true},
      ],
    };

CheckResult only(List<CheckResult> rs, String fragment) =>
    rs.singleWhere((r) => r.name.contains(fragment));

void main() {
  test('the bench cap mirrors the app cap', () {
    expect(kBenchDesignPresetMaxBytes, kDesignApiPresetMaxBytes);
  });

  test('no design preset → one vacuous, passing line', () {
    final rs = checkDesignPresetInvariants({1: ladderPreset(), 10: ladderPreset()});
    expect(rs, hasLength(1));
    expect(rs.single.pass, isTrue);
    expect(rs.single.evidence, contains('none present'));
  });

  test('a well-formed design preset passes and names slot, buses and bytes', () {
    final rs = checkDesignPresetInvariants({12: designPreset()});
    final r = only(rs, 'design preset 12');
    expect(r.pass, isTrue);
    expect(r.evidence, contains('buses=3'));
    expect(r.evidence, contains(' B'));
  });

  test('root on:false fails (would fire dark)', () {
    final r = only(checkDesignPresetInvariants({12: designPreset(on: false)}),
        'design preset 12');
    expect(r.pass, isFalse);
    expect(r.evidence, contains('root on=false'));
  });

  test('no bounds group (bounds on the paint entries — the b4b09f2 shape that '
      'painted one bus after a cold boot) fails', () {
    final r = only(checkDesignPresetInvariants({12: designPreset(bounded: false)}),
        'design preset 12');
    expect(r.pass, isFalse);
    expect(r.evidence, contains('no bounds group before the paint'));
    expect(r.evidence, contains('paint entry carries start/stop'));
  });

  test('a bounds entry missing a field fails', () {
    final p = designPreset();
    (p['seg'][1] as Map).remove('stop');
    final r = only(checkDesignPresetInvariants({12: p}), 'design preset 12');
    expect(r.pass, isFalse);
    expect(r.evidence, contains('lacks id/start/stop'));
  });

  test('a lit entry with no picture fails', () {
    final r = only(checkDesignPresetInvariants({12: designPreset(lit: false)}),
        'design preset 12');
    expect(r.pass, isFalse);
    expect(r.evidence, contains('is on with no i'));
  });

  test('a stored body over the cap fails and says the bytes', () {
    final big = designPreset();
    big['seg'][3]['i'] = [
      for (var led = 0; led < 400; led++) ...[led, [led % 255, 0, 0, 0]],
    ];
    final r = only(checkDesignPresetInvariants({12: big}), 'design preset 12');
    expect(r.pass, isFalse);
    expect(r.evidence, contains('> cap $kBenchDesignPresetMaxBytes'));
  });

  test('a design preset outside the schedule band is ignored (not ours)', () {
    final rs = checkDesignPresetInvariants({30: designPreset(on: false)});
    expect(rs.single.evidence, contains('none present'));
  });

  test('checkPresetInvariants carries the design lines', () {
    final rs = checkPresetInvariants({
      1: ladderPreset(),
      2: {'n': 'NGL Off', 'on': false, 'seg': []},
      3: ladderPreset(),
      4: ladderPreset(),
      5: ladderPreset(),
      11: designPreset(),
    });
    expect(rs.any((r) => r.name.contains('design preset 11')), isTrue);
  });
}
