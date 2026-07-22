// Tests for Bundle 3b.3c — Game Day's empty-participation skip-apply.
//
// After Bundle 3b.3c removes the inline per-channel seg-building, the
// payload shape that GameDayAutopilotService produces changes:
//   • participating == null  → seg: [{...}]      (1 entry, no id, has fx)
//   • participating == []    → seg: []            (skip-apply gate)
//   • participating == [0,1] → seg: [{...}]       (1 entry, no id, has fx)
//                              chokepoint expands at applyJson layer.
//
// The "explicit empty" case (participating == []) is the regression
// these tests prevent: rule 2 in `expandForParticipation` passes empty
// participation THROUGH (it never emits an empty seg array), so the
// skip-apply MUST happen at the caller. _applyDesign is the active gate
// — empty seg array → onApplyPayload is NOT invoked.
//
// Two assertion surfaces:
//   1. selectDesign(...).wledPayload — public, tests the new shape.
//   2. applyDesignForTest(...) (@visibleForTesting) — tests the skip
//      behavior of _applyDesign itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';

void main() {
  late GameDayAutopilotService svc;

  setUp(() {
    svc = GameDayAutopilotService(
      espnApi: EspnApiService(),
      scheduleService: GameScheduleService(),
    );
  });

  tearDown(() {
    svc.dispose();
  });

  group('Bundle 3b.3c — Game Day payload shape after seg-building removal',
      () {
    test(
        'participating == null → selectDesign emits single-seg, no id, '
        'has fx (chokepoint-expandable shape)', () {
      svc.onResolveParticipatingChannels = (_) => null;
      final design = svc.selectDesign(
        _baseConfig(),
        preferredStyles: const ['static'],
      );
      final seg = design.wledPayload['seg'] as List;
      expect(seg, hasLength(1));
      final entry = seg.first as Map;
      expect(entry.containsKey('id'), isFalse,
          reason: 'no id → chokepoint rule 7 will expand');
      expect(entry.containsKey('fx'), isTrue,
          reason: 'has fx → broadcast intent');
    });

    test(
        'participating == [] → selectDesign emits seg: [] (skip-apply '
        'gate handed off to _applyDesign)', () {
      svc.onResolveParticipatingChannels = (_) => const <int>[];
      final design = svc.selectDesign(
        _baseConfig(),
        preferredStyles: const ['static'],
      );
      final seg = design.wledPayload['seg'] as List;
      expect(seg, isEmpty,
          reason: 'explicit empty → seg: [] so _applyDesign skips');
    });

    test(
        'participating == [0, 1] → selectDesign emits single-seg, no id, '
        'has fx (chokepoint will expand — no inline multi-seg anymore)',
        () {
      svc.onResolveParticipatingChannels = (_) => const [0, 1];
      final design = svc.selectDesign(
        _baseConfig(),
        preferredStyles: const ['static'],
      );
      final seg = design.wledPayload['seg'] as List;
      expect(seg, hasLength(1),
          reason: 'Bundle 3b.3c removed inline per-channel building; '
              'expansion to 2 segs happens at the chokepoint, not here');
      final entry = seg.first as Map;
      expect(entry.containsKey('id'), isFalse);
      expect(entry.containsKey('fx'), isTrue);
    });

    test(
        'participating == [0, 1] → fallback branch (no preferredStyles) '
        'also emits single-seg-no-id', () {
      svc.onResolveParticipatingChannels = (_) => const [0, 1];
      final design = svc.selectDesign(
        _baseConfig(),
        preferredStyles: const [],
      );
      final seg = design.wledPayload['seg'] as List;
      expect(seg, hasLength(1));
      final entry = seg.first as Map;
      expect(entry.containsKey('id'), isFalse);
      expect(entry['fx'], equals(0),
          reason: 'fallback uses fx=0 (Solid)');
    });
  });

  group('Bundle 3b.3c — _applyDesign empty-seg skip-apply (ACTIVE gate)',
      () {
    late List<Map<String, dynamic>> applyCalls;

    setUp(() {
      applyCalls = [];
      svc.onApplyPayload = (payload) =>
          applyCalls.add(Map<String, dynamic>.from(payload));
    });

    test(
        'design with seg: [] → onApplyPayload is NOT called (the active '
        'gate Bundle 3b.3c relies on)', () {
      final design = DesignSelection(
        mode: AutopilotDesignMode.fallback,
        designName: 'Empty',
        effectId: 0,
        speed: 128,
        intensity: 128,
        brightness: 200,
        colors: const [
          [0, 0, 0]
        ],
        wledPayload: const {'on': true, 'bri': 200, 'seg': <dynamic>[]},
      );
      svc.applyDesignForTest(design);
      expect(applyCalls, isEmpty,
          reason: 'empty seg array MUST be filtered at _applyDesign — '
              'otherwise the empty payload posts unfiltered to seg 0');
    });

    test(
        'design with seg: [{fx:0,...}] → onApplyPayload IS called with '
        'the payload (non-empty path unchanged)', () {
      final payload = <String, dynamic>{
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': 0,
            'sx': 128,
            'ix': 128,
            'pal': 0,
            'col': [
              [255, 0, 0, 0]
            ],
          },
        ],
      };
      final design = DesignSelection(
        mode: AutopilotDesignMode.fallback,
        designName: 'Solid Red',
        effectId: 0,
        speed: 128,
        intensity: 128,
        brightness: 200,
        colors: const [
          [255, 0, 0]
        ],
        wledPayload: payload,
      );
      svc.applyDesignForTest(design);
      expect(applyCalls, hasLength(1));
      expect(applyCalls.first['seg'], hasLength(1));
    });
  });
}

GameDayAutopilotConfig _baseConfig() {
  final now = DateTime.utc(2026, 5, 21);
  return GameDayAutopilotConfig(
    teamSlug: 'mlb_royals',
    teamName: 'Kansas City Royals',
    espnTeamId: '7',
    sport: SportType.mlb,
    primaryColorValue: 0xFF004687,
    secondaryColorValue: 0xFFBD9B60,
    brightness: 200,
    createdAt: now,
    updatedAt: now,
  );
}
