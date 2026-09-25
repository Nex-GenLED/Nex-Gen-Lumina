// lib/features/game_day/ephemeral_session/ephemeral_session_expiry.dart
//
// When an ephemeral Game Day session stops being a session.
//
// The phase machine in EphemeralGameSessionService is a Dart Timer in the UI
// isolate: it only runs while the app is open. Every timestamp it records is
// therefore "when the app noticed", not when the game did something. Before
// this file existed, nothing bounded a session by the game itself:
//
//   * a session left in `liveGame` when the app was closed at the final
//     whistle stayed `liveGame` until the next launch, however long that was;
//   * on that launch the machine saw the game was over and entered `postGame`
//     with a 30-minute countdown measured FROM THAT MOMENT, hours after the
//     game, and the first sweep did not even run until 60 s after launch;
//   * the home-screen Game Day button trusted the stored phase, so it opened
//     the "Post-Game" sheet for a game nobody was watching any more.
//
// That is the 2026-09-24 bench session that blocked the Game Day entry point
// on 2026-09-25. This file adds the missing bound. A session expires a fixed
// grace after the game ends, where "game end" is the EARLIER of what was
// recorded and what the schedule implies: the recorded end can only ever be
// later than the truth (it is a noticed time), so the estimate caps it.
// Every reader applies the bound: the home-screen button ignores an expired
// session, and the service finalises one instead of running its phase
// machine on it.

import '../../autopilot/game_day_autopilot_config.dart'
    show estimatedGameDuration;
import '../../sports_alerts/data/team_colors.dart';
import 'ephemeral_game_session.dart';

/// The post-game countdown: how long the team design stays up after the
/// final before the revert payload is applied.
const Duration kEphemeralPostGameCountdown = Duration(minutes: 30);

/// The buffer the live phase allows past the sport's estimated duration
/// before it stops waiting for ESPN's final (overtime, weather delays).
const Duration kEphemeralLiveGameBuffer = Duration(minutes: 60);

/// How long after the game is taken to have ended a session may still exist,
/// in any phase.
///
/// Two hours. The countdown is 30 minutes, so an app reopened within roughly
/// 90 minutes of the estimated end still performs the designed revert; a
/// session from last night can never be "active" this morning. Past this
/// point the schedule has long since taken the house back, and applying a
/// captured revert payload would only stomp it, so an expired session is
/// finalised WITHOUT its revert.
const Duration kEphemeralSessionGrace = Duration(hours: 2);

/// Estimated duration for a slug the catalog does not know. `createSession`
/// rejects unknown slugs, but a stored document must never be able to make a
/// session immortal.
const Duration kEphemeralUnknownSportDuration = Duration(hours: 4);

/// When the game is taken to have ended.
///
/// The schedule estimate is `gameStart + estimatedGameDuration + buffer`,
/// the same fallback the live phase uses to give up on ESPN. A recorded
/// [EphemeralGameSession.gameEnd] wins only when it is EARLIER, which is a
/// real-time ESPN final on a short game. A later recorded end is a resume
/// artefact and is capped by the estimate.
DateTime ephemeralGameEndEstimate(EphemeralGameSession session) {
  final sport = kTeamColors[session.teamSlug]?.sport;
  final duration = sport == null
      ? kEphemeralUnknownSportDuration
      : estimatedGameDuration(sport);
  final estimate =
      session.gameStart.add(duration).add(kEphemeralLiveGameBuffer);
  final recorded = session.gameEnd;
  if (recorded != null && recorded.isBefore(estimate)) return recorded;
  return estimate;
}

/// The instant after which [session] is stale in every phase.
DateTime ephemeralSessionExpiresAt(EphemeralGameSession session) =>
    ephemeralGameEndEstimate(session).add(kEphemeralSessionGrace);

/// True once [now] has reached [ephemeralSessionExpiresAt].
bool isEphemeralSessionExpired(EphemeralGameSession session, DateTime now) =>
    !now.isBefore(ephemeralSessionExpiresAt(session));
