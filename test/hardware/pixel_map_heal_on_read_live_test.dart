// LIVE HARDWARE TEST — bench controller at kBenchIp (2 channels: 0–128, 128–290).
// Gated: every test skips unless run with
//
//   flutter test test/hardware/pixel_map_heal_on_read_live_test.dart --dart-define=RUN_HW=true
//
// (the literal `true` — bool.fromEnvironment does not accept `1`). Performs real
// network I/O and changes what the lights show for a few seconds; never writes
// presets or /json/cfg; puts the prior look back.
//
// WHAT IT PROVES. Heal-on-read changes which physical LEDs the editor's map
// tools address on a pre-+101 pixelMap. Each case drives the SAME consumer
// ("All runs" → paint → the real apply spine → the real WledService) twice —
// once on the segments exactly as STORED, once on the model the app now builds
// from them — and reads the rendered frame buffer back.
//
// SYNTHETIC FIXTURES ONLY. No production document is loaded. The two fixtures
// reproduce real affected SHAPES from the 2026-09-19 dry-run (release-101
// report §4) as plain numbers:
//   shape D — ch0 28+13 px (healthy); ch1 41 px stored at start_pixel 41  (REBASE)
//   shape G — ch0 168 px stored at start_pixel 128 on a 128-LED strip     (REBASE+OVERFLOW)
//             ch1 128 px (partial)
// Shape D's strips are 41 LEDs in production; the bench's are 128 / 162, so on
// the bench the unhealed indices 41–81 EXIST and light the wrong LEDs, where on
// the real 41-LED strip they fall off the end and light nothing.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kBenchIp = '192.168.1.150';
const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];
const _lengths = {0: 128, 1: 162};
const _base = [10, 10, 12, 0];

Map<String, dynamic> _seg(int ch, int i, int start, int count) => {
      'id': 'ch${ch}_seg$i', 'name': 'Run ${i + 1}', 'pixel_count': count,
      'start_pixel': start, 'type': 'run', 'anchor_pixels': <int>[],
      'anchor_led_count': 2, 'sort_order': i, 'channel_index': ch,
    };
Map<String, dynamic> _doc(int ch, int source, List<Map<String, dynamic>> segs) =>
    {'channel_index': ch, 'segments': segs, 'source_pixel_count': source};

List<PixelMapChannel> _load(List<Map<String, dynamic>> docs) => [
      for (final d in docs)
        PixelMapChannel.fromJson('synthetic', '${d['channel_index']}',
            jsonDecode(jsonEncode(d)) as Map<String, dynamic>),
    ];

final _shapeD = [
  _doc(0, 41, [_seg(0, 0, 0, 28), _seg(0, 1, 28, 13)]),
  _doc(1, 41, [_seg(1, 0, 41, 41)]),
];
final _shapeG = [
  _doc(0, 128, [_seg(0, 0, 128, 168)]),
  _doc(1, 162, [_seg(1, 0, 0, 128)]),
];

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

Future<List<List<int>>> _frame() async {
  await Future<void>.delayed(const Duration(milliseconds: 1300)); // 700 ms crossfade
  final ws = await WebSocket.connect('ws://$kBenchIp/ws');
  List<List<int>>? last;
  final sub = ws.listen((msg) {
    if (msg is! List<int> || msg.isEmpty || msg[0] != 76) return;
    final off = msg[1] == 2 ? 4 : 2;
    last = [for (int i = off; i + 2 < msg.length; i += 3) [msg[i], msg[i + 1], msg[i + 2]]];
  });
  ws.add(jsonEncode({'lv': true}));
  await Future<void>.delayed(const Duration(milliseconds: 900));
  ws.add(jsonEncode({'lv': false}));
  await sub.cancel();
  await ws.close();
  return last!;
}

List<int> _lit(List<List<int>> f) => [
      for (int i = 0; i < f.length; i++)
        if ([f[i][0], f[i][1], f[i][2]].reduce((a, b) => a > b ? a : b) > 40) i,
    ];

String _ranges(List<int> a) {
  if (a.isEmpty) return '(none)';
  final out = <String>[];
  int s = a.first, p = a.first;
  for (final x in a.skip(1)) {
    if (x == p + 1) { p = x; continue; }
    out.add(s == p ? '$s' : '$s-$p');
    s = p = x;
  }
  out.add(s == p ? '$s' : '$s-$p');
  return '${a.length} lit: ${out.join(' ')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WledService svc;
  Map<String, dynamic>? prior;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!kRunHw) return;
    svc = WledService('http://$kBenchIp');
    prior = await svc.getState();
    // ignore: avoid_print
    print('HW prior: on=${prior?['on']} bri=${prior?['bri']} ps=${prior?['ps']}');
  });

  tearDownAll(() async {
    if (!kRunHw) return;
    await restoreAfterFindLed(svc, prior); // the captured look, segment by segment
    final ps = prior?['ps'];
    if (ps is int && ps > 0) await svc.applyJson({'ps': ps});
  });

  /// "All runs" on [channel] → Paint red → Apply, through the real spine.
  Future<List<int>> allRunsOnBench(List<RooflineSegment> channelSegments, int channel) async {
    final picked = featureIndices(channelSegments, FeatureFilter.allRuns);
    final doc = PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths)
        .paint(channel, picked, const [255, 0, 0, 0]);
    final groups = doc.toLedColorGroups(onlyPainted: true);
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => svc),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ]);
    addTearDown(container.dispose);
    final result = await applyBaseAndSpansWith(container.read,
        baseRgbw: _base,
        spansByChannel: {for (final e in groups.entries) e.key: ledColorGroupsToSpans(e.value)});
    expect(result, SpineWriteResult.ok);
    return _lit(await _frame());
  }

  test('T23 shape D (REBASE): "All runs" on channel 2 — as stored vs as the app now loads it', () async {
    final raw = _load(_shapeD);
    final stored = raw.firstWhere((c) => c.channelIndex == 1).segments;
    final healed = aggregatePixelMapChannelsToConfig('synthetic', raw).segmentsForChannel(1);

    final before = await allRunsOnBench(stored, 1);
    final after = await allRunsOnBench(healed, 1);
    // ignore: avoid_print
    print('T23 AS STORED : ${_ranges(before)}');
    // ignore: avoid_print
    print('T23 HEALED    : ${_ranges(after)}');

    expect(before, [for (int i = 169; i <= 209; i++) i],
        reason: 'stored start 41 → channel-local 41–81 → the WRONG 41 LEDs');
    expect(after, [for (int i = 128; i <= 168; i++) i],
        reason: 'channel-local 0–40 → the first 41 LEDs of channel 2');
    expect(raw[1].segments.single.startPixel, 41, reason: 'the loaded doc itself is unchanged');
  }, skip: !kRunHw);

  test('T24 shape G (REBASE+OVERFLOW): "All runs" on channel 1 — nothing vs the whole channel', () async {
    final raw = _load(_shapeG);
    final stored = raw.firstWhere((c) => c.channelIndex == 0).segments;
    final healed = aggregatePixelMapChannelsToConfig('synthetic', raw).segmentsForChannel(0);

    final before = await allRunsOnBench(stored, 0);
    final after = await allRunsOnBench(healed, 0);
    // ignore: avoid_print
    print('T24 AS STORED : ${_ranges(before)}');
    // ignore: avoid_print
    print('T24 HEALED    : ${_ranges(after)}');

    expect(before, isEmpty,
        reason: 'stored start 128 on a 128-LED strip → every index is off the end → dark');
    expect(after, [for (int i = 0; i < 128; i++) i],
        reason: 'the whole of channel 1, and NOT one LED of channel 2 — the 40-px overshoot is bounded');
    expect(healed.single.pixelCount, 168, reason: 'the overshoot stays in the data; it is not guessed away');
  }, skip: !kRunHw);
}
