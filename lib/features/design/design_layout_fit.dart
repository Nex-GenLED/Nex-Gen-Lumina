// lib/features/design/design_layout_fit.dart
//
// Roofline slice 1, item 2 — does a stamped design FIT the buses the app is
// looking at right now?
//
// A positional design paints channel-local LED indices per bus id. Painted
// for three buses of 100 and sent to a controller whose second bus is now
// 120 LEDs, the picture lands 20 LEDs short on that bus and the colours of
// every run after the first change position; sent to a two-bus controller,
// bus 2's picture is silently dropped; sent to a different controller, it
// is somebody else's roofline. Until now no apply path compared the stored
// lengths with the live buses (ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03 §C,
// gate G2); `DesignApplyResult.staleApplied` was declared and never returned.
//
// The verdict is PURE and reads only: the design's stamp (item 1), the live
// channel list (device truth from the LAN cfg read; empty off the LAN, while
// loading, or when unreadable), the selected controller id, and whether the
// app is in remote mode. The apply spine (design_apply.dart) asks it before
// any write; an unstamped design is never gated (owner decision: legacy
// designs keep today's behaviour until re-saved).

import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';

enum LayoutFitVerdict {
  /// Stamp matches the live buses (and the controller, when both are known).
  fits,

  /// No stamp on the design: not gated, applied as before.
  unstamped,

  /// Away from home. The relay has no cfg door, so there is no bus data to
  /// check a stamped design against; it can only be applied on the LAN.
  offLan,

  /// On the LAN, but the bus list is empty (cfg still loading, or unread).
  layoutUnknown,

  /// Stamped for a different controller record than the one selected.
  differentController,

  /// The live controller has a different number of buses.
  busCountDiffers,

  /// Same bus count, but at least one bus has a different LED count.
  busLengthDiffers,
}

/// The fit verdict with the sentence to show when the design is refused.
class LayoutFit {
  const LayoutFit._(this.verdict, {this.message, this.detail = ''});

  final LayoutFitVerdict verdict;

  /// Customer-readable; null when the design may be applied. Names the
  /// design, says what does not match, and how to fix it.
  final String? message;

  /// Operator-readable detail for logs. No customer identifiers.
  final String detail;

  /// True when the apply may go ahead.
  bool get applies =>
      verdict == LayoutFitVerdict.fits || verdict == LayoutFitVerdict.unstamped;

  @override
  String toString() => 'LayoutFit(${verdict.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// The repair every mismatch message ends with (owner wording).
const String kLayoutFitRepairHint =
    'Run the layout capture again, or open this design and save it again.';

String _offLanMessage(String name) =>
    '"$name" was saved for your lights\' exact layout, so it can only be '
    'applied on your home network. Connect to your home Wi-Fi and try again.';

String _layoutUnknownMessage(String name) =>
    'Couldn\'t read your controller\'s layout, so "$name" wasn\'t applied. '
    'Try again in a moment.';

String _differentControllerMessage(String name) =>
    '"$name" was saved for a different controller than the one you\'re '
    'connected to, so it wasn\'t applied. $kLayoutFitRepairHint';

String _busCountMessage(String name, int saved, int live) =>
    '"$name" was saved for $saved ${saved == 1 ? 'channel' : 'channels'}, but '
    'your controller has $live now, so it wasn\'t applied. $kLayoutFitRepairHint';

String _busLengthMessage(String name, int channel, int saved, int live) =>
    '"$name" was saved with $saved lights on channel ${channel + 1}, but that '
    'channel has $live now, so it wasn\'t applied. $kLayoutFitRepairHint';

/// Pure verdict. See the file comment for what each input is.
///
/// [liveChannels] — `deviceChannelsProvider`: empty means NO bus data.
/// [liveControllerId] — `selectedControllerIdProvider`; null when the app
/// has no selected record, in which case the lengths alone decide (a
/// missing id is the absence of an expectation, not a mismatch — #94's rule).
/// [remote] — `isRemoteModeProvider`: decides which sentence an empty bus
/// list gets. It is consulted ONLY when the design is stamped and the bus
/// list is empty, so callers may pass a lazy reader.
LayoutFit layoutFitOf({
  required String designName,
  required DesignLayoutStamp? stamp,
  required List<DeviceChannel> liveChannels,
  String? liveControllerId,
  required bool Function() remote,
}) {
  if (stamp == null) {
    return const LayoutFit._(LayoutFitVerdict.unstamped);
  }
  final live = DesignLayoutStamp.fromChannels(liveChannels,
      controllerId: liveControllerId);
  if (live == null) {
    return remote()
        ? LayoutFit._(LayoutFitVerdict.offLan,
            message: _offLanMessage(designName), detail: 'no bus data (remote)')
        : LayoutFit._(LayoutFitVerdict.layoutUnknown,
            message: _layoutUnknownMessage(designName),
            detail: 'no bus data (LAN; cfg loading or unread)');
  }
  final savedId = stamp.controllerId;
  final liveId = live.controllerId;
  if (savedId != null && liveId != null && savedId != liveId) {
    return LayoutFit._(LayoutFitVerdict.differentController,
        message: _differentControllerMessage(designName),
        detail: 'stamped for another controller record');
  }
  if (stamp.busCount != live.busCount) {
    return LayoutFit._(LayoutFitVerdict.busCountDiffers,
        message: _busCountMessage(designName, stamp.busCount, live.busCount),
        detail: 'buses ${stamp.busLengths} vs live ${live.busLengths}');
  }
  for (var i = 0; i < stamp.busCount; i++) {
    if (stamp.busLengths[i] != live.busLengths[i]) {
      return LayoutFit._(LayoutFitVerdict.busLengthDiffers,
          message: _busLengthMessage(
              designName, i, stamp.busLengths[i], live.busLengths[i]),
          detail: 'bus $i: ${stamp.busLengths[i]} vs live ${live.busLengths[i]} '
              '(${stamp.busLengths} vs ${live.busLengths})');
    }
  }
  return const LayoutFit._(LayoutFitVerdict.fits);
}
