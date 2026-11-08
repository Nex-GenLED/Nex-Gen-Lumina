// lib/features/wled/live_layout_refresh.dart
//
// Roofline slice 1, G5 — after the app's own LED-count save, re-read the
// controller's bus layout so every reader of `deviceChannelsProvider` sees
// the lengths the controller now has.
//
// `deviceHardwareConfigProvider` is a plain FutureProvider: it reads
// `/json/cfg` once per repository and keeps the answer. The LED-count save
// (HardwareConfigScreen._saveSegmentCounts) changes `hw.led` on the
// controller without a reboot, so nothing invalidated that read, and the
// design layout stamp (item 1), the apply-time fit gate (item 2), the
// pixel-map staleness check and the bus-change watcher (G4) all kept
// comparing against the lengths cached at connect until the connection
// dropped and came back (ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03 §C, gate
// G5). A design stamped for the old lengths passed the gate on the new
// hardware; a design saved after the count change was stamped with the old
// lengths.
//
// No Firestore write: the gate reads device truth only, and a stamped design
// is refused off the LAN by owner decision (D6), so nothing off the LAN
// consumes the lengths.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// How long the save waits for the fresh cfg read before returning; the
/// provider keeps resolving on its own after that.
const Duration kLiveLayoutRefreshTimeout = Duration(seconds: 3);

/// Invalidates the cached cfg read and waits, bounded, for the fresh one.
/// Returns the channels the app now sees — empty when the re-read failed or
/// timed out. [invalidate] and [read] are `ref.invalidate` / `ref.read` from
/// a widget or a provider, or a container's.
Future<List<DeviceChannel>> refreshLiveLayout({
  required void Function(ProviderOrFamily provider) invalidate,
  required T Function<T>(ProviderListenable<T> provider) read,
  Duration timeout = kLiveLayoutRefreshTimeout,
}) async {
  invalidate(deviceHardwareConfigProvider);
  try {
    final cfg = await read(deviceHardwareConfigProvider.future)
        .timeout(timeout, onTimeout: () => null);
    return deviceChannelsFromConfig(cfg);
  } catch (_) {
    return const [];
  }
}
