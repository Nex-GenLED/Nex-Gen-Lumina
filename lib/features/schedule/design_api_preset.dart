// lib/features/schedule/design_api_preset.dart
//
// Roofline slice 2 — a PAINTED design as a nightly WLED preset.
//
// A preset saved the way the app saves presets (`psave` of live state) stores
// segment settings, never the pixel buffer, and captures `frz:true`: fired
// from a timer it renders nothing (ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03
// §B.1, memory frozen_segment_swallows_writes). The one WLED preset kind that
// can carry a picture is the API-command preset: a request saved with `o:true`
// is written to presets.json AS THE REQUEST and replayed through
// `deserializeState` at fire time, `seg[].i` included.
//
// OWNER DECISIONS (2026-11-05) this file encodes:
//   1. Mechanism — an API-command preset whose body carries ONE ENTRY PER BUS,
//      each with explicit `start`/`stop` from the design's stamped
//      `bus_lengths` (cumulative offsets, segment id = bus). A power cycle
//      collapses the split to one segment; at the next fire the bounds in the
//      body re-create every bus, so all of them are painted with no app on
//      the LAN. Not runs-as-segments, no boot preset.
//   2. Byte cap — REFUSE, never simplify. [kDesignApiPresetMaxBytes].
//   3. Firmware — allowed only on versions the bench has proven.
//      [kDesignApiPresetProvenFirmware]; unreadable or unproven refuses.
//   4. Eligibility — stamped (slice 1), on the controller's LAN, the live
//      layout fits the stamp (the slice 1 fit gate), body under the cap.
//      Never write while the layout is unread.
//   5. Capacity — [kMaxDesignSchedulesPerAccount] painted designs per account.
//   6. Flash safety — write only when the stored payload hash differs, one
//      writer at a time, read back after every write (schedule_sync.dart).
//
// Everything here is PURE: no Riverpod, no I/O. The picker and the sync feed
// it device facts they already hold (the live channel list, the controller id,
// the firmware version) and act on the verdict.

import 'dart:async';
import 'dart:convert';

import 'package:nexgen_command/features/design/design_layout_fit.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';

/// Hard ceiling on a design preset's API body, in BYTES, for the WHOLE body
/// across all buses as it goes over the wire (`o`, `on`, `bri`, every bus
/// entry with its `i`, plus `psave` and `n`).
///
/// PROVISIONAL. The bench-measured ceiling for a `/json/state` POST is about
/// 6.0 KB before WLED answers HTTP 400 `{"error":9}` (per_pixel.dart), and the
/// file-load path an API preset takes at fire time has not been measured at
/// all. 5,000 keeps headroom under the known POST ceiling until the bench
/// calibration (docs/bench/roofline_slice2_bench_2026-11-05.md, step 1: bodies
/// of 2 / 4 / 6 / 8 / 12 KB saved, read back and fired on the spare) sets the
/// final value. Change it HERE only; nothing else states a number.
const int kDesignApiPresetMaxBytes = 5000;

/// WLED firmware versions on which a nightly painted-design preset has been
/// bench-proven end to end (save, read back, fire by timer from master-off,
/// OFF boundary, power cycle before the fire). The string is `/json/info`'s
/// `ver`, compared exactly after trimming.
///
/// 0.15.4 only for now (the spare). 0.15.1 and 16.0.1 are added here after
/// the bench proves them (step 5 of the slice 2 bench doc). An unproven or
/// unreadable version refuses with a plain message.
const Set<String> kDesignApiPresetProvenFirmware = <String>{'0.15.4'};

/// Painted designs on the schedule, per account. A fifth refuses with a plain
/// message. Each one holds a preset slot in the 10–25 band and several KB of
/// presets.json on the controller; four keeps the file and the user document
/// small until the per-account headroom is measured.
const int kMaxDesignSchedulesPerAccount = 4;

/// True when [ver] (as `/json/info` reports it) is on the proven list.
bool isDesignApiPresetFirmwareProven(String? ver) {
  if (ver == null) return false;
  final v = ver.trim();
  return v.isNotEmpty && kDesignApiPresetProvenFirmware.contains(v);
}

/// True when [payload] is a WLED API-command preset body (`o:true`). This is
/// the one key every design preset body carries and no other builder writes;
/// the scope rule, the fan-out, the normaliser and the relay all key off it.
bool isDesignApiPresetBody(Map<String, dynamic>? payload) =>
    payload != null && payload['o'] == true;

/// The three colour slots WLED keeps on a segment, all black: a painted
/// segment's base is the buffer the `i` paint overwrites, and stating it
/// pinned keeps the stored body (and so its hash) stable across saves.
const List<List<int>> _kBlackColSlots = [
  [0, 0, 0, 0],
  [0, 0, 0, 0],
  [0, 0, 0, 0],
];

/// The API body for [design]: one `seg` entry per stamped bus, in bus order,
/// with explicit bounds from the stamp's cumulative `bus_lengths`.
///
/// A bus the design paints gets `{id, start, stop, on:true, fx:0, grp:1,
/// spc:0, pal:0, col: three black slots, i: the range-compressed paint over
/// the whole bus}`. A bus the design leaves out (channel not included, or not in the
/// design at all) gets `{id, start, stop, on:false}` — the bounds still
/// re-create the bus after a power cycle, and the scope rule's meaning holds:
/// a look that excludes a channel darkens it (U-7, schedule_models.dart).
/// A zero-length bus in the stamp gets no entry.
///
/// Root: `o:true`, `on:true`, `bri` (the design's stated brightness, or 255
/// as the pattern path forces — a nightly fire is an ON action and must never
/// be saved dark). No `ib`/`sb`: those steer the captured-state save branch,
/// which an API preset never takes.
///
/// Returns null for a design that is not positional or carries no stamp; the
/// eligibility verdict says why, this just declines to build.
Map<String, dynamic>? buildDesignApiPresetBody(CustomDesign design) {
  if (!design.isPositional) return null;
  final stamp = design.layoutStamp;
  if (stamp == null) return null;

  final byId = <int, ChannelDesign>{
    for (final c in design.channels) c.channelId: c,
  };
  final segs = <Map<String, dynamic>>[];
  var offset = 0;
  for (var bus = 0; bus < stamp.busCount; bus++) {
    final len = stamp.busLengths[bus];
    if (len <= 0) continue;
    final start = offset;
    final stop = offset + len;
    offset = stop;

    final channel = byId[bus];
    if (channel == null || !channel.included) {
      segs.add(<String, dynamic>{
        'id': bus,
        'start': start,
        'stop': stop,
        'on': false,
      });
      continue;
    }

    final spans = _coverBus(channel.fullCoverageSpans(), len);
    final i = (buildPerPixelPayload(spans, bus)['seg'] as List).first['i'];
    segs.add(<String, dynamic>{
      'id': bus,
      'start': start,
      'stop': stop,
      'on': true,
      'fx': 0,
      'grp': 1,
      'spc': 0,
      'pal': 0,
      'col': [for (final c in _kBlackColSlots) List<int>.from(c)],
      'i': i,
    });
  }

  return <String, dynamic>{
    'o': true,
    'on': true,
    'bri': design.appliedBrightness ?? 255,
    'seg': segs,
  };
}

/// Clip channel-local [spans] to `[0, len)` and fill any uncovered tail with
/// black, so the `i` array covers exactly the bus. The fit gate has already
/// refused a design whose stamp differs from the live buses; this keeps the
/// body well-formed even for a channel whose stored `led_count` disagrees
/// with its own stamp.
List<PixelSpan> _coverBus(List<PixelSpan> spans, int len) {
  final clipped = <PixelSpan>[];
  for (final s in spans) {
    if (s.start >= len) continue;
    final end = s.end >= len ? len - 1 : s.end;
    if (end < s.start) continue;
    clipped.add(PixelSpan(start: s.start, end: end, color: s.color));
  }
  final merged = normalizeAndMergePixelSpans(clipped);
  final covered = merged.isEmpty ? 0 : merged.last.end + 1;
  if (covered < len) {
    return normalizeAndMergePixelSpans([
      ...merged,
      PixelSpan(start: covered, end: len - 1, color: const [0, 0, 0, 0]),
    ]);
  }
  return merged;
}

/// The body as it goes over the wire — with the `psave` slot and the preset
/// name the save adds — measured in UTF-8 bytes. This is the number the byte
/// cap is compared against, so the cap means what the controller sees.
///
/// At pick time the slot is not yet assigned; callers pass
/// [kLastSchedulePresetId] (two digits, the widest the band has) so the
/// measurement cannot be smaller than the eventual write.
int designApiPresetWireBytes(
  Map<String, dynamic> body, {
  required int presetId,
  required String presetName,
}) =>
    utf8.encode(jsonEncode(<String, dynamic>{
      ...body,
      'psave': presetId,
      'n': presetName,
    })).length;

/// Why a stored design preset body cannot be written, or null when its shape
/// is what [buildDesignApiPresetBody] produces: `o:true`, a non-empty `seg`
/// list whose entries carry an int `id` and bounds with `stop > start`, and a
/// list `i` on every entry that is `on`. Operator-readable; the customer
/// sentence is [designApiPresetMalformedMessage].
String? designApiPresetBodyProblem(Map<String, dynamic>? body) {
  if (body == null) return 'no payload';
  if (body['o'] != true) return 'not an API-command body (no o:true)';
  final seg = body['seg'];
  if (seg is! List || seg.isEmpty) return 'no seg entries';
  for (var k = 0; k < seg.length; k++) {
    final s = seg[k];
    if (s is! Map) return 'seg[$k] is not an object';
    final id = s['id'];
    final start = s['start'];
    final stop = s['stop'];
    if (id is! int || start is! int || stop is! int) {
      return 'seg[$k] lacks int id/start/stop';
    }
    if (stop <= start) return 'seg[$k] has stop $stop <= start $start';
    if (s['on'] == true && s['i'] is! List) {
      return 'seg[$k] (id $id) is on but carries no i array';
    }
  }
  return null;
}

/// True when the body's bus entries are EXACTLY the live expected shape: the
/// same ids, each with the same `start`/`stop`, and no id on either side the
/// other lacks. The sync asks this before any write, against the controller's
/// own `hw.led.ins` buses (device truth) — owner decision 4, "the live layout
/// fits the stamp", re-checked at write time, not only at pick time.
bool designApiPresetBoundsMatch(
  Map<String, dynamic> body,
  List<SegmentShape> liveBuses,
) {
  final seg = body['seg'];
  if (seg is! List || liveBuses.isEmpty) return false;
  final want = <int, SegmentShape>{for (final b in liveBuses) b.id: b};
  final seen = <int>{};
  for (final s in seg) {
    if (s is! Map) return false;
    final id = s['id'];
    if (id is! int) return false;
    final live = want[id];
    if (live == null) return false;
    if (s['start'] != live.start || s['stop'] != live.stop) return false;
    seen.add(id);
  }
  return seen.length == want.length;
}

/// How many schedules in [schedules] are painted designs, leaving out
/// [excludingId] (the one being edited, which is never counted against
/// itself).
int designScheduleCount(Iterable<ScheduleItem> schedules,
    {String? excludingId}) {
  var n = 0;
  for (final s in schedules) {
    if (s.id == excludingId) continue;
    if (s.isDesignApiPreset) n++;
  }
  return n;
}

/// The per-account cap, at SAVE time: null when [candidate] may be saved, else
/// the sentence to show. Only a painted-design candidate is ever refused;
/// [editingId] (and the candidate's own id) are not counted, so editing one of
/// four keeps working.
String? designScheduleCountRefusal({
  required ScheduleItem candidate,
  required List<ScheduleItem> schedules,
  String? editingId,
}) {
  if (!candidate.isDesignApiPreset) return null;
  var n = 0;
  for (final s in schedules) {
    if (s.id == editingId || s.id == candidate.id) continue;
    if (s.isDesignApiPreset) n++;
  }
  if (n < kMaxDesignSchedulesPerAccount) return null;
  return designScheduleTooManyMessage(plainDesignName(candidate.actionLabel));
}

/// "Pattern: Porch stripes" → "Porch stripes"; anything else unchanged.
String plainDesignName(String actionLabel) =>
    actionLabel.startsWith('Pattern: ')
        ? actionLabel.substring('Pattern: '.length)
        : actionLabel;

// ── One writer at a time (owner decision 6) ─────────────────────────────────

/// A FIFO lock: each call runs after every call queued before it has settled.
/// Two syncs that overlap (a manual Sync during the stream-triggered one, a
/// lease write during a sync) must not interleave a design preset's write and
/// its read-back, or the read-back would judge the other writer's bytes.
class SerialWriteLock {
  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }
}

/// The process-wide lock every design preset write takes.
final SerialWriteLock designPresetWriteLock = SerialWriteLock();

// ── Customer-readable sentences ─────────────────────────────────────────────

String designScheduleUnstampedMessage(String name) =>
    '"$name" was saved before Lumina recorded your roofline layout, so it '
    "can't be scheduled yet. Open the design, save it again, and then "
    'schedule it.';

String designScheduleOffLanMessage(String name) =>
    '"$name" can only be scheduled from your home network, because Lumina '
    "checks it against your controller's layout first. Connect to your home "
    'Wi-Fi and try again.';

String designScheduleFirmwareUnreadableMessage(String name) =>
    "Lumina couldn't read your controller's firmware version, so \"$name\" "
    "wasn't scheduled. Try again in a moment.";

String designScheduleFirmwareUnprovenMessage(String name, String ver) =>
    'Your controller runs WLED $ver. Scheduling a painted design has been '
    'proven on WLED ${kDesignApiPresetProvenFirmware.join(', ')} only, so '
    "\"$name\" can't be scheduled on this controller yet. You can still apply "
    'it any time from My Designs.';

/// Names the limit ("about 5.0 KB, 5,000 bytes") and offers the repair: open
/// the editor and simplify. No automatic simplification (owner decision 2).
String designScheduleTooLargeMessage(String name, int bytes) =>
    '"$name" is too detailed to schedule: it comes to ${_kb(bytes)} '
    '(${_thousands(bytes)} bytes), and your controller can store about '
    '${_kb(kDesignApiPresetMaxBytes)} (${_thousands(kDesignApiPresetMaxBytes)} '
    'bytes) per scheduled design. Open the design and simplify it — fewer '
    'colours, or longer runs of one colour — then try again.';

String designScheduleTooManyMessage(String name) =>
    'You already have $kMaxDesignSchedulesPerAccount painted designs on your '
    'schedule, which is the most your controller can hold. Remove one of them '
    'before scheduling "$name".';

/// The sync's sentence for a per-pixel payload that reached a schedule by any
/// path other than the schedule editor's My Designs pick (Lumina chat, a
/// calendar intent, an older build): it is not written, and not armed.
String designApiPresetStrayMessage(String name) =>
    '"$name" is a painted design that reached your schedule without being '
    "checked against your controller, so it wasn't saved to the controller "
    "and won't run. Open the schedule and pick the design again from My "
    'Designs.';

String designApiPresetMalformedMessage(String name) =>
    "\"$name\" can't be saved to your controller as it is stored. Open the "
    'schedule and pick the design again from My Designs.';

String designApiPresetLayoutUnreadMessage(String name) =>
    "Lumina couldn't read your controller's layout, so \"$name\" wasn't "
    'saved to it this time. It will be saved on the next sync from your home '
    'network.';

String designApiPresetLayoutChangedMessage(String name) =>
    "Your roofline layout no longer matches \"$name\", so it wasn't saved to "
    "your controller and won't run. Open the design, save it again, and pick "
    'it again in the schedule.';

String designApiPresetReadBackMessage(String name) =>
    "\"$name\" didn't land on your controller as written, so its schedule "
    "isn't armed. Try syncing again from your home network.";

/// "Just this day" with a painted design: the one-night lease path is not a
/// nightly design mechanism (audit §B.2) and refuses, in the editor and at
/// the lease write.
String designOneNightRefusedMessage(String name) =>
    '"$name" is a painted design, which can be scheduled weekly but not for '
    'a single night yet. Pick a colour-and-effect pattern for this night, or '
    'schedule the design on its weekdays instead.';

/// Shown under the picker row when a painted design is selected.
const String kDesignScheduleHelperCopy =
    'This painted design will be saved to your controller as a picture and '
    'fired by its own timer. If your roofline layout changes, open the design '
    'and save it again, then pick it here again.';

String _kb(int bytes) => 'about ${(bytes / 1000).toStringAsFixed(1)} KB';

String _thousands(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var k = 0; k < s.length; k++) {
    if (k > 0 && (s.length - k) % 3 == 0) out.write(',');
    out.write(s[k]);
  }
  return out.toString();
}

// ── Eligibility (owner decision 4, in order) ────────────────────────────────

enum DesignScheduleVerdict {
  allowed,

  /// Not a painted design (the caller should not have asked).
  notPositional,

  /// Saved before the layout stamp existed (slice 1): re-save from the editor.
  unstamped,

  /// The repository is not a direct-LAN service, or the app is in remote
  /// mode: no bus data, no cfg door, no firmware read.
  offLan,

  /// On the LAN but the bus list is empty (cfg loading or unread).
  layoutUnknown,

  /// The stamp does not match the live buses (count, a length, or the
  /// controller record) — the slice 1 fit gate's verdict and sentence.
  layoutMismatch,

  firmwareUnreadable,
  firmwareUnproven,

  /// Over [kDesignApiPresetMaxBytes]; the message offers the editor.
  tooLarge,

  /// [kMaxDesignSchedulesPerAccount] already on the schedule.
  tooMany,
}

/// The verdict with everything the caller needs: the sentence to show on a
/// refusal, the body to store when allowed, its wire size, and whether the
/// refusal is one the editor can fix (so the UI offers to open it).
class DesignScheduleEligibility {
  const DesignScheduleEligibility._(
    this.verdict, {
    this.message,
    this.body,
    this.bytes = 0,
    this.offersEditor = false,
  });

  final DesignScheduleVerdict verdict;
  final String? message;
  final Map<String, dynamic>? body;
  final int bytes;
  final bool offersEditor;

  bool get allowed => verdict == DesignScheduleVerdict.allowed;

  @override
  String toString() => 'DesignScheduleEligibility(${verdict.name}, $bytes B)';
}

/// PURE. May [design] be scheduled nightly on the controller the app is
/// looking at? Checks run in the owner's order and the first refusal wins.
///
/// [onLan] — the repository is a direct-LAN `WledService` AND the app is not
/// in remote mode. A relay of either mode is off-LAN here: it has no cfg
/// door for the bus list and no firmware read.
/// [liveChannels] — `deviceChannelsProvider` (empty = no bus data).
/// [liveControllerId] — `selectedControllerIdProvider`; null means no
/// expectation, so the lengths alone decide (slice 1's rule).
/// [firmwareVersion] — `/json/info`'s `ver`; null or empty = unreadable.
/// [existingDesignScheduleCount] — painted designs already on the schedule,
/// not counting the one being edited.
/// [presetId] / [presetName] — what the eventual save sends, for the byte
/// measurement; the defaults are the widest slot and the design's name.
DesignScheduleEligibility designScheduleEligibility({
  required CustomDesign design,
  required bool onLan,
  required List<DeviceChannel> liveChannels,
  String? liveControllerId,
  required String? firmwareVersion,
  required int existingDesignScheduleCount,
  int presetId = kLastSchedulePresetId,
  String? presetName,
}) {
  final name = design.name;
  if (!design.isPositional) {
    return const DesignScheduleEligibility._(
        DesignScheduleVerdict.notPositional);
  }
  if (design.layoutStamp == null) {
    return DesignScheduleEligibility._(DesignScheduleVerdict.unstamped,
        message: designScheduleUnstampedMessage(name));
  }
  if (!onLan) {
    return DesignScheduleEligibility._(DesignScheduleVerdict.offLan,
        message: designScheduleOffLanMessage(name));
  }
  final fit = layoutFitOf(
    designName: name,
    stamp: design.layoutStamp,
    liveChannels: liveChannels,
    liveControllerId: liveChannels.isEmpty ? null : liveControllerId,
    remote: () => false, // off-LAN was refused above; an empty list is LAN
  );
  if (fit.verdict == LayoutFitVerdict.layoutUnknown) {
    return DesignScheduleEligibility._(DesignScheduleVerdict.layoutUnknown,
        message: fit.message);
  }
  if (!fit.applies) {
    return DesignScheduleEligibility._(DesignScheduleVerdict.layoutMismatch,
        message: fit.message);
  }
  final ver = firmwareVersion?.trim() ?? '';
  if (ver.isEmpty) {
    return DesignScheduleEligibility._(
        DesignScheduleVerdict.firmwareUnreadable,
        message: designScheduleFirmwareUnreadableMessage(name));
  }
  if (!isDesignApiPresetFirmwareProven(ver)) {
    return DesignScheduleEligibility._(DesignScheduleVerdict.firmwareUnproven,
        message: designScheduleFirmwareUnprovenMessage(name, ver));
  }
  final body = buildDesignApiPresetBody(design);
  if (body == null) {
    // Positional and stamped, so this cannot happen; refuse rather than
    // return an allowed verdict with nothing to store.
    return DesignScheduleEligibility._(DesignScheduleVerdict.unstamped,
        message: designScheduleUnstampedMessage(name));
  }
  final bytes = designApiPresetWireBytes(body,
      presetId: presetId, presetName: presetName ?? 'Pattern: $name');
  if (bytes > kDesignApiPresetMaxBytes) {
    return DesignScheduleEligibility._(DesignScheduleVerdict.tooLarge,
        message: designScheduleTooLargeMessage(name, bytes),
        bytes: bytes,
        offersEditor: true);
  }
  if (existingDesignScheduleCount >= kMaxDesignSchedulesPerAccount) {
    return DesignScheduleEligibility._(DesignScheduleVerdict.tooMany,
        message: designScheduleTooManyMessage(name), bytes: bytes);
  }
  return DesignScheduleEligibility._(DesignScheduleVerdict.allowed,
      body: body, bytes: bytes);
}
