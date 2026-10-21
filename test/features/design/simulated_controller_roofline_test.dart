// Store readiness 3b — Design Studio on the App Store review account.
//
// The review account runs on the simulated controller (DemoWledRepository).
// Its controller doc is a placeholder with no stored pixel map, so the gate
// read "Your roofline isn't mapped yet" and the reviewer could not open the
// studio. currentRooflineConfigProvider now falls back to the stock trace that
// was authored for the stock hero photo the review account shows — and only
// when NOTHING is stored, so a real map always wins and a real controller is
// untouched.
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/design/design_studio_gate.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

import '../../helpers/recording_wled_repository.dart';

const _uid = 'user-fixture';
const _ctrl = 'ctrl-fixture';

Future<FakeFirebaseFirestore> _db({bool withStoredMap = false}) async {
  final db = FakeFirebaseFirestore();
  if (withStoredMap) {
    final doc = {
      'channel_index': 0,
      'segments': [
        {
          'id': 'ch0_seg0', 'name': 'Stored Run', 'pixel_count': 40,
          'start_pixel': 0, 'type': 'run', 'anchor_pixels': <int>[],
          'anchor_led_count': 2, 'sort_order': 0, 'channel_index': 0,
        },
      ],
      'source_pixel_count': 40, 'map_version': 1, 'created_by': 'fixture',
      'is_stale': false,
    };
    await db
        .collection('users').doc(_uid)
        .collection('controllers').doc(_ctrl)
        .collection('pixelMap').doc('0')
        .set(jsonDecode(jsonEncode(doc)) as Map<String, dynamic>);
  }
  return db;
}

ProviderContainer _container(FakeFirebaseFirestore db, WledRepository? repo) {
  return ProviderContainer(overrides: [
    demoExperienceActiveProvider.overrideWith((ref) => false),
    effectiveUserUidProvider.overrideWithValue(_uid),
    activePixelMapControllerIdProvider.overrideWithValue(_ctrl),
    rooflineConfigServiceProvider
        .overrideWithValue(RooflineConfigService(firestore: db)),
    wledRepositoryProvider.overrideWithValue(repo),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle for the trace

  test('simulated controller, nothing stored: the stock trace, segmented',
      () async {
    final c = _container(await _db(), DemoWledRepository());
    addTearDown(c.dispose);
    await c.read(pixelMapMigrationProvider.future);

    final config = await c.read(currentRooflineConfigProvider.future);
    expect(config, isNotNull);
    expect(config!.segments, hasLength(6));

    final seg = assessRooflineSegmentation(config);
    expect(seg.isSegmented, isTrue,
        reason: 'both channels carry a peak, so the gate opens');
    expect(gateForSegmentation(seg).state, DesignStudioGateState.ready);
  });

  test('simulated controller with a stored map: the stored map wins',
      () async {
    final c = _container(await _db(withStoredMap: true), DemoWledRepository());
    addTearDown(c.dispose);
    await c.read(pixelMapMigrationProvider.future);

    final config = await c.read(currentRooflineConfigProvider.future);
    expect(config!.segments.single.name, 'Stored Run');
  });

  test('real controller, nothing stored: still null (unchanged)', () async {
    final c = _container(await _db(), RecordingWledRepository());
    addTearDown(c.dispose);
    await c.read(pixelMapMigrationProvider.future);

    expect(await c.read(currentRooflineConfigProvider.future), isNull);
  });
}
