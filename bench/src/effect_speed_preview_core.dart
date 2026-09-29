// Pure logic for the per-effect speed preview (bench/bin/effect_speed_preview.dart).
//
// No I/O here beyond values handed in, so every rule that keeps the preview
// safe is unit-tested (test/bench/effect_speed_preview_core_test.dart):
//   • the live home controller is refused by address, before and after connect;
//   • a payload can only ever be LIVE state — no preset, playlist, reboot or
//     config key survives [assertLiveStateOnly];
//   • a full-field strobe is never previewed at an unsafe rate — see
//     [clampFlashForPreview];
//   • the restore payload is the exact inverse of what a preview touches, and
//     [restoreDiff] proves it landed.
//
// Same rules as bench/src/team_led_preview_core.dart (fix/team-led-colors),
// restated here because that branch is not on release.

import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// The LIVE home controller. Never a preview target.
const String kLiveHomeControllerIp = '192.168.1.150';

/// The spare, unregistered bench controller.
const String kSpareControllerIp = '192.168.1.173';

/// Keys that would persist, load or reboot. A preview is live state only.
const Set<String> kForbiddenAnywhere = {
  'psave', 'pdel', 'ps', 'pl', 'playlist', 'rb',
};

/// Top-level keys that only mean something alongside a preset save (`ib`,
/// `sb`, `n`, `ql`) or advance a playlist (`np`).
const Set<String> kForbiddenTopLevel = {'ib', 'sb', 'n', 'ql', 'np'};

/// The segment fields a preview writes — and therefore the only ones restore
/// puts back. `c1`–`c3`/`o1`–`o3` are included because the preview states the
/// effect's options at their start values (the app's normalizer does too).
const List<String> kTouchedSegFields = [
  'on', 'frz', 'bri', 'grp', 'spc', 'of', 'fx', 'sx', 'ix', 'pal', 'col',
  'c1', 'c2', 'c3', 'o1', 'o2', 'o3',
];

/// The owner's report of 2026-09-29, previewed first.
const List<int> kOwnerReportedTooFast = [
  64, // Juggle
  91, // Bouncing Balls
  111, // Chunchun
  23, // Strobe
  42, // Fireworks
  90, // Fireworks 1D
  89, // Fireworks Starburst
  112, // Dancing Shadows
  25, // Strobe Mega — RETIRED 2026-09-29, so never previewed (skipped below)
];

/// The highest Strobe / Strobe Rainbow / Strobe Mega speed the PREVIEW will
/// send: one flash per `(255-sx)*20 + 2*FRAMETIME` ms is ≤ 3 Hz up to here.
const int kFlashPreviewMaxSpeed = 240;

/// Strobe Mega flashes `intensity/10 + 1` times per burst at ~11–15 Hz. Below
/// 10 it is one flash per burst, which is the only way the preview shows it.
const int kStrobeMegaPreviewMaxIntensity = 9;

/// Refuses the live home controller. [resolved] are the addresses [host]
/// resolved to (a hostname can point at it too).
String? refuseHost(String host, {List<String> resolved = const []}) {
  if (host.trim() == kLiveHomeControllerIp ||
      resolved.contains(kLiveHomeControllerIp)) {
    return 'REFUSED: $kLiveHomeControllerIp is the live home controller. '
        'The preview only ever targets the spare ($kSpareControllerIp).';
  }
  return null;
}

/// Refuses a controller whose own /json/info reports the live home address.
String? refuseInfo(Map<String, dynamic> info) {
  if (info['ip'] == kLiveHomeControllerIp) {
    return 'REFUSED: the controller reports ip $kLiveHomeControllerIp — that '
        'is the live home controller.';
  }
  return null;
}

/// Throws [StateError] if [payload] could persist, load, or reboot anything.
void assertLiveStateOnly(Map<String, dynamic> payload) {
  for (final k in payload.keys) {
    if (kForbiddenTopLevel.contains(k)) {
      throw StateError('refusing to send "$k" — live state only');
    }
  }
  void walk(Object? node) {
    if (node is Map) {
      for (final e in node.entries) {
        if (kForbiddenAnywhere.contains(e.key)) {
          throw StateError('refusing to send "${e.key}" — live state only');
        }
        walk(e.value);
      }
    } else if (node is List) {
      node.forEach(walk);
    }
  }

  walk(payload);
}

/// One effect to review.
class PreviewEffect {
  const PreviewEffect({
    required this.id,
    required this.name,
    required this.speed,
    required this.intensity,
    required this.sliderMin,
    required this.sliderMax,
    required this.note,
  });

  final int id;
  final String name;

  /// The table's proposal, or null when `sx` is not a pace for this effect.
  final int? speed;

  /// The table's intensity for an effect whose rate is intensity, else null.
  final int? intensity;

  /// The app slider's range for this effect (the owner can go either way).
  final int sliderMin;
  final int sliderMax;

  /// The table entry's own comment ("too fast (owner 09-29) · …").
  final String note;

  bool get isFlash => kPhotosensitiveFlashEffectIds.contains(id);
  bool get speedIsPace => speed != null;
}

/// Every effect the table covers that a 1D roofline can run (no 2D, no
/// audio), the owner's nine first, then catalogue order. [includeFlash]
/// false leaves out the full-field strobes entirely.
List<PreviewEffect> previewEffects({
  bool includeFlash = false,
  bool includeAll = false,
  Map<int, String> notes = const {},
}) {
  PreviewEffect make(WledEffect e) {
    final p = getSpeedProfile(e.id);
    return PreviewEffect(
      id: e.id,
      name: e.name,
      speed: effectDefaultSpeed(e.id),
      intensity: effectDefaultIntensity(e.id),
      sliderMin: p.rawMin,
      sliderMax: p.rawMax,
      note: notes[e.id] ?? '',
    );
  }

  // Offered effects only: a retired one (Strobe Mega) is never selected, so
  // there is no speed to review (pattern_flash_safety.dart).
  final eligible = [
    for (final e in WledEffectsCatalog.offeredEffects)
      if (includeAll || (!e.requires2D && !e.requiresAudio)) e,
  ];
  final byId = {for (final e in eligible) e.id: e};
  final ordered = <WledEffect>[
    for (final id in kOwnerReportedTooFast)
      if (byId[id] != null) byId[id]!,
    for (final e in eligible)
      if (!kOwnerReportedTooFast.contains(e.id)) e,
  ];
  return [
    for (final e in ordered)
      if (includeFlash || !kPhotosensitiveFlashEffectIds.contains(e.id))
        make(e),
  ];
}

final RegExp _tableLine =
    RegExp(r'^\s*(\d+): (\d+), // (.*) · [^·]+$');

/// Effect id → the trailing comment of its line in
/// lib/features/wled/pattern_effect_speeds.dart (display only; values come
/// from the import).
Map<int, String> parseTableNotes(String tableSource) => {
      for (final line in tableSource.split('\n'))
        if (_tableLine.firstMatch(line.trimRight()) case final m?)
          int.parse(m.group(1)!): m.group(3)!,
    };

/// The preview never flashes the whole field faster than ~3 Hz, whatever
/// value is being reviewed: Strobe / Strobe Rainbow / Strobe Mega speed is
/// capped at [kFlashPreviewMaxSpeed], and Strobe Mega's intensity at
/// [kStrobeMegaPreviewMaxIntensity] (one flash per burst). Returns the
/// values to SEND and whether anything was capped.
({int sx, int ix, bool capped}) clampFlashForPreview(int fx, int sx, int ix) {
  if (!kPhotosensitiveFlashEffectIds.contains(fx)) {
    return (sx: sx, ix: ix, capped: false);
  }
  final safeSx = sx > kFlashPreviewMaxSpeed ? kFlashPreviewMaxSpeed : sx;
  final safeIx = fx == 25 && ix > kStrobeMegaPreviewMaxIntensity
      ? kStrobeMegaPreviewMaxIntensity
      : ix;
  return (sx: safeSx, ix: safeIx, capped: safeSx != sx || safeIx != ix);
}

/// The live-state preview payload for existing segments [segIds]: effect [fx]
/// at speed [sx] in two high-contrast colours, laid out exactly as the app
/// would (grp 1, spc 0, the app's palette for the effect).
///
/// `tt: 0` is a one-shot instant transition (not persisted, nothing to
/// restore). Throws if the payload is not live state, and if a flash effect
/// arrives above its preview cap — [clampFlashForPreview] first.
Map<String, dynamic> buildPreviewPayload({
  required List<int> segIds,
  required int fx,
  required int sx,
  required int ix,
  required int bri,
  List<List<int>> colors = const [
    [255, 60, 0, 0],
    [0, 70, 255, 0],
    [0, 0, 0, 0],
  ],
}) {
  final safe = clampFlashForPreview(fx, sx, ix);
  if (safe.capped) {
    throw StateError('flash effect $fx above its preview cap — '
        'call clampFlashForPreview first');
  }
  final payload = <String, dynamic>{
    'on': true,
    'bri': bri.clamp(1, 255),
    'tt': 0,
    'seg': [
      for (final id in segIds)
        {
          'id': id,
          'on': true,
          'frz': false,
          'bri': 255,
          'grp': 1,
          'spc': 0,
          'of': 0,
          'fx': fx,
          'sx': sx.clamp(0, 255),
          'ix': ix.clamp(0, 255),
          'pal': WledEffectsCatalog.paletteForEffect(fx),
          'col': colors,
        },
    ],
  };
  assertLiveStateOnly(payload);
  return payload;
}

/// Segment ids present in a captured /json/state (`seg` may be a list or a
/// single map depending on firmware).
List<int> segIdsOf(Map<String, dynamic> state) => [
      for (final s in _segs(state))
        if (s['id'] is num) (s['id'] as num).toInt(),
    ];

List<Map<String, dynamic>> _segs(Map<String, dynamic> state) {
  final seg = state['seg'];
  final list = seg is List ? seg : (seg is Map ? [seg] : const []);
  return [for (final s in list) if (s is Map) s.cast<String, dynamic>()];
}

/// The exact inverse of every preview: master on/bri, and on each captured
/// segment only the [kTouchedSegFields] it reported.
Map<String, dynamic> buildRestorePayload(Map<String, dynamic> captured) {
  final payload = <String, dynamic>{
    if (captured.containsKey('on')) 'on': captured['on'],
    if (captured.containsKey('bri')) 'bri': captured['bri'],
    'tt': 0,
    'seg': [
      for (final s in _segs(captured))
        {
          'id': s['id'],
          for (final f in kTouchedSegFields)
            if (s.containsKey(f)) f: s[f],
        },
    ],
  };
  assertLiveStateOnly(payload);
  return payload;
}

/// Fields that differ between the capture and a post-restore readback. Empty
/// means the controller is back exactly as found (for everything the preview
/// can touch).
List<String> restoreDiff(
  Map<String, dynamic> captured,
  Map<String, dynamic> readback,
) {
  final out = <String>[];
  for (final k in const ['on', 'bri']) {
    if ('${captured[k]}' != '${readback[k]}') {
      out.add('$k: ${captured[k]} → ${readback[k]}');
    }
  }
  final after = {for (final s in _segs(readback)) s['id']: s};
  for (final s in _segs(captured)) {
    final r = after[s['id']];
    if (r == null) {
      out.add('seg ${s['id']}: missing after restore');
      continue;
    }
    for (final f in kTouchedSegFields) {
      if (!s.containsKey(f)) continue;
      if ('${s[f]}' != '${r[f]}') {
        out.add('seg ${s['id']}.$f: ${s[f]} → ${r[f]}');
      }
    }
  }
  return out;
}
