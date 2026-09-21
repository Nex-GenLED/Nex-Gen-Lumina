# Static / per-pixel favorites — Report (2026-09-21)

**Branch:** `feat/static-per-pixel-favorites` — local only, **not pushed, not tagged, version not bumped.**
**Base:** `origin/release/store-submission-consolidated` @ **`64fa5af`** (`chore(release): bump to 2.5.10+103`), fetched at start. Confirmed to contain this week's Save-to-Device / favorites fix: `fix/save-to-my-designs-and-favorites` (`aaa4ac1`) is an ancestor, via merge `c2b013a`. Isolated worktree; `main` and the shared checkout were not touched. The branch's auto-set upstream (it pointed at the consolidated remote) was unset so a bare `git push` from it cannot land there.
**Firestore:** production project, live ruleset **`f7b0658e`** — byte-identical to `firestore.rules` at this tip (compared, §5). **The rules were not changed.**

| Commit | What |
|---|---|
| `6999f4d` | `feat(favorites)` — a per-pixel favorite: stored as a My Designs design, applied through the chunked spine |
| `1ac9eea` | `feat(pattern-editor)` — the heart works in Static; My Favorites applies through the one favorite applier |
| `cfcbf09` | `test(hardware)` — Static favorite round trip, T27–T29 (RUN_HW-gated) |

Every commit used explicit pathspecs. Each stands on its own: `6999f4d` was checked out separately (analyzer clean on the favorites tree, 44/44 tests); the tip is the full-suite run in §6.

## Evidence labels

**HW** = read off the bench. **DATA** = the live ruleset / production Firestore, exercised with a **client** credential. **CODE** = the real production classes executed in tests. **NOT VERIFIED** = stated wherever it applies.

---

## 0. Read this first: the bench round trip was NOT run

**Step 3's bench verification is not done. Nothing in this report is HW evidence.**

The machine was not on the bench's network at any point in this session. It was tethered to a phone (`172.20.10.5`, the iPhone-hotspot subnet, over the USB Ethernet adapter) with Wi-Fi disconnected. `192.168.1.150` and the bridge at `.96` both timed out (ping 100 % loss; `curl` connect timeout). The Wi-Fi networks in range were a grocery store and a hotel at 12:12, and a completely different residential set at 12:34 — the machine was in transit. The home SSID was never visible, so there was nothing to join. The exact-pixel check reads the 290-LED frame buffer over the controller's LAN WebSocket, which the cloud relay does not carry, so there was no remote way to do it either.

I did not substitute a simulation and call it a bench result. What exists instead is labelled **CODE** throughout, and §4 says exactly what it does and does not prove.

**To finish it, on the home LAN** (≈1 minute of lights-on, `/json/state` writes only, look restored by the test's teardown):

```bash
D=<an empty dir>
# 1. light the bench as the editor does, record the frame, export the heart's document
flutter test test/hardware/static_favorite_live_test.dart \
  --dart-define=RUN_HW=true --dart-define=FAV_RT_DIR=$D --dart-define=FAV_RT_PHASE=export
# 2. the client-credential Firestore leg (scratchpad script; see §5) -> $D/from_firestore_static_fav.json
node probe_static_fav_live.js run $D firestore.rules && node probe_static_fav_live.js cleanup
# 3. back out, apply from My Favorites, compare the frame buffer
flutter test test/hardware/static_favorite_live_test.dart \
  --dart-define=RUN_HW=true --dart-define=FAV_RT_DIR=$D --dart-define=FAV_RT_PHASE=import
```

The probe is a scratch script, kept out of the repo as last week's was (it names the local admin-key path): `%LOCALAPPDATA%\Temp\claude\c--Flutter-Projects-Lumina-V-1-6\b41f91c5-3c93-45bf-8fe1-bb04772e5f88\scratchpad\probe_static_fav_live.js`. It already ran once today without the bench (§5); step 2 re-runs it only so the import phase reads a document written in the same pass.

T29 passes only if the applied frame differs from the editor's live frame in **0 of 290** LEDs, differs from the scramble in >250, arrived as ≥3 requests with every paint under 6 KB, and the device reports `bri:180` after being knocked to 90. Until that runs, **treat this branch as unverified on hardware** and do not converge it on the strength of this report alone.

---

## 1. Step 1 — the state I found

**Where the heart declined.** `lib/features/wled/edit_pattern_screen.dart:874` passed `FavoriteHeartButton` an `unavailableMessage` whenever `_pattern.effectId == 0`:

> *"This mode is stored LED by LED — tap SAVE to keep it in My Designs."*

`lib/widgets/favorite_heart_button.dart:84` showed it for 5 s and returned before writing. That parameter had exactly one caller.

**The chunked apply path.** `lib/features/design/manual_editor/design_apply.dart`: `applyPositionalDesignWith(read, design)` → `applyBaseAndSpansWith` — one solid base write through the normal chokepoint, then `PerPixelWriter.applyPerPixel` per channel, which range-compresses and posts size-bounded `i` chunks (`per_pixel.dart`, 224 LEDs/chunk, bypassing `applyJson`'s 4,096 B ceiling). My Designs reaches it from `applySavedDesign` whenever `design.isPositional`. The editor's own Static live preview already uses it (`_sendStatic`).

**The single-message path that had to go.** Not in the grid widget — inline in `lib/features/dashboard/wled_dashboard_page.dart:1337`: `applyChannelFilter(favorite.patternData)` → `repo.applyJson`.

**The favorites document shape.** `favorite_doc.dart` — `pattern_name`, `added_at`, `pattern_data` (a `jsonEncode`d string), `usage_count`, `auto_added`, `last_used`. **It needed no extending.** `pattern_data` is opaque to Firestore and to the rule; last week's probe had already shown the rule accepts a 290-LED document. What was missing was never somewhere to *put* per-pixel data — it was an apply path that could send it.

---

## 2. What was reused vs. newly built

### Reused, unchanged

| | |
|---|---|
| **The data shape** | `CustomDesign` — a Static favorite stores `CustomDesign.toFirestore()`, the map a My Designs save writes, and reads it back with `CustomDesign.fromFirestoreData`. The only difference is that the two `Timestamp` fields are dropped (JSON cannot hold them; the reader already defaults both). A test asserts the embedded map is key-for-key and value-for-value what a save writes. **No second per-pixel shape exists.** |
| **The design builder** | `customDesignFromEditablePattern` — the function SAVE and `_sendStatic` already call. The heart calls it with the same arguments, so what is favorited is what is on the lights and what SAVE would keep, by construction. |
| **The apply path** | `applyPositionalDesignWith` — called, not copied. A test sends the same pattern through My Designs' call and through the favorites applier and asserts the base write and the per-channel spans are **identical**. |
| **Brightness restore** | `CustomDesign.statesBrightness` (the `pattern-editor` tag) — a Static favorite saved at 180 comes back at 180, exactly as a saved Static design does. |
| **The favorites document + rule** | `buildFavoriteCreateData` / `buildFavoriteRefreshData` / `writeFavorite`, untouched. No new field, no rule change. |

### Newly built

| File | What |
|---|---|
| `lib/features/favorites/favorite_design_payload.dart` | `buildPerPixelFavoritePayload(design)` / `perPixelDesignOfFavorite(payload)` — puts the design under `lumina_design` inside the payload and gets it back (never throws). `FavoriteNotSavable` — a builder's way to tell the heart *why* nothing was stored. |
| `lib/features/favorites/favorite_apply.dart` | `applyFavoritePayloadWith(read, payload)` — **the one routine that decides how a favorite reaches the lights.** Per-pixel → the spine; everything else → one channel-filtered `applyJson`, as before. Takes a `ProviderReader`, so a provider-side caller (geofence) can share it. |
| `edit_pattern_screen.dart` | `_favoritePayload()` — Animated: the WLED payload, unchanged. Static: the per-pixel favorite. **The decline and its message are deleted.** |
| `favorite_heart_button.dart` | `unavailableMessage` **removed** (dead once its one caller went). A `FavoriteNotSavable` is shown as written. |
| `wled_dashboard_page.dart` | The My Favorites tap calls the applier instead of inlining the single-message send. Preview, label, usage tracking and toasts are unchanged. |

**One thing the heart still refuses, with a reason:** Static with no channel census (not connected). There is no picture to store without channel lengths — SAVE refuses the same case for the same reason. Message: *"Connect to your lights to favorite this pattern — it is stored LED by LED, so the app needs your channel lengths. Nothing was saved."*

### 2.1 Why the design rides *inside* `pattern_data`, not in a sibling field

This is the one real design decision, and it came out of the audit rather than preference. A favorite's payload does not stay in the favorites document — **it travels**:

1. Applying a favorite logs the payload to `pattern_usage` (`trackWledPayload` → `'wled': jsonEncode(payload)`).
2. The **habit learner** copies that logged string verbatim into a *new* auto-added favorite's `pattern_data` (`habit_learner.dart:228`).
3. The **geofence trigger** reads `pattern_data` on its own and applies it.

A sibling field would be dropped at hop 1, and hop 2 would mint a favorite that looks saved and lights nothing — the exact lie last week's pass removed. Inside the payload, the picture survives every hop; a test walks the habit-learner hop and gets all 290 LEDs back. It also meant **zero changes to either `FavoritePattern` model** — which matters, because `favorites_providers.dart` has uncommitted edits in a parallel session (§7).

The payload's top-level `on`/`bri`/`seg` is a **summary** (`fx:0`, up to three distinct colours): it is what the My Favorites card draws its gradient from and what usage analytics reads, both unchanged. A consumer that does not know about `lumina_design` and POSTs the map raw gets an **honest refusal** — it is 16 KB, four times the ceiling — not a success toast over dark lights.

---

## 3. "Fix the class": every site that holds a favorite's payload

The class is *"a favorite's stored payload is sent as one message."* Enumerated across `lib/`:

| Site | Does what | State |
|---|---|---|
| Dashboard My Favorites tap (`wled_dashboard_page.dart`) | applies | **Fixed** — through `applyFavoritePayloadWith` |
| Pattern Editor heart | writes | **Fixed** — Static now stores a per-pixel favorite |
| "Save to Favorites" (`pattern_category_detail.dart`) | writes | Not in the class — that screen has no per-LED mode; its payload is a few hundred bytes |
| Brand design generator | writes | Not in the class — effect payloads only |
| Habit learner auto-favorites | writes (copies the usage log) | **Covered by construction** — copies the payload whole, so its copy is re-appliable (§2.1; tested) |
| My Favorites card gradient / usage analytics | read `seg[0].col`, `fx` | **Unchanged and working** — that is what the summary `seg` is for |
| Now Playing name match, AI intent classifier, variety profile | read the *name* only | Not in the class |
| Explore "Recent Patterns" | — | Not favorites at all (usage events → `GradientPattern`); checked because the provider shares a name |
| **Geofence trigger** (`geofence_monitor.dart`) | applies `pattern_data` via `applyToDevice` → raw `applyJson` | **OPEN — deliberately not touched. See below.** |

**Geofence is the one member I did not fix, and you should know why.** It is **dormant at this tip**: it looks favorites up by a camelCase `name` field that no document has, so it finds none and no Static favorite can reach it today. But a parallel session (`fix/geofence-favorites-lookup`) has **uncommitted edits in `geofence_monitor.dart`, `geofence_setup_screen.dart` and `favorites_providers.dart`** that revive exactly that lookup. Editing those files from here would have collided with live work in another window, so I stayed out of all three.

When that branch lands, a Static favorite picked as a geofence action would be refused by size at both of its `applyJson` attempts — **the lights would do nothing and the "Welcome Home" notification would still fire.** The fix is one call: `applyFavoritePayloadWith(ref.read, payload)` in place of `applyToDevice` + the bare `applyJson` fallback. It takes a `ProviderReader` for exactly this reason. **This must be resolved at convergence, whichever branch merges second.**

I considered making the fix one level down, in `WledNotifier.applyToDevice`, which would have covered geofence without touching it. It has 24 callers (AI, voice, audio, scenes), none of which hold favorites; teaching a shared chokepoint about one feature's payload to dodge a merge conflict is the wrong trade.

---

## 4. Verification short of the bench (**CODE** — not HW)

All of this runs the real production classes. None of it involves a controller.

| What | Result |
|---|---|
| Round trip: real writer → `pattern_data` string → real decoder → design | **290/290 LEDs exact**, both channels (128 + 162); spans identical to the source design's |
| Through My Designs' call vs. through the favorites applier, same pattern | base write and per-channel spans **identical** |
| **Real `WledService`, mock host** — records each per-pixel request body instead of posting it; the bodies' `i` arrays rebuilt into a 290-LED buffer | **0/290 differ** from the picture the editor painted |
| …the same, starting from **the document real Firestore returned** (§5), parsed by the My Favorites grid's own model | **0/290 differ**; `bri` 180 |
| The old path, under the production size rule | refused (> 4,096 B) — the bug, reproduced |
| The new payload POSTed raw by an unaware consumer | refused by size — fails loudly |
| A refused paint | reported as **failed**, not "Applied" |
| Animated favorite | still exactly one channel-filtered `applyJson`; the caller previews the payload *as sent* |
| A channel outside the effective set | not painted (same semantics as My Designs) |
| The real Edit Pattern screen, Static, heart tapped | writes a per-pixel favorite equal to what SAVE would store; decline text gone |

**Does the chunking engage? Yes — and here is precisely what that means on this bench.** Worst case for size was used deliberately: red/gold/white alternating every LED, so no two neighbours match and **nothing range-compresses** (128 and 162 colour runs for 128 and 162 LEDs).

| | Requests | Size |
|---|---|---|
| Old: one message, both channels | 1 | **10,891 B** (measured now; identical to T22 on the bench last week) — **refused**, ceiling 4,096 B |
| New: base + one paint per channel | **3** | base **169 B** (before the transport’s normalisation) · channel 1 **2,372 B** · channel 2 **3,019 B** |

So the favorite arrives as three requests, each under WLED's ~6 KB JSON buffer, instead of one that is refused. What the bench **cannot** show is a split *within* a channel: the chunker splits at 224 LEDs and the bench's channels are 128 and 162. That case is covered by a unit test only — a 300-LED channel splits **224 + 76**, both under 6 KB. I would rather say that than let "chunking verified" imply more than it will.

**Still NOT VERIFIED, and will remain so after the bench run:** anything inside the running app (there is no handset), and **remote / bridge mode** — a Static favorite there is base + one relayed command per chunk, and at relay latency that will be slow. Same caveat My Designs carries.

---

## 5. Live-rule verification (**DATA**, client credential) — 22 / 22

Same standard as last week's favorites fix: the admin SDK only mints custom tokens, fetches the ruleset read-only, and cleans up; **every assertion is made with an Identity Toolkit ID token** over Firestore REST. The documents were exported from the **real Dart writers** (`buildFavoriteCreateData` over `buildPerPixelFavoritePayload`), and sent as the SDK sends them — one write: fields + server-value transforms.

**Preconditions:** live ruleset `f7b0658e` (released 2026-09-20T01:14Z) is **byte-identical** to this branch's `firestore.rules` (sha `821fdfce3f1d`, 120,688 B both), and the favorites block itself matches. So what was tested is what ships.

**Subject:** the 290-LED / 2-channel worst-case Static favorite — `pattern_data` = **16,164 B**.

| # | Case | Expected | Got |
|---|---|---|---|
| 1–2 | live ruleset ≡ branch rules; favorites block ≡ | — | ✔ ✔ |
| 3 | **Static favorite created from nothing** (empty heart tapped in Static) → create | ALLOW | **200** |
| 4 | the same card hearted while *Animated* → create | ALLOW | 200 |
| 5 | **…then re-hearted as Static** — the writer's refresh, an **update** of the same doc id | ALLOW | **200** |
| 6–9 | owner reads both back; each: `pattern_name` string, `added_at` a **server** timestamp, `pattern_data` decodes to a per-pixel design (128 + 162 LEDs, `bri` 180, no `seg[].i`) | ALLOW / — | 200 ✔ 200 ✔ |
| 10 | the My Favorites grid's own query (`orderBy added_at desc`) returns both | — | ✔ |
| 11 | usage bump on apply (`usage_count` increment + `last_used`) → update | ALLOW | 200 |
| 12 | re-sending the **create** doc over an existing Static favorite | DENY | 403 |
| 13 | update renaming `pattern_name` | DENY | 403 |
| 14 | Static create missing `added_at` | DENY | 403 |
| 15 | Static create missing `pattern_name` | DENY | 403 |
| 16–19 | another signed-in user: create / **overwrite** / read / delete | DENY | 403 ×4 |
| 20 | unauthenticated Static create | DENY | 403 |
| 21–22 | owner un-hearts both | ALLOW | 200 200 |

Row 5 is the case I added beyond last week's set, because it is the realistic one: a favorite is keyed by the *source card's* id, so a card already hearted as Animated and then favorited as Static is an **update**, not a create — and the update clause freezes `pattern_name` and `added_at`. The writer's refresh touches neither; it passes.

Rows 12–20 are the "nothing was loosened" half: the rule file is unchanged and every validation it performs still bites on a Static document.

**"Failed to save favorite" will not appear for a Static favorite** — established at the rule and in code. **NOT VERIFIED in a running app.**

---

## 6. Test and analyze results

| | Baseline `64fa5af` | This branch | Δ |
|---|---|---|---|
| `flutter analyze` errors / warnings / infos | 0 / 12 / 370 (382) | **0 / 12 / 370 (382)** | **issue set identical** — diffed line by line, positions stripped: nothing only-in-baseline, nothing only-in-branch |
| `flutter test` passed | 3,253 | **3,276** | +23 |
| skipped | 19 | **24** | +5 — the new `RUN_HW`-gated hardware tests |
| failed | 0 | **0** | — |

The baseline was **measured**, in a throwaway detached worktree at `64fa5af` — not carried over from last week's report, whose tip this is not.

Added: `favorite_design_payload_test` 10 · `favorite_apply_test` 9 · `edit_pattern_static_favorite_test` 4 (pumps the real screen). `favorites_save_buttons_test`: the two tests that asserted the decline are replaced by two asserting its successor (a builder that cannot build shows *its* reason and writes nothing; a filled heart still un-fills) — net 0. Skipped +5 = the hardware file's five gated tests.

---

## 7. Cleanup, restoration, and things for the convergence

| Item | State |
|---|---|
| **Bench** | **Never reached. Nothing was written to it** — no state, no preset, no cfg. There is nothing to restore. |
| **Production Firestore — real data** | **Unchanged.** Every real `favorites` document fingerprinted (path + updateTime) before and after: **11 docs / 8 users, sha256 `3c9a6b1631f91948` — identical.** |
| **Production Firestore — throwaway data** | Two Auth users (`zz_rules_probe_staticfav_{owner,other}_0921`), two favorites. Both favorites were deleted by their owner inside the probe; cleanup removed the two Auth users. **Residue sweep: 0.** No `users/{uid}` doc was ever created, so `assignReferralCode` never fired; nothing triggers on `favorites` (re-checked: the only reference in `functions/` is the account-purge sweep). |
| **Rules** | Not deployed, not edited. Live `f7b0658e` before and after. |
| **Worktrees** | The branch worktree is clean. The throwaway detached worktree used for the measured baseline (`wt-baseline` @ `64fa5af`) was removed at the end of the session. One scratch test written to measure payload sizes was deleted before any commit. |
| **Git** | 3 commits + this report, local only. Nothing pushed, tagged or bumped. |

**Parallel sessions to reconcile at convergence:**

- **`fix/geofence-favorites-lookup`** — see §3. Overlapping *files*: none with this branch (I stayed out of all three of theirs). Overlapping *behaviour*: their trigger must call `applyFavoritePayloadWith`.
- **`fix/brightness-restore-consistency`** (at `64fa5af`) — I did not read its contents. If it changes how `statesBrightness` or the spine's `brightness` argument work, a Static favorite inherits that, since it restores brightness through exactly that path. Worth one look when both are in.

**Found, not fixed — outside this change:** `lib/features/autopilot/learning_providers.dart:295` casts the usage log's `wled` field `as Map<String, dynamic>?`. The writer has always stored it as a **`jsonEncode`d string** (`user_service.dart:338`). That cast throws on any usage event carrying a payload — the same String-vs-Map break last week's pass found in both favorites readers — and would blank whatever streams from that provider (Explore's "Recent Patterns" is the likely casualty). **Read from the code, not demonstrated at runtime.** It is independent of this branch (payload size is irrelevant to it), which is why I left it.

---

## 8. Decisions waiting on you

1. **Run the bench phases** (§0) before this converges. That is the missing third of Step 3, and I would not merge without it.
2. **Geofence** (§3) — who adopts the applier: this branch after theirs lands, or theirs after this one.
3. **One heart, one id** is now slightly more visible. A Static Chiefs and an Animated Chiefs are the *same* favorite (keyed by source-card id), so favoriting one replaces the other's stored look. Unchanged from last week, and the rule handles it (row 5) — but Static used to be unreachable, so nobody could hit it. SAVE remains the home for keeping variations side by side.
4. **Static favorites can't be scheduled or used for Game Day** — same firmware fact as Static designs (a WLED preset cannot hold a pixel buffer). Nothing offers a favorite as a schedule source today; flagging it before something does.

## 9. For project memory

- A **per-pixel favorite** stores a `CustomDesign` under `lumina_design` **inside** `pattern_data`; the doc shape and rule are unchanged. It rides inside the payload because the payload travels: usage log → habit learner → auto-favorite, and geofence.
- **Anything that re-applies a favorite must call `applyFavoritePayloadWith`.** A raw `applyJson` of a Static favorite is refused by size (16 KB vs 4 KB). Geofence does not yet — dormant at `64fa5af`, live once `fix/geofence-favorites-lookup` lands.
- The bench's channels (128 / 162) each fit one 224-LED chunk: on this bench "chunked" means base + one paint per channel (3 requests). An intra-channel split needs a channel > 224 LEDs and can only be shown in a unit test here.
- **T27–T29 were written but never run** — the machine was off the bench LAN all session.
- `learning_providers.dart:295` casts the usage log's string `wled` field as a Map (unfixed, undemonstrated).
