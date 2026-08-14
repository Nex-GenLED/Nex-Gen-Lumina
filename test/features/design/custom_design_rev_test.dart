// CustomDesign.toWledPayload must emit NO `rev`, in either direction (#76).
//
// HISTORY, because this file has now been wrong twice in the same place.
// Originally toWledPayload wrote `'rev': channel.reverse` on EVERY segment, so
// every apply forced rev:false and clobbered the device's manual direction.
// The first fix was to emit `rev` only when reverse == true — and these tests
// pinned that. It was a half-measure: it stopped the false-clobber but still
// let a design payload assert geometry.
//
// #76 (2026-08-14, field-reported by Ellie, whose reversed channel ran
// backwards all evening) settles it: a design payload asserts DESIGN fields
// only — fx/col/pal/sx/ix/on/bri. Geometry — rev, mi, bounds, of, grp/spc —
// belongs to provisioning and is never written by a design path. The device is
// the source of truth for how it is installed.
//
// The complement to #67: unstated segment state is inherited state; state that
// isn't yours to state must not be stated.
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

    // THE #76 REGRESSION, and the one that matters: a channel the app believes
    // is reversed must STILL not write rev. Ellie's channel was correctly
    // reversed on the device; every design apply overwrote that. Writing
    // rev:true would be the same defect wearing the opposite sign — the app's
    // model overriding the installation instead of flattening it.
    test('a REVERSED channel still emits no rev — the app does not own geometry',
        () {
      final d = designWith([channel(id: 0, reverse: true)]);
      final seg = segsOf(d).single;

      expect(seg.containsKey('rev'), isFalse,
          reason: 'geometry belongs to provisioning; a design apply must '
              'preserve whatever the device is installed as');
    });

    test('mixed channels — NO segment carries rev, whatever the model says',
        () {
      final d = designWith([
        channel(id: 0, reverse: false),
        channel(id: 1, reverse: true),
        channel(id: 2, reverse: false),
      ]);
      for (final seg in segsOf(d)) {
        expect(seg.containsKey('rev'), isFalse);
      }
    });

    // The whole geometry set, not just rev — so a future edit cannot
    // reintroduce a sibling field and pass.
    test('no geometry field of any kind appears in a design segment', () {
      final d = designWith([channel(id: 0, reverse: true)]);
      for (final seg in segsOf(d)) {
        for (final k in const ['rev', 'mi', 'start', 'stop', 'of', 'grp', 'spc']) {
          expect(seg.containsKey(k), isFalse, reason: '$k is geometry (#76)');
        }
      }
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
