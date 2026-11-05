// Roofline slice 1, G5 — after the LED-count save, the app re-reads the
// controller's bus layout, so the layout stamp (item 1) and the fit gate
// (item 2) compare against the lengths the controller now has.
//
// Before: HardwareConfigScreen._saveSegmentCounts posted the new `hw.led`
// lengths, wrote the segment bounds with a read-back, and showed a message;
// it never invalidated deviceHardwareConfigProvider (a FutureProvider cached
// since connect), so deviceChannelsProvider — what the stamp, the fit gate
// and the bus-change watcher read — kept the pre-save lengths until the
// connection dropped and came back. A design stamped for the old lengths
// passed the gate on the new hardware. This file is the fail-before proof:
// it reads the channels before the save, as the dashboard does from connect,
// saves bus 2 as 120 through the screen, and reads them again.
//
// Fixture: one controller, three buses of 100 LEDs (ids 0, 1, 2); bus 2
// changed to 120 through the screen's count field. The fake controller is
// stateful: a cfg POST changes its buses, a geometry POST re-binds its
// segments, so the read-backs show what landed. No network.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_fit.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/wled/hardware_config_screen.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

import '../../helpers/recording_wled_repository.dart';

const _threeOf100 = WledHardwareConfig(totalLeds: 300, buses: [
  WledLedBus(pin: [2], start: 0, len: 100),
  WledLedBus(pin: [14], start: 100, len: 100),
  WledLedBus(pin: [16], start: 200, len: 100),
]);

Map<String, dynamic> _seg(int id, int start, int stop) => {
      'id': id,
      'start': start,
      'stop': stop,
      'len': stop - start,
      'on': true,
      'bri': 255,
      'fx': 0,
      'col': [
        [227, 24, 55, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0]
      ],
    };

/// A LAN controller: its cfg buses change on a cfg POST; its segments
/// re-bind on a geometry POST.
class _Controller extends RecordingWledRepository {
  _Controller(this.hw)
      : segs = [
          for (final (i, b) in hw.buses.indexed) _seg(i, b.start, b.start + b.len),
        ];

  WledHardwareConfig hw;
  List<Map<String, dynamic>> segs;
  int configReads = 0;
  final geometryPosts = <Map<String, dynamic>>[];

  @override
  Future<WledHardwareConfig?> getConfig() async {
    configReads++;
    return hw;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    appliedConfigs.add(cfg);
    final led = (cfg['hw'] as Map)['led'] as Map;
    hw = WledHardwareConfig(
      totalLeds: led['total'] as int,
      maxPowerMw: led['maxpwr'] as int,
      buses: [
        for (final m in led['ins'] as List)
          WledLedBus.fromMap(Map<String, dynamic>.from(m as Map)),
      ],
    );
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': true,
        'seg': [for (final s in segs) Map<String, dynamic>.from(s)],
      };

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async {
    geometryPosts.add(payload);
    for (final e in (payload['seg'] as List).cast<Map<String, dynamic>>()) {
      final id = e['id'] as int;
      final idx = segs.indexWhere((s) => s['id'] == id);
      final merged = {...(idx >= 0 ? segs[idx] : _seg(id, 0, 0)), ...e};
      merged['len'] = (merged['stop'] as int) - (merged['start'] as int);
      if (idx >= 0) {
        segs[idx] = merged;
      } else {
        segs.add(merged);
      }
    }
    return true;
  }
}

List<int> _lengths(ProviderContainer c) =>
    [for (final ch in c.read(deviceChannelsProvider)) ch.stop - ch.start];

void main() {
  testWidgets('saving bus 2 as 120 leaves deviceChannelsProvider — and so the '
      'fit gate — reading 100 / 120 / 100, not the lengths cached at connect',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = _Controller(_threeOf100);
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => controller),
    ]);
    addTearDown(container.dispose);

    // Connect: the dashboard reads the bus layout once and keeps it.
    await container.read(deviceHardwareConfigProvider.future);
    expect(_lengths(container), [100, 100, 100]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HardwareConfigScreen()),
    ));
    await tester.pumpAndSettle(); // post-frame cfg read, then the FAB's entrance
    expect(find.text('Loaded 3 channel(s) from device'), findsOneWidget);

    // The installer corrects bus 2's count and saves (counts only: no reboot).
    await tester.enterText(find.byType(TextField).at(1), '120');
    await tester.pump();
    expect(find.text('Save Changes'), findsOneWidget, reason: 'not structural');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // The controller took the new lengths and the bounds landed.
    final ins = ((controller.appliedConfigs.single['hw'] as Map)['led'] as Map)['ins'] as List;
    expect([for (final b in ins) (b as Map)['len']], [100, 120, 100]);
    expect(controller.geometryPosts, hasLength(1));
    expect([for (final s in controller.segs) s['stop']], [100, 220, 320]);

    // G5: the app's live layout is the controller's NEW layout.
    expect(_lengths(container), [100, 120, 100],
        reason: 'the cfg read cached at connect was never invalidated');

    // …which is what the fit gate compares a stamp with: a design stamped for
    // the old lengths is refused, naming channel 2, and one re-saved for the
    // new lengths fits.
    final live = container.read(deviceChannelsProvider);
    final stale = layoutFitOf(
      designName: 'Porch stripes',
      stamp: const DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]),
      liveChannels: live,
      liveControllerId: 'ctl-a',
      remote: () => false,
    );
    expect(stale.verdict, LayoutFitVerdict.busLengthDiffers);
    expect(stale.message, contains('100 lights on channel 2'));
    expect(stale.message, contains('has 120 now'));
    final refitted = layoutFitOf(
      designName: 'Porch stripes',
      stamp: const DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 120, 100]),
      liveChannels: live,
      liveControllerId: 'ctl-a',
      remote: () => false,
    );
    expect(refitted.verdict, LayoutFitVerdict.fits);

    await tester.pump(const Duration(seconds: 5)); // the snackbar goes
  });
}
