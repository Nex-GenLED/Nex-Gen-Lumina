// Roofline slice 2, B1 — the JSON element counter, anchored to the bench of
// 2026-11-06 (bench-s2-results/results.md, "bounds-first sizes").
//
// The firmware limit is an ELEMENT count (ArduinoJson pool 32,767 B at 16 B
// per element, about 2,047; 2,019 parsed, saved and fired, 2,055 refused on
// classic ESP32 0.15.4), not bytes. The bench's counting rule: every array
// element and object member is one slot; the root takes none. These anchor
// the Dart counter to the recorded points at the bench's fixture density
// (100 LEDs per bus, a base colour plus five single-LED accents, every bus
// painted, name "Pattern: Bench nightly 3-bus", slot 10):
//   1 bus   106 elements /   411 B
//   3 buses 306 elements / 1,069 B
//   6 buses 606 elements / 2,056 B

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';

final _now = DateTime(2026, 11, 6);
const kBenchName = 'Pattern: Bench nightly 3-bus';

List<LedColorGroup> benchPaint() {
  const base = [0, 0, 120, 0];
  const accent = [255, 255, 255, 0];
  final out = <LedColorGroup>[];
  var cursor = 0;
  for (final a in const [10, 30, 50, 70, 90]) {
    out.add(LedColorGroup(startLed: cursor, endLed: a - 1, color: base));
    out.add(LedColorGroup(startLed: a, endLed: a, color: accent));
    cursor = a + 1;
  }
  out.add(LedColorGroup(startLed: cursor, endLed: 99, color: base));
  return out;
}

/// [buses] buses of 100 LEDs, every one painted with the bench density.
CustomDesign benchDensity(int buses) => CustomDesign(
      id: 'bench-$buses',
      name: 'Bench nightly 3-bus',
      ownerId: 'bench',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: 180,
      brightnessStated: true,
      layoutStamp: DesignLayoutStamp(
          controllerId: 'spare-ed030c',
          busLengths: List<int>.filled(buses, 100)),
      channels: [
        for (var id = 0; id < buses; id++)
          ChannelDesign(
              channelId: id,
              channelName: 'Channel ${id + 1}',
              ledCount: 100,
              colorGroups: benchPaint()),
      ],
    );

void main() {
  group('wledJsonElementCount — the bench counting rule', () {
    test('scalars, arrays and objects: one slot per element or member, none '
        'for the root', () {
      expect(wledJsonElementCount(1), 0);
      expect(wledJsonElementCount([]), 0);
      expect(wledJsonElementCount({}), 0);
      expect(wledJsonElementCount([1, 2, 3]), 3);
      expect(wledJsonElementCount({'a': 1, 'b': 'x'}), 2);
      expect(wledJsonElementCount({'a': [1, 2]}), 3, reason: 'member + 2');
      expect(wledJsonElementCount([[0, 0, 0, 0]]), 5, reason: 'array + 4');
      expect(
          wledJsonElementCount({
            'seg': [
              {'id': 0, 'start': 0, 'stop': 100}
            ]
          }),
          5,
          reason: 'seg member, one object, three members');
    });
  });

  group('anchored to the recorded bench points (within 2 elements)', () {
    for (final (buses, elements, bytes) in const [
      (1, 106, 411),
      (3, 306, 1069),
      (6, 606, 2056),
    ]) {
      test('$buses bus(es): $elements elements, $bytes B', () {
        final body = buildDesignApiPresetBody(benchDensity(buses))!;
        final got = designApiPresetWireElements(body,
            presetId: 10, presetName: kBenchName);
        expect((got - elements).abs(), lessThanOrEqualTo(2),
            reason: 'counted $got, bench recorded $elements');
        expect(
            designApiPresetWireBytes(body,
                presetId: 10, presetName: kBenchName),
            bytes);
      });
    }
  });

  group('the element cap', () {
    test('is 1,700: 15 % under the 2,019 that parsed, saved and fired', () {
      expect(kDesignApiPresetMaxElements, 1700);
      expect(kDesignApiPresetMaxElements, lessThanOrEqualTo((2019 * 0.85).floor()));
    });

    test('the count is independent of key order and of the slot digits', () {
      final body = buildDesignApiPresetBody(benchDensity(3))!;
      final a = designApiPresetWireElements(body,
          presetId: 10, presetName: kBenchName);
      final b = designApiPresetWireElements(body,
          presetId: 25, presetName: kBenchName);
      final reordered = <String, dynamic>{
        'seg': body['seg'],
        'bri': body['bri'],
        'on': body['on'],
        'o': body['o'],
      };
      final c = designApiPresetWireElements(reordered,
          presetId: 10, presetName: kBenchName);
      expect(a, b);
      expect(a, c);
    });
  });
}
