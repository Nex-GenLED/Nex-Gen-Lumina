// Roofline slice 1, item 1 — DesignLayoutStamp: the controller id and the
// per-bus LED lengths a positional design is saved against.
//
// Pure: no device, no provider container. The round-trip through the design
// document is design_layout_stamp_roundtrip_test.dart (the fail-before file);
// the writers are manual_editor_layout_stamp_test.dart.
//
// Fixture: one controller, three buses of 100 LEDs each (ids 0, 1, 2).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';

const kThreeBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
];

void main() {
  group('fromChannels — device truth in, stamp out', () {
    test('three buses of 100 → [100, 100, 100] with the controller id', () {
      final s = DesignLayoutStamp.fromChannels(kThreeBuses, controllerId: 'ctl-a');
      expect(s, isNotNull);
      expect(s!.busLengths, [100, 100, 100]);
      expect(s.busCount, 3);
      expect(s.controllerId, 'ctl-a');
    });

    test('lengths are placed by bus id, whatever order the list arrives in', () {
      final s = DesignLayoutStamp.fromChannels(const [
        DeviceChannel(id: 2, name: 'C3', start: 200, stop: 260, gpioPin: 12),
        DeviceChannel(id: 0, name: 'C1', start: 0, stop: 100, gpioPin: 2),
        DeviceChannel(id: 1, name: 'C2', start: 100, stop: 200, gpioPin: 14),
      ]);
      expect(s!.busLengths, [100, 100, 60]);
    });

    test('no channels → no stamp (the writer saves unstamped, as before)', () {
      expect(DesignLayoutStamp.fromChannels(const [], controllerId: 'ctl-a'), isNull);
    });

    test('a blank or whitespace controller id is recorded as none', () {
      expect(DesignLayoutStamp.fromChannels(kThreeBuses, controllerId: '  ')!.controllerId,
          isNull);
      expect(DesignLayoutStamp.fromChannels(kThreeBuses)!.controllerId, isNull);
    });

    test('the stored lengths cannot be mutated through the stamp', () {
      final s = DesignLayoutStamp.fromChannels(kThreeBuses)!;
      expect(() => s.busLengths.add(1), throwsUnsupportedError);
    });
  });

  group('Firestore fields', () {
    test('toFirestoreFields writes flat ints under the two field names', () {
      final fields = DesignLayoutStamp.fromChannels(kThreeBuses, controllerId: 'ctl-a')!
          .toFirestoreFields();
      expect(fields, {
        kDesignControllerIdField: 'ctl-a',
        kDesignBusLengthsField: [100, 100, 100],
      });
      expect(fields[kDesignBusLengthsField], isA<List<int>>());
    });

    test('controller_id is omitted when none was known', () {
      final fields = DesignLayoutStamp.fromChannels(kThreeBuses)!.toFirestoreFields();
      expect(fields.containsKey(kDesignControllerIdField), isFalse);
      expect(fields[kDesignBusLengthsField], [100, 100, 100]);
    });

    test('fromFirestoreData: absent, empty or malformed lengths → null', () {
      expect(DesignLayoutStamp.fromFirestoreData(const {}), isNull);
      expect(DesignLayoutStamp.fromFirestoreData(const {'bus_lengths': []}), isNull);
      expect(DesignLayoutStamp.fromFirestoreData(const {'bus_lengths': 'x'}), isNull);
      expect(DesignLayoutStamp.fromFirestoreData(const {'bus_lengths': [100, -1]}), isNull);
      expect(DesignLayoutStamp.fromFirestoreData(const {'bus_lengths': [100, 2.5]}), isNull);
    });

    test('fromFirestoreData reads back what toFirestoreFields wrote', () {
      final s = DesignLayoutStamp.fromChannels(kThreeBuses, controllerId: 'ctl-a')!;
      expect(DesignLayoutStamp.fromFirestoreData(s.toFirestoreFields()), s);
    });
  });

  group('equality', () {
    test('same controller and lengths are equal; any difference is not', () {
      const a = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);
      const b = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const DesignLayoutStamp(controllerId: 'ctl-b', busLengths: [100, 100, 100])));
      expect(a, isNot(const DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 120, 100])));
      expect(a, isNot(const DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100])));
    });
  });

  group('on the design model', () {
    final now = DateTime(2026, 11, 4);
    final stamp = DesignLayoutStamp.fromChannels(kThreeBuses, controllerId: 'ctl-a');

    CustomDesign painted({DesignLayoutStamp? stamp}) => CustomDesign(
          id: 'd1',
          name: 'Porch',
          ownerId: 'customer-uid',
          createdAt: now,
          updatedAt: now,
          perPixel: true,
          layoutStamp: stamp,
          channels: const [
            ChannelDesign(channelId: 0, channelName: 'Channel 1', ledCount: 100, colorGroups: [
              LedColorGroup(startLed: 0, endLed: 99, color: [255, 0, 0, 0]),
            ]),
          ],
        );

    test('copyWith carries the stamp unless a new one is given', () {
      final d = painted(stamp: stamp);
      expect(d.copyWith(name: 'x').layoutStamp, stamp);
      const other = DesignLayoutStamp(controllerId: 'ctl-b', busLengths: [50]);
      expect(d.copyWith(layoutStamp: other).layoutStamp, other);
    });

    test('an unstamped design stays unstamped through copyWith and save', () {
      final d = painted();
      expect(d.copyWith(name: 'x').layoutStamp, isNull);
      expect(d.toFirestore().containsKey(kDesignBusLengthsField), isFalse);
    });

    test('nothing else about the document changes for a stamped design', () {
      final withStamp = painted(stamp: stamp).toFirestore()
        ..remove(kDesignControllerIdField)
        ..remove(kDesignBusLengthsField);
      expect(withStamp, painted().toFirestore());
    });
  });
}
