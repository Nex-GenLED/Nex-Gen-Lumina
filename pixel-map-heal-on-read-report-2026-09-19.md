# Pixel-map heal-on-read — report, 2026-09-19

**Branch:** `fix/pixelmap-heal-on-read` — **LOCAL ONLY, not pushed** (no upstream configured)
**Base:** `origin/release/store-submission-consolidated` @ `9749d91` (= `build-101`, 2.5.10+101), fetched and confirmed before branching
**Worktree:** `C:\Flutter Projects\lumina-heal-on-read` (fresh; the shared checkout and `main` were not touched)
**Version:** unchanged (2.5.10+101). No bump, no tag, no fast-forward.

Homes are referred to by letter (A–H) and by shape throughout. This repo is public; no customer uid,
controller id or address appears in this report, in the code, or in the fixtures.

---

## 0. Read this first — one thing in the brief does not match §4

The brief says to reuse §4's correction for "both the rebase case and the overshoot case", and describes
an "overshoot remap". **§4 contains no overshoot remap.** What §4 actually computed:

| §4 class | docs | the correction §4 computed | what §4 said about it |
|---|---|---|---|
| REBASE | 4 | `start_pixel` re-derived channel-local (`[33]→[0]`, `[32]→[0]`, `[41]→[0]`, `[40]→[0]`) | "makes the doc valid and nothing else about it changes" |
| REBASE + OVERFLOW | 3 | **the same re-base only** (`[44]→[0]`, `[44]→[0]`, `[128]→[0]`) | "re-basing alone does *not* make these valid … These want a remap or a human eye, not a script." |

So for the three overflow documents there is no computed per-document fix to reuse, and I did not invent
one. What I did instead, and why:

- **All 7 docs get exactly §4's correction** — the re-base — in memory.
- **`pixel_count` is never altered.** Truncating 168 → 128 (or 45 → 44, 12 → 8) would be a guess about a
  roof I cannot see — one of the three looks like two channels' segments were swapped, not over-counted.
  Worse, the +101 heal-on-save path would then **persist that guess** to Firestore the next time the owner
  saves anything. The overshoot stays in the data.
- **The overshoot is bounded where it is consumed**, which is what every per-pixel consumer already did.
  The one consumer that did not was `RooflineConfiguration.globalEndOf` — unbounded, a 168-px segment on a
  128-LED channel had a whole-controller range that ran 40 LEDs into the *next* channel. It now clamps to
  its own channel.
- **Those three docs stay flagged "needs a remap" even after an owner save** (tested) — because they still
  do. The 4 pure-REBASE docs clear on the first real save.

Net behaviour for an overflow home (shape G, 168 px mapped onto a 128-LED strip): before, the map tools
reached **0 of 128** LEDs; now they reach **128 of 128**, none of the neighbouring channel, and the remap
banner is still up. If you want something different for those three, it is a small change — tell me.

---

## 1. Step 1 — the read / consume path

```
/users/{uid}/controllers/{cid}/pixelMap/{channel}        (Firestore, one doc per channel)
  └─ RooflineConfigService.streamPixelMapChannels / loadPixelMapChannels
       └─ PixelMapChannel.fromJson                        (raw, as stored)
            ├─ currentPixelMapChannelsProvider ──► pixelMapStalenessProvider   (the "remap" flag — reads RAW)
            │                                  └─► displayChannelsProvider     (reads source_pixel_count only)
            └─ aggregatePixelMapChannelsToConfig ──► RooflineConfiguration      ◄── THE READ BOUNDARY
                 ├─ currentRooflineConfigProvider   (roofline_config_providers.dart:293 — live stream)
                 └─ RooflineConfigEditor.initialize (roofline_config_providers.dart:417 — editor load)
```

`aggregatePixelMapChannelsToConfig` has exactly two callers and every downstream consumer — the manual
editor's map tools (`featureIndices` / `anchorIndices` / `segmentIndices`), smart-preset feature
detection, `PatternComposer`, the house preview painters, Find-LED — reads the `RooflineConfiguration` it
returns. That single function is the fix point. Nothing upstream of it is changed, which is what keeps the
flag honest (§3).

---

## 2. Step 2 — the correction, in memory only

`lib/models/pixel_map_channel.dart`:

```dart
bool get storedStartPixelsAreOffset {          // is this a pre-+101 doc?
  int start = 0;
  for (final s in segments) {
    if (s.startPixel != start) return true;
    start += s.pixelCount;
  }
  return false;
}

PixelMapChannel healedForRead() => storedStartPixelsAreOffset
    ? copyWith(segments: rebaseSegmentsChannelLocal(segments))
    : this;                                     // identity for a correct doc
```

and in `aggregatePixelMapChannelsToConfig`: `segments.addAll(ch.healedForRead().segments);`

**This is §4's logic, not a re-derivation of it.** `rebaseSegmentsChannelLocal` is the function +101
already ships at the write boundary (`splitConfigToPixelMapChannels`), and it is the rule
`scripts/_dryrun_pixelmap_rebase.js` applied to produce §4's "correction" column. The test oracle is §4's
column, row for row (§4 below), so if the two ever disagreed the suite would fail.

**Why a rule and not a list of the 7 documents.** (a) App versions older than +101 are still installed and
still write offset documents — a list of 7 is stale the day it ships. (b) A list would put customer
document ids into a public repo. (c) `start_pixel` is derived data: in every writer in the codebase the
segments of a channel are a gapless ordered run, so the rule is exact, and is the identity on any correct
document.

**Two supporting changes**, both clamp-at-consumption, neither touches data:
- `RooflineConfiguration.globalEndOf` — bounded to its own channel when the channel's real length is known (§0).
- `PatternComposer` — the four `_PixelRange(globalStartOf, globalEndOf)` builders drop an empty range
  (`end < start`), which the clamp can now produce for a segment lying wholly past the end of its strip.

### The "remap" flag is intact — and slightly more truthful

`pixelMapStalenessProvider` reads the **raw** docs (`currentPixelMapChannelsProvider`), which are
deliberately left exactly as loaded. A healed-in-memory channel therefore keeps reporting "needs a remap"
until it is really re-saved. Provider-chain tests assert this directly: home D → `{0: false, 1: true}`,
home G → `{0: true, 1: false}`.

One addition: `needsRemapAgainst` now also returns true for `storedStartPixelsAreOffset`. +101's
fit-check missed **one of the seven** — home A channel 2 (11 px stored at start 33 on a 46-LED strip): the
offset range 33–43 happens to fit inside 46, so the doc looked valid while addressing the wrong 11 LEDs.
It is now flagged like the other six. The flag clears for it on the first owner save.

---

## 3. Step 3 — the 6 partial-but-valid maps

Confirmed, with one precision the brief's framing hides: **the 6 partial docs and the 7 affected docs
overlap by one.** The dry-run's own flags say 5 partial docs are class `OK` and the 6th — home A channel 2,
11 of 46 — is class `REBASE` *and* partial (§4's table labels it "REBASE (also partial)"; §4's prose
"not counted as affected" was loose about it).

- **The 5 partial-and-OK docs: no change, unaffected.** Their `start_pixel` is already channel-local, so
  `storedStartPixelsAreOffset` is false and `healedForRead()` returns **the same object** — the test
  asserts `identical(ch.healedForRead(), ch)`, not merely equality, for all 8 non-affected documents in the
  fixture set (5 partial + 3 healthy siblings). Their flag state is unchanged: a partial map is not flagged
  for being partial (home G channel 2, 128 of 162 → `false`, asserted).
- **The 6th gets §4's re-base (`[33]→[0]`) and nothing else.** Its partial-ness is not "fixed": still 11
  mapped of 46, asserted. Being partial was never the defect; addressing LEDs 33–43 instead of 0–10 was.

The `globalEndOf` clamp cannot touch a partial map either: it ends *before* its channel's last LED.

---

## 4. Step 4 — fixtures and tests

**Fixtures are the real shapes.** `kHomes` A–H in `test/models/pixel_map_heal_on_read_test.dart` are
transcribed from the dry-run's saved output (every channel of every home that has an affected or a partial
doc), as raw Firestore-shaped maps loaded through the real `PixelMapChannel.fromJson`:

| home | channels (mapped px / strip LEDs, stored `start_pixel`) | class | §4 correction |
|---|---|---|---|
| A | ch1 33/165 @0 · ch2 11/46 @33 · ch3 12/8 @44 | partial · REBASE(+partial) · REBASE+OVERFLOW | `[33]→[0]`, `[44]→[0]` |
| B | ch1 51+42 / 236 @0,51 | partial | — |
| C | ch1 22/22 @32 · ch2 32/32 @0 | REBASE (channel **1** is the offset one) | `[32]→[0]` |
| D | ch1 28+13 / 41 @0,28 · ch2 41/41 @41 | REBASE | `[41]→[0]` |
| E | ch1 40/40 @0 · ch2 40/40 @40 | REBASE | `[40]→[0]` |
| F | ch1 44/45 @0 · ch2 45/44 @44 | partial · REBASE+OVERFLOW | `[44]→[0]` |
| G | ch1 168/128 @128 · ch2 128/162 @0 | REBASE+OVERFLOW · partial | `[128]→[0]` |
| H | ch1 47/177 @0 | partial | — |

**Two things in the fixtures are not from production, stated plainly:** segment *names/ids* are synthetic
(the dry-run did not save them, and they would be customer data), and anchor *positions* — the dry-run
recorded only anchor *counts* (2 per doc, homes F and G). The fixtures use the app's default run anchors
`[0, pixelCount − 2]`. No behaviour under test depends on either.

**26 new tests, all passing.**

`test/models/pixel_map_heal_on_read_test.dart` — 23 tests:
- census: exactly 7 affected docs across 6 homes, exactly 6 partial (5 `OK` + 1 also-REBASE) — matches the dry-run;
- every corrected `start_pixel` equals §4's column; **only** `start_pixel` changes; overflow
  `pixel_count` kept (168 / 45 / 12);
- non-affected docs returned `identical`;
- **downstream consumers:** "All runs" reach per affected channel goes from `0` (or the wrong LEDs) to
  11 / 8 / 22 / 41 / 40 / 44 / 128; painting home D ch2 lands on 41 LEDs; **anchor selection** home F ch2
  `{0, 1, 43}`, home G ch1 `{0, 1}` (was nothing on the strip); **smart-preset feature detection** —
  corner/peak presets correctly yield no spans on these run-only maps, and a derived-variant corner on
  home D goes `[]` → `[[0, 40]]`; whole-controller translation on home G: ch1 `[0, 127]`, ch2 `[128, 255]`
  (unclamped it was `[0, 167]`, overlapping channel 2);
- flag: all 7 still `needsRemapAgainst`; after a save the 4 REBASE docs clear and the 3 OVERFLOW docs stay flagged;
- **the original data is never mutated** — a dedicated test serialises the raw fixture maps *and* the
  loaded stored-shape docs, runs every consumer plus a second aggregate and an explicit `healedForRead()`
  over the same objects, and requires both serialisations to be unchanged; healing is idempotent.

`test/features/design/pixel_map_heal_on_read_provider_test.dart` — 3 tests through the **real provider
chain and the real `RooflineConfigService`** over a fake Firestore seeded with shapes D and G:
- the working model is healed; the raw stream is *not*; the staleness flag is as in §2;
- the editor's `initialize()` heals the same way;
- **a canonical dump of every stored doc is byte-identical before and after** all of the above —
  *reading never writes*;
- heal-on-**save** still does the persisting: an owner pressing Save writes `start_pixel: 0`, and only then
  does the flag clear.

---

## 5. Step 5 — analyze, test, bench

**`flutter analyze`** — 0 errors / 12 warnings / 370 infos = 382 issues. Issue-set diff against the
pre-+101 baseline *and* against `build-101`: **0 new, 0 removed**. The new hardware test file analyzes clean.

**`flutter test`, full suite** (`test/bench test/features test/models test/screens test/services test/unit
test/utils test/widgets`) — **3,175 passed, 0 failed, 0 skipped.** `build-101` was 3,149; the difference is
exactly the 26 new tests. (Run twice: 3,174 with the first 25 tests; then again at 3,175 after writing this
report surfaced the partial/REBASE overlap in §3 and I added one test to pin it down. Test-only change.)

**Bench — 192.168.1.150**, hardware-observable behaviour *is* affected (which physical LEDs the map tools
address), so it was verified. `test/hardware/pixel_map_heal_on_read_live_test.dart`, gated
(`--dart-define=RUN_HW=true`; skipped in the normal suite). **Synthetic fixtures only** — shapes D and G as
plain numbers; no production document was loaded, and Firestore is not involved at all. Each case drives the
same consumer ("All runs" → paint red → the real apply spine → the real `WledService`) twice and reads
the rendered frame buffer back over the live-view WebSocket:

| case | segments as STORED | as the app now loads them |
|---|---|---|
| T23 shape D, channel 2 (41 px stored @41) | **41 lit: 169–209** — the wrong 41 LEDs | **41 lit: 128–168** — the first 41 of channel 2 |
| T24 shape G, channel 1 (168 px stored @128, 128-LED strip) | **(none)** — dark | **128 lit: 0–127** — all of channel 1, not one LED of channel 2 |

Both matched the prediction exactly; 2/2 passed. (On the real home D the strip is 41 LEDs, so the
as-stored indices 41–81 fall off the end and light nothing — §4's "0/41". The bench's channel 2 is 162
long, so there the same indices exist and light the wrong place. Same defect, both faces.)

**Bench restored and verified.** Pre-test snapshot 21:03 CDT: on, bri 255, no preset, both segments a
warm-white `grp 1 / spc 4` look, 59/290 lit. After the test: **0 of 96 state fields differ, 0 of 290 LEDs
differ, `presets.json` and `cfg.json` byte-identical** (16,585 B / 2,988 B, same SHA-256). The test writes
`/json/state` only — never a preset, never `/json/cfg`.

---

## 6. Confirmation — no production Firestore write occurred

- **No production Firestore access of any kind happened in this task — no write, and no read either.** The
  fixture shapes came from the file the 2026-09-19 read-only dry-run had already saved locally. No script
  was run against the project; no admin SDK, no REST call, no rules call, no deploy.
- **The fix cannot write.** `healedForRead` is a pure function on an immutable model and
  `aggregatePixelMapChannelsToConfig` is a pure function; neither holds a Firestore reference. I audited
  every write path to `pixelMap`: `savePixelMap` has four callers, all user-initiated saves (refine
  screen, editor Save, setup wizard, installer capture); `updateChannelStaleFlags` has **zero** callers.
  There is no write-on-load. (Pre-existing and unchanged: `migrateLegacyToPixelMap` writes only when a
  controller has *no* pixelMap docs at all — none of the 7 qualify, they are pixelMap docs.)
- **Proven, not just argued:** the provider-chain tests dump the stored docs before and after a full
  load + editor initialize and require byte equality.
- The only "Firestore" touched anywhere is `FakeFirebaseFirestore`, in-process, in tests.

---

## 7. What I did not do

- Did **not** push this branch, or anything else. Did not tag, bump, or fast-forward. Remote refs verified
  unchanged at the end: `release/store-submission-consolidated` `9749d91`, `dev/post-submission` `9749d91`,
  `main` `699a498`, `build-101` → `9749d91`; `fix/pixelmap-heal-on-read` does not exist on origin.
- Did not touch `main`. Did not touch the shared checkout — verified: HEAD `df6063b`, index SHA-1
  `05513ea4…`, 42 pending paths, all as before.
- Did not change any stored document's meaning: no `pixel_count` truncation, no anchor rewriting, no
  stale-flag write.
- Did not hide the remap indicator; one more affected channel now shows it (§2).
- The 7 production documents are still stale in Firestore. That remains your decision (§4 of the +101
  report lists the options); with this fix, doing nothing is now a safe option for the 4 REBASE docs, and
  the 3 OVERFLOW homes still need a real remap.

## 8. Files

| file | change |
|---|---|
| `lib/models/pixel_map_channel.dart` | `storedStartPixelsAreOffset`, `healedForRead()`, flag includes offset docs, heal at the read boundary |
| `lib/models/roofline_configuration.dart` | `globalEndOf` bounded to its channel |
| `lib/features/design/services/pattern_composer.dart` | drop empty ranges |
| `test/models/pixel_map_heal_on_read_test.dart` | 23 tests, real shapes A–H |
| `test/features/design/pixel_map_heal_on_read_provider_test.dart` | 3 tests, real provider chain, read-never-writes |
| `test/hardware/pixel_map_heal_on_read_live_test.dart` | gated bench test T23 / T24 |
| `pixel-map-heal-on-read-report-2026-09-19.md` | this report |
