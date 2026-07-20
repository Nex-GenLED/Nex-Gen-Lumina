import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

// GammaWatchdog: a low-frequency, READBACK-GATED re-assert of cfg.light.gc.
// Guardrail under test — the healthy path must cost ZERO cfg writes (every
// tick is a readback that skips), a genuine mid-session revert must cost
// EXACTLY ONE corrective write, and the cadence must never dip below 60s.
//
// The action seam ([GammaSelfHealAction]) stands in for pushGammaConfig:
//   • skipped()  == readback said gamma is already correct → no write
//   • warning()/plain success == a real cfg write happened
void main() {
  group('GammaWatchdog — readback-gated, anti-thrash', () {
    test('healthy board over many ticks → ZERO corrective writes', () async {
      var calls = 0;
      final wd = GammaWatchdog(
        action: (ip) async {
          calls++;
          // Board already correct every time → readback skip, no write.
          return WledConfigPushResult.skipped('color gamma already correct');
        },
        lanIp: () => '192.168.1.250',
      );

      for (var i = 0; i < 20; i++) {
        await wd.tickOnce();
      }

      expect(calls, 20, reason: 'each tick performs the readback');
      expect(wd.correctiveWrites, 0,
          reason: 'a skip (noChange) must never count as a flash write');
      expect(wd.ticks, 20);
    });

    test('mid-session revert → EXACTLY ONE corrective write, then quiet',
        () async {
      // Model the board: correct by default; a revert flips it, and a single
      // corrective write heals it back (mirrors pushGammaConfig read→write→ok).
      var boardCorrect = true;
      var writes = 0;
      final wd = GammaWatchdog(
        action: (ip) async {
          if (boardCorrect) {
            return WledConfigPushResult.skipped('already correct');
          }
          writes++;
          boardCorrect = true; // the corrective write restores gamma
          return const WledConfigPushResult(success: true); // noChange:false
        },
        lanIp: () => '192.168.1.250',
      );

      await wd.tickOnce(); // healthy → skip
      await wd.tickOnce(); // healthy → skip
      expect(wd.correctiveWrites, 0);

      boardCorrect = false; // device-side revert happens here
      await wd.tickOnce(); // detects + corrects within one interval
      expect(writes, 1);
      expect(wd.correctiveWrites, 1, reason: 'exactly one corrective write');
      expect(boardCorrect, isTrue, reason: 'gamma restored');

      await wd.tickOnce(); // back to healthy → skip
      await wd.tickOnce();
      expect(wd.correctiveWrites, 1,
          reason: 'no further writes once the board is correct again');
    });

    test('LAN-gate: off-LAN (null ip) never invokes the action', () async {
      var calls = 0;
      final wd = GammaWatchdog(
        action: (ip) async {
          calls++;
          return const WledConfigPushResult(success: true);
        },
        lanIp: () => null, // relay / mock / offline
      );

      await wd.tickOnce();
      await wd.tickOnce();

      expect(calls, 0, reason: 'no cfg traffic when not on a LAN endpoint');
      expect(wd.ticks, 0);
      expect(wd.correctiveWrites, 0);
    });

    test('cadence floor: an interval under 60s is clamped up to 60s', () {
      final tooFast = GammaWatchdog(
        action: (ip) async => WledConfigPushResult.skipped('x'),
        lanIp: () => '192.168.1.250',
        interval: const Duration(seconds: 5),
      );
      expect(tooFast.interval, kGammaWatchdogMinInterval);

      final ok = GammaWatchdog(
        action: (ip) async => WledConfigPushResult.skipped('x'),
        lanIp: () => '192.168.1.250',
        interval: const Duration(minutes: 5),
      );
      expect(ok.interval, const Duration(minutes: 5),
          reason: 'an interval at/above the floor is honored as-is');
    });

    test('a readback failure (throw) is swallowed and counts no write',
        () async {
      final wd = GammaWatchdog(
        action: (ip) async => throw Exception('network down'),
        lanIp: () => '192.168.1.250',
      );

      await wd.tickOnce(); // must not throw
      expect(wd.correctiveWrites, 0);
      expect(wd.ticks, 1);
    });
  });
}
