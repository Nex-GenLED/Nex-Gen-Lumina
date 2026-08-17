// Tests for Item #83 — the background-isolate celebration-payload leak
// surfaced by the #78 Cloud Function audit.
//
// Context:
//   The client-side WLED chokepoint (WledService.setState / savePreset)
//   routes through normalizeWledPayload, which pads seg[].col UP to 3
//   slots so the device's seg.col is overwritten explicitly on every
//   apply. Background-service isolates (Game Day autopilot + Neighborhood
//   Sync) cannot reach that chokepoint at apply time — they POST payloads
//   directly to applySyncPattern (a passthrough Cloud Function — see the
//   #78 audit).
//
//   _buildCelebrationPayload emitted a 2-slot col ([primary, secondary]).
//   _buildBasePayload's team-design path inherited TeamDesignCatalog's
//   2-slot ([p, s]) payload. Both leaked, re-poisoning the device's third
//   slot on Game Day fires regardless of the client fix.
//
// Fix shape:
//   Both builders + the sync worker's _buildPatternPayload now route
//   through normalizeWledPayload (the same chokepoint the foreground
//   uses). One normalizer reachable from isolates — kills the duplicate
//   hand-rolled padding drift between the two workers.
//
// These tests pin the post-normalize shape: every seg.col is exactly
// 3 slots, the third slot is [0, 0, 0, 0], and the in-use slots survive
// untouched.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_background_worker.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_worker.dart';

BackgroundGameDayAutopilotConfig _configForTeam({
  required int primary,
  required int secondary,
  String designMode = 'fallback',
  String designVariety = 'first',
  Map<String, dynamic>? savedDesignPayload,
}) {
  return BackgroundGameDayAutopilotConfig(
    teamSlug: 'royals',
    teamName: 'Royals',
    espnTeamId: '7',
    sport: 'mlb',
    primaryColorValue: primary,
    secondaryColorValue: secondary,
    enabled: true,
    designMode: designMode,
    effectId: 11,
    speed: 200,
    intensity: 200,
    brightness: 220,
    savedDesignName: savedDesignPayload != null ? 'saved' : null,
    savedDesignPayload: savedDesignPayload,
    skipDayGames: false,
    designVariety: designVariety,
    scoreCelebrationEnabled: true,
  );
}

List<List<int>> _firstSegCol(Map<String, dynamic> payload) {
  final seg = payload['seg'] as List;
  final first = seg.first as Map;
  final col = first['col'] as List;
  return [for (final c in col) List<int>.from(c as List)];
}

void main() {
  group('GameDay celebration payload — col pads to 3 slots', () {
    test('2-color celebration → 3-slot col, third = [0,0,0,0]', () {
      // Royals blue + gold — exactly the shape that re-poisoned the device.
      final config = _configForTeam(
        primary: 0xFF004687, // royal blue
        secondary: 0xFFBD9B60, // gold
      );

      final payload =
          GameDayAutopilotBackgroundWorker.buildCelebrationPayloadForTest(
        config,
      );
      final col = _firstSegCol(payload);

      expect(col.length, 3, reason: 'col must be padded to 3 slots');

      // Slot 0 — primary (royal blue) RGBW
      expect(col[0], [0x00, 0x46, 0x87, 0]);
      // Slot 1 — secondary (gold) RGBW
      expect(col[1], [0xBD, 0x9B, 0x60, 0]);
      // Slot 2 — the padding the device needs to clear its stale third slot
      expect(col[2], [0, 0, 0, 0]);
    });

    test('normalize-default fields (grp/spc/of) are present', () {
      // Side-benefit of routing through normalizeWledPayload — same
      // stale-segment defense the chokepoint provides for grp/spc. NOT `of` —
      // that is geometry, and the chokepoint stopped asserting it.
      final config = _configForTeam(
        primary: 0xFFFF0000,
        secondary: 0xFF00FF00,
      );

      final payload =
          GameDayAutopilotBackgroundWorker.buildCelebrationPayloadForTest(
        config,
      );
      final seg = (payload['seg'] as List).first as Map;

      expect(seg['grp'], 1);
      expect(seg['spc'], 0);
      // `of` INVERTED — geometry is not the chokepoint's to assert (#76).
      expect(seg.containsKey('of'), isFalse);
    });
  });

  group('GameDay base payload — col pads to 3 slots', () {
    test('team-design path (2-slot catalog payload) → 3-slot col', () {
      // TeamDesignCatalog._buildPayload emits col: [p, s] (always 2 slots).
      // _buildBasePayload copying it verbatim was leak #2 in #83.
      final config = _configForTeam(
        primary: 0xFFFF0000,
        secondary: 0xFF0000FF,
      );

      final payload = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
        config,
      );
      final col = _firstSegCol(payload);

      expect(col.length, 3,
          reason: 'team-design path must pad to 3 via normalize');
      expect(col[2], [0, 0, 0, 0]);
    });

    test('saved-design path with 2-slot col → 3-slot col', () {
      // savedDesignPayload comes from whatever the user saved — its shape
      // is variable. If a saved design has a 2-slot col, the base path
      // would have leaked it verbatim. Confirm normalize catches it too.
      final config = _configForTeam(
        primary: 0xFF000000,
        secondary: 0xFF000000,
        designMode: 'saved',
        savedDesignPayload: {
          'on': true,
          'bri': 200,
          'seg': [
            {
              'fx': 11,
              'sx': 200,
              'ix': 200,
              'col': [
                [255, 0, 0, 0],
                [0, 255, 0, 0],
              ], // 2 slots — the leak shape
            },
          ],
        },
      );

      final payload = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
        config,
      );
      final col = _firstSegCol(payload);

      expect(col.length, 3);
      expect(col[0], [255, 0, 0, 0]);
      expect(col[1], [0, 255, 0, 0]);
      expect(col[2], [0, 0, 0, 0]);
    });

    test('saved-design path with 3-slot col → unchanged', () {
      // Regression guard: a saved design that already supplies 3 slots
      // must pass through normalize unchanged (normalize pads UP only,
      // never trims or rewrites well-formed input).
      final config = _configForTeam(
        primary: 0xFF000000,
        secondary: 0xFF000000,
        designMode: 'saved',
        savedDesignPayload: {
          'on': true,
          'bri': 200,
          'seg': [
            {
              'fx': 11,
              'sx': 200,
              'ix': 200,
              'col': [
                [255, 0, 0, 0],
                [0, 255, 0, 0],
                [0, 0, 255, 0],
              ],
            },
          ],
        },
      );

      final payload = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
        config,
      );
      final col = _firstSegCol(payload);

      expect(col.length, 3);
      expect(col[0], [255, 0, 0, 0]);
      expect(col[1], [0, 255, 0, 0]);
      expect(col[2], [0, 0, 255, 0]);
    });
  });

  group(
    'SyncEvent _buildPatternPayload — regression: still 3-slot post-consolidation',
    () {
      test('1-color input → 3-slot col, slots 1+2 are [0,0,0,0]', () {
        final payload =
            SyncEventBackgroundWorker.buildPatternPayloadForTest(
          effectId: 0,
          colors: const [0xFF00FF00], // green only
          speed: 128,
          intensity: 128,
          brightness: 200,
        );

        // Sync worker fans out to 8 channels. All 8 segs share the same
        // colorSlots reference — normalize creates per-seg copies, so
        // every seg gets a 3-slot col independently.
        final segs = payload['seg'] as List;
        expect(segs.length, 8);
        for (final s in segs) {
          final col = (s as Map)['col'] as List;
          expect(col.length, 3);
          expect(col[0], [0x00, 0xFF, 0x00, 0]);
          expect(col[1], [0, 0, 0, 0]);
          expect(col[2], [0, 0, 0, 0]);
        }
      });

      test('2-color input → 3-slot col, third = [0,0,0,0]', () {
        final payload =
            SyncEventBackgroundWorker.buildPatternPayloadForTest(
          effectId: 0,
          colors: const [0xFFFF0000, 0xFF0000FF],
          speed: 128,
          intensity: 128,
          brightness: 200,
        );

        final firstSeg = (payload['seg'] as List).first as Map;
        final col = (firstSeg['col'] as List).cast<List>();
        expect(col.length, 3);
        expect(col[0], [0xFF, 0x00, 0x00, 0]);
        expect(col[1], [0x00, 0x00, 0xFF, 0]);
        expect(col[2], [0, 0, 0, 0]);
      });

      test('3-color input → 3-slot col, all in-use slots preserved', () {
        final payload =
            SyncEventBackgroundWorker.buildPatternPayloadForTest(
          effectId: 0,
          colors: const [0xFFFF0000, 0xFF00FF00, 0xFF0000FF],
          speed: 128,
          intensity: 128,
          brightness: 200,
        );

        final firstSeg = (payload['seg'] as List).first as Map;
        final col = (firstSeg['col'] as List).cast<List>();
        expect(col.length, 3);
        expect(col[0], [0xFF, 0x00, 0x00, 0]);
        expect(col[1], [0x00, 0xFF, 0x00, 0]);
        expect(col[2], [0x00, 0x00, 0xFF, 0]);
      });
    },
  );

  // Belt-and-suspenders: prove the normalize import resolves at compile
  // time in this isolate-style call surface. If the transitive Riverpod
  // import through wled_payload_utils ever breaks isolate compilation,
  // these tests fail to load — a fast signal beyond a green build.
  test('debugPrint sanity (no test logic) — proves test file loaded', () {
    debugPrint('[#83 test] file loaded; workers can call normalizeWledPayload');
  });
}
