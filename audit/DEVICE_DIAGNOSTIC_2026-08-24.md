# Device Diagnostic — "My Designs shows pre-Phase-A behaviour"

**2026-08-24.** Read-only investigation. Verdict: **the source is correct; no
build containing it was ever produced.** The tester is running `build-80` from
2026-08-18, which predates every line of the My Designs work.

---

## Symptom

On the TestFlight build believed to be from
`integration/test-build-2026-08-24`: tapping a My Designs row from either entry
point applies the design immediately, with no detail card, no
rename/duplicate/delete, and no edit path. Tester's words: *"I can tell it's
trying to open up another window/card but the system doesn't let it. It applies
the design."*

## Root cause: the CI trigger is tag-only, and no tag was made

`codemagic.yaml:24-29`, verbatim:

```yaml
    triggering:
      events:
        - tag
      tag_patterns:
        - pattern: 'build-*'
          include: true
```

**`events: [tag]` — there is no push event.** Pushing a branch, any branch,
cannot start an iOS build. The branch's *name* is irrelevant; only tags matter.

This is deliberate and documented in the same file (#62): auto-submit made every
docs commit ship a TestFlight build, which once put two artifacts carrying +72
code under a +71 telemetry stamp into TestFlight and served a stale build 288
during a hardware verification. The comment also warns that the push trigger
lived in the **Codemagic UI webhook**, not this file, and was switched to
tag-only in the same session.

### Evidence

| Check | Result |
|---|---|
| Integration branch tip | `0842e6e`, `2.5.10+81`, in sync with origin |
| Newest `build-*` tag | **`build-80` → `53a9f53`, 2026-08-18** |
| Any `build-*` tag descended from `0553a94` (Phase A's first commit)? | **None** |
| `design_detail_screen.dart` at `build-80` | **Does not exist** |
| `isSavedDesign` branch at `build-80` | `await _applySavedDesignAndPop(designId)` from `addPostFrameCallback` — apply, then pop |

That last row **is** the reported symptom, in the code the tester is running. The
"trying to open a card" impression is the route pushing a new
`LibraryBrowserScreen`, which renders a spinner and immediately applies + pops.

## What was ruled out

The race hypothesis was investigated in full against the branch tip and does not
apply — the racing code was deleted in Phase A.

| Hypothesis | Finding at `0842e6e` |
|---|---|
| Leftover `addPostFrameCallback` applying + popping in browse mode | **No.** The `isSavedDesign` branch returns `DesignDetailScreen(designId:)` for browse; the post-frame path survives only under `widget.onDesignSelected != null` (selection mode: schedule / Game Day pickers), which is correct |
| `_applySavedDesignAndPop` still present | **Removed.** The only `applySavedDesign` left in `pattern_theme_selection.dart` is inside `_applyDesignById`, the opt-in row overflow-menu action |
| Two routes matching `design_{id}` | **No.** Exactly one: `app_router.dart:894` `library/:nodeId`. The `:categoryId` wildcard at `:930` is registered after it and matches a single segment |
| A GoRouter `redirect` applying + popping before mount | **No.** `appRedirect` is the auth gate; a redirect can only return a path, it cannot invoke `applySavedDesign` |
| `DesignDetailScreen` popping on first frame | **No.** It is a `ConsumerWidget` with **no `initState`**. Its only pops are the "Back to My Designs" button, a post-delete pop, and dialog dismissals |
| A feature flag / remote config / A-B gate on the new path | **None exists.** No conditional stands between route resolution and `DesignDetailScreen` rendering — unlike `calendar_leases.liveWritesEnabled` in the scheduling stream |
| Duplicate widget handling `isSavedDesign` | **One only.** `DesignDetailScreen`, one definition, one registration |

## Two traps worth remembering

1. **A pushed branch is not a build.** Only `git tag build-N && git push origin
   build-N` produces one. Three branches were pushed today and none of them built
   anything.

2. **The iOS build number does not come from `pubspec.yaml`.**
   `codemagic.yaml:53-55` sets it from `${PROJECT_BUILD_NUMBER:-$(date +%s)}` and
   then **overwrites** pubspec's version during the build:

   ```
   BUILD_NUM=${PROJECT_BUILD_NUMBER:-$(date +%s)}
   VERSION_NAME=$(grep '^version:' pubspec.yaml | ... | cut -d'+' -f1)
   sed -i '' "s/^version: .*/version: ${VERSION_NAME}+${BUILD_NUM}/" pubspec.yaml
   ```

   So the `+81` bump reaches **Android** and `kStaffAuthTelemetryAppVersion`, but
   the iOS build number will be whatever Codemagic assigns. **Identify the
   resulting build by its git SHA**, per `docs/BUILD_LEDGER.md` — not by the
   number on the TestFlight card.

## To produce a build carrying this work

```
git tag build-81 0842e6e
git push origin build-81
```

Two cautions before choosing that name:

- **`build-81` overlaps the Android versionCode namespace.** `pubspec.yaml` is
  now at `+81`. If an Android `+81` is planned independently, pick a different
  tag or reconcile first — a tag and a versionCode are different counters that
  have been kept in step by convention.
- The tag auto-submits to TestFlight (`submit_to_testflight: true`), so it is one
  deliberate act producing one artifact from one SHA.

## Not verified on device

`flutter devices` on this Windows host finds only Windows desktop, Chrome and
Edge — no Android device and no iOS (impossible here). The bench tablet needs
`adb connect` on a port that churns every toggle, which is Tyler's to supply. A
local desktop/web run was not attempted: it would not isolate anything, because
the pipeline demonstrably never built these bits.

**Everything in this report is from CI config, git history, and source at
`0842e6e`. Nothing was run on hardware.**
