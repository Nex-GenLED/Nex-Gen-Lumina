// +113 — a cleanup's backup lives on the channel doc and survives the next
// ordinary full save; a channel without a backup gains none.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

const _uid = 'user123';
const _ctrl = 'ctrl1';

RooflineConfiguration _config(List<RooflineSegment> segments) =>
    RooflineConfiguration(
      id: _ctrl,
      controllerId: _ctrl,
      name: 'My Roofline',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
      totalChannelCount: 2,
      segments: segments,
    );

const _ch0 = RooflineSegment(
    id: 'a', name: 'Front', pixelCount: 44, channelIndex: 0, sortOrder: 0);
const _ch1a = RooflineSegment(
    id: 'b', name: 'Side', pixelCount: 42, channelIndex: 1, sortOrder: 1);
const _ch1dup = RooflineSegment(
    id: 'b', name: 'Side', pixelCount: 42, channelIndex: 1, sortOrder: 2);

DocumentReference<Map<String, dynamic>> _doc(FakeFirebaseFirestore db, int ch) =>
    db
        .collection('users')
        .doc(_uid)
        .collection('controllers')
        .doc(_ctrl)
        .collection('pixelMap')
        .doc('$ch');

void main() {
  test('backupChannelSegments writes the three backup fields and nothing else changes',
      () async {
    final db = FakeFirebaseFirestore();
    final svc = RooflineConfigService(firestore: db);
    await svc.savePixelMap(_uid, _ctrl, _config(const [_ch0, _ch1a, _ch1dup]),
        sourceCounts: const {0: 44, 1: 45}, createdBy: _uid);

    await svc.backupChannelSegments(_uid, _ctrl, {1: const [_ch1a, _ch1dup]},
        reason: 'duplicate cleanup');

    final ch1 = (await _doc(db, 1).get()).data()!;
    expect((ch1['segments_backup'] as List).length, 2);
    expect(ch1['segments_backup_reason'], 'duplicate cleanup');
    expect(ch1['segments_backup_at'], isA<Timestamp>());
    expect((ch1['segments'] as List).length, 2, reason: 'segments untouched');
    expect(ch1['source_pixel_count'], 45, reason: 'merge write');

    final ch0 = (await _doc(db, 0).get()).data()!;
    expect(ch0.containsKey('segments_backup'), isFalse);
  });

  test('the next full save carries the backup forward', () async {
    final db = FakeFirebaseFirestore();
    final svc = RooflineConfigService(firestore: db);
    await svc.savePixelMap(_uid, _ctrl, _config(const [_ch0, _ch1a, _ch1dup]),
        sourceCounts: const {0: 44, 1: 45}, createdBy: _uid);
    await svc.backupChannelSegments(_uid, _ctrl, {1: const [_ch1a, _ch1dup]},
        reason: 'duplicate cleanup');

    // The cleaned save: channel 1 keeps one copy.
    await svc.savePixelMap(_uid, _ctrl, _config(const [_ch0, _ch1a]),
        sourceCounts: const {0: 44, 1: 45}, createdBy: _uid);

    final ch1 = (await _doc(db, 1).get()).data()!;
    expect((ch1['segments'] as List).length, 1);
    expect((ch1['segments_backup'] as List).length, 2,
        reason: 'reversible: the stacked list is still on the doc');
    expect(ch1['segments_backup_reason'], 'duplicate cleanup');

    // Restoring is copying the backup back over segments — the model reads it.
    final restored = (ch1['segments_backup'] as List)
        .map((j) => RooflineSegment.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    expect(restored.map((s) => s.id), ['b', 'b']);

    final ch0 = (await _doc(db, 0).get()).data()!;
    expect(ch0.containsKey('segments_backup'), isFalse,
        reason: 'no backup is invented for a channel that had none');
  });
}
