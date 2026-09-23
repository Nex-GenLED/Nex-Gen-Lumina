// P1 REGRESSION GATE — `source_aspect_ratio` must survive the pixelMap
// round trip.
//
// The defect (residential path audit 2026-09-23 §6, §9.1 item 12):
// `PixelMapChannel` had no such field, so `toJson` never emitted it and
// `aggregatePixelMapChannelsToConfig` rebuilt the config without it. EVERY
// pixelMap writer therefore dropped it — production census 2026-09-23: 24 of
// 24 pixelMap docs have no `source_aspect_ratio`. The only remaining carrier
// was the legacy `roofline_mask` on the user doc, which none of the
// installer-mapped paths (Step 6, Segment Setup, the Roofline Setup Wizard,
// Refine, the legacy migration) writes.
//
// Downstream: under BoxFit.cover the painter resolves
// segment → painter → mask, all null, and the `assert(false, ...)` that was
// supposed to catch it is STRIPPED from release builds — so the shipped app
// silently mis-projects the trace on every installer-mapped home.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

const _uid = 'cust';
const _ctrl = 'ctrl1';
const _aspect = 4 / 3;

RooflineSegment _seg(int channel, int start, int count) => RooflineSegment(
      id: 'ch$channel-$start',
      name: 'Run',
      startPixel: start,
      pixelCount: count,
      channelIndex: channel,
      points: const [Offset(0.1, 0.2), Offset(0.9, 0.3)],
    );

RooflineConfiguration _config({double? aspect}) => RooflineConfiguration(
      id: _ctrl,
      controllerId: _ctrl,
      name: 'Roofline',
      segments: [_seg(0, 0, 40), _seg(1, 0, 60)],
      createdAt: DateTime(2026, 9, 23),
      updatedAt: DateTime(2026, 9, 23),
      totalChannelCount: 2,
      sourceAspectRatio: aspect,
    );

void main() {
  group('PixelMapChannel carries source_aspect_ratio', () {
    test('THE REGRESSION: toJson emits it', () {
      final channels = splitConfigToPixelMapChannels(
        _config(aspect: _aspect),
        controllerId: _ctrl,
      );
      expect(channels, hasLength(2));
      for (final ch in channels) {
        expect(ch.sourceAspectRatio, _aspect);
        expect(ch.toJson()['source_aspect_ratio'], _aspect);
      }
    });

    test('the key is omitted when there is no aspect, not written as null',
        () {
      final channels = splitConfigToPixelMapChannels(
        _config(),
        controllerId: _ctrl,
      );
      expect(channels.first.toJson().containsKey('source_aspect_ratio'),
          isFalse);
    });

    test('fromJson reads it back', () {
      final json = splitConfigToPixelMapChannels(
        _config(aspect: _aspect),
        controllerId: _ctrl,
      ).first.toJson();
      final parsed = PixelMapChannel.fromJson(_ctrl, '0', json);
      expect(parsed.sourceAspectRatio, _aspect);
    });

    test('an int in the stored doc still parses as a double', () {
      final parsed = PixelMapChannel.fromJson(_ctrl, '0', {
        'channel_index': 0,
        'segments': <dynamic>[],
        'source_aspect_ratio': 2,
      });
      expect(parsed.sourceAspectRatio, 2.0);
    });

    test('copyWith carries it', () {
      final ch = splitConfigToPixelMapChannels(
        _config(aspect: _aspect),
        controllerId: _ctrl,
      ).first;
      expect(ch.copyWith(name: 'Other').sourceAspectRatio, _aspect);
      expect(ch.copyWith(sourceAspectRatio: 1.5).sourceAspectRatio, 1.5);
    });

    test('aggregate puts it back on the config the overlay reads', () {
      final channels = splitConfigToPixelMapChannels(
        _config(aspect: _aspect),
        controllerId: _ctrl,
      );
      final back = aggregatePixelMapChannelsToConfig(_ctrl, channels);
      expect(back.sourceAspectRatio, _aspect);
    });

    test('aggregate is null when no channel has one (legacy docs)', () {
      final channels =
          splitConfigToPixelMapChannels(_config(), controllerId: _ctrl);
      final back = aggregatePixelMapChannelsToConfig(_ctrl, channels);
      expect(back.sourceAspectRatio, isNull,
          reason: 'consumers must fall back to the legacy mask, as before');
    });

    test('aggregate finds it on a later channel', () {
      var channels =
          splitConfigToPixelMapChannels(_config(), controllerId: _ctrl);
      channels = [
        channels.first,
        channels.last.copyWith(sourceAspectRatio: _aspect),
      ];
      expect(
        aggregatePixelMapChannelsToConfig(_ctrl, channels).sourceAspectRatio,
        _aspect,
      );
    });
  });

  group('savePixelMap round trip', () {
    test('writes the aspect to Firestore and loads it back', () async {
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);

      await svc.savePixelMap(_uid, _ctrl, _config(aspect: _aspect),
          createdBy: _uid);

      final raw = await db
          .collection('users')
          .doc(_uid)
          .collection('controllers')
          .doc(_ctrl)
          .collection('pixelMap')
          .doc('0')
          .get();
      expect(raw.data()!['source_aspect_ratio'], _aspect);

      final loaded = await svc.loadPixelMapChannels(_uid, _ctrl);
      expect(loaded.first.sourceAspectRatio, _aspect);
    });

    test('A REBUILDING WRITER DOES NOT STRIP IT', () async {
      // savePixelMap writes each doc with a FULL set(), so Refine / the
      // installer Map step / the Roofline Setup Wizard — which all construct a
      // fresh RooflineConfiguration with no aspect — would otherwise erase an
      // aspect a photo trace had already established.
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);

      await svc.savePixelMap(_uid, _ctrl, _config(aspect: _aspect),
          createdBy: _uid);
      await svc.savePixelMap(_uid, _ctrl, _config(), createdBy: _uid);

      final loaded = await svc.loadPixelMapChannels(_uid, _ctrl);
      expect(loaded, isNotEmpty);
      for (final ch in loaded) {
        expect(ch.sourceAspectRatio, _aspect,
            reason: 'a rebuilt config must not silently drop the traced '
                'photo aspect');
      }
    });

    test('an explicit new aspect replaces the stored one', () async {
      final db = FakeFirebaseFirestore();
      final svc = RooflineConfigService(firestore: db);

      await svc.savePixelMap(_uid, _ctrl, _config(aspect: _aspect),
          createdBy: _uid);
      await svc.savePixelMap(_uid, _ctrl, _config(aspect: 16 / 9),
          createdBy: _uid);

      final loaded = await svc.loadPixelMapChannels(_uid, _ctrl);
      expect(loaded.first.sourceAspectRatio, 16 / 9,
          reason: 're-tracing on a new photo must win');
    });
  });
}
