// Roofline slice 1, G5 — refreshLiveLayout: the cached cfg read is
// invalidated and the fresh one awaited, so deviceChannelsProvider carries
// the controller's current bus lengths. The screen-level fail-before proof
// is hardware_config_count_save_layout_test.dart; this file pins the helper.
//
// Fixture: one controller, three buses of 100 (ids 0, 1, 2), then the same
// three with bus 2 at 120.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/live_layout_refresh.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

import '../../helpers/recording_wled_repository.dart';

const _threeOf100 = WledHardwareConfig(totalLeds: 300, buses: [
  WledLedBus(pin: [2], start: 0, len: 100),
  WledLedBus(pin: [14], start: 100, len: 100),
  WledLedBus(pin: [16], start: 200, len: 100),
]);
const _bus2At120 = WledHardwareConfig(totalLeds: 320, buses: [
  WledLedBus(pin: [2], start: 0, len: 100),
  WledLedBus(pin: [14], start: 100, len: 120),
  WledLedBus(pin: [16], start: 220, len: 100),
]);

class _Controller extends RecordingWledRepository {
  _Controller(this.hw);
  WledHardwareConfig? hw;
  int configReads = 0;

  /// When set, the cfg read never answers (a controller busy re-initialising).
  Completer<WledHardwareConfig?>? hang;

  @override
  Future<WledHardwareConfig?> getConfig() async {
    configReads++;
    final h = hang;
    if (h != null) return h.future;
    return hw;
  }
}

List<int> _lengths(ProviderContainer c) =>
    [for (final ch in c.read(deviceChannelsProvider)) ch.stop - ch.start];

void main() {
  late _Controller controller;
  late ProviderContainer container;

  setUp(() {
    controller = _Controller(_threeOf100);
    container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => controller),
    ]);
    addTearDown(container.dispose);
  });

  test('after the controller changes bus 2 to 120, the refresh returns and '
      'publishes 100 / 120 / 100 — the cached read alone kept 100 / 100 / 100',
      () async {
    await container.read(deviceHardwareConfigProvider.future);
    expect(_lengths(container), [100, 100, 100]);
    controller.hw = _bus2At120;
    expect(_lengths(container), [100, 100, 100], reason: 'cached since connect');

    final live = await refreshLiveLayout(
        invalidate: container.invalidate, read: container.read);

    expect([for (final c in live) c.stop - c.start], [100, 120, 100]);
    expect(_lengths(container), [100, 120, 100]);
    expect(controller.configReads, 2);
  });

  test('a cfg read that does not answer within the bound → empty, and the save '
      'is not held up', () async {
    await container.read(deviceHardwareConfigProvider.future);
    controller.hang = Completer<WledHardwareConfig?>();
    final live = await refreshLiveLayout(
      invalidate: container.invalidate,
      read: container.read,
      timeout: const Duration(milliseconds: 20),
    );
    expect(live, isEmpty);
    controller.hang!.complete(_bus2At120);
  });

  test('a cfg read that fails → empty (the provider answers null, as it does '
      'for any read failure)', () async {
    await container.read(deviceHardwareConfigProvider.future);
    controller.hw = null;
    final live = await refreshLiveLayout(
        invalidate: container.invalidate, read: container.read);
    expect(live, isEmpty);
    expect(_lengths(container), isEmpty);
  });
}
