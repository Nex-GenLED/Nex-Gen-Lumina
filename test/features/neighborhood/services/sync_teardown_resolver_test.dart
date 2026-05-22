// Tests for [resolveCurrentMemberState] — the pure decision function
// behind the sync teardown policy.
//
// Locked policy: 1) schedule item → 2) autopilot item → 3) pre-sync
// scene → 4) off. Each tier dominates the ones below. Distributed
// resolution (each member runs this locally), no host signal needed
// beyond the existing isActive:false transition.
//
// Convergence-Phase-1B: this resolver is DORMANT in production. These
// tests lock the decision contract so Phase 2's executor can branch on
// the sealed subtype without re-deriving the priority order.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/pre_sync_scene_snapshot.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_teardown_resolver.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';

void main() {
  group('resolveCurrentMemberState — single-tier', () {
    test('priority 1: active schedule → ApplySchedule', () {
      final schedule = _scheduleItem();
      final action = resolveCurrentMemberState(
        activeSchedule: schedule,
        activeAutopilot: null,
        preSyncScene: null,
      );
      expect(action, isA<ApplySchedule>());
      expect((action as ApplySchedule).item, same(schedule));
    });

    test('priority 2: no schedule, autopilot present → ApplyAutopilot', () {
      final autopilot = _autopilotItem();
      final action = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: autopilot,
        preSyncScene: null,
      );
      expect(action, isA<ApplyAutopilot>());
      expect((action as ApplyAutopilot).item, same(autopilot));
    });

    test('priority 3: no schedule, no autopilot, scene present → '
        'ApplyPreSyncScene', () {
      final scene = _scene();
      final action = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: scene,
      );
      expect(action, isA<ApplyPreSyncScene>());
      expect((action as ApplyPreSyncScene).scene, same(scene));
    });

    test('priority 4 (off-fallback): all null → TurnOff (NOT freeze)', () {
      final action = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: null,
      );
      expect(action, isA<TurnOff>());
    });
  });

  group('resolveCurrentMemberState — fallthrough order (priority dominance)', () {
    test('schedule beats autopilot when both are present', () {
      final schedule = _scheduleItem();
      final autopilot = _autopilotItem();
      final action = resolveCurrentMemberState(
        activeSchedule: schedule,
        activeAutopilot: autopilot,
        preSyncScene: null,
      );
      expect(action, isA<ApplySchedule>());
      expect((action as ApplySchedule).item, same(schedule));
    });

    test('schedule beats scene when both are present', () {
      final schedule = _scheduleItem();
      final scene = _scene();
      final action = resolveCurrentMemberState(
        activeSchedule: schedule,
        activeAutopilot: null,
        preSyncScene: scene,
      );
      expect(action, isA<ApplySchedule>());
    });

    test('autopilot beats scene when schedule absent', () {
      final autopilot = _autopilotItem();
      final scene = _scene();
      final action = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: autopilot,
        preSyncScene: scene,
      );
      expect(action, isA<ApplyAutopilot>());
    });

    test('schedule wins over everything (all three inputs non-null)', () {
      final schedule = _scheduleItem();
      final action = resolveCurrentMemberState(
        activeSchedule: schedule,
        activeAutopilot: _autopilotItem(),
        preSyncScene: _scene(),
      );
      expect(action, isA<ApplySchedule>());
    });

    test('scene-only path is reached when both schedule and autopilot null',
        () {
      final scene = _scene();
      final action = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: scene,
      );
      expect(action, isA<ApplyPreSyncScene>());
    });
  });

  group('TurnOff is const + identity-stable', () {
    test('multiple calls with all-null return the same const TurnOff', () {
      final a = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: null,
      );
      final b = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: null,
      );
      // Both should be the literal `const TurnOff()` constant.
      expect(identical(a, b), isTrue);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────

ScheduleItem _scheduleItem() => const ScheduleItem(
      id: 'sch_1',
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
      actionLabel: 'Warm White',
      enabled: true,
      wledPayload: <String, dynamic>{
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 0, 'col': [[255, 180, 100, 0]]}
        ],
      },
    );

AutopilotScheduleItem _autopilotItem() {
  final t = DateTime.utc(2026, 5, 22, 19, 0);
  return AutopilotScheduleItem(
    id: 'ap_1',
    scheduledTime: t,
    repeatDays: const [],
    patternName: 'Royals Heritage',
    reason: 'Royals home game tonight',
    trigger: AutopilotTrigger.gameDay,
    confidenceScore: 0.9,
    wledPayload: const <String, dynamic>{
      'on': true,
      'bri': 200,
      'seg': [
        {'fx': 52, 'col': [[0, 70, 135, 0], [189, 155, 96, 0]]}
      ],
    },
    createdAt: t,
  );
}

PreSyncScene _scene() => PreSyncScene(
      groupId: 'group_1',
      wledPayload: const <String, dynamic>{
        'on': true,
        'bri': 128,
        'seg': [
          {'fx': 0, 'col': [[255, 255, 255, 0]]}
        ],
      },
      activeLabel: 'Warm White (Manual)',
      capturedAt: DateTime.utc(2026, 5, 22, 18, 30),
    );
