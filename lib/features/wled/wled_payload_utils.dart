import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/utils/color_naming.dart';
import 'package:nexgen_command/utils/rgbw_validation.dart';

/// Guarantees a color array is a 4-channel `[R, G, B, W]` list with W explicitly
/// set. Used by sports team and holiday color paths to prevent WLED's W-channel
/// auto-calculation from washing dark branded colors (e.g. Chiefs red
/// `[227, 24, 55]`) into pink on RGBW strips.
///
/// - 4-channel input: clamped to 0–255 and returned as-is.
/// - 3-channel input: clamped and W=0 is appended (no auto-white extraction).
/// - Anything else: returns `[0, 0, 0, 0]` to fail safe.
///
/// This is the canonical wrapper any code path that produces a `col` entry from
/// a team or holiday brand color should funnel through.
List<int> safeRGBW(List<int> color) {
  if (color.length == 4) {
    return [
      color[0].clamp(0, 255),
      color[1].clamp(0, 255),
      color[2].clamp(0, 255),
      color[3].clamp(0, 255),
    ];
  }
  if (color.length == 3) {
    return [
      color[0].clamp(0, 255),
      color[1].clamp(0, 255),
      color[2].clamp(0, 255),
      0, // Explicit W:0 — prevents WLED auto white-channel bleed
    ];
  }
  return [0, 0, 0, 0];
}

/// Rewrites a WLED payload's `seg` array so it targets only [channelIds].
///
/// If [channelIds] is empty, or the payload has no `seg` key, the payload is
/// returned unchanged (safe fallback). Otherwise the first segment object is
/// used as a template and replicated once per channel ID.
///
/// When [channels] is provided, each segment entry gets `start`/`stop` values
/// from the corresponding hardware bus, so WLED targets the correct LED range.
///
/// Each expanded seg is emitted with `'on': true` (channel-2-dark fix —
/// matches the semantics of [buildParticipatingSegArray]). Inline dashboard
/// builders put `'on'` at the top level of the payload, not inside the seg
/// map, so without this a channel left in `on:false` on the controller
/// stays dark even after a dashboard apply. Targeting a channel implies it
/// must be lit; we set `'on': true` explicitly per seg.
///
/// This is a pure function with no side effects — safe to call from any
/// provider or widget.
Map<String, dynamic> applyChannelFilter(
  Map<String, dynamic> payload,
  List<int> channelIds, [
  List<DeviceChannel> channels = const [],
]) {
  if (channelIds.isEmpty) return payload;

  final seg = payload['seg'];
  if (seg is! List || seg.isEmpty) return payload;

  // Use the first segment entry as a template.
  final template = Map<String, dynamic>.from(seg.first as Map);
  template.remove('id'); // strip hardcoded ID so each copy gets its own
  template.remove('start');
  template.remove('stop');
  template.remove('on'); // overridden below — channel-2-dark fix forces on:true

  final expandedSegs = channelIds.map((id) {
    final s = <String, dynamic>{'id': id, ...template, 'on': true};
    // Look up bus range — set start/stop so WLED targets the correct LEDs
    for (final ch in channels) {
      if (ch.id == id) {
        s['start'] = ch.start;
        s['stop'] = ch.stop;
        break;
      }
    }
    return s;
  }).toList();

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = expandedSegs;
  debugPrint('🎯 applyChannelFilter: targeting channels $channelIds (${expandedSegs.length} segs)');
  return result;
}

/// Builds the per-channel `seg[]` array for a participation-scoped apply
/// (Neighborhood Sync / Game Day). The SINGLE shared shape used by every
/// sync + game-day apply site — both foreground (`_executePattern`,
/// `_buildWledPayload`) and background (`_buildPatternPayload`,
/// `_buildBasePayload` in Bundle 4). Keep it that way: divergence between
/// sites is what makes audit #4-class bugs happen.
///
/// Contract (locked, validated by hardware probe on 192.168.1.250):
/// - One seg entry per participating channel id.
/// - Each entry sets `'on': true` per segment. Required: a segment left
///   in `on:false` is NOT re-lit by a top-level `on:true` — the receiver
///   silently ignores the off segment. Per-seg `'on': true` is the
///   confirmed fix for the channel-2-dark class of bug.
/// - No `start` / `stop` — WLED retains the install-time ranges set by
///   `wled_config_pusher`. Sending them would risk re-introducing the
///   Item #82 wrong-range stomp.
/// - No `rev` — that's a separate bundle (the slot is reserved here so
///   when rev lands it's added in ONE place, not four).
/// - Non-participating channels are OMITTED, not turned off. A patio
///   left on by the user for their own purposes stays on; the show only
///   touches the channels the user opted in.
/// - Empty `participatingChannelIds` → empty list. Callers MUST treat
///   that as "skip the apply entirely" (do not POST an empty seg array).
///
/// `colorSlots` is passed verbatim — the caller is responsible for the
/// RGBW shape (use [safeRGBW] for team / holiday colors). No deep-copy:
/// `colorSlots` should be treated as immutable by the caller after this
/// call.
List<Map<String, dynamic>> buildParticipatingSegArray({
  required List<int> participatingChannelIds,
  required int effectId,
  required int speed,
  required int intensity,
  required List<List<int>> colorSlots,
}) {
  return [
    for (final ch in participatingChannelIds)
      <String, dynamic>{
        'id': ch,
        'on': true,
        'fx': effectId,
        'sx': speed,
        'ix': intensity,
        'col': colorSlots,
      },
  ];
}

/// Apply-boundary chokepoint that expands a broadcast-intent payload into
/// per-participating-channel seg entries, OR returns the payload unchanged
/// when expansion is inappropriate.
///
/// Bundle 3 wired participation into two specific apply paths
/// (`_executePattern` and `_buildWledPayload`). The wider audit (#4) found
/// 20+ inline payload builders across the codebase using the legacy
/// single-seg shape, each with the same channel-2-dark / patio-force-light
/// bugs latent. This function is the single chokepoint approach: every
/// `applyJson` flows through here (it's called by both `WledService` and
/// `CloudRelayRepository` alongside [normalizeWledPayload]), regardless of
/// which inline builder produced the payload OR whether the payload was
/// replayed from a stored blob (`savedDesignPayload`, `wledPayload` fields,
/// etc.).
///
/// Discriminator (ordered — each rule short-circuits):
///
///   1. `participating == null`        → pass through. Legacy behavior or
///                                       "no preference set" — never expand
///                                       without an explicit channel list.
///   2. `participating.isEmpty`        → pass through. Caller's "explicit
///                                       none" — they must skip-apply at
///                                       their layer; this function never
///                                       emits an empty seg array.
///   3. No 'seg' key, or 'seg' not a   → pass through. Top-level-only
///      List, or empty seg list           payloads ({'on':false}, {'bri':N},
///                                       {'ps':N}, {'rb':true}, {'udpn':…})
///                                       are not pattern broadcasts.
///   4. `seg.length > 1`               → pass through. Caller built a
///                                       multi-seg payload intentionally —
///                                       either Bundle 3's
///                                       [buildParticipatingSegArray]
///                                       output (already per-channel) OR a
///                                       pixel-range animation (rising
///                                       tide, pulse burst —
///                                       lumina_custom_effects.dart) with
///                                       explicit start/stop. Either way,
///                                       don't second-guess.
///   5. `seg.first` has an 'id' key    → pass through. Explicitly-targeted
///                                       single-seg apply (e.g. voice
///                                       provider's {id:0, fx:0}). The
///                                       caller meant THAT specific seg.
///   6. `seg.first` has NO 'fx' key    → pass through. Partial-update
///                                       payload — slider tweak emitting
///                                       just {sx, ix, rev} or {grp, spc}.
///                                       These apply to seg 0 implicitly,
///                                       matching pre-Bundle-3 behavior;
///                                       expanding could silently broadcast
///                                       a slider drag to non-participating
///                                       channels.
///   7. otherwise (single-seg, no id,  → EXPAND. Replicate the seg entry
///      has fx → broadcast intent)       once per participating channel id,
///                                       each with `id: ch` and `on: true`
///                                       added. Template fields (fx, sx,
///                                       ix, col, pal, anything else) are
///                                       preserved verbatim.
///
/// PURE FUNCTION: no I/O, no SharedPreferences read inside. The caller
/// passes [participating] in; 3b.2 reads `loadLocalParticipatingChannels()`
/// once at the call site (cached in memory) and forwards it here.
///
/// IDEMPOTENT: expansion produces multi-seg-with-ids, which rule 4 catches
/// on any subsequent pass. Safe to call multiple times in any order.
///
/// Does NOT mutate the input payload — always returns a new map when
/// expansion happens. Pass-through returns the same reference (no copy).
Map<String, dynamic> expandForParticipation(
  Map<String, dynamic> payload,
  List<int>? participating,
) {
  // Rule 1: null participating → legacy/no pref.
  if (participating == null) return payload;
  // Rule 2: explicit empty → caller's "no channels" — skip-apply belongs
  // upstream; don't emit an empty seg array here.
  if (participating.isEmpty) return payload;

  final seg = payload['seg'];
  // Rule 3: no seg, non-list, or empty list → top-level-only payload.
  if (seg is! List || seg.isEmpty) return payload;
  // Rule 4: already multi-seg → caller built it that way intentionally.
  if (seg.length > 1) return payload;

  final first = seg.first;
  if (first is! Map) return payload;
  // Rule 5: explicit id on the single seg → targeted apply.
  if (first.containsKey('id')) return payload;
  // Rule 6: no fx → partial update (slider tweak), not a broadcast.
  if (!first.containsKey('fx')) return payload;

  // Rule 7: broadcast intent — expand.
  final template = Map<String, dynamic>.from(first);
  final expanded = <Map<String, dynamic>>[
    for (final ch in participating)
      <String, dynamic>{
        ...template,
        'id': ch,
        'on': true,
      },
  ];
  final result = Map<String, dynamic>.from(payload);
  result['seg'] = expanded;
  return result;
}

/// Pre-applyJson defensive filter for **externally-sourced multi-seg-WITH-ids**
/// payloads — surfaced by the Phase 2 Stop-Sync teardown audit.
///
/// **Why this exists separately from [expandForParticipation]:**
/// The chokepoint's Rule 4 passes multi-seg payloads through unchanged
/// ("caller built it that way intentionally"). That protection is
/// load-bearing for legitimate multi-seg broadcasters (Bundle 3's
/// [buildParticipatingSegArray] output, pixel-range animations in
/// `lumina_custom_effects.dart`) — those callers pre-filter their seg
/// arrays to participating ids themselves, so the chokepoint must not
/// second-guess them.
///
/// The Stop-Sync teardown's scene tier breaks that assumption: it feeds
/// the captured `getState()` snapshot to `applyJson`, and `getState()`
/// returns the FULL device state — every seg the controller has —
/// regardless of which channels the local user participates in. Rule 4
/// then passes that multi-seg payload through, and the controller's
/// non-participating segs get touched on Stop Sync. The hardware T5
/// equivalent of this bug (controller .250 / participation=[0] / staged
/// blue ch1 → restore force-lit ch1) is the merge-gate failure that
/// blocks shipping without this filter.
///
/// **Discriminator** (mirrors the chokepoint where it makes sense; the
/// shapes that pass through here also pass through the chokepoint, so
/// applying this filter is always safe as a pre-step):
///
///   • [participating] is null or empty → pass-through. Matches
///     chokepoint Rules 1 and 2 — "no preference / explicit none" is
///     filtered upstream (the engine skips-apply on empty), not here.
///   • Payload has no 'seg' or non-list seg → pass-through (top-level-
///     only payload like `{'on': false}`, `{'bri': N}`).
///   • Single-seg payload → pass-through. Chokepoint Rules 5 (id), 6
///     (no fx), and 7 (broadcast intent) handle single-seg shapes
///     correctly on their own — including the participation-aware
///     expand of Rule 7.
///   • Multi-seg where ANY entry LACKS an explicit id → pass-through.
///     That's not the bug-shape signature (externally-sourced
///     getState() output always has ids per seg); this is most likely a
///     pixel-range animation or other intentional multi-seg the caller
///     pre-filtered.
///   • Multi-seg where EVERY entry has an explicit id → **FILTER**.
///     Keep only those segs whose id is in [participating].
///
/// If filtering reduces the seg array to empty, the result rewrites to
/// `{'on': false}` (master power off): zero participating segs matched
/// the captured scene, so the safe behavior is to fall through to the
/// off-tier semantically rather than POST a seg-less payload (which
/// would leave the controller in whatever state it was in — the OLD
/// "frozen on sync state" bug).
///
/// Pure function — no side effects, no input mutation. Does not read
/// the participation cache; the caller (e.g. teardown executor) passes
/// `participating` in to match what `WledService.applyJson` reads
/// inside the chokepoint.
Map<String, dynamic> filterMultiSegByParticipation(
  Map<String, dynamic> payload,
  List<int>? participating,
) {
  if (participating == null || participating.isEmpty) return payload;

  final seg = payload['seg'];
  if (seg is! List || seg.length < 2) return payload;

  // Bug-shape signature: every entry must have an explicit id. If any
  // lacks one, this isn't the externally-sourced getState() shape —
  // leave for the chokepoint to handle.
  for (final entry in seg) {
    if (entry is! Map || !entry.containsKey('id')) return payload;
  }

  final allowed = participating.toSet();
  final filtered = <Map<String, dynamic>>[];
  for (final entry in seg) {
    final id = (entry as Map)['id'];
    if (id is int && allowed.contains(id)) {
      filtered.add(Map<String, dynamic>.from(entry));
    }
  }

  if (filtered.isEmpty) {
    // No participating segs matched. Don't POST a seg-less payload —
    // that would silently leave the controller in its prior state
    // (the sync state, in the teardown case) which is the original
    // freeze bug. Fall through to off semantically.
    return const <String, dynamic>{'on': false};
  }

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = filtered;
  return result;
}

/// Normalizes a WLED JSON API payload to prevent segment state carry-over.
///
/// WLED only updates fields explicitly included in a POST /json/state payload.
/// When switching patterns, omitting `grp`, `spc`, and `of` causes the previous
/// pattern's grouping/spacing/offset to persist, producing visual glitches.
///
/// This function inspects each segment object in the `seg` array:
/// - If the segment contains `fx` (effect ID), it is a full pattern application.
///   Missing `grp`, `spc`, and `of` fields are set to their WLED defaults (1, 0, 0).
/// - If the segment does NOT contain `fx`, it is a partial adjustment (e.g., a
///   slider changing speed/intensity) and is left untouched.
///
/// Additionally normalizes legacy key names: `gp` -> `grp`, `sp` -> `spc`.
///
/// The input map may be `const` (immutable), so this always returns a new map.
Map<String, dynamic> normalizeWledPayload(Map<String, dynamic> payload) {
  final seg = payload['seg'];
  if (seg is! List || seg.isEmpty) {
    return Map<String, dynamic>.from(payload);
  }

  final normalizedSegs = <Map<String, dynamic>>[];

  for (final raw in seg) {
    if (raw is! Map) {
      normalizedSegs.add(Map<String, dynamic>.from(raw as Map));
      continue;
    }

    final s = Map<String, dynamic>.from(raw);

    // Legacy key normalization (always, regardless of fx presence)
    if (s.containsKey('gp') && !s.containsKey('grp')) {
      s['grp'] = s.remove('gp');
    }
    if (s.containsKey('sp') && !s.containsKey('spc')) {
      s['spc'] = s.remove('sp');
    }

    // Default injection: only for full pattern applications (has fx)
    if (s.containsKey('fx')) {
      s.putIfAbsent('grp', () => 1);
      s.putIfAbsent('spc', () => 0);
      s.putIfAbsent('of', () => 0);
    }

    // Palette guard (single chokepoint for the pal:5 strobing/blending bug).
    //
    // A palette-driven / motion-sweep effect — generatesOwnColors / usesPalette
    // (Rainbow, Colorwaves, Aurora, Plasma, Fire, the Noise family) — must NOT
    // run with pal:5 ("Colors Only"): that strips the sweep and collapses it
    // into a strobe/blend through the 1–3 col[] slots. Many apply paths (and
    // older saved/scheduled/Game-Day payloads) baked in pal:5 unconditionally,
    // so this corrects them centrally on every applyJson AND on replay of a
    // stored blob — no caller needs to remember the rule.
    //
    // Rewrite to pal:4 ("Color Gradient") — the effect then sweeps a smooth
    // gradient built FROM the user's col[] colors (honoring them), rather than
    // its own built-in palette (pal:0 would make Rainbow ignore user colors).
    //
    // Surgical by design — only the broken case is rewritten:
    //   - col-based effects (pal:5 is load-bearing) → untouched
    //   - deliberate non-5 palette choices (holiday cards' pal:3/6/12) → untouched
    //   - pal absent → untouched (caller/WLED default preserved)
    // The pal index policy itself lives in WledEffectsCatalog.paletteForEffect.
    final fx = s['fx'];
    if (fx is int && s['pal'] == 5 && WledEffectsCatalog.overridesUserColors(fx)) {
      s['pal'] = 4; // "Color Gradient" — sweep a gradient of the user's colors
    }

    // RGBW validation: ensure all color arrays have 4 channels [R, G, B, W]
    final col = s['col'];
    if (col is List && col.isNotEmpty) {
      s['col'] = validateRgbwList(col, source: 'normalizeWledPayload');

      // Pad col UP to 3 slots so the device's seg.col is overwritten
      // explicitly on every apply. WLED's seg.col is a fixed 3-slot
      // array; partial-col payloads (1 or 2 slots) leave the unspecified
      // slots holding the PRIOR pattern's values. The next /json/state
      // poll then returns new-slot-0 + stale-slots-1/2, and the
      // dashboard renders all three as a "blend" — display-only bug,
      // but visible across schedule / autopilot / Game Day / Sync /
      // manual apply / scene paths because they all converge here.
      //
      // Pad UP only (do not trim oversized col). The unused-slot value
      // [0, 0, 0, 0] matches the post-validateRgbwList 4-channel shape
      // so the per-slot validator pass above stays consistent.
      //
      // Leave-alone guarantees this pad MUST preserve:
      //   - payload with NO col key → untouched (no synthesis — would
      //     blank lights on slider tweaks / current-color applies)
      //   - empty col []            → untouched (no color info)
      //   - oversized col (>3)      → untouched (pad up only)
      //   - non-fx partial updates  → untouched (this branch only
      //     runs when col is present; the fx-default block above
      //     handles the "has fx but no col" case separately)
      final padded = List<List<int>>.from(s['col'] as List);
      while (padded.length < 3) {
        padded.add(const [0, 0, 0, 0]);
      }
      s['col'] = padded;
    }

    // Normalize + validate per-pixel 'i' arrays. Canonicalizes the legacy
    // flat form ([idx,r,g,b,…]) to nested ([idx,[r,g,b,w],…]) so nothing
    // unvalidated reaches the wire (Design Studio Slice 0).
    final iArray = s['i'];
    if (iArray is List) {
      s['i'] = normalizeIArray(iArray, source: 'normalizeWledPayload');
    }

    normalizedSegs.add(s);
  }

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = normalizedSegs;
  return result;
}

/// Composes a Now Playing label by appending color names to a vanilla
/// effect-named label hint (Fix 3 / Bug A).
///
/// The label sources that feed [applyPayloadWithLabel] (schedule
/// `actionLabel`, autopilot `patternName`, scene `name`, geofence
/// `actionName`, Game Day `'$team Game Day'`) were authored at
/// create-time when only the effect-type token was captured. The color
/// component lives in the payload itself (`seg[0].col`). This composer
/// closes that gap at the apply chokepoint so legacy data composes
/// correctly without a Firestore migration.
///
/// Heuristic (audit-locked, see docs/project_preview_followups_2026_05_22.md):
///
///   1. [labelHint] == null                     → returns null
///      (TRANSIENT semantics preserved — flash / restore paths don't
///      steal the label.)
///   2. [effectId] not in [WledEffectsCatalog]  → returns [labelHint]
///   3. [labelHint] != effect.name (case-fold)  → returns [labelHint]
///      (caller has a CUSTOM label like "Royals Game Day" — the
///      Game-Day-Red mislabel guard.)
///   4. effect.colorBehavior is
///      [ColorBehavior.generatesOwnColors] or
///      [ColorBehavior.usesPalette]             → returns [labelHint]
///      (effect ignores the user color slots — appending would
///      mislead. The Rainbow-Red guard.)
///   5. No colors resolve to a named bucket     → returns [labelHint]
///      (pad/unknown/custom dropped — assembled list empty.)
///   6. Else                                    → "labelHint Color[/Color][/Color]"
///      Title-cased color names, deduped, joined with '/'.
///
/// PURE function — no Riverpod, no I/O — testable in isolation
/// alongside [normalizeWledPayload] and [expandForParticipation].
String? composeEffectLabel({
  required String? labelHint,
  required int effectId,
  required List<List<int>> colors,
}) {
  if (labelHint == null) return null;

  final effect = WledEffectsCatalog.getById(effectId);
  if (effect == null) return labelHint;

  if (labelHint.toLowerCase() != effect.name.toLowerCase()) {
    return labelHint;
  }

  if (effect.colorBehavior == ColorBehavior.generatesOwnColors ||
      effect.colorBehavior == ColorBehavior.usesPalette) {
    return labelHint;
  }

  // Resolve each color to a name, drop pads/unknowns, dedupe while
  // preserving insertion order (so "Red, Green, Blue" stays in caller-
  // intended order, not alphabetical).
  final seen = <String>{};
  final names = <String>[];
  for (final color in colors) {
    final name = colorRgbToName(color);
    if (name == 'unknown' || name == 'custom') continue;
    if (seen.add(name)) names.add(name);
  }

  if (names.isEmpty) return labelHint;

  final titleCased = names.map((n) => '${n[0].toUpperCase()}${n.substring(1)}');
  return '$labelHint ${titleCased.join('/')}';
}

