// scripts/_verify_gamma_chokepoint.dart
//
// RIG VERIFICATION for the gamma fix — audit/GAMMA_FIX.md.
// NOT part of the unit suite: this talks to real hardware over HTTP. Run it
// explicitly against a reachable controller:
//
//   flutter test scripts/_verify_gamma_chokepoint.dart --dart-define=RIG=192.168.1.150
//
// Every assertion reads /cfg.json — the LittleFS FILE — not /json/cfg (the live
// serialise). That distinction is the whole point: the firmware defect persists
// the wipe to flash, so the file is the only readback that proves durability.
//
// Every payload is written with the device's CURRENT values, so a pass leaves
// the controller functionally untouched.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

const String kRig = String.fromEnvironment('RIG', defaultValue: '192.168.1.150');

/// A cfg POST triggers a LittleFS flash save. While that save is in flight the
/// controller answers subsequent GETs with an EMPTY body — the same post-commit
/// stall schedule_sync already models. Give it room before every readback.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 1500));

Future<Map<String, dynamic>> readCfgFile() async {
  // Retry on the empty-body stall rather than reporting it as a gamma failure.
  for (var attempt = 0; ; attempt++) {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse('http://$kRig/cfg.json'));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (body.trim().isNotEmpty) {
        return jsonDecode(body) as Map<String, dynamic>;
      }
      if (attempt >= 4) {
        throw StateError('cfg.json returned an empty body 5× — controller '
            'is not serving config (not a gamma result)');
      }
    } catch (e) {
      if (attempt >= 4) rethrow;
    }
    await settle();
  }
}

Future<Map<String, dynamic>> readGamma() async {
  final cfg = await readCfgFile();
  return ((cfg['light'] as Map)['gc'] as Map).cast<String, dynamic>();
}

/// Raw POST that BYPASSES the app — used only to re-arm the bug for a
/// before/after contrast, never as part of the fix's own path.
Future<void> rawPost(Map<String, dynamic> body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final req = await client.postUrl(Uri.parse('http://$kRig/json/cfg'));
  req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  final bytes = utf8.encode(jsonEncode(body));
  req.contentLength = bytes.length;
  req.add(bytes);
  final res = await req.close().timeout(const Duration(seconds: 30));
  await res.transform(utf8.decoder).join();
  client.close(force: true);
  await settle();
}

void expectGammaOn(Map<String, dynamic> gc, String what) {
  expect(gc['col'], 2.8, reason: '$what — colour gamma must stay ON (col:2.8). '
      'col:1 means the firmware defect fired and it is on flash.');
  expect(gc['bri'], 1, reason: '$what — bri gamma unchanged');
  expect(gc['val'], 2.8, reason: '$what — exponent unchanged');
}

void main() {
  late WledService svc;
  late List<Map<String, dynamic>> originalTimers;
  late Map<String, dynamic> originalNtp;

  setUpAll(() async {
    svc = WledService('http://$kRig');
    final cfg = await readCfgFile();
    originalTimers = ((cfg['timers'] as Map)['ins'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    originalNtp = Map<String, dynamic>.from((cfg['if'] as Map)['ntp'] as Map);
    // ignore: avoid_print
    print('RIG $kRig — baseline light.gc = ${jsonEncode((cfg['light'] as Map)['gc'])}');
  });

  test('0. PRE-STATE — colour gamma is ON before we start', () async {
    expectGammaOn(await readGamma(), 'pre-state');
  });

  test('1. the DEFECT still exists in firmware (raw POST, app bypassed)', () async {
    // Proves the test is meaningful: without the app's injection, a cfg write
    // still wipes gamma on this firmware. If this ever stops failing, the
    // firmware was patched and the fix can be revisited.
    await rawPost({'if': {'ntp': {'tz': originalNtp['tz']}}});
    final gc = await readGamma();
    expect(gc['col'], 1,
        reason: 'raw cfg POST without light.gc should still wipe gamma — '
            'this is the defect the app now works around');
    expect(gc['val'], 2.8, reason: 'val survives — the fingerprint');
  });

  test('2. schedule sync through WledService.applyConfig KEEPS gamma', () async {
    // Writer #1, the highest-frequency one. Same timers the device already
    // has → functionally inert, but pre-fix this wiped gamma every time.
    // Gamma is currently OFF (test 1 left it that way), so this also proves
    // the injection REPAIRS as well as preserves.
    final ok = await svc.applyConfig({
      'timers': {'ins': originalTimers},
    });
    expect(ok, isTrue, reason: 'the cfg write itself must still succeed');
    await settle();
    expectGammaOn(await readGamma(), 'after schedule-sync applyConfig');
  });

  test('3. the timers actually landed — no cfg regression', () async {
    final ins = await svc.fetchTimerInstances();
    expect(ins, isNotNull);
    expect(ins!.length, originalTimers.length,
        reason: 'injecting light.gc must not disturb the timer table');
    for (var i = 0; i < originalTimers.length; i++) {
      expect(ins[i]['hour'], originalTimers[i]['hour']);
      expect(ins[i]['min'], originalTimers[i]['min']);
      expect(ins[i]['macro'], originalTimers[i]['macro']);
      expect(ins[i]['dow'], originalTimers[i]['dow']);
    }
  });

  test('4. lease-sweep shaped write KEEPS gamma', () async {
    // Writer #2 — same top-level key, separate call site, runs unattended.
    await rawPost({'if': {'ntp': {'tz': originalNtp['tz']}}}); // re-arm
    expect((await readGamma())['col'], 1, reason: 're-armed');

    await svc.applyConfig({
      'timers': {'ins': originalTimers},
    });
    await settle();
    expectGammaOn(await readGamma(), 'after lease-sweep applyConfig');
  });

  test('5. NTP + coords writes KEEP gamma and still land', () async {
    await rawPost({'if': {'ntp': {'tz': originalNtp['tz']}}}); // re-arm
    expect((await readGamma())['col'], 1, reason: 're-armed');

    await svc.applyConfig({
      'if': {
        'ntp': {
          'lt': originalNtp['lt'],
          'ln': originalNtp['ln'],
        },
      },
    });
    await settle();
    expectGammaOn(await readGamma(), 'after coords applyConfig');

    final cfg = await readCfgFile();
    final ntp = (cfg['if'] as Map)['ntp'] as Map;
    expect(ntp['lt'], originalNtp['lt'], reason: 'coords must still land');
    expect(ntp['ln'], originalNtp['ln']);
    expect(ntp['tz'], originalNtp['tz'], reason: 'tz untouched');
    expect(ntp['host'], originalNtp['host'], reason: 'ntp host untouched');
  });

  test('6. AudioReactive heal payload KEEPS gamma (the healer self-wipe)', () async {
    // Writer #6 — the write that used to destroy the gamma the healer had
    // asserted one step earlier.
    await rawPost({'if': {'ntp': {'tz': originalNtp['tz']}}}); // re-arm
    expect((await readGamma())['col'], 1, reason: 're-armed');

    await svc.applyConfig({
      'um': {
        'AudioReactive': {'enabled': false},
      },
    });
    await settle();
    expectGammaOn(await readGamma(), 'after AudioReactive applyConfig');
  });

  test('7. FULL HEALER RUN with AudioReactive ENABLED — gamma survives', () async {
    // The end-to-end case the ordering fix exists for. Enable AR (the state
    // that makes the healer perform its cfg write), wipe gamma, then run the
    // REAL healer and assert it both disables AR and leaves gamma ON.
    await rawPost({
      'um': {'AudioReactive': {'enabled': true}},
    });
    expect(await svc.readAudioReactiveEnabled(), isTrue,
        reason: 'AR must be enabled for this test to exercise step (d)');
    expect((await readGamma())['col'], 1,
        reason: 'enabling AR also wiped gamma — the defect, once more');

    final healer = ControllerDefaultsHealer(
      repo: svc,
      isLan: true,
      controllerIp: kRig,
      ctx: ControllerHealContext(
        profileLat: originalNtp['lt'] as double?,
        profileLon: originalNtp['ln'] as double?,
        ianaTimezone: 'America/Chicago',
        resolvePhonePosition: () async => null,
        now: DateTime.now,
        phoneUtcOffset: DateTime.now().timeZoneOffset,
      ),
      gammaAction: (ip) => pushGammaConfig(ip),
    );
    final report = await healer.run();
    await settle();

    // ignore: avoid_print
    print('healer report: audioReactiveHealed=${report.audioReactiveHealed} '
        'gammaHealed=${report.gammaHealed} rebooted=${report.rebooted} '
        'log=${report.log}');

    expect(report.audioReactiveHealed, isTrue,
        reason: 'the healer should have disabled AR');
    expect(await svc.readAudioReactiveEnabled(), isFalse,
        reason: 'AR must actually be off on the device');

    // THE RESULT THAT MATTERS: gamma is ON at the end of a healer run whose
    // AudioReactive step used to destroy it.
    expectGammaOn(await readGamma(), 'after a FULL healer run');

    // ...and gammaHealed is FALSE, which is the CORRECT post-fix outcome, not
    // a miss. Gamma went in wiped (enabling AR above wiped it). The AR heal at
    // step (d) now carries light.gc through the chokepoint, so it REPAIRED
    // gamma on its way past; by the time step (f) evaluated, the device was
    // already correct and pushGammaConfig skipped (noChange → not "healed").
    //
    // Pre-fix, this same run ended with gamma OFF and gammaHealed TRUE. That
    // exact inversion — the flag asserting the opposite of the device state —
    // is what fixes 1 and 2 together eliminate.
    expect(report.gammaHealed, isFalse,
        reason: 'the chokepoint repaired gamma before the gamma step ran, so '
            'the gamma step correctly had nothing to do');
    expect(report.log.where((l) => l.contains('gamma')), isEmpty,
        reason: 'no gamma failure or unverified-heal complaints');
    expect(report.rebooted, isFalse, reason: 'AR/gamma must never reboot');
  });

  test('8. FINAL — rig left healthy', () async {
    expectGammaOn(await readGamma(), 'final state');
    final cfg = await readCfgFile();
    expect(((cfg['if'] as Map)['live'] as Map)['no-gc'], false);
    expect(await svc.readAudioReactiveEnabled(), isFalse);
    expect(((cfg['timers'] as Map)['ins'] as List).length,
        originalTimers.length);
    // ignore: avoid_print
    print('FINAL /cfg.json light.gc = ${jsonEncode((cfg['light'] as Map)['gc'])}');
  });
}
