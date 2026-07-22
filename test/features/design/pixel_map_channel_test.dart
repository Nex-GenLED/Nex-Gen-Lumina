// Design Studio Slice 1 — per-channel pixel-map model tests (pure, no Firestore).
//
// Covers: per-channel doc round-trip incl. peak-up/peak-down direction;
// split/aggregate config conversion; device-truth source-count seeding +
// fallback; staleness; per-channel validation.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

RooflineConfiguration _config({
  DateTime? now,
  String name = 'My Roofline',
  String? photoPath = 'photos/home.jpg',
}) {
  final t = now ?? DateTime(2026, 7, 1);
  // Channel 0: a run + a peak split into up/down slopes. Channel 1: one run.
  return RooflineConfiguration(
    id: 'ctrl1',
    controllerId: 'ctrl1',
    name: name,
    photoPath: photoPath,
    createdAt: t,
    updatedAt: t,
    totalChannelCount: 2,
    segments: const [
      RooflineSegment(
        id: 's0',
        name: 'Front Run',
        pixelCount: 20,
        startPixel: 0,
        type: SegmentType.run,
        channelIndex: 0,
        sortOrder: 0,
      ),
      RooflineSegment(
        id: 's1',
        name: 'Peak Up',
        pixelCount: 15,
        startPixel: 20,
        type: SegmentType.peak,
        direction: SegmentDirection.upward,
        architecturalRole: ArchitecturalRole.peak,
        channelIndex: 0,
        sortOrder: 1,
      ),
      RooflineSegment(
        id: 's2',
        name: 'Peak Down',
        pixelCount: 15,
        startPixel: 35,
        type: SegmentType.peak,
        direction: SegmentDirection.downward,
        architecturalRole: ArchitecturalRole.peak,
        channelIndex: 0,
        sortOrder: 2,
      ),
      RooflineSegment(
        id: 's3',
        name: 'Side Accent',
        pixelCount: 60,
        startPixel: 0,
        type: SegmentType.run,
        channelIndex: 1,
        sortOrder: 0,
      ),
    ],
  );
}

void main() {
  group('PixelMapChannel serialization', () {
    test('toJson/fromJson round-trips incl. peak up/down direction + role', () {
      final channels = splitConfigToPixelMapChannels(
        _config(),
        controllerId: 'ctrl1',
        sourceCounts: const {0: 50, 1: 60},
        createdBy: 'user123',
        now: DateTime(2026, 7, 2),
      );
      final ch0 = channels.firstWhere((c) => c.channelIndex == 0);
      final restored = PixelMapChannel.fromJson('ctrl1', '0', ch0.toJson());

      expect(restored.channelIndex, 0);
      expect(restored.sourcePixelCount, 50);
      expect(restored.createdBy, 'user123');
      expect(restored.name, 'My Roofline');
      expect(restored.photoPath, 'photos/home.jpg');
      expect(restored.segments.length, 3);
      // Peak up/down expressed via SegmentDirection — no enum churn.
      final up = restored.segments.firstWhere((s) => s.name == 'Peak Up');
      final down = restored.segments.firstWhere((s) => s.name == 'Peak Down');
      expect(up.direction, SegmentDirection.upward);
      expect(up.type, SegmentType.peak);
      expect(up.architecturalRole, ArchitecturalRole.peak);
      expect(down.direction, SegmentDirection.downward);
    });

    test('doc id fallback supplies channelIndex when body omits it', () {
      final ch = PixelMapChannel.fromJson('c', '3', {'segments': const []});
      expect(ch.channelIndex, 3);
    });
  });

  group('split → aggregate round-trip', () {
    test('preserves segments, counts, name, and controllerId', () {
      final original = _config();
      final channels = splitConfigToPixelMapChannels(
        original,
        controllerId: 'ctrl1',
        now: DateTime(2026, 7, 2),
      );
      final restored = aggregatePixelMapChannelsToConfig('ctrl1', channels);

      expect(restored.controllerId, 'ctrl1');
      expect(restored.name, 'My Roofline');
      expect(restored.photoPath, 'photos/home.jpg');
      expect(restored.totalPixelCount, original.totalPixelCount); // 20+15+15+60
      expect(restored.segments.length, 4);
      // Segments come back in channel order (ch0 x3, then ch1 x1).
      expect(restored.segments.map((s) => s.id).toList(),
          ['s0', 's1', 's2', 's3']);
      expect(restored.segmentsForChannel(0).length, 3);
      expect(restored.segmentsForChannel(1).length, 1);
    });

    test('splits one doc per channel present', () {
      final channels = splitConfigToPixelMapChannels(_config(),
          controllerId: 'ctrl1', now: DateTime(2026, 7, 2));
      expect(channels.map((c) => c.channelIndex).toList(), [0, 1]);
    });

    test('empty channel list aggregates to an empty config with identity', () {
      final cfg = aggregatePixelMapChannelsToConfig('ctrlX', const []);
      expect(cfg.controllerId, 'ctrlX');
      expect(cfg.segments, isEmpty);
    });
  });

  group('device-truth source counts', () {
    test('uses provided WledLedBus.len counts', () {
      final channels = splitConfigToPixelMapChannels(_config(),
          controllerId: 'ctrl1',
          sourceCounts: const {0: 128, 1: 60},
          now: DateTime(2026, 7, 2));
      expect(channels.firstWhere((c) => c.channelIndex == 0).sourcePixelCount,
          128);
      expect(channels.firstWhere((c) => c.channelIndex == 1).sourcePixelCount,
          60);
    });

    test('falls back to mapped segment sum when a count is absent', () {
      final channels = splitConfigToPixelMapChannels(_config(),
          controllerId: 'ctrl1', now: DateTime(2026, 7, 2));
      // ch0 = 20+15+15 = 50; ch1 = 60.
      expect(channels.firstWhere((c) => c.channelIndex == 0).sourcePixelCount,
          50);
      expect(channels.firstWhere((c) => c.channelIndex == 1).sourcePixelCount,
          60);
    });
  });

  group('staleness', () {
    final ch = PixelMapChannel(
      controllerId: 'c',
      channelIndex: 0,
      segments: const [],
      sourcePixelCount: 128,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    test('matching live count is not stale', () {
      expect(ch.isStaleAgainst(128), isFalse);
    });
    test('drifted live count is stale', () {
      expect(ch.isStaleAgainst(130), isTrue);
    });
    test('unreachable device (null) is not provably stale', () {
      expect(ch.isStaleAgainst(null), isFalse);
    });
  });

  group('RooflineConfiguration.validateChannelsAgainstDevice', () {
    test('per-channel match/mismatch; unknown live count is valid', () {
      final cfg = _config(); // ch0 sum=50, ch1 sum=60
      final result = cfg.validateChannelsAgainstDevice({0: 50, 1: 55});
      expect(result[0], isTrue); // 50 == 50
      expect(result[1], isFalse); // 60 != 55 → stale
    });

    test('missing live count for a channel is treated as valid', () {
      final cfg = _config();
      final result = cfg.validateChannelsAgainstDevice({0: 50}); // ch1 unknown
      expect(result[0], isTrue);
      expect(result[1], isTrue);
    });
  });
}
