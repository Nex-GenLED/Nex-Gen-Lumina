// Roofline slice 2 — the painted-design API-preset builder and its gates.
//
// NEW-BEHAVIOUR tests (nothing built an `o:true` body before this slice):
// body shape per bus with stamp-derived bounds, the byte gate at the cap, the
// firmware allowlist, the shape validator, the live-bounds match, the
// per-account count, and the eligibility matrix in the owner's order.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';

final _now = DateTime(2026, 11, 5);

const kRed = [255, 0, 0, 0];
const kBlue = [0, 0, 255, 0];

/// Three buses: 100 / 120 / 100 on controller ctl-a (the slice 1 bench shape).
const kStamp = DesignLayoutStamp(
    controllerId: 'ctl-a', busLengths: [100, 120, 100]);

const kLiveThree = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 220, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 220, stop: 320, gpioPin: 12),
];
const kLiveDense = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 150, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 150, stop: 300, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 300, stop: 450, gpioPin: 12),
];
const kLiveTwo = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 220, gpioPin: 14),
];

ChannelDesign channel(int id, int ledCount,
        {bool included = true, List<LedColorGroup>? groups}) =>
    ChannelDesign(
      channelId: id,
      channelName: 'Channel ${id + 1}',
      included: included,
      ledCount: ledCount,
      colorGroups: groups ??
          [
            LedColorGroup(startLed: 0, endLed: ledCount ~/ 2 - 1, color: kRed),
            LedColorGroup(
                startLed: ledCount ~/ 2, endLed: ledCount - 1, color: kBlue),
          ],
    );

/// A painted design over the three buses; two runs per channel by default.
CustomDesign design({
  DesignLayoutStamp? stamp = kStamp,
  List<ChannelDesign>? channels,
  int brightness = 180,
  bool? brightnessStated = true,
  bool perPixel = true,
}) =>
    CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: perPixel,
      brightness: brightness,
      brightnessStated: brightnessStated,
      layoutStamp: stamp,
      channels: channels ??
          [channel(0, 100), channel(1, 120), channel(2, 100)],
    );

/// Every LED a different colour from its neighbours, so nothing compresses:
/// the shape a dense "every other LED" paint or a gradient takes.
CustomDesign denseDesign(List<int> lengths) {
  const palette = [
    [255, 0, 0, 0],
    [0, 255, 0, 0],
    [0, 0, 255, 0],
  ];
  return design(
    stamp: DesignLayoutStamp(controllerId: 'ctl-a', busLengths: lengths),
    channels: [
      for (var id = 0; id < lengths.length; id++)
        channel(id, lengths[id], groups: [
          for (var led = 0; led < lengths[id]; led++)
            LedColorGroup(
                startLed: led, endLed: led, color: palette[led % 3]),
        ]),
    ],
  );
}

ScheduleItem schedule(String id, {bool design = false}) => ScheduleItem(
      id: id,
      timeLabel: '7:00 PM',
      repeatDays: const ['Mon'],
      actionLabel: 'Pattern: $id',
      enabled: true,
      wledPayload: const {'on': true},
      designId: design ? 'design-$id' : null,
      presetKind: design ? kSchedulePresetKindApi : null,
    );

DesignScheduleEligibility eligible(
  CustomDesign d, {
  bool onLan = true,
  List<DeviceChannel> live = kLiveThree,
  String? controllerId = 'ctl-a',
  String? firmware = '0.15.4',
  int count = 0,
}) =>
    designScheduleEligibility(
      design: d,
      onLan: onLan,
      liveChannels: live,
      liveControllerId: controllerId,
      firmwareVersion: firmware,
      existingDesignScheduleCount: count,
    );

void main() {
  // A1 (bench 2026-11-06): the body is BOUNDS-FIRST — a group of
  // {id,start,stop} entries for every bus, then the paint entries without
  // bounds, then the left-out buses as on:false. design_api_preset_shape_test
  // pins the ordering and the cold-boot golden; these pin the per-bus content.
  group('buildDesignApiPresetBody — bounds group, then paint per bus', () {
    test('three buses 100/120/100 → bounds ids 0/1/2, starts 0/100/220, '
        'stops 100/220/320, then three paint entries', () {
      final body = buildDesignApiPresetBody(design())!;
      expect(body['o'], isTrue);
      expect(body['on'], isTrue);
      expect(body['bri'], 180, reason: 'the stated brightness');
      expect(body.containsKey('ib'), isFalse);
      expect(body.containsKey('sb'), isFalse);

      final seg = body['seg'] as List;
      expect(seg.length, 6);
      final bounds = seg.sublist(0, 3);
      final paint = seg.sublist(3, 6);
      expect(bounds.map((s) => s['id']), [0, 1, 2]);
      expect(bounds.map((s) => s['start']), [0, 100, 220]);
      expect(bounds.map((s) => s['stop']), [100, 220, 320]);
      expect(paint.map((s) => s['id']), [0, 1, 2]);
      for (final s in paint) {
        expect(s.containsKey('start'), isFalse);
        expect(s.containsKey('stop'), isFalse);
        expect(s['on'], isTrue);
        expect(s['fx'], 0);
        expect(s['grp'], 1);
        expect(s['spc'], 0);
        expect(s['pal'], 0);
        expect(s['col'], [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ]);
      }
      // Channel-local, range-compressed, stop exclusive, covering the bus.
      expect(paint[0]['i'], [0, 50, kRed, 50, 100, kBlue]);
      expect(paint[1]['i'], [0, 60, kRed, 60, 120, kBlue]);
      expect(paint[2]['i'], [0, 50, kRed, 50, 100, kBlue]);
    });

    test('a channel the design leaves out is bounded in the group and comes '
        'last as on:false, no paint', () {
      final body = buildDesignApiPresetBody(design(channels: [
        channel(0, 100),
        channel(1, 120, included: false),
        channel(2, 100),
      ]))!;
      final seg = body['seg'] as List;
      expect(seg.map((s) => s['id']), [0, 1, 2, 0, 2, 1]);
      expect(seg[1], {'id': 1, 'start': 100, 'stop': 220});
      expect(seg[5], {'id': 1, 'start': 100, 'stop': 220, 'on': false});
      expect(seg[3]['i'], isA<List>());
      expect(seg[4]['i'], isA<List>());
    });

    test('a bus the design has no channel for is still bounded (dark)', () {
      final body =
          buildDesignApiPresetBody(design(channels: [channel(0, 100)]))!;
      final seg = body['seg'] as List;
      expect(seg.length, 6);
      expect(seg.sublist(0, 3).map((s) => s['id']), [0, 1, 2]);
      expect(seg[3]['id'], 0);
      expect(seg[4], {'id': 1, 'start': 100, 'stop': 220, 'on': false});
      expect(seg[5], {'id': 2, 'start': 220, 'stop': 320, 'on': false});
    });

    test('a zero-length bus in the stamp gets no entry; offsets still accumulate',
        () {
      final body = buildDesignApiPresetBody(design(
        stamp: const DesignLayoutStamp(busLengths: [100, 0, 100]),
        channels: [channel(0, 100), channel(2, 100)],
      ))!;
      final seg = body['seg'] as List;
      expect(seg.map((s) => s['id']), [0, 2, 0, 2]);
      expect(seg[1]['start'], 100);
      expect(seg[1]['stop'], 200);
    });

    test('a channel shorter than its bus is padded black to the bus end', () {
      final body = buildDesignApiPresetBody(design(channels: [
        channel(0, 80, groups: const [
          LedColorGroup(startLed: 0, endLed: 79, color: kRed),
        ]),
        channel(1, 120),
        channel(2, 100),
      ]))!;
      final seg = body['seg'] as List;
      expect(seg[3]['i'], [0, 80, kRed, 80, 100, [0, 0, 0, 0]]);
    });

    test('a channel longer than its bus is clipped to the bus', () {
      final body = buildDesignApiPresetBody(design(channels: [
        channel(0, 150, groups: const [
          LedColorGroup(startLed: 0, endLed: 149, color: kRed),
        ]),
        channel(1, 120),
        channel(2, 100),
      ]))!;
      final seg = body['seg'] as List;
      expect(seg[3]['i'], [0, 100, kRed]);
    });

    test('no stated brightness → 255 (an ON action is never saved dark)', () {
      final body = buildDesignApiPresetBody(
          design(brightness: 0, brightnessStated: false))!;
      expect(body['bri'], 255);
    });

    test('not positional, or unstamped → null', () {
      expect(buildDesignApiPresetBody(design(stamp: null)), isNull);
      final effect = CustomDesign(
        id: 'e',
        name: 'Effect',
        ownerId: 'u',
        createdAt: _now,
        updatedAt: _now,
        layoutStamp: kStamp,
        channels: [
          ChannelDesign(
              channelId: 0,
              channelName: 'Channel 1',
              ledCount: 100,
              effectId: 28,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 0, color: kRed),
              ]),
        ],
      );
      expect(effect.isPositional, isFalse);
      expect(buildDesignApiPresetBody(effect), isNull);
    });
  });

  group('byte gate', () {
    test('wire bytes count psave and the name', () {
      final body = buildDesignApiPresetBody(design())!;
      final bare = designApiPresetWireBytes(body, presetId: 10, presetName: '');
      final named = designApiPresetWireBytes(body,
          presetId: 25, presetName: 'Pattern: Porch stripes');
      expect(named - bare, 'Pattern: Porch stripes'.length,
          reason: 'the name (slots 10 and 25 are both two digits)');
    });

    test('the cap is one named constant, 4,000 (bench 2026-11-06: the dense '
        'shape was refused at 4,700 B and passed at 4,505 B)', () {
      expect(kDesignApiPresetMaxBytes, 4000);
    });

    test('a simple three-bus design is well under the cap → allowed', () {
      final v = eligible(design());
      expect(v.verdict, DesignScheduleVerdict.allowed);
      expect(v.bytes, lessThan(kDesignApiPresetMaxBytes));
      expect(v.body, isNotNull);
      expect(v.offersEditor, isFalse);
    });

    test('a dense design over the cap → refused, names the limit, offers the editor',
        () {
      final v = eligible(denseDesign(const [150, 150, 150]), live: kLiveDense);
      expect(v.verdict, DesignScheduleVerdict.tooLarge);
      expect(v.bytes, greaterThan(kDesignApiPresetMaxBytes));
      expect(v.body, isNull, reason: 'nothing to store on a refusal');
      expect(v.offersEditor, isTrue);
      expect(v.message, contains('"Porch stripes"'));
      expect(v.message, contains('4,000 bytes'));
      expect(v.message, contains('about 4.0 KB'));
      expect(v.message, contains('simplify'));
    });

    test('exactly at the cap is allowed; one byte over is refused', () {
      // Grow a name until the body lands exactly on the cap.
      final d = design();
      final body = buildDesignApiPresetBody(d)!;
      final base = designApiPresetWireBytes(body,
          presetId: kLastSchedulePresetId, presetName: '');
      final pad = 'x' * (kDesignApiPresetMaxBytes - base);
      final at = designScheduleEligibility(
          design: d,
          onLan: true,
          liveChannels: kLiveThree,
          liveControllerId: 'ctl-a',
          firmwareVersion: '0.15.4',
          existingDesignScheduleCount: 0,
          presetName: pad);
      expect(at.bytes, kDesignApiPresetMaxBytes);
      expect(at.verdict, DesignScheduleVerdict.allowed);
      final over = designScheduleEligibility(
          design: d,
          onLan: true,
          liveChannels: kLiveThree,
          liveControllerId: 'ctl-a',
          firmwareVersion: '0.15.4',
          existingDesignScheduleCount: 0,
          presetName: '${pad}y');
      expect(over.verdict, DesignScheduleVerdict.tooLarge);
    });
  });

  group('firmware allowlist', () {
    test('0.15.4 only, exact after trim', () {
      expect(kDesignApiPresetProvenFirmware, {'0.15.4'});
      expect(isDesignApiPresetFirmwareProven('0.15.4'), isTrue);
      expect(isDesignApiPresetFirmwareProven(' 0.15.4 '), isTrue);
      expect(isDesignApiPresetFirmwareProven('0.15.1'), isFalse);
      expect(isDesignApiPresetFirmwareProven('16.0.1'), isFalse);
      expect(isDesignApiPresetFirmwareProven('0.15.4-b1'), isFalse);
      expect(isDesignApiPresetFirmwareProven(''), isFalse);
      expect(isDesignApiPresetFirmwareProven(null), isFalse);
    });
  });

  group('body shape and live bounds', () {
    test('isDesignApiPresetBody keys off o:true alone', () {
      expect(isDesignApiPresetBody({'o': true}), isTrue);
      expect(isDesignApiPresetBody({'o': false}), isFalse);
      expect(isDesignApiPresetBody({'on': true, 'seg': []}), isFalse);
      expect(isDesignApiPresetBody(null), isFalse);
    });

    test('the builder output has no problem', () {
      expect(designApiPresetBodyProblem(buildDesignApiPresetBody(design())),
          isNull);
    });

    test('a stored body missing o, the bounds group, or paint is named as '
        'the problem', () {
      expect(designApiPresetBodyProblem(null), 'no payload');
      expect(designApiPresetBodyProblem({'on': true, 'seg': []}),
          contains('no o:true'));
      expect(designApiPresetBodyProblem({'o': true, 'seg': []}),
          contains('no seg entries'));
      // Paint with no bounds group before it.
      expect(
          designApiPresetBodyProblem({
            'o': true,
            'seg': [
              {'id': 0, 'on': true, 'i': []}
            ]
          }),
          contains('no bounds entries before the paint'));
      // A bounds entry that is empty.
      expect(
          designApiPresetBodyProblem({
            'o': true,
            'seg': [
              {'id': 0, 'start': 100, 'stop': 100},
              {'id': 0, 'on': true, 'i': []}
            ]
          }),
          contains('stop 100 <= start 100'));
      // A bounds entry lacking a field.
      expect(
          designApiPresetBodyProblem({
            'o': true,
            'seg': [
              {'id': 0, 'start': 0},
            ]
          }),
          contains('lacks int id/start/stop'));
      // A lit entry with no picture (the group entry is fine).
      expect(
          designApiPresetBodyProblem({
            'o': true,
            'seg': [
              {'id': 0, 'start': 0, 'stop': 100},
              {'id': 0, 'on': true}
            ]
          }),
          contains('no i array'));
      // The b4b09f2 shape — bounds and paint in one entry — is refused by
      // name (it painted one bus after a cold boot, bench 2026-11-06).
      expect(
          designApiPresetBodyProblem({
            'o': true,
            'seg': [
              {'id': 0, 'start': 0, 'stop': 100, 'on': true, 'i': []}
            ]
          }),
          contains('paint entry carries start/stop'));
      // Paint for an id the group never bounded.
      expect(
          designApiPresetBodyProblem({
            'o': true,
            'seg': [
              {'id': 0, 'start': 0, 'stop': 100},
              {'id': 1, 'on': true, 'i': []}
            ]
          }),
          contains('no bounds entry before it'));
      // A left-out entry whose bounds drift from its group entry.
      expect(
          designApiPresetBodyProblem({
            'o': true,
            'seg': [
              {'id': 0, 'start': 0, 'stop': 100},
              {'id': 0, 'start': 0, 'stop': 90, 'on': false}
            ]
          }),
          contains('bounds differ from its bounds entry'));
    });

    test('bounds match the live buses exactly, or not at all', () {
      final body = buildDesignApiPresetBody(design())!;
      const three = [
        SegmentShape(0, 0, 100),
        SegmentShape(1, 100, 220),
        SegmentShape(2, 220, 320),
      ];
      expect(designApiPresetBoundsMatch(body, three), isTrue);
      expect(designApiPresetBoundsMatch(body, const []), isFalse,
          reason: 'no live buses = unread, never a match');
      expect(
          designApiPresetBoundsMatch(body, const [
            SegmentShape(0, 0, 100),
            SegmentShape(1, 100, 200),
            SegmentShape(2, 200, 300),
          ]),
          isFalse,
          reason: 'bus 2 is 100 live, 120 in the body');
      expect(
          designApiPresetBoundsMatch(body, const [
            SegmentShape(0, 0, 100),
            SegmentShape(1, 100, 220),
          ]),
          isFalse,
          reason: 'the body names a bus the controller lacks');
      expect(
          designApiPresetBoundsMatch(body, const [
            SegmentShape(0, 0, 100),
            SegmentShape(1, 100, 220),
            SegmentShape(2, 220, 320),
            SegmentShape(3, 320, 400),
          ]),
          isFalse,
          reason: 'the controller has a bus the body does not cover');
    });
  });

  group('per-account cap', () {
    test('counts painted designs, excluding the one being edited', () {
      final list = [
        schedule('a', design: true),
        schedule('b', design: true),
        schedule('c'),
      ];
      expect(designScheduleCount(list), 2);
      expect(designScheduleCount(list, excludingId: 'a'), 1);
      expect(kMaxDesignSchedulesPerAccount, 4);
    });

    test('a fifth painted design is refused with a plain message', () {
      final four = [for (var k = 0; k < 4; k++) schedule('s$k', design: true)];
      final msg = designScheduleCountRefusal(
          candidate: schedule('new', design: true), schedules: four);
      expect(msg, isNotNull);
      expect(msg, contains('4 painted designs'));
      expect(msg, contains('"new"'));
    });

    test('editing one of four, a catalog pattern, or three + one are fine', () {
      final four = [for (var k = 0; k < 4; k++) schedule('s$k', design: true)];
      expect(
          designScheduleCountRefusal(
              candidate: schedule('s1', design: true),
              schedules: four,
              editingId: 's1'),
          isNull);
      expect(
          designScheduleCountRefusal(candidate: schedule('p'), schedules: four),
          isNull);
      expect(
          designScheduleCountRefusal(
              candidate: schedule('new', design: true),
              schedules: four.sublist(0, 3)),
          isNull);
    });
  });

  group('eligibility matrix (owner decision 4, in order)', () {
    test('all gates pass → allowed with the body', () {
      final v = eligible(design());
      expect(v.allowed, isTrue);
      expect(v.message, isNull);
      expect(v.body!['o'], isTrue);
    });

    test('unstamped → refused, re-save from the editor', () {
      final v = eligible(design(stamp: null));
      expect(v.verdict, DesignScheduleVerdict.unstamped);
      expect(v.message, contains('"Porch stripes"'));
      expect(v.message, contains('save it again'));
    });

    test('off the LAN → refused before any layout or firmware question', () {
      final v = eligible(design(), onLan: false, live: const [], firmware: null);
      expect(v.verdict, DesignScheduleVerdict.offLan);
      expect(v.message, contains('home network'));
    });

    test('on the LAN with no bus data → layout unknown', () {
      final v = eligible(design(), live: const []);
      expect(v.verdict, DesignScheduleVerdict.layoutUnknown);
      expect(v.message, contains('layout'));
    });

    test('bus count differs → the fit gate sentence', () {
      final v = eligible(design(), live: kLiveTwo);
      expect(v.verdict, DesignScheduleVerdict.layoutMismatch);
      expect(v.message, contains('3 channels'));
      expect(v.message, contains('has 2 now'));
    });

    test('a bus length differs → the fit gate sentence', () {
      final v = eligible(design(), live: const [
        DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
        DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
        DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
      ]);
      expect(v.verdict, DesignScheduleVerdict.layoutMismatch);
      expect(v.message, contains('120 lights on channel 2'));
      expect(v.message, contains('has 100 now'));
    });

    test('a different controller record → refused; no record → lengths decide',
        () {
      expect(eligible(design(), controllerId: 'ctl-b').verdict,
          DesignScheduleVerdict.layoutMismatch);
      expect(eligible(design(), controllerId: null).verdict,
          DesignScheduleVerdict.allowed);
    });

    test('firmware unreadable → refused; unproven → refused naming the version',
        () {
      expect(eligible(design(), firmware: null).verdict,
          DesignScheduleVerdict.firmwareUnreadable);
      expect(eligible(design(), firmware: '  ').verdict,
          DesignScheduleVerdict.firmwareUnreadable);
      final v = eligible(design(), firmware: '0.15.1');
      expect(v.verdict, DesignScheduleVerdict.firmwareUnproven);
      expect(v.message, contains('WLED 0.15.1'));
      expect(v.message, contains('0.15.4'));
      expect(v.message, contains('My Designs'));
      expect(eligible(design(), firmware: '16.0.1').verdict,
          DesignScheduleVerdict.firmwareUnproven);
    });

    test('four already on the schedule → refused as the fifth', () {
      final v = eligible(design(), count: 4);
      expect(v.verdict, DesignScheduleVerdict.tooMany);
      expect(v.message, contains('4 painted designs'));
      expect(eligible(design(), count: 3).verdict,
          DesignScheduleVerdict.allowed);
    });

    test('the byte cap is judged before the count', () {
      final v = eligible(denseDesign(const [150, 150, 150]),
          live: kLiveDense, count: 4);
      expect(v.verdict, DesignScheduleVerdict.tooLarge);
    });

    test('an effect design is not positional → notPositional', () {
      expect(eligible(design(perPixel: false, channels: [
        ChannelDesign(
            channelId: 0,
            channelName: 'Channel 1',
            ledCount: 100,
            effectId: 28,
            colorGroups: const [
              LedColorGroup(startLed: 0, endLed: 0, color: kRed),
            ]),
      ])).verdict, DesignScheduleVerdict.notPositional);
    });
  });
}
