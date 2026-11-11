// Build 124, fix d5 — Glitter (fx 87) sparkles in col[2], and in ULTRA-WHITE
// (R=G=B=W=255) when col[2] is black. The chokepoint's col pad wrote black
// into every missing third slot, so two-colour Glitter flashed full white.
// Owner's bench, spare controller 2026-11-10, step 10: the white flashes "look
// a little cheaper"; col[2] = the second colour "colors look better". This file
// pins that approved payload through normalizeWledPayload (the LAN and relay
// chokepoint, and the background worker's build-time normaliser).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

Map<String, dynamic> _seg(Map<String, dynamic> p) =>
    ((p['seg'] as List).single as Map).cast<String, dynamic>();

Map<String, dynamic> _wire(Map<String, dynamic> seg) =>
    _seg(normalizeWledPayload({'on': true, 'seg': [seg]}));

const _purple = [128, 0, 128, 0];
const _orange = [255, 140, 0, 0];
const _black = [0, 0, 0, 0];

void main() {
  test('bench step 10, exactly: Haunted House Glitter gets orange sparkles', () {
    final s = _wire({
      'fx': 87,
      'sx': 40,
      'ix': 128,
      'pal': 5,
      'col': [_purple, _orange],
    });
    expect(s['col'], [_purple, _orange, _orange]);
    expect([s['fx'], s['sx'], s['ix'], s['pal'], s['grp'], s['spc'], s['bri']],
        [87, 40, 128, 5, 1, 0, 255],
        reason: 'the rest of the look is untouched; the background stays the '
            'two design colours (the second is repeated, nothing is added)');
  });

  test('a team Glitter sparkles in the team LED secondary', () {
    final s = _wire({
      'fx': 87,
      'sx': 40,
      'ix': 128,
      'pal': 5,
      'col': [
        [255, 0, 34, 0], // Chiefs red, LED
        [255, 168, 0, 0], // Chiefs gold, LED
        _black,
      ],
    });
    expect(s['col'], [
      [255, 0, 34, 0],
      [255, 168, 0, 0],
      [255, 168, 0, 0],
    ], reason: 'an explicitly black third slot is replaced too');
  });

  test('left alone: a chosen sparkle colour, a black second colour, and every '
      'other effect', () {
    expect(_wire({'fx': 87, 'col': [_purple, _orange, _purple]})['col'],
        [_purple, _orange, _purple],
        reason: 'a non-black col[2] IS the sparkle colour');
    expect(_wire({'fx': 87, 'col': [_purple, _black]})['col'],
        [_purple, _black, _black],
        reason: 'no second colour to sparkle in');
    expect(_wire({'fx': 28, 'col': [_purple, _orange]})['col'],
        [_purple, _orange, _black],
        reason: 'Chase keeps the black pad (its lead block is col[2])');
    expect(_wire({'fx': 103, 'col': [_purple, _orange]})['col'],
        [_purple, _orange, _black],
        reason: 'Solid Glitter (103) was not benched; unchanged in build 124');
  });

  test('an API-command preset body (o:true) is never touched', () {
    final body = {
      'o': true,
      'seg': [
        {
          'fx': 87,
          'col': [_purple, _orange, _black],
        }
      ],
    };
    expect(normalizeWledPayload(body), body);
  });
}
