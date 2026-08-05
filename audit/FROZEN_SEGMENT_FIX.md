# FROZEN SEGMENT — implementation report

**Date:** 2026-08-05 · **Rig:** 192.168.1.150 (WLED 0.15.1, vid 2507300)
**Predecessor:** `audit/FROZEN_SEGMENT.md` (the blast-radius audit this answers)
**Status:** IMPLEMENTED. Both fixes ship together. No branch created. `firestore.rules` untouched.

---

## 1. WHERE THE FIXES LANDED — one shared function, not two repositories

The brief asked for the chokepoint in both repositories *or* a shared payload builder, and to say
which. **There is a shared builder, and it is better than patching both repos:**
`normalizeWledPayload` in `wled_payload_utils.dart` is already called by

- `WledService.applyJson` (`:473`)
- `CloudRelayRepository.applyJson` (`:372`)
- `WledService.savePreset` and `CloudRelayRepository.savePreset`

So **one edit covers both transports, all ~66 `applyJson` call sites, and both psave paths** — and
any call site added later inherits it. No per-repository duplication was needed for fix 1.

### FIX 1 — clear the freeze on every segment-level write

[wled_payload_utils.dart](../lib/features/wled/wled_payload_utils.dart), inside
`normalizeWledPayload`'s per-segment loop:

```dart
if (!s.containsKey('i')) {
  s['frz'] = false;
}
```

A segment-level write means "render this", so it clears the freeze. The one exception is a
per-pixel write, which sets the pixel buffer directly and re-freezes by design — detected by the
`i` key.

**Safe unconditionally: nothing in `lib/` ever writes `frz`**, so there is no deliberate freeze
anywhere for this to override. (Grepped `'frz'`/`"frz"` across `lib/` — zero hits before this
change.)

### FIX 2 — a psave must never capture `frz:true`

New pure helper `ensurePsaveClearsFreeze(state, participating)` in the same file, called by
`savePreset` in **both** repositories.

Fix 1 already clears `frz` on any seg entry a caller supplied. The gap is the **seg-LESS** psave:
`{'on': true, 'bri': N, 'ib': true}` — which is exactly the shape of ON-presets **1/3/4/5, the
presets schedules fire**. With no `seg` key, WLED captures the live segment state including its
freeze. The helper synthesizes a minimal entry per participating segment:

```dart
{'id': id, 'frz': false}
```

**Only the freeze flag.** Colour, effect and everything else stay live and are captured normally —
this must not become a colour write, and a test asserts the key set is exactly `{id, frz}`.

**Chosen over "unfreeze in a separate POST before psave"** because it is atomic: one write, no
window in which the strip is unfrozen but unsaved, and no extra flash-adjacent round trip on a
controller with known post-commit stall behaviour.

---

## 2. A DESIGN PROBLEM THE SUITE CAUGHT — worth recording

My first version called `getCachedParticipatingChannels()` directly in `savePreset`. That reaches
**SharedPreferences**, which throws without a Flutter binding — and **`savePreset` previously had no
I/O of its own**. It broke **8 tests** across `sunrise_off_service_test` and
`schedule_sync_off_lan_test` with `Binding has not yet been initialized`.

That was a real defect, not a test artifact: I had made a preset save depend on prefs availability.
A freeze-clearing nicety must never be the reason a preset fails to save. Both repositories now
wrap the read:

```dart
Future<List<int>?> _participatingChannelsOrNull() async {
  try { return await getCachedParticipatingChannels(); } catch (_) { return null; }
}
```

`null` → `ensurePsaveClearsFreeze` falls back to segment 0.

**Documented residual:** a multi-segment controller whose participation preference is unavailable
falls back to segment 0 only. Segment 0 is what a per-pixel paint targets by default, so this
covers the realistic case, but it is not total. Recorded rather than hidden.

---

## 3. ONE TEST CONTRACT DELIBERATELY CHANGED

`wled_service_save_preset_test.dart` asserted a seg-less psave *"passes through unchanged"*
(`expect(captured.containsKey('seg'), isFalse)`). Fix 2 must change exactly that.

This is **not** a stale test being discarded — its original intent (*savePreset must not fabricate
segment content*) is still correct and is still asserted: the updated test pins that the injected
entry's key set is exactly `{id, frz}`, so no colour or effect is synthesized. The comment records
why the contract moved, so nobody "restores" it later.

---

## 4. HARDWARE VERIFICATION — 192.168.1.150

Each step replays the payload the **fixed** code now emits.

| # | Step | Before | After |
|---|---|---|---|
| **1** | Freeze via per-pixel `i` write | `seg0 frz=False` | **`seg0 frz=True`** ✅ |
| **2** | Segment colour write **as fixed code emits it** (`frz:false` injected) | `seg0 frz=True` | **`frz=False`, `col0=[255,0,0,0]`** ✅ renders |
| **3** | Per-pixel still works: base(`frz:false`) → per-pixel | `frz=False` | **`frz=True`, base `[10,10,12,0]`** ✅ paint lands and re-freezes by design |
| **4** | psave **while frozen** with the fixed payload | live `seg0 frz=True` | **stored preset 62 `seg.frz = [False, False]`** ✅ (pre-fix this captured `[True, False]`) |
| **5** | Re-freeze, then load preset 62 | `seg0 frz=True` | **`frz=False` on both** ✅ preset renders instead of re-freezing |

**Step 3 was verified, not assumed** — the brief specifically asked for the ordering to be checked.
`base(frz:false) → per-pixel` leaves the segment frozen *and* painted, which is the correct end
state: the paint owns the buffer, and the next segment-level write will clear it.

**Step 6 (undo/erase in the manual editor) — NOT verified end-to-end.** That needs the rebuilt app
deployed to the handset, which this session could not do. What *is* verified is the wire equivalent:
step 2 is byte-for-byte the payload `applyBaseAndSpans` now emits for an undo/erase, and it clears
the freeze and renders. **P1-50 should stay open until someone confirms it in the app**, and that is
the one claim in this report I am not making.

### Interruption during verification, recorded

Steps 3-5 first attempt returned HTTP `000` on every POST. Diagnosis: the **gateway (192.168.1.1)
was also unreachable**, so it was my machine's Wi-Fi, not the controller. On recovery the rig read
back exactly the step-2 state, confirming nothing from the failed attempt had landed and no
half-applied write needed unwinding. Steps re-run clean.

### Rig restored

`on=True bri=200`, 2 segments (`seg0` 0-128, `seg1` 128-290), both `fx:52`,
`col0=[227,24,55,0]`, both `frz:false` — verified equal to the pre-test capture. Scratch preset 62
deleted; preset set back to `1,2,3,4,5,10,26,27,28,29,30,41`.

---

## 5. TEST + ANALYZE

| Check | Result |
|---|---|
| New suite `frozen_segment_fix_test.dart` | **15/15 pass** |
| Full suite | **1893 passed · 3 skipped · 1 failed** |
| Failing test | `cloud_ai_processor_normalize_test.dart` — the known pre-existing stale P1-8 assertion. **No new failures** |
| Arithmetic | 1878 (the +62 baseline) **+ 15 new = 1893** ✅ — no test lost or silently skipped |
| `flutter analyze`, all 5 changed files | **0 errors, 0 warnings** (28 info: pre-existing `annotate_overrides` / deprecations) |

The 15 new tests pin both fixes, including the cases that would silently undo them: a per-pixel
payload must keep its freeze; the synthesized psave entry must carry only `{id, frz}`; a
seg-bearing state must not be fanned out; `ensurePsaveClearsFreeze` must not mutate the caller's map.

---

## 6. WHAT THIS CLOSES AND WHAT IT DOES NOT

**Closes:**
- The chokepoint — every segment-level write on both transports now renders.
- The durable half — no psave can bake `frz:true` into flash.

**Does NOT close:**
- **P1-50 stays OPEN** until undo/erase are confirmed in the running app (§4, step 6).
- The seg-0-only fallback when participation is unavailable (§2).
- Design Studio per-pixel release readiness — this removes the two blockers named in
  `audit/FROZEN_SEGMENT.md`, but P1-49 (conflict dialog with no selectable option) is untouched and
  still makes the AI entry point unusable.

**Fleet impact:** zero accounts currently hold `pixelMap` data, so no customer is in the frozen
state today. This ships ahead of the exposure rather than in response to it.

---

## FILES CHANGED

```
lib/features/wled/wled_payload_utils.dart          FIX 1 in normalizeWledPayload + ensurePsaveClearsFreeze
lib/features/wled/wled_service.dart                savePreset → ensurePsaveClearsFreeze; safe participation read
lib/features/wled/cloud_relay_repository.dart      same, for transport parity
test/features/wled/frozen_segment_fix_test.dart    NEW — 15 cases
test/features/wled/wled_service_save_preset_test.dart   contract update (§3)
```
