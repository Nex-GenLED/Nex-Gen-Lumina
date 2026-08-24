# Integration Test Build — 2026-08-24

**Branch:** `integration/test-build-2026-08-24` @ **`be3ed43`** — pushed to origin.
**Purpose:** a throwaway test vehicle for a combined Codemagic build. **Not a
merge target.** `main`, `feat/design-card` and `feat/schedule-v3-model` are
untouched.

> ## ⚠️ Read before triggering the build
>
> **`pubspec.yaml` is at `2.5.10+80`, inherited from `main` — neither feature
> branch bumped it.** A built Android AAB **consumes its version code even if it
> is never uploaded**. If Codemagic builds this branch for Android at +80, then
> +80 is burned, and the next real release from `main` (also at +80) will
> collide.
>
> I did **not** bump it — that was not among the seven steps, and the right
> value depends on what the schedule-v3 session plans to ship. **Decide before
> building:** bump this branch to +81 (and `kStaffAuthTelemetryAppVersion` in
> [staff_auth_telemetry.dart:57](../lib/features/installer/staff_auth_telemetry.dart#L57)
> to match), or build iOS-only, or accept burning +80.

---

## 1. Pre-check

| Check | Result |
|---|---|
| Modified tracked files | **None** — `git status --porcelain` shows no `M`/`A`/`D` entries |
| Current branch | `feat/design-card` ✅ |
| HEAD | `18479ba1b68c3e774805eb3b7bf67c381fd12f46` ✅ |
| `feat/schedule-v3-model` visible | ✅ listed with `+` (checked out at `C:/Flutter Projects/lumina-schedule-v3`) — expected; merging by name needs no local checkout |

**Untracked files — one is mine.** Reported rather than assumed away:

```
?? audit/COLOR_FIDELITY_AUDIT.md        ← MINE (previous task was read-only / no-commit)
?? audit/SCHEDULING_V3_AUDIT.md         ← not mine
?? docs/AUDIT_APP_STRUCTURE_3FRONTS.md  ← not mine
?? scripts/_inventory_sync_domain.js    ← not mine
?? scripts/_stamp_customer_dealer_code.js
?? scripts/_teardown_sync_domain.js
```

`COLOR_FIDELITY_AUDIT.md` is the colour-fidelity audit from the previous task,
which was explicitly read-only-no-commits. It stays untracked and was **not**
staged into any merge here. It carries across branch checkouts harmlessly. It
still needs a home — flagged in §6.

**Source-branch tips recorded for reproducibility** (schedule-v3 is a moving
target — the parallel session advanced it from `23cf4f0` to `8368255` during
this session):

| Branch | SHA merged |
|---|---|
| `main` (base) | `c14368d` |
| `feat/design-card` | `18479ba` |
| `feat/schedule-v3-model` | **`8368255`** — `docs(schedule): file the Phase D report` |

---

## 2. Merge steps

### Step 1 — branch off `main`

```
git checkout -b integration/test-build-2026-08-24 main
```
Created at `c14368d`. ✅

### Step 2 — `git merge feat/design-card --no-ff`

**Clean, no conflicts.** 28 files changed, 4 778 insertions, 464 deletions.
Merge commit `ec05ae1`.

New files: `design_deletion.dart`, `design_detail_screen.dart`,
`selector_payload.dart`, three test files, five audit documents.

### Step 3 — `git merge feat/schedule-v3-model --no-ff`

**Clean, no conflicts.** Merge commit `be3ed43`.
`git diff --name-only --diff-filter=U` returned **empty**.

---

## 3. Conflicts

**There were none — including in `my_schedule_page.dart`.**

The brief expected a conflict there, and both branches did modify that file:

| Branch | Commits touching `my_schedule_page.dart` |
|---|---|
| `feat/design-card` | `d8c7ae1` — the B3 comment annotation at the picker call |
| `feat/schedule-v3-model` | `967c621`, `c9d56b8`, `23cf4f0` — D4 channel picker, slot meter, timeline |

They did not conflict because design-card's change to that file is a **comment
block only** (it added an annotation recording that the "catalog + My Designs"
claim had become true), while schedule-v3's D4 additions sit **higher in the
same editor sheet**. Adjacent, not overlapping — git's 3-way merge resolved the
offset.

**A clean auto-merge is not proof of a correct one**, so both sides were verified
present in the merged file rather than assumed:

| Requirement | Verified at | Evidence |
|---|---|---|
| My Designs still reachable from the schedule picker (design-card) | `my_schedule_page.dart:4659-4683` | the annotated comment and `nodeId: null` — the root-level picker that now lists My Designs as a tree root |
| D4 channel picker present (schedule-v3) | `my_schedule_page.dart:4562` | `ChannelScopePicker(channels: _channels, onChanged: …)` |
| D4 slot accounting present (schedule-v3) | `my_schedule_page.dart:4573` | `TimerSlotMeter(editingId: widget.editing?.id)` |
| Both imports intact | `:20-21` | `channel_scope_picker.dart`, `timer_slot_meter.dart` |

**Structural coherence checked by reading the merged region**, not just grepping
for symbols: the scope picker and slot meter sit above the "Action" dropdown;
the pattern-picker row (with the My Designs wiring) sits below it, gated on
`_action == _ActionType.runPattern`. That is the order both branches intended.

**No `--ours` / `--theirs` was used anywhere** — there was nothing to resolve.

---

## 4. Analyze and test

### `flutter pub get` — clean

### `flutter analyze` — **zero errors**

385 issues total, **12 warnings**, all pre-existing.

**New warnings introduced by the merge: zero.** Verified by diffing the warning
*sets*, not just the counts, against `feat/design-card` built alone:

```
8c8
< warning - Unnecessary cast - lib\features\schedule\schedule_sync.dart:937:19
---
> warning - Unnecessary cast - lib\features\schedule\schedule_sync.dart:1111:19
```

The single difference is the **same warning, same file, same rule**, moved from
line 937 to 1111 because schedule-v3 inserted ~174 lines above it. Every other
warning is byte-identical.

> A baseline for `feat/schedule-v3-model` alone could not be measured here: `git
> checkout feat/schedule-v3-model` is correctly refused because that branch is
> checked out in another worktree. I did **not** work around it — running
> `flutter analyze` inside that session's worktree would write `.dart_tool` under
> their feet. The design-card comparison plus the zero-error result is the
> evidence offered.

### `flutter test` — **2 596 passed, 0 failed** (~2 min 31 s)

| Branch alone | Tests |
|---|---|
| `feat/design-card` | 2 504 |
| **integration (merged)** | **2 596** |

+92 from schedule-v3's suites (`scope_sidecar_test`, `scoped_preset_test`,
`preset_satisfies_test`, `day_timeline_test`, `calendar_entry_storage_test`,
`channel_scope_display_test`, `entry_editor_wiring_test`, and others).
`~4` skipped, unchanged from both branches.

**No failure to attribute.**

---

## 5. Divergence check (step 6)

### A — `feat/design-card...integration` (should show only schedule-v3's work)

27 files under `lib/`. **25 are under `lib/features/schedule/` or
`lib/features/autopilot/`.** The two outside that fence were each checked:

| File | Attribution |
|---|---|
| `lib/features/dashboard/wled_dashboard_page.dart` | schedule-v3's `967c621` + `23cf4f0`. **design-card has zero commits touching it** → no overlap |
| `lib/services/user_service.dart` | schedule-v3's `967c621` + `23cf4f0`. **design-card has zero commits touching it** → no overlap |

### B — `feat/schedule-v3-model...integration` (should show only design-card's work)

19 files under `lib/`. **Every one traces to a design-card commit** — verified
programmatically (`git log main..feat/design-card -- <file>` non-empty for all
19). Zero unexpected entries.

**Nothing diverged silently in either direction.**

### Source branches untouched

| Branch | Before | After |
|---|---|---|
| `main` | `c14368d` | `c14368d` ✅ |
| `feat/design-card` | `18479ba` | `18479ba` ✅ |
| `feat/schedule-v3-model` | `8368255` | `8368255` ✅ |

No branch was deleted, reset, or rewritten. No `git stash` was run.

---

## 6. Pushed, and what needs a decision

### Pushed ✅

```
* [new branch]  integration/test-build-2026-08-24 -> integration/test-build-2026-08-24
branch 'integration/test-build-2026-08-24' set up to track
  'origin/integration/test-build-2026-08-24'
```

Local `be3ed43` == `origin/integration/test-build-2026-08-24` `be3ed43`.
GitHub offers a PR link; **do not open one** — this is a test vehicle.

Note both feature branches remain **local-only**; `origin` carries neither. This
integration branch is therefore the only pushed artifact containing either
body of work.

### Needs your decision

1. **The `+80` version code** (banner at the top). An Android build burns it, and
   `main` is also at +80. Bump to +81 here — with
   `kStaffAuthTelemetryAppVersion` kept in lockstep — or build iOS-only, or
   accept the burn. **Not actioned: outside the seven steps, and it interacts
   with what the schedule-v3 session intends to ship.**

2. **`audit/COLOR_FIDELITY_AUDIT.md` is still untracked.** The task that produced
   it forbade commits. It is not on any branch, so it will not reach Codemagic
   and is not in this build. It needs committing somewhere — most naturally onto
   `feat/design-card`, alongside the addendum it completes.

3. **`feat/schedule-v3-model` is actively moving.** It advanced from `23cf4f0` to
   `8368255` while this session ran. This build pins `8368255`; anything that
   session lands afterwards is **not** in it. Re-merge before re-building if
   that matters.

4. **Nothing else was blocked.** No resolution was guessed, because no conflict
   occurred.

---

## 7. What I would have had to fabricate, and didn't

1. **A conflict resolution.** The brief anticipated one in
   `my_schedule_page.dart`; there was none. I verified both features survived
   rather than reporting a resolution I did not perform.
2. **A schedule-v3-alone analyzer baseline.** Blocked by the worktree lock, which
   I respected rather than circumventing. Stated as a gap, with the
   design-card comparison given in its place.
3. **That the build is release-ready.** It compiles, analyzes clean and passes
   2 596 tests. **Nothing here has run on a device**, and the design-card work in
   particular has an open device pass (the cancel-restore path). This is a test
   vehicle only.
4. **A version bump.** Flagged, not performed — see §6.1.
