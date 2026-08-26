// Part C — one shared HttpClient per connect-timeout, not one per call site.
//
// Two defects in the old shape (audit/SYNC_PACING_FIX_STATUS.md §1(d), and P1
// of the fix prompt):
//   1. Fifteen separate `HttpClient()` instantiations, each force-closed after
//      its single request — so every call was a fresh TCP connect + teardown.
//   2. Fourteen of the fifteen closes sat on the SUCCESS path inside `try`,
//      with no `finally`. Any throw before the close — overwhelmingly a
//      TIMEOUT — leaked the client and its socket. Self-amplifying exactly
//      when the controller starts to struggle.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

void main() {
  setUp(resetWledHttpClientsForTest);
  tearDown(resetWledHttpClientsForTest);

  test('the same connect-timeout resolves to the SAME client instance', () {
    final a = wledClientForTest(const Duration(seconds: 15));
    final b = wledClientForTest(const Duration(seconds: 15));
    expect(identical(a, b), isTrue, reason: 'reuse, not re-instantiation');
    expect(wledHttpClientCacheSize(), 1);
  });

  test('different connect-timeouts get their own client', () {
    wledClientForTest(const Duration(seconds: 5));
    wledClientForTest(const Duration(seconds: 10));
    wledClientForTest(const Duration(seconds: 15));
    expect(wledHttpClientCacheSize(), 3);
  });

  // The consolidation's whole point: the service has three distinct timeouts
  // (5s ×1, 10s ×3, 15s ×11) across fifteen sites. Repeated resolution must
  // never grow past those three.
  test('many resolutions never exceed the distinct-timeout count', () {
    for (var i = 0; i < 50; i++) {
      wledClientForTest(const Duration(seconds: 15));
      wledClientForTest(const Duration(seconds: 10));
      wledClientForTest(const Duration(seconds: 5));
    }
    expect(wledHttpClientCacheSize(), 3,
        reason: '50 rounds of 3 timeouts must still be 3 clients');
  });

  test('the resolved client carries the requested connect timeout', () {
    final c = wledClientForTest(const Duration(seconds: 10));
    expect(c.connectionTimeout, const Duration(seconds: 10));
  });

  test('reset clears the cache so tests cannot bleed into each other', () {
    wledClientForTest(const Duration(seconds: 15));
    expect(wledHttpClientCacheSize(), 1);
    resetWledHttpClientsForTest();
    expect(wledHttpClientCacheSize(), 0);
  });

  test('the cached object really is an HttpClient', () {
    expect(wledClientForTest(const Duration(seconds: 15)), isA<HttpClient>());
  });
}
