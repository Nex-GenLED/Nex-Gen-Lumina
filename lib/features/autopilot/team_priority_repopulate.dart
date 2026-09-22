// lib/features/autopilot/team_priority_repopulate.dart
//
// Make reordering the team hierarchy actually do something.
//
// THE BUG THIS CLOSES. `TeamRegistrationService` has always exposed an
// `onTeamsChanged` seam and `teamRegistrationServiceProvider` has always built
// the service without one. So dragging a team to #1 wrote two Firestore fields
// and stopped there: the hierarchy is read at POPULATE time
// (`orderConfigsForCalendarWrite`, called from `_doPopulateCalendarsInner`),
// and nothing re-ran the populate. The controller kept arming the old #1 team's
// design until the 7-day cadence gate elapsed, a team was toggled, or the user
// happened to press refresh — with nothing on screen saying so. A user who
// reordered before kickoff got the wrong team's colours that night and no
// indication why.
//
// WHY A KEEP-ALIVE PROVIDER AND NOT THE SCREEN. The hierarchy is editable from
// TWO surfaces — the Game Day screen and Edit Profile — through one write
// helper. Hanging the repopulate off the Game Day widget would fix it on the
// surface that happens to be mounted and leave Edit Profile exactly as broken
// as it is today. Wiring the service's own callback covers both, once.
//
// WHY NOT WIRE IT INSIDE team_registration_service.dart. That file is imported
// BY `game_day_autopilot_providers.dart`; reaching back for the notifier there
// would make a direct two-file import cycle. This module sits downstream of
// both and is kept alive from MainScaffold, alongside the other shell-level
// watches.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sports_alerts/services/team_registration_service.dart';
import 'game_day_autopilot_providers.dart';

/// How long to wait after the last reorder before repopulating.
///
/// ON DROP, THEN DEBOUNCED — and both halves matter.
///
/// `ReorderableListView.onReorder` already fires once per completed drop, not
/// per drag frame, so the repopulate is never driven by pointer movement. That
/// alone would be enough to avoid the pathological case.
///
/// The debounce exists for the ordinary case on top of it: rearranging four
/// teams into the order you want is three or four separate drops a second or
/// two apart, and each drop is a complete `setTeamPriority` write. Firing per
/// drop would run three full clear-and-rewrite cycles — three rounds of ESPN
/// reads, whole-document Firestore rewrites and lease preset saves to the
/// controller — to reach a state only the last one describes. The first two
/// are not merely wasted; every one of them writes presets to controller
/// flash.
///
/// 3 seconds is chosen to sit above a comfortable drag-think-drag rhythm and
/// well below the point where a user has moved on. Only the FINAL order is
/// ever populated, which is the only order they asked for.
const Duration kTeamPriorityRepopulateDebounce = Duration(seconds: 3);

/// Wires [TeamRegistrationService.onTeamsChanged] to a debounced calendar
/// repopulate. Keep alive from the app shell — see MainScaffold.
///
/// Returns nothing useful; it exists for its wiring. Reading it is what
/// installs the callback.
final gameDayPriorityRepopulateProvider = Provider<void>((ref) {
  final service = ref.watch(teamRegistrationServiceProvider);

  Timer? debounce;
  ref.onDispose(() {
    debounce?.cancel();
    // Leave the service as we found it. A stale closure holding a disposed
    // `ref` is exactly the "Bad state: Notifier used after dispose" shape this
    // codebase has been bitten by before.
    if (identical(service.onTeamsChanged, _installed)) {
      service.onTeamsChanged = null;
    }
  });

  void handler(TeamsChangedReason reason) {
    // MEMBERSHIP CHANGES ARE DELIBERATELY IGNORED.
    //
    // `GameDayAutopilotNotifier.toggleAutopilot` already calls
    // `_populateCalendarInBackground` immediately after `addTeam`. Reacting to
    // `membership` here too would start a SECOND clear-and-rewrite over the
    // same `calendar_entries` map — the precise race the in-flight guard was
    // added to refuse. Relying on that guard to paper over a self-inflicted
    // double-fire would make a safety net load-bearing.
    if (reason != TeamsChangedReason.priorityReordered) return;

    debounce?.cancel();
    debounce = Timer(kTeamPriorityRepopulateDebounce, () async {
      try {
        // force: true — the user just told us the order is wrong. The 7-day
        // cadence gate exists to stop UNPROMPTED regeneration; this is as
        // prompted as it gets.
        final result = await ref
            .read(gameDayAutopilotNotifierProvider.notifier)
            .refreshAllCalendars(force: true);
        debugPrint('[GameDayPriority] repopulate after reorder — $result');
      } catch (e) {
        // Silent by design: the user dragged a row, they did not ask for a
        // task. A failure here costs them the OLD ordering staying armed,
        // which is what they had a moment ago — and the Game Day screen's
        // own refresh button remains the visible way to retry.
        debugPrint('[GameDayPriority] repopulate after reorder failed: $e');
      }
    });
  }

  _installed = handler;
  service.onTeamsChanged = handler;
});

/// The handler this provider most recently installed, so disposal can tell
/// "still ours" from "someone else's" before clearing it.
void Function(TeamsChangedReason)? _installed;
