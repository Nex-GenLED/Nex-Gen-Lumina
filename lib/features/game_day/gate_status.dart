// The readiness gate, as the CUSTOMER sees it.
//
// The planner evaluates three checks per account every five minutes and
// persists the blocking reasons to `users/{uid}.gameday_gate_blocking`. This
// file is the client's READER for that field. It never re-evaluates: a second
// implementation of the rules would drift from the server's, and the server's
// is the one that decides whether lights actually fire.
//
// WHY IT EXISTS. An account held in log-only currently sees a Game Day UI that
// looks armed — the toggle is on, teams are listed, the badge says "Today". It
// promises a show the server has already decided not to run. Eight of the ten
// live accounts are in that state.
//
// WHAT IS DELIBERATELY NOT SHOWN. `gated_no_ladder_unknown` is ADVISORY: the
// account is armed, and the missing fact is ours to collect, not the
// customer's to fix. Advisory is not a customer problem, so it renders nothing.

import 'package:flutter/foundation.dart';

/// Server reason strings. Mirrors `functions/src/gameDayGate.ts` — these are a
/// wire contract, not local labels.
/// HISTORICAL — the server stopped producing this on 2026-08-26 when the R1
/// floor check was removed (Game Day must work with zero recurring schedules).
/// It is still named here for one reason: ~7 live accounts have it PERSISTED in
/// `gameday_gate_blocking`, and their doc is not rewritten until the planner's
/// next tick. [GateStatus.fromUserDoc] drops it so those accounts read as armed
/// immediately instead of showing a reasonless "not firing yet" for five
/// minutes. Remove once no persisted verdict contains it.
const String kGateNoFloorHistorical = 'gated_no_floor';
const String kGateNoFacts = 'gated_no_facts';
const String kGateLadderBad = 'gated_ladder_bad';

/// What the customer is told, and what they can do about it.
@immutable
class GateStatus {
  /// Blocking reasons exactly as the server wrote them, order preserved.
  final List<String> blocking;

  const GateStatus(this.blocking);

  /// No field yet — the planner has not evaluated this account. Treated as
  /// armed: the gate's own default is to allow, and inventing a warning from
  /// an absent field would be the client deciding policy.
  static const GateStatus unknown = GateStatus(<String>[]);

  bool get armed => blocking.isEmpty;

  /// Parse the persisted field. Anything unexpected reads as armed rather than
  /// as a fabricated block — the client must never invent a refusal.
  static GateStatus fromUserDoc(Object? raw) {
    if (raw is! List) return unknown;
    final out = <String>[];
    for (final r in raw) {
      if (r is! String || r.isEmpty) continue;
      // Drop the retired floor reason. A stored verdict written before R1 was
      // removed would otherwise leave `blocking` non-empty — so `armed` false,
      // the headline "not firing yet", and no sentence under it, because the
      // copy for it is gone. Dropping it here makes the client agree with what
      // the server will say on its next tick, five minutes early.
      if (r == kGateNoFloorHistorical) continue;
      out.add(r);
    }
    return GateStatus(out);
  }

  /// Headline. Present tense, and it says Game Day IS on — because it is; what
  /// is missing is the precondition for firing, not the feature.
  String get headline =>
      armed ? 'Game Day is on' : 'Game Day is on — not firing yet';

  /// The actionable sentence, naming the missing item.
  ///
  /// One reason gets one sentence. Several get several, because "something is
  /// missing" is the message the old gate effectively gave and it helped nobody.
  List<String> get reasons {
    final out = <String>[];
    for (final r in blocking) {
      switch (r) {
        case kGateNoFacts:
          out.add(
            'Open the app at home, on your Wi-Fi, so your controller can '
            'report its channels.',
          );
          break;
        case kGateLadderBad:
          out.add(
            'Your saved lighting presets need repairing before Game Day can '
            'run safely.',
          );
          break;
        default:
          // An unrecognised reason is still a real block; say so honestly
          // rather than rendering nothing and looking armed.
          out.add('A setup step is incomplete.');
      }
    }
    return out;
  }

  /// Retired with R1. The only self-serve fix the gate ever offered was "set a
  /// schedule", and a schedule is no longer a precondition for anything — so
  /// there is no longer a blocking reason the customer can clear with one tap.
  /// The remaining two are a LAN visit (`no_facts`) and a preset repair
  /// (`ladder_bad`); neither is a button.
  @Deprecated('R1 removed 2026-08-26; always false. Remove with its callers.')
  bool get hasScheduleFix => false;

  @override
  bool operator ==(Object other) =>
      other is GateStatus && listEquals(other.blocking, blocking);

  @override
  int get hashCode => Object.hashAll(blocking);
}

/// What the game-status badge may promise for an UPCOMING game.
///
/// Live and final games are reports of fact and are never gated — only the
/// PRE-GAME promise is a claim about the future, so only it consults the gate.
/// That split is what keeps the badge's own polling cadence uncoupled from
/// plan state, which froze it once before for celebrations-off users.
enum UpcomingPromise {
  /// The account is armed. Unchanged from today's behaviour.
  willFire,

  /// The account is in log-only. The game is still today; the lights are not.
  gated,
}

/// PURE. The promise the badge is entitled to make.
UpcomingPromise upcomingPromiseFor(GateStatus status) =>
    status.armed ? UpcomingPromise.willFire : UpcomingPromise.gated;

/// Badge text for a gated upcoming game. Short enough for a chip, and it does
/// not say "Today" alone — that word is the promise being withdrawn.
const String kGatedBadgeLabel = 'Today · setup needed';
