// What a timer-table build needs to know, for the writers that are NOT the
// schedule sync: the lease manager (one-night and Game Day nights) and the
// sunrise-off toggle.
//
// Schedule sync owns the table and tells the customer what it refused, so it
// keeps its own reading of these inputs. These writers have no such voice and
// now send all 10 rows (see timer_table.dart), so a guess is no longer free:
// "solar off" or "sunrise-off off" read during a loading window would write a
// placeholder over a live sunset row or the live sunrise-off. A value that is
// still loading therefore reads as UNKNOWN and the caller defers the write —
// the lease is re-armed by the next sweep, the toggle reports it could not
// finish — rather than sending a table built on a guess.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart' show authStateProvider;
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart'
    show globalSunriseOffTimerProvider;
import 'package:nexgen_command/features/schedule/timer_table.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

/// How long a writer waits for a loading input before calling it unknown.
const Duration kTimerTableContextWait = Duration(seconds: 3);

/// Either a [context] to build with, or why it is [unknown].
class TimerTableContextRead {
  final TimerTableContext? context;
  final String? unknown;
  const TimerTableContextRead.ready(TimerTableContext this.context)
      : unknown = null;
  const TimerTableContextRead.unknown(String this.unknown) : context = null;
}

/// Resolve the context for a lease or sunrise-off write to [repo].
///
/// [sunriseOff] / [sunriseOffGiven]: the toggle passes the value it is writing
/// (its own profile write may not have streamed back yet).
Future<TimerTableContextRead> resolveTimerTableContext(
  Ref ref,
  WledRepository repo, {
  bool sunriseOffGiven = false,
  Map<String, dynamic>? sunriseOff,
}) async {
  // 1. The solar flag. An error reads as off (the provider's own contract).
  final bool flagOn;
  final flag = ref.read(solarSchedulingEnabledProvider);
  if (flag.hasValue) {
    flagOn = flag.requireValue;
  } else if (flag.hasError) {
    flagOn = false;
  } else {
    try {
      flagOn = await ref
          .read(solarSchedulingEnabledProvider.future)
          .timeout(kTimerTableContextWait);
    } on TimeoutException {
      return const TimerTableContextRead.unknown(
          'the sunrise/sunset setting has not loaded');
    } catch (_) {
      return _withSunriseOff(ref, false, false,
          sunriseOffGiven: sunriseOffGiven, sunriseOff: sunriseOff);
    }
  }

  // 2. Coordinates, read only when the flag is on — the same rule schedule
  // sync uses. 0,0 is a KNOWN "no location"; an unreadable cfg is unknown.
  var solarEnabled = false;
  if (flagOn && repo is ClockInfoSource) {
    ControllerClockInfo? info;
    try {
      info = await (repo as ClockInfoSource).fetchClockInfo();
    } catch (_) {
      info = null;
    }
    final lat = info?.latitude;
    final lon = info?.longitude;
    if (lat == null || lon == null) {
      return const TimerTableContextRead.unknown(
          'the controller location could not be read');
    }
    solarEnabled = !(lat == 0 && lon == 0);
  }

  return _withSunriseOff(ref, flagOn, solarEnabled,
      sunriseOffGiven: sunriseOffGiven, sunriseOff: sunriseOff);
}

Future<TimerTableContextRead> _withSunriseOff(
  Ref ref,
  bool flagOn,
  bool solarEnabled, {
  required bool sunriseOffGiven,
  Map<String, dynamic>? sunriseOff,
}) async {
  Map<String, dynamic>? off;
  if (sunriseOffGiven) {
    off = sunriseOff;
  } else {
    if (!await _profileSettled(ref)) {
      return const TimerTableContextRead.unknown(
          'the account profile has not loaded');
    }
    try {
      off = ref.read(globalSunriseOffTimerProvider);
    } catch (_) {
      return const TimerTableContextRead.unknown(
          'the sunrise-off setting could not be read');
    }
  }
  return TimerTableContextRead.ready(TimerTableContext(
    solarFlagOn: flagOn,
    solarEnabled: solarEnabled,
    globalSunriseOff: off,
  ));
}

/// True once the profile that holds `sunrise_off_enabled` is known: loaded,
/// or nobody is signed in (there is then no profile to wait for).
Future<bool> _profileSettled(Ref ref) async {
  if (ref.read(currentUserProfileProvider).hasValue) return true;

  final auth = ref.read(authStateProvider);
  Object? user;
  if (auth.hasValue) {
    user = auth.value;
  } else if (auth.hasError) {
    return true;
  } else {
    try {
      user = await ref
          .read(authStateProvider.future)
          .timeout(kTimerTableContextWait);
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
  }
  if (user == null) return true;

  try {
    await ref
        .read(currentUserProfileProvider.future)
        .timeout(kTimerTableContextWait);
    return true;
  } on TimeoutException {
    return false;
  } catch (_) {
    return true;
  }
}
