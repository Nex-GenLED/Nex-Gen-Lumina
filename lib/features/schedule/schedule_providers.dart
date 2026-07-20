import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/data/schedule_lazy_migrator.dart';
import 'package:nexgen_command/features/schedule/data/schedule_repository.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_detector.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/schedules_subcollection_feature_flag.dart';
import 'package:nexgen_command/features/schedule/solar_schedule_cleanup.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart'
    show repoCanWriteCfg;
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Streams the current user's schedules from Firestore — THE app-wide source of
/// truth (SchedulesNotifier and all 14 consumers read through it). Reads via
/// [effectiveUserUidProvider] so installer impersonation transparently scopes
/// the stream to the chosen customer's account.
///
/// A-5 read-path flip: the stream is now sourced from
/// [scheduleRepositoryProvider], which the schedules_subcollection flag selects:
///   • flag OFF (default) → LegacyArrayScheduleRepository — the byte-identical
///     legacy array snapshot stream (unchanged behavior).
///   • flag ON → SubcollectionScheduleRepository — the /schedules subcollection
///     listener, ordered by sortKey (== insertion order; proven equivalent in
///     A-5-prime), so no consumer logic changes.
///
/// Under flag ON we first run the lazy-migration safety net so a user the
/// server backfill hasn't reached yet is migrated (array → subcollection,
/// sortKey = array index) BEFORE their subcollection is read — otherwise they'd
/// momentarily read an empty list. A migration failure is logged, never
/// surfaced: we fall through and read the subcollection as-is (the unset marker
/// makes it retry next launch).
final userSchedulesStreamProvider = StreamProvider<List<ScheduleItem>>((ref) async* {
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null) return;

  final repo = ref.watch(scheduleRepositoryProvider);
  final subEnabled = ref.watch(schedulesSubcollectionEnabledSyncProvider);

  if (subEnabled) {
    try {
      await ref.read(scheduleLazyMigratorProvider).ensureMigrated(uid);
    } catch (e) {
      debugPrint(
          'userSchedulesStream: lazy migration failed — $e (reading subcollection as-is)');
    }
  }

  yield* repo.streamSchedules(uid);
});

/// Notifier that manages schedule state and syncs with Firestore.
/// All mutations use optimistic local updates with revert-on-failure,
/// automatic retry, server verification, and user-visible error reporting.
class SchedulesNotifier extends StateNotifier<List<ScheduleItem>> {
  final Ref _ref;
  bool _initialized = false;

  /// Guard flag: while a local mutation is being persisted to Firestore,
  /// suppress stream-listener overwrites to prevent flash-back-to-old-data.
  bool _isMutating = false;

  /// Debounces WLED sync after schedule mutations. A burst of writes
  /// (autopilot 7-day fan-out, batched manual edits) coalesces into a
  /// single /json/cfg push.
  Timer? _syncDebounceTimer;

  /// Session guard for the one-time solar-timer cleanup (P0 hour:24/25). The
  /// cross-session, per-account gate is a SharedPreferences flag; this only
  /// avoids re-attempting within a single app session once a terminal state
  /// (cleaned / already-done / no-solar / failed) is reached. Left open on an
  /// off-LAN deferral so a LAN connect later this session still retries.
  bool _solarCleanupAttemptedThisSession = false;

  SchedulesNotifier(this._ref) : super([]) {
    _init();
  }

  @override
  void dispose() {
    _syncDebounceTimer?.cancel();
    super.dispose();
  }

  // ─── WLED sync wiring ──────────────────────────────────────────
  //
  // Auto-sync to the controller lives here (not in any widget) so every
  // schedule mutation — Lumina chat, autopilot, calendar collapse,
  // manual entry — reaches WLED without the user navigating to My
  // Schedule. The widget-scoped ref.listen previously in
  // _MySchedulePageState was torn down whenever that page wasn't
  // mounted, so schedules created from other surfaces never pushed.

  /// Schedule a WLED sync ~800ms after the most recent mutation.
  /// Each call cancels the previous timer so back-to-back writes
  /// (autopilot 7-day fan-out, rapid manual edits) collapse into one
  /// /json/cfg push. Sync failures are logged but never rethrown —
  /// a controller-side problem must never block the Firestore write.
  void _triggerWledSync() {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(const Duration(milliseconds: 800), _runWledSync);
  }

  /// Immediate sync — bypasses the debounce. Used by the manual
  /// Sync button in My Schedule (the user's escape hatch when they
  /// want to force a push without waiting on the 800ms coalesce).
  Future<ScheduleSyncResult> runSyncNow() async {
    _syncDebounceTimer?.cancel();
    return _runWledSync();
  }

  Future<ScheduleSyncResult> _runWledSync() async {
    try {
      final ref = _ref;
      final service = ref.read(scheduleSyncServiceProvider);
      final result = await service.syncAll(ref, state);
      if (result.success) {
        debugPrint(
            'SchedulesNotifier: WLED sync OK — ${state.length} schedules pushed');
      } else {
        debugPrint(
            'SchedulesNotifier: WLED sync failed — ${result.error ?? "unknown"}');
      }
      return result;
    } catch (e) {
      debugPrint('SchedulesNotifier: WLED sync threw — $e');
      return ScheduleSyncResult(
        success: false,
        error: 'Sync exception: $e',
      );
    }
  }

  Future<void> _init() async {
    // Listen to the stream provider for initial data and updates
    _ref.listen<AsyncValue<List<ScheduleItem>>>(
      userSchedulesStreamProvider,
      (previous, next) {
        next.whenData((schedules) {
          // Skip stream updates while a local mutation is in-flight
          if (_isMutating) return;
          if (!_initialized || !_listEquals(state, schedules)) {
            state = schedules;
            _initialized = true;
            debugPrint('SchedulesNotifier: Loaded ${schedules.length} schedules from Firestore');
            // One-time solar-timer cleanup (P0 hour:24/25): now that schedules
            // are loaded, attempt the LAN re-sync that clears stale hour:24/25
            // timers. Fire-and-forget; internally gated + idempotent.
            unawaited(maybeRunSolarCleanup());
          }
        });
      },
      fireImmediately: true,
    );

    // Also fire the cleanup when a LAN controller becomes reachable — cfg
    // writes only land on LAN, so a user who launched off-LAN (or before the
    // controller connected) gets remediated the moment they're home. Idempotent
    // and session-guarded, so this is safe on every connect.
    _ref.listen<WledRepository?>(wledRepositoryProvider, (prev, next) {
      if (next != null && repoCanWriteCfg(next)) {
        unawaited(maybeRunSolarCleanup());
      }
    });
  }

  /// One-time, LAN-only remediation of stale solar (hour:24/25) timers left on
  /// a controller before the Commit-2 refuse. Fire-and-forget and safe to call
  /// on every schedule-load and LAN-connect: a per-account SharedPreferences
  /// flag is the cross-session gate and [_solarCleanupAttemptedThisSession] the
  /// within-session one. SILENT — no user-facing surface; off-LAN defers and
  /// retries next LAN launch. See memory/project_solar_schedules_never_fire.
  Future<SolarCleanupOutcome> maybeRunSolarCleanup() async {
    if (!_initialized) return SolarCleanupOutcome.noSolar; // wait for schedules
    if (_solarCleanupAttemptedThisSession) {
      return SolarCleanupOutcome.alreadyDone;
    }
    final uid = _ref.read(effectiveUserUidProvider);
    if (uid == null) return SolarCleanupOutcome.noSolar;

    // Cheap in-memory gate first — most accounts have no solar schedules, so
    // they never touch SharedPreferences or the network.
    if (!scheduleListHasSolar(state)) return SolarCleanupOutcome.noSolar;

    final prefs = await SharedPreferences.getInstance();
    final key = 'solar_cleanup_done_$uid';
    final repo = _ref.read(wledRepositoryProvider);

    final outcome = await runSolarScheduleCleanupIfNeeded(
      alreadyDone: prefs.getBool(key) ?? false,
      schedules: state,
      onLan: repo != null && repoCanWriteCfg(repo),
      runSync: runSyncNow,
      markDone: () async => prefs.setBool(key, true),
    );

    // Latch the session guard for every terminal state EXCEPT an off-LAN
    // deferral — that one must retry when the LAN connect listener fires.
    if (outcome != SolarCleanupOutcome.deferredOffLan) {
      _solarCleanupAttemptedThisSession = true;
    }
    if (outcome == SolarCleanupOutcome.cleaned) {
      debugPrint('SchedulesNotifier: solar-timer cleanup re-sync OK — stale '
          'hour:24/25 timers reclaimed on the controller');
    }
    return outcome;
  }

  /// Deep-compare two schedule lists by ID and enabled state.
  static bool _listEquals(List<ScheduleItem> a, List<ScheduleItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].enabled != b[i].enabled) return false;
    }
    return true;
  }

  String? get _userId {
    return _ref.read(authStateProvider).maybeWhen(
          data: (u) => u?.uid,
          orElse: () => null,
        );
  }

  // ─── Error surfacing ───────────────────────────────────────────

  /// Shows a persistent snackbar with a retry action when a schedule
  /// write fails after all automatic retries. Surfaces the underlying
  /// Firestore error code (permission-denied, not-found, unavailable, …)
  /// so installers can diagnose without checking logs.
  void _showSaveError(String operation, Object error, VoidCallback retry) {
    final messenger = AppRouter.scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final detail = _humanizeWriteError(error);

    messenger.showSnackBar(
      SnackBar(
        content: Text("Schedule couldn't be saved — $detail"),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'RETRY',
          onPressed: retry,
        ),
      ),
    );
  }

  /// Map a write exception to a short user-facing string. Preserves the
  /// Firestore error code so it shows up in support reports, but with
  /// plain-English context for the most common cases.
  static String _humanizeWriteError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'permission denied. The account may be missing required '
              'fields or the Firestore rules rejected the write '
              '(${error.code}).';
        case 'not-found':
          return 'your account record was not found in the database '
              '(${error.code}).';
        case 'unavailable':
          return 'the server is unreachable — check your connection '
              '(${error.code}).';
        case 'unauthenticated':
          return 'your session expired — please sign out and back in '
              '(${error.code}).';
        default:
          return 'Firestore error: ${error.code} ${error.message ?? ''}'
              .trim();
      }
    }
    return 'unexpected error: $error';
  }

  /// True when [item]'s repeatDays arm a real WLED timer (nonzero dow mask).
  /// An empty or all-unrecognized set produces dow:0 — a timer that occupies a
  /// slot but never fires — so those are refused before persist. Policy:
  /// refuse-and-warn, never silently normalize to daily. Delegates to the
  /// canonical [wledDowMaskForDayList] so this stays in lock-step with the
  /// arm-boundary guard in ScheduleSyncService.
  static bool _hasArmableDays(ScheduleItem item) =>
      wledDowMaskForDayList(item.repeatDays) != 0;

  /// Surface a validation error to the user via the app-level messenger.
  void _showValidationError(String message) {
    final messenger = AppRouter.scaffoldMessengerKey.currentState;
    messenger?.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 6),
    ));
  }

  // ─── Conflict detection ─────────────────────────────────────────

  /// Check for conflicts before adding a schedule.
  /// Returns info the caller can pass to [showScheduleConflictDialog].
  ScheduleConflictInfo checkConflictsForAdd(ScheduleItem item,
      {String? excludeId}) {
    final calEntries = _ref.read(calendarScheduleProvider);
    return ScheduleConflictInfo(
      conflictingItems: ScheduleConflictDetector.findItemConflicts(
        incoming: item,
        existing: state,
        excludeId: excludeId,
      ),
      conflictingEntryKeys: ScheduleConflictDetector.findEntryConflictsForItem(
        item: item,
        calendarEntries: calEntries,
      ),
      calendarEntries: calEntries,
    );
  }

  /// Aggregate conflict pre-check for a batch addAll. Detects both:
  ///   • batch-vs-existing — each item's overlap with already-persisted
  ///     ScheduleItems and CalendarEntries
  ///   • intra-batch — two items in the SAME batch colliding with each
  ///     other (e.g. compound dispatcher emits "7pm Mon-Fri" and "7:30pm
  ///     Mon-Fri" — overlapping windows on shared days)
  ///
  /// Returns one merged [ScheduleConflictInfo] so a single dialog can
  /// surface every conflict at once. No dialog is shown here — the caller
  /// (compound handler) decides UX.
  ///
  /// [excludeIds] lets the caller suppress siblings already considered
  /// part of the batch (used when editing one item of a compound set).
  ScheduleConflictInfo checkConflictsForAddAll(List<ScheduleItem> items,
      {Set<String>? excludeIds}) {
    if (items.isEmpty) return const ScheduleConflictInfo();

    final calEntries = _ref.read(calendarScheduleProvider);
    final excluded = excludeIds ?? const <String>{};

    // Dedupe by ScheduleItem.id so the same already-persisted conflict
    // surfaced by multiple batch items isn't listed twice in the dialog.
    final mergedItemConflicts = <String, ScheduleItem>{};
    final mergedEntryKeys = <String>{};

    // Batch-vs-existing: each item vs already-persisted state.
    for (final item in items) {
      final hits = ScheduleConflictDetector.findItemConflicts(
        incoming: item,
        existing: state,
      );
      for (final c in hits) {
        if (excluded.contains(c.id)) continue;
        mergedItemConflicts[c.id] = c;
      }
      mergedEntryKeys.addAll(
        ScheduleConflictDetector.findEntryConflictsForItem(
          item: item,
          calendarEntries: calEntries,
        ),
      );
    }

    // Intra-batch: pairwise check among the items themselves. If item j
    // (j > i) collides with item i, BOTH are listed so the user sees what
    // their compound prompt produced.
    final intraBatch = <String, ScheduleItem>{};
    for (int i = 0; i < items.length; i++) {
      final earlierSlice = items.sublist(0, i);
      final hits = ScheduleConflictDetector.findItemConflicts(
        incoming: items[i],
        existing: earlierSlice,
      );
      if (hits.isNotEmpty) {
        intraBatch[items[i].id] = items[i];
        for (final c in hits) {
          intraBatch[c.id] = c;
        }
      }
    }
    // Intra-batch items belong in the conflict list too — the user must
    // see them next to the existing-state conflicts, not in a separate
    // surface.
    for (final entry in intraBatch.entries) {
      if (excluded.contains(entry.key)) continue;
      mergedItemConflicts[entry.key] = entry.value;
    }

    return ScheduleConflictInfo(
      conflictingItems: mergedItemConflicts.values.toList(),
      conflictingEntryKeys: mergedEntryKeys.toList(),
      calendarEntries: calEntries,
    );
  }

  // ─── Sort-key assignment (A-5-prime) ───────────────────────────

  /// THE single place client-created schedules receive their monotonic
  /// per-user [ScheduleItem.sortKey]. Every create path on this notifier
  /// (add / addAll / mergeWithDedup / replaceAll) routes new items through
  /// here, so manual entry, autopilot merge, commercial events, and the AI
  /// intent handler all get consistent keys without each caller knowing about
  /// ordering.
  ///
  /// Any item lacking a positive sortKey is stamped with a contiguous,
  /// increasing key starting at (max sortKey over current [state]) + 1 — so
  /// subcollection reads (ordered by sortKey) reproduce the legacy array's
  /// insertion order. Items that ALREADY carry a positive sortKey (e.g. an
  /// existing item re-persisted through a full-overwrite path) keep it. List
  /// order within [items] is preserved as a contiguous block (intra-batch
  /// order intact). Runs under both flag states — harmless when the legacy
  /// array backend ignores order, ready when the subcollection backend uses it.
  List<ScheduleItem> _assignSortKeys(List<ScheduleItem> items) {
    var nextKey = nextSortKeySeed(state);
    return [
      for (final item in items)
        item.sortKey > 0 ? item : item.copyWith(sortKey: nextKey++),
    ];
  }

  /// First key handed to a newly created item, seeded from [current] state.
  ///
  /// Normally (max sortKey) + 1. The `current.length` floor is belt-and-braces
  /// against a backfill gap: a user whose ARRAY items predate the sortKey field
  /// deserializes to all-zero (`ScheduleItem.fromJson: ?? 0`), so the max-based
  /// seed collapses to 1 — which COLLIDES with the contiguous 0..n-1 the
  /// array→subcollection backfill already stamped into their subcollection. The
  /// mirrored write would then tie on `sortKey`, and the subcollection's
  /// orderBy read would diverge from the array's insertion order. Seeding at no
  /// less than the item count clears a contiguous backfilled block.
  ///
  /// This is a safety net, not a proof: it assumes the backfill's contiguous
  /// 0..n-1 numbering and array/subcollection count parity (both hold for every
  /// user the real backfill touched). The actual repair is making the array
  /// carry the same keys as the subcollection — see
  /// functions/scripts/repair_array_sortkeys.js. The floor never LOWERS the
  /// seed, so it can never collide with a key already present in [current].
  @visibleForTesting
  static int nextSortKeySeed(List<ScheduleItem> current) {
    final byMax = _maxSortKey(current) + 1;
    return byMax > current.length ? byMax : current.length;
  }

  static int _maxSortKey(List<ScheduleItem> items) {
    var max = 0;
    for (final s in items) {
      if (s.sortKey > max) max = s.sortKey;
    }
    return max;
  }

  // ─── Mutations ─────────────────────────────────────────────────

  /// Toggle a schedule's enabled state
  Future<void> toggle(String id, bool value) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot toggle - no user signed in');
      return;
    }

    _isMutating = true;

    // Store previous state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(enabled: value) else s,
    ];

    // Persist to Firestore — throws on failure after retries.
    final schedule = state.firstWhere((s) => s.id == id);
    try {
      await _ref.read(userServiceProvider).updateSchedule(userId, schedule);
      debugPrint('Schedule $id toggled to $value and saved');
      _triggerWledSync();
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist toggle — reverting: $e');
      state = oldState;
      _showSaveError('toggle', e, () => toggle(id, value));
    }

    _isMutating = false;
  }

  /// Add a new schedule.
  /// Pass [resolution] after showing the conflict dialog to handle overlaps.
  Future<void> add(ScheduleItem rawItem,
      {ConflictResolution? resolution}) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot add - no user signed in');
      return;
    }

    // A-5-prime: stamp the monotonic ordering key before anything persists.
    final item = _assignSortKeys([rawItem]).first;

    // Refuse-and-warn: a schedule with no valid repeat days would arm a WLED
    // timer that never fires (dow:0). Don't persist it. (Manual picker and AI
    // handler already block this upstream; persistence-layer backstop.)
    if (!_hasArmableDays(item)) {
      debugPrint('SchedulesNotifier: refusing add — "${item.actionLabel}" '
          'has no valid repeat days (${item.repeatDays})');
      _showValidationError(
          "Pick at least one repeat day — the schedule won't run without one.");
      return;
    }

    // ── Conflict resolution (before optimistic update) ───────────
    if (resolution == ConflictResolution.cancel) return;
    if (resolution == ConflictResolution.removeExisting) {
      final conflicts = checkConflictsForAdd(item);
      for (final c in conflicts.conflictingItems) {
        await remove(c.id);
      }
      final calNotifier = _ref.read(calendarScheduleProvider.notifier);
      for (final key in conflicts.conflictingEntryKeys) {
        await calNotifier.removeEntry(key);
      }
    }

    _isMutating = true;

    // Store previous state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = [...state, item];

    // Persist to Firestore — throws on failure after retries.
    try {
      await _ref.read(userServiceProvider).addSchedule(userId, item);
      debugPrint('Schedule added and saved: ${item.id}');
      _triggerWledSync();
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist add — reverting: $e');
      state = oldState;
      _showSaveError('add', e, () => add(item));
    }

    _isMutating = false;
  }

  /// Atomically add multiple schedules in a single Firestore write.
  ///
  /// All-or-nothing: either every item persists or none do. Designed for
  /// compound user-intent batches where partial success would leave the
  /// user with an incoherent schedule (e.g. one Lumina prompt → 3 sibling
  /// ScheduleItems sharing the same `sourcePromptId` provenance stamp).
  ///
  /// Differs from [mergeWithDedup] (autopilot path) in three ways:
  ///   • Persists every item verbatim — no dedup against existing items.
  ///   • Single arrayUnion write rather than full-field overwrite, so it
  ///     doesn't clobber concurrent autopilot/manual writes — EXCEPT when the
  ///     50-item cap (shared with [mergeWithDedup]) requires trimming, in which
  ///     case it falls back to a full overwrite to drop the oldest entries.
  ///
  /// Pass [resolution] after showing the conflict dialog to handle overlaps,
  /// same convention as [add].
  /// Returns `true` only when the batch is confirmed persisted to Firestore;
  /// `false` when the write failed (state is reverted and a retry error is
  /// surfaced) or no user is signed in. Callers driving a "scheduled"
  /// confirmation MUST branch on this — a failed write previously returned
  /// normally, letting the UI claim success with no row written.
  Future<bool> addAll(List<ScheduleItem> items,
      {ConflictResolution? resolution}) async {
    if (items.isEmpty) return true; // nothing to write — vacuously fine

    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot addAll - no user signed in');
      return false;
    }

    // Refuse-and-warn: reject the batch if any item has no valid repeat days
    // (dow:0 would never fire). Upstream flows (AI handler, manual picker)
    // already filter these; this is the persistence-layer backstop.
    final badDays = items.where((i) => !_hasArmableDays(i)).toList();
    if (badDays.isNotEmpty) {
      debugPrint('SchedulesNotifier: refusing addAll — ${badDays.length} '
          'item(s) have no valid repeat days');
      _showValidationError(
          "Some schedules had no repeat days set and weren't added — pick at "
          "least one day.");
      return false;
    }

    // ── Conflict resolution (before optimistic update) ───────────
    if (resolution == ConflictResolution.cancel) return false;
    if (resolution == ConflictResolution.removeExisting) {
      final conflicts = checkConflictsForAddAll(items);
      for (final c in conflicts.conflictingItems) {
        await remove(c.id);
      }
      final calNotifier = _ref.read(calendarScheduleProvider.notifier);
      for (final key in conflicts.conflictingEntryKeys) {
        await calNotifier.removeEntry(key);
      }
    }

    _isMutating = true;

    // Capture oldState ONCE before the optimistic push so a partial-failure
    // revert restores every item together.
    final oldState = List<ScheduleItem>.from(state);

    // A-5-prime: stamp a contiguous, increasing sortKey block so the batch's
    // intra-order is preserved under the subcollection backend. Computed after
    // conflict-resolution removals so the base reflects the trimmed state.
    final stamped = _assignSortKeys(items);

    // Hard cap at 50 schedules — same bound (and keep-newest trim) as
    // [mergeWithDedup], applied here so compound AI batches can't grow the
    // user-doc array unbounded. Existing first, new items appended last, so
    // skip(removed) drops the OLDEST and keeps the most recently created 50
    // (identical semantics to mergeWithDedup's trim). Interim protection on
    // the array shape; the subcollection migration (#TD-1) is unaffected.
    const maxSchedules = 50;
    var combined = [...oldState, ...stamped];
    final needsTrim = combined.length > maxSchedules;
    if (needsTrim) {
      final removed = combined.length - maxSchedules;
      combined = combined.skip(removed).toList();
      debugPrint(
          'SchedulesNotifier: addAll cap enforced — trimmed $removed entries to stay at $maxSchedules');
    }

    // Single optimistic push — listeners see the (possibly trimmed) batch
    // atomically.
    state = combined;

    // Outcome propagates to the caller (the confirm flow) — we still revert
    // optimistic state + surface a retry error on failure, we just no longer
    // hide whether the write actually committed.
    bool ok;
    try {
      // arrayUnion (append-only) can't drop the oldest entries, so when the cap
      // requires trimming, persist the full trimmed set instead. The common
      // (uncapped) path keeps the non-clobbering arrayUnion write.
      if (needsTrim) {
        await _ref.read(userServiceProvider).saveSchedules(userId, combined);
      } else {
        await _ref.read(userServiceProvider).addSchedules(userId, stamped);
      }
      debugPrint(
          'SchedulesNotifier: addAll persisted ${items.length} items atomically'
          '${needsTrim ? ' (trimmed to $maxSchedules total)' : ''}');
      _triggerWledSync();
      ok = true;
    } catch (e) {
      debugPrint(
          'SchedulesNotifier: Failed to persist addAll — reverting all ${items.length} items: $e');
      state = oldState;
      _showSaveError('addAll', e, () => addAll(items, resolution: resolution));
      ok = false;
    }

    _isMutating = false;
    return ok;
  }

  /// Remove a schedule by ID
  Future<void> remove(String id) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot remove - no user signed in');
      return;
    }

    _isMutating = true;

    // Store previous state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = state.where((s) => s.id != id).toList();

    // Persist to Firestore — throws on failure after retries.
    try {
      await _ref.read(userServiceProvider).removeSchedule(userId, id);
      debugPrint('Schedule removed and saved: $id');
      _triggerWledSync();
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist remove — reverting: $e');
      state = oldState;
      _showSaveError('remove', e, () => remove(id));
    }

    _isMutating = false;
  }

  /// Update an existing schedule
  Future<void> update(ScheduleItem item) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot update - no user signed in');
      return;
    }

    // A-5-prime: an edit must never reset the ordering key. If the editor
    // reconstructed the item without a sortKey (0), inherit the existing
    // item's key so its subcollection position stays stable.
    if (item.sortKey <= 0) {
      final existing = state.where((s) => s.id == item.id);
      if (existing.isNotEmpty) {
        item = item.copyWith(sortKey: existing.first.sortKey);
      }
    }

    _isMutating = true;

    // Store previous state for revert
    final oldState = List<ScheduleItem>.from(state);

    // Optimistically update local state
    state = [for (final s in state) if (s.id == item.id) item else s];

    // Persist to Firestore — throws on failure after retries.
    try {
      await _ref.read(userServiceProvider).updateSchedule(userId, item);
      debugPrint('Schedule updated and saved: ${item.id}');
      _triggerWledSync();
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist update — reverting: $e');
      state = oldState;
      _showSaveError('update', e, () => update(item));
    }

    _isMutating = false;
  }

  /// Replace all schedules (used by Autopilot)
  Future<void> replaceAll(List<ScheduleItem> schedules) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot replace - no user signed in');
      return;
    }

    _isMutating = true;

    // Store old state for revert
    final oldState = List<ScheduleItem>.from(state);

    // A-5-prime: autopilot builds fresh items (sortKey 0); stamp them in list
    // order so the regenerated set keeps its intended ordering under the
    // subcollection backend. Items already carrying a positive key keep it.
    schedules = _assignSortKeys(schedules);

    // Optimistically update local state
    state = schedules;

    // Persist to Firestore — throws on failure after retries.
    try {
      await _ref.read(userServiceProvider).saveSchedules(userId, schedules);
      debugPrint('All schedules replaced and saved: ${schedules.length} items');
      _triggerWledSync();
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist replaceAll — reverting: $e');
      state = oldState;
      _showSaveError('replaceAll', e, () => replaceAll(schedules));
    }

    _isMutating = false;
  }

  /// Merge multiple schedules with dedup + cap (used by Autopilot).
  ///
  /// Not a plain "add everything I give you" — this path is autopilot-shaped:
  /// dedups by id AND by content fingerprint (timeLabel, offTimeLabel,
  /// repeatDays, actionLabel, enabled), enforces a 50-item cap by trimming
  /// the oldest entries, and writes via `saveSchedules` (full-field
  /// overwrite). Content-fingerprint dedup is the load-bearing one for
  /// autopilot: AutopilotGenerationService stamps fresh UUIDs on every regen,
  /// so id-only dedup lets duplicate items slip in whenever two regen paths
  /// fire close together (e.g. boot-time runAutopilotRegenIfNeeded racing
  /// with the schedule page's _maybeAutoTrigger).
  ///
  /// For compound user-intent batches (e.g. one Lumina prompt → N schedules)
  /// a separate atomic batch path is being introduced — it persists every
  /// item verbatim, no dedup, no cap, all-or-nothing atomic revert.
  /// Returns `true` when the merged set is confirmed persisted (or when every
  /// item was already present so there was nothing to write); `false` when the
  /// Firestore write failed (state reverted, retry error surfaced) or no user
  /// is signed in. Lets a caller-driven confirmation branch on the real
  /// outcome instead of assuming success.
  Future<bool> mergeWithDedup(List<ScheduleItem> items) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('SchedulesNotifier: Cannot mergeWithDedup - no user signed in');
      return false;
    }

    _isMutating = true;

    final oldState = List<ScheduleItem>.from(state);

    bool isDuplicate(ScheduleItem item) => state.any((e) =>
        e.id == item.id ||
        (e.timeLabel == item.timeLabel &&
            e.offTimeLabel == item.offTimeLabel &&
            e.repeatDays.join(',') == item.repeatDays.join(',') &&
            e.actionLabel == item.actionLabel &&
            e.enabled == item.enabled));
    final newItems = items.where((i) => !isDuplicate(i)).toList();

    if (newItems.isEmpty) {
      debugPrint(
          'SchedulesNotifier: mergeWithDedup skipped — all ${items.length} items already present');
      _isMutating = false;
      return true; // already present = nothing to persist, not a failure
    }

    // A-5-prime: stamp a contiguous ordering block for the surviving new items.
    final stampedNew = _assignSortKeys(newItems);

    var merged = [...state, ...stampedNew];

    // Hard cap at 50 schedules. Defends against runaway autopilot regen
    // loops appending duplicates faster than dedup can catch them — keeps
    // the user doc bounded so Firestore reads don't bloat. Trimming keeps
    // the most recently appended entries (last in the array).
    const maxSchedules = 50;
    if (merged.length > maxSchedules) {
      final removed = merged.length - maxSchedules;
      merged = merged.skip(removed).toList();
      debugPrint(
          'Schedule cap enforced — trimmed $removed entries to stay at $maxSchedules');
    }

    state = merged;

    // Persist to Firestore — propagate the outcome so the caller never claims
    // success on a reverted write.
    bool ok;
    try {
      await _ref.read(userServiceProvider).saveSchedules(userId, merged);
      debugPrint(
          'Merged ${newItems.length} new schedules (filtered ${items.length - newItems.length} duplicates), total: ${merged.length}');
      _triggerWledSync();
      ok = true;
    } catch (e) {
      debugPrint('SchedulesNotifier: Failed to persist mergeWithDedup — reverting: $e');
      state = oldState;
      _showSaveError('mergeWithDedup', e, () => mergeWithDedup(items));
      ok = false;
    }

    _isMutating = false;
    return ok;
  }

  // ─── Persistence health check ──────────────────────────────────

  /// Verifies local schedule state matches the Firestore server.
  /// Runs on app launch to catch any prior sync failures.
  /// Trusts the server as the source of truth on mismatch.
  Future<void> verifyPersistence() async {
    final userId = _userId;
    if (userId == null) return;

    try {
      final serverSchedules = await _ref
          .read(userServiceProvider)
          .fetchSchedulesFromServer(userId);

      if (!_listEquals(state, serverSchedules)) {
        debugPrint(
          'SchedulesNotifier: Cache/server mismatch — '
          'local=${state.length}, server=${serverSchedules.length}. '
          'Resyncing from server.',
        );
        state = serverSchedules;
      } else {
        debugPrint('SchedulesNotifier: Persistence verified — ${state.length} schedules in sync');
      }
    } catch (e) {
      debugPrint('SchedulesNotifier: Persistence check failed (offline?): $e');
    }
  }
}

final schedulesProvider = StateNotifierProvider<SchedulesNotifier, List<ScheduleItem>>(
  (ref) => SchedulesNotifier(ref),
);

/// Helper class to find what schedule should be running at a given time.
/// Handles parsing of schedule times including sunrise/sunset triggers.
class ScheduleFinder {
  /// Finds the schedule that should currently be active based on on/off times.
  /// Returns null if no schedule is currently active.
  ///
  /// Logic:
  /// 1. Check CalendarEntry for today (date-specific override, highest priority)
  /// 2. Filter recurring schedules that apply to today's day of week
  /// 3. For each schedule, check if we're within its on/off window
  /// 4. If a schedule has no off time, it stays active until another schedule starts
  /// 5. Return the most recently started schedule that is still active
  static ScheduleItem? findCurrentSchedule(
    List<ScheduleItem> schedules,
    DateTime now, {
    double? latitude,
    double? longitude,
    Map<String, CalendarEntry>? calendarEntries,
  }) {
    // Date-specific entries take priority over recurring schedules for today
    if (calendarEntries != null) {
      final todayKey = calendarDateKey(now);
      final entry = calendarEntries[todayKey];
      if (entry != null && entry.brightness > 0 && entry.onTime != null) {
        final onParts = entry.onTime!.split(':');
        if (onParts.length == 2) {
          final onHour = int.tryParse(onParts[0]) ?? 0;
          final onMinute = int.tryParse(onParts[1]) ?? 0;
          final onDt = DateTime(now.year, now.month, now.day, onHour, onMinute);

          if (!now.isBefore(onDt)) {
            // Check off time (if any)
            bool withinWindow = true;
            if (entry.offTime != null) {
              final offParts = entry.offTime!.split(':');
              if (offParts.length == 2) {
                final offHour = int.tryParse(offParts[0]) ?? 0;
                final offMinute = int.tryParse(offParts[1]) ?? 0;
                final offDt = DateTime(now.year, now.month, now.day, offHour, offMinute);

                // Same-day window: on < off means off is today
                if (offDt.isAfter(onDt)) {
                  withinWindow = now.isBefore(offDt);
                }
                // Overnight window (off <= on): always active after onTime today
              }
            }

            if (withinWindow) {
              // Synthesise a ScheduleItem so downstream consumers work unchanged
              final onLabel =
                  '${onHour == 0 ? 12 : onHour > 12 ? onHour - 12 : onHour}:'
                  '${onMinute.toString().padLeft(2, '0')} '
                  '${onHour < 12 ? 'AM' : 'PM'}';
              String? offLabel;
              if (entry.offTime != null) {
                final offParts = entry.offTime!.split(':');
                if (offParts.length == 2) {
                  final oh = int.tryParse(offParts[0]) ?? 0;
                  final om = int.tryParse(offParts[1]) ?? 0;
                  offLabel =
                      '${oh == 0 ? 12 : oh > 12 ? oh - 12 : oh}:'
                      '${om.toString().padLeft(2, '0')} '
                      '${oh < 12 ? 'AM' : 'PM'}';
                }
              }

              return ScheduleItem(
                id: 'cal_${entry.dateKey}',
                timeLabel: onLabel,
                offTimeLabel: offLabel,
                repeatDays: const [],
                actionLabel: 'Pattern: ${entry.patternName}',
                enabled: true,
              );
            }
          }
        }
      }
    }

    if (schedules.isEmpty) return null;

    // Get today's day abbreviation (Sun, Mon, Tue, Wed, Thu, Fri, Sat)
    final dayAbbrs = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final todayAbbr = dayAbbrs[now.weekday % 7].toLowerCase();
    final yesterdayAbbr = dayAbbrs[(now.weekday - 1 + 7) % 7].toLowerCase();

    // Helper to check if schedule applies to a day
    bool appliesToDay(ScheduleItem s, String dayAbbr) {
      final daysLower = s.repeatDays.map((d) => d.toLowerCase()).toList();
      if (daysLower.contains('daily')) return true;
      return daysLower.any((d) => d.startsWith(dayAbbr));
    }

    // Filter to enabled schedules that apply to today or yesterday (for overnight schedules)
    final candidateSchedules = schedules.where((s) {
      if (!s.enabled) return false;
      return appliesToDay(s, todayAbbr) || appliesToDay(s, yesterdayAbbr);
    }).toList();

    if (candidateSchedules.isEmpty) return null;

    ScheduleItem? activeSchedule;
    DateTime? activeOnTime;

    for (final schedule in candidateSchedules) {
      // Check if this schedule started today
      if (appliesToDay(schedule, todayAbbr)) {
        final onTime = _parseTimeLabel(schedule.timeLabel, now, latitude, longitude);
        if (onTime == null) continue;

        // Has the on time passed?
        if (onTime.isAfter(now)) continue;

        // If there's an off time, check if we're still within the window
        if (schedule.hasOffTime && schedule.offTimeLabel != null) {
          final offTime = _parseTimeLabel(schedule.offTimeLabel!, now, latitude, longitude);
          if (offTime != null) {
            // Handle overnight schedules (off time is before on time = next day)
            final isOvernight = offTime.isBefore(onTime) || offTime.isAtSameMomentAs(onTime);
            if (isOvernight) {
              // Off time is tomorrow, so we're still active if we've passed on time
              // (We'll check yesterday's schedule separately)
            } else {
              // Same-day schedule: check if off time has passed
              if (now.isAfter(offTime)) continue; // Already turned off
            }
          }
        }

        // This schedule is active - check if it's more recent than others
        if (activeOnTime == null || onTime.isAfter(activeOnTime)) {
          activeOnTime = onTime;
          activeSchedule = schedule;
        }
      }

      // Check if this is an overnight schedule that started yesterday
      if (appliesToDay(schedule, yesterdayAbbr) && schedule.hasOffTime) {
        final yesterday = now.subtract(const Duration(days: 1));
        final onTime = _parseTimeLabel(schedule.timeLabel, yesterday, latitude, longitude);
        final offTime = _parseTimeLabel(schedule.offTimeLabel!, now, latitude, longitude);

        if (onTime == null || offTime == null) continue;

        // Check if this is an overnight schedule (off time would be "today")
        final isOvernight = offTime.hour < onTime.hour ||
            (offTime.hour == onTime.hour && offTime.minute <= onTime.minute);

        if (isOvernight) {
          // The off time is today - check if it hasn't passed yet
          if (now.isBefore(offTime)) {
            // This overnight schedule is still active
            // Use yesterday's on time for comparison
            if (activeOnTime == null || onTime.isAfter(activeOnTime)) {
              activeOnTime = onTime;
              activeSchedule = schedule;
            }
          }
        }
      }
    }

    return activeSchedule;
  }

  /// Parses a time label into an actual DateTime for a given day.
  /// Handles:
  /// - "Sunset" / "Sunrise" (requires lat/lon)
  /// - "7:00 PM", "10:30 AM" etc.
  static DateTime? _parseTimeLabel(
    String label,
    DateTime day,
    double? latitude,
    double? longitude,
  ) {
    final trimmed = label.trim().toLowerCase();

    // Handle solar events
    if (trimmed == 'sunset') {
      if (latitude == null || longitude == null) return null;
      return SunUtils.sunsetLocal(latitude, longitude, day);
    }
    if (trimmed == 'sunrise') {
      if (latitude == null || longitude == null) return null;
      return SunUtils.sunriseLocal(latitude, longitude, day);
    }

    // Parse time format like "7:00 PM", "10:30 AM"
    final timeRegex = RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)$', caseSensitive: false);
    final match = timeRegex.firstMatch(label.trim());
    if (match == null) return null;

    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    final ampm = match.group(3)!.toLowerCase();

    // Convert to 24-hour format
    if (ampm == 'pm' && hour != 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;

    return DateTime(day.year, day.month, day.day, hour, minute);
  }

}

/// Provider that returns the currently applicable schedule item based on
/// the current time and day of week.  Date-specific [CalendarEntry] overrides
/// take priority over recurring schedules.
final currentScheduledActionProvider = Provider<ScheduleItem?>((ref) {
  final schedules = ref.watch(schedulesProvider);
  final calEntries = ref.watch(calendarScheduleProvider);
  final user = ref.watch(currentUserProfileProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );

  final now = DateTime.now();
  return ScheduleFinder.findCurrentSchedule(
    schedules,
    now,
    latitude: user?.latitude,
    longitude: user?.longitude,
    calendarEntries: calEntries,
  );
});
