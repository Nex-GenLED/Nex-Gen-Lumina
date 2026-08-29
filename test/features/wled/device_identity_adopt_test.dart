// #94 — VERIFY-AND-ADOPT, message routing, and the stale-park TTL.
//
// #93 shipped an identity guard that compares the Firestore controller DOC ID
// against the MAC the device reports. Controller documents created before the
// claim-fix are keyed by IP (`192_168_1_150`) or by a Firestore auto-id
// (`g6YTg5yhRXOaUvfdM6qL`) and carry no `mac` field at all, so they can never
// match. #93 therefore refused EVERY write on those accounts — four live
// customers locked out of their own lights, shown a connectivity banner while
// a healthy controller sat there answering.
//
// A non-MAC-shaped expectation is not a WRONG expectation. It is the ABSENCE
// of one, and the correct response is to learn the identity, not to refuse.
//
// The existing `device_identity_test.dart` covers #92/#92b and must stay green:
// its `_expectedId` is MAC-shaped, so every refusal it asserts still refuses.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexgen_command/features/wled/device_identity.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// Non-routable TEST-NET-1 (RFC 5737), so `_simulate` stays FALSE — a
/// localhost base URL would put WledService in simulation mode and skip the
/// guard entirely, making these tests vacuous.
const _host = 'http://192.0.2.10';

/// A real, MAC-shaped controller doc id.
const _macShapedId = '80_f3_da_b4_d1_50';

/// The two legacy, identity-less doc-id classes actually present in the fleet.
const _legacyIpId = '192_168_1_150';
const _legacyAutoId = 'g6YTg5yhRXOaUvfdM6qL';

/// Serves a canned `/json/info` and counts probes, so no socket is opened.
class _AdoptingService extends WledService {
  _AdoptingService({
    required String? mac,
    required this.reachable,
    required String expectedId,
    void Function(String)? onAdopt,
  })  : _mac = mac,
        super(_host,
            expectedControllerId: expectedId, onIdentityAdopted: onAdopt);

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
  // reaches the guard, so the binding and a mock store are required.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WledService.resetDeviceVerificationForTest();
    clearIdentityRefusal();
    identityRefusalClock = DateTime.now;
  });

  tearDown(() {
    WledService.resetDeviceVerificationForTest();
    clearIdentityRefusal();
    identityRefusalClock = DateTime.now;
  });

  group('#94 isMacShapedId', () {
    test('accepts every shape a real MAC arrives in', () {
      expect(isMacShapedId('80f3daae6f04'), isTrue);
      expect(isMacShapedId('80_f3_da_ae_6f_04'), isTrue);
      expect(isMacShapedId('80:F3:DA:AE:6F:04'), isTrue);
      expect(isMacShapedId('80-f3-da-ae-6f-04'), isTrue);
    });

    test('rejects both legacy doc-id classes', () {
      expect(isMacShapedId(_legacyIpId), isFalse,
          reason: '192_168_1_150 canonicalises to 1921681150 — ten digits');
      expect(isMacShapedId(_legacyAutoId), isFalse);
      expect(isMacShapedId(''), isFalse);
    });

    test('rejects a hex string of the wrong length', () {
      expect(isMacShapedId('80f3daae6f'), isFalse);
      expect(isMacShapedId('80f3daae6f0400'), isFalse);
    });
  });

  group('#94 assertDeviceIdentity — adoption', () {
    test('legacy IP-keyed id + a device that names itself → ADOPT', () {
      final r = assertDeviceIdentity(
        baseUrl: _host,
        expectedControllerId: _legacyIpId,
        info: const {'mac': '80f3daae6f04'},
      );
      expect(r.adopted, isTrue);
      expect(r.adoptedMac, '80f3daae6f04');
    });

    test('legacy auto-id adopts too', () {
      final r = assertDeviceIdentity(
        baseUrl: _host,
        expectedControllerId: _legacyAutoId,
        info: const {'mac': '80:F3:DA:B3:B8:20'},
      );
      expect(r.adopted, isTrue);
      expect(r.adoptedMac, '80f3dab3b820',
          reason: 'the adopted value is canonical, ready to write');
    });

    test('legacy id + UNREACHABLE stays unverifiable — adoption must not '
        'weaken the unreachable contract', () {
      expect(
        () => assertDeviceIdentity(
          baseUrl: _host,
          expectedControllerId: _legacyIpId,
          info: null,
        ),
        throwsA(isA<WledDeviceUnverifiableException>()),
      );
    });

    test('legacy id + a reachable device naming NO mac → proceeds with '
        'nothing to adopt', () {
      final r = assertDeviceIdentity(
        baseUrl: _host,
        expectedControllerId: _legacyIpId,
        info: const {'ver': '0.15.1'},
      );
      expect(r.adopted, isTrue);
      expect(r.adoptedMac, isNull,
          reason: 'no identity to write, but none was violated either — '
              'refusing here would re-create the lockout #94 exists to end');
    });

    test('a MAC-shaped mismatch STILL refuses — #94 must not widen #93', () {
      expect(
        () => assertDeviceIdentity(
          baseUrl: _host,
          expectedControllerId: _macShapedId,
          info: const {'mac': '80f3dab3b820'},
        ),
        throwsA(isA<WledDeviceMismatchException>().having(
          (e) => e.userMessage,
          'userMessage',
          'A different device answered at this address — check your network',
        )),
      );
    });

    test('a MAC-shaped match reports verified, not adopted', () {
      final r = assertDeviceIdentity(
        baseUrl: _host,
        expectedControllerId: _macShapedId,
        info: const {'mac': '80f3dab4d150'},
      );
      expect(r.adopted, isFalse);
      expect(r.adoptedMac, isNull);
    });
  });

  group('#94 WledService — adoption reaches the write path', () {
    test('legacy id + reachable → guard PASSES and the adoption signal fires '
        'exactly once per session', () async {
      final adopted = <String>[];
      final svc = _AdoptingService(
        mac: '80f3daae6f04',
        reachable: true,
        expectedId: _legacyIpId,
        onAdopt: adopted.add,
      );

      await svc.assertExpectedDeviceForTest();

      expect(adopted, ['80f3daae6f04'],
          reason: 'the doc must gain the mac it never had');
      expect(takeIdentityRefusalMessage(), isNull,
          reason: 'an adoption is not a refusal — nothing may be parked');

      // The session cache holds: no second probe, no duplicate adoption write.
      await svc.assertExpectedDeviceForTest();
      await svc.assertExpectedDeviceForTest();
      expect(svc.getInfoCalls, 1);
      expect(adopted, hasLength(1));
    });

    test('legacy id + reachable → applyJson is NOT refused by the guard',
        () async {
      final svc = _AdoptingService(
        mac: '80f3daae6f04',
        reachable: true,
        expectedId: _legacyIpId,
        onAdopt: (_) {},
      );
      // The HTTP write cannot complete against TEST-NET-1, but the guard must
      // not be what stopped it: no refusal may be parked.
      await svc.applyJson(const {'on': true});
      expect(takeIdentityRefusalMessage(), isNull,
          reason: 'pre-#94 this parked "a different device answered" and no '
              'HTTP was attempted at all');
    });

    test('legacy id + UNREACHABLE refuses with the unreachable sentence and '
        'adopts nothing', () async {
      final adopted = <String>[];
      final svc = _AdoptingService(
        mac: null,
        reachable: false,
        expectedId: _legacyIpId,
        onAdopt: adopted.add,
      );
      final ok = await svc.applyJson(const {'on': true});
      expect(ok, isFalse);
      expect(adopted, isEmpty);
      expect(takeIdentityRefusalMessage(),
          "Can't reach your controller on this network");
    });

    test('a MAC-shaped mismatch still refuses at the service door', () async {
      final svc = _AdoptingService(
        mac: '80f3dab3b820',
        reachable: true,
        expectedId: _macShapedId,
        onAdopt: (_) => fail('a mismatch must never adopt'),
      );
      final ok = await svc.applyJson(const {'on': true});
      expect(ok, isFalse);
      expect(takeIdentityRefusalMessage(),
          'A different device answered at this address — check your network');
    });

    test('an adoption callback that throws does not fail the light command',
        () async {
      final svc = _AdoptingService(
        mac: '80f3daae6f04',
        reachable: true,
        expectedId: _legacyIpId,
        onAdopt: (_) => throw StateError('firestore offline'),
      );
      await expectLater(svc.assertExpectedDeviceForTest(), completes);
      expect(takeIdentityRefusalMessage(), isNull);
    });
  });

  // ===========================================================================
  // STALE PARK
  //
  // Take-once was not enough. Three reporters never consumed the park, so a
  // refusal they dropped stayed parked and the NEXT failure — an ordinary
  // timeout, minutes or hours later — popped it and told the user "a different
  // device answered". A stale park does not merely fail to inform; it
  // misattributes.
  // ===========================================================================

  group('#94 refusal park TTL', () {
    test('a park inside the TTL is claimable', () {
      var now = DateTime(2026, 8, 28, 22, 0, 0);
      identityRefusalClock = () => now;
      recordIdentityRefusal(WledDeviceMismatchException(
        baseUrl: _host,
        expectedControllerId: _macShapedId,
        reportedMac: '80f3dab3b820',
      ));
      now = now.add(const Duration(seconds: 9));
      expect(takeIdentityRefusalMessage(),
          'A different device answered at this address — check your network');
    });

    test('a park older than the TTL expires → generic message, no '
        'cross-attribution', () {
      var now = DateTime(2026, 8, 28, 22, 0, 0);
      identityRefusalClock = () => now;
      recordIdentityRefusal(WledDeviceMismatchException(
        baseUrl: _host,
        expectedControllerId: _macShapedId,
        reportedMac: '80f3dab3b820',
      ));
      // A later, UNRELATED failure — exactly the shape that produced the bug.
      now = now.add(const Duration(seconds: 11));
      expect(takeIdentityRefusalMessage(), isNull,
          reason: 'the caller falls back to its own generic sentence');
    });

    test('an expired park is cleared, not left to poison the next failure',
        () {
      var now = DateTime(2026, 8, 28, 22, 0, 0);
      identityRefusalClock = () => now;
      recordIdentityRefusal(WledDeviceUnverifiableException(
        baseUrl: _host,
        expectedControllerId: _macShapedId,
      ));
      now = now.add(const Duration(minutes: 5));
      expect(takeIdentityRefusalMessage(), isNull);
      now = now.add(const Duration(seconds: 1));
      expect(takeIdentityRefusalMessage(), isNull,
          reason: 'consumed on the expiring read; nothing survives it');
    });

    test('take-once still holds inside the TTL', () {
      var now = DateTime(2026, 8, 28, 22, 0, 0);
      identityRefusalClock = () => now;
      recordIdentityRefusal(WledDeviceUnverifiableException(
        baseUrl: _host,
        expectedControllerId: _macShapedId,
      ));
      expect(takeIdentityRefusalMessage(), isNotNull);
      expect(takeIdentityRefusalMessage(), isNull);
    });
  });

  // ===========================================================================
  // ALL FOUR REPORTING SURFACES
  //
  // Source-level rather than four widget harnesses, deliberately: the defect
  // was that a surface HARD-CODED the generic banner and never consulted the
  // park. That is a property of the call site, and this is the cheapest check
  // that fails when a fifth surface repeats the mistake.
  // ===========================================================================

  group('#94 every failure reporter consults the park', () {
    // file → how many generic banners it shows (each needs a park read)
    const surfaces = <String, int>{
      'lib/features/wled/wled_providers.dart': 2,
      'lib/features/design/manual_editor/manual_design_editor.dart': 1,
      'lib/features/design/screens/ai_design_studio_screen.dart': 1,
    };

    test('no surface shows the generic banner without first taking the '
        'parked refusal', () {
      for (final entry in surfaces.entries) {
        final src = File(entry.key).readAsStringSync();
        final generic =
            "Couldn't reach your lights".allMatches(src).length;
        final takes = 'takeIdentityRefusalMessage('.allMatches(src).length;
        expect(
          takes,
          greaterThanOrEqualTo(entry.value),
          reason: '${entry.key} shows $generic generic banner(s) but reads the '
              'park only $takes time(s). A reporter that never consults the '
              'park is the #94 defect.',
        );
      }
    });

    test('the mismatch sentence is defined exactly once, in device_identity',
        () {
      final src =
          File('lib/features/wled/device_identity.dart').readAsStringSync();
      expect(src.contains('A different device answered at this address'),
          isTrue);
      for (final f in [
        'lib/features/wled/wled_providers.dart',
        'lib/features/design/manual_editor/manual_design_editor.dart',
        'lib/features/design/screens/ai_design_studio_screen.dart',
      ]) {
        expect(
          File(f).readAsStringSync().contains('A different device answered'),
          isFalse,
          reason: '$f must route the sentence, never restate it — three '
              'copies drift into three explanations',
        );
      }
    });
  });
}
