// Design Studio Slice 1 — RooflineConfigService per-controller storage + lazy
// migration + the currentRooflineConfigProvider read chain, against a fake
// Firestore.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

const _uid = 'user123';
const _ctrl = 'ctrl1';

RooflineConfiguration _config() => RooflineConfiguration(
      id: _ctrl,
      controllerId: _ctrl,
      name: 'My Roofline',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
      totalChannelCount: 2,
      segments: const [
        RooflineSegment(
            id: 's0',
            name: 'Front',
            pixelCount: 128,
            type: SegmentType.run,
            channelIndex: 0,
            sortOrder: 0),
        RooflineSegment(
            id: 's1',
            name: 'Peak',
            pixelCount: 24,
            type: SegmentType.peak,
            architecturalRole: ArchitecturalRole.peak,
            channelIndex: 0,
            sortOrder: 1),
        RooflineSegment(
            id: 's2',
            name: 'Side',
            pixelCount: 60,
            type: SegmentType.run,
            channelIndex: 1,
            sortOrder: 0),
      ],
    );

CollectionReference<Map<String, dynamic>> _pixelMapCol(
        FakeFirebaseFirestore db) =>
    db
        .collection('users')
        .doc(_uid)
        .collection('controllers')
        .doc(_ctrl)
        .collection('pixelMap');

void main() {
  group('savePixelMap / loadPixelMapChannels', () {
    test('round-trips a multi-channel map into per-channel docs', () async {
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);

      await svc.savePixelMap(_uid, _ctrl, _config(),
          sourceCounts: const {0: 128, 1: 60}, createdBy: _uid);

      // One doc per channel, doc id == channel index.
      final snap = await _pixelMapCol(db).get();
      expect(snap.docs.map((d) => d.id).toSet(), {'0', '1'});

      final channels = await svc.loadPixelMapChannels(_uid, _ctrl);
      expect(channels.length, 2);
      final ch0 = channels.firstWhere((c) => c.channelIndex == 0);
      expect(ch0.segments.length, 2);
      expect(ch0.sourcePixelCount, 128);
      expect(ch0.createdBy, _uid);

      // Aggregate is faithful to the original (serializer parity).
      final agg = aggregatePixelMapChannelsToConfig(_ctrl, channels);
      expect(agg.totalPixelCount, _config().totalPixelCount); // 128+24+60
      expect(agg.segments.map((s) => s.id).toList(), ['s0', 's1', 's2']);
      expect(agg.segmentsForChannel(0).map((s) => s.name), ['Front', 'Peak']);
    });

    test('re-saving with a channel removed deletes its orphan doc', () async {
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);
      await svc.savePixelMap(_uid, _ctrl, _config());
      expect((await _pixelMapCol(db).get()).docs.length, 2);

      // Save a config with only channel 0.
      final onlyCh0 = _config().copyWith(
        segments:
            _config().segments.where((s) => s.channelIndex == 0).toList(),
      );
      await svc.savePixelMap(_uid, _ctrl, onlyCh0);

      final ids = (await _pixelMapCol(db).get()).docs.map((d) => d.id).toSet();
      expect(ids, {'0'}); // channel 1 doc deleted
    });
  });

  group('lazy migrateLegacyToPixelMap', () {
    Future<void> seedLegacy(FakeFirebaseFirestore db) async {
      await db
          .collection('users')
          .doc(_uid)
          .collection('roofline_config')
          .doc('config')
          .set(_config().toJson());
    }

    test('migrates a legacy config into per-channel docs + marks it', () async {
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);
      await seedLegacy(db);

      final migrated = await svc.migrateLegacyToPixelMap(_uid, _ctrl);
      expect(migrated, isTrue);

      final channels = await svc.loadPixelMapChannels(_uid, _ctrl);
      expect(channels.map((c) => c.channelIndex).toSet(), {0, 1});
      expect(channels.fold<int>(0, (a, c) => a + c.mappedPixelCount),
          _config().totalPixelCount);

      // Legacy doc marked migrated (not deleted).
      final legacy = await db
          .collection('users')
          .doc(_uid)
          .collection('roofline_config')
          .doc('config')
          .get();
      expect(legacy.exists, isTrue);
      expect(legacy.data()!['migrated_to_pixel_map'], isTrue);
      expect(legacy.data()!['migrated_controller_id'], _ctrl);
    });

    test('is a no-op when no legacy config exists', () async {
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);
      final migrated = await svc.migrateLegacyToPixelMap(_uid, _ctrl);
      expect(migrated, isFalse);
      expect((await _pixelMapCol(db).get()).docs, isEmpty);
    });

    test('is idempotent — second call does nothing once pixelMap exists',
        () async {
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);
      await seedLegacy(db);

      expect(await svc.migrateLegacyToPixelMap(_uid, _ctrl), isTrue);
      // Mutate legacy afterwards; a second migration must NOT overwrite pixelMap.
      expect(await svc.migrateLegacyToPixelMap(_uid, _ctrl), isFalse);
      expect((await _pixelMapCol(db).get()).docs.length, 2);
    });
  });

  group('updateChannelStaleFlags', () {
    test('persists is_stale per channel doc (merge)', () async {
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);
      await svc.savePixelMap(_uid, _ctrl, _config());

      await svc.updateChannelStaleFlags(_uid, _ctrl, {0: true, 1: false});
      final channels = await svc.loadPixelMapChannels(_uid, _ctrl);
      expect(channels.firstWhere((c) => c.channelIndex == 0).isStale, isTrue);
      expect(channels.firstWhere((c) => c.channelIndex == 1).isStale, isFalse);
      // Merge preserved segment data.
      expect(channels.firstWhere((c) => c.channelIndex == 0).segments, isNotEmpty);
    });
  });

  group('currentRooflineConfigProvider read chain', () {
    ProviderContainer makeContainer(FakeFirebaseFirestore db) {
      return ProviderContainer(overrides: [
        demoExperienceActiveProvider.overrideWith((ref) => false),
        effectiveUserUidProvider.overrideWithValue(_uid),
        activePixelMapControllerIdProvider.overrideWithValue(_ctrl),
        rooflineConfigServiceProvider
            .overrideWithValue(RooflineConfigService(firestore: db)),
      ]);
    }

    test('aggregates seeded pixelMap docs into RooflineConfiguration',
        () async {
      final db = FakeFirebaseFirestore();
      await RooflineConfigService(firestore: db)
          .savePixelMap(_uid, _ctrl, _config(), createdBy: _uid);

      final container = makeContainer(db);
      addTearDown(container.dispose);

      // Settle the lazy migration first so the config stream isn't rebuilt out
      // from under StreamProvider.future by the migration state transition.
      await container.read(pixelMapMigrationProvider.future);
      final config = await container.read(currentRooflineConfigProvider.future);
      expect(config, isNotNull);
      expect(config!.controllerId, _ctrl);
      expect(config.segments.length, 3);
      expect(config.totalPixelCount, _config().totalPixelCount);
    });

    test('lazy-migrates a legacy config on first read', () async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('users')
          .doc(_uid)
          .collection('roofline_config')
          .doc('config')
          .set(_config().toJson());

      final container = makeContainer(db);
      addTearDown(container.dispose);

      // Force the lazy migration to complete first (it also runs transitively
      // when the config is read, but awaiting it makes the read deterministic).
      final didMigrate =
          await container.read(pixelMapMigrationProvider.future);
      expect(didMigrate, isTrue);

      final config = await container.read(currentRooflineConfigProvider.future);
      expect(config, isNotNull);
      expect(config!.segments.length, 3);

      // The per-channel docs now exist.
      final channels = await RooflineConfigService(firestore: db)
          .loadPixelMapChannels(_uid, _ctrl);
      expect(channels.length, 2);
    });

    test('returns null when there is no controller', () async {
      final db = FakeFirebaseFirestore();
      final container = ProviderContainer(overrides: [
        demoExperienceActiveProvider.overrideWith((ref) => false),
        effectiveUserUidProvider.overrideWithValue(_uid),
        activePixelMapControllerIdProvider.overrideWithValue(null),
        rooflineConfigServiceProvider
            .overrideWithValue(RooflineConfigService(firestore: db)),
      ]);
      addTearDown(container.dispose);
      await container.read(pixelMapMigrationProvider.future);
      final config = await container.read(currentRooflineConfigProvider.future);
      expect(config, isNull);
    });
  });
}
