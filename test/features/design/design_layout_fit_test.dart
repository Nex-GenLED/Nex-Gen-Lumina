// Roofline slice 1, item 2 — the pure fit verdict (design_layout_fit.dart).
//
// Verdict table over one fixture: a design stamped for controller `ctl-a`
// with three buses of 100 (ids 0, 1, 2), against the live layouts: equal;
// bus count differs; one bus length differs; a bus re-provisioned on another
// controller (same lengths, `ctl-b`); off the LAN (no bus data, remote); on
// the LAN with no bus data yet. Plus: an unstamped design is never gated, and
// a missing controller id on either side is not a mismatch.
//
// The apply-spine wiring is design_layout_fit_apply_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_fit.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';

const kStamp = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);

const kThreeBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
];
const kTwoBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];
const kFourBuses = [
  ...kThreeBuses,
  DeviceChannel(id: 3, name: 'Channel 4', start: 300, stop: 350, gpioPin: 13),
];
const kMiddleBusLonger = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 220, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 220, stop: 320, gpioPin: 12),
];
const kLastBusShorter = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 299, gpioPin: 12),
];

LayoutFit fit({
  DesignLayoutStamp? stamp = kStamp,
  required List<DeviceChannel> live,
  String? controllerId = 'ctl-a',
  bool remote = false,
  bool Function()? remoteReader,
}) =>
    layoutFitOf(
      designName: 'Porch stripes',
      stamp: stamp,
      liveChannels: live,
      liveControllerId: controllerId,
      remote: remoteReader ?? () => remote,
    );

void main() {
  group('applies', () {
    test('equal: three buses of 100 on ctl-a → fits, no message', () {
      final f = fit(live: kThreeBuses);
      expect(f.verdict, LayoutFitVerdict.fits);
      expect(f.applies, isTrue);
      expect(f.message, isNull);
    });

    test('unstamped → never gated, whatever the live layout is', () {
      for (final live in [kThreeBuses, kTwoBuses, kMiddleBusLonger, const <DeviceChannel>[]]) {
        final f = fit(stamp: null, live: live, controllerId: 'ctl-b', remote: true);
        expect(f.verdict, LayoutFitVerdict.unstamped, reason: '$live');
        expect(f.applies, isTrue);
        expect(f.message, isNull);
      }
    });

    test('the remote flag is NOT read for an unstamped design or when buses are known', () {
      var reads = 0;
      bool counting() {
        reads++;
        return true;
      }

      fit(stamp: null, live: const [], remoteReader: counting);
      fit(live: kThreeBuses, remoteReader: counting);
      fit(live: kTwoBuses, remoteReader: counting);
      expect(reads, 0);
    });

    test('no selected controller record on the live side → lengths decide', () {
      expect(fit(live: kThreeBuses, controllerId: null).verdict, LayoutFitVerdict.fits);
      expect(fit(live: kTwoBuses, controllerId: null).verdict,
          LayoutFitVerdict.busCountDiffers);
    });

    test('no controller id in the stamp → lengths decide', () {
      const noId = DesignLayoutStamp(busLengths: [100, 100, 100]);
      expect(fit(stamp: noId, live: kThreeBuses, controllerId: 'ctl-b').verdict,
          LayoutFitVerdict.fits);
      expect(fit(stamp: noId, live: kMiddleBusLonger, controllerId: 'ctl-b').verdict,
          LayoutFitVerdict.busLengthDiffers);
    });
  });

  group('refused', () {
    test('bus count differs (two live buses): says 3 → 2 and the repair', () {
      final f = fit(live: kTwoBuses);
      expect(f.verdict, LayoutFitVerdict.busCountDiffers);
      expect(f.applies, isFalse);
      expect(f.message, contains('"Porch stripes"'));
      expect(f.message, contains('saved for 3 channels'));
      expect(f.message, contains('has 2 now'));
      expect(f.message, contains(kLayoutFitRepairHint));
    });

    test('bus count differs (four live buses)', () {
      final f = fit(live: kFourBuses);
      expect(f.verdict, LayoutFitVerdict.busCountDiffers);
      expect(f.message, contains('has 4 now'));
    });

    test('one bus length differs: names the channel (1-based) and both counts', () {
      final f = fit(live: kMiddleBusLonger);
      expect(f.verdict, LayoutFitVerdict.busLengthDiffers);
      expect(f.message, contains('100 lights on channel 2'));
      expect(f.message, contains('has 120 now'));
      expect(f.message, contains(kLayoutFitRepairHint));
      final g = fit(live: kLastBusShorter);
      expect(g.verdict, LayoutFitVerdict.busLengthDiffers);
      expect(g.message, contains('channel 3'));
      expect(g.message, contains('has 99 now'));
    });

    test('a bus re-provisioned on another controller: same lengths, ctl-b', () {
      final f = fit(live: kThreeBuses, controllerId: 'ctl-b');
      expect(f.verdict, LayoutFitVerdict.differentController);
      expect(f.applies, isFalse);
      expect(f.message, contains('different controller'));
      expect(f.message, contains(kLayoutFitRepairHint));
    });

    test('the controller check comes before the bus checks', () {
      final f = fit(live: kTwoBuses, controllerId: 'ctl-b');
      expect(f.verdict, LayoutFitVerdict.differentController);
    });

    test('off the LAN: no bus data + remote → home-network sentence', () {
      final f = fit(live: const [], remote: true);
      expect(f.verdict, LayoutFitVerdict.offLan);
      expect(f.applies, isFalse);
      expect(f.message, contains('only be applied on your home network'));
      expect(f.message, contains('home Wi-Fi'));
      expect(f.message, isNot(contains(kLayoutFitRepairHint)),
          reason: 'nothing to fix: the design may well fit; the app cannot tell from here');
    });

    test('on the LAN with no bus data yet → try-again sentence, no repair hint', () {
      final f = fit(live: const [], remote: false);
      expect(f.verdict, LayoutFitVerdict.layoutUnknown);
      expect(f.applies, isFalse);
      expect(f.message, contains("Couldn't read your controller's layout"));
      expect(f.message, contains('Try again'));
    });

    test('no message names an id, an address or a status code', () {
      for (final f in [
        fit(live: kTwoBuses),
        fit(live: kMiddleBusLonger),
        fit(live: kThreeBuses, controllerId: 'ctl-b'),
        fit(live: const [], remote: true),
        fit(live: const [], remote: false),
      ]) {
        expect(f.message, isNot(contains('ctl-')), reason: f.toString());
        expect(f.message, isNot(contains('192.')), reason: f.toString());
        expect(f.message, isNot(matches(RegExp(r'\b[45]\d\d\b'))), reason: f.toString());
      }
    });
  });
}
