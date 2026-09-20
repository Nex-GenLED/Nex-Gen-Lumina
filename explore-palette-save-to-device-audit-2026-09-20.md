# Explore palette → "SAVE TO DEVICE" — Forensic Audit (2026-09-20)

**Scope:** one reported bug — a user customizes an Explore Patterns card's colors, presses "Save to Device", and the customization is then unfindable (not in My Designs, not in the source Explore folder). **Mode:** read-only audit; nothing was fixed.
**Code pin:** `origin/release/store-submission-consolidated` @ **`73ae375`** (fetched at audit start; tip confirmed = signing-input guard on top of `a988854` / 2.5.10+102), in an isolated detached worktree. `main`, the shared checkout, all tags and the in-progress Android upload were not touched.
**Hardware:** bench controller `192.168.1.150` — WLED 0.15.1, vid 2507300, MAC `80f3daae6f04`, 290 RGBW LEDs, seg0 = 0–128, seg1 = 128–290. **Read-only this audit: zero writes of any kind** (see §4 for why that was the right call).
**Firestore:** production project, **read-only** (gcloud ADC, `runQuery` only). Live ruleset **`f7b0658e`**, fetched and found byte-identical (LF-normalised, 120,688 chars) to `firestore.rules` at this tip.

## How to read the evidence labels

| Label | Meaning |
|---|---|
| **HW** | Read directly off the bench controller: `/presets.json`, `/json/state`, `/json/info`, and the rendered frame buffer (WebSocket live-view, all 290 LEDs). |
| **DATA** | Confirmed against real production Firestore documents and the live deployed ruleset. |
| **CODE** | Confirmed by reading code and/or **executing the real production classes** (`EditablePattern`, `presetIdForUserPattern`, `WledService.savePreset` in its built-in simulate mode) in a throwaway harness. Not observed in a running app. |
| **NOT VERIFIED** | Could not be, or deliberately was not, tested. Stated wherever it applies. |

**Standing limitation:** there is no handset/ADB test device, so nothing here was observed inside the running app UI. All "User sees" text is derived from code.

---

## 1. Direct answer

> "Where did it go, and is this a bug or a discoverability gap?"

**It went into a WLED preset slot on the physical controller — and nowhere else. No part of the app can list, load, rename or delete that slot. And in the mode the reporter used, the preset that was written does not actually contain the custom colors.**

So the verdict is **(b) with an (a) inside it**:

- **(b) — real persistence location the user cannot reach.** The button is `SAVE TO DEVICE` in the app bar of the **Edit Pattern** screen ([edit_pattern_screen.dart:178-188](lib/features/wled/edit_pattern_screen.dart#L178-L188)), reached from the Colorway Effect Selector's **tune icon** ("Open in Pattern Editor", [colorway_effect_selector.dart:978-1003](lib/features/wled/colorway_effect_selector.dart#L978-L1003)). It is *not* in the Colorway selector itself. It performs exactly one action: an HTTP `psave` into a controller preset slot in the range 100–200. It makes **no Firestore write at all** — by design, per its own docstring (#85 W2, `9f6008c`, 2026-05-30). My Designs reads `/users/{uid}/designs`; the Explore catalog is a compile-time static tree. Neither can ever show it. The 100–200 preset range has **zero readers** in the app.
- **(a) — and the write itself is hollow in Static mode.** When the pattern's MODE is Static (fx 0), the editor sends a per-pixel `i` payload. A WLED preset cannot store per-pixel data. What the controller captured is **all-black colors, `frz:true`, no `on`, no `bri`** — while the app toasts **"Saved to device: Kansas City Chiefs"**. This is the F6/F7 pattern: success means "the HTTP call returned 200", not "the thing you made was saved". (**HW**, §4.)
- **Not (c).** Persistence *is* intended and *is* invoked (`repo.savePreset` → `psave`). It is not an apply-only button with a misleading label. The label is misleading in a different way: it is accurate about *where*, and silent about the fact that *the app can never get it back*.

**The single strongest piece of evidence** needed no test at all. The bench controller already held the artifact of a real press of this button, from a real handset, written **at most ~7 minutes before this audit first read the controller**:

| | What the strip was rendering (**HW**, live frame) | What slot 160 stored (**HW**, `/presets.json`) |
|---|---|---|
| Name | — | `"Kansas City Chiefs"` |
| Colors | 43 × Chiefs red, 43 × Chiefs gold, **42 × white**, repeating R/G/W on LEDs 0–127 (stock Chiefs is red + gold only — **white is the user's customization**) | `col: [[0,0,0,0],[0,0,0,0],[0,0,0,0]]` on both segments |
| Effect / freeze | `fx:0`, `frz:true` | `fx:0`, **`frz:true`** on both segments |
| Master | `on:true bri:255` | **no `on`, no `bri` key** |

`presetIdForUserPattern('team_nfl_chiefs')` = **160** (executed in Dart; `team_nfl_chiefs` is the NFL Chiefs Explore node id, [sports_library_builder.dart:139-146](lib/features/wled/sports_library_builder.dart#L139-L146)). 160 is inside the range that **only** this button allocates. The harness in §4 reproduces slot, name and payload shape exactly.

---

## 2. Summary table

| # | Component | Status | One-line reason | Evidence |
|---|---|---|---|---|
| S1 | Where "SAVE TO DEVICE" persists | **works-as-coded, unreachable** | One WLED `psave` to slot 100–200. No Firestore write. No app reader of that range. | CODE + HW + DATA |
| S2 | Preset content, **Static mode** | **verified-broken** | Per-pixel `i` payload is not storable in a preset → black, frozen, no on/bri; toast says "Saved". | **HW** + CODE |
| S3 | Preset content, animated modes | **suspected-lossy — needs HW** | Only the first 3 of up to 15 "layers" are sent; no `ib`; no seg `id`; skips the channel filter the live path uses. | CODE (executed) |
| S4 | The heart button (the docstring's "app-side persistence") | **verified-broken** | Writes a doc shape the **live** `favorites` create rule rejects. 0 such docs exist in production. | DATA + CODE |
| S5 | The heart, even if S4 were fixed | **verified-broken (latent)** | Invisible to My Favorites (`orderBy('added_at')`); payload is editor JSON, not a WLED state; shares the stock card's id; ignores the rename. | CODE |
| S6 | Slot allocation (`hash % 101`) | **works-as-coded, unsafe** | Keyed on the *source card's* id: every variation of one card overwrites the last; different cards can silently collide; presets are never deleted. | CODE |
| S7 | Success/failure reporting | **partially sound** | The bool *is* checked (better than F6/F7) — but "success" = HTTP 2xx, no read-back; and demo mode is not gated. | CODE |
| — | Does the button mutate the Explore card? | **No** | Catalog is a static in-memory tree with no Firestore and no auth. | CODE |
| — | Shares the known-lossy `CustomDesign.toWledPayload()` / `apply_saved_design.dart` path? | **No — separate path, separately lossy** | Uses `EditablePattern.toWledPayload()`; never touches `CustomDesign`. | CODE |

---

## 3. Findings

Prefix `S` (Save-to-device) is used to avoid colliding with F1–F7 / M1–M15 from the 2026-09-19 audits.

### S1 — The customization is saved to a place the app cannot read  ← answers the reported symptom

**What the button does, end to end** ([edit_pattern_screen.dart:118-166](lib/features/wled/edit_pattern_screen.dart#L118-L166)):

1. **In-memory:** `_pattern.copyWith(name: <text field>)`. Nothing is stored in any provider; nothing survives leaving the screen.
2. **Firestore:** **none.** The docstring is explicit: *"This intentionally does NOT write to Firestore: the old /users/{uid}/patterns/ write had zero readers and produced a false-success (#85 W2)."* **DATA:** production holds **0** `/users/*/patterns` docs.
3. **Device:** `presetIdForUserPattern(id)` → `repo.savePreset(presetId, state: toWledPayload(totalPixels), presetName)` → `POST /json/state` with `psave` ([wled_service.dart:1519-1615](lib/features/wled/wled_service.dart#L1519-L1615)). This is real device-side persistence (LittleFS `presets.json`), not a live-apply only. The POST also applies the state live as a side effect.
4. **The Explore card:** untouched. `PatternRepository` is *"a static in-memory catalog with no auth and no Firestore"* ([pattern_repository.dart:867-885](lib/features/wled/pattern_repository.dart#L867-L885)).

**Why it is unfindable:**

- **My Designs** = the `my_designs` library node whose children come from `designsStreamProvider` → `/users/{uid}/designs` ([design_service.dart:15](lib/features/design/design_service.dart#L15)). Nothing was written there. **DATA:** of 16 designs / 8 users in production, **0** are named like "Chiefs"/"Kansas".
- **The source Explore folder** is compiled into the app. No user action can add or change a card in it.
- **The preset range 100–200 has no reader.** `loadPreset` has exactly one caller in `lib/` — [schedule_enforcement.dart:209](lib/features/schedule/schedule_enforcement.dart#L209), with schedule-range ids (10–25). `readPresets()` is used only by schedule sync and the controller healer. `fetchPresetNames()` feeds only the Now Playing label, and only when the device reports an active `ps` — after this save the bench reports `ps:-1`. Over the bridge, `fetchPresetNames()` is hard-coded `const {}` ([cloud_relay_repository.dart:612](lib/features/wled/cloud_relay_repository.dart#L612)). No screen lists device presets; no customer-facing screen opens the controller's own web UI.

**User sees:** edits colors → lights change live (that part works) → taps `SAVE TO DEVICE` → grey toast **"Saved to device: Kansas City Chiefs"** → backs out → My Designs: nothing. Explore › NFL › Chiefs: the stock red/gold card, unchanged. Re-opening the editor from that card starts again from stock colors. There is nowhere else to look. The only way to ever see slot 160 is to browse to the controller's IP and open WLED's own preset list — which a customer is never told exists.

### S2 — In Static mode the preset does not contain the customization  (**HW**)

`EditablePattern.toWledPayload()` branches on effect ([editable_pattern_model.dart:123-153](lib/features/wled/editable_pattern_model.dart#L123-L153)): for `effectId == 0` it emits a per-pixel array — `{"on":true,"bri":255,"seg":[{"fx":0,"i":[0,[227,24,55,0],1,[255,184,28,0],2,[255,255,255,0], …]}]}` — 580 entries, 5,459 bytes for 290 LEDs, **no `col` key at all** (CODE, executed). WLED's `psave` serialises *segment state*; per-pixel buffer contents are not part of segment state. So the preset captures whatever `col` the segment already had (black), plus the freeze flag that the `i` write itself sets.

Two guards that exist specifically to stop a `psave` capturing `frz:true` both miss this caller:
- `normalizeWledPayload` sets `frz:false` only `if (!s.containsKey('i'))` ([wled_payload_utils.dart:703-705](lib/features/wled/wled_payload_utils.dart#L703-L705)) — correct for a live per-pixel apply, wrong for a save.
- `ensurePsaveClearsFreeze` returns early whenever the caller supplied segments, on the stated assumption *"normalizeWledPayload already set frz:false"* ([wled_payload_utils.dart:441-442](lib/features/wled/wled_payload_utils.dart#L441-L442)). For an `i`-bearing segment that assumption is false.

**Result (HW, slot 160):** `col` all zero, `fx:0`, `frz:true` on both segments, no `on`/`bri`. Loading it would re-freeze both segments and assert no colors — the "preset that loads successfully and lights nothing" class already documented in `audit/FROZEN_SEGMENT.md`. *Loading slot 160 was NOT exercised in this audit* (it would have destroyed a live reproduction; and no app path loads it anyway).

**User sees:** nothing different from S1 — that is what makes it F6/F7-class. The toast is identical whether the controller stored the design or an empty frozen shell.

### S3 — Animated modes: storable, but lossy in four ways  (CODE, executed; **NOT VERIFIED on HW from this caller**)

For `effectId != 0` the payload is a normal `fx`/`col` segment and *would* be stored. But ([editable_pattern_model.dart:156-218](lib/features/wled/editable_pattern_model.dart#L156-L218), [edit_pattern_screen.dart:135-141](lib/features/wled/edit_pattern_screen.dart#L135-L141)):

1. **`actionColors.take(3)`.** The screen offers "15 Layers" and shows all of them in the preview; layers 4–15 never leave the phone. Executed with 5 colors → `col` holds 3. (This also affects the *live* apply, not just the save.)
2. **No `ib:true`.** On this firmware a preset without `ib` stores no `on`/`bri` (slot 160 confirms: neither key present; compare slot 10, written by schedule sync, which has both). Brightness set in the editor is not in the preset.
3. **No segment `id`, no channel fan-out.** The live path runs `applyChannelFilter(payload, channels, …)` ([:94](lib/features/wled/edit_pattern_screen.dart#L94)); `_saveToDevice` does not ([:139](lib/features/wled/edit_pattern_screen.dart#L139)). An id-less single segment addresses WLED seg 0 only; every other channel is captured as whatever happens to be live.
4. **`direction` is unrepresented** (documented in-code, #76) — it is a control on the screen that reaches neither the lights nor the preset.

### S4 — The heart button cannot save: the live rule rejects its document shape  (**DATA** + CODE)

`_saveToDevice`'s docstring says *"App-side persistence is handled separately by the FavoriteHeartButton (writes to /favorites/, a read surface)."* That heart ([edit_pattern_screen.dart:667-672](lib/features/wled/edit_pattern_screen.dart#L667-L672)) — whose **only call site in the entire app is this screen** — writes via `FavoritesNotifier.addFavorite` ([favorites_providers.dart:183-211](lib/features/favorites/favorites_providers.dart#L183-L211)):

```
{ name, usageCount, lastUsed, wledPayload, autoAdded }      ← what is written
```

The **live** create rule ([firestore.rules:956-959](firestore.rules#L956-L959), identical in ruleset `f7b0658e`):

```
request.resource.data.keys().hasAll(['pattern_name', 'added_at'])
  && pattern_name is string && added_at is timestamp
```

Neither required key is present. `set(…, merge:true)` on a new doc id is a create. **DATA:** of 10 favorites docs / 7 users in production, **all 10** are the *other* (snake_case, `added_at`) schema; **0** are this schema, and **0** carry an editor-shaped payload.

**User sees:** taps the heart → it does not fill → orange toast **"Failed to save favorite"**. The same writer backs "Save to Favorites" at [pattern_category_detail.dart:563](lib/features/wled/pattern_category_detail.dart#L563) → "Failed to save to Favorites".

*Honest limit:* the denial is **deduced** from live rule text + write shape + the zero-document census. It was **not observed** with a client credential — doing so would have required a write to production.

### S5 — Even with S4 fixed, the heart would not deliver the customization  (CODE, latent)

- **Invisible in My Favorites.** The dashboard grid reads `UserService.streamFavorites` → `.orderBy('added_at', descending: true)` ([user_service.dart:492-506](lib/services/user_service.dart#L492-L506), via [learning_providers.dart:75](lib/features/autopilot/learning_providers.dart#L75)). Firestore excludes documents lacking the ordered field. Two incompatible schemas share one collection.
- **Unparseable by the grid's model.** That model reads `pattern_name` / `added_at` / `pattern_data` with non-null casts ([usage_analytics_models.dart:265-273](lib/models/usage_analytics_models.dart#L265-L273)); a heart doc has none of the three.
- **Wrong payload.** `patternData: _pattern.toJson()` is *editor* JSON (`actionColors`, `effectId`, …) stored under the key `wledPayload`. The consumer that *does* read that key by `name` — the geofence trigger ([geofence_monitor.dart:293-306](lib/features/geofence/geofence_monitor.dart#L293-L306)) — decodes it and treats it as a WLED state. It contains no `on`/`bri`/`seg`; WLED would ignore every key.
- **Shares the stock card's identity.** `patternId: _pattern.id` is the *Explore node id*. A customized Chiefs and stock Chiefs are the same favorite; a second tap deletes it.
- **Ignores the rename.** The heart passes `_pattern.name`; the name `TextField` has no `onChanged`, so `_pattern.name` never changes ([:243-258](lib/features/wled/edit_pattern_screen.dart#L243-L258)). Only `_saveToDevice` reads the text field.

### S6 — Slot allocation overwrites and collides silently  (CODE)

`presetIdForUserPattern` = `100 + id.hashCode.abs() % 101` ([wled_preset_ranges.dart:117-120](lib/features/wled/wled_preset_ranges.dart#L117-L120)), and `id` is the **source card's** id.

- **One slot per source card, forever.** A second custom variation of Chiefs overwrites the first. Renaming does not help — the slot is keyed on id, not name.
- **Cross-card collisions are silent.** 101 slots: ≥50 % chance of at least one collision by ~12 distinct cards. Executed: Chiefs 160, Bills 152, Royals 195, Cowboys 117.
- **`String.hashCode` is not a stable contract** across Dart releases/platforms. Observed equal here (desktop JIT and the handset both → 160), but an SDK bump could re-map every slot.
- **Nothing ever deletes these presets.** `deletePreset` has one caller, strictly bounded to 10–25 ([schedule_sync.dart:1507-1510](lib/features/schedule/schedule_sync.dart#L1507-L1510)).

### S7 — Success reporting: better than F6/F7, still not verification  (CODE)

Credit where due: the returned bool **is** checked, a failure shows red "Failed to save to device", and exceptions are caught — this is *not* a discarded-result bug. The gaps:
- **Success = HTTP 2xx** ([wled_service.dart:1603-1608](lib/features/wled/wled_service.dart#L1603-L1608)). No read-back. WLED answers 200 equally for a useful preset and for S2's empty shell.
- **No demo-mode gate.** `_sendToWled` returns early under `demoModeProvider` ([:83](lib/features/wled/edit_pattern_screen.dart#L83)); `_saveToDevice` does not, and `DemoWledRepository.savePreset` returns `true` → "Saved to device" with no device. Low severity.
- **Bridge path:** `CloudRelayRepository.savePreset` queues the same payload as a relay command. **NOT VERIFIED** — whether a 5.4 KB `i`+`psave` command survives the bridge was not exercised.

---

## 4. Hardware log (bench `.150`) — read-only

**No payload was sent to the controller.** The task brief asked for the code path to be driven on the bench and read back. I deliberately did not, for three reasons, and I think the evidence is stronger for it:

1. **The real artifact was already there.** Slot 160 was written by the real app on a real handset through the real button. A replay from a harness is a weaker form of the same evidence.
2. **The controller was in live use.** `info.fs.pmt` (presets last-modified) was **2026-09-20 18:29:50 UTC**; my first read was 18:36:48 UTC. The strip was still showing the custom red/gold/white look with `ps:-1`. That is, most plausibly, the reproduction itself. A replay would have overwritten it, and a frozen per-pixel frame cannot be restored faithfully from a gamma-shaped live-view read.
3. **Cleanup would have needed `pdel`**, which is the known cause of stray-byte corruption in `presets.json` (P1-52) — on a file that already carries 7 stray bytes.

| Step | What was done | Result |
|---|---|---|
| R1 | `GET /json/info`, `/json/state`, `/json/cfg`, `/presets.json` | 0.15.1 / vid 2507300; `on:true bri:255 ps:-1`; both segs `fx:0 frz:true col:black`; presets 16,585 B |
| R2 | Per-entry salvage parse of `/presets.json` | 22 slots: 0–5, 10, 26–31, 33–34, 36–41, **160**. Slot 160 = `n:"Kansas City Chiefs"`, content as in §1. Exactly one slot in 100–200. |
| R3 | WebSocket live-view, one frame, 290 LEDs | LEDs 0–127: (184,0,3) ×43, (255,102,1) ×43, (255,255,255) ×42, strict R/G/W repeat. LEDs 128–289: black. Values = `E31837` / `FFB81C` / `FFFFFF` through 2.8 gamma. |
| R4 | Dart: `presetIdForUserPattern('team_nfl_chiefs')` | **160** |
| C1 | Throwaway harness, real classes, simulate mode (no network) | Static → slot 160, name "Kansas City Chiefs", `seg[0]` keys `[fx, i, grp, spc]` — no `col`, no `frz`, no `id`; top-level no `ib`. Animated ×3 colors → `col` ×3, `frz:false`. Animated ×5 colors → `col` ×3. |

**Inference, labelled as such:** `pmt` records the last write to `presets.json` by *any* writer, so 18:29:50 UTC is an upper bound on when slot 160 was written, not proof of it. `_saveToDevice` is unchanged since `9f6008c` (2026-05-30) and is contained in every build tag from `build-74` through `build-102`, so whichever build wrote slot 160, it ran this code.

**Observed, cause NOT DETERMINED:** channel 2 (LEDs 128–289) is black and frozen. Whether the live-apply's channel filter or the id-less save POST (S3.3) produced that was not isolated.

---

## 5. Root cause

This is the residue of a correct-but-incomplete fix. **#85 W2 (`9f6008c`)** found that this button wrote to `/users/{uid}/patterns/`, a collection with zero readers, and toasted success. It removed the dead write — right call — and kept the `psave`, reasoning that the heart covered app-side persistence. Two things were not checked at the time and are still true:

1. **The `psave` also has zero readers.** The fix replaced "a Firestore write nobody reads" with "a device write nobody reads". The false-success moved; it did not go away.
2. **The heart was never able to write** (S4), so the screen has had *no* working app-side persistence since at least that commit.

Underneath both: the Edit Pattern screen is an island. It was modeled on the native controller app (its own header comment says so), where "save to device" *is* the whole persistence model because that app browses device presets. Lumina's persistence model is `/designs` + a static catalog. The screen was ported without being connected to either.

S2 is an independent defect on top: two freeze guards each assume the other handles the `i`-segment case.

**Relationship to known-lossy paths:** this flow does **not** pass through `CustomDesign.toWledPayload()` or `apply_saved_design.dart` (F3). It is a separate path with its own, similar loss (`take(3)`).

---

## 6. Other investigated items

| Question | Answer | Evidence |
|---|---|---|
| Is the Colorway Effect Selector the screen with the button? | No. It hosts the *entry* (tune icon). Its own commit button reads "Apply" / "Set design" / "Save to design". The literal string `SAVE TO DEVICE` occurs once in `lib/`. | CODE |
| Does the button mutate the Explore card? | No. | CODE |
| Is there *any* working route from a customized Explore palette into My Designs? | Only indirectly: dashboard adjustment panel → **"Save As Custom Pattern"** → `saveCurrentAsDesignProvider` → `/designs` ([design_providers.dart:567-619](lib/features/design/design_providers.dart#L567-L619)). It snapshots `wledState.color` — **one color per channel** — so it cannot hold a multi-color custom palette either. Not traced further. | CODE |
| Did anything get written to Firestore by the reporter's session? | 2 `designs` docs were written on 2026-09-20 UTC (newest 18:26:17Z, ~3.5 min before the preset write). Neither is named like the pattern. Their content was not read. | DATA |
| Reporter's own account | A `users` lookup by the owner's email matched 0 docs (different field name or a different sign-in). Not pursued; fleet-wide counts were used instead. | DATA |

---

## 7. What would need to be true for this to work as the user expects

1. "Save" on the Edit Pattern screen writes a `/users/{uid}/designs` document (new id, not the catalog id) that carries **all** action colors, so it appears in My Designs.
2. If a device preset is still wanted, it is written *from* that design, with `ib:true`, channel fan-out, and — for Static — a storable representation rather than an `i` array; and its slot id is recorded on the design so the app can find and delete it.
3. The heart either conforms to the `favorites` rule and the grid's schema, or is removed from this screen.
4. Success is reported after a read-back, not after an HTTP 200.

Suggested order if this is picked up: **1** (fixes the reported symptom) → **S2 guard** (stops writing poison presets) → **3** → the rest.

---

## 8. Cleanup confirmation

| Item | State |
|---|---|
| Bench controller state | **Never written.** `/json/state` before vs after: **96 fields compared, 0 differing**. Live frame: **290 LEDs compared, 0 differing**. The user's reproduction is still on the strip exactly as found. |
| Bench presets / config | **Never written.** `presets.json` sha256 `8c53e9fe…29a8` before **and** after; `cfg` sha256 `2693deef…0f35` before and after; `fs.pmt` unchanged (1789928990). No `psave`, no `pdel`, no `/json/cfg`, no reboot, no upload. Slot 160 left in place — it is the user's data and the primary evidence. |
| Firestore | **Zero writes.** Three read-only `runQuery` calls (collection groups `favorites`, `patterns`, `designs`), one `users` equality query, one ruleset fetch. No throwaway documents exist. |
| Worktree | Throwaway harness (`test/_audit_tmp/`) deleted; `git status` clean at `73ae375` before this report was added. `flutter pub get` created only git-ignored artifacts. |
| Git | One throwaway commit containing only this file, on a **local-only** branch. **Nothing pushed.** `main`, the shared checkout, all tags untouched. |
| Customer data | Only counts, schema shapes, catalog-constant ids and rule text were extracted. No names, emails, addresses or design content were read into this report. |

## 9. Side-findings (out of scope, untouched)

- **`/presets.json` on the bench is still not valid JSON** — same 7 stray `0xFF` bytes at the same offsets as reported 2026-09-19 (3868, 4581, 4685, 4827, 4970, 4973, 4978). **Correction to that report's wording:** only the first 2 sit in whitespace padding. The other **5 are inside slot 41 ("Lease…") and overwrite real characters** — the `a` of `"mainseg"`, a `col` value, a value after `"m12":`, a `{` and a `:`. Slot 41 is unrecoverable; stripping the bytes does not repair it. Per-entry salvage recovers the other 21 slots, slot 160 included. Pre-existing (same offsets yesterday); byte-identical across this audit.
- The bench reported **uptime 743 s** at first read — it had booted ~5.5 min before the preset write. Noted as a fact only; no cause investigated.

## 10. Notes for project memory

- `FavoriteHeartButton` has exactly one call site and **cannot write under the live rules**; `/users/*/favorites` holds two incompatible schemas, of which only the snake_case one exists in production (10 docs / 7 users).
- The WLED preset range **100–200 is write-only** from the app's point of view.
- `designs` census moved from 14 docs / 7 users (09-19) to **16 / 8** (09-20).
