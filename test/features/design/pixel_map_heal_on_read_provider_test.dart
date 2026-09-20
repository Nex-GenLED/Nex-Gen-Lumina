// HEAL-ON-READ, end to end through the REAL provider chain and the REAL
// RooflineConfigService, against a fake Firestore holding production-shaped
// documents — and the proof that READING NEVER WRITES.
//
// Shapes are from the 2026-09-19 read-only dry-run (release-101-report §4):
//   home D — ch0 healthy (28 + 13 on a 41-LED strip), ch1 REBASE ([41] → [0])
//   home G — ch0 REBASE+OVERFLOW (168 px stored at 128 on a 128-LED strip),
//            ch1 partial (128 of 162)
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

const _uid = 'user-fixture';
const _ctrl = 'ctrl-fixture';

Map<String, dynamic> _seg(int ch, int i, int start, int count) => {
      'id': 'ch${ch}_seg$i', 'name': 'Run ${i + 1}', 'pixel_count': count,
      'start_pixel': start, 'type': 'run', 'anchor_pixels': <int>[],
      'anchor_led_count': 2, 'sort_order': i, 'channel_index': ch,
    };
Map<String, dynamic> _doc(int ch, int source, List<Map<String, dynamic>> segs) => {
      'channel_index': ch, 'segments': segs, 'source_pixel_count': source,
      'map_version': 1, 'created_by': 'fixture', 'is_stale': false,
    };

final _homeD = [
  _doc(0, 41, [_seg(0, 0, 0, 28), _seg(0, 1, 28, 13)]),
  _doc(1, 41, [_seg(1, 0, 41, 41)]),
];
final _homeG = [
  _doc(0, 128, [_seg(0, 0, 128, 168)]),
  _doc(1, 162, [_seg(1, 0, 0, 128)]),
];

Future<FakeFirebaseFirestore> _seed(List<Map<String, dynamic>> docs) async {
  final db = FakeFirebaseFirestore();
  final col = db.collection('users').doc(_uid).collection('controllers').doc(_ctrl).collection('pixelMap');
  for (final d in docs) {
    await col.doc('${d['channel_index']}').set(jsonDecode(jsonEncode(d)) as Map<String, dynamic>);
  }
  return db;
}

/// Everything stored under the controller's pixelMap, as canonical JSON.
Future<String> _dump(FakeFirebaseFirestore db) async {
  final snap = await db.collection('users').doc(_uid).collection('controllers').doc(_ctrl).collection('pixelMap').get();
  final docs = {for (final d in snap.docs) d.id: d.data()};
  return jsonEncode({for (final k in (docs.keys.toList()..sort())) k: docs[k]},
      toEncodable: (o) => o.toString()); // Timestamp, after a real save
}

ProviderContainer _container(FakeFirebaseFirestore db, Map<int, int> busLengths) {
  int start = 0;
  final channels = <DeviceChannel>[];
  for (final e in busLengths.entries) {
    channels.add(DeviceChannel(id: e.key, name: 'Channel ${e.key + 1}', start: start, stop: start + e.value, gpioPin: e.key));
    start += e.value;
  }
  return ProviderContainer(overrides: [
    demoExperienceActiveProvider.overrideWith((ref) => false),
    effectiveUserUidProvider.overrideWithValue(_uid),
    activePixelMapControllerIdProvider.overrideWithValue(_ctrl),
    rooflineConfigServiceProvider.overrideWithValue(RooflineConfigService(firestore: db)),
    deviceChannelsProvider.overrideWithValue(channels),
  ]);
}

void main() {
  test('home D: the working model is healed; the stored docs are untouched; remap stays on', () async {
    final db = await _seed(_homeD);
    final before = await _dump(db);
    final c = _container(db, const {0: 41, 1: 41});
    addTearDown(c.dispose);

    // Settle the lazy migration first so the config stream is not rebuilt out
    // from under StreamProvider.future (same as pixel_map_service_test.dart).
    await c.read(pixelMapMigrationProvider.future);
    final config = (await c.read(currentRooflineConfigProvider.future))!;
    expect([for (final s in config.segmentsForChannel(0)) s.startPixel], [0, 28]);
    expect(config.segmentsForChannel(1).single.startPixel, 0, reason: 'stored 41 — §4: [41] → [0]');

    // A consumer, on the healed model: "All runs" on channel 2 reaches LEDs 0–40.
    final runs = featureIndices(config.segmentsForChannel(1), FeatureFilter.allRuns);
    expect(runs.where((i) => i < 41).length, 41, reason: 'was 0 of 41');

    // The RAW docs are what the staleness signal reads — still flagged.
    final raw = await c.read(currentPixelMapChannelsProvider.future);
    expect(raw.firstWhere((p) => p.channelIndex == 1).segments.single.startPixel, 41,
        reason: 'the raw stream is NOT healed');
    expect(c.read(pixelMapStalenessProvider), {0: false, 1: true});

    // The editor's load path heals the same way — and also writes nothing.
    await c.read(rooflineConfigEditorProvider.notifier).initialize();
    expect(c.read(rooflineConfigEditorProvider)!.segmentsForChannel(1).single.startPixel, 0);

    expect(await _dump(db), before, reason: 'READING MUST NOT WRITE — stored docs changed');
  });

  test('home G: overshoot is kept in the data, bounded at use; the stored docs are untouched', () async {
    final db = await _seed(_homeG);
    final before = await _dump(db);
    final c = _container(db, const {0: 128, 1: 162});
    addTearDown(c.dispose);

    // Settle the lazy migration first so the config stream is not rebuilt out
    // from under StreamProvider.future (same as pixel_map_service_test.dart).
    await c.read(pixelMapMigrationProvider.future);
    final config = (await c.read(currentRooflineConfigProvider.future))!;
    final ch0 = config.segmentsForChannel(0).single;
    expect([ch0.startPixel, ch0.pixelCount], [0, 168], reason: 'start healed, pixel_count NOT guessed');
    expect(featureIndices([ch0], FeatureFilter.allRuns).where((i) => i < 128).length, 128,
        reason: 'was 0 of 128');
    expect([config.globalStartOf(ch0), config.globalEndOf(ch0)], [0, 127]);

    await c.read(currentPixelMapChannelsProvider.future);
    expect(c.read(pixelMapStalenessProvider), {0: true, 1: false},
        reason: 'ch0 needs a remap; the partial ch1 is valid and is not flagged');
    expect(await _dump(db), before, reason: 'READING MUST NOT WRITE');
  });

  test('heal-on-SAVE still does the persisting: an ordinary owner save writes §4\'s value', () async {
    final db = await _seed(_homeD);
    final c = _container(db, const {0: 41, 1: 41});
    addTearDown(c.dispose);
    await c.read(pixelMapMigrationProvider.future);
    final editor = c.read(rooflineConfigEditorProvider.notifier);
    await editor.initialize();
    expect(await editor.save(), isTrue); // the OWNER pressing Save — not this fix
    final stored = jsonDecode(await _dump(db)) as Map<String, dynamic>;
    expect(((stored['1'] as Map)['segments'] as List).single['start_pixel'], 0);
    await c.read(currentPixelMapChannelsProvider.future);
    expect(c.read(pixelMapStalenessProvider)[1], isFalse, reason: 'the flag clears only after a REAL save');
  });
}
