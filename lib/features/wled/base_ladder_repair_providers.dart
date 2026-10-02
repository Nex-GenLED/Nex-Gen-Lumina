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
import 'package:nexgen_command/features/wled/base_ladder_repair.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show controllerFactsPublisherProvider, healerPhoneNowProvider;
import 'package:nexgen_command/features/wled/controller_facts_publisher.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// `*_source` stamped on facts republished after a repair.
const String kLadderRepairPublishSource = 'ladder_repair';

// ── Game Day activity (pure core + probe) ────────────────────────────────────

/// PURE. What the server's own status says about a game in progress, or null.
///
/// Read whether or not the served flag is fresh: a planner that stopped
/// writing may still have minted jobs that the dispatcher fires, so for a
/// "do not touch the controller now" question the raw data is the safe input.
///   • a start that completed within the last 8 h and no end since → live;
///   • an END pending → the game is on;
///   • a START due within [kLadderRepairGameGuard] (or overdue) → about to fire.
String? serverLiveReasonAt(GameDayServerStatus s, DateTime now) {
  final last = s.lastFire;
  if (last != null &&
      last.seq == 'start' &&
      last.completed &&
      last.completedAt != null &&
      now.difference(last.completedAt!) < const Duration(hours: 8)) {
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

/// Called by the healer provider once a LAN connect's publish has resolved.
/// Returns null when there was nothing to consider.
final ladderRepairCoordinatorProvider = Provider<LadderRepairConsider>((ref) {
  return ({
    required FactsPublishOutcome outcome,
    required WledService svc,
    required String controllerId,
  }) async {
    final verdict = outcome.ladderRestore;
    final participating = outcome.participating;
    if (verdict == null || participating == null || verdict.restoreLit) {
      return null;
    }
    final nowFn = ref.read(healerPhoneNowProvider);
    final runner = BaseLadderRepairRunner(LadderRepairDeps(
      svc: svc,
      controllerId: controllerId,
      participating: participating,
      now: nowFn,
      phoneUtcOffset: nowFn().timeZoneOffset,
      // Absent or unreadable config = dry run; only an explicit "repair"
      // writes (ladderRepairModeFrom).
      mode: () => readLadderRepairMode(
          () => ref.read(baseLadderRepairConfigProvider.future)),
      gameDay: ref.read(gameDayActivityProbeProvider),
      store: SharedPrefsLadderRepairStore(
        onStatus: (s) => ref.read(ladderRepairStatusProvider.notifier).show(s),
      ),
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
    final run = await runner.consider(verdict);
    debugPrint('[LadderRepair] $controllerId → $run');
    return run;
  };
});
