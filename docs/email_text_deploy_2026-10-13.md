# Customer email text: "no line-voltage work" wording — PREPARED, NOT DEPLOYED

*Branch `fix/email-line-voltage-text`, based on `a836a3e`. Prepared 2026-10-12 for a deploy the owner approves separately (planned Tuesday 2026-10-13, after the Game Day window's S2 read). Nothing in this page has been run against the live project. No Game Day function, flag or schedule is touched. The wording is FACTS T-W12 and strings proposal item 29 on `docs/overhaul-2026-10` (not merged).*

## 1. The base commit, and how it was found

The live versions of `onSalesJobStatusChanged` and `sendInstallReminders` were deployed by the 2026-08-19 full functions deploy (45 functions, Node 22), whose ledger row names the deployed SHA `a836a3e` (then `origin/main`). Every functions deploy since was `--only` named functions and never these two: 2026-09-30 (`executeWledCommand`, `sweepExpiredCommands`, `probeControllerHealth`, `collectControllerHealth`, from `8b3bcdf`; its ledger row records the previous live version as "the 2026-08-19 nodejs22 full deploy, `a836a3e`"), 2026-10-02 (Game Day A+B: `planGameDayFires`, `dispatchFireJobs`, `teardownTeamFires`), and 2026-10-12 12:00 CDT (the same three, per the Game Day deploy plan `docs/gameday_espn_slate_deploy_plan_2026-10-02.md` §5 on `fix/gameday-espn-slate` and the deploy log in the other session's scratchpad `deploy1012/deploy.log`: "updating … teardownTeamFires / dispatchFireJobs / planGameDayFires … Deploy complete!", packaged from the Game Day worktree).

Both files are byte-identical at `a836a3e`, at the 2026-09-30 deploy commit `8b3bcdf`, at the Game Day deploy sources `d2e0f6e` / `309a5d9` / `319e654`, at the release tip `c283d62` and at `origin/main` (blob `e2aefba` and `f38ccd3`; last changed 2026-04-09). So no line differs between the deployed commit and the release tip for either file, and `a836a3e` is used as the base. Build inputs at `a836a3e`: `firebase.json` predeploy `npm --prefix functions run build` (= `tsc`), runtime `nodejs22`, `functions/package.json` unchanged against the release tip (so the main checkout's installed `node_modules` match), `tsconfig.json` lacks the later `noEmitOnError` (a compile error would still stop the predeploy because `tsc` exits non-zero).

## 2. The change: seven string literals, nothing else

| File:line | Before | After |
|---|---|---|
| `functions/src/onSalesJobStatusChanged.ts:212` (plain-text email, Step 1) | "Step 1 — Day 1: Our electrician visits to run all wiring. No lights go up on this day." | "Step 1 — Day 1: Our installer visits to run the low-voltage wiring. No lights go up on this day. We do no line-voltage (household power) work. Our installer can plug the power supply into an existing outlet, but we do not install outlets or run line-voltage wiring. That is the homeowner's responsibility, arranged through a licensed professional of the homeowner's choosing." |
| `:219` (plain-text access list) | "  • your electrical panel" | "  • the controller and power-supply location" |
| `:239` (HTML email, Step 1 paragraph) | Our electrician visits to run all wiring. **No lights go up on this day.** | Our installer visits to run the low-voltage wiring. **No lights go up on this day.** We do no line-voltage (household power) work. Our installer can plug the power supply into an existing outlet, but we do not install outlets or run line-voltage wiring. That is the homeowner's responsibility, arranged through a licensed professional of the homeowner's choosing. |
| `:251` (HTML access list) | `<li>your electrical panel</li>` | `<li>the controller and power-supply location</li>` |
| `functions/src/sendInstallReminders.ts:274` (Day 1 reminder text) | "electrical panel, garage or utility area, and exterior eaves. " (preceded on :273 by "…access to: your ") | "controller and power-supply location, garage or utility area, and exterior eaves. " |
| `functions/src/sendInstallReminders.ts:273` (Day 1 reminder text; added in the 2026-10-12 follow-up) | "to run all wiring. Please make sure we have access to: your " | "to run the low-voltage wiring. Please make sure we have access to: your " |
| `:344` (Day 2 reminder text) | "complete the full installation. No electrical access needed " (followed on :345 by "tomorrow — just the exterior of your home…") | "complete the full installation. Nothing is needed inside " |

Triggers, unchanged: `onSalesJobStatusChanged` is a Firestore `onDocumentUpdated` on `sales_jobs/{jobId}` (us-central1); `sendInstallReminders` is `onSchedule` every day 18:00 America/Chicago (us-central1, 540 s, 256 MiB). Resulting customer text: the booking email's Step 1 and access list, the Day 1 reminder ("…will be there at your home to run all wiring. Please make sure we have access to: your controller and power-supply location, garage or utility area, and exterior eaves. No lights go up tomorrow — that's Day 2!") and the Day 2 reminder ("…complete the full installation. Nothing is needed inside tomorrow — just the exterior of your home."). The words "electrician" and "electrical" no longer appear in either file. No price, license, insurance or warranty statement was added (the only "licensed" is inside the owner's public sentence).

The complete text as the customer reads it (placeholders in angle brackets are the values the code fills in at send time):

**Booking email, plain-text part (onSalesJobStatusChanged.ts, the text array)**

```
Hi <firstName>,

Your permanent LED lighting system is confirmed. Here's what happens next:

Step 1 — Day 1: Our installer visits to run the low-voltage wiring. No lights go up on this day. We do no line-voltage (household power) work. Our installer can plug the power supply into an existing outlet, but we do not install outlets or run line-voltage wiring. That is the homeowner's responsibility, arranged through a licensed professional of the homeowner's choosing.

Step 2 — Day 2: Our install team arrives and your lights go up.

We'll send you a text reminder the night before each visit.

Before we arrive, please make sure we'll have access to:
  • the controller and power-supply location
  • your garage or utility area
  • the exterior eaves of your home

Questions or scheduling changes? Reach out to <dealerName> anytime.

Welcome to the Nex-Gen LED family!
```

**Booking email, HTML part rendered as text (the html template)**

```
You're booked! 🎉
Hi ,
Your permanent LED lighting system is confirmed. Here's what happens next:
STEP 1 — DAY 1
Our installer visits to run the low-voltage wiring. No lights go up on this day. We do no line-voltage (household power) work. Our installer can plug the power supply into an existing outlet, but we do not install outlets or run line-voltage wiring. That is the homeowner's responsibility, arranged through a licensed professional of the homeowner's choosing.
STEP 2 — DAY 2
Our install team arrives and your lights go up.
We'll send you a text reminder the night before each visit.
Before we arrive, please make sure we'll have access to:
the controller and power-supply location
your garage or utility area
the exterior eaves of your home
Questions or scheduling changes? Reach out to  anytime.
Welcome to the Nex-Gen LED family!
`.trim();
return { subject, html, text };
}
function buildInstallCompleteEmail(
prospect: ProspectInfo,
dealerName: string,
): { subject: string; html: string; text: string } {
const firstName = prospect.firstName || "there";
const subject = "Your Nex-Gen LED system is live! 💡";
const text = [
`Hi ,`,
"",
"Your permanent LED lighting system is installed and ready.",
"",
"Download Lumina to control your lights:",
`  • iPhone: ${APP_STORE_URL}`,
`  • Android: ${PLAY_STORE_URL}`,
"",
`Your login was sent to ${prospect.email}. Check your inbox for your account setup email.`,
"",
"Welcome to the Nex-Gen LED family — we can't wait to see your home lit up.",
"",
`Questions?  is here for you.`,
].join("\n");
const html = `
Your system is live! 💡
Hi ,
Your permanent LED lighting system is installed and ready.
Download Lumina to control your lights
Download for iPhone
Download for Android
Your login was sent to ${prospect.email}. Check your inbox for your account setup email.
Welcome to the Nex-Gen LED family — we can't wait to see your home lit up.
Questions?  is here for you.
`.trim();
return { subject, html, text };
}
// ── Cloud Function ──────────────────────────────────────────────────────────
export const onSalesJobStatusChanged = onDocumentUpdated(
{
document: "sales_jobs/{jobId}",
region: "us-central1",
},
async (event) => {
const before = event.data?.before.data();
const after = event.data?.after.data();
if (!before || !after) {
logger.warn(
"onSalesJobStatusChanged: missing before/after snapshot, ignoring",
);
return;
}
const jobId = event.params.jobId;
const beforeStatus = before.status as string | undefined;
const afterStatus = after.status as string | undefined;
const prospect = readProspect(after);
const firstName = prospect.firstName || "there";
// ── Load dealer messaging config (toggles + sign-off) ─────────────────
//
// Load once up front since both the day1-completed branch and the
// status-transition branch need it. loadDealerMessagingConfig
// returns defaults on missing/invalid configs and never throws.
const dealerCode = (after.dealerCode as string) ?? "";
const config: DealerMessagingConfig =
await loadDealerMessagingConfig(dealerCode);
const signOff = resolveSignOff(config);
// ── Day 1 completion detection (independent of status change) ─────────
//
// markDay1Complete in sales_job_service.dart writes BOTH status:
// prewireComplete AND day1CompletedAt: now in the same atomic update.
// We detect day1CompletedAt becoming non-null specifically rather
// than the prewireComplete status, because the spec wants this
// message tied to the completion event, not the queue transition.
//
// Not toggle-controlled — the spec only puts toggles on the two
// emails and the two day-before reminders. This SMS always sends.
const day1CompletedBefore = before.day1CompletedAt;
const day1CompletedAfter = after.day1CompletedAt;
const day1JustCompleted =
day1CompletedBefore == null && day1CompletedAfter != null;
if (day1JustCompleted) {
const body =
`Great news, ! Wiring prep is complete at your home. ` +
"Your light installation day is coming soon — we'll text you the " +
`night before. — ${signOff}
```

**Day 1 reminder, SMS text (sendInstallReminders.ts, the first body)**

```
Hi <firstName>! 👋 Just a reminder — tomorrow is your <signOff> prep day. <techName> will be there at your home to run the low-voltage wiring. Please make sure we have access to: your controller and power-supply location, garage or utility area, and exterior eaves. No lights go up tomorrow — that's Day 2! See you then. — <signOff>
```

**Day 2 reminder, SMS text (the second body)**

```
Hi <firstName>! 🎉 Big day tomorrow — your <signOff> lights go up! Our install team will be at your home to complete the full installation. Nothing is needed inside tomorrow — just the exterior of your home. Get ready to see it light up! — <signOff>
```


## 3. Proof that the change is text only

`git diff --numstat a836a3e`: `4 4 functions/src/onSalesJobStatusChanged.ts`, `3 3 functions/src/sendInstallReminders.ts`; no other file. A tokenizer (`strip_literals.py`, kept with the hand-back) that removes the contents of every `'…'`, `"…"` and `` `…` `` literal while keeping `${…}` expressions as code was run on each file against its `a836a3e` version: skeleton identical for both (everything outside string-literal contents), 136 literals on each side of `onSalesJobStatusChanged.ts` with 3 contents differing (the two plain-text strings and the one HTML template-literal segment that holds both HTML changes), 117 on each side of `sendInstallReminders.ts` with 3 differing (re-run 2026-10-12 after the line-273 change). The same tool on the untouched `a836a3e` file against the release tip reports 0 differing literals (control).

## 3b. The same wording elsewhere under `functions/`

Searched `functions/` (every `.ts`, `.js`, `.json`, `.html`, `.txt`, `.md` outside `node_modules/`) for "electrician", "electrical", "all wiring" and "electrical panel" after the change: no hit in `functions/src/` or `functions/index.js`. The only hits are the tracked, stale compiled copies `functions/lib/onSalesJobStatusChanged.js` (lines 200, 207, 226, 238) and `functions/lib/sendInstallReminders.js` (249, 250, 305): build outputs that the deploy's predeploy `tsc` overwrites before packaging, so they reach no customer on this path. They are not edited here; after the predeploy they show as modified, restore them with `git checkout -- functions/lib` and never commit them.

**Hazard (the ledger's standing one):** the separate voice-integration repository's functions tree also exports `onSalesJobStatusChanged` and `sendInstallReminders` from its own source copies, which still carry the old wording. A functions deploy from that repository to this project would silently put the old text back. Deploy these two only from this branch.

## 4. The deploy command (written, checked, NOT run)

Prerequisites, all read-only or git-ignored: the branch head is the SHA in the hand-back; the tree is clean; `functions/.env` is a copy of the main checkout's (git-ignored, never committed); `functions/node_modules` is a junction to the main checkout's (`functions/package.json` is identical at `a836a3e` and the release tip, so the installed modules fit). Git Bash:

```
cd "C:/Flutter Projects/lumina-email-text"
git fetch origin --no-tags
git status --porcelain                                     # must print nothing
git rev-parse HEAD                                         # must equal the hand-back SHA
git diff --numstat a836a3e HEAD -- functions               # exactly: 4 4 onSalesJobStatusChanged.ts, 3 3 sendInstallReminders.ts
cp "C:/Flutter Projects/Lumina V 1.6/functions/.env" functions/.env
cmd //c mklink //J "C:\Flutter Projects\lumina-email-text\functions\node_modules" "C:\Flutter Projects\Lumina V 1.6\functions\node_modules"
git status --porcelain                                     # still nothing (both ignored)

FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --project icrt6menwsv2d8all8oijs021b06s5 \
  --only functions:onSalesJobStatusChanged,functions:sendInstallReminders --non-interactive
```

What it runs: `firebase.json`'s predeploy `npm --prefix functions run build` (= `tsc`, exit-checked; emits `functions/lib/`), then packages `functions/` and updates **only** `onSalesJobStatusChanged(us-central1)` and `sendInstallReminders(us-central1)`; `--only` never deletes or updates another function, and `--non-interactive` makes any prompt a failure instead of a hang. Expected output ends with exactly two "Successful update operation." lines, for those two names, then "Deploy complete!". Any other "updating … function" line means stop and read.

Teardown after the deploy (never `rm -rf` on the junction's target): `cmd //c rmdir "C:\Flutter Projects\lumina-email-text\functions\node_modules"` (removes the link only), `rm functions/.env`, `git status --porcelain` (nothing).

## 5. The rollback command (written, NOT run)

Redeploys the same two functions from the deployed commit `a836a3e`:

```
git worktree add --detach "C:/Flutter Projects/lumina-email-rollback" a836a3e
cd "C:/Flutter Projects/lumina-email-rollback"
git status --porcelain                                     # nothing
cp "C:/Flutter Projects/Lumina V 1.6/functions/.env" functions/.env
cmd //c mklink //J "C:\Flutter Projects\lumina-email-rollback\functions\node_modules" "C:\Flutter Projects\Lumina V 1.6\functions\node_modules"
FUNCTIONS_DISCOVERY_TIMEOUT=180 firebase deploy --project icrt6menwsv2d8all8oijs021b06s5 \
  --only functions:onSalesJobStatusChanged,functions:sendInstallReminders --non-interactive
cmd //c rmdir "C:\Flutter Projects\lumina-email-rollback\functions\node_modules"
rm functions/.env
cd .. && git worktree remove "C:/Flutter Projects/lumina-email-rollback"
```

## 6. Read-only checks after the deploy (written, NOT run)

```
P=icrt6menwsv2d8all8oijs021b06s5
# (a) before the deploy, snapshot every function's update time; (b) after it, diff: exactly two names change
gcloud functions list --project $P --format="table(name,updateTime)" > before.txt
gcloud functions list --project $P --format="table(name,updateTime)" > after.txt
diff before.txt after.txt                                  # only onSalesJobStatusChanged and sendInstallReminders differ

# both revisions changed, update time in the deploy minute
for f in onSalesJobStatusChanged sendInstallReminders; do
  gcloud functions describe $f --gen2 --region us-central1 --project $P \
    --format="value(updateTime,serviceConfig.revision,buildConfig.source.storageSource.bucket,buildConfig.source.storageSource.object)"
done

# delivery is not content: the uploaded source carries the text
gsutil cp gs://<bucket>/<object-for-onSalesJobStatusChanged> onSales.zip
unzip -p onSales.zip lib/onSalesJobStatusChanged.js | grep -c "line-voltage"            # 2 or more
unzip -p onSales.zip lib/onSalesJobStatusChanged.js | grep -ciE "electrician|electrical" # 0
gsutil cp gs://<bucket>/<object-for-sendInstallReminders> reminders.zip
unzip -p reminders.zip lib/sendInstallReminders.js | grep -c "controller and power-supply location"   # 1
unzip -p reminders.zip lib/sendInstallReminders.js | grep -c "Nothing is needed inside"                # 1
unzip -p reminders.zip lib/sendInstallReminders.js | grep -ci "electrical"                             # 0
unzip -l onSales.zip | grep -c "\.env"                                                                 # 0

# the scheduled function keeps its schedule (source: every day 18:00 America/Chicago, us-central1; a redeploy updates the job, never fires it)
gcloud scheduler jobs list --project $P --location us-central1 --format="table(name,schedule,state)"

# no new errors in the two services in the two hours after
gcloud logging read 'resource.type="cloud_run_revision" AND (resource.labels.service_name="onsalesjobstatuschanged" OR resource.labels.service_name="sendinstallreminders") AND severity>=ERROR' \
  --project $P --freshness=2h --limit=50 --format="table(timestamp,severity,textPayload)"   # expect no rows
firebase functions:log --project $P --only onSalesJobStatusChanged,sendInstallReminders        # next scheduled tick clean; next signed job sends the new text
```

Then a `docs/BUILD_LEDGER.md` row on the release branch in the 2026-09-30 row's format (deploy time, the two names, base `a836a3e`, read-backs, rollback = §5), by the owner.

## 7. What was not done

Follow-up 2026-10-12: line 273 added as the seventh literal; the proof re-run; the search in section 3b. Still nothing deployed.

### The original note

Nothing was deployed, built, tested or merged. No tag, no version bump, no `codemagic.yaml` change, no app code change, no write to any controller, bridge, Firestore document, configuration or Drive. The in-app strings of proposal item 29 wait for the next app build. No process was stopped or killed.
