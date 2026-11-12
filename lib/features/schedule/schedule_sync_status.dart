// +126 (a)(b)(c) — the persisted, per-account outcome of the last schedule
// sync, the owed re-sync flag, the bounded automatic re-sync policy and the
// non-fatal Firestore mirror.
//
// WHY (Classic Christmas audit, 2026-11-11): three accounts had a schedule
// the app showed as enabled while the controller held something else — an
// edit made off the home network that was never re-synced, an enabled
// schedule never armed since 11-03, and a toggle whose sync was dropped. The
// sync's outcome lived only in a session-scoped provider, so a restart showed
// nothing, and nothing ever re-ran a deferred or failed sync. This file is
// the memory the app was missing: what the last sync did, whether a re-sync
// is owed, and when the app may run one by itself.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The five states a customer can be in, as the status row and the Home chip
/// name them.
enum ScheduleSyncState {
  /// The last sync was confirmed on the controller and every preset it wrote
  /// converged.
  synced,

  /// A sync is owed and will run by itself: queued behind one in flight, or
  /// deferred until the schedules / lease ledger loaded.
  queued,

  /// Saved, but the phone was off the home Wi-Fi (a bridge/relay session
  /// counts as off-LAN) so nothing could be written to the controller.
  deferredOffLan,

  /// The controller could not be reached, or the timer write could not be
  /// confirmed.
  failed,

  /// The timers were armed (owner decision ii), but at least one pattern
  /// preset could not be confirmed as written: its id is in
  /// [ScheduleSyncStatus.unconvergedPresetIds].
  writtenNotVerified,
}

/// The persisted outcome of the last sync for one account.
@immutable
class ScheduleSyncStatus {
  const ScheduleSyncStatus({
    required this.state,
    required this.at,
    this.message,
    this.unconvergedPresetIds = const [],
    this.scheduleCount = 0,
  });

  final ScheduleSyncState state;

  /// When the sync that produced this outcome finished.
  final DateTime at;

  /// The sync's own sentence (error or deferral copy), if any.
  final String? message;

  /// Preset slots the sync armed without a converged write (option ii).
  final List<int> unconvergedPresetIds;

  /// How many schedules the sync armed (synced) or carried.
  final int scheduleCount;

  /// True when a re-sync is owed: anything but a clean, converged sync.
  bool get owesResync => state != ScheduleSyncState.synced;

  /// Derive the persisted outcome from a sync result. The interim
  /// `verifying` state is never persisted (the in-flight sync owns the row).
  static ScheduleSyncStatus? fromResult(ScheduleSyncResult r) {
    if (r.verifying) return null;
    final at = r.syncedAt;
    if (r.queuedBehindInFlight || r.deferredNotLoaded || r.deferredLeaseLedger) {
      return ScheduleSyncStatus(
          state: ScheduleSyncState.queued, at: at, message: r.summaryMessage);
    }
    if (r.deferredOffLan) {
      return ScheduleSyncStatus(
          state: ScheduleSyncState.deferredOffLan,
          at: at,
          message: r.summaryMessage,
          scheduleCount: r.schedulesWithPresets.length);
    }
    if (!r.success) {
      return ScheduleSyncStatus(
          state: ScheduleSyncState.failed,
          at: at,
          message: r.error ?? r.summaryMessage,
          unconvergedPresetIds: r.unconvergedPresetIds,
          scheduleCount: r.schedulesWithPresets.length);
    }
    if (r.unconvergedPresetIds.isNotEmpty) {
      return ScheduleSyncStatus(
          state: ScheduleSyncState.writtenNotVerified,
          at: at,
          message: r.presetErrors.isEmpty ? null : r.presetErrors.first,
          unconvergedPresetIds: r.unconvergedPresetIds,
          scheduleCount: r.schedulesWithPresets.length);
    }
    return ScheduleSyncStatus(
        state: ScheduleSyncState.synced,
        at: at,
        scheduleCount: r.schedulesWithPresets.length);
  }

  Map<String, dynamic> toJson() => {
        'state': state.name,
        'at': at.toUtc().toIso8601String(),
        if (message != null) 'message': message,
        'unconverged_preset_ids': unconvergedPresetIds,
        'schedule_count': scheduleCount,
      };

  static ScheduleSyncStatus? fromJson(Map<String, dynamic> json) {
    final stateName = json['state'];
    final state = ScheduleSyncState.values
        .cast<ScheduleSyncState?>()
        .firstWhere((s) => s!.name == stateName, orElse: () => null);
    final at = DateTime.tryParse(json['at']?.toString() ?? '');
    if (state == null || at == null) return null;
    final ids = json['unconverged_preset_ids'];
    return ScheduleSyncStatus(
      state: state,
      at: at.toLocal(),
      message: json['message'] as String?,
      unconvergedPresetIds:
          ids is List ? ids.whereType<num>().map((n) => n.toInt()).toList() : const [],
      scheduleCount: (json['schedule_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// The Firestore mirror body: the same facts plus a server stamp.
  Map<String, dynamic> toMirror() => {
        ...toJson(),
        'at': Timestamp.fromDate(at.toUtc()),
        'mirrored_at': FieldValue.serverTimestamp(),
      };

  @override
  bool operator ==(Object other) =>
      other is ScheduleSyncStatus &&
      other.state == state &&
      other.at == at &&
      other.message == message &&
      listEquals(other.unconvergedPresetIds, unconvergedPresetIds) &&
      other.scheduleCount == scheduleCount;

  @override
  int get hashCode => Object.hash(state, at, message, scheduleCount,
      Object.hashAll(unconvergedPresetIds));
}

// ─── Homeowner copy ──────────────────────────────────────────────────────────

/// What the status row and the Home chip say, per state. One place so the
/// two surfaces cannot drift. Plain words; no "preset", "cfg" or "timer".
class ScheduleSyncCopy {
  const ScheduleSyncCopy({
    required this.headline,
    required this.detail,
    required this.showsRetry,
  });

  /// The one line the chip shows and the row leads with.
  final String headline;

  /// The row's second sentence (what happens next / what to do).
  final String detail;

  /// Whether a Retry action is offered. A manual retry is always allowed;
  /// it is simply not OFFERED where it would do nothing new (synced) or
  /// where one is already running by itself (queued).
  final bool showsRetry;

  static ScheduleSyncCopy forState(ScheduleSyncState state) {
    switch (state) {
      case ScheduleSyncState.synced:
        return const ScheduleSyncCopy(
          headline: 'Your schedule is on your lights.',
          detail: '',
          showsRetry: false,
        );
      case ScheduleSyncState.queued:
        return const ScheduleSyncCopy(
          headline: 'Saving your latest change.',
          detail: 'It goes to your lights next, automatically.',
          showsRetry: false,
        );
      case ScheduleSyncState.deferredOffLan:
        return const ScheduleSyncCopy(
          headline: "Your schedule hasn't reached your lights yet.",
          detail: "It will the next time you open the app on your home "
              "Wi-Fi. You can retry now if you're home.",
          showsRetry: true,
        );
      case ScheduleSyncState.failed:
        return const ScheduleSyncCopy(
          headline: "Your schedule hasn't reached your lights yet.",
          detail: "Your controller didn't answer. Check that it's powered "
              'and on Wi-Fi, then retry.',
          showsRetry: true,
        );
      case ScheduleSyncState.writtenNotVerified:
        return const ScheduleSyncCopy(
          headline: 'Your schedule is set, but one pattern could not be '
              'confirmed on your lights.',
          detail: "We'll keep trying on our own. You can retry now.",
          showsRetry: true,
        );
    }
  }
}

// ─── Bounded automatic re-sync ───────────────────────────────────────────────

/// At most this many automatic attempts per account per local day.
///
/// Six covers a bad day — a controller that is off-line through several
/// launches — without turning a persistent failure into a flash every time
/// the phone joins the Wi-Fi. A manual Retry is never counted.
const int kAutoResyncMaxPerDay = 6;

/// At least this long between two automatic attempts.
///
/// Ten minutes is longer than the longest sync (the post-commit verification
/// poll is bounded at five minutes), so two automatic attempts can never
/// overlap, and a flapping Wi-Fi link (each join is a LAN-return event)
/// cannot drive the count.
const Duration kAutoResyncMinGap = Duration(minutes: 10);

/// The local hours (inclusive start, exclusive end) in which an automatic
/// re-sync may run. See [autoResyncDecision] for why.
const int kAutoResyncDayStartHour = 8;
const int kAutoResyncDayEndHour = 17;

/// Why an automatic re-sync did or did not run now.
enum AutoResyncVerdict {
  run,
  nothingOwed,
  offLan,
  lightsOn,
  outsideDaytime,
  tooSoon,
  dailyCapReached,
}

/// The per-account ledger of automatic attempts.
@immutable
class AutoResyncLedger {
  const AutoResyncLedger({this.lastAttemptAt, this.dayKey, this.countToday = 0});

  final DateTime? lastAttemptAt;

  /// Local calendar day of [countToday], as `YYYY-MM-DD`.
  final String? dayKey;
  final int countToday;

  static const empty = AutoResyncLedger();

  static String dayKeyFor(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';

  int countOn(DateTime now) => dayKey == dayKeyFor(now) ? countToday : 0;

  AutoResyncLedger recordAttempt(DateTime now) => AutoResyncLedger(
        lastAttemptAt: now,
        dayKey: dayKeyFor(now),
        countToday: countOn(now) + 1,
      );

  Map<String, dynamic> toJson() => {
        if (lastAttemptAt != null)
          'last_attempt_at': lastAttemptAt!.toUtc().toIso8601String(),
        if (dayKey != null) 'day_key': dayKey,
        'count_today': countToday,
      };

  static AutoResyncLedger fromJson(Map<String, dynamic> json) =>
      AutoResyncLedger(
        lastAttemptAt:
            DateTime.tryParse(json['last_attempt_at']?.toString() ?? '')
                ?.toLocal(),
        dayKey: json['day_key'] as String?,
        countToday: (json['count_today'] as num?)?.toInt() ?? 0,
      );
}

/// Whether the app may run an automatic re-sync right now.
///
/// Order matters: the cheap "is anything owed / can we even write" checks
/// come first, then the two customer-visibility gates, then the bounds.
///
/// THE LIGHTS GATE. A re-sync psaves the schedule's pattern, and on this
/// firmware a psave APPLIES its body to the strip before storing it (the
/// sync restores the captured state straight after, with `transition:0`).
/// With the lights ON the house would switch to the schedule's pattern for
/// well under a second and snap back; with the lights OFF it would light up
/// with that pattern for the same moment and go dark again. Neither is
/// invisible on a dark house at night, so an automatic re-sync runs only
/// while the lights are OFF and it is DAYTIME ([kAutoResyncDayStartHour] to
/// [kAutoResyncDayEndHour] local): a sub-second flicker of unlit roofline
/// LEDs in daylight is the least a customer can be asked to notice. A manual
/// Retry runs at once, whatever the lights are doing — the customer pressed it.
AutoResyncVerdict autoResyncDecision({
  required bool owed,
  required bool onLan,
  required bool lightsOn,
  required DateTime now,
  required AutoResyncLedger ledger,
}) {
  if (!owed) return AutoResyncVerdict.nothingOwed;
  if (!onLan) return AutoResyncVerdict.offLan;
  if (lightsOn) return AutoResyncVerdict.lightsOn;
  if (now.hour < kAutoResyncDayStartHour || now.hour >= kAutoResyncDayEndHour) {
    return AutoResyncVerdict.outsideDaytime;
  }
  final last = ledger.lastAttemptAt;
  if (last != null && now.difference(last) < kAutoResyncMinGap) {
    return AutoResyncVerdict.tooSoon;
  }
  if (ledger.countOn(now) >= kAutoResyncMaxPerDay) {
    return AutoResyncVerdict.dailyCapReached;
  }
  return AutoResyncVerdict.run;
}

// ─── Persistence ─────────────────────────────────────────────────────────────

/// SharedPreferences keys, per account.
String scheduleSyncStatusKey(String uid) => 'schedule_sync_status_$uid';
String scheduleSyncOwedKey(String uid) => 'schedule_sync_owed_$uid';
String scheduleSyncAutoLedgerKey(String uid) => 'schedule_sync_auto_$uid';

/// Reads and writes the three per-account facts. Every method swallows a
/// storage failure: the sync must never fail because its bookkeeping did.
class ScheduleSyncStatusStore {
  const ScheduleSyncStatusStore();

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('ScheduleSyncStatusStore: prefs unavailable — $e');
      return null;
    }
  }

  Future<ScheduleSyncStatus?> readStatus(String uid) async {
    final p = await _prefs();
    final raw = p?.getString(scheduleSyncStatusKey(uid));
    if (raw == null) return null;
    try {
      return ScheduleSyncStatus.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('ScheduleSyncStatusStore: bad status json — $e');
      return null;
    }
  }

  Future<void> writeStatus(String uid, ScheduleSyncStatus status) async {
    final p = await _prefs();
    await p?.setString(scheduleSyncStatusKey(uid), jsonEncode(status.toJson()));
  }

  Future<bool> readOwed(String uid) async {
    final p = await _prefs();
    return p?.getBool(scheduleSyncOwedKey(uid)) ?? false;
  }

  Future<void> writeOwed(String uid, bool owed) async {
    final p = await _prefs();
    await p?.setBool(scheduleSyncOwedKey(uid), owed);
  }

  Future<AutoResyncLedger> readLedger(String uid) async {
    final p = await _prefs();
    final raw = p?.getString(scheduleSyncAutoLedgerKey(uid));
    if (raw == null) return AutoResyncLedger.empty;
    try {
      return AutoResyncLedger.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AutoResyncLedger.empty;
    }
  }

  Future<void> writeLedger(String uid, AutoResyncLedger ledger) async {
    final p = await _prefs();
    await p?.setString(
        scheduleSyncAutoLedgerKey(uid), jsonEncode(ledger.toJson()));
  }
}

final scheduleSyncStatusStoreProvider =
    Provider<ScheduleSyncStatusStore>((_) => const ScheduleSyncStatusStore());

// ─── Firestore mirror ────────────────────────────────────────────────────────

/// Field on `users/{uid}` that carries the mirrored outcome. A FIELD on the
/// owner's own document, not a subcollection: the owner's update rule on
/// `/users/{userId}` already permits it (isOwner + the critical fields
/// unchanged; a `set(merge:true)` leaves them unchanged), so no rules
/// change is needed for the mirror to land.
const String kScheduleSyncMirrorField = 'schedule_sync';

/// Writes the outcome somewhere support can see it. NON-FATAL by contract:
/// a rules rejection, no network or no Firebase app is logged and dropped,
/// and the app carries on exactly as if the mirror did not exist.
abstract class ScheduleSyncMirror {
  Future<void> write(String uid, ScheduleSyncStatus status);
}

class FirestoreScheduleSyncMirror implements ScheduleSyncMirror {
  FirestoreScheduleSyncMirror({FirebaseFirestore? firestore})
      : _firestore = firestore;
  final FirebaseFirestore? _firestore;

  @override
  Future<void> write(String uid, ScheduleSyncStatus status) async {
    try {
      final db = _firestore ?? FirebaseFirestore.instance;
      await db
          .collection('users')
          .doc(uid)
          .set({kScheduleSyncMirrorField: status.toMirror()},
              SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // Permission-denied, offline, no app: all the same here. Logged, never
      // surfaced, never rethrown.
      debugPrint('ScheduleSyncMirror: mirror write dropped — $e');
    }
  }
}

/// A mirror that drops everything (demo mode, tests).
class NoopScheduleSyncMirror implements ScheduleSyncMirror {
  const NoopScheduleSyncMirror();
  @override
  Future<void> write(String uid, ScheduleSyncStatus status) async {}
}

final scheduleSyncMirrorProvider =
    Provider<ScheduleSyncMirror>((_) => FirestoreScheduleSyncMirror());

// ─── The status provider ─────────────────────────────────────────────────────

/// The last persisted outcome for the effective account; `null` until a sync
/// has ever run for it. Loaded from SharedPreferences when the account is
/// known, then kept current by [SchedulesNotifier] through [record].
class ScheduleSyncStatusNotifier extends StateNotifier<ScheduleSyncStatus?> {
  ScheduleSyncStatusNotifier(this._store, this._uid) : super(null) {
    _load();
  }

  final ScheduleSyncStatusStore _store;
  final String? _uid;

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    final persisted = await _store.readStatus(uid);
    if (!mounted) return;
    // A sync may have recorded a fresher outcome while the read was pending.
    if (state == null) state = persisted;
  }

  /// Store the outcome in memory and on disk.
  Future<void> record(ScheduleSyncStatus status) async {
    if (!mounted) return;
    state = status;
    final uid = _uid;
    if (uid != null) await _store.writeStatus(uid, status);
  }
}

final scheduleSyncStatusProvider =
    StateNotifierProvider<ScheduleSyncStatusNotifier, ScheduleSyncStatus?>(
  (ref) => ScheduleSyncStatusNotifier(
    ref.watch(scheduleSyncStatusStoreProvider),
    ref.watch(effectiveUserUidProvider),
  ),
);
