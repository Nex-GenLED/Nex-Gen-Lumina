// Tests for the sports-alert score-celebration CHANNEL TARGETING fix.
//
// Bug: every animation payload hardcoded `'id': 0`, so expandForParticipation
// Rule 5 passed it through to seg 0 = channel 1 only — channel 2 stayed dark,
// even with a warm participation cache. Fix: build NO-ID template payloads and
// route each through applyChannelFilter across all configured channels.
//
// These tests verify (a) the animation CONTENT is unchanged (effects / speeds /
// colors / timing), (b) the no-id templates fan out across BOTH seg 0 and seg 1
// via applyChannelFilter independent of the participation cache, and (c) the
// bus -> channel derivation used to resolve per-controller channels.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

void main() {
  const team = TeamColors(
    primary: Color(0xFFE31837), // Chiefs red
    secondary: Color(0xFFFFB81C), // gold
    teamName: 'Test Team',
    sport: SportType.nfl,
    espnTeamId: '12',
  );

  // 2-channel device (matches the hardware probe on 192.168.1.250:
  // seg 0 = 0-128 Front Roofline, seg 1 = 128-188 Side Accent).
  const twoChannels = [
    DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
    DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 188, gpioPin: 1),
  ];

  group('buildAnimationSteps — content unchanged + no hardcoded id', () {
    test('touchdown: Strobe fx2 (2s) -> Wipe fx9 (5s) -> Running fx63 (8s), '
        'no seg carries an id', () {
      final steps =
          AlertTriggerService.buildAnimationSteps(AlertEventType.touchdown, team);
      expect(steps.length, 3);

      expect(steps[0].hold, const Duration(seconds: 2));
      expect(steps[1].hold, const Duration(seconds: 5));
      expect(steps[2].hold, const Duration(seconds: 8));

      final fx = steps.map((s) => (s.payload['seg'] as List).first['fx']).toList();
      expect(fx, [2, 9, 63]);
      expect(steps[0].payload['bri'], 255);
      expect(steps[0].payload['on'], true);

      // The channel-2 fix: NO step's seg may carry a hardcoded 'id'.
      for (final step in steps) {
        final seg = (step.payload['seg'] as List).first as Map;
        expect(seg.containsKey('id'), isFalse,
            reason: 'templates must be id-less so applyChannelFilter fans out');
      }
    });

    test('soccerGoal: fx28 -> fx23 -> fx63 -> fx2, 20s total, all id-less', () {
      final steps = AlertTriggerService.buildAnimationSteps(
          AlertEventType.soccerGoal, team);
      expect(steps.length, 4);
      expect(steps.map((s) => (s.payload['seg'] as List).first['fx']).toList(),
          [28, 23, 63, 2]);
      final total = steps.fold<int>(0, (sum, s) => sum + s.hold.inSeconds);
      expect(total, 20);
      for (final step in steps) {
        expect((step.payload['seg'] as List).first.containsKey('id'), isFalse);
      }
    });

    test('every defined event yields id-less templates (regression sweep)', () {
      for (final type in AlertEventType.values) {
        final steps = AlertTriggerService.buildAnimationSteps(type, team);
        for (final step in steps) {
          for (final seg in step.payload['seg'] as List) {
            expect((seg as Map).containsKey('id'), isFalse,
                reason: '$type produced a hardcoded seg id');
          }
        }
      }
    });

    test('turnover has no animation (Phase 2)', () {
      expect(
        AlertTriggerService.buildAnimationSteps(AlertEventType.turnover, team),
        isEmpty,
      );
    });
  });

  group('channel fan-out via applyChannelFilter (cache-independent)', () {
    // #89 — the bounds half of this assertion INVERTED. An apply states design,
    // never installation bounds; the per-bus start/stop this used to pin was
    // the same defect class as a [0,0) exclusion, aimed the other way.
    test('2-channel device → celebration addresses BOTH seg 0 AND seg 1, '
        'with NO start/stop + per-seg on:true, content preserved', () {
      final step =
          AlertTriggerService.buildAnimationSteps(AlertEventType.touchdown, team)
              .first;

      final filtered =
          applyChannelFilter(step.payload, const [0, 1], twoChannels);
      final segs = filtered['seg'] as List;
      expect(segs.length, 2, reason: 'one seg per channel');

      final seg0 = segs[0] as Map;
      final seg1 = segs[1] as Map;
      expect(seg0['id'], 0);
      expect(seg1['id'], 1, reason: 'channel 2 (seg 1) MUST be addressed');
      for (final seg in [seg0, seg1]) {
        expect(seg.containsKey('start'), isFalse,
            reason: 'bounds are provisioning\'s — a celebration must not '
                're-bound the installation');
        expect(seg.containsKey('stop'), isFalse);
      }
      expect(seg0['on'], isTrue);
      expect(seg1['on'], isTrue);

      // Content (effect + colors) preserved verbatim on every channel.
      final expectedColors = [
        AlertTriggerService.colorToRgbw(team.primary),
        AlertTriggerService.colorToRgbw(team.secondary),
        [0, 0, 0, 0],
      ];
      for (final seg in [seg0, seg1]) {
        expect(seg['fx'], 2);
        expect(seg['sx'], 240);
        expect(seg['ix'], 255);
        expect(seg['col'], expectedColors);
      }

      // Top-level device fields untouched by the channel filter.
      expect(filtered['on'], true);
      expect(filtered['bri'], 255);
    });

    test('single-channel device → addresses ONLY seg 0', () {
      final step =
          AlertTriggerService.buildAnimationSteps(AlertEventType.safety, team)
              .first;
      final filtered = applyChannelFilter(
          step.payload, const [0], [twoChannels[0]]);
      final segs = filtered['seg'] as List;
      expect(segs.length, 1);
      expect((segs[0] as Map)['id'], 0);
      expect((segs[0] as Map)['fx'], 23);
    });

    test('U1 empty-gate shape: no channels → applyChannelFilter is a no-op '
        '(payload stays a single id-less template; the service skips the '
        'controller before this point)', () {
      final step =
          AlertTriggerService.buildAnimationSteps(AlertEventType.run, team).first;
      final filtered = applyChannelFilter(step.payload, const [], const []);
      // Unchanged: still one seg, still no id — nothing fabricated.
      expect((filtered['seg'] as List).length, 1);
      expect((filtered['seg'] as List).first.containsKey('id'), isFalse);
    });
  });

  group('deviceChannelsFromConfig — per-controller bus derivation', () {
    test('derives one channel per bus with start/stop from the bus range', () {
      const cfg = WledHardwareConfig(
        totalLeds: 188,
        maxPowerMw: 30000,
        buses: [
          WledLedBus(pin: [2], start: 0, len: 128),
          WledLedBus(pin: [1], start: 128, len: 60),
        ],
      );
      final channels = deviceChannelsFromConfig(cfg);
      expect(channels.length, 2);
      expect(channels[0].id, 0);
      expect(channels[0].start, 0);
      expect(channels[0].stop, 128);
      expect(channels[1].id, 1);
      expect(channels[1].start, 128);
      expect(channels[1].stop, 188);
    });

    test('null / empty config → empty list (drives the U1 skip gate)', () {
      expect(deviceChannelsFromConfig(null), isEmpty);
      expect(
        deviceChannelsFromConfig(
          const WledHardwareConfig(totalLeds: 0, maxPowerMw: 0, buses: []),
        ),
        isEmpty,
      );
    });
  });
}
