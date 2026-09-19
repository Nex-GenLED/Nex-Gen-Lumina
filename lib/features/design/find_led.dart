import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

/// "Find LED" — light exactly ONE physical LED so an installer can walk the
/// roof and see where a number lands.
///
/// This replaces a stub that showed a green "LED N should now be lit red"
/// snackbar and sent NOTHING to the controller
/// (design-studio-followup-2026-09-19 N1a). The rule it now follows is the one
/// the whole apply spine follows: success is reported only when the device
/// accepted every write.
///
/// Pure of Riverpod/Flutter so it is unit-testable and bench-replayable.

enum FindLedOutcome {
  /// Both writes were accepted: the strip is dark except the target LED.
  lit,

  /// No controller, or it exposes no per-pixel writer.
  noController,

  /// The controller's channel layout is unknown (not connected yet).
  noChannels,

  /// [FindLedResult.requested] is outside the controller's LED range.
  outOfRange,

  /// A write was sent and the controller did not accept it.
  writeFailed,
}

class FindLedResult {
  final FindLedOutcome outcome;

  /// The whole-controller LED number asked for.
  final int requested;

  /// Where it resolved to, when it resolved.
  final int? channelId;
  final int? localIndex;

  /// Total LEDs the controller reports (for the out-of-range message).
  final int controllerLedCount;

  const FindLedResult(
    this.outcome, {
    required this.requested,
    this.channelId,
    this.localIndex,
    this.controllerLedCount = 0,
  });

  bool get isLit => outcome == FindLedOutcome.lit;

  /// Installer-facing sentence. Never claims a light that was not confirmed.
  String get message {
    switch (outcome) {
      case FindLedOutcome.lit:
        return 'LED $requested is lit red (Channel ${channelId! + 1}, '
            'position $localIndex). Everything else is dark.';
      case FindLedOutcome.noController:
        return "Not connected to a controller — can't light LED $requested.";
      case FindLedOutcome.noChannels:
        return "The controller's channels haven't loaded yet. Check the "
            'connection and try again.';
      case FindLedOutcome.outOfRange:
        return 'LED $requested is past the end of this controller '
            '(it has $controllerLedCount LEDs: 0–${controllerLedCount - 1}).';
      case FindLedOutcome.writeFailed:
        return "The controller didn't accept the command — LED $requested "
            'was NOT lit. Check the connection and try again.';
    }
  }
}

/// Whole-controller [globalIndex] → (channel, channel-local index), using the
/// device's real bus ranges. Null when it falls outside every channel.
({DeviceChannel channel, int local})? resolveGlobalLed(
  List<DeviceChannel> channels,
  int globalIndex,
) {
  for (final c in channels) {
    if (globalIndex >= c.start && globalIndex < c.stop) {
      return (channel: c, local: globalIndex - c.start);
    }
  }
  return null;
}

/// Lights [globalIndex] red and everything else dark. Two writes, both
/// checked: a solid-black base across every channel (which also clears any
/// frozen per-pixel frame), then the single-pixel `i` write on the target
/// channel (segmentId == channel id — Lumina splits segments to match buses).
Future<FindLedResult> lightSingleLed({
  required WledRepository? repo,
  required List<DeviceChannel> channels,
  required int globalIndex,
  List<int> color = const [255, 0, 0, 0],
}) async {
  final total = channels.fold<int>(0, (m, c) => c.stop > m ? c.stop : m);
  if (repo == null || repo is! PerPixelWriter) {
    return FindLedResult(FindLedOutcome.noController, requested: globalIndex);
  }
  if (channels.isEmpty) {
    return FindLedResult(FindLedOutcome.noChannels, requested: globalIndex);
  }
  final hit = resolveGlobalLed(channels, globalIndex);
  if (hit == null) {
    return FindLedResult(FindLedOutcome.outOfRange,
        requested: globalIndex, controllerLedCount: total);
  }

  final base = applyChannelFilter(
    <String, dynamic>{
      'on': true,
      'seg': [
        {
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'pal': 0,
          'col': [
            const [0, 0, 0, 0]
          ],
        }
      ],
    },
    [for (final c in channels) c.id],
    channels,
  );
  final baseOk = await repo.applyJson(base);
  if (!baseOk) {
    return FindLedResult(FindLedOutcome.writeFailed,
        requested: globalIndex,
        channelId: hit.channel.id,
        localIndex: hit.local,
        controllerLedCount: total);
  }
  final pixelOk = await (repo as PerPixelWriter).applyPerPixel(
    segmentId: hit.channel.id,
    spans: [PixelSpan.single(hit.local, color)],
  );
  return FindLedResult(
    pixelOk ? FindLedOutcome.lit : FindLedOutcome.writeFailed,
    requested: globalIndex,
    channelId: hit.channel.id,
    localIndex: hit.local,
    controllerLedCount: total,
  );
}

/// The look fields worth putting back after a Find-LED session: master power /
/// brightness and, per segment, the design fields. Geometry (`start`/`stop`/
/// `rev`/`of`/`mi`) is deliberately NOT replayed — a design path never asserts
/// geometry (#76). No `i` key, so the apply chokepoint clears the per-pixel
/// freeze and each segment's effect renders again.
Map<String, dynamic>? buildRestorePayload(Map<String, dynamic>? prior) {
  if (prior == null) return null;
  final segs = prior['seg'];
  if (segs is! List) return null;
  final out = <Map<String, dynamic>>[];
  for (final s in segs) {
    if (s is! Map || s['id'] is! int) continue;
    out.add({
      'id': s['id'],
      for (final k in const ['on', 'bri', 'fx', 'sx', 'ix', 'pal', 'grp', 'spc', 'col'])
        if (s[k] != null) k: s[k],
    });
  }
  if (out.isEmpty) return null;
  return {
    if (prior['on'] != null) 'on': prior['on'],
    if (prior['bri'] != null) 'bri': prior['bri'],
    'seg': out,
  };
}

/// Puts back the look captured before [lightSingleLed]. Returns false when
/// there was nothing to restore or the controller refused it.
Future<bool> restoreAfterFindLed(
  WledRepository? repo,
  Map<String, dynamic>? prior,
) async {
  final payload = buildRestorePayload(prior);
  if (repo == null || payload == null) return false;
  return repo.applyJson(payload);
}
