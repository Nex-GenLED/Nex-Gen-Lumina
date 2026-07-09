// lib/features/wled/clock_health_providers.dart
//
// BUG-CLOCK-1 plumbing. Evaluates controller clock health on demand and caches
// the result — NO polling loop. It re-runs when the active repository changes
// (controller connect, local↔relay switch) and whenever a consumer invalidates
// it (e.g. My Schedule refreshes on screen open). Works for local AND relay
// mode via the repository's fetchClockInfo (relay yields time-only).

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

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

// ── Gamma self-heal ─────────────────────────────────────────────────────────
//
// An audit confirmed no app cfg writer reverts cfg.light.gc; gamma is asserted
// only at install / manual Re-sync, so an external reset (controller reflash,
// a WLED web-UI cfg save, a factory/backup restore, a fresh controller) sticks
// until the user re-syncs. This re-asserts the NGL color-gamma standard once
// each time we connect to a LAN controller — same connect lifecycle the
// clock-health evaluator keys off, hence its home here.

/// The device write a gamma self-heal performs. Injected via
/// [gammaSelfHealActionProvider] so tests can observe/stub it without an HTTP
/// layer. Default delegates to [pushGammaConfig], which reads cfg, skips when
/// the device already matches (2.8 / no-gc:false), else POSTs + readback-verifies.
typedef GammaSelfHealAction = Future<WledConfigPushResult> Function(String ip);

/// Test seam for [gammaSelfHealProvider]. Override in a ProviderContainer to
/// record calls or simulate skip/drift/failure results.
final gammaSelfHealActionProvider = Provider<GammaSelfHealAction>(
  (ref) => (ip) => pushGammaConfig(ip),
);

/// True when a [wledRepositoryProvider] transition is a NEW LAN-controller
/// connect that warrants a gamma self-heal — i.e. [next] is a LAN [WledService]
/// reaching a different IP than [prev] (or [prev] was not a LAN service). Guards
/// the [WledNotifier] listener so ordinary provider churn that reuses the same
/// LAN IP (connectivity/profile rebuilds emit a fresh WledService each time)
/// does NOT re-fire the cfg readback. Pure so it is unit-testable.
bool shouldSelfHealGammaOnConnect(
  WledRepository? previous,
  WledRepository? next,
) {
  if (next is! WledService) return false; // LAN only
  final prevUrl = previous is WledService ? previous.baseUrl : null;
  return prevUrl != next.baseUrl;
}

/// Re-asserts the NGL color-gamma standard ([kNglLightGammaConfig] at
/// `cfg.light.gc`, plus `if.live.no-gc:false`) on the currently-connected
/// controller. Returns a callable the connect lifecycle fires imperatively so
/// no widget has to watch a provider to keep gamma healthy.
///
/// LAN mode only. [pushGammaConfig] does a raw-HTTP cfg readback + POST against
/// the device IP; the relay path can't read cfg back cheaply
/// ([CloudRelayRepository.getConfig] returns null and there is no getCfg relay
/// command), so relay connects are skipped rather than growing new bridge
/// plumbing for a cosmetic self-heal.
///
/// Idempotent + non-blocking: [pushGammaConfig] writes nothing when the device
/// already matches, so a healthy controller is silent. A drift that gets
/// corrected emits ONE debug line (gamma is invisible-until-wrong — no
/// user-facing surface). Any failure is swallowed; the next connect retries
/// naturally (no polling, no retry loop).
final gammaSelfHealProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo is! WledService) return; // LAN only (see above)
    final ip = Uri.tryParse(repo.baseUrl)?.host;
    if (ip == null || ip.isEmpty) return;

    final action = ref.read(gammaSelfHealActionProvider);
    try {
      final result = await action(ip);
      if (result.success && !result.noChange) {
        // Drift detected and (re-)written. Single debug line only.
        final note = result.warnings.isEmpty ? 'ok' : result.warnings.join('; ');
        debugPrint('[GammaSelfHeal] re-asserted cfg.light.gc on $ip ($note)');
      }
      // noChange (already correct) or !success → silent; failure retries next connect.
    } catch (e) {
      debugPrint('[GammaSelfHeal] skipped on $ip — retry next connect ($e)');
    }
  };
});
