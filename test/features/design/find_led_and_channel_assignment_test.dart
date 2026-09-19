// M6 (N1a) — "Find LED → Light It Up" sends real, CHECKED writes.
// N1c      — the Roofline Setup Wizard assigns segments to channels.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/find_led.dart';
import 'package:nexgen_command/features/design/roofline_channel_assignment.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 16),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 3),
];

/// Records what was sent; each write's answer is scripted.
class _FakeRepo implements WledRepository, PerPixelWriter {
  _FakeRepo({this.jsonOk = true, this.pixelOk = true});
  final bool jsonOk;
  final bool pixelOk;
  final json = <Map<String, dynamic>>[];
  final pixels = <({int segmentId, List<PixelSpan> spans})>[];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(payload);
    return jsonOk;
  }

  @override
  Future<bool> applyPerPixel({
    int segmentId = 0,
    required List<PixelSpan> spans,
    int chunkSize = kDefaultPixelChunkSize,
  }) async {
    pixels.add((segmentId: segmentId, spans: spans));
    return pixelOk;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('lightSingleLed', () {
    test('resolves a whole-controller number onto the right channel', () async {
      final repo = _FakeRepo();
      final r = await lightSingleLed(repo: repo, channels: _channels, globalIndex: 130);

      expect(r.isLit, isTrue);
      expect(r.channelId, 1);
      expect(r.localIndex, 2, reason: '130 − channel 2 start (128)');
      // Base: every channel, solid black, master on.
      expect(repo.json.single['on'], true);
      final segs = (repo.json.single['seg'] as List).cast<Map>();
      expect(segs.map((s) => s['id']), [0, 1]);
      expect(segs.every((s) => s['fx'] == 0), isTrue);
      // Then exactly one red pixel, on channel 2 only.
      expect(repo.pixels.single.segmentId, 1);
      expect(repo.pixels.single.spans.single.start, 2);
      expect(repo.pixels.single.spans.single.end, 2);
      expect(repo.pixels.single.spans.single.color, [255, 0, 0, 0]);
      expect(r.message, contains('LED 130 is lit red'));
    });

    test('NEVER reports success when the controller refuses a write', () async {
      final baseFails = await lightSingleLed(
          repo: _FakeRepo(jsonOk: false), channels: _channels, globalIndex: 5);
      expect(baseFails.outcome, FindLedOutcome.writeFailed);
      expect(baseFails.message, contains('NOT lit'));

      final pixelRepo = _FakeRepo(pixelOk: false);
      final pixelFails =
          await lightSingleLed(repo: pixelRepo, channels: _channels, globalIndex: 5);
      expect(pixelFails.outcome, FindLedOutcome.writeFailed);
      expect(pixelFails.isLit, isFalse);
    });

    test('says so instead of pretending: no controller / no channels / out of range', () async {
      expect((await lightSingleLed(repo: null, channels: _channels, globalIndex: 1)).outcome,
          FindLedOutcome.noController);
      expect((await lightSingleLed(repo: _FakeRepo(), channels: const [], globalIndex: 1)).outcome,
          FindLedOutcome.noChannels);
      final repo = _FakeRepo();
      final past = await lightSingleLed(repo: repo, channels: _channels, globalIndex: 290);
      expect(past.outcome, FindLedOutcome.outOfRange);
      expect(past.message, contains('290 LEDs'));
      expect(repo.json, isEmpty, reason: 'nothing is sent for an invalid LED');
    });

    test('restore replays the captured LOOK — no geometry, no per-pixel key', () {
      final payload = buildRestorePayload({
        'on': false,
        'bri': 128,
        'seg': [
          {'id': 0, 'start': 0, 'stop': 128, 'on': true, 'fx': 17, 'sx': 40, 'ix': 128,
           'pal': 5, 'grp': 1, 'spc': 2, 'rev': true, 'of': 3, 'frz': true,
           'col': [[255, 160, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]},
        ],
      })!;
      expect(payload['on'], false);
      expect(payload['bri'], 128);
      final seg = (payload['seg'] as List).single as Map;
      expect(seg.keys, containsAll(['id', 'on', 'fx', 'sx', 'ix', 'pal', 'grp', 'spc', 'col']));
      for (final k in ['start', 'stop', 'rev', 'of', 'frz', 'i']) {
        expect(seg.containsKey(k), isFalse, reason: '$k must not be replayed');
      }
      expect(buildRestorePayload(null), isNull);
    });
  });

  group('assignSegmentsToChannels', () {
    test('walks the roof across channel lengths', () {
      final a = assignSegmentsToChannels(
        segmentLedCounts: [100, 28, 150, 12],
        channelLedCounts: [128, 162],
      );
      expect(a.isValid, isTrue);
      expect(a.channelIndexBySegment, [0, 0, 1, 1]);
    });

    test('a segment straddling two channels is reported, not guessed', () {
      final a = assignSegmentsToChannels(
        segmentLedCounts: [100, 60],
        channelLedCounts: [128, 162],
        segmentNames: ['Front run', 'Porch'],
      );
      expect(a.isValid, isFalse);
      expect(a.error, contains('"Porch"'));
      expect(a.error, contains('28 + 32'));
    });

    test('single channel (or none typed) → everything on channel 0', () {
      expect(assignSegmentsToChannels(segmentLedCounts: [50, 50], channelLedCounts: [100])
          .channelIndexBySegment, [0, 0]);
      expect(assignSegmentsToChannels(segmentLedCounts: [50, 50], channelLedCounts: [])
          .channelIndexBySegment, [0, 0]);
    });

    test('LEDs past the last channel stay on the last channel', () {
      final a = assignSegmentsToChannels(
        segmentLedCounts: [128, 162, 40],
        channelLedCounts: [128, 162],
      );
      expect(a.isValid, isTrue);
      expect(a.channelIndexBySegment, [0, 1, 1]);
    });
  });
}
