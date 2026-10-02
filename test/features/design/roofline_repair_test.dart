// +113 — duplicate-segment cleanup: a stacked fixture collapses to one
// canonical set without touching any kept segment's lights, the backup holds
// every original, and the Design Studio gate and Game Day participation read
// the same answer before and after.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_repair.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/neighborhood/services/channel_participation_resolver.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

RooflineSegment _seg(String id, int start, int count,
        {SegmentType type = SegmentType.run,
        ArchitecturalRole? role,
        String? name,
        int ch = 1,
        bool confirmed = true}) =>
    RooflineSegment(
      id: id,
      name: name ?? (type == SegmentType.run ? 'Run' : type.name),
      startPixel: start,
      pixelCount: count,
      type: type,
      architecturalRole: role,
      channelIndex: ch,
      featureConfirmed: confirmed,
    );

RooflineConfiguration _config(List<RooflineSegment> segments) =>
    RooflineConfiguration(
      id: 'c',
      controllerId: 'c',
      name: 'r',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      segments: segments,
      channelPixelCounts: const {0: 44, 1: 45},
    );

void main() {
  // The tester's shape as stored today: channel 0 one run, channel 1
  // run · corner · run. Nothing to clean.
  final clean = [
    _seg('ch0_seg0', 0, 44, ch: 0, name: 'Run 1'),
    _seg('ch1_seg0', 0, 42, name: 'Run 1'),
    _seg('ch1_seg1', 42, 1,
        type: SegmentType.corner, role: ArchitecturalRole.corner, name: 'Corner'),
    _seg('ch1_seg2', 43, 2, name: 'Run 2'),
  ];

  // A stacked channel 1: the same three sections written twice more, as a
  // re-marking bug would leave them — once with the same ids at the same
  // starts, once with the same ids rebased to follow (end to end).
  final stacked = [
    clean[0],
    ...clean.sublist(1),
    _seg('ch1_seg0', 0, 42, name: 'Run 1'),
    _seg('ch1_seg1', 42, 1,
        type: SegmentType.corner, role: ArchitecturalRole.corner, name: 'Corner'),
    _seg('ch1_seg2', 43, 2, name: 'Run 2'),
    _seg('ch1_seg0', 45, 42, name: 'Run 1'),
    _seg('ch1_seg1', 87, 1,
        type: SegmentType.corner, role: ArchitecturalRole.corner, name: 'Corner'),
    _seg('ch1_seg2', 88, 2, name: 'Run 2'),
  ];

  group('planChannelCleanup', () {
    test('a clean channel has nothing to do', () {
      final plans = planRooflineCleanup(_config(clean));
      expect(cleanupHasWork(plans), isFalse);
      expect(plans[1]!.kept.length, 3);
      expect(describeChannelCleanup(plans[1]!), contains('Nothing to clean up'));
      expect(applyCleanupPlans(_config(clean), plans).segments, clean);
    });

    test('a stacked channel collapses to the canonical set, kept lights untouched', () {
      final plans = planRooflineCleanup(_config(stacked));
      expect(cleanupHasWork(plans), isTrue);
      expect(plans[0]!.hasWork, isFalse);
      final p = plans[1]!;
      expect(p.original.length, 9);
      expect(p.kept.length, 3);
      expect(p.removed.length, 6);
      expect(p.renamed, isEmpty);
      expect(p.originalTotal, 135);
      expect(p.keptTotal, 45, reason: 'back to the strip length');
      // Every kept segment is one of the originals, with its own start/count.
      for (final k in p.kept) {
        final original = p.original.firstWhere((o) =>
            o.id == k.id && o.startPixel == k.startPixel && o.pixelCount == k.pixelCount);
        expect(original.name, k.name);
      }
      expect(p.kept.map((s) => (s.startPixel, s.pixelCount)),
          [(0, 42), (42, 1), (43, 2)]);
      // Reasons: the same-start copies are stacked, the rebased copies are
      // duplicate ids (the first copy with that id was kept).
      expect(
          p.removed.where((r) => r.reason == CleanupReason.stackedCopy).length, 3);
      expect(
          p.removed.where((r) => r.reason == CleanupReason.duplicateId).length, 3);
    });

    test('the backup (the plan\'s original list) holds every stored segment', () {
      final p = planRooflineCleanup(_config(stacked))[1]!;
      expect(p.original.length, 9);
      expect(p.original.map((s) => s.id).toSet(), {'ch1_seg0', 'ch1_seg1', 'ch1_seg2'});
    });

    test('same id with DIFFERENT lights is renamed, never removed', () {
      final p = planChannelCleanup(1, [
        _seg('ch1_seg1', 0, 10),
        _seg('ch1_seg1', 10, 1, type: SegmentType.corner, role: ArchitecturalRole.corner),
      ]);
      expect(p.removed, isEmpty);
      expect(p.renamed.single.newId, 'ch1_seg1_2');
      expect(p.kept.map((s) => s.id), ['ch1_seg1', 'ch1_seg1_2']);
      expect(p.keptTotal, 11);
    });

    test('adjacent identical neighbours are reported, not removed', () {
      final p = planChannelCleanup(1, [
        _seg('a', 0, 10, name: 'Run 1'),
        _seg('b', 10, 1, type: SegmentType.corner, role: ArchitecturalRole.corner),
        _seg('c', 11, 1, type: SegmentType.corner, role: ArchitecturalRole.corner),
        _seg('d', 12, 10, name: 'Run 2'),
      ]);
      expect(p.hasWork, isFalse);
      expect(p.suspects.single.map((s) => s.id), ['b', 'c']);
      expect(describeChannelCleanup(p), contains('identical neighbours left alone'));
    });

    test('applyCleanupPlans replaces only the planned channel and renumbers sortOrder', () {
      final before = _config(stacked);
      final after = applyCleanupPlans(before, planRooflineCleanup(before));
      expect(after.segmentsForChannel(0), [stacked[0]]);
      expect(after.segmentsForChannel(1).length, 3);
      expect(after.segments.map((s) => s.sortOrder), [0, 1, 2, 3]);
      expect(after.segmentsForChannel(1).map((s) => (s.startPixel, s.pixelCount)),
          [(0, 42), (42, 1), (43, 2)]);
    });
  });

  group('readers agree before and after', () {
    test('Design Studio gate answer is unchanged', () {
      final before = assessRooflineSegmentation(_config(stacked));
      final after = assessRooflineSegmentation(
          applyCleanupPlans(_config(stacked), planRooflineCleanup(_config(stacked))));
      expect(before.isSegmented, isTrue);
      expect(after.isSegmented, isTrue);
      expect(after.markedChannels, before.markedChannels);
      expect(after.unmarkedChannels, before.unmarkedChannels);
      // Only the counts shrink — three corners were one.
      expect(before.corners, 3);
      expect(after.corners, 1);
    });

    test('Game Day / sync participation is unchanged', () {
      final before = resolveParticipatingChannels(
          explicit: null, segments: stacked, allDeviceChannelIds: const [0, 1, 2]);
      final cleaned =
          applyCleanupPlans(_config(stacked), planRooflineCleanup(_config(stacked)));
      final after = resolveParticipatingChannels(
          explicit: null, segments: cleaned.segments, allDeviceChannelIds: const [0, 1, 2]);
      expect(after, before);
      expect(after, [0, 1, 2]);
    });
  });
}
