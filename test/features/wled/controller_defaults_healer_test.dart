// Controller-defaults self-heal (2.5.2) — on-connect remediation of the silent
// schedule-killers clock-health detects (failed NTP host, UTC tz, 0,0 coords)
// plus the folded-in color-gamma standard. Policy is HEAL-ONLY-BROKEN.
//
// Coverage: pure planners (ntp host / tz mapping incl. unmappable fallback /
// coords source order + skip), the heal-only-broken orchestration matrix,
// reboot-only-on-clock-change, relay gating, gamma cases, the AudioReactive
// usermod disable, and the connect predicate. No HTTP: the repo is a recording
// fake, gamma is an injected action.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/audioreactive_health.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

// A recording WLED repo that also serves canned clock info. Extends the base
// (inheriting concrete defaults) and adds the ClockInfoSource capability.
class _FakeHealRepo extends WledRepository
    implements ClockInfoSource, AudioReactiveConfigSource {
  _FakeHealRepo(
    this._clockInfo, {
    this.applyConfigResult = true,
    this.stateResponse,
    this.audioReactiveEnabled,
    this.audioReactiveReadThrows = false,
    this.audioReactiveWriteSticks = true,
  });

  final ControllerClockInfo? _clockInfo;
  final bool applyConfigResult;

  /// Canned /json/state for the reboot-deferral gate (on/ps). Null = unreadable.
  final Map<String, dynamic>? stateResponse;

  /// Canned `cfg.um.AudioReactive.enabled`. Null models a firmware build with
  /// no AudioReactive usermod (or an unreadable cfg) — both mean "don't heal".
  bool? audioReactiveEnabled;
  final bool audioReactiveReadThrows;

  /// When false, a successful disable POST leaves the device flag ON — models a
  /// write that silently didn't take, so the readback verify has something to
  /// catch.
  final bool audioReactiveWriteSticks;

  int audioReactiveReads = 0;

  final List<Map<String, dynamic>> configPosts = [];
  final List<Map<String, dynamic>> jsonPosts = [];

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async => _clockInfo;

  @override
  Future<Map<String, dynamic>?> getState() async => stateResponse;

  @override
  Future<bool?> readAudioReactiveEnabled() async {
    audioReactiveReads++;
    if (audioReactiveReadThrows) throw Exception('cfg read boom');
    return audioReactiveEnabled;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    configPosts.add(cfg);
    if (applyConfigResult &&
        audioReactiveWriteSticks &&
        cfg.containsKey('um')) {
      audioReactiveEnabled = false; // the device honoured the disable
    }
    return applyConfigResult;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    jsonPosts.add(payload);
    return true;
  }

  // Unused abstract members.
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      true;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => true;
  @override
  Future<bool> configureSyncReceiver() async => true;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      true;
}

/// Records gamma-action invocations and returns a canned result.
class _GammaSpy {
  final List<String> calls = [];
  WledConfigPushResult result;
  bool throws = false;
  _GammaSpy({WledConfigPushResult? result})
      : result = result ?? WledConfigPushResult.skipped('already correct');

  GammaSelfHealAction get action => (ip) async {
        calls.add(ip);
        if (throws) throw Exception('gamma boom');
        return result;
      };
}

// A fixed "phone now" (harness clock is frozen; pass an explicit instant).
final DateTime _now = DateTime(2026, 7, 9, 20, 0, 0);

ControllerHealContext _ctx({
  double? profileLat,
  double? profileLon,
  String? iana,
  Duration phoneOffset = const Duration(hours: -6), // Central-ish; non-UTC
  Future<({double lat, double lon})?> Function()? phone,
}) {
  return ControllerHealContext(
    profileLat: profileLat,
    profileLon: profileLon,
    ianaTimezone: iana,
    resolvePhonePosition: phone ?? () async => null,
    now: () => _now,
    phoneUtcOffset: phoneOffset,
  );
}

ControllerDefaultsHealer _healer(
  _FakeHealRepo repo, {
  required bool isLan,
  ControllerHealContext? ctx,
  GammaSelfHealAction? gamma,
  String? ip = '192.168.1.250',
}) {
  return ControllerDefaultsHealer(
    repo: repo,
    isLan: isLan,
    controllerIp: ip,
    ctx: ctx ?? _ctx(),
    gammaAction: gamma ?? _GammaSpy().action,
  );
}

// Canned device states.
ControllerClockInfo _healthy() => ControllerClockInfo(
      deviceTime: _now, // synced
      tzIndex: 5, // non-UTC → no TZ_SUSPECT
      tzOffsetSeconds: 0,
      latitude: 41.88,
      longitude: -87.63,
      ntpHost: kHealNtpHost, // already good
    );

ControllerClockInfo _clockUnset() =>
    const ControllerClockInfo(deviceTime: null); // no readable time

ControllerClockInfo _locationUnset() => ControllerClockInfo(
      deviceTime: _now,
      tzIndex: 5,
      tzOffsetSeconds: 0,
      latitude: 0,
      longitude: 0,
      ntpHost: kHealNtpHost,
    );

ControllerClockInfo _tzSuspect() => ControllerClockInfo(
      deviceTime: _now,
      tzIndex: 0, // UTC
      tzOffsetSeconds: 0,
      latitude: 41.88,
      longitude: -87.63,
      ntpHost: kHealNtpHost,
    );

void main() {
  group('pure planner — ntpHostNeedsHeal', () {
    test('clock unset → heal (host unreadable is irrelevant)', () {
      expect(ntpHostNeedsHeal(clockUnset: true, currentHost: null), true);
      expect(ntpHostNeedsHeal(clockUnset: true, currentHost: kHealNtpHost), true);
    });
    test('clock ok + known-bad default host → heal', () {
      expect(ntpHostNeedsHeal(clockUnset: false, currentHost: kKnownBadNtpHost),
          true);
    });
    test('clock ok + good host → no heal', () {
      expect(ntpHostNeedsHeal(clockUnset: false, currentHost: kHealNtpHost),
          false);
    });
    test('clock ok + host unreadable (relay) → no heal', () {
      expect(ntpHostNeedsHeal(clockUnset: false, currentHost: null), false);
    });
  });

  group('pure planner — tzHealFor', () {
    test('not suspect → null', () {
      expect(
          tzHealFor(
              tzSuspect: false,
              ianaTimezone: 'America/Chicago',
              phoneOffset: Duration.zero),
          isNull);
    });
    test('mapped US zone → WLED enum index', () {
      expect(
          tzHealFor(
              tzSuspect: true,
              ianaTimezone: 'America/Chicago',
              phoneOffset: const Duration(hours: -6)),
          const TzHeal.index(5));
      expect(
          tzHealFor(
              tzSuspect: true,
              ianaTimezone: 'America/New_York',
              phoneOffset: const Duration(hours: -5)),
          const TzHeal.index(4));
      expect(
          tzHealFor(
              tzSuspect: true,
              ianaTimezone: 'America/Phoenix',
              phoneOffset: const Duration(hours: -7)),
          const TzHeal.index(7));
    });
    test('unmapped zone → offset-seconds fallback', () {
      expect(
          tzHealFor(
              tzSuspect: true,
              ianaTimezone: 'Europe/Paris',
              phoneOffset: const Duration(hours: 1)),
          const TzHeal.offset(3600));
    });
    test('null zone → offset-seconds fallback', () {
      expect(
          tzHealFor(
              tzSuspect: true,
              ianaTimezone: null,
              phoneOffset: const Duration(hours: -6)),
          const TzHeal.offset(-21600));
    });
  });

  group('pure planner — coordHealFor', () {
    test('not unset → null', () {
      expect(
          coordHealFor(
              locationUnset: false, profileLat: 0, profileLon: 0),
          isNull);
    });
    test('profile home wins, rounded to 2 dp', () {
      expect(
          coordHealFor(
              locationUnset: true,
              profileLat: 41.878114,
              profileLon: -87.629798,
              phoneLat: 1.23,
              phoneLon: 4.56),
          const CoordHeal(41.88, -87.63));
    });
    test('no profile → phone position, rounded', () {
      expect(
          coordHealFor(
              locationUnset: true,
              profileLat: null,
              profileLon: null,
              phoneLat: 30.267,
              phoneLon: -97.743),
          const CoordHeal(30.27, -97.74));
    });
    test('profile 0,0 treated as unset → falls through to phone', () {
      expect(
          coordHealFor(
              locationUnset: true,
              profileLat: 0,
              profileLon: 0,
              phoneLat: 30.27,
              phoneLon: -97.74),
          const CoordHeal(30.27, -97.74));
    });
    test('no source → skip (null)', () {
      expect(
          coordHealFor(
              locationUnset: true,
              profileLat: null,
              profileLon: null,
              phoneLat: null,
              phoneLon: null),
          isNull);
    });
  });

  group('pure planner — audioReactiveNeedsHeal', () {
    test('usermod ON → heal', () {
      expect(audioReactiveNeedsHeal(true), true);
    });
    test('already disabled → no heal', () {
      expect(audioReactiveNeedsHeal(false), false);
    });
    test('absent (non-AR build) or unreadable → no heal', () {
      // Null must never be treated as "on": a firmware without the usermod must
      // not have a `um` block written into it from nothing.
      expect(audioReactiveNeedsHeal(null), false);
    });
  });

  group('pure — audioReactiveEnabledFromCfg', () {
    test('reads the flag from a real captured cfg shape', () {
      // Shape taken from a live Dig-Octa-ESP32-8L-Eth-AR controller.
      expect(
          audioReactiveEnabledFromCfg({
            'um': {
              'AudioReactive': {
                'enabled': true,
                'digitalmic': {
                  'type': 1,
                  'pin': [32, 15, 14, -1],
                },
              },
            },
          }),
          true);
    });
    test('non-AR firmware / missing block / null cfg → null', () {
      expect(audioReactiveEnabledFromCfg(null), isNull);
      expect(audioReactiveEnabledFromCfg({}), isNull);
      expect(audioReactiveEnabledFromCfg({'um': {}}), isNull);
      expect(audioReactiveEnabledFromCfg({'um': <String, dynamic>{'AudioReactive': {}}}),
          isNull);
    });
    test('malformed values → null, never throws', () {
      expect(audioReactiveEnabledFromCfg({'um': 'nope'}), isNull);
      expect(
          audioReactiveEnabledFromCfg({
            'um': {'AudioReactive': 'nope'},
          }),
          isNull);
      expect(
          audioReactiveEnabledFromCfg({
            'um': {
              'AudioReactive': {'enabled': 1},
            },
          }),
          isNull);
    });
  });

  group('audioreactive heal (LAN)', () {
    test('already disabled → ZERO POSTs', () async {
      final repo = _FakeHealRepo(_healthy(), audioReactiveEnabled: false);
      final report = await _healer(repo, isLan: true).run();

      expect(repo.configPosts, isEmpty);
      expect(report.audioReactiveHealed, false);
      expect(report.anyHealed, false);
      expect(repo.audioReactiveReads, 1, reason: 'evaluated once, not written');
    });

    test('firmware without the usermod (null) → ZERO POSTs', () async {
      final repo = _FakeHealRepo(_healthy()); // audioReactiveEnabled null
      final report = await _healer(repo, isLan: true).run();

      expect(repo.configPosts, isEmpty);
      expect(report.audioReactiveHealed, false);
    });

    test('ENABLED → exactly one surgical POST + readback verify, NO reboot',
        () async {
      final repo = _FakeHealRepo(_healthy(), audioReactiveEnabled: true);
      final report = await _healer(repo, isLan: true).run();

      expect(repo.configPosts, hasLength(1));
      expect(
        repo.configPosts.single,
        {
          'um': {
            'AudioReactive': {'enabled': false},
          },
        },
        reason: 'enabled-only: mic type/pins must never be sent — changing '
            'those is the ONLY thing that would demand a reboot',
      );
      expect(report.audioReactiveHealed, true);
      expect(repo.audioReactiveReads, 2, reason: 'evaluate + readback verify');

      // The whole point: disabling takes effect on the controller's next
      // loop(), so this heal must never trigger a reboot.
      expect(report.rebooted, false);
      expect(report.rebootDeferred, false);
      expect(repo.jsonPosts, isEmpty);
      expect(report.log, isEmpty);
    });

    test('POST rejected → not marked healed, no readback, no reboot', () async {
      final repo = _FakeHealRepo(_healthy(),
          audioReactiveEnabled: true, applyConfigResult: false);
      final report = await _healer(repo, isLan: true).run();

      expect(repo.configPosts, hasLength(1), reason: 'attempted');
      expect(report.audioReactiveHealed, false);
      expect(repo.audioReactiveReads, 1, reason: 'no readback after a failure');
      expect(report.rebooted, false);
      expect(repo.jsonPosts, isEmpty);
      expect(report.log.any((l) => l.contains('audioreactive POST returned false')),
          true);
    });

    test('cfg read failure is inert — no POST, run completes', () async {
      final repo = _FakeHealRepo(_healthy(), audioReactiveReadThrows: true);
      final report = await _healer(repo, isLan: true).run();

      expect(repo.configPosts, isEmpty);
      expect(report.audioReactiveHealed, false);
      expect(report.anyHealed, false);
      expect(report.log.any((l) => l.contains('audioreactive read failed')), true);
    });

    test('write that silently did not take → readback logs it, still no reboot',
        () async {
      final repo = _FakeHealRepo(_healthy(),
          audioReactiveEnabled: true, audioReactiveWriteSticks: false);
      final report = await _healer(repo, isLan: true).run();

      expect(report.audioReactiveHealed, true, reason: 'the POST was accepted');
      expect(
          report.log
              .any((l) => l.contains('readback: audioreactive still enabled')),
          true);
      expect(report.rebooted, false);
    });

    test('alongside an NTP heal → separate surgical POSTs; reboot is NTP-only',
        () async {
      final repo = _FakeHealRepo(_clockUnset(),
          stateResponse: {'on': false}, audioReactiveEnabled: true);
      final report = await _healer(repo, isLan: true).run();

      // Never one combined blob.
      expect(repo.configPosts, hasLength(2));
      expect(repo.configPosts[0], {
        'if': {
          'ntp': {'host': kHealNtpHost, 'en': true},
        },
      });
      expect(repo.configPosts[1], {
        'um': {
          'AudioReactive': {'enabled': false},
        },
      });
      expect(report.ntpHostHealed, true);
      expect(report.audioReactiveHealed, true);
      // The reboot is driven by the NTP host change alone — audioreactive
      // contributes nothing to that decision.
      expect(report.rebooted, true);
      expect(repo.jsonPosts, [
        {'rb': true}
      ]);
      expect(report.toString(), 'ntp-host+audioreactive+reboot');
    });
  });

  group('heal-only-broken matrix (LAN)', () {
    test('healthy controller → ZERO cfg POSTs, no reboot', () async {
      final repo = _FakeHealRepo(_healthy());
      final gamma = _GammaSpy(); // returns skipped/noChange
      final report =
          await _healer(repo, isLan: true, gamma: gamma.action).run();

      expect(repo.configPosts, isEmpty);
      expect(repo.jsonPosts, isEmpty);
      expect(report.anyHealed, false);
      // Gamma is always readback-evaluated on LAN, but skips (no write) here.
      expect(gamma.calls, ['192.168.1.250']);
    });

    test('CLOCK_UNSET (lights off) → ntp-host POST + reboot', () async {
      final repo = _FakeHealRepo(_clockUnset(), stateResponse: {'on': false});
      final report = await _healer(repo, isLan: true).run();

      expect(repo.configPosts, hasLength(1));
      expect(repo.configPosts.single, {
        'if': {
          'ntp': {'host': kHealNtpHost, 'en': true},
        },
      });
      expect(report.ntpHostHealed, true);
      expect(report.rebooted, true);
      expect(repo.jsonPosts, [
        {'rb': true}
      ]);
    });

    test('LOCATION_UNSET → exactly the coords POST, NO reboot', () async {
      final repo = _FakeHealRepo(_locationUnset());
      final ctx = _ctx(profileLat: 41.878, profileLon: -87.6298);
      final report = await _healer(repo, isLan: true, ctx: ctx).run();

      expect(repo.configPosts, hasLength(1));
      expect(repo.configPosts.single, {
        'if': {
          'ntp': {'lt': 41.88, 'ln': -87.63},
        },
      });
      expect(report.coordsHealed, true);
      expect(report.rebooted, false);
      expect(repo.jsonPosts, isEmpty);
    });

    test('LOCATION_UNSET with no source → SKIP (zero POSTs)', () async {
      final repo = _FakeHealRepo(_locationUnset());
      final ctx = _ctx(); // no profile coords, phone resolver returns null
      final report = await _healer(repo, isLan: true, ctx: ctx).run();

      expect(repo.configPosts, isEmpty);
      expect(report.coordsHealed, false);
    });

    test('TZ_SUSPECT (mapped) → exactly the tz-index POST, NO reboot',
        () async {
      final repo = _FakeHealRepo(_tzSuspect());
      final ctx = _ctx(iana: 'America/Chicago');
      final report = await _healer(repo, isLan: true, ctx: ctx).run();

      expect(repo.configPosts, hasLength(1));
      expect(repo.configPosts.single, {
        'if': {
          'ntp': {'tz': 5},
        },
      });
      expect(report.tzHealed, true);
      expect(report.rebooted, false);
    });

    test('TZ_SUSPECT (unmapped zone) → offset fallback POST', () async {
      final repo = _FakeHealRepo(_tzSuspect());
      final ctx = _ctx(iana: 'Europe/Paris', phoneOffset: const Duration(hours: 1));
      // Europe/Paris phone offset makes the device (UTC) still suspect vs phone.
      await _healer(repo, isLan: true, ctx: ctx).run();

      expect(repo.configPosts.single, {
        'if': {
          'ntp': {'tz': kWledTzUtc, 'offset': 3600},
        },
      });
    });
  });

  group('reboot gating', () {
    test('reboot ONLY on a clock (ntp host) change — gamma drift never reboots',
        () async {
      final repo = _FakeHealRepo(_healthy());
      final gamma =
          _GammaSpy(result: const WledConfigPushResult(success: true)); // wrote
      final report =
          await _healer(repo, isLan: true, gamma: gamma.action).run();

      expect(report.gammaHealed, true);
      expect(report.rebooted, false);
      expect(repo.jsonPosts, isEmpty);
    });
  });

  group('reboot-deferral predicate — shouldRebootAfterHostHeal', () {
    test('lights off → reboot now', () {
      expect(shouldRebootAfterHostHeal(deviceOn: false), true);
      expect(
          shouldRebootAfterHostHeal(
              deviceOn: false, activePresetId: 3, bootPresetId: 5),
          true);
    });
    test('on + active look IS the boot preset → reboot now', () {
      expect(
          shouldRebootAfterHostHeal(
              deviceOn: true, activePresetId: 5, bootPresetId: 5),
          true);
    });
    test('on + active look differs from boot preset → DEFER', () {
      expect(
          shouldRebootAfterHostHeal(
              deviceOn: true, activePresetId: 3, bootPresetId: 5),
          false);
    });
    test('on + manual look (ps -1) → DEFER', () {
      expect(
          shouldRebootAfterHostHeal(
              deviceOn: true,
              activePresetId: kWledNoActivePreset,
              bootPresetId: 5),
          false);
    });
    test('on + no boot preset configured (0 or null) → DEFER', () {
      expect(
          shouldRebootAfterHostHeal(
              deviceOn: true,
              activePresetId: kWledNoBootPreset,
              bootPresetId: kWledNoBootPreset),
          false);
      expect(
          shouldRebootAfterHostHeal(
              deviceOn: true, activePresetId: 2, bootPresetId: null),
          false);
    });
  });

  group('reboot-deferral orchestration', () {
    test('CLOCK_UNSET + lights on a non-boot look → heal persists, reboot DEFERRED',
        () async {
      // Fake isn't a WledService → bootPresetId resolves null → on-state defers.
      final repo = _FakeHealRepo(_clockUnset(),
          stateResponse: {'on': true, 'ps': 7});
      final report = await _healer(repo, isLan: true).run();

      // The host/en write still happened (persists in cfg for next boot)…
      expect(report.ntpHostHealed, true);
      expect(repo.configPosts.single, {
        'if': {
          'ntp': {'host': kHealNtpHost, 'en': true},
        },
      });
      // …but no reboot was sent.
      expect(report.rebooted, false);
      expect(report.rebootDeferred, true);
      expect(repo.jsonPosts, isEmpty);
      expect(report.log.any((l) => l.contains('deferred')), true);
    });

    test('CLOCK_UNSET + device state unreadable → defer (never blind-reboot)',
        () async {
      final repo = _FakeHealRepo(_clockUnset()); // stateResponse null
      final report = await _healer(repo, isLan: true).run();
      expect(report.ntpHostHealed, true);
      expect(report.rebooted, false);
      expect(report.rebootDeferred, true);
    });
  });

  group('relay gating', () {
    test('relay + CLOCK_UNSET (off) → ntp-host POST + reboot, gamma NOT evaluated',
        () async {
      final repo = _FakeHealRepo(_clockUnset(), stateResponse: {'on': false});
      final gamma = _GammaSpy();
      final report =
          await _healer(repo, isLan: false, gamma: gamma.action).run();

      expect(repo.configPosts, hasLength(1));
      expect(report.ntpHostHealed, true);
      expect(report.rebooted, true);
      expect(gamma.calls, isEmpty, reason: 'gamma is LAN-only');
    });

    test('relay + AudioReactive ON → never read, never POSTed', () async {
      // The bridge exposes only getState/getInfo — it cannot GET /json/cfg, so
      // the usermod flag is not evaluable off-LAN. Same gating as tz/coords.
      final repo = _FakeHealRepo(
        ControllerClockInfo(deviceTime: _now), // clock fine → no host heal
        audioReactiveEnabled: true,
      );
      final report = await _healer(repo, isLan: false).run();

      expect(repo.audioReactiveReads, 0, reason: 'cfg is unreadable over relay');
      expect(repo.configPosts, isEmpty);
      expect(report.audioReactiveHealed, false);
    });

    test('relay + healthy clock → ZERO POSTs (tz/coords/gamma not evaluable)',
        () async {
      // Device has a known-bad host, but relay cannot read it → no host heal
      // unless the clock itself is unset. Clock is good here → nothing.
      final repo = _FakeHealRepo(ControllerClockInfo(
        deviceTime: _now,
        // relay: tz/lat/lon/host all unknown (cfg unreadable)
      ));
      final report = await _healer(repo, isLan: false).run();

      expect(repo.configPosts, isEmpty);
      expect(repo.jsonPosts, isEmpty);
      expect(report.anyHealed, false);
    });
  });

  group('gamma cases (folded in)', () {
    test('gamma already correct (noChange) → not counted as a heal', () async {
      final repo = _FakeHealRepo(_healthy());
      final gamma =
          _GammaSpy(result: WledConfigPushResult.skipped('already correct'));
      final report =
          await _healer(repo, isLan: true, gamma: gamma.action).run();
      expect(report.gammaHealed, false);
    });

    test('gamma drift corrected → counted as a heal', () async {
      final repo = _FakeHealRepo(_healthy());
      final gamma =
          _GammaSpy(result: const WledConfigPushResult(success: true));
      final report =
          await _healer(repo, isLan: true, gamma: gamma.action).run();
      expect(report.gammaHealed, true);
    });

    test('gamma throwing is inert — run completes, other state intact',
        () async {
      final repo = _FakeHealRepo(_healthy());
      final gamma = _GammaSpy()..throws = true;
      final report =
          await _healer(repo, isLan: true, gamma: gamma.action).run();
      expect(report.gammaHealed, false);
      expect(report.anyHealed, false);
      expect(report.log.any((l) => l.contains('gamma')), true);
    });
  });

  group('inertness', () {
    test('unreachable device (null clock info) → no POSTs, reachable=false',
        () async {
      final repo = _FakeHealRepo(null);
      final report = await _healer(repo, isLan: true).run();
      expect(report.reachable, false);
      expect(repo.configPosts, isEmpty);
      expect(report.anyHealed, false);
    });

    test('failed applyConfig → not marked healed, no reboot', () async {
      final repo = _FakeHealRepo(_clockUnset(), applyConfigResult: false);
      final report = await _healer(repo, isLan: true).run();
      expect(report.ntpHostHealed, false);
      expect(report.rebooted, false); // no clock field actually changed
      expect(repo.jsonPosts, isEmpty);
    });
  });

  group('connect predicate — shouldHealOnConnect', () {
    final lanA = WledService('http://192.168.1.250');
    final lanA2 = WledService('http://192.168.1.250');
    final lanB = WledService('http://192.168.1.99');
    final relayA = CloudRelayRepository(
      userId: 'u1',
      controllerId: 'c1',
      controllerIp: '10.0.0.5',
      webhookUrl: '',
      firestore: FakeFirebaseFirestore(),
    );
    final relayA2 = CloudRelayRepository(
      userId: 'u1',
      controllerId: 'c1',
      controllerIp: '10.0.0.5',
      webhookUrl: '',
      firestore: FakeFirebaseFirestore(),
    );
    final relayB = CloudRelayRepository(
      userId: 'u1',
      controllerId: 'c2',
      controllerIp: '10.0.0.6',
      webhookUrl: '',
      firestore: FakeFirebaseFirestore(),
    );

    test('null → LAN fires; same LAN endpoint does not', () {
      expect(shouldHealOnConnect(null, lanA), true);
      expect(shouldHealOnConnect(lanA, lanA2), false);
      expect(shouldHealOnConnect(lanA, lanB), true);
    });

    test('relay connects fire; same relay endpoint does not', () {
      expect(shouldHealOnConnect(null, relayA), true);
      expect(shouldHealOnConnect(relayA, relayA2), false);
      expect(shouldHealOnConnect(relayA, relayB), true);
    });

    test('cross local↔relay transitions fire; disconnect does not', () {
      expect(shouldHealOnConnect(lanA, relayA), true);
      expect(shouldHealOnConnect(relayA, lanA), true);
      expect(shouldHealOnConnect(lanA, null), false);
    });
  });
}
