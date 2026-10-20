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

final autopilotVisibleProvider = Provider<bool>((_) => kAutopilotVisible);

final weeklyScheduleGenerationVisibleProvider =
    Provider<bool>((_) => kWeeklyScheduleGenerationVisible);

final simpleModeVisibleProvider = Provider<bool>((_) => kSimpleModeVisible);

/// Where a hidden Autopilot route sends the user: the Schedule tab, which is
/// where every Autopilot entry point used to live. Returns null (no redirect)
/// when the feature is visible. Pure so it can be asserted without a router.
String? hiddenAutopilotRouteTarget({bool visible = kAutopilotVisible}) =>
    visible ? null : AppRoutes.schedule;
