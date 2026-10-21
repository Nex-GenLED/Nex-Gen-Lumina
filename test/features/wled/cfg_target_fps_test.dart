// test/features/wled/cfg_target_fps_test.dart
//
// EVERY CFG WRITE SET THE FRAME RATE TO UNLIMITED — source read of WLED
// v0.15.1 / v0.15.4 (2026-10-20): deserializeConfig does
// `strip.setTargetFps(hw_led["fps"])` (cfg.cpp:119); a body without the key
// yields 0 and setTargetFps accepts 0 as the unlimited mode
// (FX_fcn.cpp:1488-1491, FPS_UNLIMITED 0, MIN_FRAME_DELAY 2 ms). No cfg body
// Lumina built ever carried hw.led.fps, so every timer sync, heal, install push
// and hardware save left the render loop free-running and the web server
// starved. v16.0.1 defaults a missing key to 42 (cfg.cpp:181), so there the
// injection is harmless and merely explicit.
//
// FIX — normalizeWledCfgPayload carries hw.led.fps at the SAME write boundary
// as gamma: the device's own rate when a cfg read has seen one in 1–250,
// otherwise kDefaultTargetFps. This file pins the rule over every payload
// builder the app has, plus the WledService boundary in simulation.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart'
    show ScheduleSyncService;
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart'
    show buildSunriseOffTimerEntry;
import 'package:nexgen_command/features/wled/audioreactive_health.dart'
    show audioReactiveHealPayload;
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show
        CoordHeal,
        TzHeal,
        coordHealPayload,
        ntpHostHealPayload,
        tzHealPayload;
import 'package:nexgen_command/features/wled/wled_cfg_gamma.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart'
    show buildGammaPayload, buildLedConfig;

int? fpsOf(Map<String, dynamic> cfg) =>
    ((cfg['hw'] as Map?)?['led'] as Map?)?['fps'] as int?;

/// Every cfg body the app builds, by writer. Shapes are the real builders
/// where one exists and the literal shape where the writer builds inline
/// (hardware screen, lease merge, sunrise-off).
final Map<String, Map<String, dynamic>> kEveryCfgBody = {
  'healer ntp host': ntpHostHealPayload(),
  'healer tz index': tzHealPayload(const TzHeal.index(5)),
  'healer tz offset': tzHealPayload(const TzHeal.offset(-21600)),
  'healer coords': coordHealPayload(const CoordHeal(38.99, -94.25)),
  'healer audioreactive': audioReactiveHealPayload(),
  'gamma self-heal': buildGammaPayload(),
  'schedule sync timers': {
    'timers': {
      'ins': ScheduleSyncService.padTimersToMax([
        {'en': 1, 'hour': 19, 'min': 0, 'macro': 10, 'dow': 127},
        {'en': 1, 'hour': 7, 'min': 0, 'macro': 2, 'dow': 127},
      ]),
    },
  },
  'schedule sync solar table': {
    'timers': {
      'ins': ScheduleSyncService.assembleSolarAwareIns(const [],
          sunrise: buildSunriseOffTimerEntry()),
    },
  },
  'calendar lease merge': {
    'timers': {
      'ins': ScheduleSyncService.padTimersToMax([
        {'en': 1, 'hour': 18, 'min': 30, 'macro': 26, 'dow': 127},
      ]),
    },
  },
  'sunrise-off slot 8': {
    'timers': {
      'ins': ScheduleSyncService.assembleSolarAwareIns(const [],
          sunrise: buildSunriseOffTimerEntry()),
    },
  },
  'install hw push': {
    'hw': {
      'led': buildLedConfig(total: 490, maxpwr: 20000, ins: const []),
    },
  },
  'install mdns': {
    'id': {'mdns': 'ngl-test-0000'},
  },
  'install time/location': {
    'if': {
      'ntp': {
        'en': true,
        'host': 'time.example.invalid',
        'tz': 5,
        'offset': 0,
        'ampm': false,
        'ln': -94.25,
        'lt': 38.99,
      },
    },
  },
  'hardware screen': {
    'hw': {
      'led': {'maxpwr': 20000, 'ins': <Map<String, dynamic>>[]},
    },
  },
  'empty body': <String, dynamic>{},
};

void main() {
  group('normalizeWledCfgPayload — hw.led.fps on every body', () {
    for (final entry in kEveryCfgBody.entries) {
      test('${entry.key}: default when nothing is known', () {
        final out = normalizeWledCfgPayload(entry.value);
        expect(fpsOf(out), kDefaultTargetFps);
        expect(fpsOf(out), isA<int>());
        expect(fpsOf(out)!, inInclusiveRange(1, 250));
      });

      test('${entry.key}: the device\'s own rate is kept when usable', () {
        for (final seen in const [1, 42, 60, 120, 250]) {
          final out = normalizeWledCfgPayload(entry.value, currentFps: seen);
          expect(fpsOf(out), seen, reason: 'seen $seen');
        }
      });

      test('${entry.key}: 0 (unlimited), null and out-of-range → default', () {
        for (final seen in const <int?>[0, null, -1, 251, 1000]) {
          final out = normalizeWledCfgPayload(entry.value, currentFps: seen);
          expect(fpsOf(out), kDefaultTargetFps, reason: 'seen $seen');
        }
      });

      test('${entry.key}: the caller\'s own keys survive', () {
        final out = normalizeWledCfgPayload(entry.value, currentFps: 42);
        for (final k in entry.value.keys) {
          expect(out.containsKey(k), isTrue, reason: 'lost $k');
        }
        // Gamma still rides along (the first chokepoint is untouched).
        expect(((out['light'] as Map)['gc'] as Map)['col'], 2.8);
      });
    }

    test('a body that already names a usable hw.led.fps is authoritative', () {
      final out = normalizeWledCfgPayload({
        'hw': {
          'led': {'fps': 30, 'maxpwr': 20000},
        },
      }, currentFps: 42);
      expect(fpsOf(out), 30);
      expect(((out['hw'] as Map)['led'] as Map)['maxpwr'], 20000,
          reason: 'sibling hw.led keys untouched');
    });

    test('a body that names fps 0 is corrected like a missing key', () {
      final out = normalizeWledCfgPayload({
        'hw': {
          'led': {'fps': 0},
        },
      }, currentFps: 42);
      expect(fpsOf(out), 42);
    });

    test('the install hw body keeps its bus list and gains only fps', () {
      final out = normalizeWledCfgPayload(kEveryCfgBody['install hw push']!,
          currentFps: 0);
      final led = (out['hw'] as Map)['led'] as Map;
      expect(led.keys.toSet(), {'total', 'maxpwr', 'ins', 'fps'});
      expect(led['fps'], kDefaultTargetFps);
    });

    test('the input map is not mutated', () {
      final body = <String, dynamic>{
        'timers': {'ins': <Map<String, dynamic>>[]},
      };
      normalizeWledCfgPayload(body);
      expect(body.containsKey('hw'), isFalse);
      expect(body.containsKey('light'), isFalse);
    });
  });

  group('helpers', () {
    test('kDefaultTargetFps is 42, WLED\'s own default (owner decision), '
        'and in range', () {
      expect(kDefaultTargetFps, 42);
      expect(isUsableTargetFps(kDefaultTargetFps), isTrue);
    });

    test('a cached 0 maps to 42 everywhere the constant is used', () {
      // The normaliser, the healer's single write and the AudioReactive heal
      // body all resolve through resolveTargetFps; pin the mapping once.
      expect(resolveTargetFps(0), 42);
      final out = normalizeWledCfgPayload({
        'um': {
          'AudioReactive': {'enabled': false},
        },
      }, currentFps: 0);
      expect(fpsOf(out), 42);
    });

    test('isUsableTargetFps / resolveTargetFps', () {
      expect(isUsableTargetFps(null), isFalse);
      expect(isUsableTargetFps(0), isFalse);
      expect(isUsableTargetFps(1), isTrue);
      expect(isUsableTargetFps(250), isTrue);
      expect(isUsableTargetFps(251), isFalse);
      expect(resolveTargetFps(42), 42);
      expect(resolveTargetFps(0), kDefaultTargetFps);
      expect(resolveTargetFps(null), kDefaultTargetFps);
    });

    test('targetFpsFromCfg reads cfg.hw.led.fps, 0 as 0, absent as null', () {
      expect(
          targetFpsFromCfg({
            'hw': {
              'led': {'fps': 42},
            },
          }),
          42);
      expect(
          targetFpsFromCfg({
            'hw': {
              'led': {'fps': 0},
            },
          }),
          0);
      expect(targetFpsFromCfg({'hw': {}}), isNull);
      expect(targetFpsFromCfg(null), isNull);
    });
  });

  group('WledService boundary (simulation = the real _postConfig path)', () {
    test('no cfg read yet → the default goes out', () async {
      final service = WledService('http://mock');
      expect(await service.applyConfig({
        'timers': {'ins': <Map<String, dynamic>>[]},
      }), isTrue);
      expect(fpsOf(service.lastSimulatedConfigPayload!), kDefaultTargetFps);
      expect(((service.lastSimulatedConfigPayload!['light'] as Map)['gc']
              as Map)['col'],
          2.8);
    });

    test('a cached device rate is kept on every later write', () async {
      final service = WledService('http://mock');
      service.seedTargetFpsForTest(42);
      await service.applyConfig({
        'if': {
          'ntp': {'tz': 5},
        },
      });
      expect(fpsOf(service.lastSimulatedConfigPayload!), 42);
      await service.applyConfig({
        'um': {
          'AudioReactive': {'enabled': false},
        },
      });
      expect(fpsOf(service.lastSimulatedConfigPayload!), 42);
    });

    test('a cached 0 (the unlimited mode) is replaced by the default', () async {
      final service = WledService('http://mock');
      service.seedTargetFpsForTest(0);
      await service.applyConfig({
        'timers': {'ins': <Map<String, dynamic>>[]},
      });
      expect(fpsOf(service.lastSimulatedConfigPayload!), kDefaultTargetFps);
    });
  });
}
