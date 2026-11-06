// Roofline slice 2, D1 — pick time refuses a controller whose buses are not
// laid end to end. The body's bounds are cumulative offsets from zero and the
// sync's write-time gate compares them with hw.led.ins[].start EXACTLY, while
// the slice 1 fit gate compares counts and lengths only; on b4b09f2 such a
// controller passed the picker and refused at every sync with a repair hint
// that could not work. The "layout not read yet" verdict is kept where the
// bus list is empty.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';

final _now = DateTime(2026, 11, 6);

CustomDesign design() => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: 180,
      brightnessStated: true,
      layoutStamp: const DesignLayoutStamp(
          controllerId: 'ctl-a', busLengths: [100, 100, 100]),
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(
              channelId: id,
              channelName: 'Channel ${id + 1}',
              ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 99, color: [255, 0, 0, 0]),
              ]),
      ],
    );

DeviceChannel ch(int id, int start, int stop) =>
    DeviceChannel(id: id, name: 'Channel ${id + 1}', start: start, stop: stop, gpioPin: 2);

DesignScheduleEligibility verdict(List<DeviceChannel> live) =>
    designScheduleEligibility(
      design: design(),
      onLan: true,
      liveChannels: live,
      liveControllerId: 'ctl-a',
      firmwareVersion: '0.15.4',
      architecture: 'esp32',
    );

void main() {
  group('busStartsProblem', () {
    test('end to end → null', () {
      expect(busStartsProblem([ch(0, 0, 100), ch(1, 100, 200), ch(2, 200, 300)]),
          isNull);
    });

    test('a gap names the first bus that does not start where the last ended',
        () {
      expect(busStartsProblem([ch(0, 0, 100), ch(1, 110, 210), ch(2, 210, 310)]),
          (channel: 1, start: 110, expected: 100));
    });

    test('an overlap is caught too', () {
      expect(busStartsProblem([ch(0, 0, 100), ch(1, 90, 190)]),
          (channel: 1, start: 90, expected: 100));
    });

    test('a first bus that does not start at zero', () {
      expect(busStartsProblem([ch(0, 10, 110)]),
          (channel: 0, start: 10, expected: 0));
    });

    test('judged by id order, not list order; zero-length buses skipped', () {
      expect(
          busStartsProblem([ch(2, 200, 300), ch(0, 0, 100), ch(1, 100, 200)]),
          isNull);
      expect(busStartsProblem([ch(0, 0, 100), ch(1, 100, 100), ch(2, 100, 200)]),
          isNull);
    });
  });

  group('pick time', () {
    test('buses with a gap: refused with a truthful sentence (fail-before: '
        'lengths matched, so b4b09f2 allowed it)', () {
      final v = verdict([ch(0, 0, 100), ch(1, 110, 210), ch(2, 210, 310)]);
      expect(v.verdict, DesignScheduleVerdict.layoutMismatch);
      expect(v.message, contains("aren't laid out end to end"));
      expect(v.message, contains('channel 2 starts at light 111 instead of 101'));
      expect(v.message, contains('"Porch stripes"'));
      expect(v.body, isNull);
    });

    test('end to end: allowed', () {
      expect(verdict([ch(0, 0, 100), ch(1, 100, 200), ch(2, 200, 300)]).verdict,
          DesignScheduleVerdict.allowed);
    });

    test('no bus data keeps the "layout not read yet" verdict', () {
      final v = verdict(const []);
      expect(v.verdict, DesignScheduleVerdict.layoutUnknown);
      expect(v.message, contains("Couldn't read your controller's layout"));
    });

    test('the slice 1 fit gate still wins when a length differs', () {
      final v = verdict([ch(0, 0, 100), ch(1, 100, 220), ch(2, 220, 320)]);
      expect(v.verdict, DesignScheduleVerdict.layoutMismatch);
      expect(v.message, contains('120 now'));
    });
  });
}
