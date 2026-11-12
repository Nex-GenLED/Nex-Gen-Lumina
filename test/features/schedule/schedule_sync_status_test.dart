// +126 (a)(b)(c) — the persisted sync status: result → state mapping, the
// homeowner copy, the automatic re-sync ledger and the bounded decision.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_sync_status.dart';

ScheduleItem _s(String id) => ScheduleItem(
      id: id,
      timeLabel: '5:00 PM',
      repeatDays: const ['Mon'],
      actionLabel: 'Pattern: X',
      enabled: true,
    );

final _at = DateTime(2026, 11, 12, 10, 0);

void main() {
  group('ScheduleSyncStatus.fromResult', () {
    test('a clean confirmed sync → synced, nothing owed', () {
      final st = ScheduleSyncStatus.fromResult(ScheduleSyncResult(
          success: true, schedulesWithPresets: [_s('a'), _s('b')], syncedAt: _at))!;
      expect(st.state, ScheduleSyncState.synced);
      expect(st.owesResync, isFalse);
      expect(st.scheduleCount, 2);
    });

    test('confirmed but an armed slot did not converge → writtenNotVerified, '
        'owed', () {
      final st = ScheduleSyncStatus.fromResult(ScheduleSyncResult(
        success: true,
        schedulesWithPresets: [_s('a')],
        presetErrors: const ['Failed to save preset 10 (Pattern: X)'],
        unconvergedPresetIds: const [10],
        syncedAt: _at,
      ))!;
      expect(st.state, ScheduleSyncState.writtenNotVerified);
      expect(st.unconvergedPresetIds, [10]);
      expect(st.owesResync, isTrue);
    });

    test('off-LAN deferral → deferredOffLan, owed', () {
      final st = ScheduleSyncStatus.fromResult(
          ScheduleSyncResult.deferredOffLan(schedulesWithPresets: [_s('a')]))!;
      expect(st.state, ScheduleSyncState.deferredOffLan);
      expect(st.owesResync, isTrue);
    });

    test('queued / not-loaded / lease-ledger deferrals → queued (a retry is '
        'already armed), owed', () {
      for (final r in [
        ScheduleSyncResult.queued(),
        ScheduleSyncResult.notLoaded(),
        ScheduleSyncResult.deferredLeaseLedger(),
      ]) {
        final st = ScheduleSyncStatus.fromResult(r)!;
        expect(st.state, ScheduleSyncState.queued, reason: r.summaryMessage);
        expect(st.owesResync, isTrue);
      }
    });

    test('a failure → failed with the sync\'s own sentence, owed', () {
      final st = ScheduleSyncStatus.fromResult(ScheduleSyncResult(
          success: false, error: kScheduleCfgWriteFailed, syncedAt: _at))!;
      expect(st.state, ScheduleSyncState.failed);
      expect(st.message, kScheduleCfgWriteFailed);
      expect(st.owesResync, isTrue);
    });

    test('the interim verifying result is never persisted', () {
      expect(ScheduleSyncStatus.fromResult(ScheduleSyncResult.verifying()),
          isNull);
    });

    test('round-trips through json', () {
      final st = ScheduleSyncStatus(
        state: ScheduleSyncState.writtenNotVerified,
        at: _at,
        message: 'm',
        unconvergedPresetIds: const [10, 12],
        scheduleCount: 3,
      );
      expect(ScheduleSyncStatus.fromJson(st.toJson()), st);
      expect(ScheduleSyncStatus.fromJson(const {'state': 'nope'}), isNull);
    });
  });

  group('ScheduleSyncCopy', () {
    test('every state has homeowner words and no engineering nouns', () {
      for (final s in ScheduleSyncState.values) {
        final c = ScheduleSyncCopy.forState(s);
        final all = '${c.headline} ${c.detail}'.toLowerCase();
        expect(c.headline, isNotEmpty, reason: s.name);
        for (final noun in ['preset', 'cfg', 'timer', 'macro', 'slot', 'lan']) {
          expect(all, isNot(contains(noun)), reason: '${s.name}: $noun');
        }
      }
    });

    test('Retry is offered where it can change something', () {
      expect(ScheduleSyncCopy.forState(ScheduleSyncState.synced).showsRetry,
          isFalse);
      expect(ScheduleSyncCopy.forState(ScheduleSyncState.queued).showsRetry,
          isFalse, reason: 'one is already running by itself');
      for (final s in [
        ScheduleSyncState.deferredOffLan,
        ScheduleSyncState.failed,
        ScheduleSyncState.writtenNotVerified,
      ]) {
        expect(ScheduleSyncCopy.forState(s).showsRetry, isTrue, reason: s.name);
      }
    });

    test('the not-reached states say so in the headline', () {
      for (final s in [
        ScheduleSyncState.deferredOffLan,
        ScheduleSyncState.failed,
      ]) {
        expect(ScheduleSyncCopy.forState(s).headline,
            "Your schedule hasn't reached your lights yet.");
      }
    });
  });

  group('AutoResyncLedger', () {
    test('counts per local day and resets on a new day', () {
      final l1 = AutoResyncLedger.empty.recordAttempt(_at);
      expect(l1.countOn(_at), 1);
      final l2 = l1.recordAttempt(_at.add(const Duration(hours: 1)));
      expect(l2.countOn(_at), 2);
      expect(l2.countOn(_at.add(const Duration(days: 1))), 0);
      final l3 = l2.recordAttempt(_at.add(const Duration(days: 1)));
      expect(l3.countToday, 1);
    });

    test('round-trips through json', () {
      final l = AutoResyncLedger.empty.recordAttempt(_at);
      final back = AutoResyncLedger.fromJson(l.toJson());
      expect(back.lastAttemptAt, _at);
      expect(back.dayKey, AutoResyncLedger.dayKeyFor(_at));
      expect(back.countToday, 1);
    });
  });

  group('autoResyncDecision', () {
    AutoResyncVerdict decide({
      bool owed = true,
      bool onLan = true,
      bool lightsOn = false,
      DateTime? now,
      AutoResyncLedger ledger = AutoResyncLedger.empty,
    }) =>
        autoResyncDecision(
            owed: owed,
            onLan: onLan,
            lightsOn: lightsOn,
            now: now ?? _at,
            ledger: ledger);

    test('runs when owed, on LAN, lights off, daytime, within bounds', () {
      expect(decide(), AutoResyncVerdict.run);
    });

    test('nothing owed → never', () {
      expect(decide(owed: false), AutoResyncVerdict.nothingOwed);
    });

    test('off the home Wi-Fi (bridge/relay counts) → held', () {
      expect(decide(onLan: false), AutoResyncVerdict.offLan);
    });

    test('lights on → held (a psave would be visible)', () {
      expect(decide(lightsOn: true), AutoResyncVerdict.lightsOn);
    });

    test('outside 8:00–17:00 local → held', () {
      expect(decide(now: DateTime(2026, 11, 12, 7, 59)),
          AutoResyncVerdict.outsideDaytime);
      expect(decide(now: DateTime(2026, 11, 12, 17, 0)),
          AutoResyncVerdict.outsideDaytime);
      expect(decide(now: DateTime(2026, 11, 12, 21, 30)),
          AutoResyncVerdict.outsideDaytime);
      expect(decide(now: DateTime(2026, 11, 12, 8, 0)), AutoResyncVerdict.run);
      expect(decide(now: DateTime(2026, 11, 12, 16, 59)),
          AutoResyncVerdict.run);
    });

    test('at least ten minutes between automatic attempts', () {
      final l = AutoResyncLedger.empty.recordAttempt(_at);
      expect(decide(now: _at.add(const Duration(minutes: 9, seconds: 59)), ledger: l),
          AutoResyncVerdict.tooSoon);
      expect(decide(now: _at.add(const Duration(minutes: 10)), ledger: l),
          AutoResyncVerdict.run);
    });

    test('at most six automatic attempts a day; a new day resets', () {
      var l = AutoResyncLedger.empty;
      var t = _at;
      for (var i = 0; i < kAutoResyncMaxPerDay; i++) {
        expect(decide(now: t, ledger: l), AutoResyncVerdict.run, reason: 'attempt ${i + 1}');
        l = l.recordAttempt(t);
        t = t.add(const Duration(minutes: 30));
      }
      expect(decide(now: t, ledger: l), AutoResyncVerdict.dailyCapReached);
      // Next day, 10:00 — the cap is per local day.
      expect(decide(now: _at.add(const Duration(days: 1)), ledger: l),
          AutoResyncVerdict.run);
    });

    test('the numbers themselves', () {
      expect(kAutoResyncMaxPerDay, 6);
      expect(kAutoResyncMinGap, const Duration(minutes: 10));
      expect(kAutoResyncDayStartHour, 8);
      expect(kAutoResyncDayEndHour, 17);
    });
  });
}
