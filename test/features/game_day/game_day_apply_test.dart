// Tests for [applyGameDayConfigToDevice] — the shared payload builder
// + apply path used by both Path 1's _activateNow and Path 2's "Light
// it Up Now". Verifies the multi-channel payload shape (channel-2 fix),
// the savedDesignPayload override precedence, the U1 empty-gate, and the
// label hint format.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/game_day/game_day_apply.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

void main() {
  group('applyGameDayConfigToDevice', () {
    // A 2-channel device (matches the hardware probe on 192.168.1.250:
    // seg 0 = 0-128 Front Roofline, seg 1 = 128-188 Side Accent).
    const twoChannels = [
      DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
      DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 188, gpioPin: 1),
    ];

    GameDayAutopilotConfig configFor({
      String teamSlug = 'mlb_royals',
      String teamName = 'Kansas City Royals',
      int effectId = 52,
      int speed = 200,
      int intensity = 180,
      int brightness = 220,
      int primary = 0xFF004687,
      int secondary = 0xFFBD9B60,
      Map<String, dynamic>? savedDesignPayload,
      String? savedDesignName,
    }) {
      final created = DateTime.utc(2026, 5, 1);
      return GameDayAutopilotConfig(
        teamSlug: teamSlug,
        teamName: teamName,
        espnTeamId: '7',
        sport: SportType.mlb,
        primaryColorValue: primary,
        secondaryColorValue: secondary,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
        savedDesignName: savedDesignName,
        savedDesignPayload: savedDesignPayload,
        createdAt: created,
        updatedAt: created,
      );
    }

    test(
        'cold/null participation cache, 2-channel device → addresses BOTH '
        'seg 0 AND seg 1 (channel-2 skip fix). The helper pre-enumerates '
        'channels itself instead of relying on the chokepoint, so the '
        'auto-built single-seg-no-id payload no longer falls through to '
        'seg 0 only.', () async {
      late Map<String, dynamic> captured;
      String? capturedLabel;
      final ok = await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          captured = payload;
          capturedLabel = labelHint;
          return true;
        },
        config: configFor(),
        participatingChannels: const [0, 1],
        deviceChannels: twoChannels,
      );

      expect(ok, isTrue);
      expect(captured['on'], isTrue);
      expect(captured['bri'], 220, reason: 'brightness from config');

      final segs = captured['seg'] as List;
      expect(segs.length, 2, reason: 'one seg per configured channel');

      final seg0 = segs[0] as Map<String, dynamic>;
      final seg1 = segs[1] as Map<String, dynamic>;
      expect(seg0['id'], 0);
      expect(seg1['id'], 1, reason: 'channel 2 (seg 1) MUST be addressed');

      // #89 INVERTED — this used to pin start/stop to the hardware bus config.
      // Bounds belong to provisioning; the W-track device-targeting helper
      // builds through applyChannelFilter, so it inherits the contract.
      for (final seg in [seg0, seg1]) {
        expect(seg.containsKey('start'), isFalse);
        expect(seg.containsKey('stop'), isFalse);
      }

      // Both segs are explicitly lit (per-seg on:true — channel-2-dark fix).
      expect(seg0['on'], isTrue);
      expect(seg1['on'], isTrue);

      // The template effect/colors are preserved on every channel.
      for (final seg in [seg0, seg1]) {
        expect(seg['fx'], 52);
        expect(seg['sx'], 200);
        expect(seg['ix'], 180);
        expect(seg['pal'], 0);
        final cols = seg['col'] as List;
        expect(cols.length, 2);
        expect(cols[0], [0, 70, 135, 0]); // primary 0xFF004687
        expect(cols[1], [189, 155, 96, 0]); // secondary 0xFFBD9B60
      }

      // Post Fix 3 Part 2 (2026-05-23): shortTeamName prefers the curated
      // teamShortName(teamName) lookup, so "Kansas City Royals" resolves to
      // "Royals Game Day".
      expect(capturedLabel, 'Royals Game Day');
    });

    test(
        'single-channel scope on a two-channel device → the FULL PARTITION: '
        'channel 0 lit with the design, channel 1 excluded as {id, on:false} '
        'and NOT deleted (#89)',
        () async {
      late Map<String, dynamic> captured;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          captured = payload;
          return true;
        },
        config: configFor(),
        participatingChannels: const [0],
        deviceChannels: twoChannels,
      );

      final segs = (captured['seg'] as List).cast<Map>();
      // Both segments still exist — the excluded channel is DARK, not GONE.
      expect(segs.map((s) => s['id']).toList(), equals([0, 1]));
      expect(segs[0]['on'], isTrue);
      expect(segs[0]['fx'], 52);
      expect(segs[1]['on'], isFalse);
      expect(segs[1].keys.toSet(), equals({'id', 'on'}),
          reason: 'exclusion states exclusion and nothing else — the '
              'excluded channel keeps its own look');
      for (final s in segs) {
        expect(s.containsKey('start'), isFalse);
        expect(s.containsKey('stop'), isFalse);
      }
    });

    test(
        'U1 empty-gate: no configured channels → returns false and NEVER '
        'calls applyPayloadWithLabel (matches applySavedDesign — bail when '
        'the device/hardware config is not ready)', () async {
      var applyCalls = 0;
      final ok = await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          applyCalls += 1;
          return true;
        },
        config: configFor(),
        participatingChannels: const [],
        deviceChannels: twoChannels,
      );

      expect(ok, isFalse);
      expect(applyCalls, 0,
          reason: 'an empty channel list means there is nothing to target');
    });

    test(
        'savedDesignPayload overrides the auto-built payload AND is forwarded '
        'verbatim — the picker already channel-filtered it (multi-seg-with-'
        'ids), so re-filtering would flatten a per-channel design',
        () async {
      final custom = <String, dynamic>{
        'on': true,
        'bri': 100,
        'seg': [
          {'id': 0, 'fx': 99, 'col': [[10, 20, 30, 0]]},
          {'id': 1, 'fx': 99, 'col': [[40, 50, 60, 0]]},
        ],
      };
      late Map<String, dynamic> captured;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          captured = payload;
          return true;
        },
        config: configFor(
            savedDesignPayload: custom, savedDesignName: 'Crown Royale'),
        participatingChannels: const [0, 1],
        deviceChannels: twoChannels,
      );
      expect(captured, same(custom),
          reason: 'must forward the savedDesignPayload object verbatim, NOT '
              'a re-filtered dict — the picker owns its per-channel shape');
    });

    test('clamps brightness to 0-255 — caller is shielded from bad config',
        () async {
      late Map<String, dynamic> captured;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          captured = payload;
          return true;
        },
        config: configFor(brightness: 999),
        participatingChannels: const [0, 1],
        deviceChannels: twoChannels,
      );
      expect(captured['bri'], 255);
    });

    test('returns false when the chokepoint returns false (device unreachable)',
        () async {
      final ok = await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          return false;
        },
        config: configFor(),
        participatingChannels: const [0, 1],
        deviceChannels: twoChannels,
      );
      expect(ok, isFalse);
    });

    test(
        'label hint composes to "Royals Game Day" regardless of slug '
        'shape — the curated teamShortName lookup against teamName is '
        'the primary resolution path post Fix 3 Part 2. Hyphenated '
        'slugs (legacy doc format) and underscore slugs (production '
        'kTeamColors format) both produce the same compact label.',
        () async {
      String? capturedLabel;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          capturedLabel = labelHint;
          return true;
        },
        config: configFor(
            teamSlug: 'kansas-city-royals', teamName: 'Kansas City Royals'),
        participatingChannels: const [0, 1],
        deviceChannels: twoChannels,
      );
      expect(capturedLabel, 'Royals Game Day');
    });
  });
}
