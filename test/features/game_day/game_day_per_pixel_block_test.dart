// Roofline slice 1, item 4 — a per-pixel (painted) design cannot become a
// Game Day BASE design.
//
// Cause (from code): `gameDayDesignUpdate` / `writeGameDayDesign` is the one
// place a design is written into a team's plan, and it accepted any payload.
// The plan then fires `saved_design_payload` verbatim through the bridge or
// the LAN as one applyJson (game_day_apply.dart:107), the server passes it
// raw with no key filter, and on the device a per-pixel body FREEZES the
// segment — a frame the post-game revert cannot clear. The only thing in the
// way was the library picker's snackbar; the tuner's "Save to Game Day" and
// any future caller reached the write unguarded.
//
// Now the write REFUSES a payload carrying `seg[].i` with a plain message
// (PerPixelDesignRefused), before anything is written. The picker's own
// refusal names Game Day when that is the destination.
//
// This file is the fail-before proof: on the unchanged code the first test
// below gets a map with `saved_design_payload` holding the `i` arrays
// instead of an exception. It uses only API that existed before (the
// builder, a stamped painted design's own toWledPayload, throwsException).
//
// Fixture: one controller with three buses of 100; a painted design over
// all three; an effect design for the pass-through case.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/game_day/game_day_design_write.dart';

final _now = DateTime(2026, 11, 4);

CustomDesign painted() => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: 120,
      brightnessStated: true,
      layoutStamp: const DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]),
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(channelId: id, channelName: 'Channel ${id + 1}', ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
              ]),
      ],
    );

CustomDesign effect() => CustomDesign(
      id: 'e1',
      name: 'Crimson chase',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      brightness: 200,
      brightnessStated: true,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Channel 1', ledCount: 100, effectId: 28,
            colorGroups: [
              LedColorGroup(startLed: 0, endLed: 0, color: [227, 24, 55, 0]),
              LedColorGroup(startLed: 1, endLed: 1, color: [255, 255, 255, 0]),
            ]),
      ],
    );

void main() {
  test('fixture sanity: the painted design\'s payload carries i on every bus; '
      'the effect design\'s does not', () {
    final p = painted().toWledPayload();
    expect(painted().isPositional, isTrue);
    for (final s in (p['seg'] as List).cast<Map>()) {
      expect(s.containsKey('i'), isTrue);
    }
    final e = effect().toWledPayload();
    expect(((e['seg'] as List).single as Map).containsKey('i'), isFalse);
  });

  test('a per-pixel payload is REFUSED by the plan write with a plain message — '
      'nothing is built', () {
    final d = painted();
    expect(
      () => gameDayDesignUpdate(designName: d.name, wledPayload: d.toWledPayload()),
      throwsException,
      reason: 'the unchanged builder returned an update carrying the i arrays',
    );
    try {
      gameDayDesignUpdate(designName: d.name, wledPayload: d.toWledPayload());
      fail('expected a refusal');
    } on Exception catch (e) {
      final text = e.toString();
      expect(text, contains('"Porch stripes"'), reason: 'names the design');
      expect(text, contains('painted design'));
      expect(text, contains('Game Day'));
      expect(text, contains('colour-and-effect'), reason: 'says what to choose instead');
      expect(text, isNot(contains('Exception:')), reason: 'plain, not a raw \$e');
    }
  });

  test('an effect design still writes the plan exactly as before', () {
    final d = effect();
    final update = gameDayDesignUpdate(designName: d.name, wledPayload: d.toWledPayload());
    expect(update['design_mode'], 'saved');
    expect(update['saved_design_name'], 'Crimson chase');
    expect(update['effect_id'], 28);
    expect(update['brightness'], 200);
    final stored = jsonDecode(update['saved_design_payload'] as String) as Map;
    expect(((stored['seg'] as List).single as Map)['fx'], 28);
    expect(((stored['seg'] as List).single as Map).containsKey('i'), isFalse);
  });

  test('a per-pixel payload hidden in a single map seg (not a list) is refused too', () {
    expect(
      () => gameDayDesignUpdate(designName: 'x', wledPayload: {
        'on': true,
        'seg': {'id': 0, 'fx': 0, 'i': [0, [255, 0, 0, 0]]},
      }),
      throwsException,
    );
  });
}
