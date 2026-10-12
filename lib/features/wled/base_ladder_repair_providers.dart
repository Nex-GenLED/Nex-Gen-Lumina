// lib/features/wled/base_ladder_repair_providers.dart
//
// +114 — the Riverpod wiring for the on-connect ladder repair
// (base_ladder_repair.dart): where its inputs come from, where its record and
// banner status go. Everything that decides lives in the pure file; this one
// only connects it to the app.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart'
    show effectiveUserUidProvider, installerAccessingCustomerProvider;
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart'
    show AutopilotSession;
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session.dart'
    show EphemeralGameSession;
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart'
    show activeEphemeralSessionsProvider;
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status_provider.dart'
    show gameDayServerStatusSyncProvider;
import 'package:nexgen_command/features/schedule/base_ladder_repair_feature_flag.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/wled/base_ladder_denormalizer.dart'
    show publishedBaseLadderMemo;
import 'package:nexgen_command/features/wled/base_ladder_repair.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show
        controllerDefaultsHealerProvider,
        controllerFactsPublisherProvider,
        healerPhoneNowProvider;
import 'package:nexgen_command/features/wled/controller_facts_publisher.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';
import 'package:nexgen_command/features/wled/device_channel.dart'
    show deviceChannelsFromConfig;
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// `*_source` stamped on facts republished after a repair.
const String kLadderRepairPublishSource = 'ladder_repair';

// ── Game Day activity (pure core + probe) ────────────────────────────────────

/// How long a server start with no end since still counts as a game in
/// progress: kickoff plus the app's hard cap for a game whose end was never
/// confirmed — the same six hours `gameDayEntryWindow`, the priority resolver
/// and the background worker use. The server itself ends on start + the
/// estimated duration, well inside this. It used to be eight hours with no
/// relation to any cap, which held the repair off for the whole stranded
/// evening of 2026-10-05 (#177 server side, #183 app side).
const Duration kGameDayStartHardCap = Duration(hours: 6);

/// PURE. What the server's own status says about a game in progress, or null.
///
/// Read whether or not the served flag is fresh: a planner that stopped
/// writing may still have minted jobs that the dispatcher fires, so for a
/// "do not touch the controller now" question the raw data is the safe input.
///   • a start that completed less than [startCap] ago and no end since →
///     live; past the cap the game is treated as ENDED, whatever the server
///     has or has not written (#183);
///   • an END pending → the game is on;
///   • a START due within [kLadderRepairGameGuard] (or overdue) → about to fire.
String? serverLiveReasonAt(
  GameDayServerStatus s,
  DateTime now, {
  Duration startCap = kGameDayStartHardCap,
}) {
  final last = s.lastFire;
  if (last != null &&
      last.seq == 'start' &&
      last.completed &&
      last.completedAt != null &&
      now.difference(last.completedAt!) < startCap) {
    return 'our servers started a game and have not ended it yet';
  }
  final next = s.nextFire;
  if (next == null) return null;
  if (next.seq == 'end') return 'our servers will end a game in progress';
  if (next.seq == 'start' &&
      next.fireAt.difference(now) <= kLadderRepairGameGuard) {
    return 'our servers start a game at ${next.fireAt.hour}:'
        '${next.fireAt.minute.toString().padLeft(2, '0')}';
  }
  return null;
}

({int hour, int min})? _hm(String? t) {
  if (t == null) return null;
  final lower = t.trim().toLowerCase();
  // Same approximations the lease manager uses for window math; the guard
  // margin absorbs the difference.
  if (lower == 'sunrise') return (hour: 6, min: 0);
  if (lower == 'sunset') return (hour: 18, min: 0);
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mm = int.parse(m.group(2)!);
  if (h > 23 || mm > 59) return null;
  return (hour: h, min: mm);
}

/// The window a Game Day calendar entry holds the house, or null when its
/// times cannot be read. Open-ended entries run to their hard cap (or the
/// estimate, or six hours); fixed ones to their off time, wrapping midnight.
({DateTime start, DateTime end})? gameDayEntryWindow(CalendarEntry e) {
  final date = DateTime.tryParse(e.dateKey);
  final on = _hm(e.onTime);
  if (date == null || on == null) return null;
  final start = DateTime(date.year, date.month, date.day, on.hour, on.min);
  DateTime end;
  final off = _hm(e.offTime);
  if (e.isOpenEnded || off == null) {
    end = e.hardCapAt ?? e.estimatedEnd ?? start.add(const Duration(hours: 6));
  } else {
    end = DateTime(date.year, date.month, date.day, off.hour, off.min);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
  }
  return (start: start, end: end);
}

/// PURE. Everything the Game Day side knows, folded into one answer for the
/// repair guard. Any input that has not loaded makes the answer UNKNOWN —
/// which the guard treats as a refusal.
GameDayActivity gameDayActivityFrom({
  required DateTime now,
  required bool configsLoaded,
  required bool calendarLoaded,
  required Iterable<CalendarEntry> calendarEntries,
  required Iterable<AutopilotSession> autopilotSessions,
  required bool ephemeralKnown,
  required Iterable<EphemeralGameSession> ephemeralSessions,
  String? espnLiveReason,
  String? serverLiveReason,
}) {
  for (final s in autopilotSessions) {
    if (s.isActive) return GameDayActivity.live('${s.teamSlug} Game Day session is ${s.phase.name}');
  }
  for (final e in ephemeralSessions) {
    if (e.phase.isActive) return GameDayActivity.live('${e.teamSlug} live session is ${e.phase.name}');
  }
  if (espnLiveReason != null) return GameDayActivity.live(espnLiveReason);
  if (serverLiveReason != null) return GameDayActivity.live(serverLiveReason);
  for (final e in calendarEntries) {
    if (!e.holdsGameDay) continue;
    final w = gameDayEntryWindow(e);
    if (w == null) continue;
    if (!now.isBefore(w.start.subtract(kLadderRepairGameGuard)) &&
        !now.isAfter(w.end.add(kLadderRepairGameGuard))) {
      return GameDayActivity.live(
          'Game Day ${e.gameDayTeamName ?? e.patternName} holds ${e.dateKey} '
          '${e.onTime}–${e.offTime ?? 'game end'}');
    }
  }
  if (!configsLoaded) return const GameDayActivity.unknown('team list');
  if (!calendarLoaded) return const GameDayActivity.unknown('calendar');
  if (!ephemeralKnown) return const GameDayActivity.unknown('live sessions');
  return const GameDayActivity.quiet();
}

/// Reads every Game Day input at CALL time (the guard is evaluated twice, the
/// second time immediately before the first write).
final gameDayActivityProbeProvider =
    Provider<Future<GameDayActivity> Function()>((ref) {
  return () async {
    GameDayActivity fold({String? espn}) {
      final configs = ref.read(gameDayAutopilotConfigsProvider);
      final ephemeral = ref.read(activeEphemeralSessionsProvider);
      return gameDayActivityFrom(
        now: ref.read(healerPhoneNowProvider)(),
        configsLoaded: configs.hasValue,
        calendarLoaded:
            ref.read(calendarScheduleProvider.notifier).loadedFromFirestore,
        calendarEntries: ref.read(calendarScheduleProvider).allEntries,
        autopilotSessions: ref.read(gameDayAutopilotNotifierProvider).values,
        ephemeralKnown: ephemeral.hasValue,
        ephemeralSessions:
            ephemeral.valueOrNull ?? const <EphemeralGameSession>[],
        espnLiveReason: espn,
        serverLiveReason: serverLiveReasonAt(
            ref.read(gameDayServerStatusSyncProvider),
            ref.read(healerPhoneNowProvider)()),
      );
    }

    // Local signals first. ESPN is asked only once everything local has
    // loaded and says quiet — the readiness loop polls this every few
    // seconds, and a network call per team per poll would be waste.
    final local = fold();
    if (!local.known || local.liveReason != null) return local;
    return fold(espn: await ref.read(followedGameLiveReasonProvider)());
  };
});

// ── Phone-side store ─────────────────────────────────────────────────────────

const String kLadderRepairStatusKey =
    'base_ladder_repair_status.$kLadderRepairVersion';

String ladderRepairMarkerKey(String controllerId) =>
    'base_ladder_connect_repair.$kLadderRepairVersion.$controllerId';

String ladderRepairBackupKey(String controllerId) =>
    'base_ladder_backup.$kLadderRepairVersion.$controllerId';

class SharedPrefsLadderRepairStore implements LadderRepairStore {
  SharedPrefsLadderRepairStore({this.onStatus});

  /// Pushes a fresh status to the banner without waiting for a rebuild.
  final void Function(LadderRepairStatus status)? onStatus;

  @override
  Future<bool> hasRun(String controllerId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.containsKey(ladderRepairMarkerKey(controllerId));
    } catch (_) {
      // Cannot tell — treat as RAN. A one-time repair that might run twice is
      // worse than one that waits for a readable store.
      return true;
    }
  }

  @override
  Future<bool> markRan(String controllerId, Map<String, Object?> record) async {
    try {
      final p = await SharedPreferences.getInstance();
      return await p.setString(ladderRepairMarkerKey(controllerId), jsonEncode({
        ...record,
        'at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearRan(String controllerId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(ladderRepairMarkerKey(controllerId));
    } catch (_) {/* a marker that cannot be cleared waits for the next build */}
  }

  @override
  Future<bool> saveBackup(String controllerId, String backupJson) async {
    try {
      final p = await SharedPreferences.getInstance();
      final ok = await p.setString(ladderRepairBackupKey(controllerId), backupJson);
      // Read it back: "stored" means readable, not "the call returned".
      return ok && p.getString(ladderRepairBackupKey(controllerId)) == backupJson;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> readBackup(String controllerId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(ladderRepairBackupKey(controllerId));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveStatus(LadderRepairStatus status) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kLadderRepairStatusKey, jsonEncode(status.toJson()));
    } catch (_) {/* the banner is cosmetic; never fail the repair on it */}
    onStatus?.call(status);
  }
}

// ── Banner status (item 1d) ──────────────────────────────────────────────────

class LadderRepairStatusNotifier extends StateNotifier<LadderRepairStatus?> {
  LadderRepairStatusNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(kLadderRepairStatusKey);
      if (raw == null) return;
      final s = LadderRepairStatus.fromJson(jsonDecode(raw));
      if (mounted && state == null) state = s;
    } catch (_) {/* nothing to show */}
  }

  void show(LadderRepairStatus status) {
    if (mounted) state = status;
  }

  Future<void> dismiss() async {
    state = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(kLadderRepairStatusKey);
    } catch (_) {}
  }
}

/// The last repair that WROTE, until the customer dismisses it. Null when
/// there is nothing to say (never repaired, or dismissed).
final ladderRepairStatusProvider =
    StateNotifierProvider<LadderRepairStatusNotifier, LadderRepairStatus?>(
        (ref) => LadderRepairStatusNotifier());

// ── Coordinator ──────────────────────────────────────────────────────────────

typedef LadderRepairConsider = Future<LadderRepairRun?> Function({
  required FactsPublishOutcome outcome,
  required WledService svc,
  required String controllerId,
});

/// The runner, wired to the app. Shared by the connect-time coordinator and
/// the customer's own "Repair base lighting" (#183). [participating] empty
/// means every bus (the runner's default).
BaseLadderRepairRunner buildLadderRepairRunner(
  Ref ref, {
  required WledService svc,
  required String controllerId,
  required List<int> participating,
  Duration readinessTimeout = const Duration(minutes: 2),
  void Function(String step)? onProgress,
}) {
  final nowFn = ref.read(healerPhoneNowProvider);
  // The account that asked. A run whose account changes under it stops: the
  // next account's controller is not the one that was backed up.
  final uidAtStart = ref.read(effectiveUserUidProvider);
  return BaseLadderRepairRunner(LadderRepairDeps(
      svc: svc,
      controllerId: controllerId,
      participating: participating,
      now: nowFn,
      phoneUtcOffset: nowFn().timeZoneOffset,
      // Absent or unreadable config = dry run; only an explicit "repair"
      // writes (ladderRepairModeFrom). The user action ignores the mode
      // except `enabled:false` (repairNow).
      mode: () => readLadderRepairMode(
          () => ref.read(baseLadderRepairConfigProvider.future)),
      gameDay: ref.read(gameDayActivityProbeProvider),
      store: SharedPrefsLadderRepairStore(
        onStatus: (s) => ref.read(ladderRepairStatusProvider.notifier).show(s),
      ),
      readinessTimeout: readinessTimeout,
      onProgress: onProgress,
      cancelled: () => ref.read(effectiveUserUidProvider) != uidAtStart,
      writeRecord: (record) => writeControllerFacts(
        controllerId: controllerId,
        families: [
          PreparedFacts(
            {
              kLadderRepairRecordField: {
                ...record,
                'at': FieldValue.serverTimestamp(),
              },
            },
            () {},
          ),
        ],
        label: 'ladder repair',
      ),
      // The record already on the controller doc, so a dry run only writes
      // when its result changes (cache or server; a failed read writes).
      readRecord: () async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) return null;
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('controllers')
            .doc(controllerId)
            .get();
        final v = snap.data()?[kLadderRepairRecordField];
        return v is Map ? Map<String, dynamic>.from(v) : null;
      },
      republish: (asserts, v) async {
        await ref.read(controllerFactsPublisherProvider).publishDeviceFacts(
              controllerId: controllerId,
              participation: null,
              baseBoundaries: null,
              slotsRead: 0,
              source: kLadderRepairPublishSource,
              ladderAssertsSegments: asserts,
              ladderRestore: v,
            );
      },
      // Same LAN endpoint, not the same instance: wledRepositoryProvider
      // builds a fresh WledService for the SAME controller on connectivity /
      // profile rebuilds, and that is not a reason to defer.
      stillConnected: () {
        final cur = ref.read(wledRepositoryProvider);
        return cur is WledService && cur.baseUrl == svc.baseUrl;
      },
      pausePolling: () {
        try {
          ref.read(wledStateProvider.notifier).pausePolling();
        } catch (_) {}
      },
      resumePolling: () {
        try {
          ref.read(wledStateProvider.notifier).resumePolling();
        } catch (_) {}
      },
    ));
}

/// Called by the healer provider once a LAN connect's publish has resolved.
/// Returns null when there was nothing to consider: the ladder lights AND
/// states every bus (R2), or was not measured.
final ladderRepairCoordinatorProvider = Provider<LadderRepairConsider>((ref) {
  return ({
    required FactsPublishOutcome outcome,
    required WledService svc,
    required String controllerId,
  }) async {
    final verdict = outcome.ladderRestore;
    final participating = outcome.participating;
    final asserts = outcome.ladderAssertsSegments;
    if (verdict == null ||
        participating == null ||
        (verdict.restoreLit && asserts != false)) {
      return null;
    }
    final runner = buildLadderRepairRunner(
      ref,
      svc: svc,
      controllerId: controllerId,
      participating: participating,
    );
    final run = await runner.consider(verdict, assertsSegments: asserts);
    debugPrint('[LadderRepair] $controllerId → $run');
    return run;
  };
});

// ── Bus change (#183) ────────────────────────────────────────────────────────

/// PURE. Did the bus list change in a way the ladder cares about — the count
/// or the ids? A first reading is not a change.
bool busSetChanged(List<int>? before, List<int> after) {
  if (before == null) return false;
  final a = [...before]..sort();
  final b = [...after]..sort();
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

/// Re-runs the ladder evaluation when the LIVE bus list changes, not only at
/// connect. The healer measures the ladder once per connect; a bus added
/// outside the app (WLED's own settings page) mid-session, or found changed on
/// the next connect of the same endpoint, left the facts stale and the
/// one-time repair marker set. On a change for the SAME endpoint this clears
/// that marker and runs the heal again (facts republished, repair
/// reconsidered). A new endpoint is a connect, which the healer already
/// handles. Pure apart from the injected actions, so it is unit-testable.
class LadderBusChangeWatcher {
  LadderBusChangeWatcher({
    required this.reheal,
    required this.clearMarker,
    required this.controllerId,
  });

  final Future<void> Function() reheal;
  final Future<void> Function(String controllerId) clearMarker;
  final String? Function() controllerId;

  String? _endpoint;
  List<int>? _lastIds;
  bool _running = false;

  /// The ids last seen for the current endpoint (tests).
  List<int>? get lastIds => _lastIds;

  /// One hardware reading for [endpoint]. True when it re-ran the heal.
  Future<bool> onBuses(String endpoint, List<int> ids) async {
    if (_endpoint != endpoint) {
      _endpoint = endpoint;
      _lastIds = ids;
      return false;
    }
    if (!busSetChanged(_lastIds, ids)) return false;
    _lastIds = ids;
    if (_running) return false;
    _running = true;
    try {
      final id = controllerId();
      if (id != null && id.isNotEmpty) await clearMarker(id);
      await reheal();
      return true;
    } catch (e) {
      debugPrint('[LadderRepair] bus-change re-evaluation failed: $e');
      return false;
    } finally {
      _running = false;
    }
  }
}

/// Keeps a [LadderBusChangeWatcher] on the live hardware config. Watched by
/// MainScaffold. A controller reboots when its buses change, so the
/// connection drops and comes back; on that return the hardware config is
/// re-read, which is what feeds the watcher.
final ladderBusChangeWatchProvider = Provider<LadderBusChangeWatcher>((ref) {
  final watcher = LadderBusChangeWatcher(
    reheal: () => ref.read(controllerDefaultsHealerProvider)(),
    clearMarker: (id) => SharedPrefsLadderRepairStore().clearRan(id),
    controllerId: () => ref.read(selectedControllerIdProvider),
  );
  ref.listen<AsyncValue<WledHardwareConfig?>>(deviceHardwareConfigProvider,
      (_, next) {
    if (!next.hasValue) return;
    final hw = next.value;
    final repo = ref.read(wledRepositoryProvider);
    if (hw == null || repo is! WledService) return;
    unawaited(watcher.onBuses(
      repo.baseUrl,
      deviceChannelsFromConfig(hw).map((c) => c.id).toList(),
    ));
  }, fireImmediately: true);
  ref.listen<bool>(wledStateProvider.select((s) => s.connected), (prev, next) {
    if (prev == false && next) ref.invalidate(deviceHardwareConfigProvider);
  });
  return watcher;
});

// ── The customer's own repair (#183) ─────────────────────────────────────────

/// Does the readiness status say the base ladder needs repair? The server
/// gate's `gated_ladder_bad`, pre-flight's `preflight_ladder_bad`, or this
/// session's own R2 measurement for the selected controller.
final ladderRepairNeededProvider = Provider<bool>((ref) {
  final gate = ref.watch(gateStatusProvider).valueOrNull ?? GateStatus.unknown;
  if (gate.blocking.contains(kGateLadderBad)) return true;
  final pf = ref.watch(gameDayServerStatusSyncProvider).preflight;
  if (pf != null && pf.reasons.contains(PreflightReason.ladderBad)) return true;
  final id = ref.watch(selectedControllerIdProvider);
  return id != null && publishedBaseLadderMemo[id] == false;
});

/// Why "Repair base lighting" cannot run right now, or null when it can:
/// the LAN (a direct WledService), the account's own controller (not a
/// customer an installer is viewing), and a selected controller record.
String? ladderRepairBlockedReason({
  required bool onLan,
  required bool hasControllerId,
  required bool impersonating,
}) {
  if (impersonating) {
    return "Only the homeowner's phone can repair base lighting.";
  }
  if (!onLan) {
    return 'Connect to your home Wi-Fi to repair your base lighting.';
  }
  if (!hasControllerId) return 'Choose your controller in Settings first.';
  return null;
}

/// What the Game Day screen's action talks to — an interface so widget tests
/// can fake the run without a controller.
abstract class LadderRepairAction {
  String? blockedReason();
  Future<LadderRepairRun> run({void Function(String step)? onProgress});
  Future<LadderRepairRun> restore({void Function(String step)? onProgress});
}

/// The customer's repair: the same runner as the connect-time repair, with
/// the tap as consent (repairNow) and a shorter wait for Game Day state.
class UserLadderRepair implements LadderRepairAction {
  const UserLadderRepair(this._ref);
  final Ref _ref;

  @override
  String? blockedReason() => ladderRepairBlockedReason(
        onLan: _ref.read(wledRepositoryProvider) is WledService,
        hasControllerId:
            (_ref.read(selectedControllerIdProvider) ?? '').isNotEmpty,
        impersonating: _ref.read(installerAccessingCustomerProvider) != null,
      );

  BaseLadderRepairRunner? _runner(void Function(String step)? onProgress) {
    final repo = _ref.read(wledRepositoryProvider);
    final id = _ref.read(selectedControllerIdProvider);
    if (repo is! WledService || id == null || id.isEmpty) return null;
    return buildLadderRepairRunner(
      _ref,
      svc: repo,
      controllerId: id,
      participating: const [],
      readinessTimeout: const Duration(seconds: 20),
      onProgress: onProgress,
    );
  }

  @override
  Future<LadderRepairRun> run({void Function(String step)? onProgress}) async {
    final reason = blockedReason();
    if (reason != null) {
      return LadderRepairRun(LadderRepairOutcome.aborted, reason);
    }
    final runner = _runner(onProgress);
    if (runner == null) {
      return const LadderRepairRun(
          LadderRepairOutcome.aborted, 'no controller on the LAN');
    }
    return runner.repairNow();
  }

  @override
  Future<LadderRepairRun> restore(
      {void Function(String step)? onProgress}) async {
    final reason = blockedReason();
    if (reason != null) {
      return LadderRepairRun(LadderRepairOutcome.aborted, reason);
    }
    final runner = _runner(onProgress);
    if (runner == null) {
      return const LadderRepairRun(
          LadderRepairOutcome.aborted, 'no controller on the LAN');
    }
    return runner.restoreFromBackup();
  }

  Future<bool> hasBackup() async {
    final id = _ref.read(selectedControllerIdProvider);
    if (id == null || id.isEmpty) return false;
    return await SharedPrefsLadderRepairStore().readBackup(id) != null;
  }
}

final userLadderRepairProvider =
    Provider<LadderRepairAction>((ref) => UserLadderRepair(ref));
