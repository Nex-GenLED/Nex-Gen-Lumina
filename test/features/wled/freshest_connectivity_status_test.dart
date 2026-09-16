import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';

/// #114 TAIL — while the connectivity stream is restarting (app resume clears
/// the SSID cache and forces a fresh check), the repository used to fall back
/// to the last EMITTED status. On iOS a fresh check can take seconds, so
/// commands kept going to the bridge for 3–7 s after a completed check had
/// already said "local" (observed 2026-09-16 14:53:28–34Z).
///
/// The fallback now prefers whichever is NEWER: the last emitted status, or
/// the last completed check.
ConnectivityCheckSnapshot check(String outcome, DateTime at) =>
    ConnectivityCheckSnapshot(
      checkedAt: at,
      reportedTypes: const ['wifi'],
      wifiReported: true,
      outcome: outcome,
      reason: ConnectivityCheckReason.ssidMatched,
    );

void main() {
  final t0 = DateTime.utc(2026, 9, 16, 14, 53, 20);

  test('a completed check NEWER than the cached emission wins', () {
    expect(
      freshestKnownStatus(
        cached: ConnectivityStatus.remote,
        cachedAt: t0,
        lastCheck: check('local', t0.add(const Duration(seconds: 8))),
      ),
      ConnectivityStatus.local,
    );
  });

  test('an OLDER completed check does not override a newer emission', () {
    expect(
      freshestKnownStatus(
        cached: ConnectivityStatus.local,
        cachedAt: t0.add(const Duration(seconds: 8)),
        lastCheck: check('remote', t0),
      ),
      ConnectivityStatus.local,
    );
  });

  test('with no completed check, the cached emission is used', () {
    expect(
      freshestKnownStatus(
        cached: ConnectivityStatus.remote,
        cachedAt: t0,
        lastCheck: null,
      ),
      ConnectivityStatus.remote,
    );
  });

  test('with no cached emission, the completed check is used', () {
    expect(
      freshestKnownStatus(
        cached: null,
        cachedAt: null,
        lastCheck: check('local', t0),
      ),
      ConnectivityStatus.local,
    );
  });

  test('nothing known at all stays null (repository stays null, as before)', () {
    expect(
      freshestKnownStatus(cached: null, cachedAt: null, lastCheck: null),
      isNull,
    );
  });

  test('every outcome string maps back to its status', () {
    for (final s in ConnectivityStatus.values) {
      expect(
        freshestKnownStatus(
          cached: null,
          cachedAt: null,
          lastCheck: check(s.name, t0),
        ),
        s,
      );
    }
  });

  test('an unrecognised outcome falls back to the cached value', () {
    expect(
      freshestKnownStatus(
        cached: ConnectivityStatus.remote,
        cachedAt: t0,
        lastCheck: check('nonsense', t0.add(const Duration(seconds: 5))),
      ),
      ConnectivityStatus.remote,
    );
  });
}
