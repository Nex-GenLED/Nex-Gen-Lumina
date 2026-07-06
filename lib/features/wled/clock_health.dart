// lib/features/wled/clock_health.dart
//
// BUG-CLOCK-1 — controller clock-health evaluator (ships in 2.5.1 with the
// dow:0 P0 fix). A WLED controller with NTP enabled but never synced sits at
// the 1970 epoch (or the 2106 uint32-overflow sentinel) and fires NO schedules
// — indistinguishable to a user from the dow:0 dead-timer bug. Two sibling
// silent schedule-killers: a timezone left at UTC shifts every wall-clock
// timer, and lat/lon 0,0 computes sunrise/sunset for the Gulf of Guinea.
//
// This is the PURE evaluator — no Flutter widgets, no network. It reads the
// fields WLED actually exposes and classifies them. Surfacing (banners,
// creation-flow warnings, installer checklist) lives in clock_health_ui.dart;
// fetching + caching lives in clock_health_providers.dart.
//
// ── Field availability on WLED 0.15.x (1a finding) ────────────────────────
//   • Device local time  → GET /json/info  `time`  ("2026-7-6, 13:49:41",
//                          not zero-padded; already timezone-adjusted).
//   • Timezone index      → GET /json/cfg   `if.ntp.tz`   (0 = UTC).
//   • Manual UTC offset   → GET /json/cfg   `if.ntp.offset` (seconds).
//   • Latitude/Longitude  → GET /json/cfg   `if.ntp.lt` / `if.ntp.ln`.
// So the CLOCK check needs only /json/info; TZ and LOCATION need /json/cfg.
// In RELAY mode the bridge exposes getInfo (→ device time) but NOT cfg
// (CloudRelayRepository.getConfig returns null and there is no getCfg relay
// command), so tz/location are unknown there and their checks are skipped
// rather than false-warned — see [ControllerClockInfo.timezoneKnown] /
// [locationKnown].

import 'package:flutter/foundation.dart';

/// Capability interface for repositories that can read a controller's clock /
/// timezone / location for the BUG-CLOCK-1 health check. Kept OFF
/// [WledRepository] on purpose — like PerPixelWriter — so the many repository
/// implementations (and their test fakes) don't all have to implement it.
/// Only WledService (full) and CloudRelayRepository (time-only) opt in;
/// consumers type-check `repo is ClockInfoSource` before calling.
abstract class ClockInfoSource {
  /// Read-only fetch of the controller's clock/timezone/location fields. Never
  /// writes to the device. Returns null when unreachable or the fields can't be
  /// read. Local mode populates all fields; relay mode populates only
  /// [ControllerClockInfo.deviceTime] (cfg is not fetchable over the bridge).
  Future<ControllerClockInfo?> fetchClockInfo();
}

// ── Tunable thresholds ────────────────────────────────────────────────────

/// Below this year the device clock is treated as never-synced (1970 epoch).
const int kClockMinPlausibleYear = 2020;

/// Above this year the device clock is the uint32 rollover sentinel
/// (4294967295 s past 1970 ≈ 2106-02-07) — also "never got a real time".
const int kClockMaxPlausibleYear = 2100;

/// Sub-hour drift beyond this (after removing whole-hour timezone offsets) is
/// treated as a genuinely wrong clock, not a timezone mismatch.
const Duration kClockDriftThreshold = Duration(minutes: 10);

/// Absolute device-vs-phone difference beyond this can't be explained by any
/// real timezone (max legitimate offset is ~UTC+14) → the clock is unset or
/// wildly wrong. Catches the epoch/overflow sentinels even if the phone's own
/// clock is a little off.
const Duration kClockGrossDriftThreshold = Duration(hours: 25);

// ── Issue taxonomy ────────────────────────────────────────────────────────

/// Individual controller clock-health problems. A controller can exhibit more
/// than one at once; [ClockHealth] carries the full set. Declaration order is
/// severity order (most schedule-breaking first).
enum ClockHealthIssue {
  /// Device clock is at an epoch/overflow sentinel, unreadable, or drifted far
  /// from the phone — the RTC has no valid time, so NO schedule fires.
  clockUnset,

  /// Device timezone reads UTC while the phone's zone isn't — every wall-clock
  /// timer fires shifted by the UTC offset. Heuristic, warn-only.
  tzSuspect,

  /// Device latitude/longitude are both 0 — sunrise/sunset compute for the Gulf
  /// of Guinea, so solar schedules fire at the wrong time. Only matters when
  /// solar schedules exist or are being created.
  locationUnset,
}

// ── Device-side inputs ────────────────────────────────────────────────────

/// The clock/timezone/location fields read from a controller, normalized. Built
/// from the raw /json/info (+ /json/cfg when available) maps. Fields that could
/// not be read are null — see [timezoneKnown] / [locationKnown], which let the
/// evaluator skip a check rather than false-warn on missing data (relay mode).
@immutable
class ControllerClockInfo {
  /// Device local time parsed from /json/info `time`. Null when absent/garbage.
  final DateTime? deviceTime;

  /// WLED timezone index from cfg.if.ntp.tz (0 = UTC). Null when cfg was
  /// unavailable (relay mode).
  final int? tzIndex;

  /// Manual UTC offset in seconds from cfg.if.ntp.offset. Null when unavailable.
  final int? tzOffsetSeconds;

  /// Latitude / longitude from cfg.if.ntp.lt / .ln. Null when cfg unavailable.
  final double? latitude;
  final double? longitude;

  const ControllerClockInfo({
    this.deviceTime,
    this.tzIndex,
    this.tzOffsetSeconds,
    this.latitude,
    this.longitude,
  });

  /// True when timezone fields were readable (local mode). False in relay mode
  /// where cfg can't be fetched — the TZ check is skipped rather than false-warn.
  bool get timezoneKnown => tzIndex != null;

  /// True when location fields were readable.
  bool get locationKnown => latitude != null && longitude != null;

  /// Build from the raw /json/info and (optional) /json/cfg maps.
  factory ControllerClockInfo.fromMaps(
    Map<String, dynamic>? info,
    Map<String, dynamic>? cfg,
  ) {
    final deviceTime = parseWledDeviceTime(info == null ? null : info['time']);
    int? tz;
    int? ofs;
    double? lat;
    double? lon;
    final ifBlock = (cfg != null && cfg['if'] is Map) ? cfg['if'] as Map : null;
    final ntp = (ifBlock != null && ifBlock['ntp'] is Map)
        ? ifBlock['ntp'] as Map
        : null;
    if (ntp != null) {
      final t = ntp['tz'];
      if (t is num) tz = t.toInt();
      final o = ntp['offset'];
      if (o is num) ofs = o.toInt();
      final la = ntp['lt'];
      if (la is num) lat = la.toDouble();
      final lo = ntp['ln'];
      if (lo is num) lon = lo.toDouble();
    }
    return ControllerClockInfo(
      deviceTime: deviceTime,
      tzIndex: tz,
      tzOffsetSeconds: ofs,
      latitude: lat,
      longitude: lon,
    );
  }
}

/// Parse WLED's /json/info `time` string into a LOCAL [DateTime].
///
/// The field looks like `"2026-7-6, 13:49:41"` — components are NOT zero-padded
/// and the value is already timezone-adjusted (device local time). Returns null
/// for absent, non-string, or unparseable input (never throws).
DateTime? parseWledDeviceTime(dynamic raw) {
  if (raw is! String) return null;
  final m = RegExp(r'^(\d{1,4})-(\d{1,2})-(\d{1,2}),\s*(\d{1,2}):(\d{1,2}):(\d{1,2})')
      .firstMatch(raw.trim());
  if (m == null) return null;
  try {
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  } catch (_) {
    return null;
  }
}

// ── Result ────────────────────────────────────────────────────────────────

/// The set of clock-health problems detected on a controller. Empty = healthy.
@immutable
class ClockHealth {
  final Set<ClockHealthIssue> issues;

  const ClockHealth(this.issues);
  const ClockHealth.healthy() : issues = const {};

  bool get isHealthy => issues.isEmpty;
  bool get clockUnset => issues.contains(ClockHealthIssue.clockUnset);
  bool get tzSuspect => issues.contains(ClockHealthIssue.tzSuspect);
  bool get locationUnset => issues.contains(ClockHealthIssue.locationUnset);

  @override
  bool operator ==(Object other) =>
      other is ClockHealth && setEquals(issues, other.issues);

  @override
  int get hashCode => Object.hashAll(issues.toList()..sort((a, b) => a.index - b.index));

  @override
  String toString() => 'ClockHealth($issues)';
}

/// Classify a controller's clock health from its [device] fields and the phone
/// clock at read time ([phoneNow] + [phoneUtcOffset]). Pure — no network, no
/// `DateTime.now()` inside; callers pass the phone time so it stays testable.
ClockHealth evaluateClockHealth({
  required ControllerClockInfo device,
  required DateTime phoneNow,
  required Duration phoneUtcOffset,
}) {
  final issues = <ClockHealthIssue>{};

  // ── CLOCK_UNSET ─────────────────────────────────────────────────────────
  final dt = device.deviceTime;
  bool clockUnset;
  if (dt == null) {
    clockUnset = true; // no readable time at all
  } else if (dt.year < kClockMinPlausibleYear || dt.year > kClockMaxPlausibleYear) {
    clockUnset = true; // 1970 epoch / 2106 overflow sentinel
  } else {
    final diff = dt.difference(phoneNow).abs();
    if (diff > kClockGrossDriftThreshold) {
      clockUnset = true; // beyond any real timezone → unset/wildly wrong
    } else {
      // Remove whole-hour (timezone-like) offsets; only the sub-hour residual
      // is genuine drift. A device on the wrong timezone but a correctly-synced
      // clock lands on a whole-hour boundary (residual ≈ 0) and is handled by
      // TZ_SUSPECT instead of being mislabeled CLOCK_UNSET.
      final totalMin = diff.inMinutes;
      final residual = totalMin % 60; // 0..59
      final centered = residual > 30 ? 60 - residual : residual;
      clockUnset = centered > kClockDriftThreshold.inMinutes;
    }
  }
  if (clockUnset) issues.add(ClockHealthIssue.clockUnset);

  // ── TZ_SUSPECT (heuristic, warn-only; needs cfg; suppressed if clock unset) ─
  // Only fire when the device reads UTC AND the phone's own zone is NOT UTC —
  // that bounds the false positive against a legitimately-UTC user (their phone
  // offset is also zero, so no warning).
  if (!clockUnset && device.timezoneKnown) {
    final deviceIsUtc =
        device.tzIndex == 0 && (device.tzOffsetSeconds ?? 0) == 0;
    final phoneIsUtc = phoneUtcOffset == Duration.zero;
    if (deviceIsUtc && !phoneIsUtc) issues.add(ClockHealthIssue.tzSuspect);
  }

  // ── LOCATION_UNSET (needs cfg) ──────────────────────────────────────────
  if (device.locationKnown &&
      device.latitude == 0 &&
      device.longitude == 0) {
    issues.add(ClockHealthIssue.locationUnset);
  }

  return ClockHealth(issues);
}

/// True when a schedule time label is a solar trigger ("Sunrise"/"Sunset",
/// case-insensitive) — the labels whose firing depends on the controller's
/// latitude/longitude. Used to gate LOCATION_UNSET surfacing.
bool isSolarTimeLabel(String? label) {
  if (label == null) return false;
  final l = label.trim().toLowerCase();
  return l == 'sunrise' || l == 'sunset';
}

/// The single most important issue to surface, given whether solar schedules
/// are relevant. Returns null when nothing should be shown. [locationUnset] is
/// only surfaced when [solarRelevant] (it only breaks sunrise/sunset timers).
/// Priority: clockUnset > tzSuspect > locationUnset.
ClockHealthIssue? primaryIssueToSurface(
  ClockHealth health, {
  required bool solarRelevant,
}) {
  if (health.clockUnset) return ClockHealthIssue.clockUnset;
  if (health.tzSuspect) return ClockHealthIssue.tzSuspect;
  if (health.locationUnset && solarRelevant) {
    return ClockHealthIssue.locationUnset;
  }
  return null;
}

// ── User-facing copy ──────────────────────────────────────────────────────

/// Short banner/inline message for an issue.
String clockHealthMessage(ClockHealthIssue issue) {
  switch (issue) {
    case ClockHealthIssue.clockUnset:
      return "Controller clock isn't set — schedules won't fire. "
          'Check WiFi/NTP in controller settings.';
    case ClockHealthIssue.tzSuspect:
      return 'Controller timezone looks off — schedules may fire at the '
          'wrong hour.';
    case ClockHealthIssue.locationUnset:
      return "Sunrise/sunset schedules need the controller's location set.";
  }
}

/// Longer remediation text — the settings path on the controller's own web UI.
/// (No in-app remote fix in this slice; writing cfg time settings via
/// applyConfig is possible and is the future one-tap-fix follow-up.)
String clockHealthRemediation(ClockHealthIssue issue) {
  switch (issue) {
    case ClockHealthIssue.clockUnset:
      return 'Open the controller in a browser (type its IP address), then '
          'Config → WiFi Setup and confirm it is connected to your network. '
          "Next, Config → Time & Macros and enable “Get time from NTP server.” "
          'The clock syncs within a minute once the controller has internet.';
    case ClockHealthIssue.tzSuspect:
      return 'Open the controller in a browser (type its IP address), then '
          'Config → Time & Macros and set the Time Zone to your local zone. '
          'Save and reboot if prompted.';
    case ClockHealthIssue.locationUnset:
      return 'Open the controller in a browser (type its IP address), then '
          'Config → Time & Macros and set Latitude and Longitude for the '
          'install site so sunrise/sunset calculate correctly.';
  }
}
