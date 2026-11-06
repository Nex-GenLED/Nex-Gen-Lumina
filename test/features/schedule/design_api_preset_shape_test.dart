// Roofline slice 2, A1 — the BOUNDS-FIRST body shape.
//
// FAIL-BEFORE on b4b09f2. Bench 2026-11-06 (spare .179, WLED 0.15.4, classic
// ESP32): after a cold boot WLED holds ONE segment, so a body that puts bounds
// and paint in the same entry appends ids 1 and 2 as full-strip segments, and
// `Segment::setUp` fills each appended segment's old range black before taking
// the new bounds — every append wipes the frozen paint already laid on the
// earlier buses, and only the last bus survived (power cycle #1). The shape
// that painted every bus from a cold boot (power cycle #2): first one
// `{id,start,stop}` entry per bus (left-out buses included, bus order), then
// one paint entry per painted bus with NO start/stop, then each left-out bus
// as `{id,start,stop,on:false}`.
//
// The golden below is the segment array recorded for power cycle #2
// (bench-s2-results/results.md, design/wire-nomid-bf.json), compared as
// parsed JSON.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';

final _now = DateTime(2026, 11, 6);

/// The spare as it reported itself: three buses of 100.
const kSpareStamp =
    DesignLayoutStamp(controllerId: 'spare-ed030c', busLengths: [100, 100, 100]);

/// A base colour with single-LED accents at [accentLeds]: the groups the
/// editor stores when accents are painted over a base.
List<LedColorGroup> paint(
    List<int> base, List<int> accent, List<int> accentLeds, int len) {
  final out = <LedColorGroup>[];
  var cursor = 0;
  for (final a in accentLeds) {
    if (a > cursor) {
      out.add(LedColorGroup(startLed: cursor, endLed: a - 1, color: base));
    }
    out.add(LedColorGroup(startLed: a, endLed: a, color: accent));
    cursor = a + 1;
  }
  if (cursor < len) {
    out.add(LedColorGroup(startLed: cursor, endLed: len - 1, color: base));
  }
  return out;
}

ChannelDesign ch0({bool included = true}) => ChannelDesign(
    channelId: 0,
    channelName: 'Channel 1',
    included: included,
    ledCount: 100,
    colorGroups:
        paint([0, 0, 120, 0], [255, 255, 255, 0], [10, 30, 50, 70, 90], 100));
ChannelDesign ch1({bool included = true}) => ChannelDesign(
    channelId: 1,
    channelName: 'Channel 2',
    included: included,
    ledCount: 100,
    colorGroups: paint([120, 0, 0, 0], [0, 255, 0, 0], [15, 45, 75], 100));
ChannelDesign ch2({bool included = true}) => ChannelDesign(
    channelId: 2,
    channelName: 'Channel 3',
    included: included,
    ledCount: 100,
    colorGroups: paint([0, 120, 0, 0], [255, 0, 255, 0], [20, 40, 60, 80], 100));

/// "Bench nightly 3-bus" exactly as the bench scratch test built it.
CustomDesign benchDesign({
  DesignLayoutStamp stamp = kSpareStamp,
  List<ChannelDesign>? channels,
}) =>
    CustomDesign(
      id: 'bench-nightly-3bus',
      name: 'Bench nightly 3-bus',
      ownerId: 'bench',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: 180,
      brightnessStated: true,
      layoutStamp: stamp,
      channels: channels ?? [ch0(), ch1(), ch2()],
    );

/// results.md, "Power cycle #2 — bounds-first body, middle channel excluded":
/// the `seg` array of design/wire-nomid-bf.json (770 B wire, 202 elements),
/// which fired from a cold boot with buses 0 and 2 painted and bus 1 dark.
const String kRecordedPowerCycle2Seg =
    '[{"id":0,"start":0,"stop":100},{"id":1,"start":100,"stop":200},'
    '{"id":2,"start":200,"stop":300},'
    '{"id":0,"on":true,"fx":0,"grp":1,"spc":0,"pal":0,'
    '"col":[[0,0,0,0],[0,0,0,0],[0,0,0,0]],'
    '"i":[0,10,[0,0,120,0],10,[255,255,255,0],11,30,[0,0,120,0],30,'
    '[255,255,255,0],31,50,[0,0,120,0],50,[255,255,255,0],51,70,[0,0,120,0],'
    '70,[255,255,255,0],71,90,[0,0,120,0],90,[255,255,255,0],91,100,'
    '[0,0,120,0]]},'
    '{"id":2,"on":true,"fx":0,"grp":1,"spc":0,"pal":0,'
    '"col":[[0,0,0,0],[0,0,0,0],[0,0,0,0]],'
    '"i":[0,20,[0,120,0,0],20,[255,0,255,0],21,40,[0,120,0,0],40,'
    '[255,0,255,0],41,60,[0,120,0,0],60,[255,0,255,0],61,80,[0,120,0,0],80,'
    '[255,0,255,0],81,100,[0,120,0,0]]},'
    '{"id":1,"start":100,"stop":200,"on":false}]';

List<Map<String, dynamic>> segOf(CustomDesign d) =>
    (buildDesignApiPresetBody(d)!['seg'] as List)
        .cast<Map<String, dynamic>>();

bool isPaint(Map<String, dynamic> s) => s['i'] is List;
bool isOff(Map<String, dynamic> s) => s['on'] == false;
bool isBounds(Map<String, dynamic> s) => !isPaint(s) && !isOff(s);

void main() {
  group('bounds-first shape (fail-before on b4b09f2)', () {
    test('every bounds entry precedes every paint entry, and paint entries '
        'carry no start or stop', () {
      final seg = segOf(benchDesign());
      final firstPaint = seg.indexWhere(isPaint);
      final lastBounds = seg.lastIndexWhere(isBounds);
      expect(firstPaint, greaterThanOrEqualTo(0), reason: 'something is painted');
      expect(lastBounds, lessThan(firstPaint),
          reason: 'a bounds entry after a paint entry appends a full-strip '
              'segment on a cold boot and wipes the paint already laid');
      for (final s in seg.where(isPaint)) {
        expect(s.containsKey('start'), isFalse,
            reason: 'paint entry ${s['id']} carries start');
        expect(s.containsKey('stop'), isFalse,
            reason: 'paint entry ${s['id']} carries stop');
      }
      for (final s in seg.where(isBounds)) {
        expect(s.keys.toSet(), {'id', 'start', 'stop'},
            reason: 'a bounds entry carries only id/start/stop');
      }
    });

    test('golden: three buses 100/100/100, middle channel excluded, equals '
        'the segment array that fired from a cold boot on the spare', () {
      final seg = segOf(benchDesign(channels: [ch0(), ch1(included: false), ch2()]));
      expect(jsonDecode(jsonEncode(seg)), jsonDecode(kRecordedPowerCycle2Seg));
    });

    test('left-out buses are bounded in the first group and come back last as '
        '{id,start,stop,on:false}, in bus order', () {
      final seg = segOf(benchDesign(
          channels: [ch0(included: false), ch1(), ch2(included: false)]));
      expect(seg.map((s) => s['id']).toList(), [0, 1, 2, 1, 0, 2]);
      expect(seg[4], {'id': 0, 'start': 0, 'stop': 100, 'on': false});
      expect(seg[5], {'id': 2, 'start': 200, 'stop': 300, 'on': false});
      expect(seg.where(isPaint).map((s) => s['id']), [1]);
    });

    test('one bus: one bounds entry, then its paint', () {
      final seg = segOf(benchDesign(
          stamp: const DesignLayoutStamp(
              controllerId: 'one', busLengths: [100]),
          channels: [ch0()]));
      expect(seg.length, 2);
      expect(seg[0], {'id': 0, 'start': 0, 'stop': 100});
      expect(isPaint(seg[1]), isTrue);
      expect(seg[1]['id'], 0);
      expect(seg[1].containsKey('start'), isFalse);
    });

    test('six buses, all painted: six bounds entries with cumulative offsets, '
        'then six paint entries in bus order, no off entries', () {
      final seg = segOf(benchDesign(
          stamp: const DesignLayoutStamp(
              controllerId: 'six', busLengths: [100, 100, 100, 100, 100, 100]),
          channels: [
            for (var id = 0; id < 6; id++)
              ChannelDesign(
                  channelId: id,
                  channelName: 'Channel ${id + 1}',
                  ledCount: 100,
                  colorGroups: paint(
                      [0, 0, 120, 0], [255, 255, 255, 0], [10, 30, 50, 70, 90], 100)),
          ]));
      expect(seg.length, 12);
      for (var id = 0; id < 6; id++) {
        expect(seg[id], {'id': id, 'start': id * 100, 'stop': (id + 1) * 100});
        expect(isPaint(seg[6 + id]), isTrue);
        expect(seg[6 + id]['id'], id);
      }
      expect(seg.any(isOff), isFalse);
    });

    test('all three painted: three bounds entries, three paint entries, '
        'no off entries; the paint keeps the app fields', () {
      final seg = segOf(benchDesign());
      expect(seg.map((s) => s['id']).toList(), [0, 1, 2, 0, 1, 2]);
      expect(seg.any(isOff), isFalse);
      for (final s in seg.where(isPaint)) {
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
    });

    test('the root is unchanged: o:true, on:true, the stated brightness', () {
      final body = buildDesignApiPresetBody(benchDesign())!;
      expect(body['o'], isTrue);
      expect(body['on'], isTrue);
      expect(body['bri'], 180);
      expect(body.keys.toList(), ['o', 'on', 'bri', 'seg']);
    });

    test('the builder output passes its own shape check, and a body with '
        'bounds on a paint entry does not', () {
      final body = buildDesignApiPresetBody(benchDesign())!;
      expect(designApiPresetBodyProblem(body), isNull);
      final old = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
      // The b4b09f2 shape: bounds and paint in one entry.
      final seg = (old['seg'] as List).cast<Map<String, dynamic>>();
      final merged = [
        for (var k = 0; k < 3; k++) {...seg[k], ...seg[3 + k]},
      ];
      old['seg'] = merged;
      expect(designApiPresetBodyProblem(old), isNotNull);
      expect(designApiPresetBodyProblem(old), contains('start/stop'));
    });
  });
}
