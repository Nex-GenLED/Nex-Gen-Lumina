import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
// buildChannelPowerPayload moved to a pure-Dart file (bench/ CLI imports it
// without dart:ui); re-exported so existing importers are unaffected.
export 'package:nexgen_command/features/wled/channel_power_payload.dart';
// #88 design-spacing defaults — pure Dart for the same reason, re-exported
// here so nothing importing this file needs a second import.
import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
export 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
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

/// Rewrites a WLED payload's `seg` array into the **full partition** over the
/// device's channels: the targeted ones carry the design, every other one
/// carries `{id, on:false}` and nothing else.
///
/// If [channelIds] is empty, or the payload has no `seg` key, the payload is
/// returned unchanged (safe fallback). Otherwise the first segment object is
/// used as a template for the targeted channels.
///
/// THE CONTRACT (#67's answer, brought to the interactive path — #89):
///
///  1. **"Channel unused" is `{id: N, on: false}` and NOTHING else.** Never a
///     dropped seg entry, never a zero-length `[0,0)` bound. A design that
///     leaves a channel out is stating "dark for this design", not "this
///     channel does not exist" — the segment survives with its look intact,
///     exactly as the server-side `buildFullPartitionSegArray` /
///     `partitionBroadcastPayload` already do for Game Day and Sync.
///  2. **An apply NEVER writes `start`/`stop`.** Bounds are provisioning's,
///     sourced from the hardware buses (#76: state that isn't yours to state
///     must not be stated). This function used to stamp them from
///     [channels] — that is the Item-#82 wrong-range stomp with a friendlier
///     face, and a stale channel map could re-bound a physically-resized
///     channel on an ordinary pattern tap.
///  3. **Segment ids come from the device channel list, never a literal.**
///     [channels] is now the channel CENSUS rather than a bounds source.
///
/// [channelIds] is unioned into the census rather than intersected with it:
/// the caller's target must always be represented even when [channels] is
/// cold, stale or partial. (Same call `buildChannelPowerPayload` makes for
/// the same reason — the server can trust its device list, a widget cannot.)
/// With no [channels] at all the census degrades to [channelIds], which is
/// the pre-partition behaviour: nothing to exclude, so nothing is excluded.
///
/// Each targeted seg is emitted with `'on': true` (channel-2-dark fix —
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
  template.remove('start'); // bounds are provisioning's — rule 2
  template.remove('stop');
  template.remove('on'); // overridden below — channel-2-dark fix forces on:true

  final targeted = channelIds.toSet();
  final census = <int>{...channels.map((c) => c.id), ...channelIds}.toList()
    ..sort();

  final expandedSegs = <Map<String, dynamic>>[
    for (final id in census)
      if (targeted.contains(id))
        <String, dynamic>{'id': id, ...template, 'on': true}
      else
        // Rule 1 — excluded, not deleted. No look fields, no bounds.
        <String, dynamic>{'id': id, 'on': false},
  ];

  final result = Map<String, dynamic>.from(payload);
  result['seg'] = expandedSegs;
  debugPrint('🎯 applyChannelFilter: targeting channels $channelIds '
      '(${expandedSegs.length} segs over census $census)');
  return result;
}

/// The first `seg` entry that actually carries a DESIGN (an `fx` or a `col`),
/// falling back to the first map entry and finally to null.
///
/// Since [applyChannelFilter] emits the full partition, `seg[0]` is no longer
/// guaranteed to be a design seg — on a design scoped to channel 1 of a
/// two-channel device, `seg[0]` is the exclusion `{id: 0, on: false}`. Every
/// reader that mirrors "what did we just send" into the dashboard preview
/// (`applyPayloadWithLabel`, `applySavedDesign`'s wire-fx lookup) must read the
/// design seg, not the zeroth one, or an excluded channel 0 silently blanks the
/// preview it used to drive.
Map<String, dynamic>? firstDesignSeg(dynamic seg) {
  if (seg is! List || seg.isEmpty) return null;
  for (final entry in seg) {
    if (entry is Map && (entry.containsKey('fx') || entry.containsKey('col'))) {
      return Map<String, dynamic>.from(entry);
    }
  }
  final first = seg.first;
  return first is Map ? Map<String, dynamic>.from(first) : null;
}

// buildChannelPowerPayload (P1-43) lives in channel_power_payload.dart (pure
// Dart) and is re-exported above.

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
/// FROZEN-SEGMENT FIX 2 — guarantee a `psave` cannot capture `frz:true`.
///
/// `psave` saves the state included in the same command merged over the CURRENT
/// live state. Bench-proven (audit/FROZEN_SEGMENT.md): with a segment frozen,
/// `{"psave":N}` stored `seg.frz = [true, ...]`; loading that preset re-froze
/// the segment, so it could not render its own stored colours — a preset that
/// loads successfully and lights nothing.
///
/// This is the DURABLE half of the defect. A live freeze clears on the next
/// segment write or a reboot; a poisoned preset re-freezes on every load until
/// it is re-saved. Reachable in production because schedule sync ALWAYS psaves
/// pattern presets from live state.
///
/// [normalizeWledPayload] already clears `frz` on any seg entry the caller
/// supplied. This covers the seg-LESS case — the ON-preset states
/// (`{'on': true, 'bri': N, 'ib': true}`, presets 1/3/4/5, the ones schedules
/// fire) carry no `seg`, so WLED would capture the live segment state including
/// its freeze. A minimal `{'id': n, 'frz': false}` entry touches ONLY the
/// freeze flag; colour, effect and everything else stay live and are captured
/// normally.
///
/// Atomic by design — one write, rather than an unfreeze POST followed by a
/// psave, which would leave a window where the strip is unfrozen but unsaved
/// and add a round trip on a controller with known post-commit stall behaviour.
///
/// [participating] is the cached participating-channel list; `null` means
/// legacy/no preference, in which case this falls back to segment 0 — the
/// segment a per-pixel paint targets by default. Residual: a multi-segment
/// controller with no participation preference could still capture a freeze on
/// a segment that cannot be enumerated here.
Map<String, dynamic> ensurePsaveClearsFreeze(
  Map<String, dynamic> state,
  List<int>? participating,
) {
  final seg = state['seg'];
  // Caller supplied segments → normalizeWledPayload already set frz:false.
  if (seg is List && seg.isNotEmpty) return state;

  final ids = (participating != null && participating.isNotEmpty)
      ? participating
      : const <int>[0];

  final out = Map<String, dynamic>.from(state);
  out['seg'] = [
    for (final id in ids) <String, dynamic>{'id': id, 'frz': false},
  ];
  return out;
}

/// The NGL color-gamma standard, written to `cfg.light.gc`.
///
/// Matches the WLED firmware default that renders saturated colors correctly
/// on the Lumina SK6812/WS2814 RGBW strip: brightness gamma OFF (`bri:1`),
/// color gamma ON (`col:2.8`), exponent 2.8 (`val:2.8`). WLED stores gamma
/// here — NOT under `hw.led`. A `2.8`/`1`/`2.8` triple is what makes orange
/// render vivid instead of washed amber (gamma darkens the green midtone).
///
/// Lives HERE, not in wled_config_pusher, purely for the import graph:
/// [normalizeWledCfgPayload] needs it, and every cfg write boundary must reach
/// that function. wled_config_pusher imports wled_service imports this file, so
/// defining it in the pusher and importing it back would close a cycle. This is
/// still the ONE definition — the pusher imports it from here.
const Map<String, dynamic> kNglLightGammaConfig = <String, dynamic>{
  'bri': 1,
  'col': 2.8,
  'val': 2.8,
};

/// Asserts [kNglLightGammaConfig] at `light.gc` on EVERY outbound `/json/cfg`
/// payload. The cfg-side twin of [normalizeWledPayload] — same role, same
/// reason: a firmware defect that must be neutralised at the write boundary
/// rather than at each call site.
///
/// **The firmware defect** (WLED 0.15.1, bench-proven 4× — audit/GAMMA_BUG.md):
/// a `POST /json/cfg` whose body omits `light.gc` resets `gammaCorrectCol` and
/// `gammaCorrectBri` to false and `serializeConfig()` persists that to
/// `cfg.json` on LittleFS, so it survives reboot. `gc.val` is preserved by a
/// separate code path — that `col`-resets-while-`val`-survives asymmetry is the
/// fingerprint. Every unrelated cfg key deep-merges correctly; only `light.gc`
/// is recomputed from an absent object. Nesting a partial `light` does NOT
/// protect it: `{"light":{"scale-bri":100}}` wipes gamma just as thoroughly.
///
/// Lumina had EIGHT cfg writers (schedule timers, calendar-lease sweeps, four
/// healer heals, the installer hardware screen, the profile location push) and
/// none carried `light.gc`, so every one of them silently disabled colour
/// gamma. The symptom read as "gamma turns off on some effects and not others"
/// because the GammaWatchdog repaired it within ≤2 min — the apparent
/// effect-correlation was an artifact of the observation window.
///
/// **Why the boundary and not the call sites:** eight sites is eight chances to
/// forget, and the ninth writer added later inherits the bug silently. P1-51 is
/// the standing evidence that per-call-site discipline does not survive contact
/// with this codebase. Injecting here means a cfg payload cannot leave the app
/// without gamma, whatever it is for and whoever wrote it.
///
/// Non-destructive: a caller that already supplies `light.gc` is authoritative
/// and passes through untouched (that is how [pushGammaConfig]'s own payload,
/// and any future user-facing gamma control, keep working). Other `light.*`
/// keys are preserved — the merge is one level deep into `light`, adding only
/// the missing `gc`.
Map<String, dynamic> normalizeWledCfgPayload(Map<String, dynamic> cfg) {
  final light = cfg['light'];
  final existingGc = light is Map ? light['gc'] : null;
  // Caller supplied gamma explicitly — it wins, unconditionally.
  if (existingGc is Map && existingGc.isNotEmpty) {
    return Map<String, dynamic>.from(cfg);
  }

  final out = Map<String, dynamic>.from(cfg);
  final mergedLight = light is Map
      ? Map<String, dynamic>.from(light)
      : <String, dynamic>{};
  mergedLight['gc'] = Map<String, dynamic>.from(kNglLightGammaConfig);
  out['light'] = mergedLight;
  return out;
}

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

    // #88 — DESIGN-SPACING ASSERTION, at the boundary rather than at N call
    // sites. The trigger widens from `fx` to "this seg states a design at all"
    // (fx, col, or a per-pixel `i`), because the census lesson of #88 is that a
    // hand-walked builder list under-counts its own family twice running: #76
    // listed seven and missed four, and the BUG-GD-PICKER-1 sweep missed a
    // third sibling. A builder cannot forget an assertion it does not make.
    //
    // Deliberately NOT widened:
    //   • a partial slider payload ({'sx':200} or {'grp':N}) states neither fx
    //     nor col, so a speed drag can never flatten a spacing the user chose;
    //   • `of` stays on the fx-only trigger — #76 classified offset as
    //     installation geometry and this decision reclassified only grp/spc.
    final statesADesign = s.containsKey('fx') ||
        s.containsKey('col') ||
        s.containsKey('i');
    if (statesADesign) {
      s.putIfAbsent('grp', () => kDesignDefaultGrp);
      s.putIfAbsent('spc', () => kDesignDefaultSpc);
    }
    if (s.containsKey('fx')) {
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

    // ── FROZEN-SEGMENT CHOKEPOINT (audit/FROZEN_SEGMENT.md) ───────────────
    // A per-pixel write sets `seg.frz = true` on WLED 0.15.1 (bench-proven,
    // 192.168.1.150). A FROZEN SEGMENT DOES NOT RUN ITS EFFECT, so every
    // subsequent segment-level colour/effect write is stored, answers 200,
    // reads back correctly from /json/state — and never reaches the LEDs.
    // Nothing in the app ever sent `frz` at all, so the freeze persisted until
    // a preset load or a reboot cleared it.
    //
    // A segment-level write means "render this". Clear the freeze on every one
    // of them. The ONLY exception is a per-pixel write, which sets the pixel
    // buffer directly and re-freezes by design — detected by the `i` key.
    //
    // WHY HERE and not at the call sites: there are ~66 `applyJson` call sites
    // across ~30 files. Both repositories (WledService + CloudRelayRepository)
    // and savePreset funnel through THIS function, so one edit covers every
    // current caller and every future one. Patching applyBaseAndSpans would
    // have fixed Design Studio and left quick presets, the colour picker,
    // celebrations, neighborhood fanout and the healer still swallowed — and
    // P1-51 (P0-7 covering 1 of 3 roofline save surfaces) is this codebase's
    // own evidence that call-site patches do not get remembered.
    //
    // Safe unconditionally: nothing in lib/ ever writes `frz`, so there is no
    // deliberate freeze anywhere for this to override.
    if (!s.containsKey('i')) {
      s['frz'] = false;
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

