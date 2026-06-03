// Tests for #29 — background Game Day multi-channel via per-config resolved
// participation (Option A2). The background isolate cannot resolve participation
// (no Riverpod); the resolved set is persisted onto BackgroundGameDayAutopilotConfig
// at schedule time, and the worker expands the payload via expandForChannels:
//   • RAW single-seg-no-id (team-colors / celebration) → applyChannelFilter to
//     the participating set → multi-seg-with-ids, each on:true, NO start/stop
//     (WLED retains install-time ranges).
//   • already multi-seg / id-bearing (saved design) → pass through untouched.
//   • [] → seg:[] (skip-apply).
//   • null → legacy single-seg (lights ch1, NOT dark).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_background_worker.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';

BackgroundGameDayAutopilotConfig _config({
  List<int>? participatingChannelIds,
  String designMode = 'fallback',
  Map<String, dynamic>? savedDesignPayload,
}) {
  return BackgroundGameDayAutopilotConfig(
    teamSlug: 'royals',
    teamName: 'Royals',
    espnTeamId: '7',
    sport: 'mlb',
    primaryColorValue: 0xFFFF0000,
    secondaryColorValue: 0xFF0000FF,
    enabled: true,
    designMode: designMode,
    effectId: 11,
    speed: 200,
    intensity: 200,
    brightness: 220,
    savedDesignName: savedDesignPayload != null ? 'saved' : null,
    savedDesignPayload: savedDesignPayload,
    skipDayGames: false,
    designVariety: 'first',
    scoreCelebrationEnabled: true,
    participatingChannelIds: participatingChannelIds,
  );
}

List<Map> _segs(Map<String, dynamic> payload) =>
    (payload['seg'] as List).cast<Map>();

void main() {
  group('expandForChannels — the #29 discriminator (direct unit)', () {
    final raw = {
      'on': true,
      'bri': 220,
      'seg': [
        {'fx': 11, 'sx': 200, 'ix': 200, 'col': [[255, 0, 0, 0]]},
      ],
    };

    test('RAW single-seg + [0,1] → 2 segs ids 0/1, on:true, NO start/stop',
        () {
      final out = GameDayAutopilotBackgroundWorker.expandForChannels(
          Map<String, dynamic>.from(raw), const [0, 1]);
      final segs = _segs(out);
      expect(segs, hasLength(2));
      expect(segs[0]['id'], 0);
      expect(segs[1]['id'], 1);
      expect(segs[0]['on'], isTrue);
      expect(segs[1]['on'], isTrue);
      // Install-time ranges retained — no start/stop computed in-isolate.
      expect(segs[0].containsKey('start'), isFalse);
      expect(segs[0].containsKey('stop'), isFalse);
      // Template effect preserved on each channel.
      expect(segs[0]['fx'], 11);
      expect(segs[1]['fx'], 11);
    });

    test('non-participating channel NOT lit: [0] → only seg id 0', () {
      final out = GameDayAutopilotBackgroundWorker.expandForChannels(
          Map<String, dynamic>.from(raw), const [0]);
      final segs = _segs(out);
      expect(segs, hasLength(1));
      expect(segs.first['id'], 0);
      expect(segs.any((s) => s['id'] == 1), isFalse,
          reason: 'channel 1 is not in the participating set — must be omitted');
    });

    test('[] (explicit opt-out) → seg:[] (skip-apply signal)', () {
      final out = GameDayAutopilotBackgroundWorker.expandForChannels(
          Map<String, dynamic>.from(raw), const []);
      expect(out['seg'], isEmpty);
    });

    test('null (legacy) → unchanged single-seg-no-id (lights ch1, NOT dark)',
        () {
      final out = GameDayAutopilotBackgroundWorker.expandForChannels(
          Map<String, dynamic>.from(raw), null);
      final segs = _segs(out);
      expect(segs, hasLength(1));
      expect(segs.first.containsKey('id'), isFalse,
          reason: 'legacy raw payload — WLED applies to seg 0');
    });

    test('id-bearing multi-seg (saved design) + [0,1] → passthrough, NOT '
        'flattened', () {
      final prefiltered = {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 0, 0, 0]]}, // ch0 red
          {'id': 1, 'fx': 0, 'col': [[0, 0, 255, 0]]}, // ch1 blue
        ],
      };
      final out = GameDayAutopilotBackgroundWorker.expandForChannels(
          Map<String, dynamic>.from(prefiltered), const [0, 1]);
      final segs = _segs(out);
      expect(segs, hasLength(2));
      expect(segs[0]['col'], equals([[255, 0, 0, 0]]), reason: 'ch0 stays red');
      expect(segs[1]['col'], equals([[0, 0, 255, 0]]),
          reason: 'ch1 stays blue — not templated off seg.first');
    });
  });

  group('buildBasePayloadForTest — team-colors path through #29 expansion', () {
    test('2-channel participant → both channels addressed, 3-slot col each',
        () {
      final payload = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
        _config(participatingChannelIds: const [0, 1]),
      );
      final segs = _segs(payload);
      expect(segs, hasLength(2));
      expect(segs[0]['id'], 0);
      expect(segs[1]['id'], 1);
      expect(segs[0]['on'], isTrue);
      expect(segs[1]['on'], isTrue);
      // #83 col-pad survives the expansion: each channel gets a 3-slot col.
      expect((segs[0]['col'] as List), hasLength(3));
      expect((segs[1]['col'] as List), hasLength(3));
    });

    test('single-channel participant → one seg id 0', () {
      final payload = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
        _config(participatingChannelIds: const [0]),
      );
      final segs = _segs(payload);
      expect(segs, hasLength(1));
      expect(segs.first['id'], 0);
    });

    test('[] participant → seg:[] (worker will skip-apply)', () {
      final payload = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
        _config(participatingChannelIds: const []),
      );
      expect(payload['seg'], isEmpty);
    });

    test('null participant → legacy single-seg (NOT dark, NOT bus-broadcast)',
        () {
      final payload = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
        _config(participatingChannelIds: null),
      );
      final segs = _segs(payload);
      expect(segs, hasLength(1));
      expect(segs.first.containsKey('id'), isFalse);
    });

    test('saved-design (multi-seg-with-ids) + participation → passthrough', () {
      final payload = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
        _config(
          participatingChannelIds: const [0, 1],
          designMode: 'saved',
          savedDesignPayload: {
            'on': true,
            'bri': 200,
            'seg': [
              {'id': 0, 'fx': 11, 'col': [[255, 0, 0, 0]]},
              {'id': 1, 'fx': 11, 'col': [[0, 255, 0, 0]]},
            ],
          },
        ),
      );
      final segs = _segs(payload);
      expect(segs, hasLength(2), reason: 'design segs preserved, not collapsed');
      expect(segs[0]['id'], 0);
      expect(segs[1]['id'], 1);
      // col[0] slot 0 stays the per-channel colour (normalize pads to 3).
      expect((segs[0]['col'] as List).first, equals([255, 0, 0, 0]));
      expect((segs[1]['col'] as List).first, equals([0, 255, 0, 0]));
    });
  });

  group('buildCelebrationPayloadForTest — also participation-aware', () {
    test('2-channel participant → celebration flash on both channels', () {
      final payload =
          GameDayAutopilotBackgroundWorker.buildCelebrationPayloadForTest(
        _config(participatingChannelIds: const [0, 1]),
      );
      final segs = _segs(payload);
      expect(segs, hasLength(2));
      expect(segs[0]['id'], 0);
      expect(segs[1]['id'], 1);
      expect(segs[0]['fx'], 11); // Sparkle preserved per channel
    });
  });
}
