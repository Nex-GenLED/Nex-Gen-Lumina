// lib/features/game_day/game_day_server_status.dart
//
// +114 (plan §3.2/§3.4, step C) — the CLIENT READER for `users/{uid}.gameday_server`,
// the planner's statement of whether OUR SERVERS run this account's Game Day.
//
// THE CONTRACT (written by planGameDayFires + dispatchFireJobs; server step B):
//   served       bool      starts for this account are minted by the server
//   teams        [string]  team slugs the server can fire (D2, per team)
//   checked_at   Timestamp written EVERY planner tick while served (D1)
//   preflight    {ok, reasons[], info[], mode, at} | null — null = not
//                allowlisted (pre-flight runs for allowlisted accounts only)
//   next_fire    {event_id, team_slug, seq, fire_at} | null
//   last_fire    {event_id, seq, state, completed_at, latency_ms} | null
//                (dispatcher-owned)
//
// THE APP NEVER WRITES IT (rules B5 deny client writes), and it REFLECTS rather
// than re-deriving: a second implementation of "is this account served" would
// drift from the planner's, and the planner's is the one that fires.
//
// FAIL-SAFE DIRECTION. Every degraded read — absent field, malformed map,
// signed out, stream error, and a served flag whose heartbeat is older than
// [kServerStatusStaleAfter] — reads as NOT SERVED, i.e. the phone runs Game
// Day exactly as build 112 did. A wrong "not served" costs a duplicate fire
// (server and phone both apply the same look). A wrong "served" would silence
// the phone while nothing fires: a dark house. So the parser only ever errs
// one way. (D1: a dead planner degrades to today's behaviour, never to dark.)
//
// STALENESS IS A FUNCTION OF TIME, NOT OF THE SNAPSHOT. A planner that stops
// writing produces no snapshot, so the last value would sit "served" forever.
// [servedAt] / [servesTeamAt] take `now` and are what every decision calls; the
// provider also re-emits on a timer so on-screen state ages out by itself.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Field name on `users/{uid}`. A wire contract with the server.
const String kGameDayServerField = 'gameday_server';

/// A served flag whose `checked_at` is older than this is not trusted (D1).
/// The planner ticks every 5 minutes; six missed ticks is not a blip.
const Duration kServerStatusStaleAfter = Duration(minutes: 30);

DateTime? _time(Object? v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

List<String> _strings(Object? v) =>
    v is List ? [for (final x in v) if (x is String && x.isNotEmpty) x] : const [];

/// `gameday_server.preflight`.
@immutable
class ServerPreflight {
  final bool ok;
  final List<String> reasons;
  final List<String> info;

  /// `enforce` or `observe`. In observe mode a failing account is still served.
  final String mode;

  const ServerPreflight({
    required this.ok,
    required this.reasons,
    required this.info,
    required this.mode,
  });

  bool get observeOnly => mode == 'observe';
}

/// `gameday_server.next_fire`.
@immutable
class ServerNextFire {
  final String eventId;
  final String? teamSlug;

  /// `start` or `end` (later steps add more; unknown strings are kept).
  final String seq;
  final DateTime fireAt;

  const ServerNextFire({
    required this.eventId,
    required this.teamSlug,
    required this.seq,
    required this.fireAt,
  });
}

/// `gameday_server.last_fire`.
@immutable
class ServerLastFire {
  final String eventId;
  final String seq;
  final String state;
  final DateTime? completedAt;
  final int? latencyMs;

  const ServerLastFire({
    required this.eventId,
    required this.seq,
    required this.state,
    required this.completedAt,
    required this.latencyMs,
  });

  bool get completed => state == 'completed';
}

@immutable
class GameDayServerStatus {
  /// `served` exactly as written. Use [servedAt] for decisions.
  final bool servedFlag;
  final List<String> teams;
  final DateTime? checkedAt;
  final ServerPreflight? preflight;
  final ServerNextFire? nextFire;
  final ServerLastFire? lastFire;

  const GameDayServerStatus({
    required this.servedFlag,
    required this.teams,
    required this.checkedAt,
    required this.preflight,
    required this.nextFire,
    required this.lastFire,
  });

  /// Absent, malformed, signed out, error: the phone runs Game Day.
  static const GameDayServerStatus notServed = GameDayServerStatus(
    servedFlag: false,
    teams: [],
    checkedAt: null,
    preflight: null,
    nextFire: null,
    lastFire: null,
  );

  /// The account is on the server allowlist (pre-flight is only evaluated for
  /// allowlisted accounts, so its presence says so).
  bool get allowlisted => preflight != null;

  /// Served AND the planner's heartbeat is fresh. A served flag with no
  /// `checked_at` at all is malformed and reads as not served.
  bool servedAt(DateTime now) {
    if (!servedFlag) return false;
    final at = checkedAt;
    if (at == null) return false;
    return now.difference(at) <= kServerStatusStaleAfter;
  }

  /// The served flag is set but its heartbeat has aged out — the planner has
  /// stopped writing. Shown as "Phone" (with no reason the customer can act on).
  bool staleAt(DateTime now) => servedFlag && !servedAt(now);

  /// Does the server run [teamSlug]'s Game Day right now?
  bool servesTeamAt(String teamSlug, DateTime now) =>
      servedAt(now) && teams.contains(teamSlug);

  /// The served team slugs right now; empty when not served.
  Set<String> servedTeamsAt(DateTime now) =>
      servedAt(now) ? teams.toSet() : const <String>{};

  /// PURE. Parse the user document's `gameday_server` value. Never throws;
  /// anything unexpected reads as [notServed] or drops the bad sub-field.
  static GameDayServerStatus fromUserDoc(Object? raw) {
    if (raw is! Map) return notServed;
    try {
      final pf = raw['preflight'];
      final nf = raw['next_fire'];
      final lf = raw['last_fire'];

      ServerNextFire? nextFire;
      if (nf is Map) {
        final ev = nf['event_id'];
        final seq = nf['seq'];
        final at = _time(nf['fire_at']);
        if (ev is String && seq is String && at != null) {
          final slug = nf['team_slug'];
          nextFire = ServerNextFire(
            eventId: ev,
            teamSlug: slug is String && slug.isNotEmpty ? slug : null,
            seq: seq,
            fireAt: at,
          );
        }
      }

      ServerLastFire? lastFire;
      if (lf is Map && lf['event_id'] is String && lf['seq'] is String) {
        final lat = lf['latency_ms'];
        lastFire = ServerLastFire(
          eventId: lf['event_id'] as String,
          seq: lf['seq'] as String,
          state: lf['state'] is String ? lf['state'] as String : 'unknown',
          completedAt: _time(lf['completed_at']),
          latencyMs: lat is num ? lat.toInt() : null,
        );
      }

      return GameDayServerStatus(
        servedFlag: raw['served'] == true,
        teams: _strings(raw['teams']),
        checkedAt: _time(raw['checked_at']),
        preflight: pf is Map
            ? ServerPreflight(
                ok: pf['ok'] == true,
                reasons: _strings(pf['reasons']),
                info: _strings(pf['info']),
                mode: pf['mode'] == 'observe' ? 'observe' : 'enforce',
              )
            : null,
        nextFire: nextFire,
        lastFire: lastFire,
      );
    } catch (_) {
      return notServed;
    }
  }
}

/// Server pre-flight reason strings (`functions/src/gameDayPreflight.ts`).
/// A wire contract, not local labels.
abstract final class PreflightReason {
  static const noBridge = 'preflight_no_bridge';
  static const bridgeStale = 'preflight_bridge_stale';
  static const noParticipation = 'preflight_no_participation';
  static const ladderUnknown = 'preflight_ladder_unknown';
  static const ladderBad = 'preflight_ladder_bad';
  static const gated = 'preflight_gated';
  static const controllerUnreachable = 'preflight_controller_unreachable';
}

/// What the customer can read about one pre-flight reason — or null for a
/// reason that has no customer meaning (an unknown future string still gets a
/// generic sentence; [PreflightReason.gated] is shown by the Blocked state).
String? preflightReasonCopy(String reason) {
  switch (reason) {
    case PreflightReason.noBridge:
      return 'Your home has no Lumina Bridge paired, so our servers cannot '
          'reach your lights.';
    case PreflightReason.bridgeStale:
      return 'Your Lumina Bridge has not checked in recently. Check that it '
          'is plugged in.';
    case PreflightReason.noParticipation:
      return 'Open the app at home, on your Wi-Fi, so your controller can '
          'report its channels.';
    case PreflightReason.ladderUnknown:
      return 'Open the app at home, on your Wi-Fi, so we can check your '
          'everyday lighting settings.';
    case PreflightReason.ladderBad:
      // #183 — "Opening the app at home repairs them" was untrue once a bus
      // had been added outside the app: the on-connect repair dry-runs by
      // default and never included preset 2. Name the cause and the action.
      return "Your everyday lighting settings don't cover every channel on "
          'your controller — usually after a channel was added or changed. '
          'Use Repair base lighting on the Game Day screen.';
    case PreflightReason.controllerUnreachable:
      return 'Our servers could not reach your controller before the game.';
    case PreflightReason.gated:
      return null;
    default:
      return 'A setup step for server-run Game Day is incomplete.';
  }
}
