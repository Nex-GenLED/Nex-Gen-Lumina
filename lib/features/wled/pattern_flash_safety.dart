// lib/features/wled/pattern_flash_safety.dart
//
// Full-field flashing on an outdoor product — the owner's decision
// (2026-09-29, +110 E1), from the WLED 0.15.1 firmware maths recorded in
// pattern_effect_speeds.dart (`kPhotosensitiveFlashEffectIds`):
//
//   • Strobe (23) and Strobe Rainbow (24) flash once per
//     `(255 - sx) * 20 + 2 frames` ms: sx 240 is 2.9 Hz, 241 is 3.1 Hz. Their
//     speed is CAPPED at 240 — at or under the 3 Hz general flash threshold
//     (WCAG 2.3.1) — whatever a slider, a stored design or a preset says.
//
//   • Strobe Mega (25) bursts at ~11–15 Hz whatever the speed; only
//     intensity < 10 keeps it under the threshold, and the owner chose not to
//     ship it pinned. It is RETIRED: no picker offers it, and a stored
//     reference — a saved design, a favourite, a scene, a schedule's preset,
//     an AI suggestion — DEGRADES to Strobe at the capped speed instead of
//     failing.
//
// WHERE IT IS ENFORCED
//   • normalizeWledPayload (wled_payload_utils.dart): every applyJson and
//     savePreset the app sends, local and relay — so a stored blob is made
//     safe on its way out, with no Firestore migration.
//   • sendChannelTweak: a bare `{sx: N}` adjustment names no effect, so the
//     normalizer cannot see it is a strobe; the sender caps it against the
//     live effect.
//   • EffectSpeedSlider: the slider never offers more than the cap.
//   • WledEffectsCatalog / EffectDatabase: Strobe Mega is left out of every
//     offered list, but still resolves by id so an old reference can be
//     named.
//   • Where a stored design is opened for editing (the palette tuner, the
//     Pattern Editor), the effect is shown as what will actually play.
//
// NOT covered: presets ALREADY stored on a controller (they change only when
// the app re-saves them, e.g. the next schedule sync, which passes through
// the normalizer), and payloads a Cloud Function builds or replays itself.
//
// Pure Dart: the bench CLI and the catalog import it.

/// Strobe and Strobe Rainbow never run faster than this `sx` (≈2.9 Hz).
const int kStrobeSpeedCap = 240;

/// Effects whose `sx` is capped at [kStrobeSpeedCap].
const Set<int> kSpeedCappedFlashEffectIds = {23, 24};

/// Effects no picker offers. A stored reference degrades to
/// [kRetiredEffectFallback].
const Set<int> kRetiredEffectIds = {25};

/// What a retired effect plays instead: Strobe, at the capped speed.
const int kRetiredEffectFallback = 23;

/// Strobe's intensity is its duty cycle (on-time per flash); Strobe Mega's was
/// the number of flashes per burst. A degraded reference gets Strobe's
/// neutral duty cycle rather than a number that meant something else.
const int kRetiredEffectFallbackIntensity = 128;

/// True when [effectId] is never offered.
bool isRetiredEffect(int effectId) => kRetiredEffectIds.contains(effectId);

/// The effect that will actually play for [effectId].
int offeredEffectId(int effectId) =>
    isRetiredEffect(effectId) ? kRetiredEffectFallback : effectId;

/// [speed], capped when [effectId] (after any degrade) is a capped strobe.
int capFlashSpeed(int effectId, int speed) =>
    kSpeedCappedFlashEffectIds.contains(offeredEffectId(effectId)) &&
            speed > kStrobeSpeedCap
        ? kStrobeSpeedCap
        : speed;

/// Makes one WLED segment map safe, in place: a retired effect becomes
/// Strobe, and a capped strobe's `sx` comes down to [kStrobeSpeedCap].
/// A segment that names no effect is left alone. Returns whether anything
/// changed.
bool applyFlashSafetyToSegment(Map<String, dynamic> seg) {
  final fx = seg['fx'];
  if (fx is! num) return false;
  var changed = false;
  var id = fx.toInt();
  if (isRetiredEffect(id)) {
    id = kRetiredEffectFallback;
    seg['fx'] = id;
    seg['ix'] = kRetiredEffectFallbackIntensity;
    changed = true;
  }
  if (kSpeedCappedFlashEffectIds.contains(id)) {
    final sx = seg['sx'];
    if (sx is num && sx > kStrobeSpeedCap) {
      seg['sx'] = kStrobeSpeedCap;
      changed = true;
    }
  }
  return changed;
}

/// A bare adjustment (`{sx: N}`, no `fx`) against the effect that is playing:
/// [fields] with `sx` capped when [liveEffectId] is a capped strobe.
Map<String, dynamic> capAdjustmentForLiveEffect(
  Map<String, dynamic> fields,
  int? liveEffectId,
) {
  final sx = fields['sx'];
  if (fields.containsKey('fx') || liveEffectId == null || sx is! num) {
    return fields;
  }
  final capped = capFlashSpeed(liveEffectId, sx.toInt());
  if (capped == sx) return fields;
  return <String, dynamic>{...fields, 'sx': capped};
}
