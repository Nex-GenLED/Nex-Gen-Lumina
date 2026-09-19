// LIVE HARDWARE TEST — requires the bench controller at kBenchIp (2 channels:
// 0–128 and 128–290). NOT part of the normal suite: it performs real network
// I/O and changes what the lights show (never presets, never /json/cfg), then
// puts the look back. Run explicitly:
//
//   flutter test test/hardware/design_studio_101_live_test.dart --dart-define=RUN_HW=true
//
// Without the define every test skips. (It must be the literal `true`:
// bool.fromEnvironment does not accept `1`.)
//
// It drives the REAL shipping code — the pixel-map writer, the apply spine,
// Find-LED, CustomDesign.toWledPayload, the tuner payload builder, the pattern
// tool — through the REAL WledService, and reads the controller's rendered
// frame buffer back over the live-view WebSocket (all 290 LEDs). This is the
// hardware half of the 2.5.10+101 Design Studio fix pass; the numbering
// continues the two audits' test logs (T1–T14).
//
// Live-view values are post-gamma RGB with W folded in, so colours are
// compared by WHICH LEDs are lit and their dominant channel, not byte-for-byte.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
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
final _now = DateTime(2026, 9, 19);

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

ProviderContainer _container(WledRepository repo) => ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ]);

/// One live-view frame per ~40 ms for [duration]. Each frame = 290 × [r,g,b].
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

Future<List<List<int>>> _frame() async {
  await Future<void>.delayed(const Duration(milliseconds: 1300)); // 700 ms crossfade
  return (await _frames(const Duration(milliseconds: 900))).last;
}

int _bright(List<int> l) => [l[0], l[1], l[2]].reduce((a, b) => a > b ? a : b);
List<int> _lit(List<List<int>> f, [int thr = 40]) =>
    [for (int i = 0; i < f.length; i++) if (_bright(f[i]) > thr) i];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WledService svc;
  Map<String, dynamic>? prior;

  setUpAll(() async {
    HttpOverrides.global = null; // flutter_test stubs HTTP with a 400
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (!kRunHw) return;
    svc = WledService('http://$kBenchIp');
    prior = await svc.getState();
    // ignore: avoid_print
    print('HW prior: on=${prior?['on']} bri=${prior?['bri']} ps=${prior?['ps']}');
  });

  tearDownAll(() async {
    if (!kRunHw) return;
    // Put the look back: the captured segments, then the preset it came from
    // (which also restores the `ps` pointer). Presets/cfg were never written.
    await restoreAfterFindLed(svc, prior);
    final ps = prior?['ps'];
    if (ps is int && ps > 0) await svc.applyJson({'ps': ps});
  });

  test('T15 (fix 1) anchors set through the REAL writer land on the right LEDs', () async {
    final cfg = RooflineConfiguration(
      id: 'c', name: 'bench', createdAt: _now, updatedAt: _now, totalChannelCount: 2,
      segments: const [
        RooflineSegment(id: 'a', name: 'Front run', pixelCount: 128, channelIndex: 0),
        RooflineSegment(id: 'b', name: 'Garage run', pixelCount: 162, channelIndex: 1),
      ],
    );
    // Exactly what the anchor editor does, on BOTH channels.
    var edited = cfg.updateSegment('a', cfg.segmentById('a')!.copyWith(anchorPixels: [0, 126]));
    edited = edited.updateSegment('b', edited.segmentById('b')!.copyWith(anchorPixels: [0, 160]));
    expect(edited.segmentById('b')!.startPixel, 0);

    var doc = PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths);
    for (final ch in [0, 1]) {
      doc = doc.paint(ch, anchorIndices(edited.segmentsForChannel(ch)), const [255, 0, 0, 0]);
    }
    final groups = doc.toLedColorGroups(onlyPainted: true);
    final result = await applyBaseAndSpansWith(_container(svc).read,
        baseRgbw: _base,
        spansByChannel: {for (final e in groups.entries) e.key: ledColorGroupsToSpans(e.value)});
    expect(result, SpineWriteResult.ok);

    final lit = _lit(await _frame());
    // ignore: avoid_print
    print('T15 lit global LEDs: $lit');
    expect(lit, [0, 1, 126, 127, 128, 129, 288, 289],
        reason: 'ch2 anchors used to land at 256-257 (offset by channel 1 length)');
  }, skip: !kRunHw);

  test('T16 (fix 2) Find LED lights exactly the requested LED, then restores', () async {
    // Start from a known EFFECT look (solid amber, not frozen) so "restored"
    // means something: T15 leaves the segments per-pixel-frozen, and a frozen
    // picture cannot be restored from /json/state (the pixel buffer is not in
    // it) — Find-LED restores the LOOK, see find_led.dart.
    expect(await svc.applyJson(applyChannelFilter({
      'on': true, 'bri': 128,
      'seg': [{'fx': 0, 'col': [[255, 160, 0, 0]], 'pal': 0}],
    }, [0, 1], _channels)), isTrue);
    final amber = _lit(await _frame()).length;
    // ignore: avoid_print
    print('T16 amber start look: $amber/290 lit');
    expect(amber, 290);
    final before = await svc.getState();
    final r = await lightSingleLed(repo: svc, channels: _channels, globalIndex: 130);
    expect(r.outcome, FindLedOutcome.lit);
    final f = await _frame();
    final lit = _lit(f, 8);
    // ignore: avoid_print
    print('T16 lit: $lit colour=${f[130]} msg="${r.message}"');
    expect(lit, [130]);
    expect(f[130][0], greaterThan(200));
    expect(f[130][1] + f[130][2], lessThan(40), reason: 'red');

    // A different LED replaces it (no leftovers from the first).
    await lightSingleLed(repo: svc, channels: _channels, globalIndex: 5);
    expect(_lit(await _frame(), 8), [5]);

    expect(await restoreAfterFindLed(svc, before), isTrue);
    final after = await svc.getState();
    for (int i = 0; i < 2; i++) {
      final a = (before!['seg'] as List)[i] as Map, b = (after!['seg'] as List)[i] as Map;
      for (final k in ['on', 'fx', 'sx', 'ix', 'pal', 'grp', 'spc', 'col', 'frz']) {
        expect(b[k], a[k], reason: 'seg$i.$k after restore');
      }
    }
    expect(after!['on'], before!['on']);
    expect(after['bri'], before['bri']);
    // …and the roof itself is showing the amber look again, all 290 LEDs.
    final restored = await _frame();
    // ignore: avoid_print
    print('T16 after restore: ${_lit(restored).length}/290 lit, LED 0 = ${restored[0]}');
    expect(_lit(restored).length, 290);
  }, skip: !kRunHw);

  test('T17 (fix 3) the spine and Find-LED report FAILURE when the device refuses', () async {
    // Nothing listens on :81 → the connection is refused immediately.
    final dead = WledService('http://$kBenchIp:81');
    final result = await applyBaseAndSpansWith(_container(dead).read,
        baseRgbw: _base,
        spansByChannel: const {0: [PixelSpan(start: 1, end: 1, color: [255, 0, 0, 0])]});
    // ignore: avoid_print
    print('T17 dead-device spine result: $result');
    expect(result, SpineWriteResult.baseFailed, reason: 'used to `return true`');
    expect(result.userMessage, isNotNull);

    final find = await lightSingleLed(repo: dead, channels: _channels, globalIndex: 3);
    expect(find.outcome, FindLedOutcome.writeFailed);
    expect(find.message, contains('NOT lit'));

    // …and the same call against the live bench is truthful the other way.
    final ok = await applyBaseAndSpansWith(_container(svc).read,
        baseRgbw: const [0, 0, 0, 0],
        spansByChannel: const {0: [PixelSpan(start: 1, end: 1, color: [255, 0, 0, 0])]});
    expect(ok, SpineWriteResult.ok);
    expect(_lit(await _frame(), 8), [1]);
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 3)));

  group('fix 4 — a saved per-pixel design', () {
    // Built the way the paint editor's _save() builds it (full coverage).
    final doc = PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths)
        .paint(0, [10], const [255, 0, 0, 0])
        .paint(0, [20], const [0, 255, 0, 0])
        .paint(0, everyNthInRange(start: 40, end: 100, step: 4), const [0, 60, 255, 0])
        .paint(1, [0, 1, 2, 3], const [255, 40, 150, 0]);
    final design = CustomDesign(
      id: 'd', name: 'Bench design', ownerId: 'u', createdAt: _now, updatedAt: _now,
      perPixel: true,
      channels: [
        for (final e in doc.toLedColorGroups().entries)
          ChannelDesign(channelId: e.key, channelName: 'Channel ${e.key + 1}',
              colorGroups: e.value, ledCount: doc.channelLength(e.key)),
      ],
    );
    final expected = [10, 20, ...everyNthInRange(start: 40, end: 100, step: 4), 128, 129, 130, 131];

    test('T18 My Designs / scene path (the spine) renders it exactly', () async {
      final round = CustomDesign.fromFirestoreData('d', design.toFirestore());
      expect(round.isPositional, isTrue);
      final res = await applyPositionalDesignWith(_container(svc).read, round);
      expect(res, DesignApplyResult.applied);
      final f = await _frame();
      // ignore: avoid_print
      print('T18 lit: ${_lit(f)}');
      expect(_lit(f), expected, reason: 'was 257 black + one 33-LED red block at 257-289');
      expect(f[10][0], greaterThan(200)); // red
      expect(f[20][1], greaterThan(200)); // green
      expect(f[44][2], greaterThan(200)); // blue
      expect(f[128][0], greaterThan(200)); // pink
    }, skip: !kRunHw);

    test('T19 toWledPayload() — ONE payload over a bright look — leaves nothing behind', () async {
      // A bright, busy look first, so any LED the payload failed to cover shows.
      expect(await svc.applyJson(applyChannelFilter({
        'on': true, 'bri': 128,
        'seg': [{'fx': 0, 'col': [[255, 160, 0, 0]], 'pal': 0}],
      }, [0, 1], _channels)), isTrue);
      expect(_lit(await _frame()).length, 290);

      final payload = design.toWledPayload();
      // ignore: avoid_print
      print('T19 payload bytes: ${utf8.encode(jsonEncode(normalizeWledPayload(payload))).length}');
      expect(await svc.applyJson(payload), isTrue);
      final f = await _frame();
      expect(_lit(f), expected,
          reason: 'every LED the design does not light must be dark — full-coverage `i`');
    }, skip: !kRunHw);
  });

  test('T20 (fix 7) Architectural Twinkle ANIMATES — 12 s of frames', () async {
    final repo = PatternRepository();
    final node = await repo.getNodeById('arch_k3000_1on2off');
    final cols = node!.themeColors!.take(3)
        .map((c) => rgbToRgbw((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(),
            forceZeroWhite: true))
        .toList();
    // What the tuner sends when "Twinkle" is tapped for this card.
    final payload = applyChannelFilter(
      buildSelectorPayload(SelectorState(
        effectId: 17,
        speed: getSpeedProfile(17).rawDefault,
        intensity: 128,
        grouping: node.metadata!['grouping'] as int,
        spacing: node.metadata!['spacing'] as int,
        colors: cols,
      )),
      [0, 1], _channels);
    // ignore: avoid_print
    print('T20 wire: ${jsonEncode(normalizeWledPayload(payload))}');
    expect(await svc.applyJson(payload), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final frames = await _frames(const Duration(seconds: 12));
    final brightCounts = [for (final f in frames) _lit(f, 120).length];
    final changed = <int>{};
    int changedFrames = 0;
    for (int i = 1; i < frames.length; i++) {
      bool any = false;
      for (int j = 0; j < frames[i].length; j++) {
        if ((_bright(frames[i][j]) - _bright(frames[i - 1][j])).abs() > 30) {
          changed.add(j);
          any = true;
        }
      }
      if (any) changedFrames++;
    }
    final state = await svc.getState();
    final fx = [for (final s in state!['seg'] as List) (s as Map)['fx']];
    // ignore: avoid_print
    print('T20 frames=${frames.length} device fx=$fx '
        'bright-LEDs per frame min=${brightCounts.reduce((a, b) => a < b ? a : b)} '
        'max=${brightCounts.reduce((a, b) => a > b ? a : b)} '
        'frames that changed=$changedFrames distinct LEDs that changed=${changed.length}');

    expect(fx, [17, 17], reason: 'genuine Twinkle — nothing substituted');
    expect(brightCounts.toSet().length, greaterThan(5),
        reason: 'the number of bright LEDs VARIES (was a constant 97/97)');
    expect(changed.length, greaterThan(25), reason: 'was 10 LEDs in 10 s');
    expect(changedFrames, greaterThan(20), reason: 'was 5 of 132 frames');
  }, skip: !kRunHw, timeout: const Timeout(Duration(minutes: 2)));

  test('T21 (fix 8) pattern tool: "4 off" then "6 off" → exactly every 7th', () async {
    var doc = PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths);
    // The two "Paint pattern" presses, exactly as _everyNthDialog commits them.
    for (final off in [4, 6]) {
      final p = onOffPatternInRange(start: 0, end: 127, on: 1, off: off);
      doc = doc.clearToBase(0, p.dark).paint(0, p.lit, const [255, 255, 255, 0]);
    }
    final groups = doc.toLedColorGroups(onlyPainted: true);
    final res = await applyBaseAndSpansWith(_container(svc).read,
        baseRgbw: _base,
        spansByChannel: {for (final e in groups.entries) e.key: ledColorGroupsToSpans(e.value)});
    expect(res, SpineWriteResult.ok);
    final lit = _lit(await _frame());
    // ignore: avoid_print
    print('T21 lit (${lit.length}): $lit');
    expect(lit, everyNthInRange(start: 0, end: 127, step: 7),
        reason: 'was the union of every-5th and every-7th: 41 LEDs');
  }, skip: !kRunHw);

  test('T22 (fix 9) a saved "1 On 4 Off" design re-applies WITH its spacing', () async {
    final design = CustomDesign(
      id: 's', name: '1 On 4 Off', ownerId: 'u', createdAt: _now, updatedAt: _now,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Ch1', grouping: 1, spacing: 4,
            colorGroups: [LedColorGroup(startLed: 0, endLed: 0, color: [255, 177, 110, 0])]),
        ChannelDesign(channelId: 1, channelName: 'Ch2', grouping: 1, spacing: 4,
            colorGroups: [LedColorGroup(startLed: 0, endLed: 0, color: [255, 177, 110, 0])]),
      ],
    );
    final back = CustomDesign.fromFirestoreData('s', design.toFirestore());
    expect(await svc.applyJson(back.toWledPayload()), isTrue);
    final lit = _lit(await _frame(), 8);
    // ignore: avoid_print
    print('T22 lit: ch1=${lit.where((i) => i < 128).length} ch2=${lit.where((i) => i >= 128).length}');
    expect(lit.where((i) => i < 128).toList(), everyNthInRange(start: 0, end: 127, step: 5));
    expect(lit.where((i) => i >= 128).length, 33, reason: 'was 162 — every LED lit');
  }, skip: !kRunHw);
}
