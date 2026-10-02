// lib/features/wled/base_ladder_restore.dart
//
// +114 — does the base ladder actually LIGHT the house when it fires?
//
// WHY A SECOND LADDER FACT. `base_ladder_asserts_segments` (R2) answers a
// narrow question: do presets 1 and 2 name `on` for every channel. A preset can
// pass that and still fire dark — master on, every segment on, colour black —
// because the ladder used to capture colour from whatever the house was showing
// at save time (see base_look.dart). The end of a server Game Day restores the
// house with `{ps:1}` or `{ps:2}`, and the everyday timers load 1/3/4/5 and 2,
// so what matters is what those presets PRODUCE. This file answers that, from
// the stored preset bodies, on the LAN connect the healer already performs.
//
// THE RULES (+114 brief, item 1b):
//   ON presets 1/3/4/5 — root `on:true`, root `bri` above zero, and for every
//     PARTICIPATING bus: a segment that names `on:true`, a segment opacity
//     (`bri`) not zero when present, and something to show — a non-black colour
//     or a fixed palette (6 or higher). Solid (fx 0) shows colour slot 1 only,
//     so for Solid only slot 1 counts and the palette is ignored, exactly as
//     the firmware renders it.
//   OFF preset 2 — every bus dark: root `on:false` (or root `bri` 0, which WLED
//     loads as off), or every device bus named `on:false`.
//   Presets 1 and 2 are the two a server restore can load, so a MISSING 1 or 2
//   fails the ladder. A missing 3/4/5 is reported but does not fail it: the
//   server never restores to them, and the healer does not invent presets
//   schedule sync owns (controller_defaults_healer.dart, step (e) history).
//
// ROOT `on` IS REQUIRED ON AN ON PRESET even though the brief names `bri` only:
// without root `on` (no `ib` at save time) a preset loaded from a master-off
// strip leaves the master off — every segment "on", house dark. That is the
// 9158c00 defect, and a preset with it does not light.
//
// TRI-STATE, LIKE EVERY LADDER FACT. `null` = not measured (presets unreadable,
// no bus list, no participation). Never `false` for "we could not look":
// `false` drives the on-connect repair, and a failed GET must never do that.
//
// PURE DART apart from the Firestore sentinel types in the fact family below.

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/wled/base_look.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';

/// `true` every ladder preset lights (and the OFF preset darkens) every
/// participating bus; `false` at least one does not; absent = not measured.
const String kBaseLadderRestoreLitField = 'base_ladder_restore_lit';

/// Participating bus ids that at least one present ON preset leaves dark,
/// ascending. `[]` alongside `restore_lit:true`.
const String kBaseLadderDarkChannelsField = 'base_ladder_dark_channels';

/// The ON ladder slots.
const List<int> kLadderOnPresetIds = <int>[1, 3, 4, 5];

/// The OFF ladder slot.
const int kLadderOffPresetId = 2;

/// The presets a server restore can load; a missing one fails the ladder.
const Set<int> kLadderRequiredPresetIds = <int>{1, 2};

/// WLED palettes below this id derive their colours from the segment's own
/// colour slots (0 default, 1 random cycle, 2-5 colour-slot palettes). From 6
/// up a palette carries its own colours, so it lights a segment whose slots are
/// black.
const int kFirstFixedPaletteId = 6;

/// Why one preset fails. Short, stable codes: they are logged, recorded on the
/// repair record, and asserted by tests.
abstract final class LadderFault {
  static const missing = 'missing';
  static const rootNotOn = 'root_not_on';
  static const rootBriZero = 'root_bri_zero';
  static const noSegments = 'no_segments';
  static const channelAbsent = 'channel_absent';
  static const channelOff = 'channel_off';
  static const channelOpacityZero = 'channel_opacity_zero';
  static const channelBlack = 'channel_black';
  static const offLeavesLit = 'off_leaves_lit';
}

/// The verdict for one ladder slot.
@immutable
class LadderPresetVerdict {
  final int presetId;
  final bool present;

  /// ON preset: the participating buses it leaves dark. OFF preset: the device
  /// buses it leaves lit. Ascending.
  final List<int> channels;

  /// Fault codes ([LadderFault]), in the order found. Empty when ok.
  final List<String> faults;

  const LadderPresetVerdict({
    required this.presetId,
    required this.present,
    required this.channels,
    required this.faults,
  });

  bool get ok => present && faults.isEmpty;

  bool get isOff => presetId == kLadderOffPresetId;

  @override
  String toString() => ok
      ? 'p$presetId ok'
      : 'p$presetId ${faults.join('+')}'
          '${channels.isEmpty ? '' : ' ${isOff ? 'lit' : 'dark'}:$channels'}';
}

/// The whole ladder.
@immutable
class LadderRestoreVerdict {
  /// Every ladder slot, ascending by id (1-5).
  final List<LadderPresetVerdict> presets;

  const LadderRestoreVerdict(this.presets);

  /// The published `base_ladder_restore_lit`.
  bool get restoreLit {
    for (final p in presets) {
      if (!p.present) {
        if (kLadderRequiredPresetIds.contains(p.presetId)) return false;
        continue;
      }
      if (!p.ok) return false;
    }
    return true;
  }

  /// The published `base_ladder_dark_channels`.
  List<int> get darkChannels {
    final out = <int>{};
    for (final p in presets) {
      if (p.present && !p.isOff) out.addAll(p.channels);
    }
    return out.toList()..sort();
  }

  /// PRESENT slots that fail — what a repair would rewrite.
  List<int> get badPresetIds => [
        for (final p in presets)
          if (p.present && !p.ok) p.presetId,
      ];

  /// Slots the controller does not hold.
  List<int> get missingPresetIds => [
        for (final p in presets)
          if (!p.present) p.presetId,
      ];

  @override
  String toString() =>
      'restore_lit=$restoreLit dark=$darkChannels [${presets.join(', ')}]';
}

int? _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

/// One colour slot's components, or null when unreadable. Accepts WLED's array
/// form and its hex-string form ("FF0000" / "FF000000").
List<int>? _colorComponents(Object? slot) {
  if (slot is List) {
    final out = <int>[];
    for (final c in slot) {
      final i = _asInt(c);
      if (i == null) return null;
      out.add(i);
    }
    return out;
  }
  if (slot is String) {
    final hex = slot.startsWith('#') ? slot.substring(1) : slot;
    if (hex.length != 6 && hex.length != 8) return null;
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final v = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }
  return null;
}

bool _nonBlack(Object? slot) {
  final c = _colorComponents(slot);
  return c != null && c.any((v) => v > 0);
}

/// PURE. Does this stored segment show something when it is on?
///
/// Solid (fx 0, or fx absent) renders colour slot 1 and ignores the palette.
/// Any other effect is lit by any non-black slot or a fixed palette.
bool segmentShowsLight(Map seg) {
  final col = seg['col'];
  final slots = col is List ? col : const <Object?>[];
  final fx = _asInt(seg['fx']) ?? kBaseLookEffectId;
  if (fx == kBaseLookEffectId) {
    return slots.isNotEmpty && _nonBlack(slots.first);
  }
  if (slots.any(_nonBlack)) return true;
  final pal = _asInt(seg['pal']);
  return pal != null && pal >= kFirstFixedPaletteId;
}

/// Index a stored preset's segments by id, falling back to position for the
/// id-less shape (the same rule `presetSatisfies` uses).
Map<int, Map> _segmentsById(Object? raw) {
  final out = <int, Map>{};
  if (raw is! List) return out;
  for (var i = 0; i < raw.length; i++) {
    final s = raw[i];
    if (s is! Map) continue;
    out[_asInt(s['id']) ?? i] = s;
  }
  return out;
}

/// PURE. One ON slot against the participating buses.
LadderPresetVerdict evaluateOnPreset(
  int presetId,
  Map<String, dynamic>? def,
  List<int> participating,
) {
  if (def == null) {
    return LadderPresetVerdict(
      presetId: presetId,
      present: false,
      channels: List<int>.from(participating)..sort(),
      faults: const [LadderFault.missing],
    );
  }
  final faults = <String>[];
  final dark = <int>{};

  if (def['on'] != true) faults.add(LadderFault.rootNotOn);
  final bri = _asInt(def['bri']);
  if (bri == null || bri <= 0) faults.add(LadderFault.rootBriZero);
  // A preset that cannot raise the master leaves every bus dark.
  if (faults.isNotEmpty) dark.addAll(participating);

  final segs = _segmentsById(def['seg']);
  if (segs.isEmpty) {
    faults.add(LadderFault.noSegments);
    dark.addAll(participating);
  } else {
    for (final c in participating) {
      final s = segs[c];
      String? fault;
      if (s == null) {
        fault = LadderFault.channelAbsent;
      } else if (s['on'] != true) {
        fault = LadderFault.channelOff;
      } else if (_asInt(s['bri']) == 0) {
        fault = LadderFault.channelOpacityZero;
      } else if (!segmentShowsLight(s)) {
        fault = LadderFault.channelBlack;
      }
      if (fault != null) {
        dark.add(c);
        if (!faults.contains(fault)) faults.add(fault);
      }
    }
  }
  return LadderPresetVerdict(
    presetId: presetId,
    present: true,
    channels: dark.toList()..sort(),
    faults: faults,
  );
}

/// PURE. The OFF slot against every device bus.
LadderPresetVerdict evaluateOffPreset(
  Map<String, dynamic>? def,
  List<int> deviceChannelIds,
) {
  if (def == null) {
    return const LadderPresetVerdict(
      presetId: kLadderOffPresetId,
      present: false,
      channels: [],
      faults: [LadderFault.missing],
    );
  }
  // Root master off kills every bus regardless of segments; so does root bri 0.
  if (def['on'] == false || _asInt(def['bri']) == 0) {
    return const LadderPresetVerdict(
      presetId: kLadderOffPresetId,
      present: true,
      channels: [],
      faults: [],
    );
  }
  final segs = _segmentsById(def['seg']);
  final lit = <int>[
    for (final c in deviceChannelIds)
      if (segs[c]?['on'] != false) c,
  ]..sort();
  return LadderPresetVerdict(
    presetId: kLadderOffPresetId,
    present: true,
    channels: lit,
    faults: lit.isEmpty ? const [] : const [LadderFault.offLeavesLit],
  );
}

/// PURE. The whole ladder, or null when it cannot be measured.
///
/// [presets] null = unreadable. An empty map is a REAL measurement (the
/// controller holds nothing) and yields `restoreLit:false` with every slot
/// missing. [participating] empty or [deviceChannelIds] empty = we do not know
/// which buses must light → null.
LadderRestoreVerdict? evaluateLadderRestore({
  required Map<int, Map<String, dynamic>>? presets,
  required List<int> participating,
  required List<int> deviceChannelIds,
}) {
  if (presets == null) return null;
  if (participating.isEmpty || deviceChannelIds.isEmpty) return null;
  final out = <LadderPresetVerdict>[];
  for (final id in const [1, 2, 3, 4, 5]) {
    out.add(id == kLadderOffPresetId
        ? evaluateOffPreset(presets[id], deviceChannelIds)
        : evaluateOnPreset(id, presets[id], participating));
  }
  return LadderRestoreVerdict(out);
}

// ── The fact family ──────────────────────────────────────────────────────────

/// What this process last published per controller: `restore_lit` + the dark
/// list, compared by value. Process-scoped like every fact memo here — a
/// relaunch republishes by design (controller_facts_writer.dart).
final Map<String, String> publishedLadderRestoreMemo = <String, String>{};

String _memoKey(LadderRestoreVerdict v) =>
    '${v.restoreLit}|${v.darkChannels.join(',')}';

/// This family's contribution to a publish, or [PreparedFacts.none] when the
/// verdict is unmeasured or unchanged from what this process last published.
PreparedFacts prepareLadderRestoreFacts({
  required String controllerId,
  required LadderRestoreVerdict? verdict,
  required String source,
}) {
  if (verdict == null) return PreparedFacts.none;
  final key = _memoKey(verdict);
  final last = publishedLadderRestoreMemo[controllerId];
  if (last == key) return PreparedFacts.none;

  final fields = <String, Object?>{
    kBaseLadderRestoreLitField: verdict.restoreLit,
    kBaseLadderDarkChannelsField: verdict.darkChannels,
  };
  stampFactFamily(
    fields,
    field: kBaseLadderRestoreLitField,
    source: source,
    previous: last == null ? null : last.split('|').first == 'true',
    previousKnown: last != null,
  );
  return PreparedFacts(
    fields,
    () => publishedLadderRestoreMemo[controllerId] = key,
  );
}

/// Test seam: forget what this process published.
@visibleForTesting
void resetLadderRestoreMemo() => publishedLadderRestoreMemo.clear();
