import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';

/// #112 — an UNCHANGED connectivity result is re-emitted at most every 30 s
/// (Direct / offline) or 120 s (Via Bridge); a CHANGED result passes at once.
///
/// Every emission rebuilds `wledRepositoryProvider`, and every rebuild re-runs
/// its dependents — over the relay `clockHealthProvider` became a `getInfo`
/// command every 10.0 s (2026-09-12 flood).
void main() {
  final t0 = DateTime.utc(2026, 9, 16, 18);

  Future<List<ConnectivityStatus>> run(
    List<(int, ConnectivityStatus)> script,
  ) async {
    var now = t0;
    final ctrl = StreamController<ConnectivityStatus>();
    final out = <ConnectivityStatus>[];
    final sub = suppressRepeatedConnectivity(ctrl.stream, clock: () => now)
        .listen(out.add);
    for (final (atSeconds, status) in script) {
      now = t0.add(Duration(seconds: atSeconds));
      ctrl.add(status);
      await pumpEventQueue();
    }
    await ctrl.close();
    await sub.cancel();
    return out;
  }

  test('the first result always passes', () async {
    expect(await run([(0, ConnectivityStatus.local)]),
        [ConnectivityStatus.local]);
  });

  test('Direct: identical results inside 30 s are suppressed', () async {
    final out = await run([
      (0, ConnectivityStatus.local),
      (10, ConnectivityStatus.local),
      (20, ConnectivityStatus.local),
      (29, ConnectivityStatus.local),
    ]);
    expect(out, [ConnectivityStatus.local]);
  });

  test('Direct: an identical result re-emits once 30 s have passed', () async {
    final out = await run([
      (0, ConnectivityStatus.local),
      (10, ConnectivityStatus.local),
      (30, ConnectivityStatus.local),
      (40, ConnectivityStatus.local),
      (60, ConnectivityStatus.local),
    ]);
    expect(out, List.filled(3, ConnectivityStatus.local)); // t=0, 30, 60
  });

  test('Via Bridge: identical results re-emit only every 120 s', () async {
    final script = [
      for (var s = 0; s <= 240; s += 10) (s, ConnectivityStatus.remote),
    ];
    final out = await run(script);
    expect(out, List.filled(3, ConnectivityStatus.remote)); // t=0, 120, 240
  });

  test('a CHANGE passes immediately, however recent the last emission', () async {
    final out = await run([
      (0, ConnectivityStatus.local),
      (1, ConnectivityStatus.remote),
      (2, ConnectivityStatus.local),
      (3, ConnectivityStatus.offline),
    ]);
    expect(out, [
      ConnectivityStatus.local,
      ConnectivityStatus.remote,
      ConnectivityStatus.local,
      ConnectivityStatus.offline,
    ]);
  });

  test('the repeat window is measured from the last EMISSION', () async {
    final out = await run([
      (0, ConnectivityStatus.remote),
      (100, ConnectivityStatus.local), // change → emits, restarts the clock
      (125, ConnectivityStatus.local), // 25 s after → suppressed
      (131, ConnectivityStatus.local), // 31 s after → emits
    ]);
    expect(out, [
      ConnectivityStatus.remote,
      ConnectivityStatus.local,
      ConnectivityStatus.local,
    ]);
  });

  test('interval per status', () {
    expect(connectivityRepeatInterval(ConnectivityStatus.local),
        const Duration(seconds: 30));
    expect(connectivityRepeatInterval(ConnectivityStatus.offline),
        const Duration(seconds: 30));
    expect(connectivityRepeatInterval(ConnectivityStatus.remote),
        const Duration(seconds: 120));
  });
}
