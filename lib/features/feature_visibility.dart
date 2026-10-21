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

/// "Also broadcast to my neighborhood" (build 120): the host-only checkbox on
/// the Complement-theme Game Day setup sheet, with its "broadcast to N
/// houses" toast. Hidden because the checkbox only writes the group's
/// Game Day config document; the one reader of that document (the sync
/// session manager) is never mounted, so no neighbour's lights change.
/// The group config document and its card stay as they are.
///
/// Flip to true only when a mounted path turns that document into lights on
/// members' controllers: either the cheap route (the checkbox dispatches an
/// ad-hoc sync command through the walked "Start Neighborhood Sync" path) or
/// the session manager mounted, hardened and tested, with members' consent.
const bool kGroupGameDayBroadcastVisible = false;

/// Neighborhood public listing and Discover Nearby (build 120): the "Public
/// Group" toggle with its "approximate location" sentence in the create
/// dialog, and the "Discover Nearby Groups" button on the onboarding's last
/// page (its sheet becomes unreachable). Hidden because no location is ever
/// read: the create dialog passes null coordinates, so no public listing is
/// written and no in-app group can be found, and the Discover sheet searches
/// a hard-coded coordinate instead of the phone's. The listing projection,
/// its rules and the search code stay in place.
///
/// Flip to true only when: the create dialog reads the device location (with
/// the iOS purpose strings and the App Privacy answers updated to say so);
/// Discover uses the phone's location and is reachable from the group list;
/// a group can be made public or private later; the owner's privacy decisions
/// on cell size, name moderation and who may search are implemented; and the
/// "request to join" wording matches what the callable does.
const bool kNeighborhoodDiscoveryVisible = false;

/// Group Schedule (build 120): the "Group Schedule" section of the Sync
/// Control Center (list, Add, "Create First Schedule", the time-config sheet,
/// opt-out, the Game Day Autopilot shortcut inside it) and the onboarding's
/// "Scheduled Shows" chip. Hidden because a group schedule is saved to
/// Firestore and nothing in the app or the Cloud Functions ever reads or runs
/// it. Stored schedules stay as they are.
///
/// Flip to true only when an executor exists: either members' apps reconcile
/// the group's active schedules into their own controller timers on open
/// (option A, no server), or a scheduled function fans each due start and
/// end out to consenting members' command queues (option B, needs the deploy
/// and the fan-out allow-list). Date ranges, sunset start and "Notify Group"
/// must do what their labels say, or the labels change.
const bool kGroupScheduleVisible = false;

final autopilotVisibleProvider = Provider<bool>((_) => kAutopilotVisible);

final weeklyScheduleGenerationVisibleProvider =
    Provider<bool>((_) => kWeeklyScheduleGenerationVisible);

final simpleModeVisibleProvider = Provider<bool>((_) => kSimpleModeVisible);

final gameDayCrewsVisibleProvider =
    Provider<bool>((_) => kGameDayCrewsVisible);

final groupGameDayBroadcastVisibleProvider =
    Provider<bool>((_) => kGroupGameDayBroadcastVisible);

final neighborhoodDiscoveryVisibleProvider =
    Provider<bool>((_) => kNeighborhoodDiscoveryVisible);

final groupScheduleVisibleProvider =
    Provider<bool>((_) => kGroupScheduleVisible);

/// Where a hidden Autopilot route sends the user: the Schedule tab, which is
/// where every Autopilot entry point used to live. Returns null (no redirect)
/// when the feature is visible. Pure so it can be asserted without a router.
String? hiddenAutopilotRouteTarget({bool visible = kAutopilotVisible}) =>
    visible ? null : AppRoutes.schedule;
