// THE MULTI-CHANNEL SEGMENT CONTRACT — what each app path sends to a
// three-bus controller, executed rather than read.
//
// Field report 2026-10-02: on a multi-channel install a Game Day look does not
// run the same on every channel. The server's start payload for the reported
// 3-bus controller carried identical fx/sx/ix/col per segment, so the first
// question is what every OTHER path sends, and whether any of them differ
// per channel. This file drives the real builders for a 162 / 128 / 100 px
// controller and pins the answer:
//
//   1. every participating segment carries the SAME look (no per-channel
//      offsets, reversal, mirroring, grouping or palette differences);
//   2. the app wire STATES pal, grp, spc, frz:false and three colour slots on
//      every participating segment (what the server start payload omits —
//      see audit/MULTICHANNEL_GAMEDAY_AUDIT_2026-10-02.md §1 and §4);
//   3. no app path writes geometry (start/stop/rev/mi/of — #76).
//
// So whatever a customer sees differ between channels is NOT a parameter the
// app sends differently; it is the controller rendering one effect per
// segment over three different lengths (the audit's §2), or a per-segment
// field the server path leaves inherited.
//
// Synthetic colours and documentation-range addresses only.

import 'dart:ui' show Color;

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_background_worker.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/team_design_catalog.dart';
import 'package:nexgen_command/features/game_day/game_day_apply.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// The reported layout: three buses of 162, 128 and 100 pixels, one segment
/// per bus (channel ids 0, 1, 2). Pixel counts only; nothing identifies a
/// site.
const List<DeviceChannel> kThreeBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 162, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 162, stop: 290, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 290, stop: 390, gpioPin: 16),
];
const List<int> kAllThree = [0, 1, 2];

const _primary = [255, 0, 0, 0];
const _secondary = [0, 0, 255, 0];
const _black = [0, 0, 0, 0];

/// What the LAN repository does to a payload before it reaches the wire
/// (`WledService.applyJson`: normalize, then participation expansion). The
/// relay repository runs the same two steps.
Map<String, dynamic> wire(Map<String, dynamic> payload, [List<int>? participating]) =>
    expandForParticipation(normalizeWledPayload(payload), participating);

List<Map<String, dynamic>> segsOf(Map<String, dynamic> payload) =>
    (payload['seg'] as List).map((s) => Map<String, dynamic>.from(s as Map)).toList();

List<Map<String, dynamic>> litSegs(Map<String, dynamic> payload) =>
    segsOf(payload).where((s) => s['on'] == true).toList();

/// Contract 1 — every lit segment carries the same look.
void expectIdenticalLook(Map<String, dynamic> payload, {String? reason}) {
  final lit = litSegs(payload);
  expect(lit, isNotEmpty, reason: reason);
  Map<String, dynamic> look(Map<String, dynamic> s) =>
      Map<String, dynamic>.from(s)..remove('id');
  final first = look(lit.first);
  for (final s in lit.skip(1)) {
    expect(look(s), equals(first),
        reason: '${reason ?? ''} segment ${s['id']} differs from ${lit.first['id']}');
  }
}

/// Contract 2 — the look is STATED, not inherited.
void expectStatedLook(Map<String, dynamic> payload, {String? reason}) {
  for (final s in litSegs(payload)) {
    for (final key in ['fx', 'sx', 'ix', 'pal', 'grp', 'spc', 'col']) {
      expect(s.containsKey(key), isTrue,
          reason: '${reason ?? ''} segment ${s['id']} must state $key');
    }
    expect(s['frz'], isFalse, reason: '${reason ?? ''} frz cleared on the wire');
    expect((s['col'] as List).length, 3,
        reason: '${reason ?? ''} all three colour slots overwritten');
  }
}

/// Contract 3 — no geometry (#76).
void expectNoGeometry(Map<String, dynamic> payload, {String? reason}) {
  for (final s in segsOf(payload)) {
    for (final key in ['start', 'stop', 'rev', 'mi', 'of']) {
      expect(s.containsKey(key), isFalse,
          reason: '${reason ?? ''} segment ${s['id']} must not state $key');
    }
  }
}

void expectFullPartition(Map<String, dynamic> payload) {
  expect(segsOf(payload).map((s) => s['id']).toList(), kAllThree,
      reason: 'every device channel named exactly once, in device order');
}

GameDayAutopilotConfig _config({int effectId = 52, int speed = 160, int intensity = 128}) {
  final created = DateTime.utc(2026, 10, 2);
  return GameDayAutopilotConfig(
    teamSlug: 'team-a',
    teamName: 'Team A',
    espnTeamId: '0',
    sport: SportType.nfl,
    primaryColorValue: 0xFFFF0000,
    secondaryColorValue: 0xFF0000FF,
    effectId: effectId,
    speed: speed,
    intensity: intensity,
    brightness: 200,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  group('Game Day — Light it Up Now / Path 1 activate (game_day_apply.dart)', () {
    test('three identical, fully stated segments; the exact array', () async {
      late Map<String, dynamic> sent;
      final ok = await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          sent = payload;
          return true;
        },
        config: _config(),
        participatingChannels: kAllThree,
        deviceChannels: kThreeBuses,
      );
      expect(ok, isTrue);
      final w = wire(sent, null);
      expectFullPartition(w);
      expectIdenticalLook(w);
      expectStatedLook(w);
      expectNoGeometry(w);
      expect(segsOf(w), [
        for (final id in kAllThree)
          {
            'id': id,
            'grp': 1,
            'spc': 0,
            'fx': 52,
            'sx': 160,
            'ix': 128,
            'pal': 0,
            'col': [_primary, _secondary, _black],
            'on': true,
            // +110 completes the segment at the wire: its own brightness is
            // stated (kSegDefaultBri), not inherited. The server start payload
            // states none of pal / grp / spc / bri / frz / col[2].
            'bri': 255,
            'frz': false,
          },
      ]);
    });

    test('a channel left out goes {id, on:false} (plus the wire freeze clear) '
        'and nothing else', () async {
      late Map<String, dynamic> sent;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          sent = payload;
          return true;
        },
        config: _config(),
        participatingChannels: const [0, 2],
        deviceChannels: kThreeBuses,
      );
      final w = wire(sent, null);
      expectFullPartition(w);
      expect(segsOf(w)[1], {'id': 1, 'on': false, 'frz': false});
      expectIdenticalLook(w);
    });
  });

  group('Game Day — foreground engine (GameDayAutopilotService._buildWledPayload)', () {
    // The engine emits the single-seg-no-id "broadcast intent" shape
    // (game_day_autopilot_service.dart, _buildWledPayload) and lets the
    // chokepoint's Rule 7 fan it out per participating channel. The shape is
    // replicated here field for field; the fan-out and normalisation are the
    // real functions.
    test('Rule 7 fans one template across the participating set', () {
      final fx = 52;
      final engineShape = {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': fx,
            'sx': 160,
            'ix': 128,
            'pal': WledEffectsCatalog.setColorsPaletteFor(fx),
            'col': [_primary, _secondary],
          },
        ],
      };
      final w = wire(engineShape, kAllThree);
      expect(segsOf(w).map((s) => s['id']).toList(), kAllThree);
      expectIdenticalLook(w);
      expectStatedLook(w);
      expectNoGeometry(w);
    });
  });

  group('Game Day — background worker + TeamDesignCatalog (all six designs)', () {
    final catalog = TeamDesignCatalog.build(
      teamName: 'Team A',
      primary: const Color(0xFFFF0000),
      secondary: const Color(0xFF0000FF),
      brightness: 200,
    );

    for (final design in catalog) {
      test('${design.name}: fx ${design.effectId} identical on all three', () {
        final w = GameDayAutopilotBackgroundWorker.expandForChannels(
          normalizeWledPayload(Map<String, dynamic>.from(design.wledPayload)),
          kAllThree,
        );
        expect(segsOf(w).map((s) => s['id']).toList(), kAllThree);
        expectIdenticalLook(w, reason: design.name);
        expectStatedLook(w, reason: design.name);
        expectNoGeometry(w, reason: design.name);
        expect(segsOf(w).first['fx'], design.effectId);
        expect(segsOf(w).first['grp'], design.colorGroupSize,
            reason: 'the Stripe design IS its grouping (#88)');
      });
    }

    test('the catalog mixes length-sensitive and length-free effects', () {
      // Documented in the audit (§2): Running Dual (52) anchors a reverse wave
      // on each segment's END and maps the palette positionally; Chase (28)
      // scales dot position AND size with the segment length; Solid (0) and
      // Fade (12) are length-free; Breathe (2) is time-only. Stripe (0 with
      // grp 3) restarts its bands at every segment origin.
      expect(catalog.map((d) => d.effectId).toList(), [52, 0, 28, 2, 12, 0]);
    });
  });

  group('Game Day — a dated-night lease preset (CalendarEntryLeaseManager)', () {
    // The lease's fallback look (_synthesizeWledPayload, no carried payload)
    // is one Solid segment with no id. savePreset normalises it and expands
    // it over the cached participating set; with NO cached set it falls back
    // to segment 0 and the psave captures the other two segments AS THEY ARE.
    final leaseShape = {
      'on': true,
      'bri': 255,
      'ib': true,
      'seg': [
        {
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'col': [_primary],
        },
      ],
    };

    // FINDING (#154). The lease manager never channel-filters this shape, and
    // the preset-save path only ADDS `{id, frz:false}` markers when the caller
    // supplied no segments at all — it does not fan a single id-less segment
    // out. So whatever the cache holds, the saved preset states the look on
    // the main segment only; WLED applies an id-less seg entry to `mainseg`,
    // and the psave captures channels 2 and 3 exactly as they were at arming
    // time (the "ambient capture" of the 10-01 lease prep). On a three-bus
    // house a dated-night lease lights channel 1 in the team colour and
    // leaves the other two on whatever came before.
    for (final cache in [null, kAllThree]) {
      test('cache ${cache ?? 'unknown'}: ONE id-less segment — channels 2 and '
          '3 are captured as they were, not written', () {
        final saved =
            ensurePsaveClearsFreeze(normalizeWledPayload(leaseShape), cache);
        final segs = segsOf(saved);
        expect(segs.where((s) => s.containsKey('fx')).length, 1,
            reason: 'the look is stated once');
        expect(segs.single.containsKey('id'), isFalse,
            reason: 'no id: WLED applies it to the main segment');
        expectNoGeometry(saved);
      });
    }
  });

  group('Celebrations — every stage, fanned over all three channels', () {
    final team = TeamColors(
      primary: Colors.red,
      secondary: Colors.blue,
      teamName: 'Team A',
      sport: SportType.nfl,
      espnTeamId: '0',
    );

    for (final event in AlertEventType.values) {
      test('${event.name}: each stage identical and stated on all three', () {
        final steps = AlertTriggerService.buildAnimationSteps(event, team);
        if (steps.isEmpty) {
          // "Phase 2 — no animation yet" in the trigger service. Only this one.
          expect(event, AlertEventType.turnover);
          return;
        }
        for (var i = 0; i < steps.length; i++) {
          // WledCelebrationDelivery.play: applyChannelFilter, then applyJson.
          final w = wire(applyChannelFilter(steps[i].payload, kAllThree, kThreeBuses), null);
          expectFullPartition(w);
          expectIdenticalLook(w, reason: '${event.name} stage $i');
          expectStatedLook(w, reason: '${event.name} stage $i');
          expectNoGeometry(w, reason: '${event.name} stage $i');
        }
      });
    }
  });

  group('Explore Patterns — the tuner (buildSelectorPayload + applyChannelFilter)', () {
    test('Static Blocks: three segments, each its own thirds (fx 83 pal 5)', () {
      final solid = solidLayoutFields(
          layout: SolidLayout.blocks, colorCount: 3, ledsPerColor: 1);
      final payload = buildSelectorPayload(SelectorState(
        effectId: solid.fx,
        speed: solid.sx ?? 128,
        intensity: solid.ix ?? 128,
        grouping: solid.grp,
        spacing: 0,
        colors: const [_primary, [255, 255, 255, 0], _secondary],
        paletteOverride: solid.pal,
      ));
      final w = wire(applyChannelFilter(payload, kAllThree, kThreeBuses), null);
      expectFullPartition(w);
      expectIdenticalLook(w);
      expectStatedLook(w);
      expectNoGeometry(w);
      expect(segsOf(w), [
        for (final id in kAllThree)
          {
            'id': id,
            'fx': 83,
            'sx': 128,
            'ix': 128,
            'pal': 5,
            'grp': 1,
            'spc': 0,
            'col': [_primary, [255, 255, 255, 0], _secondary],
            'on': true,
            'bri': 255,
            'frz': false,
          },
      ]);
    });

    test('Chase from the tuner is the same template on every channel', () {
      final payload = buildSelectorPayload(const SelectorState(
        effectId: 28,
        speed: 180,
        intensity: 180,
        colors: [_primary, _secondary],
      ));
      final w = wire(applyChannelFilter(payload, kAllThree, kThreeBuses), null);
      expectIdenticalLook(w);
      expectStatedLook(w);
      expect(segsOf(w).first['fx'], 28);
    });
  });

  group('Neighborhood Sync — the engine\'s single-seg broadcast', () {
    // neighborhood_sync_engine.dart builds `{fx, sx, ix, pal, grp, spc, col}`
    // with no id and lets the chokepoint's Rule 7 fan it out.
    test('Rule 7 fans the member pattern across the participating set', () {
      final shape = {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': 52,
            'sx': 160,
            'ix': 128,
            'pal': 5,
            'grp': 1,
            'spc': 0,
            'col': [_primary, _secondary, _black],
          },
        ],
      };
      final w = wire(shape, kAllThree);
      expect(segsOf(w).map((s) => s['id']).toList(), kAllThree);
      expectIdenticalLook(w);
      expectStatedLook(w);
      expectNoGeometry(w);
    });
  });
}
