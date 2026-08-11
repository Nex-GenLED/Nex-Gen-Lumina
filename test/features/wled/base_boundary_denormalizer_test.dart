// Base-boundary publish — the app-side half of making device timer rows
// visible to a server-side planner that cannot read /json/cfg.
//
// Pure logic + document shape. The Firestore write itself is covered in
// controller_facts_writer_test.dart against fake_cloud_firestore.

import 'package:flutter_test/flutter_test.dart';
// schedule_sync re-exports timer_landing's predicates, including
// timerInstancesFromCfg — the extractor under test here.
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';

/// A clock row as WLED serializes it. `en` is an INT — the firmware reads it
/// type-strictly and stores a JSON bool as 0.
Map<String, dynamic> _clock({
  required int hour,
  required int min,
  required int macro,
  int dow = 127,
  int en = 1,
}) =>
    {'en': en, 'hour': hour, 'min': min, 'macro': macro, 'dow': dow};

Map<String, dynamic> _stub() =>
    {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0};

/// The bench rig's table (`.150`) exactly as `/json/cfg` RETURNS it, captured
/// 2026-08-11: base ON 20:23 macro 10, base OFF 06:22 macro 2, a Wednesday
/// lease macro 40, and the slot-8 solar sentinel.
///
/// FOUR entries, not ten. WLED compacts the readback — it drops the disabled
/// padding stubs, so the slot-8 sentinel arrives at INDEX 3. Every fixture here
/// is the readback shape, because that is the only shape the publisher ever
/// sees.
List<Map<String, dynamic>> _rigTable() => [
      _clock(hour: 20, min: 23, macro: 10),
      _clock(hour: 6, min: 22, macro: 2),
      _clock(hour: 20, min: 40, macro: 40, dow: kWledDowWednesday),
      // The slot-8 sunrise sentinel — the global sunrise-off (macro 2).
      {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127},
    ];

/// What the app SENDS: ten entries, sentinel positioned at slot 8. A readback
/// only looks like this when every slot is armed.
List<Map<String, dynamic>> _sentShapeTable() => [
      _clock(hour: 20, min: 23, macro: 10),
      _clock(hour: 6, min: 22, macro: 2),
      _stub(),
      _stub(),
      _stub(),
      _stub(),
      _stub(),
      _stub(),
      {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127},
      _stub(),
    ];

void main() {
  setUp(resetBaseBoundariesMemo);

  group('extractBaseBoundaries — null vs empty', () {
    test('NULL rows in → NULL out (unreadable is not empty)', () {
      // The whole point. An unreadable timer table must never reach the planner
      // as "this house has no boundaries" — that is the state in which it would
      // happily plan a fire straight through one.
      expect(extractBaseBoundaries(null), isNull);
    });

    test('an all-stub table reads as EMPTY, which is a real answer', () {
      final rows = extractBaseBoundaries(List.generate(10, (_) => _stub()));
      expect(rows, isNotNull);
      expect(rows, isEmpty);
    });
  });

  group('extractBaseBoundaries — the bench rig table', () {
    late List<BaseBoundaryRow> rows;
    setUp(() => rows = extractBaseBoundaries(_rigTable())!);

    test('finds exactly the four armed rows and drops the stubs', () {
      expect(rows.length, 4);
      expect(rows.map((r) => r.macro).toList(), [10, 2, 40, 2]);
    });

    test('base ON 20:23 macro 10 is a clock row at index 0', () {
      final on = rows.first;
      expect(on.index, 0);
      expect(on.kind, kBoundaryKindClock);
      expect(on.hour, 20);
      expect(on.minute, 23);
      expect(on.macro, 10);
      expect(on.role, 'schedule');
    });

    test('base OFF 06:22 macro 2 classifies as system_off', () {
      final off = rows[1];
      expect(off.hour, 6);
      expect(off.minute, 22);
      expect(off.role, 'system_off');
    });

    test('the Wednesday lease macro 40 classifies as lease, dow bit 2', () {
      final lease = rows[2];
      expect(lease.macro, 40);
      expect(lease.role, 'lease');
      // Monday=bit0, so Wednesday is bit 2 = 4. The app previously shipped
      // Sunday=bit0 and every non-Daily schedule fired a day late.
      expect(lease.dow, 4);
    });

    test('the slot-8 sentinel arrives at INDEX 3 and is still recognised as '
        'solar', () {
      // THE BENCH FINDING. Classifying by array index called this a CLOCK row
      // at hour 255 — a boundary at an impossible time. `hour == 255` is what
      // makes a row solar, wherever WLED's compaction happens to put it.
      final sentinel = rows[3];
      expect(sentinel.index, 3);
      expect(sentinel.index, isNot(kSunriseSlotIndex));
      expect(sentinel.isSolar, isTrue);
      expect(sentinel.hour, 255);
    });

    test('a LONE solar row refuses to name its direction', () {
      // Only one 255-row came back, and "on at sunset / off at a clock time"
      // produces an identical wire shape. Guessing sunrise would put a planner
      // 14 hours out.
      expect(rows[3].kind, kBoundaryKindSolarUnknown);
    });
  });

  group('solar rows', () {
    test('TWO solar rows pair ordinally — first sunrise, second sunset', () {
      // Order is preserved on the wire, so with both armed the direction IS
      // decidable. This is also what makes a swap detectable.
      final ins = [
        _clock(hour: 20, min: 23, macro: 10),
        {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127},
        {'en': 1, 'hour': 255, 'min': -30, 'macro': 11, 'dow': 127},
      ];
      final rows = extractBaseBoundaries(ins)!;
      expect(rows[1].kind, kBoundaryKindSunrise);
      expect(rows[2].kind, kBoundaryKindSunset);
    });

    test('a full-length readback still classifies by CONTENT, and agrees with '
        'position', () {
      // When nothing was compacted the two rules coincide. They must not be
      // allowed to disagree.
      final rows = extractBaseBoundaries(_sentShapeTable())!;
      final solar = rows.singleWhere((r) => r.isSolar);
      expect(solar.index, kSunriseSlotIndex);
      expect(solar.kind, kBoundaryKindSolarUnknown,
          reason: 'still a lone 255-row — position does not rescue direction');
    });

    test('a NEGATIVE offset round-tripped through an unsigned byte is folded '
        'back', () {
      // -30 comes off the wire as 226. Publishing 226 would tell a planner the
      // row fires 3h46m after sunset instead of 30 min before it.
      final ins = [
        {'en': 1, 'hour': 255, 'min': 226, 'macro': 10, 'dow': 127}
      ];
      expect(extractBaseBoundaries(ins)!.single.minute, -30);
    });

    test('a clock row minute is NOT folded — 226 is not a legal minute but is '
        'passed through verbatim', () {
      // The fold applies only to solar slots. A clock row's `min` is a wall
      // clock minute; reinterpreting it as signed would corrupt real data.
      final ins = [_clock(hour: 5, min: 226, macro: 10)];
      expect(extractBaseBoundaries(ins)!.single.minute, 226);
    });
  });

  group('toJson — clock and solar carry DIFFERENT keys', () {
    test('a clock row emits hour + minute and no offset', () {
      final j = extractBaseBoundaries([_clock(hour: 20, min: 23, macro: 10)])!
          .single
          .toJson();
      expect(j['hour'], 20);
      expect(j['minute'], 23);
      expect(j.containsKey('offset_minutes'), isFalse);
    });

    test('a solar row emits offset_minutes and NO hour at all', () {
      // hour 255 is a marker, not an hour. A planner that reads `hour` off a
      // solar row must get nothing rather than 255 — or `minute` and get an
      // offset. Two quantities in one device field, two keys on the wire.
      final ins = [
        {'en': 1, 'hour': 255, 'min': -15, 'macro': 2, 'dow': 127}
      ];
      final j = extractBaseBoundaries(ins)!.single.toJson();
      expect(j.containsKey('hour'), isFalse);
      expect(j.containsKey('minute'), isFalse);
      expect(j['offset_minutes'], -15);
      expect(j['kind'], kBoundaryKindSolarUnknown);
    });

    test('every row carries index, macro, role and dow', () {
      final j = extractBaseBoundaries([_clock(hour: 1, min: 2, macro: 30)])!
          .single
          .toJson();
      expect(j['index'], 0);
      expect(j['macro'], 30);
      expect(j['role'], 'lease');
      expect(j['dow'], 127);
    });
  });

  group('armed-row filtering matches the clobber guard', () {
    test('a disabled row with a real macro is NOT a boundary', () {
      final ins = [_clock(hour: 20, min: 23, macro: 10, en: 0)];
      expect(extractBaseBoundaries(ins), isEmpty);
    });

    test('an enabled row with macro 0 does nothing and is NOT a boundary', () {
      final ins = [_clock(hour: 20, min: 23, macro: 0)];
      expect(extractBaseBoundaries(ins), isEmpty);
    });

    test('en as a BOOL true is still honoured on read', () {
      // The app must never WRITE a bool (WLED stores it as 0), but a table
      // written by some other tool could carry one, and it would fire.
      final ins = [
        {'en': true, 'hour': 20, 'min': 23, 'macro': 10, 'dow': 127}
      ];
      expect(extractBaseBoundaries(ins)!.length, 1);
    });
  });

  group('shouldPublishBaseBoundaries', () {
    BaseBoundaryRow row(int hour) => BaseBoundaryRow(
          index: 0,
          kind: kBoundaryKindClock,
          hour: hour,
          minute: 0,
          dow: 127,
          macro: 10,
          role: 'schedule',
        );

    test('publishes when nothing has been published yet', () {
      expect(
        shouldPublishBaseBoundaries(rows: [row(20)], lastPublished: null),
        isTrue,
      );
    });

    test('does NOT republish an unchanged table', () {
      expect(
        shouldPublishBaseBoundaries(rows: [row(20)], lastPublished: [row(20)]),
        isFalse,
      );
    });

    test('publishes when a boundary MOVES', () {
      expect(
        shouldPublishBaseBoundaries(rows: [row(21)], lastPublished: [row(20)]),
        isTrue,
      );
    });

    test('publishes when a row is added or removed', () {
      expect(
        shouldPublishBaseBoundaries(
            rows: [row(20), row(6)], lastPublished: [row(20)]),
        isTrue,
      );
      expect(
        shouldPublishBaseBoundaries(rows: [], lastPublished: [row(20)]),
        isTrue,
      );
    });

    test('an EMPTY table is publishable and distinct from never-published', () {
      expect(shouldPublishBaseBoundaries(rows: [], lastPublished: null), isTrue);
      expect(shouldPublishBaseBoundaries(rows: [], lastPublished: []), isFalse);
    });
  });

  group('memo', () {
    final rows = extractBaseBoundaries(_rigTable())!;

    test('remembering suppresses the next identical publish', () {
      expect(prepareBaseBoundaryFacts(
        controllerId: 'c1',
        rows: rows,
        slotsRead: 10,
        source: 'healer',
      ).isEmpty, isFalse);

      // prepare does not commit — the write does. Simulate a successful write.
      rememberPublishedBaseBoundaries('c1', rows);

      expect(prepareBaseBoundaryFacts(
        controllerId: 'c1',
        rows: rows,
        slotsRead: 10,
        source: 'healer',
      ).isEmpty, isTrue);
    });

    test('is per-controller', () {
      rememberPublishedBaseBoundaries('c1', rows);
      expect(prepareBaseBoundaryFacts(
        controllerId: 'c2',
        rows: rows,
        slotsRead: 10,
        source: 'healer',
      ).isEmpty, isFalse);
    });

    test('stores a COPY — mutating the source cannot corrupt the memo', () {
      final live = List<BaseBoundaryRow>.from(rows);
      rememberPublishedBaseBoundaries('c1', live);
      live.clear();
      expect(publishedBaseBoundariesMemo['c1']!.length, rows.length);
    });
  });

  group('prepareBaseBoundaryFacts', () {
    test('an UNREADABLE table contributes nothing to the write', () {
      expect(
        prepareBaseBoundaryFacts(
          controllerId: 'c1',
          rows: null,
          slotsRead: 0,
          source: 'healer',
        ).isEmpty,
        isTrue,
      );
    });

    test('records the slots it read — provenance for an empty answer', () {
      // Without this, "no boundaries" and "we parsed a truncated body that
      // happened to yield nothing" look identical.
      final f = prepareBaseBoundaryFacts(
        controllerId: 'c1',
        rows: const [],
        slotsRead: 10,
        source: 'healer',
      );
      expect(f.fields[kBaseBoundariesField], isEmpty);
      expect(f.fields[kBaseBoundariesSlotsReadField], 10);
    });

    test('states the dow convention on every publish', () {
      final f = prepareBaseBoundaryFacts(
        controllerId: 'c1',
        rows: extractBaseBoundaries(_rigTable()),
        slotsRead: 10,
        source: 'healer',
      );
      expect(f.fields[kBaseBoundariesDowBit0Field], 'monday');
    });

    test('field names are snake_case, matching the controller-doc convention',
        () {
      expect(kBaseBoundariesField, 'base_boundaries');
      expect(kBaseBoundariesSlotsReadField, 'base_boundaries_slots_read');
      expect(kBaseBoundariesDowBit0Field, 'base_boundaries_dow_bit0');
    });
  });

  group('wledPresetRole', () {
    test('classifies each allocator range', () {
      expect(wledPresetRole(2), 'system_off');
      expect(wledPresetRole(1), 'system_on');
      expect(wledPresetRole(5), 'system_on');
      expect(wledPresetRole(10), 'schedule');
      expect(wledPresetRole(25), 'schedule');
      expect(wledPresetRole(26), 'lease');
      expect(wledPresetRole(41), 'lease');
      expect(wledPresetRole(100), 'user_pattern');
      expect(wledPresetRole(200), 'user_pattern');
    });

    test('admits ignorance rather than guessing on a gap', () {
      // 42-99 and 201-250 are intentional breathing room; a macro there was
      // written by something outside Lumina's allocators.
      expect(wledPresetRole(50), 'unknown');
      expect(wledPresetRole(220), 'unknown');
      expect(wledPresetRole(0), 'unknown');
    });
  });

  group('DRIFT GUARD — the pure range table matches the real allocators', () {
    // wled_preset_ranges.dart is pure Dart so the classifier does not drag
    // Flutter into the denormalizer, which means the system-preset ids are
    // written down twice. These tests are the binding: if ScheduleSyncService
    // ever gains or renames an ON slot, the classifier stops silently
    // mislabeling it as `unknown` and this fails instead.
    test('kSystemOnPresetIds == ScheduleSyncService.kOnPresetSpecs.keys', () {
      expect(kSystemOnPresetIds,
          equals(ScheduleSyncService.kOnPresetSpecs.keys.toSet()));
    });

    test('kSystemOffPresetId == ScheduleSyncService.kNglOffPresetId', () {
      expect(kSystemOffPresetId, ScheduleSyncService.kNglOffPresetId);
    });

    test('the solar slot indices match the ones schedule sync writes', () {
      expect(kSunriseSlotIndex, ScheduleSyncService.kWledSunriseSlot);
      expect(kSunsetSlotIndex, ScheduleSyncService.kWledSunsetSlot);
      expect(kWledTotalTimerSlots, ScheduleSyncService.kWledTotalTimerSlots);
    });
  });

  group('index-vs-slot honesty', () {
    test('a COMPACTED readback declares its indices are NOT slots', () {
      final f = prepareBaseBoundaryFacts(
        controllerId: 'c1',
        rows: extractBaseBoundaries(_rigTable()),
        slotsRead: 4,
        source: 'healer',
      );
      expect(f.fields[kBaseBoundariesIndicesAreSlotsField], isFalse);
      expect(f.fields[kBaseBoundariesSlotsReadField], 4);
    });

    test('a FULL-LENGTH readback declares that they are', () {
      final f = prepareBaseBoundaryFacts(
        controllerId: 'c1',
        rows: extractBaseBoundaries(_sentShapeTable()),
        slotsRead: 10,
        source: 'healer',
      );
      expect(f.fields[kBaseBoundariesIndicesAreSlotsField], isTrue);
    });
  });

  group('timerInstancesFromCfg — the shared cfg extractor', () {
    test('null cfg, absent block, and a wrong-typed block all read UNKNOWN',
        () {
      expect(timerInstancesFromCfg(null), isNull);
      expect(timerInstancesFromCfg({'if': {}}), isNull);
      expect(timerInstancesFromCfg({'timers': 'nope'}), isNull);
      expect(timerInstancesFromCfg({'timers': {'ins': 'nope'}}), isNull);
    });

    test('a real cfg yields plain maps in slot order', () {
      final ins = timerInstancesFromCfg({
        'timers': {'ins': _sentShapeTable()}
      })!;
      expect(ins.length, 10);
      expect(ins[0]['macro'], 10);
      expect(ins[8]['hour'], 255);

      // ...and the real, compacted readback comes back short.
      final compacted = timerInstancesFromCfg({
        'timers': {'ins': _rigTable()}
      })!;
      expect(compacted.length, 4);
    });

    test('an empty array is EMPTY, not unknown', () {
      expect(timerInstancesFromCfg({'timers': {'ins': []}}), isEmpty);
    });
  });

  group('ControllerClockInfo carries the rows off the healer cfg read', () {
    test('timersKnown is false when cfg was unavailable (relay)', () {
      final info = ControllerClockInfo.fromMaps({'time': '2026-8-11, 20:0:0'}, null);
      expect(info.timersKnown, isFalse);
      expect(info.timerRows, isNull);
    });

    test('timersKnown is true and the rows survive a full cfg parse', () {
      final info = ControllerClockInfo.fromMaps(
        {'time': '2026-8-11, 20:0:0'},
        {
          'if': {
            'ntp': {'tz': 5, 'lt': 41.88, 'ln': -87.63}
          },
          'timers': {'ins': _rigTable()},
        },
      );
      expect(info.timersKnown, isTrue);
      expect(info.timerRows!.length, 4);
      // The clock fields still parse — the timer rows are additive.
      expect(info.tzIndex, 5);
      expect(extractBaseBoundaries(info.timerRows)!.length, 4);
    });
  });
}
