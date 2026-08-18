# PARTICIPATION RE-ENTRY — #95's second half

**Filed 2026-08-18, against the +80 field build. Completes the #95 story:
`c204577` un-gated per-channel POWER but left SELECTION gated on
participation, and there was no user path back INTO participation.**

---

## 1. The defect, stated

Participation is the OUTER gate on every design apply
(`effectiveChannelIdsProvider`, zone_providers.dart). Before this change, every
writer of participation was a **re-derivation** of the same pure function:

```dart
resolveParticipatingChannels(explicit: null, segments: …, allDeviceChannelIds: …)
```

`explicit` was provably `null` at every shipped call site — the per-config /
per-member `participatingChannelIndices` fields are dead schema, written by no
UI. So participation was **derived-only**, and its exclusion branch —

> channels with segments but NO `isPrimary` segment are EXCLUDED

— depended entirely on `is_primary` in the roofline `pixelMap` docs. **No
shipped UI can set `is_primary` false, and none can set it back to true**
(`roofline_editor.dart:690` hardcodes `isPrimary: true`;
`RooflineSegment.isPrimary` defaults true).

A channel that entered the excluded state therefore could not leave it:

| candidate way back | why it failed |
|---|---|
| Game Day resolve | re-derives — same answer |
| Sync engine resolve | re-derives — same answer |
| Sync teardown → `null` | transient; the next resolve re-derives |
| **Reconciler** | clears only when cache ≠ **the same recompute**. Cache `[0]` == recompute `[0]` ⇒ never stale ⇒ **never cleared** |
| Healer facts publish | Firestore only; the app UI never reads that field |
| `explicit` override | **dead schema — no UI wrote it** |
| Re-running the roofline wizard | works, but is unlabelled, undiscoverable, and destroys the map to fix a channel flag |

**And "All Zones" was a lie.** `effectiveChannelIdsProvider` intersects with
participation even in the `filter == null` case, so an apply labelled "All
Zones" emitted **no `seg` at all** for the excluded channel — it kept its
previous design, with no warning and a cheerful `Applied: <design>` afterwards.

### The bench instance

`users/wrQRUUKyXyc0deyuu0ORS6wsovO2/controllers/192_168_1_150/pixelMap/1` was
hand-written on **2026-08-12** (BUILD_LEDGER §7.2d Leg B) with
`is_primary: false`, deliberately, to make the rig discriminating for the
roofline leg. That single durable field produced `participating_channels: [0]`
and locked channel 1 out of every design apply from that day forward.

**The 8/18-deselection hypothesis is disproven.** `selectedChannelIdsProvider`
is a plain in-memory `StateProvider`; `_toggleChannel` writes nothing else. No
apply-time deselection has ever written durable participation. The category
error was one level up: **participation was inferred from geometry the user
cannot edit, and never stated by the user at all.**

---

## 2. What shipped

### Item 1 — explicit include-back, with provenance ✅

- **`bg_participation_override`** (SharedPreferences, alongside the cache so the
  background isolate reaches the same answer): the user's EXPLICIT set.
  `saveParticipationOverride` / `getParticipationOverride` /
  `peekParticipationOverride`, plus `participationOverrideNotifier` for
  reactivity. `[]` normalises to `null` — a UI-reachable "nothing is in my
  shows" would rebuild the lockout.
- **`participationOverrideProvider`**, and `participatingChannelIdsProvider`
  now prefers the override over the derived cache, so an include-back lands on
  the next frame rather than waiting for a resolve.
- **Every resolve site passes it as `explicit`** — Game Day (live + background
  persistence), sync engine, and the healer. The healer **awaits** it rather
  than peeking: it publishes on every LAN connect, and a cold peek there would
  write a derived set over a stated one and re-exclude the channel server-side.
- **Provenance flag = the override's existence.** The reconciler branches on it
  *before* the staleness predicate, routing override-sourced state to
  `pruneOverrideToDevice` (prune to channels the device still reports; drop the
  override entirely if none survive) instead of clearing it. This closes the
  `TODO(participation-pickers)` in `participation_reconciler.dart` — without it,
  the next launch would have silently undone every include-back.
- **`participating_channels_explicit`** published alongside the set, and the
  explicit-source exemption in `prepareParticipationFacts` that
  `participation_denormalizer.dart`'s own TODO called for: an explicit set does
  not consume the bus list, so an unknown device shape must not suppress it.
- **UI**: tapping a dimmed chip (previously `onTap: null` — a dead control)
  opens a sheet that explains the state, names where it came from, and offers
  **Include in Shows**. A **Reset** footer appears whenever an override is in
  force, so this is not a one-way door in the opposite direction either.

### Found while building this: a load-vs-write race in BOTH caches ✅

`getParticipationOverride` and `getCachedParticipatingChannels` both did:

```dart
if (!loaded) { value = await readDisk(); loaded = true; }
```

Their writers set the in-memory value **synchronously** and mark the cache
loaded *before* the disk write completes — deliberately, so an apply on the
next frame sees the new value. So a load already in flight would resume after
the write, read the **pre-write bytes**, and clobber it.

Concretely: the dashboard warms the override on first build; a user taps
*Include in Shows* moments later; the in-flight load resumes and silently
re-excludes the channel. Caught by
`participation_override_test.dart` → *"override outranks a derived cache that
excludes ch1"*, which is the only test that reads the provider **before**
writing — the ordering that makes the race reachable.

Both now re-check the flag after the await: a write is always newer than a read
that started before it, so the write wins. **The cache-side instance is
pre-existing and shipped** — it is the same defect in the path the U1 gate
reads on every apply, and it would have discarded a just-completed resolve.

### Deliberate trade: the healer swallows an override-read failure

First cut let the override read sit inside the healer's existing catch. That
demoted the whole participation leg to `inputsFailed` whenever
`SharedPreferences.getInstance()` threw — which is what 7 red tests in
`controller_defaults_healer_publish_test.dart` were reporting (that file builds
a healer without an initialised binding, so the read threw every time).

Fixed in the healer, not the tests, because the tests were describing a real
production hazard: **a prefs failure would have stopped participation
publishing fleet-wide, on every connect, for every account** — trading a silent
global stop for an overlay that is null for almost everyone.

The read is now wrapped and swallowed, with a log line. The justification is
that the dispositions describe the **inputs participation is derived from** —
the bus list and the roofline — and the override is an authority *overlay*, not
one of them. It is also self-healing: the memo dedups on VALUE, so the next
connect with a working read republishes the override.

**The accepted cost:** with prefs broken, the healer publishes the derived set
over a user's explicit one, and a server-side fire would re-exclude their
channel until the next healthy connect. On-device behaviour is unaffected (the
dashboard reads the in-memory notifier). Revisit if
`participating_channels_explicit` ever shows this happening.

### Item 3 — the header tells the truth ✅

`All Zones` becomes `All Zones · 1 of 2 in shows` whenever participation
narrows. The count is computed from the same set the apply path acts on.

### Item 2 — NOT IMPLEMENTED (deliberately)

> **Stop inferring exclusion from `is_primary` alone while no UI can set it.**

Left undone, and it is the deeper of the three. `is_primary` means "this run is
part of the primary roofline (vs secondary features)" — a *geometry* statement.
Participation reads it as "this channel opts out of shows" — an *intent*
statement. Those are different claims, and conflating them is what let a
decorative-run flag silently remove a channel from every design apply.

Item 1 makes that recoverable; it does not make it correct. A house whose
installer traced an accent strip as secondary still starts out excluded, and
the customer still has to discover the dimmed chip to fix it.

**Not fixed here because the right fix is a decision, not a patch:** either
(a) drop the "traced but not primary ⇒ excluded" branch entirely, making
participation opt-OUT only and default-in everywhere — which changes behaviour
for every existing install with a secondary-flagged run, or (b) give the
roofline editor a real per-channel "in my shows" flag distinct from
`is_primary`, and migrate. (a) is a one-line change with fleet-wide blast
radius; (b) is a schema addition plus a migration. Both need a call, and both
want the item-1 telemetry (`participating_channels_explicit`) to show how often
customers actually override before choosing.

---

## 3. Bench remediation

`scripts/_fix_bench_participation.js` — **dry-run by default**, `--commit` to
write, `--mode=flip` (default; sets `is_primary: true`, one-boolean-reversible)
or `--mode=delete` (removes the doc; the channel becomes untraced, which
defaults IN). Prints the published facts, the roofline input, and the
resolver's projected before/after before writing anything.

**Note it un-discriminates the rig's roofline leg** (§7.2d Leg B is the only
place the "traced but NOT primary ⇒ EXCLUDED" branch has ever executed on real
hardware). `flip` is the default precisely because it is one boolean back.

**After running:** full app restart on LAN. The phone's cache still holds the
old value; the reconciler is once-per-PROCESS and needs both
`deviceChannelsProvider` and the roofline ready before it can clear it.

Or, without touching Firestore at all: **tap the dimmed chip and Include in
Shows.** That is the point of item 1 — and exercising it on the bench is the
better smoke test of the two.

---

## 4. Verification owed

| # | check | status |
|---|---|---|
| 1 | `participation_override_test.dart` — 20 cases | written |
| 2 | Include-back on hardware: dimmed chip → sheet → both channels take an All-Zones design apply | **OWED** |
| 3 | Survives relaunch — the reconciler prunes, does not clear | **OWED** |
| 4 | **§7.2d re-verify.** The healer's participation leg changed (awaits the override, publishes `_explicit`). Its dispositions, dedup memo and single-write property are unchanged by inspection, but §7.2d GREEN was measured on +73 without this await — re-run Leg A (dedup) and confirm `participation_publish_disposition` still transitions `offered` and writes zero on a second heal | **OWED — blocks the +81 ledger entry** |
| 5 | Firestore rules: `participating_channels_explicit` is a new field on an already-owner-writable doc; no rules change expected — confirm | **OWED** |
