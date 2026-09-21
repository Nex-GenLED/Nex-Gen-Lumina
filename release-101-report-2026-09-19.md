# Release 2.5.10+101 — Design Studio fix pass

**Date:** 2026-09-19 · **Branch:** `release/store-submission-101` · **Tag:** `build-101` → `9749d91`
**Base:** `origin/release/store-submission-consolidated` @ `3df2d24` (= `build-100`; fetched and verified first, not assumed).
**Status:** pushed, tagged, both integration refs fast-forwarded, iOS CI run **confirmed started**. `main` untouched. Android bundle built locally, not uploaded. **Nothing was deployed** (no rules, no functions) and **no production document was modified**.
**Source of truth for what to fix:** `design-studio-audit-2026-09-19.md` (F1–F7, root causes A/B/C) and `design-studio-followup-2026-09-19.md` §5 (M1–M15), both read in full first.

> ## ⚠ Four things need you before / after this ships
> 1. **HARD STOP honoured — production pixel maps were NOT touched.** §4 is a dry-run for your decision: **7 documents across 6 installs** are affected; 4 are a mechanical re-base, 3 overflow their strip and need a human.
> 2. **The `designs` rule change is committed but NOT deployed.** The live ruleset (`fdaecb9d`) is byte-identical to this branch's parent, so a deploy from here changes exactly two `allow` lines. Until it is deployed an installer in Existing-Customer mode still cannot save — but is now *told* so. After deploy, verify with a **client** credential.
> 3. **Per-pixel designs cannot be scheduled (or used for Game Day) — by WLED's design, not ours.** I made the picker refuse them honestly instead of scheduling the wrong look. Whether to build real support is a product/firmware decision (§5.1).
> 4. **Nothing here was seen in a running app.** There is still no handset. Every UI change is covered by widget tests and every device-facing change by bench frame-buffer reads, but nobody has tapped these screens on a phone.

---

## 0. Ground truth

| Check | Result |
|---|---|
| `git fetch origin` | tip of `origin/release/store-submission-consolidated` = **`3df2d24`** = `build-100` = `origin/dev/post-submission` |
| Worktree | fresh: `C:\Flutter Projects\lumina-b101`, new branch `release/store-submission-101` (upstream deliberately unset) |
| `design/` vs the audits' pins | `lib/features/design/` byte-identical at `995d9fc` and `3df2d24`, so every audit citation held |
| Live Firestore ruleset | `fdaecb9d` (2026-09-18) — **byte-identical** to `firestore.rules` at `3df2d24` (fetched via the Rules REST API and compared). The project-memory note that a deploy from the consolidated line would revert the stub-doc fix is **stale**: that fix is already on this line. |
| Shared checkout `C:\Flutter Projects\Lumina V 1.6` | **never written.** Read twice: `git show` of the two audits / the +100 report from refs, and an md5 of the three git-ignored Android signing inputs to confirm the copies I used match. Verified at the end of the pass: `HEAD` still `df6063b` (detached), the index file's SHA-1 unchanged (`05513ea4…`), and `git status` still reports the same 42 pending paths — no tracked file modified, no file added. |

---

## 1. What was fixed

Order follows the follow-up report's §5: **the pixel-map writer first**, because it re-corrupts documents on every anchor edit and any data fix made before it would be overwritten.

| # (yours) | Audit id | Commit | One-line |
|---|---|---|---|
| 1 | M4 · F4 · N1b/N1d | `3020e97` | `start_pixel` is channel-local everywhere; the writer keeps one counter **per channel**; the Firestore write boundary re-derives it; the AI camp translates explicitly. |
| 1 (wizard) · 2 | N1c · M6 · N1a | `870e8ef` | Setup Wizard assigns segments to channels; **"Light It Up" lights a real LED** with checked writes and restores on close. |
| 3 · 12 | M5 · F7 · M12 · F5 | `5f85321` | The shared spine returns the **real wire outcome**; smart presets / feature tools say "nothing to apply" and send nothing. |
| 4 · 13 | M1 · F3 · M15 | `969ea0f` | A saved per-pixel design applies as painted from **every** door; `DesignKind` follows a stored marker. |
| 5 | F6 (app) | `79d8bd5` | A failed Save tells the user. |
| 5 | F6 (rules) · M9 | `cdc29c3` | `designs` create/update: owner **or** `staffMayReach`. Not deployed. |
| 7 | M7 · N2/N2b | `31b3615` | Twinkle gets a readable field and a readable speed. |
| 9 | M8 · N3b | `aa983df` | `ChannelDesign.grouping/spacing`, threaded through save / edit / apply, plus an off-count control. |
| 6 | M3 · F1 | `9db2433` | "Manual controls" opens the manual editor; the dead flag is gone. |
| — | (found) | `80a01f8` | The no-photo preview strip no longer cuts LEDs off. |
| 8 · 14 | M10 · N3a · M2 · F2 | `58fc871` | On/off pattern tool that **replaces**; zoom + pan + "Go to LED". |
| 11 | M13 · N5 | `b4a239d` | The "Color Picker" tab is the colour wheel and keeps its hue. |
| 10 | M14 · N3c/N3d | `615f9ef` | AI spacing phrasing, "off" ≠ black, and the clarification loop. |
| — | M15 (low) | `57d32e8` | Adjustment-sheet debounce no longer drops a slider change. |
| — | — | `43fd2fd`, `88f2969` | Live hardware test; analyzer cleanup. |
| — | HARD STOP | `339ab21` | Read-only dry-run script. |
| — | — | `9749d91` | `chore(release): bump to 2.5.10+101` ← **`build-101`** |

Every commit used an explicit pathspec; `git status` was checked after each.

### 1.1 Fix 1 — the anchor writer (root cause B)
**Audit first.** Before touching the writer I classified every reader of `startPixel` in `lib/`. They split into two camps: *channel-local* (editor selection tools, smart presets, house preview, refine) and *whole-controller* (the AI composer, the Lumina prompt context, `segmentForPixel`). Fixing the writer alone would have broken the second camp on multi-channel homes. I also read the other writers: the installer capture (`compileMarksToChannelSegments`) and the refine reflow both already produce gapless, channel-local runs — confirming channel-local is the intended base and that `start_pixel` is **derived** data (order + counts).

**The fix, as a class:**
- `recalculateStartPixels()` — one running counter **per channel** (it runs on every anchor toggle, add, reorder, delete).
- `splitConfigToPixelMapChannels` — the single place a pixelMap doc is born — re-derives `start_pixel` per channel. A no-op for a correct map; the fix for the cumulative legacy per-user config that `migrateLegacyToPixelMap` folds in.
- `globalStartOf / globalEndOf / globalPixelCount` on the config; the AI composer, the Lumina prompt and `segmentForPixel` translate through them. Device-truth channel lengths ride in-memory on the config (from `source_pixel_count`; live bus lengths in the AI pipeline) so the translation is right even when a lower channel is only partly mapped.
- `PixelMapChannel.segmentsFitChannel / needsRemapAgainst`, wired into `pixelMapStalenessProvider`. The old length-only check passed 28/28 production docs while several did not fit.
- The wizard: segments are walked across the typed channel lengths; a segment straddling two outputs is **reported to the installer**, not guessed. `source_pixel_count` is now passed (live bus length if connected, else the typed count).

**No existing production document is rewritten by this release.** A stored map changes only when its owner next edits and saves it.

### 1.2 Fix 2 — "Light It Up"
Wired to a real write rather than removed. `find_led.dart`: a solid-black base on every channel, then one red pixel on the resolved channel; **both results checked**; success reported only if the controller accepted both. It says plainly when it could not (no controller / channels not loaded / past the end of the strip / write refused), resolves a whole-controller LED number through the device's real bus ranges, and restores the captured look when the dialog closes however it closes. *Limit, stated in the code:* a look that was itself a painted picture (`frz:true`) cannot be restored from `/json/state` — the pixel buffer is not in it.

### 1.3 Fix 3 — F7, at the shared layer
`applyBaseAndSpans` awaited both writes, dropped both booleans, and returned `true`. It now returns a `SpineWriteResult` (`ok / noDevice / noChannels / baseFailed / pixelsFailed`); the bool every existing caller consumes is true **only** when the controller accepted every write, so the manual editor, the AI studio's Apply and the smart presets all inherit it without per-screen patches. It stops at the first refused paint, and sets the Now-Playing label only on success. Two things this surfaced:
- A repository that cannot paint per-pixel used to be skipped silently. It is now a failed paint — so `DemoWledRepository` was given `PerPixelWriter`, otherwise **App Review / demo sessions would have started seeing an error**.
- The fire-and-forget writers (the editor's live preview, the installer walk cursor, the refine spotlight) dropped their results too. `DeviceWriteReporter` speaks once when a failure streak starts and once when it ends.

### 1.4 Fix 4 — F3, every caller checked individually
| Caller | What it did | Now |
|---|---|---|
| **My Designs → Apply** (`apply_saved_design.dart`) | lossy `toWledPayload()` | positional design → the **same chunked spine** the editor uses |
| **Scene apply** (`applySceneProvider`) — *every saved design is also a custom scene* (`Scene.fromDesign`), which the follow-up report had not spotted | lossy | positional → spine (`applyPositionalDesignWith(ref.read, …)`; the spine now takes a `ProviderReader` so provider-side callers share the one implementation) |
| **Lumina command router** (`scene.toWledPayload()`) | lossy | inherits a now-**faithful** `toWledPayload()` |
| **`pattern_theme_selection.dart`** (selection mode → **schedules** and **Game Day**) | handed back the lossy payload | **refuses** a positional design with a plain message — see §5.1 |
| `applyDesignProvider` | lossy | 0 callers (dead); inherits the faithful payload anyway |

`toWledPayload()` for a positional design now emits `fx:0` plus a **full-coverage** `i` array per channel (gaps written black). Full coverage is what makes a single payload safe: a per-pixel write freezes the segment in the same request, so a base colour sent alongside it never renders, and any LED the `i` array skipped would keep the previous look's pixel. Bench-confirmed over a bright prior look (T19).

### 1.5 Fix 5 — F6
App: `_save()` has a real `catch`; `describeDesignSaveError` maps permission-denied, not-found (= deleted on another device), network, size. A signed-out save says so.
Rules: create/update get `|| staffMayReach(userId)`; **read and delete stay owner-only** — the save path does not need them and I widened nothing it didn't need. Verified with the read-only Rules `:test` endpoint against the local file: compiles clean, **15/15** (own-dealer staff ALLOW; cross-dealer, self-signup customer, staff read, staff delete, forged role without `dealerCode`, unauthenticated → DENY).

### 1.6 Fix 6 — F1
All four writers of the dead flag (app-bar tune icon, "open manual" in the understanding panel, a layer's edit button, "Set manually" in a clarification) now call `_openManual()`, which switches to the Manual mode of the **AI | Manual toggle — still the real entry point, unchanged and covered by a test.** The flag is deleted.

### 1.7 Fix 7 — Twinkle
Read from the **WLED v0.15.1 source** (fetched from the tag): `mode_twinkle` calls `fade_out()` toward `SEGCOLOR(1)`, and the effect's own metadata labels colour slot 2 **"Bg"**. 85 effects do. For most (Wipe, Chase, Theater, Fade) a second palette colour *is* the look, so I did **not** change them. The defect is specific to *sparkles over a field*: **17 Twinkle, 20 Sparkle, 51 Fairytwinkle, 80/81 Twinklefox/-cat, 106 Twinkleup** — verified function by function.
- `sparkle_background.dart`: when the field is indistinguishable from the sparkle colour (RGBW distance < 120 — all nine Kelvin pairs are 21–66 apart, every brightness-gradient step pair < 100; red vs green ≈ 360), `col[1]` becomes a **30 % dim of the sparkle colour** and the col-based members go out `pal:0`. (`pal:5` "Colors Only" builds the sparkle palette *from* `col[]`, so the dim field would have become half the sparkles.) Clearly different colours are left byte-for-byte alone.
- Applied where payloads are **built**, once each: `buildSelectorPayload` (tuner preview / apply / save-to-design) and one post-pass over every library card generator.
- Speed: Twinkle lights one pixel per `20 + (255 − sx) × 5` ms. Tuner default **40 → 200** (1.1 s → 0.3 s per pixel; slider ceiling raised to 250); Galaxy twinkle cards 80 → 200 and 40/80/150 → 150/200/235.
- **Found by the new card-walk test and fixed:** `_cleanForLed` pushed 6500K "Moonlight"'s second white `(238,242,255)` through its *blue-dominant* branch and emitted **saturated cyan** `[0,242,255]`. Any colour with every channel ≥ 225 now passes through as the white it is.

### 1.8 Fix 8 — Every-Nth → "On / off pattern"
Lit / Dark / From LED / To LED, remembered for the session, with a live "N lit" summary. **Paint pattern** writes both halves in one undoable step (lit LEDs painted, dark LEDs in the range cleared), so "4 off" → "6 off" yields exactly the new pattern. **Select** replaces the selection in range. It warns about the one input that yields a single LED — a range shorter than one repeat — which is the only route I found to the originally reported "collapses to one light".

### 1.9 Fix 9 — spacing on the model
`ChannelDesign.grouping / .spacing` (absent → 1 / 0, what older designs have always applied with; clamped on read). `toWledPayload` still **always asserts** `grp/spc` (#88), now from the channel. The tuner seeds them, saves them, and has a new **"Dark LEDs between" 0–10** control (the off-count could previously only be inherited from a library card, max 4). Both "save the running look" creators capture the look's banding.

### 1.10 Fix 10 — AI parser
On/off phrases are canonicalised to `spc:<on>:<off>` **before** clause splitting and colour scanning — either order, optional comma / "and" / "then" / "/", digits or number words, optional units. One step fixes three defects: off-first phrasing unrecognised; "1 on, 6 off" torn in two by the clause splitter; and "off" → **black** making the *lit* pixels black. **The "(with remainder)" loop:** an answered spacing choice is marked `SpacingRule.acceptRemainder` and the solver accepts it. Every offered option now resolves (test walks all of them); "(with remainder)" yields exactly the requested pattern.

### 1.11 Fix 11 — colour picker
Replaced with the existing `NeonColorWheel`, wrapped in a small `HsvWheelPicker` that **holds HSV** (wheel = hue + saturation, one brightness control — the pairing the other two screens already use). I did not patch the slider maths. The RGB "Slider" tab is unchanged.

### 1.12 Fix 12 — F5
`SmartPresetApplyResult.noFeatures`: nothing is sent; the user is told their map has no corners or peaks marked and offered Roofline setup. The editor's All corners / All peaks / All runs / Anchors tools say "Nothing to select — Channel N has no corners marked…". The deeper problem (production maps carry no features — the dry-run confirms **28 of 28 docs are `run`-only**) is untouched, as instructed.

### 1.13 Fix 13 — `DesignKind`
Shape-guessing was wrong **in both directions**: a one-colour or blank painted design was `effect`; and the colour editor's "save as pattern" (three single-LED groups `0–0, 1–1, 2–2`) was `perPixel`. A stored `per_pixel` marker, written by the paint editor, now decides — through `CustomDesign.isPositional`, the *same* predicate that decides how the design is sent to the lights, so what Edit opens and what Apply sends cannot disagree. Unmarked legacy docs are positional only if their groups genuinely tile the channel.

### 1.14 Fix 14 — F2, the minimal change
Not a redesign. Zoom **1×–32× with pan** on the selection strip, plus **"Go to LED"** (`57` or `12-40`) which selects, zooms and scrolls to the target. At 1× a drag selects as before; zoomed, a drag pans and press-and-hold-drag selects. LED numbers appear once cells are wide enough; the selection ring is white (it was cyan on a cyan default paint colour); the last-touched LED is shown; `onTapDown` → `onTapUp`. I used **zoom buttons rather than pinch**: a scale recogniser fights both the drag-select and the scroll in the gesture arena, and buttons are the sturdy version of the same capability. Nothing blocked a minimal fix.

---

## 2. Hardware verification (bench `192.168.1.150`)

WLED 0.15.1, 290 RGBW LEDs, seg0 0–128, seg1 128–290. The live test (`test/hardware/design_studio_101_live_test.dart`, gated on `--dart-define=RUN_HW=true`) drives the **real shipping code through the real `WledService`** and reads the rendered frame buffer over the live-view WebSocket — all 290 LEDs; **12 s / ~160 frames** for the animation claim. Numbering continues the audits' T1–T14.

| Test | Fix | Before (audits) | After (+101) |
|---|---|---|---|
| **T15** | 1 | anchors meant for 128–129 + 288–289 lit **256–257** | anchors set through the real writer on both channels → **0, 1, 126, 127, 128, 129, 288, 289** ✔ |
| **T16** | 2 | nothing sent; green "success" | **exactly LED 130**, red `[255,0,0]`; a second request leaves only LED 5; restore → all compared segment fields equal and **290/290** back to the prior look ✔ |
| **T17** | 3 | `return true` regardless | against a refusing device: spine → `baseFailed`, Find-LED → `writeFailed` ("was NOT lit"); same calls against the live bench → `ok` with the LED lit ✔ |
| **T18** | 4 | 257 black + one 33-LED red block at 257–289 | via the spine (the My Designs / scene route), after a real Firestore round-trip → **the exact 22 LEDs**, 4 colours ✔ |
| **T19** | 4 | — | `toWledPayload()` as **one 905-byte payload** over a fully lit amber roof → the exact 22 LEDs, nothing left behind ✔ |
| **T20** | 7 | **97/97 constant**, ~93 % exactly `col[1]`, 10 LEDs changed in 10 s, 5 of 132 frames | device reports `fx=[17,17]` (genuine Twinkle); bright-LED count **varies 5–29**; **34–39 frames** and **42–52 distinct LEDs** change in 12 s ✔ |
| **T21** | 8 | union of every-5th and every-7th: 41 LEDs | "4 off" then "6 off" → **exactly every 7th, 19 LEDs** ✔ |
| **T22** | 9 | every LED lit | saved "1 On 4 Off" after a Firestore round-trip → **26 + 33 lit**, every 5th ✔ |

**Runs:** 3 consecutive full passes (8/8) plus a T15–T19 subset pass (5/5). Two earlier runs were 7/8: the first because my own T16 compared `frz` across a restore that deliberately clears it (a test bug, fixed); the second is the one worth knowing about — **an intermittent failure, reported rather than hidden:** T16 failed once in its *setup* step (the amber start look), before I had added the diagnostic print, so I cannot say what it read. It did not reproduce in the five T16 executions that followed, and the Find-LED assertion itself (`lit == [130]`) passed every time it was reached. Most likely a live-view frame caught mid-crossfade; **cause not determined.**

**Restoration (same discipline as both audits):** snapshot before vs after — **96 state fields compared, 0 differing**; 290/290 black, 0 differing from baseline; `on:false`, `ps:2`, `frz:false` both segments. `presets.json` (16,585 B) and `cfg.json` (2,988 B) **SHA-256 identical** — no `psave`, no `/json/cfg`, no reboot.

**A later reading, so nobody is surprised:** at 19:07 the controller reads `on:true, bri:255, ps:10`. That is not residue from this work — it is the home's own schedule. `timers.ins` slot 0 fires **daily at 19:00 → preset 10**; the device clock read 19:07:29; uptime was ~45 h (no reboot); the changed fields match preset 10's stored contents exactly (`grp 1, spc 2, pal 5`, its two warm whites); and `presets.json` / `cfg.json` are still SHA-identical. My restoration check above was taken before 19:00 and I made no bench writes after it. I left the evening look alone on purpose — putting the lights back to OFF would have overridden the house's schedule. Lights were physically on for roughly five minutes in total across the six runs (it was after dark; this is the home controller).

**Not hardware-observable, verified by test instead:** fixes 5, 6, 10, 11, 12, 13, 14 (UI / parsing / persistence).

---

## 3. Analyze and test

| Gate | Result |
|---|---|
| `flutter analyze` — full tree, **on the bumped tree** | **0 errors · 12 warnings · 370 infos** (382 issues) |
| Baseline, same command at `3df2d24` | 0 errors · 12 warnings · 370 infos (382) — matches the +100 report |
| Issue-set diff (line numbers ignored) | **Empty in both directions.** This work adds no analyzer issue and removes none. (Nine were introduced along the way and cleaned before tagging.) |
| `flutter test` — everything except `test/hardware`, **on the bumped tree** | **3,149 passed · 0 failed · 0 skipped**, exit 0. The +107 are this pass's new tests. |
| For comparison, +100 | 3,042 passed · 0 failed |
| Firestore rules `:test` (read-only engine, local file) | compiles clean · **15/15** |

One existing test was changed, deliberately: `design_edit_tuner_test.dart`'s fx-83 fixture was two groups tiling a 10-LED channel — literally a painted picture, now correctly sent per-pixel. It was given the palette shape the colour editor really writes; its purpose is unchanged.

---

## 4. HARD STOP — dry-run reconciliation (for your review; nothing was changed)

`scripts/_dryrun_pixelmap_rebase.js` issues **one read-only collection-group query** and has **no write path**. Run 2026-09-19 against production:

**28 pixelMap docs · 21 controllers · 17 users. Affected: 7 docs · 6 installs · 6 users.** Stored `is_stale` is `false` on all 28. Every segment in every doc is type `run`.

| customer | ch | mapped / strip | class | reachable today | `start_pixel` stored → corrected |
|---|---|---|---|---|---|
| Customer A | 1 | 11 / 46 | **REBASE** (also partial) | 11/46 | `[33]` → `[0]` |
| Customer A | 2 | 12 / 8 | **REBASE + OVERFLOW** | 0/8 | `[44]` → `[0]` |
| Customer B | 0 | 22 / 22 | **REBASE** | 0/22 | `[32]` → `[0]` |
| Customer C | 1 | 41 / 41 | **REBASE** | 0/41 | `[41]` → `[0]` |
| Customer D | 1 | 40 / 40 | **REBASE** | 0/40 | `[40]` → `[0]` |
| Customer E | 1 | 45 / 44 | **REBASE + OVERFLOW** | 0/44 | `[44]` → `[0]` |
| Customer F | 0 | 168 / 128 | **REBASE + OVERFLOW** | 0/128 | `[128]` → `[0]` |

(**Customers are anonymized for publication.** This repository is public, so the user-id prefixes and the controller-id column that the working copy of this table carried have been removed; which real document each of Customer A–F refers to is recorded privately, not here. "Reachable today" = how many of that channel's LEDs the editor's map-based tools can currently address.)

**Reading it:**
- **REBASE (4 docs, 4 installs)** — purely the cumulative-offset defect. Re-deriving `start_pixel` makes the doc valid and nothing else about it changes. For three of them the tools currently reach **0** LEDs on that channel. Note Customer B: it is **channel 0** that is offset — the channel-2 segment sat first in the list — so this is not only a "channel 2+" problem.
- **REBASE + OVERFLOW (3 docs, 3 installs)** — re-basing alone does *not* make these valid: the segments describe more LEDs than the strip has. Customer F is the 168-px-on-128 map from the original audit, consistent with the wizard bug fixed here (a whole roof saved onto channel 1). Customer E looks like two channels' segments swapped (ch0 44/45, ch1 45/44). These want a remap or a human eye, not a script.
- **PARTIAL (6 docs) — not damage, not counted as affected.** The map covers part of the strip (e.g. 33 of 165); the mapped part is valid and usable. Listed so they are not mistaken for corruption.
- Three docs sit under a `staff_*` uid (never handed off to a customer); all three are OK.

**What +101 does to these documents on its own: nothing is rewritten.** They are now *flagged* (`needsRemapAgainst` → the existing "roofline changed — remap" signal) instead of silently selecting nothing, and any one of them heals itself the moment its owner next edits and saves the roofline, because the writer now produces correct values.

**Your options for the 4 REBASE docs** (I did none of them):
- **A. Leave them.** They self-heal on the owner's next roofline edit; until then the app says "remap".
- **B. A one-time script** that rewrites `start_pixel` for exactly these four docs with the corrected values above. Small, auditable, reversible from this table.
- **C. Heal-on-read** in `aggregatePixelMapChannelsToConfig` — tools work immediately with no Firestore write, and the doc is rewritten on the owner's next save. I deliberately did **not** ship this: it silently reinterprets customer data, which is the decision you asked to make yourself.

The 3 OVERFLOW docs need a remap whichever you choose.

---

## 5. Flagged — structural ambiguity, assumptions, and what I did not do

### 5.1 Per-pixel designs cannot be scheduled (structural, needs your decision)
Schedules and Game Day replay their stored payload **unattended through a WLED preset**, and a preset stores segment settings — **not the pixel buffer** (the same firmware fact behind the frozen-segment fixes). So a painted design cannot survive the trip: the old picker handed back the lossy payload and scheduled a look the user never made; a faithful payload would be `psave`d and fire as the bare base — **dark**, for a painted design. I made the picker **refuse** with a plain explanation. Real support probably means WLED API-presets carrying an `i` array (`"o":true` saves) within the JSON buffer limit — firmware-facing, needs bench research, and touches the most fragile subsystem in the app. I did not guess at it. *Side effect to know about:* the 4 AI-composed designs in production can no longer be picked for a schedule either (they could before, as a degraded fx-83 rendition).

### 5.2 Installer save — one inconsistency I left alone
After the rule is deployed, an installer's Save lands in the **customer's** designs — but `designsStreamProvider` streams the **signed-in** uid, so the installer's own My Designs list will not show it, and staff cannot read the customer's designs (read stayed owner-only on purpose). Making that coherent means either widening read access to customer designs for staff, or a product decision about whose list the installer sees. Not mine to make unattended.

### 5.3 Twinkle — what I deliberately did not change
Only palettes whose colours are *close* get the dim field. Red-on-green Twinkle still renders a green field with red sparkles, as it always has. The inverse family (21/22 Sparkle Dark / Sparkle+, where `col[1]` is the *flash*) has the mirror-image problem on near-identical whites and was **not** touched — not reported, not bench-verified. Patterns **already stored** (favourites, schedules) with the old Architectural-Twinkle payload are unchanged until re-saved; I did not add a chokepoint rewrite, to keep the blast radius small.

### 5.4 Assumptions made without you
- Wizard channel index = **position among the selected channels** (WLED numbers buses 0..n-1 in configuration order, not by output-port label).
- Twinkle field = 30 % of the sparkle colour; "same colour" threshold = RGBW distance 120. Both are named constants with the reasoning beside them.
- `REBASE` re-derivation assumes segments are a gapless ordered run within a channel — true of every writer in the codebase, and I checked each.
- `docs/BUILD_LEDGER.md` has **no +101 row**, for the same reason +100 had none: a ledger commit would move the tip past the tag.

### 5.5 Not done
- **M11** (maps must contain features) — out of scope per your item 12.
- **M15** remainder: no UI for the editor's hard-coded near-black base; dead `saveDesignProvider` / `applyDesignProvider` / `EffectSelector` and the unreachable layout sliders in `PatternAdjustmentPanel` left in place.
- AI: "warm white" still parses as pure `#FFFFFF`.
- **Remote (bridge) per-pixel** is still unverified — exercising it means driving the production relay. The truthful spine will at least now *report* a relay failure.
- The two older `test/hardware` files document `--dart-define=RUN_HW=1`, which `bool.fromEnvironment` does not accept (it needs `true`), so as written they always skip. Noted in my test's header; their files were not edited.

---

## 6. Tag, push, CI

All confirmed afterwards with `git ls-remote origin`, not assumed. No force-push anywhere — each was a plain push, which can only succeed as a fast-forward; ancestry was also checked explicitly first (`git merge-base --is-ancestor`) and both were clean.

| Ref on origin | Now | Was |
|---|---|---|
| `release/store-submission-101` | `9749d91` | (new) |
| `release/store-submission-consolidated` | `9749d91` | `3df2d24` — **fast-forward** |
| `dev/post-submission` | `9749d91` | `3df2d24` — **fast-forward** |
| `build-101` (annotated, tag object `ddbce09`) | → `9749d91` | (new) — matches `codemagic.yaml`'s `tag_patterns: 'build-*'`, the **only** CI trigger |
| `main` | `699a498` | `699a498` — **not touched** |

Before pushing to a public repo I scanned every added line of the 18 commits (59 files, +4,742 / −376) for customer id prefixes, tokens, e-mail addresses and key material: nothing. The three git-ignored Android signing inputs are untracked and were not committed.

**Version bump.** `pubspec.yaml` `2.5.10+100` → **`2.5.10+101`**; `lib/app_version.dart` `kAppVersion` likewise. **Alias verified, not assumed:** `staff_auth_telemetry.dart:58` is `const String kStaffAuthTelemetryAppVersion = kAppVersion;`, used at `:143` and `:191`. `grep` over `lib test android ios codemagic.yaml pubspec.yaml` finds no other `2.5.10+100` / `+101` literal (one mention in a test file's header comment). The bump was applied to the working tree, **the full gate was run on that exact tree**, and only then was it committed — so the bump commit is both the build point and the tested tree. (The one commit between the test run and the bump, `88f2969`, removes two unused imports from the gated-out `test/hardware` file; analyze was re-run after it.)

**Did the build actually start? Yes — confirmed.** Via the public GitHub check-runs API for the tagged commit:
`iOS Release` · **in_progress** · started **2026-09-20T00:00:24Z** · `head_sha 9749d91` · app `codemagic-ci-cd`.
It was **still in progress when this report was written**, so success is *not* confirmed — check TestFlight, or re-query
`https://api.github.com/repos/Nex-GenLED/Nex-Gen-Lumina/commits/9749d9161f94e10342aab27ce43bd69823a76816/check-runs`. The iOS build number comes from Codemagic's own counter; read it off TestFlight.

## 7. Android bundle (local only — NOT uploaded)

Matching the +100 pattern. `flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info/android`, exit 0, 257 s.

- `C:\Flutter Projects\lumina-b101-artifacts\lumina-2.5.10+101-9749d91.aab` — **68,720,308 bytes**, sha256 `26bd6d61b2de579b859acd2fb25e811776eb685ab5a51a8ffeeb5dfc00dfe8bb` (re-verified after copy), with `SHA256.txt` and the three symbol files in `debug-info-android/` alongside. **Keep the symbols** — they are required to symbolicate crashes from this build.
- Merged manifest **from the built bundle** (not pubspec): `versionCode="101"`, `versionName="2.5.10"`, `targetSdkVersion="36"`.
- `jar verified.` Signer `CN=Tyler Honeycutt, OU=Nex-Gen LED LLC …`, SHA1 `8E:4A:35:…:57:DA` — the same certificate as +100.
- Built from `9749d91` with an empty `git status` before and after. Signing inputs (`key.properties`, the keystore, `google-services.json`) were copied from the +100 worktree and are md5-identical to the canonical copies.
- **versionCode 101 is now consumed. The next Android build must be ≥ +102.**

## 8. Cleanup confirmation

| Item | State |
|---|---|
| Bench | Restored and verified — §2. Presets/config never written. |
| Production Firestore | **Read-only.** One collection-group query (the dry-run). Zero writes; no throwaway documents. |
| Firestore rules / Functions | **Nothing deployed.** Rules change is in the repo only. The Rules `:test` endpoint publishes nothing. |
| Shared checkout `C:\Flutter Projects\Lumina V 1.6` | **Never written.** Verified at the end of the pass: `HEAD` still `df6063b` (detached), the index file's SHA-1 unchanged (`05513ea4…`), and `git status` still reports the same 42 pending paths — no tracked file modified, no file added. |
| Other branches | `main` untouched. No existing branch was modified except the two fast-forwards you asked for. |
| This report | Untracked at the root of the `lumina-b101` worktree (the tagged tree stays clean, as with +100) **and** committed on the branch `docs/release-101-report-2026-09-19`. It was first held local-only, because §4 identified customer documents by id prefix and the GitHub repo is public; it was **published on 2026-09-21 after §4 was reviewed and anonymized** (customers relabelled A–F, controller-id column removed). Nothing else in the report was changed. |
