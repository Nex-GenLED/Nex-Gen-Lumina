// Build-time visibility switches for features withheld from the first App
// Store build (119). Nothing here deletes code or data: a hidden feature's
// screens, rows and background runners are compiled out of reach, and the
// customer's stored preferences and generated content stay exactly as they
// were, so each feature can return later by flipping one constant.
//
// Each const has a Provider twin. Production code reads the Provider where
// a Riverpod `ref` is available (so tests can exercise the "returns later"
// path with an override) and the const where there is no ref (widget trees,
// route tables). The Provider's default is always the const.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_router.dart' show AppRoutes;

/// Lumina Autopilot: the weekly schedule generator, its Suggest/Proactive
/// row on the Schedule tab's Lumina card, its suggestions card, its three
/// full-screen routes, the profile editor's Autopilot card and the
/// installer's autonomy tiles. Hidden: the scheduler never starts, no
/// generation runs (manual, on-connect, Sunday or weekly-brief), and a
/// weekly-brief deep link lands on the Schedule tab instead.
const bool kAutopilotVisible = false;

/// The "Generate This Week's Schedule" button at the bottom of My Schedule.
/// It forces an Autopilot generation, so it is hidden with Autopilot but
/// has its own switch because it could return on its own.
const bool kWeeklyScheduleGenerationVisible = false;

/// Simple Mode: the two-tab shell, its Settings card and the installer
/// handoff's Simple Mode card. Hidden: the shell is always the full dock,
/// even on a device whose saved preference is ON (the saved value is left
/// in place and is honoured again when the feature returns).
const bool kSimpleModeVisible = false;

/// Game Day crews (build 120): the "Join a Crew" card, the team card's
/// "Share with neighbors / Create Crew" row and the crew status row with
/// Manage and Leave (the host's manage sheet and the Leave dialog hang off
/// those). Hidden because join-by-code has no server half (the rules deny a
/// non-member's invite-code query by design), the Leave button is a no-op,
/// nothing delivers the host's design or the "(all members)" switches to a
/// member, and creating a crew for a team with a saved design writes nested
/// arrays that abort the app on iOS. Existing crew documents are untouched.
///
/// Flip to true only when ALL of these hold: a `joinGameDayCrew` callable
/// (transaction, cooldown, size cap, one not-found for a wrong code and a
/// closed crew) is deployed and the app joins through it; Leave calls
/// `leaveCrew`; a member-side mirror copies the host's design and switches
/// into the member's own per-team config and restores it on Leave; the crew
/// document JSON-encodes `design_payload`; the host name comes from the
/// profile, not the literal "My House".
const bool kGameDayCrewsVisible = false;

final autopilotVisibleProvider = Provider<bool>((_) => kAutopilotVisible);

final weeklyScheduleGenerationVisibleProvider =
    Provider<bool>((_) => kWeeklyScheduleGenerationVisible);

final simpleModeVisibleProvider = Provider<bool>((_) => kSimpleModeVisible);

final gameDayCrewsVisibleProvider =
    Provider<bool>((_) => kGameDayCrewsVisible);

/// Where a hidden Autopilot route sends the user: the Schedule tab, which is
/// where every Autopilot entry point used to live. Returns null (no redirect)
/// when the feature is visible. Pure so it can be asserted without a router.
String? hiddenAutopilotRouteTarget({bool visible = kAutopilotVisible}) =>
    visible ? null : AppRoutes.schedule;
