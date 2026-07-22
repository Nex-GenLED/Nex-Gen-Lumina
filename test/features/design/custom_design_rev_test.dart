// Tests for CustomDesign.toWledPayload's seg `rev` handling (#4, firmware-free
// half).
//
// Root cause: toWledPayload wrote `'rev': channel.reverse` on EVERY segment.
// ChannelDesign.reverse defaults false, so every design apply forced rev:false
// — clobbering the device's manual per-segment direction on each design change
// / sync-stop. Fix: emit `rev` ONLY when reverse == true; omit it otherwise so
// the apply preserves the controller's current seg.rev.
//
// Pure-model tests — no Firebase, no Riverpod, no device.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';

void main() {
  CustomDesign designWith(List<ChannelDesign> channels) {
    final now = DateTime(2026, 6, 3);
    return CustomDesign(
      id: 'd1',
      name: 'Test Design',
      createdAt: now,
      updatedAt: now,
      ownerId: 'u1',
      channels: channels,
    );
  }

  ChannelDesign channel({required int id, required bool reverse}) {
    return ChannelDesign(
      channelId: id,
      channelName: 'ch$id',
      colorGroups: const [
        LedColorGroup(startLed: 0, endLed: 10, color: [255, 0, 0, 0]),
      ],
      reverse: reverse,
    );
  }

  List<Map<String, dynamic>> segsOf(CustomDesign d) {
    final payload = d.toWledPayload();
    return (payload['seg'] as List).cast<Map<String, dynamic>>();
  }

  group('CustomDesign.toWledPayload — seg rev', () {
    test('non-reversed channel OMITS rev (preserves device direction)', () {
      final d = designWith([channel(id: 0, reverse: false)]);
      final seg = segsOf(d).single;

      expect(seg.containsKey('rev'), isFalse,
          reason: 'rev must be omitted when not reversed so the device keeps '
              'its current manual direction');
    });

    test('reversed channel emits rev:true', () {
      final d = designWith([channel(id: 0, reverse: true)]);
      final seg = segsOf(d).single;

      expect(seg['rev'], isTrue);
    });

    test('mixed channels — only the reversed one carries rev', () {
      final d = designWith([
        channel(id: 0, reverse: false),
        channel(id: 1, reverse: true),
        channel(id: 2, reverse: false),
      ]);
      final segs = segsOf(d);

      expect(segs[0].containsKey('rev'), isFalse);
      expect(segs[1]['rev'], isTrue);
      expect(segs[2].containsKey('rev'), isFalse);
    });

    test('omitting rev does not break the rest of the apply payload', () {
      final d = designWith([channel(id: 0, reverse: false)]);
      final payload = d.toWledPayload();
      final seg = segsOf(d).single;

      // Core apply fields still present and well-formed.
      expect(payload['on'], isTrue);
      expect(payload['bri'], isA<int>());
      expect(seg['id'], 0);
      expect(seg['col'], isA<List>());
      expect(seg['fx'], isA<int>());
      expect(seg['sx'], isA<int>());
      expect(seg['ix'], isA<int>());
    });
  });
}
