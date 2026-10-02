// Lumina AI on a three-channel controller (#163).
//
// Owner report, 2026-10-02: a Lumina team look ("Royals Theater Chase") said
// it applied, the preview and Now Playing showed it, but only segment 0 of a
// 162 / 128 / 100 px controller changed; segments 1 and 2 kept the earlier
// Chiefs look. This file runs the REAL payload builders (team tier, the cloud
// reply parser, the local command parser) through the REAL apply path
// (WledNotifier, then the same normalize / participation / geometry steps
// WledService.applyJson and CloudRelayRepository.applyJson take) into a fake
// controller that merges a `seg` array the way WLED does: an entry with an
// `id` updates that segment, an entry without one updates the segment at its
// array index, and a bare `seg` object updates the selected segment (0).
//
// The rule it pins: a Lumina design reaches EVERY participating channel as
// one fully stated segment, whatever shape the builder produced, and the
// channels the reply names are the channels that were sent.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/local_command_parser.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/wled/geometry_wire_pin.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/shared/write_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Chiefs look every segment holds before each test (fx 37 = the earlier
/// look in the owner's report).
Map<String, dynamic> _chiefs(int id) => {
      'id': id,
      'on': true,
      'fx': 37,
      'sx': 128,
      'ix': 128,
      'pal': 0,
      'col': [
        [227, 24, 55, 0],
        [255, 184, 28, 0],
        [0, 0, 0, 0],
      ],
    };

/// A three-bus controller. [applyJson] takes the payload the app hands the
/// repository, runs the wire steps the real repositories run, and merges the
/// result into [segs] with WLED's rules.
class _ThreeBusController implements WledRepository {
  _ThreeBusController({this.participatingCache});

  /// What `getCachedParticipatingChannels` returns on this phone: null when
  /// nothing (Game Day, Sync) ever wrote it — the common case.
  final List<int>? participatingCache;

  final List<Map<String, dynamic>> segs = [for (var i = 0; i < 3; i++) _chiefs(i)];
  bool masterOn = true;
  int masterBri = 200;
  final List<Map<String, dynamic>> wire = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    final out = stripGeometry(expandForParticipation(
        normalizeWledPayload(payload), participatingCache));
    wire.add(jsonDecode(jsonEncode(out)) as Map<String, dynamic>);
    if (out['on'] is bool) masterOn = out['on'] as bool;
    if (out['bri'] is int) masterBri = out['bri'] as int;
    final seg = out['seg'];
    if (seg is Map) {
      _merge((seg['id'] as int?) ?? 0, seg);
    } else if (seg is List) {
      for (var i = 0; i < seg.length; i++) {
        final e = seg[i];
        if (e is Map) _merge((e['id'] as int?) ?? i, e);
      }
    }
    return true;
  }

  void _merge(int id, Map e) {
    if (id < 0 || id >= segs.length) return; // WLED ignores it
    e.forEach((k, v) {
      if (k != 'id') segs[id]['$k'] = jsonDecode(jsonEncode(v));
    });
  }

  /// The channels whose look is no longer the Chiefs look.
  List<int> get changed => [
        for (final s in segs)
          if (s['fx'] != 37 ||
              jsonEncode(s['col']) != jsonEncode(_chiefs(0)['col']))
            s['id'] as int,
      ];

  /// The channels that are lit (segment on and master on).
  List<int> get lit => [
        for (final s in segs)
          if (masterOn && s['on'] == true) s['id'] as int,
      ];

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;
  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  Future<Map<String, dynamic>?> getState() async => null;
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      false;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<bool> supportsRgbw() async => true;
  @override
  Future<List<WledSegment>> fetchSegments() async => const [];
  @override
  Future<bool> renameSegment({required int id, required String name}) async =>
      false;
  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async =>
      false;
  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => 390;
  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      false;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}

const _threeChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 162, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 162, stop: 290, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 290, stop: 390, gpioPin: 16),
];

ProviderContainer _container(
  _ThreeBusController ctl, {
  List<int>? participating,
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => ctl),
    wledConnectivityStatusProvider.overrideWith(
      (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
    ),
    deviceChannelsProvider.overrideWithValue(_threeChannels),
    participatingChannelIdsProvider.overrideWithValue(participating),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// The device part of a Lumina payload as the chat hands it to the apply
/// funnel today (metadata keys and all).
Map<String, dynamic> _cloudPayload(String seg) {
  final reply = 'Here you go! {"patternName":"Royals Theater Chase",'
      '"wled":{"on":true,"bri":200,"seg":$seg}}';
  final r = CloudAIProcessor.parseAiResponseForTest(reply, 'royals design');
  expect(r.wledPayload, isNotNull, reason: 'the parser must yield a payload');
  return r.wledPayload!;
}

const _royalsSeg = '{"fx":12,"sx":160,"ix":128,'
    '"col":[[0,70,135,0],[189,155,96,0],[0,0,0,0]]}';

/// The apply the chat funnel makes for a reply
/// (RiverpodLuminaConversationServices.applyToDevice → applyLuminaDesign).
Future<WriteResult> _luminaApply(
    ProviderContainer c, Map<String, dynamic> p) async {
  final r = await c.read(wledStateProvider.notifier).applyLuminaDesign(p);
  expect(r.ok, isTrue, reason: 'the write must be sent');
  return r;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // Each case: the request, the payload the real builder makes, and the
  // channels a correct apply must change.
  final designCases = <String, Map<String, dynamic> Function()>{
    'team tier: "royals theater chase"': () =>
        LuminaBrain.teamPayloadFor('royals theater chase')!,
    'team tier: "royals colors" (colours only)': () =>
        LuminaBrain.teamPayloadFor('royals colors')!,
    'cloud reply: one segment, no id': () => _cloudPayload('[$_royalsSeg]'),
    'cloud reply: one segment, id 0': () =>
        _cloudPayload('[${_royalsSeg.replaceFirst('{', '{"id":0,')}]'),
    'cloud reply: a bare segment object': () => _cloudPayload(_royalsSeg),
    'local parser: "make it blue"': () => LocalCommandParser.toWledPayload(
        LocalCommandParser.parse('make it blue'))!,
  };

  for (final participating in <List<int>?>[null, const [0, 1, 2]]) {
    final cache = participating == null ? 'cold cache' : 'warm cache [0,1,2]';
    group('every Lumina design reaches all three channels ($cache)', () {
      designCases.forEach((label, build) {
        test(label, () async {
          final ctl = _ThreeBusController(participatingCache: participating);
          final c = _container(ctl, participating: participating);
          final payload = build();
          final r = await _luminaApply(c, payload);
          final lastWire = ctl.wire.last;
          printOnFailure('payload: ${jsonEncode(payload['seg'])}\n'
              'wire:    ${jsonEncode(lastWire['seg'])}\n'
              'changed: ${ctl.changed}  lit: ${ctl.lit}');
          expect(ctl.changed, [0, 1, 2],
              reason: 'a design must change every participating channel');
          expect(ctl.lit, [0, 1, 2]);
          final seg = lastWire['seg'] as List;
          expect(seg.map((s) => (s as Map)['id']), [0, 1, 2],
              reason: 'one fully stated segment per channel');
          final looks = {
            for (final s in seg.cast<Map>()) jsonEncode({...s}..remove('id')),
          };
          expect(looks, hasLength(1), reason: 'the same look on every channel');
          for (final s in seg.cast<Map>()) {
            expect(s['fx'], isNotNull);
            expect(s['col'], isNotNull);
            expect(s['on'], isTrue);
          }
          expect(lastWire.containsKey('patternName'), isFalse,
              reason: 'display metadata never rides to the controller');
          expect(r.channels, [0, 1, 2]);
          expect(r.message, 'All 3 channels');
        });
      });
    });
  }

  test('power and brightness carry no seg and act on the whole controller',
      () async {
    final ctl = _ThreeBusController();
    final c = _container(ctl);
    await _luminaApply(c, LocalCommandParser.toWledPayload(
        LocalCommandParser.parse('set brightness to 50%'))!);
    expect(ctl.wire.last.containsKey('seg'), isFalse);
    expect(ctl.masterBri, 128, reason: "50% is bri 128 on the whole controller");
    expect(ctl.changed, isEmpty, reason: 'brightness is not a design');
  });

  test('REGRESSION: the reply never claims more channels than were lit',
      () async {
    // Every design case, with every channel participating and with one left
    // out of shows: the channels the result names must all have changed, and
    // nothing outside them may change.
    for (final participating in <List<int>?>[null, const [0, 2]]) {
      for (final entry in designCases.entries) {
        final ctl = _ThreeBusController(participatingCache: participating);
        final c = _container(ctl, participating: participating);
        final r = await _luminaApply(c, entry.value());
        final claimed = r.channels ?? const <int>[];
        printOnFailure('${entry.key} / participating $participating: '
            'claimed $claimed (${r.message}), changed ${ctl.changed}');
        expect(claimed, isNotEmpty, reason: entry.key);
        expect(ctl.changed, containsAll(claimed),
            reason: '${entry.key}: every channel the reply names changed');
        expect(ctl.changed, claimed,
            reason: '${entry.key}: nothing outside them changed');
      }
    }
  });

  test('a channel left out of shows is not written, and the reply names the '
      'channels that were', () async {
    final ctl = _ThreeBusController(participatingCache: const [0, 2]);
    final c = _container(ctl, participating: const [0, 2]);
    final r =
        await _luminaApply(c, LuminaBrain.teamPayloadFor('royals colors')!);
    expect(ctl.changed, [0, 2]);
    expect((ctl.wire.last['seg'] as List).map((s) => (s as Map)['id']), [0, 2],
        reason: 'nothing at all is said about channel 2');
    expect(r.message, 'Channel 1 and Channel 3');
  });

  test('a scene that states each channel passes through unchanged', () async {
    final ctl = _ThreeBusController();
    final c = _container(ctl);
    await _luminaApply(c, {
      'on': true,
      'seg': [
        {'id': 0, 'fx': 0, 'col': [[255, 0, 0, 0]]},
        {'id': 1, 'fx': 0, 'col': [[0, 255, 0, 0]]},
        {'id': 2, 'fx': 0, 'col': [[0, 0, 255, 0]]},
      ],
    });
    expect(ctl.segs.map((s) => (s['col'] as List).first), [
      [255, 0, 0, 0],
      [0, 255, 0, 0],
      [0, 0, 255, 0],
    ], reason: 'per-channel colours are not flattened to one look');
  });

  test('power reports no channels (it acts on the whole controller)',
      () async {
    final ctl = _ThreeBusController();
    final c = _container(ctl);
    final r = await _luminaApply(c, LocalCommandParser.toWledPayload(
        LocalCommandParser.parse('turn off'))!);
    expect(ctl.masterOn, isFalse);
    expect(r.channels, isNull);
  });

  test('a Home channel selection does not narrow a Lumina design', () async {
    final ctl = _ThreeBusController();
    final c = _container(ctl);
    c.read(selectedChannelIdsProvider.notifier).state = {1};
    await _luminaApply(c, LocalCommandParser.toWledPayload(
        LocalCommandParser.parse('make it blue'))!);
    printOnFailure('wire: ${jsonEncode(ctl.wire.last['seg'])}  '
        'lit: ${ctl.lit}  changed: ${ctl.changed}');
    expect(ctl.lit, [0, 1, 2],
        reason: 'the reply says the design is for the house; nothing the '
            'chat shows narrows it to the channel picked on Home');
  });
}
