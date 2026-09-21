# "Save to Device" → My Designs, and the favorites fix — Report (2026-09-21)

**Branch:** `fix/save-to-my-designs-and-favorites` — local only, **not pushed, not tagged, version not bumped.**
**Base:** `origin/release/store-submission-consolidated` @ **`73ae375`** (fetched at start; tip confirmed unchanged since the 09-20 audit). Isolated worktree. `main`, the shared checkout, every tag, and the `fix/firestore-transaction-crash` and Game Day rainbow branches/worktrees were not touched.
**Audits read first, in full:** `design-studio-audit-2026-09-19.md`, `design-studio-followup-2026-09-19.md`, `explore-palette-save-to-device-audit-2026-09-20.md` (`a9ce127`).
**Hardware:** bench `192.168.1.150` — WLED 0.15.1, 290 RGBW LEDs, seg0 = 0–128, seg1 = 128–290.
**Firestore:** production project, live ruleset **`f7b0658e`** (byte-identical to `firestore.rules` at this tip). **The rules were not changed.**

| Commit | What |
|---|---|
| `dc20d79` | `fix(design)` — a saved effect design states its palette; the spine can restore a chosen brightness |
| `adacf15` | `fix(favorites)` — one document shape, the one the live rule accepts |
| `ff5f1b4` | `feat(pattern-editor)` — SAVE keeps the pattern in My Designs; retire "SAVE TO DEVICE" |
| `54a7baf` | `test` — drop two redundant imports |

Every commit used explicit pathspecs. Each compiles on its own.

## Evidence labels

**HW** = read off the bench (state, presets, 290-LED frame buffer over the live-view WebSocket). **DATA** = real production Firestore, or the live ruleset, exercised with a **client** credential. **CODE** = the real production classes executed in tests. **NOT VERIFIED** = stated wherever it applies. *There is still no handset, so nothing here was seen inside the running app UI.*

---

## 0. Two corrections to the brief, up front

**1. The 10 (now 11) production favorites are not malformed.** The brief says *"0 of 10 real production favorites match the required format — every favorite save has been failing."* My 09-20 audit said the reverse and I should have made it harder to misread: **all** of them match the rule. They were written by the habit learner, the one writer that has always conformed. What has never succeeded is a *manual* favorite — the heart and "Save to Favorites". So:
- There is nothing to repair or migrate, and I touched none of them (§5, fingerprint identical).
- But those 11 documents turned out to be **unreadable by the app** — a second, independent break on the read side (§3.2). That is fixed without changing a byte of data.

**2. The bench found two defects that neither the audits nor the brief knew about.** Both sat directly in the path of this change, so both are fixed here rather than reported and left:
- The editor's **Static live preview never reached the lights** on this install (§2.3).
- A saved **animated design lost its third colour on re-apply**, depending on what ran before it (§2.4).

---

## 1. Summary

| | Before | After | Evidence |
|---|---|---|---|
| Where Save puts the pattern | a WLED preset slot no part of the app can read | a document in `/users/{uid}/designs` — My Designs | DATA |
| Static pattern, saved | black, frozen, no on/bri (bench slot 160) | 290/290 pixels exact after a real Firestore round trip | **HW** + DATA |
| Static pattern, re-applied from My Designs | n/a (unreachable) | frame buffer **0/290 differ** from the editor's live look; brightness restored | **HW** |
| Animated pattern, re-applied | n/a | device look identical to the editor's, incl. `pal`; all three colours in the frames | **HW** |
| Static live preview in the editor | refused before it was posted (5.5 KB / 10.9 KB vs a 4 KB cap), silently | 290/290 lit on both channels | **HW** |
| Two saves from one Explore card | second overwrote the first (one hashed slot per source card) | two documents, two server-assigned ids | DATA |
| Manual favorite (heart / Save to Favorites) | **403** from the live rule, every time | **200**; every control still 403 | DATA (client token) |
| My Favorites grid, for users who have favorites | model threw on every production doc → grid silently empty | parses | CODE |

Gates: `flutter analyze` **0 / 12 / 370 — issue set identical to baseline**. `flutter test` **3,219 passed / 19 skipped / 0 failed** (baseline 3,175 / 14 / 0).

---

## 2. Part A — "Save to Device" is retired

### 2.1 What was removed, what replaced it

**Removed** (`ff5f1b4`):
- `_EditPatternScreenState._saveToDevice` — the `repo.savePreset(...)` → `psave` call. Nothing on this screen writes to device storage any more.
- `presetIdForUserPattern` (`wled_preset_ranges.dart`) — `100 + id.hashCode.abs() % 101`. **Mechanism confirmed before removal:** the key was the *source card's id* (`team_nfl_chiefs` → 160). Callers in `lib/`: **one** — the button. Removed with its 6 tests.

**Replaced with** `_saveToMyDesigns` → `customDesignFromEditablePattern` (new, pure: `lib/features/design/editable_pattern_design.dart`) → **`DesignService.saveDesign`**, which I confirmed is still the canonical entry point after +101 (the paint editor, the tuner's save-to-design, the AI studio and the dashboard save all go through it). It builds the two shapes the design system already has, not a third:

- **Static →** a painted design, `per_pixel: true`. The look is laid into a `PixelDesignDocument` and compressed with `toLedColorGroups()` — *the paint editor's own writer*. Applies through the per-pixel spine; **Edit** reopens it in the paint editor. All 15 layers survive.
- **Animated →** an effect design, the shape the colourway tuner edits.

**The button is now `SAVE`** (tooltip/semantics "Save to My Designs"). I chose the short label because "SAVE TO MY DESIGNS" at the app bar's 15 px bold does not fit beside the title on a 360 dp phone. The toast carries the destination — `Saved "Kansas City Chiefs" to My Designs` — with a **VIEW** action that opens My Designs.

**Name:** the screen's existing PATTERN NAME field, pre-filled from the source card and editable. Blank → "Custom Pattern". If the account already has a design by that name it becomes "Kansas City Chiefs 2" — checked with a one-shot fetch for the account being saved *into*. (My first version read `designsStreamProvider`; a widget test showed that provider is cold unless another screen happens to be watching it, so the check silently did nothing. Fixed before commit.) The name field never updated the model before, so the heart always used the source card's name; it does now.

**Pressing SAVE twice:** same name as the last save from this screen → **updates** that design. A different name → a **new** design. So renaming is how a second variation is kept, and a variation can never overwrite the first by accident.

**Failure handling:** signed out, a denied write, a deleted target and no-channel-census each produce a specific red message and no success toast (reuses +101's `describeDesignSaveError`).

### 2.2 Item 6 — no collision risk

New designs carry `id: ''` → `createDesign` → `.add()` → a server-assigned id. **DATA:** two saves built from the *same* source card, written with a client token, came back as `WAKT6X45…` and `qj8qdJG0…`. A unit test asserts the source card's id appears nowhere in the stored document. The hash, the 101-slot band and the one-slot-per-source-card behaviour are gone.

### 2.3 Found on the bench: the Static live preview never worked here  (**HW**)

Phase 1 of the bench test failed on its first line: the editor's own Static write returned `false`.

`EditablePattern` Static emits one `i` entry per LED, and the channel filter clones that segment per channel. `WledService.applyJson` refuses anything over **4,096 B** (WLED itself rejects ~6 KB). `_sendToWled` did `if (!ok) return;` — silently.

| T22 | Payload | `applyJson` | Frame |
|---|---|---|---|
| 1 channel | 5,480 B | **false** | unchanged |
| 2 channels | 10,891 B | **false** | unchanged |

So on any install past ~215 LEDs, Static in this editor has never reached the lights. **This also closes the "cause NOT DETERMINED" note in the 09-20 audit:** the only thing that lit your red/gold/white pattern was the old `SAVE TO DEVICE` POST itself — it had no size guard and no channel filter, so it landed on segment 0 only. That is exactly why channel 2 was black.

It matters here because with the `psave` gone, Static would otherwise *never* reach the lights from this screen. **Fix:** Static now goes through the chunked per-pixel spine (no payload ceiling), built from **the same design Save stores** — what is on the lights is what gets kept, by construction. Sends are serialised so a colour-wheel drag cannot interleave two multi-request applies. **HW (T23): 290/290 lit, both channels, each restarting red/gold/white at its own LED 0.**

### 2.4 Item 5 — the animated colour-loss bug: gone by construction, and what the new path still can't do

**Gone because the code path is gone, not patched.** The 3-of-15 / no-brightness / one-channel losses lived in `_saveToDevice`'s `psave` encoding. That function no longer exists; nothing else called it.

You asked me not to assume the new path is automatically fine. It wasn't, quite:

| Old loss | New path | Evidence |
|---|---|---|
| **Only 3 of 15 colours** | **Static: all 15 stored *and* rendered** (per-LED). **Animated: a real limit remains, and it is firmware's** — a WLED effect has three colour slots (`seg.col[0..2]`). The first three groups are byte-identical to what the lights show (background slot included); layers 4–15 are *kept in the document* but no effect can draw them. The old screen offered 15 layers and silently showed 3. It now says, in amber: *"Animated modes use the first 3 colors. Set MODE to Solid to use all N."* | CODE |
| **No brightness** | Effect designs always stated `bri`. **The per-pixel path did not** — the spine has never sent it, deliberately, because most designs carry the model default (200) that nobody chose (the paint editor has no brightness control). Fixed narrowly: the spine takes an optional brightness in its base write, used **only** for designs this editor saved (`CustomDesign.statesBrightness`, keyed on the `pattern-editor` tag). Every other caller passes null and its payload is byte-identical to before — **no existing design changes behaviour**. Bench: controller at 128 → My Designs apply → **180**, the saved value. | **HW** (T25) |
| **Other channels not targeted** | The design holds every channel the editor was targeting; both apply paths fan out by channel id. | **HW** (T25/T26, both segments) |
| *(new)* **Palette inherited from the previous look** | `CustomDesign.toWledPayload()`'s effect shape never stated `pal`. Every live builder in the app states `pal:5`; after any per-pixel apply the segment sits at `pal:0`, under which a palette-driven effect draws only its first colour(s). **First bench run (T26): a red/gold/WHITE "Running" design came back red/gold — the white, i.e. the customization, gone — with the device reporting `pal:0` where the editor had shown `pal:5`.** Same rule as #88's grp/spc (*unstated design state is inherited design state*), fixed the same way: stated, as `kDesignColorsOnlyPalette`. Re-run against the **same stored Firestore documents**: `pal:5`, white back. This benefits every saved effect design, not only this editor's. | **HW** |

**Still true, flagged rather than fixed:**
- **DIRECTION** is a control on this screen that reaches neither the lights nor the design. Pre-existing and deliberate (#76: `rev`/`mi` are installation geometry). Noting it because it is now the one remaining control here that does nothing.
- **Static designs can't be scheduled or used for Game Day.** They are per-pixel designs, and the +101 picker refuses those (a WLED preset can't hold the pixel buffer — the same fact that motivated this whole change). Animated saves are unaffected.
- **BG COLOR is ignored in Static** (pre-existing: the Static look never used it).
- **Document size.** Alternating per-LED colours don't compress: 290 LEDs = 290 runs = 64 KB as REST JSON. Fine against Firestore's 1 MiB; an oversize save surfaces +101's "too large" message.

### 2.5 Item 7 — the old preset-slot mechanism: what went, what stayed, and why

**Checked before deleting anything.** Readers of presets in 100–200, across `lib/`: **none.** `loadPreset` has one caller (`schedule_enforcement.dart`, slots 10–25). `deletePreset` is bounded to 10–25. `readPresets()` is used only by the healer and schedule sync. No screen lists device presets.

- **Removed:** `presetIdForUserPattern` — dead the moment its only caller went.
- **Kept, deliberately:** the band constants and `wledPresetRole`'s `'user_pattern'` branch. That is **a live dependency**: `base_boundary_denormalizer.dart:294` publishes each timer macro's role to the server. And controllers in the field still hold presets customers saved there. So the band stays **reserved** and is now documented as *legacy — no longer allocated*; a future allocator must not reuse those slots.
- **Not touched:** `savePreset` itself (schedules, leases, healer, sunrise-off all use it).

**Two things left for you:**
1. **Bench slot 160 ("Kansas City Chiefs") is still on your controller.** I did not delete it: it is your data, and `pdel` is the known cause of `presets.json` corruption (P1-52) on a file that already has a wrecked slot 41.
2. **The freeze-guard gap from the 09-20 audit (S2) is still open**, now latent. `normalizeWledPayload` skips `frz:false` for `i`-segments and `ensurePsaveClearsFreeze` early-returns on caller-supplied segments. With this button gone, **no caller `psave`s an `i` payload any more**. Making `savePreset` refuse one would be the class fix, but schedule sync and the lease manager share that function and a refusal changes what Sync reports; I did not make that call unattended.

---

## 3. Part B — favorites

### 3.1 The write  (**DATA**, client credential)

The heart, "Save to Favorites" and the brand design generator all wrote `{name, usageCount, lastUsed, wledPayload, autoAdded}`. The live create rule requires `pattern_name` (string) **and** `added_at` (timestamp).

**Fix:** `lib/features/favorites/favorite_doc.dart` is now the **one** place a favorites document is built, and every writer goes through it:

```
pattern_name  string     the pattern/card name        (rule-required; immutable)
added_at      timestamp  FieldValue.serverTimestamp() (rule-required; immutable)
pattern_data  string     jsonEncode(WLED payload)
usage_count   int
auto_added    bool
```

- **Convention, checked not invented:** this is field-for-field the shape of every favorite in production, and `UserService.addFavorite` already used `serverTimestamp()` for `added_at`. `pattern_data` stays JSON-encoded for #84 (arrays-of-arrays abort the native iOS codec).
- **A re-save never restates `pattern_name` or `added_at`.** The update clause freezes both, and a fresh server timestamp *is* a change. The old `set(merge:true)` would have been denied on every second save even with the right keys — verified live below.
- **Why it survived two audit passes:** the widget tests swap the notifier for a fake and never look at the document. `favorite_doc_test` now **parses the required keys out of `firestore.rules`** and asserts the writer emits them, so the two cannot drift apart again.

**Live-rule verification — 18 / 18.** Same pattern as the designs-rule deploy: the admin SDK only mints custom tokens and cleans up; **every assertion is made with an Identity Toolkit ID token** over Firestore REST. The documents sent were exported from the **real Dart writers**, not hand-written look-alikes, and sent as the SDK sends them (one write: fields + server-value transforms).

| # | Case | Expected | Got |
|---|---|---|---|
| 1 | **OLD heart shape → create** | DENY | **403** — *the production failure, observed; on 09-20 I could only deduce it* |
| 2 | **NEW shape (real writer output, 290-LED Static payload) → create** | ALLOW | **200** |
| 3 | owner reads it back | ALLOW | 200 |
| 4 | stored doc: `pattern_name` string, `added_at` a **server** timestamp, `pattern_data` decodes to the payload | — | ✔ |
| 5 | the My Favorites grid's own query (`orderBy added_at`) returns it | — | ✔ |
| 6 | re-save (writer's refresh: `pattern_data` + `last_used`) → update | ALLOW | 200 |
| 7 | usage bump (`usage_count` increment + `last_used`) → update | ALLOW | 200 |
| 8 | re-sending the **create** doc over an existing favorite | DENY | 403 |
| 9 | update renaming `pattern_name` | DENY | 403 |
| 10 | create missing `added_at` | DENY | 403 |
| 11 | create missing `pattern_name` | DENY | 403 |
| 12 | `pattern_name` not a string | DENY | 403 |
| 13 | `added_at` a string, not a timestamp | DENY | 403 |
| 14–16 | another signed-in user: create / read / delete | DENY | 403 ×3 |
| 17 | unauthenticated create | DENY | 403 |
| 18 | owner deletes (un-heart) | ALLOW | 200 |

Rows 8–17 are the "didn't loosen or bypass anything" half: **the rule file is unchanged** and every validation it performs still bites.

**"Failed to save favorite" no longer appears for a well-formed favorite** — established at the rule (row 2) and in code. **NOT VERIFIED in a running app.**

### 3.2 The read — the break the brief didn't know about  (CODE)

Once the writer conformed I checked whether the surface that *shows* favorites could read a conforming document. It could not — including the 11 that already exist.

- **My Favorites grid** (`usage_analytics_models.FavoritePattern.fromJson`) cast `pattern_data` `as Map?`. It is a **String** in every production document. Demonstrated, not asserted — on the pristine `73ae375` tree with a production-shaped doc:
  `THREW _TypeError: type 'String' is not a subtype of type 'Map<dynamic, dynamic>?'`
  `FavoritesGrid`'s error branch renders the **empty state**. So for the 8 users who have favorites, My Favorites has been silently blank. Fixed with a tolerant decoder; **no data touched**. It also now survives a null `added_at`, which is what a pending server timestamp reads as on the *first snapshot after any create* — without that, every new favorite would have blanked the grid for a moment.
- **The heart-side model** (`favorites_providers.FavoritePattern.fromFirestore`) read only the camelCase keys no document has ever had — every favorite was `"Unnamed Pattern"` with an empty payload (it feeds the Now Playing name match and the AI classifier). Now snake_case first, camelCase as fallback. Its dead camelCase `toFirestore()` is removed; `favoritesPatternsProvider` orders by `usage_count`.

### 3.3 What a favorite stores

The heart stored `_pattern.toJson()` — the *editor model's* JSON (`actionColors`, `effectId`…) — under a key My Favorites POSTs to the controller verbatim. WLED would have ignored every key. `FavoriteHeartButton` now takes a **tap-time** payload builder, and its one caller passes the real WLED payload. "Save to Favorites" now stores the payload its own screen applies (adds `on:true`).

**In Static the heart declines:** *"This mode is stored LED by LED — tap SAVE to keep it in My Designs."* A 290-LED per-pixel payload **is** accepted by the rule (row 2 is exactly that document) — and could then never be re-applied, because My Favorites sends a favorite as one payload through the same 4 KB-capped `applyJson` (§2.3). Saving something that cannot be applied is the lie this pass exists to remove. A heart that is already filled can still be un-filled.

### 3.4 Left alone, on purpose

- **The 11 production favorites.** Well-formed; untouched; now readable.
- **Geofence.** `geofence_monitor` / `geofence_setup_screen` look favorites up by the camelCase `name`, and a comment there records a deliberate earlier decision *not* to query `pattern_name`. They see no favorites today and still see none. Not overriding a documented decision in a feature I cannot exercise.
- **Brand design generator:** document **shape** fixed only. From an installer's session the owner-only rule still denies it, as before — a rules decision. **NOT VERIFIED end to end.**
- **One heart, one id.** A favorite is still keyed by the *source card's* id, so a customized Chiefs and stock Chiefs are the same favorite. Save (My Designs) is the right home for variations.
- There are still two `FavoritesNotifier` / `FavoritePattern` classes in two libraries. They now agree on the schema; merging them is a refactor.

---

## 4. Bench verification — save → reopen → apply  (**HW**)

`test/hardware/save_to_my_designs_live_test.dart` (RUN_HW-gated; skips otherwise) drives the **real** classes through the **real** `WledService`. The design crosses a **real Firestore leg in the middle**, made with a client token, so "appears in My Designs" means *My Designs' own query returned it*.

**Subject:** the NFL Chiefs Explore card exactly as the tuner hands it to the editor (`team_nfl_chiefs`, red + gold), customized with a third colour (white) and brightness 180.

| Test | What | Result |
|---|---|---|
| Baseline | read-only | OFF, `ps:2`, 290/290 black, `bri:128` |
| **T22** | the editor's *old* Static write | refused at 5,480 B and 10,891 B; frame unchanged (§2.3) |
| **T23** | Static, lit as the editor now does; design exported | **290/290 lit**; LEDs 0–2 and 128–130 = red / gold / white |
| **T24** | Animated ("Running"), lit as the editor does; design exported | 53 frames; `fx:15 sx:140 ix:128 pal:5`; palette includes white |
| **Firestore leg** *(client token, 7/7)* | both designs created with `.add()`; read back through **My Designs' own query** (`orderBy updated_at desc`) | both returned, two distinct ids; another signed-in user's list → **403** |
| **T25** | Static: rebuilt from what Firestore returned → reopened as the paint editor does → scrambled → applied as My Designs does | **reopened 290/290 pixels exact**; applied frame vs the editor's live frame: **0/290 differ** (vs the scramble: 290/290 differ); `bri` 128 → **180** |
| **T26** | Animated: reopened as the tuner does (3 colours, fx/speed/intensity/brightness) → applied over a **frozen `pal:0`** state — the worst case | 1st run **FAIL** — `pal:0`, white missing (§2.4). After `dc20d79`, against the *same stored documents*: **PASS** — device look identical field-for-field incl. `pal:5`; frame palette identical; animating |

*Honest limits.* "As My Designs does" means the two calls `applySavedDesign` makes (`applyPositionalDesignWith`; `applyChannelFilter` + `applyJson`) — not that function itself, which needs a `BuildContext` and the sync-warning dialog. The live-view frame is pre-brightness, so brightness was read from `/json/state`. Animation was judged on a 4 s frame *series*, not a snapshot. **Remote/bridge mode NOT VERIFIED:** Static live preview is now base + one request per chunk, and at relay latency that will be slow.

---

## 5. Cleanup and restoration

| Item | State |
|---|---|
| **Bench state** | **Restored and verified.** `/json/state` before vs after: **96 fields compared, 0 differing.** Live frame: **290 LEDs, 0 differing** (all black). `on:false`, `ps:2`. Restored by the test's own teardown + the controller's OFF preset. No reboot (uptime continuous). |
| **Bench presets / config** | **Never written.** `presets.json` sha256 `8c53e9fe…` before **and** after (same as 09-20 — slot 160 included); `cfg` `e1feef2e…` before and after. No `psave`, no `pdel`, no `/json/cfg`. |
| **Bench exposure** | Four runs of 7–13 s each (10:29–10:47 local, daylight); lights on only while a run was in progress, OFF again after each. `/json/state` POSTs only. |
| **Production Firestore — real data** | **Unchanged.** Every real `favorites` (11 docs / 8 users) and `designs` (18 / 8) document fingerprinted by name + updateTime before and after, via a second credential path (gcloud ADC): sha256 `33a7d440…` and `0ce3bbd0…` — **identical**. |
| **Production Firestore — throwaway data** | Two Auth users (`zz_rules_probe_fav_{owner,other}_0921`), one favorite, two designs. The favorite was deleted by its owner inside the probe (row 18); cleanup removed the 2 designs + 2 Auth users. **Residue sweep: 0**, confirmed by both credential paths. No `users/{uid}` doc was ever created, so `assignReferralCode` never fired; no function triggers on `favorites` or `designs` (checked). Every denied write, by definition, created nothing. |
| **Rules** | Not deployed, not edited. Live `f7b0658e` before and after. |
| **Worktrees** | Scratch tests deleted from both worktrees; both clean. |
| **Git** | 4 commits + this report on a local-only branch. Nothing pushed, tagged or bumped. |

---

## 6. Test and analyze results

| | Baseline `73ae375` | This branch | Δ |
|---|---|---|---|
| `flutter analyze` errors / warnings / infos | 0 / 12 / 370 (382) | **0 / 12 / 370 (382)** | **issue set identical** (diffed line by line, positions stripped) |
| `flutter test` passed | 3,175 | **3,219** | +44 |
| skipped | 14 | **19** | +5 — the new `RUN_HW`-gated hardware tests |
| failed | 0 | **0** | — |

+44 = 50 added − 6 removed (the dead allocator's tests): `editable_pattern_design_test` 19 · `favorite_doc_test` 16 · `edit_pattern_save_to_my_designs_test` 11 (pumps the real screen with a real `GoRouter`) · `positional_design_apply_test` +2 · `favorites_save_buttons_test` +2.

The known time-dependent red test (the midnight-wrap lease, #64) happened to pass in every run today.

---

## 7. Decisions waiting on you

1. **Bench slot 160** — delete it, or leave it? (§2.5)
2. **`savePreset` refusing `i`-bearing payloads** — closes the 09-20 S2 guard gap for good, but touches schedule sync's error reporting. (§2.5)
3. **Brightness for *all* painted designs.** I restored it only for designs this editor saves. The scene/router payload path *already* states `bri` for every painted design (default 200) while My Designs' apply does not — an inconsistency that predates this pass. Unifying it changes what existing painted designs do. (§2.4)
4. **Static favorites.** Declined for now. Making them work means teaching My Favorites' apply to route an `i`-bearing payload through the chunked spine. (§3.3)
5. **Geofence** reading favorites by `pattern_name`. (§3.4)

## 8. For project memory

- `applyJson` has a **4,096 B ceiling**; anything per-LED must go through the spine. The Pattern Editor's Static preview was silently dead past ~215 LEDs until this branch.
- A saved effect design must state `pal` — `CustomDesign.toWledPayload()` now does.
- `/users/*/favorites`: one schema, snake_case, built only in `favorite_doc.dart`. Production: 11 docs / 8 users, all well-formed, all auto-added. Both reader models were broken against them until this branch.
- WLED preset band 100–200: legacy, reserved, unallocated.
- `cloud_firestore` captures its `FieldValue` factory statically on first use — a test that builds a server timestamp before constructing `FakeFirebaseFirestore` poisons every later fake write in that file.
