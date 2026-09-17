# Store Submission Branch — Report

**Branch:** `release/store-submission-2026-09-17`
**Cut from:** `origin/main` @ `699a498`
**Version:** `2.5.10+98`
**Date:** 2026-09-17

---

## 1. Ground truth on branch state (Step 1)

### Main's actual current tip

| | |
|---|---|
| **`origin/main` tip** | **`699a498`** — *Merge branch 'feat/112-poll-throttle' into main* |
| **Version on that tip** | **`2.5.10+97`** |
| `targetSdk` / `compileSdk` | 36 / 36 (from `5b7804b`) |

**Read directly off `origin/main` after `git fetch`, and it corrected two stale references:**

- **Local `main` was stale by 23 commits** — it sat at `625bae6` / `2.5.10+90`. Anything derived
  from the local ref would have been wrong. It has not been moved; the branch was cut from
  `origin/main` explicitly.
- The working tree was a **detached HEAD at `df6063b`**, a docs-only branch that is **not an
  ancestor of `origin/main`**. Its `pubspec.yaml` reads `2.5.10+88` and its gradle files are
  targetSdk **35**, which Play now refuses at upload. **Nothing should ever be built from that
  checkout.**

`versionCode 97` is recorded in `docs/BUILD_LEDGER.md` as **CONSUMED** (the +97 AAB was built). A
built bundle burns its code whether or not it was uploaded, so the next release had to be ≥ +98.

### The seven drafts vs main's existing +89 pass

The guide files are **unchanged between `625bae6` and `699a498`** — the 23 intervening commits
touched `BUGS_AND_DEBT.md` and `BUILD_LEDGER.md` only. So main's doc state is still the `+89` pass
(`d67d350`), and that is what the drafts were compared against.

**Already correct on main — the +89 pass wins, left untouched:**

| Item |
|---|
| Sports Alerts retired; settings folded onto the Game Day team card |
| The 8-slot controller timer budget, and solar boundaries being free |
| Channel-scoping turning the unselected channels off |
| Game Day no longer requiring a schedule |
| Account deletion, with the lights / bridge / residual-data caveats |
| Warranty terms — 5yr product, 1yr labor minimum, 50,000h rated |
| TestFlight / Play-testing distribution rather than a store search |
| The My Designs action table, and Edit being greyed out for AI-composed designs |
| Bridge firmware v1.2; the 30-second re-assertion; server release not freeing a live bridge |

**Net-new in this pass — merged in:**

| Correction | Basis |
|---|---|
| Production flag values, not code defaults | All five `config/*` flags default `false` in Dart; `solar_scheduling` and `calendar_leases` are **`true`** in production |
| The bridge serves **no web UI at all** | Six `/api/*` routes; no `serveStatic`, no LittleFS, no `data/`; `handleNotFound` returns 404 JSON |
| Commercial guide rebuilt | Phase 3a removed the `/commercial` redirect; the shell is orphaned |
| Welcome Home / geofence removed | Route registered, zero inbound navigation |
| Game Day crews, Alexa/Google removed then revised | Missing rules blocks (now fixed — §3) |
| Audio Mode excluded | `if (kDebugMode && audioSupported)` |
| Estimate Wizard, material check-in, dealer inventory, Brand Library admin, commercial onboarding, scheduled crew syncs excluded | Orphaned or permission-impossible |
| "Live Scoring" alone does nothing | Celebrations also require the team's Autopilot switch |
| Two schedule limits, not one | 20 saved **and** 8 controller slots |
| Routing badge documented | `#114` / `f2a228a`, Direct / Via Bridge |
| No "AR" anywhere | No camera path, no AR SDK |

**Where the two genuinely disagreed** — all four resolved in favour of this pass, because each was
verified against shipping code and each was actively misleading:

1. Bridge web dashboard / Factory Reset button (9 passages on main)
2. Welcome Home documented as a working Settings screen
3. Game Day crews documented as working
4. Alexa/Google described as "still rolling out" (reads as *might work for you*; it could not work
   for anyone)

---

## 2. What was merged, what conflicted, how each was resolved (Step 2)

No `git merge` was run and there were no textual merge conflicts — the branch was cut from
`origin/main` and the drafts are new files. The "conflicts" were **factual**, between what main's
guides asserted and what the code does. Each resolution:

| # | Conflict | Resolution | Why |
|---|---|---|---|
| C-1 | Main: release a bridge via a browser **Factory Reset** button. Drafts: no web UI exists. | **Drafts win.** All 9 dashboard passages rewritten; status/testing moved to the app's Remote Access screen; reset documented as installer-assisted. | Verified in firmware: 6 routes, no static serving, no `data/` dir, `handleNotFound` → 404 JSON. Most harmful error in the set — the one procedure for moving a bridge between houses sent people to a page that 404s. |
| C-2 | Main: Welcome Home at *System → Geofence Controls*. Drafts: unavailable. | **Drafts win.** Section replaced with a correction notice; a Sunset schedule offered as the workaround. The two location-permission rationales that cited it were rewritten to cite home-network detection. | `GeofenceSetupScreen` exists and its route is registered, but nothing in `lib/` navigates to it, so the config doc can never be written and `GeofenceMonitor` returns early on a null config forever. |
| C-3 | Main: Game Day crews work. Drafts: they don't. | **Split.** Rules gap fixed (§3), so create/view/manage now work. Join-by-invite-code remains closed; the Leave button is still a client no-op. Documented as *partly working*, not fixed. | Honest post-fix state. Overstating it would repeat the original error in the other direction. |
| C-4 | Main: Alexa/Google "still rolling out". Drafts: cannot complete. | **Split.** Rules gap fixed (§3) — the app's side now works and the deep link launches. Store-side availability of the skill/action is **unverified from this environment** and is stated as such. | Verified with a real client-credential write. Claiming the whole integration works would assert something not checked. |
| C-5 | Main's commercial guide documents a Fleet dashboard. | **Drafts win**, by annotation rather than deletion. | Phase 3a removed the route-guard fork; nothing navigates to `/commercial`. |
| C-6 | Two guide families now exist. | **Both kept.** The six old guides get a `SUPERSEDED` banner naming their replacement; the harmful instructions inside them are corrected in place. | Their rendered PDFs are in circulation. Deleting them would strand anyone holding a PDF; a wholesale rewrite of retiring documents is risk without benefit. Corrections carry an inline *Corrected 2026-09-17* notice so a PDF holder can see the delta. |

---

## 3. Firestore rules — confirmed against deployed, and verified with real writes (Step 3)

### The gap was confirmed against the deployed ruleset, not inferred from source

Fetched the live ruleset over the `firebaserules` REST API before changing anything:

```
ruleset   60e1a879-4b96-44c7-8890-6533105e564b
released  2026-08-12T20:58:23Z
2243 lines
probe "integrations"   : 0 hits
probe "game_day_crews" : 0 hits
probe "crews"          : 0 hits
```

It was also **byte-identical to `origin/main`'s `firestore.rules`** (`diff` exit 0), which
established that no undeployed drift would ride along with the deploy — the specific hazard behind
the +74 join regression.

### What was added

**(a) `users/{uid}/integrations/{provider}`** — owner-only read; client writes **field-limited** to
`{linkInitiated, initiatedAt}`, the only keys the client authors, so a client cannot forge
`isLinked` or inject token fields the Cloud Functions own; providers limited to `alexa` and
`google_home`. Deliberately **not** `canReadUserData()` — these docs hold OAuth token material, so
media/admin reads are excluded.

**(b) `game_day_crews/{crewId}`** — membership is the read boundary; create requires the author to
be the host and sole seeded member; `host_uid` immutable on update; delete host-only; leaving is an
`arrayRemove` update.

> **Join-by-invite-code is left closed deliberately, and this is the significant judgement call.**
> `joinCrew()` finds a crew with a collection query filtered on `invite_code`. Firestore rules
> cannot see a query's `where` filters — only `limit`/`offset`/`orderBy` — so "allow only when
> filtered on invite_code" is not expressible. The only rules that make that query succeed let any
> signed-in user *list* crews, which hands out every crew's invite code and reproduces the
> I-18/I-20 self-join exposure that the `joinNeighborhood` callable and `config/sync_fanout` exist
> to prevent. Joins belong in a callable that resolves the code with the admin SDK. That reasoning
> is recorded **in the rules file itself** so the next author does not "fix" it with a wildcard.

### Verification — real writes with a client credential

**Pre-deploy**, `scripts/_test_rules_integrations_crews.js` ran 19 cases through the `firebaserules`
`:test` engine: rules compiled clean, **19/19** behaved as predicted.

Rules were then deployed (`firebase deploy --only firestore:rules`), producing ruleset
**`c433942c-6996-4ae0-85c2-1e267a776928`**, released **2026-09-17T19:46:13Z**.

**Post-deploy**, `scripts/_test_rules_integrations_crews_live.js` drove **real Firestore REST reads
and writes with user ID tokens** minted through Identity Toolkit — subject to exactly the rules a
phone is subject to. Explicitly **not** an admin readback: admin bypasses rules, so an admin write
proves a document can exist and proves nothing about whether the app can write it.

**14/14 passed.** The two writes that were the actual bugs:

```
INT-1  owner CREATE users/{uid}/integrations/alexa   HTTP 200   (previously threw)
CREW-1 host  CREATE game_day_crews/{crewId}          HTTP 200   (previously denied)
```

Eight of the fourteen are **negative controls**, and they are why the passes mean anything — a
token that could do everything would make the ALLOW results worthless:

| Negative control | Result |
|---|---|
| Other user GET another user's integrations doc | 403 |
| Owner forging `isLinked` | 403 |
| Unknown provider id | 403 |
| Non-member GET a crew (invite-code harvesting) | 403 |
| Non-member UPDATE a crew (driving strangers' lights) | 403 |
| `host_uid` mutation | 403 |
| Non-host DELETE | 403 |
| Unauthenticated GET | 403 (pre-deploy suite) |

Both synthetic users and every document written were removed in cleanup.

**Rollback artifact:** the previous ruleset source is saved, and `60e1a879-4b96-44c7-8890-6533105e564b`
can be re-released from the console if needed.

---

## 4. Bridge factory-reset fix (Step 4)

**Approach taken: app-side, as directed. Firmware untouched.** No firmware change is warranted —
the firmware is the correct side of this mismatch.

`BridgeApiClient.reset()` posted to `/api/bridge/reset`. `setupWebServer()` registers exactly six
routes — `/api/info`, `/api/bridge/status`, `/api/bridge/pair`, `/api/bridge/auth`, `/api/reboot`,
`/api/reset` — and `onNotFound()` answers everything else with `404 {"error":"Not found"}`. The call
returned `false` on every bridge ever shipped, and because the client catches and returns `false`,
the failure was indistinguishable from an offline bridge.

**`/api/reset` confirmed before wiring to it — from the firmware handler, not a live device.**
`handleReset()` opens the `bridge` NVS namespace, calls `prefs.clear()` (dropping the stored `uid`
and `wledIp` — exactly the pairing state that makes a bridge un-releasable), replies
`200 {"ok":true,"message":"Resetting..."}` and restarts after 500 ms. So the existing 200-check is
the right success condition and needed no change.

> **Deliberately not tested against a live bridge.** The only reachable unit is the production home
> bridge. POSTing `/api/reset` to it would wipe its pairing and force a re-pair, on hardware with no
> OTA. That is a destructive act on a live install and was not authorised. The endpoint contract was
> confirmed from firmware source, which is definitive for the path, the status code and the effect.

**Fixed the class, not the instance.** A unit test of `reset()` would have asserted whichever path
the implementation used. `test/services/bridge_api_client_endpoints_test.dart` parses `server.on(...)`
out of `main.cpp` and asserts every `$baseUrl` path the client builds is a route the firmware
registers. All six client paths were audited, not just the broken one — the other five already
matched. The test also guards against vacuous passes (asserts both parsers matched something) and
pins the specific regression by name.

**Proven to be a real guard:** with the old path restored it fails with
*`BridgeApiClient builds "/api/bridge/reset", which the firmware does not register`*. With the fix,
4/4 pass.

*Note: nothing in the app calls `reset()` yet, so this restores a correct client contract rather
than shipping a user-facing reset button. Surfacing it is separate work.*

---

## 5. `CLAUDE.md` corrections (Step 5)

`kSimulationMode` is `false` (`lib/app_providers.dart:17`); the file claimed `true`. Documentation
fixed; **the code value was not touched**, as instructed.

This matters more than a typo: a reader who believed it would conclude release builds bypass
permission prompts and use a virtual device, and would misread all eight read sites — discovery, BLE
provisioning, device setup, welcome wizard, bridge discovery, DDP — as simulated when every one is
the real-hardware path.

Two further stale claims in the same file were corrected while there (same class — internal notes
that stopped matching the code and were never re-checked):

- *"HTTP timeouts are currently set to 5 seconds in `WledService`"* — they are **15 s** at every call
  site, and `areaAnyOnProvider` is 15 s too.
- *"Critical Known Issues → System Offline / Bad State"* was flagged **MUST BE RE-APPLIED** with all
  three fixes listed as outstanding. All three are present. Rewritten as a verification table,
  keeping the rule that still matters (never cache a notifier reference in a `State` class).

Also noted that `lib/nav.dart` is now a four-line barrel and the dashboard lives in
`lib/features/dashboard/wled_dashboard_page.dart`, so older instructions pointing at `nav.dart` for
dashboard code point at the wrong file.

---

## 6. Submission-readiness audits, re-run against this branch (Step 6)

Both audits dated 2026-09-17 already assessed `origin/main @ 699a498`, so this re-run covers the
delta introduced by this branch plus the items that were previously unverifiable.

### Branch health

| Check | Result |
|---|---|
| `flutter analyze` | **385 issues, 0 errors** — identical to the documented baseline (0 errors / 12 warnings / 373 infos) |
| `flutter test` | **2984 passed, 4 skipped, 0 failed** |
| `codemagic.yaml` | re-parsed as valid YAML after edit |

**No fix on this branch introduced a new blocker.** The changes are: docs, `firestore.rules`
(additive, verified), one endpoint path string, one CI guard, a version bump, and a
narrowly-scoped route-guard widening.

### Google Play — **NOT-YET** (unchanged verdict; one blocker cleared)

| # | Category | Verdict |
|---|---|---|
| 1 | Manifest & build config | **GO** — targetSdk/compileSdk 36, minSdk 24, signing config intact |
| 2a | Data-safety inventory | **GO as inventory**; the form itself is outstanding |
| 2b | Secrets in the artifact | **GO** |
| 2c | Sensitive-API declarations | **GO** |
| 2d | Deep links | **GO** |
| 3 | App identity | **GO — cleared this branch.** versionCode bumped to **98** (97 was consumed); `kStaffAuthTelemetryAppVersion` moved with it |
| 4 | 12 testers × 14 days | **NOT-YET** — calendar, not engineering |
| 5 | Crash/stability | **GO with caveats** |

**Remaining Play blockers — all yours, none code-side except B-6/B-9:**
B-1 tester recruitment · B-4 Data Safety form · B-5 privacy policy · B-6 analytics opt-out (ship the
toggle or stop promising it) · B-7 API-key restrictions · B-8 reviewer credentials in App Access ·
B-9 delete the deployed `openaiProxy` function · B-10 declare keyless third parties (Nominatim,
Photon, Open-Meteo).

### Apple App Store — **NOT-YET** (two of four blockers cleared)

| # | Category | Verdict |
|---|---|---|
| 1 | Info.plist usage descriptions | **GO** — all ten present |
| 1b | `PrivacyInfo.xcprivacy` | **GO with caveat** — present, 74 declared data-type entries; third-party plugin manifests still unverified |
| 1c | Debug/staging leftovers | **GO** |
| 2 | Build & signing | **GO — cleared this branch.** The epoch fallback is gone; CI now fails fast |
| 3 | Common-rejection surface | **NOT-YET** — privacy policy still under-discloses |
| 4 | Hardware/bridge review risk | **Substantially cleared** — see below |
| 5 | Assets | **GO** |

**B-2 — CLEARED.** `BUILD_NUM=${PROJECT_BUILD_NUMBER:?…}` replaces the `$(date +%s)` fallback that
could have permanently burned the `CFBundleVersion` space.

**B-3 — FIXED, but not runtime-verified.** `/link-account` was terminal for a signed-up user with no
system. Fixed in two halves: `appRedirect`'s unlinked branch now permits `/demo*` (it already
computed `isDemoRoute` but only honoured it on the unauthenticated branch — which is exactly why the
demo door existed only on `/login`), and an **"Explore the demo instead"** button was added. Scope is
narrow: it widens access only for `/demo*` paths and only for signed-in-but-unlinked users; a linked
customer is resolved by earlier branches and never reaches that code. **Kept as its own commit so it
can be reverted in isolation.** See the manual checklist — this is the one change that needs a
hand smoke-test.

**B-4 — VERIFIED, and it is in better shape than the audit could establish.** The audit could not
check production data from the repo. Checked directly:

| Door | Finding |
|---|---|
| Reviewer Auth user | `reviewer@nex-genled.com` **EXISTS**, uid `atzEKyOfrjRWmN6apQQzvJwBgmv1`, **not disabled**, last sign-in 2026-04-23 |
| Reviewer Firestore profile | Absent — **expected, not a fault.** `seedForUser()` is idempotent and runs *after* first sign-in; `isReviewer()` matches on email alone, so the guard bypass works before any doc exists |
| Demo code | `dealer_demo_codes/REVIEW` **EXISTS** with `dealerCode: 'APPLE-REVIEW'`, `isActive: true` |

**What remains unverifiable:** the reviewer account's **password**. Admin cannot read it. That is a
manual sign-in check.

**Remaining Apple blocker:** B-1 — the published privacy policy does not disclose precise location,
photos, camera, microphone/speech or AI-prompt content, while the binary prompts for them and
`PrivacyInfo.xcprivacy` declares them. Web + App Store Connect work, no code.

### Signed artifacts — not attempted, and why

**I do not have working signing material in this environment.** This worktree lacks
`android/key.properties`, `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
(all gitignored), and there is no keystore or provisioning profile available here. Per scope, no
`.ipa` or `.aab` was built. iOS signing lives in Codemagic regardless.

---

## 7. Branch shape (Step 7)

Nine commits, sequential, each with an explicit pathspec (`git commit --only <paths>`); no
`git add -A`, no squashing — each commit is independently reviewable and revertible.

| # | Commit | What |
|---|---|---|
| 1 | `586a430` | The seven-draft 2026.09 guide family |
| 2 | `5ac40ac` | Reconcile the +89 pass against verified behavior |
| 3 | `ae99259` | The two missing Firestore rules blocks |
| 4 | `9318625` | Live client-credential verification + post-fix doc revision |
| 5 | `f4753ca` | Bridge `reset()` endpoint + firmware-pinning test |
| 6 | `0899a86` | `CLAUDE.md` stale-claim corrections |
| 7 | `a3e6b12` | `chore(release): 2.5.10+98` |
| 8 | `195615a` | CI build-number fail-fast (Apple B-2) |
| 9 | `122505c` | `/link-account` demo escape (Apple B-3) |

26 files, +3337 / −71. The branch's upstream was **unset** so a stray `git push` cannot land on
`main`.

> **Working-tree note.** This work was done in an isolated worktree at
> `C:/Flutter Projects/lumina-store-submission`, because the primary checkout holds another
> session's uncommitted edits (`docs/BUGS_AND_DEBT.md` plus ~25 untracked audit files). Nothing in
> the primary tree was touched, staged or stashed.

---

## 8. `dev/post-submission` (Step 8)

Created off the release branch tip, with **no commits of its own** — a clean starting point for
experimental work once both stores approve.

```
release/store-submission-2026-09-17   1e69a98
dev/post-submission                   1e69a98
commits on dev not on release:        0
```

Both refs point at the same commit. Nothing has been added to `dev/post-submission`; branch from it
or commit onto it when you pick work back up after approval.

---

## 9. What you still need to do yourself

### Before building

- [ ] **Copy signing material into whatever tree you build from** — `android/key.properties`,
      `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, and the keystore.
      A fresh worktree has none of them.
- [ ] **Build from this branch, never from the old checkout.** `df6063b` is targetSdk 35 and would
      be rejected at upload.
- [ ] **Smoke-test the B-3 change by hand** (commit `122505c`) — sign up with a throwaway address,
      confirm **"Explore the demo instead"** appears on `/link-account` and reaches the demo-code
      screen instead of looping back. If you would rather not ship it, `git revert 122505c`.
- [ ] **Confirm `PROJECT_BUILD_NUMBER` is set in every Codemagic workflow.** The CI step now fails
      fast instead of inventing a number — intended, but it will stop a workflow that relied on the
      fallback.

### Apple

- [ ] **B-1 — update the privacy policy** to disclose precise location, photos, camera,
      microphone/speech and AI-prompt content, and name the processors (Firebase/Google, the AI
      provider). Then make the App Store Connect nutrition label match `PrivacyInfo.xcprivacy`
      field-for-field. *Best done by making the manifest the single source of truth and deriving the
      other two from it, so they cannot drift again.*
- [ ] **Sign in as `reviewer@nex-genled.com` and confirm the password**, then put those exact
      credentials in App Review notes. The account and the `APPLE-REVIEW` demo code both exist and
      are active — only the password is unverified.
- [ ] Submit in App Store Connect.

### Google Play

- [ ] **Recruit to ≥12 opted-in closed testers and hold 14 continuous days.** Longest pole; start
      now if it hasn't started.
- [ ] **Complete the Data Safety form** against the audit's Appendix A — financial info = yes, crash
      logs collected/linked/required, and make the microphone call.
- [ ] **Fix the privacy policy** (same edit as Apple B-1, plus address, phone and voice).
- [ ] **Analytics opt-out: ship the toggle or remove the promise.** `analyticsPreferenceNotifierProvider`
      has zero consumers today; Play only permits "optional" if the user can actually decline.
- [ ] **Delete the deployed `openaiProxy` Cloud Function** — key-bearing, zero callers. Otherwise you
      must declare OpenAI as a data recipient. *(Use `FUNCTIONS_DISCOVERY_TIMEOUT=180`.)*
- [ ] **Verify Places/Firebase API-key restrictions** — the only finding with direct billing exposure.
- [ ] **Correct the reviewer credentials in App Access.**
- [ ] **Declare the keyless third parties** that receive data straight from the device — Nominatim
      and Photon (raw street address), Open-Meteo (precise coordinates).
- [ ] Upload the `+98` bundle and submit.

### Merge

- [ ] Review and merge `release/store-submission-2026-09-17` into `main` before or alongside
      submitting, so the shipped artifact's SHA is an ancestor of `main`.

> **Already done for you, no action needed:** the Firestore rules fix is deployed *and* verified with
> real client-credential writes (ruleset `c433942c…`). The +98 bump, the CI build-number guard and
> the bridge endpoint fix are committed.

---

## 10. Confirmations

- [x] **Main's actual tip verified in Step 1** — `699a498`, `2.5.10+97`, read off `origin/main` after
      `git fetch`. Local `main` was 23 commits stale at `625bae6`/`+90`; the working tree was a
      detached docs branch at `df6063b`/`+88`/targetSdk 35.
- [x] **Both rules fixes verified with real writes, not just added** — deployed ruleset
      `c433942c-6996-4ae0-85c2-1e267a776928`; 14/14 live cases with Identity Toolkit user ID tokens,
      including the two previously-failing writes returning HTTP 200 and eight negative controls
      returning 403. Test documents and synthetic users cleaned up.
- [x] **Bridge reset fixed app-side, firmware untouched** — `/api/reset` confirmed from
      `handleReset()`; not tested against a live bridge, because the only reachable unit is the
      production home bridge and a reset there is destructive on hardware with no OTA.
- [x] **`CLAUDE.md` corrected, code value unchanged** — `kSimulationMode` remains `false`.
- [x] **Both audits re-run against this branch** — Play **NOT-YET** (versionCode blocker cleared;
      remaining items are console/policy/tester work), Apple **NOT-YET** (B-2 and B-4 cleared, B-3
      fixed pending a smoke test; B-1 is a web + ASC edit).
- [x] **No signed artifacts attempted** — no signing material in this environment, stated rather
      than worked around.
- [x] **`dev/post-submission` created off the release tip and is empty** — both refs at `1e69a98`,
      `git rev-list --count release..dev` = **0**.

---

*Generated 2026-09-17 against `release/store-submission-2026-09-17`.*
