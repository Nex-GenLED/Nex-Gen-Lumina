// Device identity before writing (#92 fix C).
//
// An IP is an address, not an identity. DHCP reassigns it, customers swap
// hardware, and 192.168.1.250 is a default router address that FOUR unrelated
// accounts in this fleet independently use. Before #92 nothing compared the
// device that answered against the controller the app meant to drive, so a
// stale or reused address meant writing to someone else's lights — silently,
// and reporting success.
//
// The decision is pure (`assertDeviceIdentity`) precisely so all three
// outcomes are testable with no socket: MATCH proceeds, MISMATCH refuses,
// UNREADABLE refuses. The service-level tests then prove the two properties
// that a pure function cannot: exactly ONE extra getInfo per session (the
// cache works), and NO HTTP write is issued on a refusal (the throw happens
// before the request is built).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/features/wled/device_identity.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// Non-routable TEST-NET-1 (RFC 5737). Chosen so `_simulate` stays FALSE — a
/// 127.0.0.1/localhost base URL puts WledService into simulation mode, which
/// skips the guard entirely and would make these tests vacuous.
const _host = 'http://192.0.2.10';
const _expectedId = '80_f3_da_b4_d1_50';

/// Counts getInfo calls and serves a canned body, so no socket is opened.
class _CountingService extends WledService {
  _CountingService({required String? mac, required this.reachable})
      : _mac = mac,
        super(_host, expectedControllerId: _expectedId);

  final String? _mac;
  final bool reachable;
  int getInfoCalls = 0;

  @override
  Future<WledInfoResponse?> getInfo() async {
    getInfoCalls++;
    if (!reachable) return null;
    return WledInfoResponse(
      maxseg: 16,
      arch: 'esp32',
      ver: '0.15.1',
      raw: {if (_mac != null) 'mac': _mac, 'ver': '0.15.1'},
    );
  }
}

void main() {
  // applyJson reads the participation cache (SharedPreferences) before it
  // reaches the guard, so the binding and a mock store are required for the
  // service-level tests below.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WledService.resetDeviceVerificationForTest();
  });
  tearDown(WledService.resetDeviceVerificationForTest);

  group('canonicalDeviceId', () {
    test('normalizes every shape this fleet actually stores', () {
      const want = '80f3dab4d150';
      expect(canonicalDeviceId('80_f3_da_b4_d1_50'), want, reason: 'doc id');
      expect(canonicalDeviceId('80:F3:DA:B4:D1:50'), want, reason: 'colon MAC');
      expect(canonicalDeviceId('80-f3-da-b4-d1-50'), want, reason: 'hyphen');
      expect(canonicalDeviceId('80F3DAB4D150'), want, reason: 'upper, bare');
      expect(canonicalDeviceId('80f3dab4d150'), want, reason: 'as reported');
    });

    test('empty / junk collapses to empty rather than matching anything', () {
      expect(canonicalDeviceId(''), '');
      expect(canonicalDeviceId('::--__'), '');
    });
  });

  group('deviceIdentityMatches', () {
    test('matches across separator and case differences', () {
      expect(
        deviceIdentityMatches(
            reportedMac: '80f3dab4d150', expectedControllerId: _expectedId),
        isTrue,
      );
    });

    // The Nancy/Stegall shape: two real controllers, same LAN address.
    test('two real controllers at the same address do NOT match', () {
      expect(
        deviceIdentityMatches(
            reportedMac: '80f3dab3b820', // Stegall's device
            expectedControllerId: '80_f3_da_b4_d1_50'), // Nancy's doc id
        isFalse,
      );
    });

    test('null / empty MAC is NEVER a match', () {
      expect(
        deviceIdentityMatches(
            reportedMac: null, expectedControllerId: _expectedId),
        isFalse,
      );
      expect(
        deviceIdentityMatches(
            reportedMac: '', expectedControllerId: _expectedId),
        isFalse,
      );
    });

    test('an empty expectation never matches (no vacuous pass)', () {
      expect(
        deviceIdentityMatches(
            reportedMac: '80f3dab4d150', expectedControllerId: ''),
        isFalse,
      );
    });
  });

  group('assertDeviceIdentity (pure decision — three outcomes, not two)', () {
    test('MATCH returns normally', () {
      expect(
        () => assertDeviceIdentity(
          baseUrl: _host,
          expectedControllerId: _expectedId,
          info: const {'mac': '80f3dab4d150'},
        ),
        returnsNormally,
      );
    });

    test('MISMATCH throws WledDeviceMismatchException with the user sentence',
        () {
      expect(
        () => assertDeviceIdentity(
          baseUrl: _host,
          expectedControllerId: _expectedId,
          info: const {'mac': '80f3dab3b820'},
        ),
        throwsA(isA<WledDeviceMismatchException>().having(
          (e) => e.userMessage,
          'userMessage',
          'A different device answered at this address — check your network',
        )),
      );
    });

    test('UNREADABLE info throws Unverifiable — never treated as a pass', () {
      expect(
        () => assertDeviceIdentity(
          baseUrl: _host,
          expectedControllerId: _expectedId,
          info: null,
        ),
        throwsA(isA<WledDeviceUnverifiableException>()),
      );
    });

    test('info present but carrying NO mac is a refusal, not a pass', () {
      expect(
        () => assertDeviceIdentity(
          baseUrl: _host,
          expectedControllerId: _expectedId,
          info: const {'ver': '0.15.1'},
        ),
        throwsA(isA<WledDeviceMismatchException>()),
      );
    });
  });

  group('WledService guard — caching and no-write-on-refusal', () {
    test('MATCH passes and costs exactly ONE extra getInfo per session',
        () async {
      final svc = _CountingService(mac: '80f3dab4d150', reachable: true);

      await svc.assertExpectedDeviceForTest();
      expect(svc.getInfoCalls, 1, reason: 'first write of the session probes');

      // Three more writes in the same session must be free.
      await svc.assertExpectedDeviceForTest();
      await svc.assertExpectedDeviceForTest();
      await svc.assertExpectedDeviceForTest();
      expect(svc.getInfoCalls, 1,
          reason: 'the (address, controller) pair is cached for the process; '
              'a per-instance cache would re-probe on every provider rebuild');
    });

    // The load-bearing property: a refusal must happen BEFORE the request is
    // built. applyJson wraps its HTTP in try/catch and returns false on error,
    // so a guard placed inside that block would silently downgrade a refusal
    // to a no-op. These tests would time out against TEST-NET-1 if any HTTP
    // were attempted — they pass fast precisely because none is.
    test('MISMATCH refuses applyJson by THROWING, with no write on the wire',
        () async {
      final svc = _CountingService(mac: '80f3dab3b820', reachable: true);
      await expectLater(
        svc.applyJson(const {'on': true}),
        throwsA(isA<WledDeviceMismatchException>()),
      );
      expect(svc.getInfoCalls, 1);
    });

    test('UNREACHABLE info refuses applyJson — not a silent pass', () async {
      final svc = _CountingService(mac: null, reachable: false);
      await expectLater(
        svc.applyJson(const {'on': true}),
        throwsA(isA<WledDeviceUnverifiableException>()),
      );
      expect(svc.getInfoCalls, 1);
    });

    test('a refused pair is NOT cached — the next attempt re-probes', () async {
      final svc = _CountingService(mac: null, reachable: false);
      await expectLater(svc.applyJson(const {'on': true}),
          throwsA(isA<WledDeviceUnverifiableException>()));
      await expectLater(svc.applyJson(const {'on': true}),
          throwsA(isA<WledDeviceUnverifiableException>()));
      expect(svc.getInfoCalls, 2,
          reason: 'caching a failure would make a transient outage permanent '
              'for the rest of the process');
    });

    test('no expectation supplied → guard is skipped entirely (back-compat)',
        () async {
      // Every pre-#92 construction site (bench CLI, probes, tests) passes only
      // a base URL. Those must behave exactly as they did.
      final svc = WledService(_host);
      expect(svc.expectedControllerId, isNull);
      await svc.assertExpectedDeviceForTest(); // must not throw, must not probe
    });
  });
}
