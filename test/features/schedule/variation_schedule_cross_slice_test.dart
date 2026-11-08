// +123 candidate — the cross-slice proof that neither roofline slice could
// run on its own branch.
//
// A roofline SLICE 3 colour variation — composed by the real studio
// orchestrator over the saved design's STAMPED bus lengths
// (configForAiPipeline in a variation session), and saved by the real studio
// save (saveComposedDesignProvider), so it carries the base design's layout
// stamp — is handed to roofline SLICE 2's schedule path:
//
//   * the pick-time verdict over the live providers
//     (designSchedulePickVerdict → designScheduleEligibility: slice 1's fit
//     gate, the bus-starts check, firmware and model, the bounds-first body
//     builder, the element cap and the byte cap), and
//   * the same pure checks the sync makes before it writes the preset
//     (schedule_sync.dart: body shape, bounds against the controller's own
//     buses, both caps with the real slot and the real name).
//
// Slice 2 was built and tested without slice 3's composer or save; slice 3
// without slice 2's builder or caps. Nothing here changes either slice.
//
// Fixture: a saved design stamped for three buses of 100 on ctl-a, in red /
// blue / white (50 / 40 / 10 % of the lights, so the seeded accent is white).
// The live controller is the same three buses on ctl-a, WLED 0.15.4 on a
// classic ESP32 — the one proven pair.
//
// Element arithmetic, from wledJsonElementCount's rule (one per array element
// and per object member; the root itself none), for one paint entry over a
// 100-LED bus:
//   entry 1 + id/on/fx/grp/spc/pal 6 + col (1 + 3 × 5) 16 + i (1 + Σ spans),
//   a one-LED span = 6 (index + a four-value colour list), a run = 7.
// Body overhead: root members o/on/bri/psave/n 5, seg 1, a bounds entry 4,
// a left-out entry 5.
//   "1 on 3 off"  — 25 one-LED spans + 25 runs of 3 → i 326 → entry 349.
//       all three buses painted: 5 + 1 + 12 + 3 × 349      = 1,065
//       channel 2 left out:      5 + 1 + 12 + 2 × 349 + 5  =   721
//   "every other light" — 100 one-LED spans → i 601 → entry 624.
//       5 + 1 + 12 + 3 × 624 = 1,890 — over the 1,700 element cap, while
//       the wire bytes stay under the 6,000 byte cap: the element cap decides.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_color_summary.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/schedule/design_api_preset.dart';
import 'package:nexgen_command/features/schedule/gated_preset_save.dart';
import 'package:nexgen_command/features/wled/design_schedule_pick.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

final _now = DateTime(2026, 11, 7);

const kStamp =
    DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);

/// The live controller: three buses of 100, end to end, on ctl-a.
const kThree = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
];

/// The same controller after bus 2 was set to 120 LEDs.
const kMiddle120 = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 220, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 220, stop: 320, gpioPin: 12),
];

const kWhite = [255, 255, 255, 0];
const kDark = [0, 0, 0, 0];

/// The saved design the variation is made from (slice 1 stamp).
CustomDesign _saved() => CustomDesign(
      id: 'base',
      name: 'Porch stripes',
      ownerId: 'u1',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      layoutStamp: kStamp,
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(
              channelId: id,
              channelName: 'Channel ${id + 1}',
              ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 89, color: [0, 0, 255, 0]),
                LedColorGroup(startLed: 90, endLed: 99, color: kWhite),
              ]),
      ],
    );

/// A one-bus roofline map, as recorded before any bus lengths are attached.
RooflineConfiguration _map() => RooflineConfiguration(
      id: 'r',
      name: 'Roof',
      createdAt: _now,
      updatedAt: _now,
      controllerId: 'ctl-a',
      segments: const [
        RooflineSegment(
            id: 'a', name: 'Front run', pixelCount: 40, channelIndex: 0),
      ],
    );

/// The direct-LAN service with the proven firmware and model; counts reads.
class _Lan extends WledService {
  _Lan() : super('http://mock');
  int infoReads = 0;

  @override
  Future<WledInfoResponse?> getInfo() async {
    infoReads++;
    return WledInfoResponse(maxseg: 10, arch: 'esp32', ver: '0.15.4');
  }
}

// User is sealed; subclassing for a scoped test fake is intentional.
// ignore: subtype_of_sealed_class
class _StubUser implements User {
  _StubUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

class _LiveZoneSegments extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [
        WledSegment(id: 0, name: 'Channel 1', start: 0, stop: 100),
        WledSegment(id: 1, name: 'Channel 2', start: 100, stop: 200),
        WledSegment(id: 2, name: 'Channel 3', start: 200, stop: 300),
      ];
}

/// Slice 3: compose [prompt] the way the studio does in a variation session —
/// the config from configForAiPipeline (the base's stamped lengths), the
/// base's colour summary handed to the orchestrator (which seeds it only when
/// the prompt names no colour).
Future<ComposedPattern> _composeVariation(
    String prompt, VariationBase base) async {
  final c = ProviderContainer(overrides: [
    currentRooflineConfigProvider.overrideWith((ref) => Stream.value(_map())),
    deviceChannelsProvider.overrideWithValue(kThree),
    variationBaseProvider.overrideWith((ref) => base),
  ]);
  addTearDown(c.dispose);
  await c.read(currentRooflineConfigProvider.future);
  final cfg = configForAiPipeline(c.read)!;
  expect(cfg.channelPixelCounts, {0: 100, 1: 100, 2: 100},
      reason: 'a variation composes over the stamped bus lengths');
  final res = await DesignStudioOrchestrator().processUserInput(
      prompt: prompt, config: cfg, baseColors: c.read(variationBaseProvider)?.colors);
  expect(res.isReady, isTrue, reason: '"$prompt": ${res.status} ${res.errorMessage}');
  return res.pattern!;
}

/// Slice 3: the studio save, then the document read back as the schedule
/// picker's My Designs list reads it.
Future<CustomDesign> _saveAndReadBack(
    ComposedPattern pattern, VariationBase base) async {
  final firestore = FakeFirebaseFirestore();
  final c = ProviderContainer(overrides: [
    authStateProvider
        .overrideWith((ref) => Stream<User?>.value(_StubUser('u1'))),
    designServiceProvider
        .overrideWith((ref) => DesignService(firestore: firestore)),
    zoneSegmentsProvider.overrideWith(_LiveZoneSegments.new),
    composedPatternProvider.overrideWith((ref) => pattern),
    wledRepositoryProvider.overrideWith((ref) => null),
    deviceChannelsProvider.overrideWithValue(kThree),
    selectedControllerIdProvider.overrideWithValue('ctl-a'),
    isRemoteModeProvider.overrideWithValue(false),
    variationBaseProvider.overrideWith((ref) => base),
  ]);
  addTearDown(c.dispose);
  await c.read(authStateProvider.future);
  await c.read(zoneSegmentsProvider.future);
  final id = await c.read(saveComposedDesignProvider)();
  expect(id, isNotNull);
  final snap = await firestore
      .collection('users')
      .doc('u1')
      .collection('designs')
      .doc(id)
      .get();
  return CustomDesign.fromFirestoreData(snap.id, snap.data()!);
}

/// Slice 2: the schedule picker's verdict over the live providers.
Future<DesignScheduleEligibility> _pick(CustomDesign design,
    {required _Lan lan, List<DeviceChannel> live = kThree}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(lan),
    deviceChannelsProvider.overrideWithValue(live),
    selectedControllerIdProvider.overrideWithValue('ctl-a'),
    isRemoteModeProvider.overrideWithValue(false),
  ]);
  addTearDown(c.dispose);
  return designSchedulePickVerdict(c.read, design);
}

/// The name the picker stores on the schedule and the sync writes as `n`.
String _wireName(CustomDesign d) => 'Pattern: ${d.name}';

/// Every LED of a paint entry's `i` array, decoded (WLED's range stop is
/// exclusive). Fails if any LED of the bus is left unwritten.
List<List<int>> _decodeI(List<dynamic> i, int len) {
  final out = List<List<int>?>.filled(len, null);
  var k = 0;
  while (k < i.length) {
    final a = i[k] as int;
    if (i[k + 1] is int) {
      final b = i[k + 1] as int;
      final c = (i[k + 2] as List).cast<int>();
      for (var x = a; x < b; x++) {
        out[x] = c;
      }
      k += 3;
    } else {
      out[a] = (i[k + 1] as List).cast<int>();
      k += 2;
    }
  }
  expect(out.every((c) => c != null), isTrue, reason: 'every LED written');
  return [for (final c in out) c!];
}

/// The bounds-first shape, asserted entry by entry: the bounds group (every
/// stamped bus, in bus order, id/start/stop only), then one paint entry per
/// painted bus with no bounds, then each left-out bus bounded and dark.
void _expectBoundsFirst(Map<String, dynamic> body,
    {required List<int> painted, required List<int> leftOut}) {
  expect(body['o'], isTrue);
  expect(body['on'], isTrue);
  final seg = (body['seg'] as List).cast<Map<String, dynamic>>();
  expect(seg.length, 3 + painted.length + leftOut.length);
  expect(seg.take(3).toList(), [
    {'id': 0, 'start': 0, 'stop': 100},
    {'id': 1, 'start': 100, 'stop': 200},
    {'id': 2, 'start': 200, 'stop': 300},
  ]);
  final paints = seg.skip(3).take(painted.length).toList();
  expect(paints.map((s) => s['id']), painted);
  for (final p in paints) {
    expect(p.containsKey('start') || p.containsKey('stop'), isFalse,
        reason: 'paint entry ${p['id']} carries no bounds');
    expect(p['on'], isTrue);
    expect(p['fx'], 0);
    expect(p['i'], isA<List<dynamic>>());
  }
  expect(seg.skip(3 + painted.length).toList(), [
    for (final id in leftOut)
      {'id': id, 'start': id * 100, 'stop': id * 100 + 100, 'on': false},
  ]);
  expect(designApiPresetBodyProblem(body), isNull);
}

/// What the sync checks before it writes the preset to slot [slot], for a
/// body the picker handed back: the shape, the bounds against the
/// controller's own buses, and both caps with the real slot and name.
void _expectWriteTimeAdmits(Map<String, dynamic> body, CustomDesign d,
    {int slot = 10}) {
  expect(designApiPresetBodyProblem(body), isNull);
  expect(designApiPresetBoundsMatch(body, expectedShapeFromChannels(kThree)),
      isTrue);
  expect(
      designApiPresetCapRefusal(body,
          presetId: slot, presetName: _wireName(d), designName: d.name),
      isNull);
}

/// The paint for bus [bus] lights exactly the LEDs [lit] chooses, in white,
/// and leaves every other LED dark — per bus, from LED 0 of that bus.
void _expectPicture(Map<String, dynamic> body, int bus, bool Function(int) lit) {
  final entry = (body['seg'] as List)
      .cast<Map<String, dynamic>>()
      .skip(3)
      .firstWhere((s) => s['id'] == bus);
  final pixels = _decodeI(entry['i'] as List<dynamic>, 100);
  for (var x = 0; x < 100; x++) {
    expect(pixels[x], lit(x) ? kWhite : kDark, reason: 'bus $bus LED $x');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VariationBase base;
  setUp(() {
    base = variationBaseFor(_saved())!;
    expect(base.stamp, kStamp);
  });

  group('"1 on 3 off" — a variation the controller can store', () {
    late CustomDesign variation;
    setUp(() async {
      variation =
          await _saveAndReadBack(await _composeVariation('1 on 3 off', base), base);
    });

    test('the saved variation carries the BASE design\'s stamp', () {
      expect(variation.layoutStamp, kStamp);
      expect(variation.isPositional, isTrue);
      expect(variation.channels.map((c) => c.ledCount), [100, 100, 100]);
    });

    test('the pick admits it with a bounds-first body over the stamp, under '
        'both caps, and the sync\'s write-time checks admit the same body',
        () async {
      final lan = _Lan();
      final v = await _pick(variation, lan: lan);
      expect(v.verdict, DesignScheduleVerdict.allowed, reason: v.message);
      expect(lan.infoReads, 1);
      final body = v.body!;
      _expectBoundsFirst(body, painted: [0, 1, 2], leftOut: []);

      final elements = designApiPresetWireElements(body,
          presetId: kLastSchedulePresetId, presetName: _wireName(variation));
      final bytes = designApiPresetWireBytes(body,
          presetId: kLastSchedulePresetId, presetName: _wireName(variation));
      expect(elements, 1065);
      expect(elements, lessThanOrEqualTo(kDesignApiPresetMaxElements));
      expect(bytes, lessThanOrEqualTo(kDesignApiPresetMaxBytes));
      expect(v.bytes, bytes);

      _expectWriteTimeAdmits(body, variation);
    });

    test('the body carries the variation\'s picture: one in four lit from '
        'LED 0 of EVERY bus (the phase restarts per bus), the rest dark',
        () async {
      final v = await _pick(variation, lan: _Lan());
      for (final bus in [0, 1, 2]) {
        _expectPicture(v.body!, bus, (x) => x % 4 == 0);
      }
    });

    test('channel 2 switched off in the editor: still admitted, bus 1 bounded '
        'in the bounds group AND at the end as on:false, not painted',
        () async {
      // The editor's own switch on the saved variation (before its save,
      // which re-stamps from the live buses — here equal to the stamp).
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(currentDesignProvider.notifier).loadDesign(variation);
      c.read(currentDesignProvider.notifier).toggleChannelIncluded(1);
      final edited = c.read(currentDesignProvider)!;
      expect(edited.layoutStamp, kStamp, reason: 'the edit keeps the stamp');

      final v = await _pick(edited, lan: _Lan());
      expect(v.verdict, DesignScheduleVerdict.allowed, reason: v.message);
      final body = v.body!;
      _expectBoundsFirst(body, painted: [0, 2], leftOut: [1]);
      expect(
          designApiPresetWireElements(body,
              presetId: kLastSchedulePresetId, presetName: _wireName(edited)),
          721);
      _expectPicture(body, 0, (x) => x % 4 == 0);
      _expectPicture(body, 2, (x) => x % 4 == 0);
      _expectWriteTimeAdmits(body, edited);
    });

    test('on lights it was not composed for, the pick refuses it at the fit '
        'gate and hands back no body', () async {
      final v = await _pick(variation, lan: _Lan(), live: kMiddle120);
      expect(v.verdict, DesignScheduleVerdict.layoutMismatch);
      expect(v.body, isNull);
      expect(v.message, contains('120'));
    });
  });

  group('"every other light" — a variation too detailed to store', () {
    late CustomDesign variation;
    setUp(() async {
      variation = await _saveAndReadBack(
          await _composeVariation('every other light', base), base);
    });

    test('the pick refuses it as too detailed, by the ELEMENT cap — its bytes '
        'are under the byte cap — and offers the editor', () async {
      final v = await _pick(variation, lan: _Lan());
      expect(v.verdict, DesignScheduleVerdict.tooLarge);
      expect(v.body, isNull);
      expect(v.offersEditor, isTrue);
      expect(v.message, contains('1,890 details'));
      expect(v.message, contains('the limit is 1,700 details'));
      expect(v.bytes, lessThanOrEqualTo(kDesignApiPresetMaxBytes),
          reason: 'bytes alone would pass: the element cap decides');
    });

    test('the body it refused is still bounds-first — size refused it, not '
        'shape — and the write-time cap refuses it with the real slot too',
        () {
      final body = buildDesignApiPresetBody(variation)!;
      _expectBoundsFirst(body, painted: [0, 1, 2], leftOut: []);
      for (final bus in [0, 1, 2]) {
        _expectPicture(body, bus, (x) => x.isEven);
      }
      expect(
          designApiPresetWireElements(body,
              presetId: 10, presetName: _wireName(variation)),
          1890);
      expect(
          designApiPresetCapRefusal(body,
              presetId: 10,
              presetName: _wireName(variation),
              designName: variation.name),
          contains('too detailed'));
    });
  });
}
