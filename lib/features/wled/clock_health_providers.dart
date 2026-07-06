// lib/features/wled/clock_health_providers.dart
//
// BUG-CLOCK-1 plumbing. Evaluates controller clock health on demand and caches
// the result — NO polling loop. It re-runs when the active repository changes
// (controller connect, local↔relay switch) and whenever a consumer invalidates
// it (e.g. My Schedule refreshes on screen open). Works for local AND relay
// mode via the repository's fetchClockInfo (relay yields time-only).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// Cached controller clock health. `null` when there is no connected repository
/// or the device can't be read (→ surface nothing; never false-warn). Reads the
/// phone clock at evaluation time, so it stays a pure comparison with no server
/// time call.
final clockHealthProvider = FutureProvider<ClockHealth?>((ref) async {
  final repo = ref.watch(wledRepositoryProvider);
  // fetchClockInfo lives on the ClockInfoSource capability interface (not on
  // WledRepository) — demo/mock repos simply don't implement it → no banner.
  if (repo is! ClockInfoSource) return null;
  final info = await (repo as ClockInfoSource).fetchClockInfo();
  if (info == null) return null;
  final now = DateTime.now();
  return evaluateClockHealth(
    device: info,
    phoneNow: now,
    phoneUtcOffset: now.timeZoneOffset,
  );
});
