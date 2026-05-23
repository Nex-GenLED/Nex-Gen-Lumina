// Tests for [applyGameDayConfigToDevice] — the shared payload builder
// + apply path used by both Path 1's _activateNow and Path 2's "Light
// it Up Now". Verifies the basic payload shape, the
// savedDesignPayload override precedence, and the label hint format.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/game_day/game_day_apply.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

void main() {
  group('applyGameDayConfigToDevice', () {
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
        'sends a basic payload built from the config when savedDesignPayload '
        'is null', () async {
      late Map<String, dynamic> captured;
      String? capturedLabel;
      final ok = await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint, updateExplorePreview = true}) async {
          captured = payload;
          capturedLabel = labelHint;
          return true;
        },
        config: configFor(),
      );

      expect(ok, isTrue);
      expect(captured['on'], isTrue);
      expect(captured['bri'], 220, reason: 'brightness from config');
      expect(captured['seg'], isA<List>());
      final seg = (captured['seg'] as List).first as Map<String, dynamic>;
      expect(seg['fx'], 52);
      expect(seg['sx'], 200);
      expect(seg['ix'], 180);
      expect(seg['pal'], 0);
      final cols = seg['col'] as List;
      expect(cols.length, 2);
      // Primary 0xFF004687 → r=0, g=70, b=135 ; alpha never sent
      expect(cols[0], [0, 70, 135, 0]);
      // Secondary 0xFFBD9B60 → r=189, g=155, b=96
      expect(cols[1], [189, 155, 96, 0]);
      // Post Fix 3 Part 2 (2026-05-23): shortTeamName now prefers
      // teamShortName(teamName) — the curated short-name lookup — so a
      // production "Kansas City Royals" config resolves to "Royals
      // Game Day" instead of the pre-fix "Mlb_royals Game Day" leak.
      // The underscore + league prefix that used to surface in Now
      // Playing is gone.
      expect(capturedLabel, 'Royals Game Day');
    });

    test(
        'savedDesignPayload overrides the auto-built basic payload — the '
        'user\'s named design wins (same precedence as Path 1 _activateNow)',
        () async {
      final custom = <String, dynamic>{
        'on': true,
        'bri': 100,
        'seg': [
          {
            'fx': 99,
            'palette_id': 42,
            'meta': 'user-custom-design',
          }
        ],
      };
      late Map<String, dynamic> captured;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint, updateExplorePreview = true}) async {
          captured = payload;
          return true;
        },
        config: configFor(savedDesignPayload: custom, savedDesignName: 'Crown Royale'),
      );
      expect(captured, same(custom),
          reason: 'must forward the savedDesignPayload object verbatim, '
              'NOT a merged dict — the chokepoint owns participation');
    });

    test('clamps brightness to 0-255 — caller is shielded from bad config',
        () async {
      late Map<String, dynamic> captured;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint, updateExplorePreview = true}) async {
          captured = payload;
          return true;
        },
        config: configFor(brightness: 999),
      );
      expect(captured['bri'], 255);
    });

    test('returns false when the chokepoint returns false (device unreachable)',
        () async {
      final ok = await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint, updateExplorePreview = true}) async {
          return false;
        },
        config: configFor(),
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
        applyPayloadWithLabel: (payload, {required labelHint, updateExplorePreview = true}) async {
          capturedLabel = labelHint;
          return true;
        },
        config: configFor(teamSlug: 'kansas-city-royals', teamName: 'Kansas City Royals'),
      );
      expect(capturedLabel, 'Royals Game Day');
    });
  });
}
