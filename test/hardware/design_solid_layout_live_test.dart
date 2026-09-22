// LIVE HARDWARE TEST — requires the bench controller at kBenchIp (2 channels:
// 0–128 and 128–290). NOT part of the normal suite: it performs real network
// I/O and changes what the lights show (never presets, never /json/cfg), then
// puts the look back. Without the define every test skips.
//
//   flutter test test/hardware/design_solid_layout_live_test.dart \
//     --dart-define=RUN_HW=true
//
// Part B of the design-card layout fix (audit/DESIGN_CARD_BLOCKS_LAYOUT_AUDIT_
// 2026-09-22.md): a saved design with a STORED Blocks | Alternating layout,
// re-applied the way My Designs applies it (`applyChannelFilter(
// design.toWledPayload(), …)` → `applyJson`), reaches the controller in that
// layout. Verified from the CONTROLLER — `/json/state` read back and full
// liveview frames — not from the payload that was sent.
//
// Bracket: /json/state, presets.json and cfg.json are captured first; the
// look is restored at the end; the three are compared / hashed again and the
// uptime is checked so a reboot could not hide behind a matching state.
//
// Numbering continues the audits' bench logs (T35–T38).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kBenchIp = '192.168.1.150';
const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];

const _red = [255, 0, 0, 0];
const _white = [255, 255, 255, 0];
const _blue = [0, 0, 255, 0];

final _now = DateTime(2026, 9, 22);

/// A palette-shaped Solid design (one single-LED group per colour, no
/// led_count — what the tuner and the colour editor save), one channel per
/// bench segment, with the layout under test STORED on it.
CustomDesign _design(String name, List<List<int>> colors, SolidLayout layout) =>
    CustomDesign(
      id: 'zz-probe-${name.toLowerCase().replaceAll(' ', '-')}',
      name: name,
      ownerId: 'PROBE',
      createdAt: _now,
      updatedAt: _now,
      brightness: 200,
      channels: [
        for (final ch in _channels)
          ChannelDesign(
            channelId: ch.id,
            channelName: ch.name,
            effectId: 0,
            speed: 128,
            intensity: 128,
            solidLayout: layout,
            colorGroups: [
              for (var i = 0; i < colors.length; i++)
                LedColorGroup(startLed: i, endLed: i, color: colors[i]),
            ],
          ),
      ],
    );

Future<List<List<List<int>>>> _frames(Duration duration) async {
  final ws = await WebSocket.connect('ws://$kBenchIp/ws');
  final frames = <List<List<int>>>[];
  final sub = ws.listen((msg) {
    if (msg is! List<int> || msg.isEmpty || msg[0] != 76 /* 'L' */) return;
    final off = msg[1] == 2 ? 4 : 2;
    frames.add([
      for (int i = off; i + 2 < msg.length; i += 3) [msg[i], msg[i + 1], msg[i + 2]],
    ]);
  });
  ws.add(jsonEncode({'lv': true}));
  await Future<void>.delayed(duration);
  ws.add(jsonEncode({'lv': false}));
  await sub.cancel();
  await ws.close();
  return frames;
}

/// One settled frame (past the 700 ms crossfade).
Future<List<List<int>>> _frame() async {
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  return (await _frames(const Duration(milliseconds: 900))).last;
}

/// Which of [colors] (RGBW) a liveview pixel (RGB) is nearest to — or -1 when
/// it is nowhere near any of them (a blend, or dark).
int _nearest(List<int> px, List<List<int>> colors) {
  var best = -1;
  var bestD = 1 << 30;
  for (var k = 0; k < colors.length; k++) {
    final c = colors[k];
    final d = (px[0] - c[0]) * (px[0] - c[0]) +
        (px[1] - c[1]) * (px[1] - c[1]) +
        (px[2] - c[2]) * (px[2] - c[2]);
    if (d < bestD) {
      bestD = d;
      best = k;
    }
  }
  return bestD <= 60 * 60 ? best : -1;
}

/// The segment fields a design owns, as the DEVICE reports them.
List<Map<String, dynamic>> _deviceLook(Map<String, dynamic> state) => [
      for (final s in (state['seg'] as List).cast<Map>())
        if ((s['stop'] as int? ?? 0) > 0)
          {
            for (final k in ['id', 'on', 'fx', 'sx', 'ix', 'pal', 'grp', 'spc', 'col', 'frz'])
              k: s[k],
          },
    ];

/// Each segment's `rev`, as the device reports it. A design never asserts
/// geometry (#76), so the bench's own direction is what the frames follow:
/// on a reversed segment virtual pixel 0 is the LAST physical LED. The bench
/// controller runs channel 1 reversed.
Map<int, bool> _revOf(Map<String, dynamic> state) => {
      for (final s in (state['seg'] as List).cast<Map>())
        if ((s['stop'] as int? ?? 0) > 0) s['id'] as int: s['rev'] == true,
    };

/// The VIRTUAL index (what the effect computes with) of physical LED [i] on
/// [ch], honouring the segment's direction.
int _virtual(DeviceChannel ch, int i, bool rev) =>
    rev ? (ch.stop - 1 - i) : (i - ch.start);

Future<String> _sha(String path) async {
  final req = await HttpClient().getUrl(Uri.parse('http://$kBenchIp/$path'));
  final res = await req.close();
  final bytes = <int>[];
  await for (final chunk in res) {
    bytes.addAll(chunk);
  }
  return '${sha256.convert(bytes)} (${bytes.length} B)';
}

Future<int> _uptime(WledService svc) async {
  final req = await HttpClient().getUrl(Uri.parse('http://$kBenchIp/json/info'));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  return (jsonDecode(body) as Map)['uptime'] as int;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WledService svc;
  Map<String, dynamic>? prior;
  String? presetsBefore;
  String? cfgBefore;
  int? uptimeBefore;

  setUpAll(() async {
    HttpOverrides.global = null; // flutter_test stubs HTTP with a 400
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!kRunHw) return;
    svc = WledService('http://$kBenchIp');
    prior = await svc.getState();
    presetsBefore = await _sha('presets.json');
    cfgBefore = await _sha('cfg.json');
    uptimeBefore = await _uptime(svc);
    // ignore: avoid_print
    print('HW prior: on=${prior?['on']} bri=${prior?['bri']} ps=${prior?['ps']} '
        'look=${_deviceLook(prior!)}\n  presets.json $presetsBefore\n  cfg.json $cfgBefore\n'
        '  uptime $uptimeBefore s');
  });

  tearDownAll(() async {
    if (!kRunHw) return;
    // Put the look back: the captured segments, then the preset it came from
    // (which also restores the `ps` pointer). Presets/cfg were never written.
    await restoreAfterFindLed(svc, prior);
    final ps = prior?['ps'];
    if (ps is int && ps > 0) await svc.applyJson({'ps': ps});
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final after = (await svc.getState())!;
    final presetsAfter = await _sha('presets.json');
    final cfgAfter = await _sha('cfg.json');
    final uptimeAfter = await _uptime(svc);
    // ignore: avoid_print
    print('HW restore: on=${after['on']} bri=${after['bri']} ps=${after['ps']} '
        'look=${_deviceLook(after)}\n  presets.json $presetsAfter\n  cfg.json $cfgAfter\n'
        '  uptime $uptimeAfter s');
    expect(jsonEncode(_deviceLook(after)), jsonEncode(_deviceLook(prior!)),
        reason: 'zero state diff on the segment fields');
    expect([after['on'], after['bri'], after['ps']], [prior!['on'], prior!['bri'], prior!['ps']]);
    expect(presetsAfter, presetsBefore, reason: 'presets.json untouched');
    expect(cfgAfter, cfgBefore, reason: 'cfg.json untouched');
    expect(uptimeAfter, greaterThan(uptimeBefore!), reason: 'no reboot');
  });

  /// Apply exactly as My Designs does (apply_saved_design.dart): the design's
  /// own payload, channel-filtered, through applyJson.
  Future<void> applyAsMyDesigns(CustomDesign d) async {
    final payload = applyChannelFilter(d.toWledPayload(), const [0, 1], _channels);
    expect(await svc.applyJson(payload), isTrue);
  }

  test('T35 — a design STORED as Alternating (3 colours) fires as fx 84 ix:0, '
      'and the strip alternates per bulb', () async {
    final d = _design('zz probe Alternating 3', [_red, _white, _blue], SolidLayout.alternating);
    // Round-trip through the stored form first: this is what My Designs reopens.
    final reopened = CustomDesign.fromFirestoreData(d.id, d.toFirestore());
    expect(reopened.channels.map((c) => c.solidLayout).toSet(), {SolidLayout.alternating});

    await applyAsMyDesigns(reopened);
    final frame = await _frame();
    final state = (await svc.getState())!;
    final look = _deviceLook(state);
    final rev = _revOf(state);
    // ignore: avoid_print
    print('T35 device look: $look rev=$rev\n  LEDs 0-8: ${frame.sublist(0, 9)}\n'
        '  LEDs 128-136: ${frame.sublist(128, 137)}');

    for (final s in look) {
      expect(s['fx'], 84, reason: 'seg ${s['id']}: fx 84 Solid Pattern Tri');
      expect(s['ix'], 0, reason: 'seg ${s['id']}: 1-px runs, width from grp');
      expect(s['sx'], 0);
      expect(s['grp'], 1);
      expect(s['pal'], 5);
      expect(s['frz'], isNot(true));
    }
    // Per-bulb alternation on both channels: virtual pixel v shows colour v % 3.
    var wrong = 0;
    for (final ch in _channels) {
      for (var i = ch.start; i < ch.stop; i++) {
        final v = _virtual(ch, i, rev[ch.id] ?? false);
        if (_nearest(frame[i], [_red, _white, _blue]) != v % 3) wrong++;
      }
    }
    expect(wrong, 0, reason: 'LEDs not in the r,w,b,r,w,b… cycle');
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 2)));

  test('T36 — a design STORED as Blocks (3 colours) still fires as fx 83 + pal 5, '
      'and the strip shows three contiguous blocks', () async {
    final d = _design('zz probe Blocks 3', [_red, _white, _blue], SolidLayout.blocks);
    final reopened = CustomDesign.fromFirestoreData(d.id, d.toFirestore());
    expect(reopened.channels.map((c) => c.solidLayout).toSet(), {SolidLayout.blocks});

    await applyAsMyDesigns(reopened);
    final frame = await _frame();
    final state = (await svc.getState())!;
    final look = _deviceLook(state);
    final rev = _revOf(state);
    // ignore: avoid_print
    print('T36 device look: $look rev=$rev\n  LEDs 0-8: ${frame.sublist(0, 9)}\n'
        '  LEDs 60-68: ${frame.sublist(60, 69)}\n  LEDs 119-127: ${frame.sublist(119, 128)}\n'
        '  LEDs 128-136: ${frame.sublist(128, 137)}\n  LEDs 281-289: ${frame.sublist(281, 290)}');

    for (final s in look) {
      expect(s['fx'], 83, reason: 'seg ${s['id']}: fx 83 Solid Pattern');
      expect(s['pal'], 5, reason: 'seg ${s['id']}: Colors Only → positional');
      expect(s['sx'], 128, reason: 'not pinned for Blocks');
      expect(s['ix'], 128);
      expect(s['frz'], isNot(true));
    }
    // Contiguous blocks in slot order along each channel's VIRTUAL axis, as
    // fx 83 "Solid Pattern" actually lays them out (FX.cpp, WLED 0.15.1):
    // a LIT band of `1 + sx` px coloured positionally from the pal-5 palette
    // over the whole virtual length, then an UNLIT band of `1 + ix` px of
    // col[1]. At the tuner defaults (sx = ix = 128) a segment up to 129 LEDs
    // is entirely lit — exact thirds — while the bench's 162-LED channel 1
    // shows thirds over 0–128 (red 54, white 54, blue 21) and col[1] white
    // on 129–161. Pre-existing, documented in solid_palette_blocks.dart, and
    // byte-identical to what Blocks fired before the layout field (T38).
    // Sampled away from the block boundaries (they blend) and away from the
    // last ~1/16 of the lit band (the palette's wrap entry fades to col[0]).
    int model(int v, int len, int sx, int ix) {
      final lit = 1 + sx, unlit = 1 + ix;
      if (v % (lit + unlit) >= lit) return 1; // unlit band: col[1]
      return solidPaletteBlockIndex(v, len, 3);
    }

    for (final ch in _channels) {
      final len = ch.stop - ch.start;
      final r = rev[ch.id] ?? false;
      final sx = look.firstWhere((s) => s['id'] == ch.id)['sx'] as int;
      final ix = look.firstWhere((s) => s['id'] == ch.id)['ix'] as int;
      final samples = <int>{
        len ~/ 6, len ~/ 2, 5 * len ~/ 6,
        // Just inside the lit band's tail, where the third block lives on a
        // channel longer than the band (162 → virtual 108–128 is blue).
        if (len > 1 + sx) (1 + sx) - 8,
      };
      for (final v in samples) {
        final phys = r ? ch.stop - 1 - v : ch.start + v;
        expect(_nearest(frame[phys], [_red, _white, _blue]), model(v, len, sx, ix),
            reason: 'channel ${ch.id} LED $phys (virtual $v of $len, sx $sx ix $ix)');
      }
      // The lit band starts with a run of col[0]: a contiguous block, not a
      // per-bulb cycle. Check the first three virtual pixels.
      for (var v = 0; v < 3; v++) {
        final phys = r ? ch.stop - 1 - v : ch.start + v;
        expect(_nearest(frame[phys], [_red, _white, _blue]), 0,
            reason: 'channel ${ch.id} virtual $v is in block 0 (not alternating)');
      }
    }
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 2)));

  test('T37 — a design STORED as Alternating (2 colours) fires as fx 83 + pal 0 '
      'sx:0 ix:0, and the strip alternates per bulb', () async {
    final d = _design('zz probe Alternating 2', [_red, _blue], SolidLayout.alternating);
    final reopened = CustomDesign.fromFirestoreData(d.id, d.toFirestore());

    await applyAsMyDesigns(reopened);
    final frame = await _frame();
    final state = (await svc.getState())!;
    final look = _deviceLook(state);
    final rev = _revOf(state);
    // ignore: avoid_print
    print('T37 device look: $look rev=$rev\n  LEDs 0-8: ${frame.sublist(0, 9)}\n'
        '  LEDs 128-136: ${frame.sublist(128, 137)}');

    for (final s in look) {
      expect(s['fx'], 83, reason: 'seg ${s['id']}');
      expect(s['pal'], 0, reason: 'seg ${s['id']}: pal 5 would be half/half');
      expect(s['sx'], 0);
      expect(s['ix'], 0);
    }
    var wrong = 0;
    for (final ch in _channels) {
      for (var i = ch.start; i < ch.stop; i++) {
        final v = _virtual(ch, i, rev[ch.id] ?? false);
        if (_nearest(frame[i], [_red, _blue]) != v % 2) wrong++;
      }
    }
    expect(wrong, 0, reason: 'LEDs not in the r,b,r,b… cycle');
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 2)));

  test('T38 — a legacy stored channel (no solid_layout key) fires as Blocks, '
      'exactly as it did before the field existed', () async {
    final d = _design('zz probe Legacy', [_red, _white, _blue], SolidLayout.alternating);
    final data = d.toFirestore();
    // Strip the new key, as a document saved by an older build has none.
    data['channels'] = <Map<String, dynamic>>[
      for (final ch in (data['channels'] as List).cast<Map>())
        <String, dynamic>{
          for (final e in ch.entries)
            if (e.key != 'solid_layout') '${e.key}': e.value,
        },
    ];
    final legacy = CustomDesign.fromFirestoreData(d.id, data);
    expect(legacy.channels.map((c) => c.solidLayout).toSet(), {SolidLayout.blocks});

    await applyAsMyDesigns(legacy);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final look = _deviceLook((await svc.getState())!);
    // ignore: avoid_print
    print('T38 device look: $look');
    for (final s in look) {
      expect([s['fx'], s['pal']], [83, 5], reason: 'seg ${s['id']}');
    }
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 2)));
}
