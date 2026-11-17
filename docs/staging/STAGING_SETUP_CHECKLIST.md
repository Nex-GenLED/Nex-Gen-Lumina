# Staging setup checklist (owner)

**What this sets up:** "Lumina Staging", a second iPhone app that installs beside the real one.

| | Production (unchanged) | Staging |
|---|---|---|
| Bundle id | `com.nexgenled.command` | `com.nexgenled.command.staging` |
| Home-screen name | Lumina | Lumina Staging (plus an orange **STAGING** ribbon on every screen) |
| Firebase project | `icrt6menwsv2d8all8oijs021b06s5` | `nex-gen-lumina-22751` |
| Codemagic workflow | `ios-workflow`, tags `build-*` | `ios-staging-workflow`, tags `staging-*` only |
| App Store Connect | the existing Lumina record | a NEW, separate record |

The client side is on branch `backend/dealer-tools-staging-env`. The backend (rules, functions) is set up in another window.

**Do not, at any step:** run `flutterfire configure`, add a `GoogleService-Info.plist` to Xcode, or edit anything under `ios/`. Staging is switched by `--dart-define=LUMINA_ENV=staging`. The bundle id is rewritten only on the Codemagic build machine.

---

## Order and what blocks what

```
F1 ─ F2 Blaze ─┬─ F6 Storage (optional)
               └─ backend Cloud Functions deploy (other window)
F3 Auth providers ──────────────────────────────┐
F5 register iOS app ── H1 hand back ── I commit ─┤
A1 App ID ── S1 app record ── S3 testers ────────┼── C6 first staging build
C3 / C4 Codemagic checks ────────────────────────┘
```

- **F5 blocks C6.** Until the staging `apiKey` and `appId` are in the code, the workflow stops at its first step. If someone did build it, the app would refuse to start.
- **A1 blocks S1 and C6.** The bundle id appears in the App Store Connect dropdown only after A1. Signing also needs it.
- **S1 blocks C6.** An upload needs a record with that bundle id.
- **F2 blocks F6** and the backend window's function deploys.
- F3, S3, C3 and C4 can be done in any order before C6.

---

## F. Firebase console — project `nex-gen-lumina-22751`

Already done: the project exists, and Firestore `(default)` exists in `nam5`. Both were read with the CLI on 2026-11-17. No iOS app is registered yet.

**F1. Open the right project.**
1. Go to console.firebase.google.com.
2. Click **Nex-Gen Lumina**.
3. Click the gear icon, then **Project settings**.
4. Check that **Project ID** reads exactly `nex-gen-lumina-22751`. Check that **Project number** reads `431625047151`.

**F2. Pay-as-you-go billing (Blaze).** *Blocks: F6, and the backend function deploys.*
1. Click the gear icon, then **Usage and billing**, then the **Details & settings** tab.
2. Click **Modify plan**, then **Blaze**, then **Continue**.
3. Choose a billing account (or create one), then click **Purchase**.
4. Set a budget alert, because anonymous sign-in is on. On the same page, click **Set budget alert**. Google Cloud Billing opens.
5. Click **Create budget**. Set a monthly amount (for example $25) and alerts at 50 %, 90 % and 100 %. Click **Finish**.

**F3. Authentication: Email/Password and Anonymous.**
1. In the left menu, click **Build**, then **Authentication**, then **Get started** (first time only).
2. On the **Sign-in method** tab, click **Email/Password**. Turn on **Enable**. Leave **Email link** off. Click **Save**.
3. Click **Add new provider**, then **Anonymous**. Turn on **Enable**. Click **Save**.

Staff PIN sessions sign in anonymously first, then trade the session for a custom token. The custom token is minted by a Cloud Function: that part belongs to the backend window and needs F2.

**F4. Firestore.** Already created. Nothing to do here; rules are the backend window's job.

**F5. Register the staging iOS app.** *Blocks: H1, then C6.*
1. Click **Project Overview** (top left).
2. Click **+ Add app**, then the **iOS** (Apple) icon.
3. **Apple bundle ID:** `com.nexgenled.command.staging` (exactly, all lower case).
4. **App nickname:** `Lumina Staging`.
5. **App Store ID:** leave blank.
6. Click **Register app**.
7. Click **Download GoogleService-Info.plist** and keep the file somewhere outside the repo. **Do not add it to Xcode or to the repo.**
8. Click **Next**, **Next**, then **Continue to console**. Skip every SDK step: the code is already done.

**F6. Storage (optional; only for photo uploads in staging).** *Needs F2.*
1. Click **Build**, then **Storage**, then **Get started**.
2. Choose the same region as Firestore (US multi-region).
3. Pick **Start in production mode**. The backend window deploys the real rules.
4. When it finishes, note the bucket name at the top. The code assumes `gs://nex-gen-lumina-22751.firebasestorage.app`. If yours differs, hand it back (H2).

If you skip F6, photo uploads fail in staging with an error message. Nothing else is affected.

**F7. Restrict the staging iOS API key (recommended).**
1. Go to console.cloud.google.com and select project **nex-gen-lumina-22751**.
2. Click **APIs & Services**, then **Credentials**.
3. Open **iOS key (auto created by Firebase)**.
4. Under **Application restrictions**, choose **iOS apps**. Add `com.nexgenled.command.staging`. Click **Save**.
5. Optional: for Google address autocomplete in staging, enable **Places API (New)** in this project. Without it, staging uses the free fallback (Photon) automatically.

---

## A. Apple Developer — developer.apple.com/account

**A1. App ID for the staging bundle id.** *Blocks: S1 and C6.*
1. Click **Certificates, Identifiers & Profiles**, then **Identifiers**, then the **+** button.
2. Choose **App IDs**, then **Continue**. Choose **App**, then **Continue**.
3. **Description:** `Lumina Staging`.
4. **Bundle ID:** choose **Explicit** and enter `com.nexgenled.command.staging`.
5. Under **Capabilities**, tick **Access Wi-Fi Information** only. The staging build keeps that entitlement, so the home/away check works.
6. Leave **Push Notifications**, **Sign in with Apple**, **Associated Domains** and **App Groups** unticked. Staging has no push by design; the build removes the push entitlement.
7. Click **Continue**, then **Register**.

Do not create a provisioning profile by hand. Codemagic creates the App Store profile for this id on the first build (`fetch-signing-files --create`).

---

## S. App Store Connect — appstoreconnect.apple.com

**S1. New app record.** *Needs A1. Blocks C6.*
1. Click **Apps**, then the **+** button, then **New App**.
2. **Platforms:** iOS.
3. **Name:** `Lumina Staging`. Names must be unique on the App Store. If it is taken, use something like `Lumina Staging NexGen`: this name appears only in App Store Connect and TestFlight. The home-screen name comes from the build.
4. **Primary Language:** English (U.S.).
5. **Bundle ID:** choose `com.nexgenled.command.staging` from the dropdown.
6. **SKU:** `lumina-staging`.
7. **User Access:** Full Access.
8. Click **Create**.

**S2. Note the Apple ID (for the ledger only).** In the new app, click **App Information** (left side). Copy the numeric **Apple ID**. The workflow does not need it.

**S3. Internal testers.**
1. Click the **TestFlight** tab, then the **+** next to **Internal Testing**.
2. Name the group `Staging`. Tick **Enable automatic distribution**. Click **Create**.
3. Add yourself, and anyone else who should get staging builds. Testers must be App Store Connect users on your team.

**S4. Skip:** Test Information, external groups and Beta App Review. The staging workflow uploads only (`submit_to_testflight: false`), and internal testers get every processed build without review.

---

## C. Codemagic — codemagic.io

The staging workflow lives in `codemagic.yaml` and needs no new variables and no new integration. It reuses two things production already has:

- the App Store Connect API key **NexGen**, which works across the team and uploads to whichever record matches the IPA's bundle id;
- the environment group **`ios-workflow`**, for the distribution-certificate key that `fetch-signing-files --create` needs.

**C1. Branch.** Codemagic reads `codemagic.yaml` from the commit a tag points at. So a `staging-*` tag must point at a commit that contains this branch's `codemagic.yaml`.

**C2. See the workflow.**
1. Open the Lumina app in Codemagic.
2. In the branch selector, choose `backend/dealer-tools-staging-env`.
3. **iOS Staging (Lumina Staging)** should appear next to **iOS Release**.

**C3. Check the API key's role.**
1. Click **Teams**, then your team, then **Integrations**.
2. Open **Developer Portal** (App Store Connect API) and confirm the key named **NexGen** is listed.
3. In App Store Connect, open **Users and Access**, then **Integrations**, then **App Store Connect API**. Confirm that key's access is **Admin** or **App Manager**, which the first build needs to create the staging profile. Production already creates profiles with it, so it almost certainly is.

**C4. Check the `ios-workflow` group holds nothing app-specific.**
1. In the Lumina app, click **Environment variables**.
2. Open group **`ios-workflow`**. Read the variable names only; do not reveal values.
3. Expected: team-level signing names only (for example `CERTIFICATE_PRIVATE_KEY`).
4. If you see anything app-specific (a bundle id, a Firebase project id, an App Store app id), stop and send me the names (H3). I will split the group. The staging workflow refuses a wrong `BUNDLE_ID` either way.

**C5. Triggers.**
1. Click **Webhooks** and confirm the repository webhook is present. It already is, because `build-*` tags trigger.
2. Triggers come from the `triggering:` block in the YAML: `staging-*` tags only.
3. A manual **Start new build** of the staging workflow on a branch is refused by its first step.

**C6. First staging build.** *Needs F5 and H1 (values committed), A1, S1 and C4.*
1. I commit the staging values (H1). The tag is then pushed by you, or by me when you say so: `git tag staging-1 <sha>` and `git push origin staging-1`.
2. Expected log, in order:
   1. staging guard OK;
   2. tests and analyze green;
   3. "CI-clone changes" diff (bundle id, name, URL scheme, entitlements);
   4. signing files fetched (the first run creates the staging App Store profile);
   5. build;
   6. "OK: staging IPA verified";
   7. upload.
3. The build shows in App Store Connect under **Lumina Staging**, then **TestFlight**, after processing (usually 10–30 min). Install it from the TestFlight app. It sits beside the real Lumina.

---

## Build numbers — please read (decision D1)

- Staging numbers 1, 2, 3 … from Codemagic's **per-workflow** counter (`BUILD_NUMBER`), on its own App Store Connect record. That record never collides with production's.
- Production reads `PROJECT_BUILD_NUMBER`. Codemagic advances that counter for **every** build of **every** workflow in the app, so **each staging build makes production's next build number skip one**. Production's YAML is unchanged and Apple accepts gaps (numbers only have to rise), but the TestFlight numbers in `docs/BUILD_LEDGER.md` will jump.
- The only way to avoid it is a second Codemagic app on the same repo. That is worse: both apps would run `ios-workflow` on every `build-*` tag, uploading twice.
- Recommendation: accept the gaps and note them in the ledger.
- Do not rename `ios-staging-workflow`: its counter would restart at 1, and uploads would then be rejected as duplicates.

---

## What does not work in staging, by design

| Feature | In staging |
|---|---|
| Push notifications | Off. The build strips `aps-environment` and FCM auto-init, and the app never asks for notification permission. Joining a Neighborhood Sync group still works; it just stores no push token. |
| Sign in with Apple, associated domains, App Check | Not used anywhere in the app today, so nothing to break. |
| Lumina Bridge pair / reboot / reset | **Blocked** in the app (decision D2). Every bridge is flashed for the production project, so pairing one from staging would point a real bridge at a staging account. Reading bridge status still works. |
| Android, web | Refuse to start. Staging is iOS only. An Android staging build would also replace the real app, which has the same package name. |
| `lumina://` links | Staging registers `lumina-staging://`, so `lumina://` always opens the real app. Deep links do nothing in staging. |
| Alexa / Google Home linking | Opens the **production** skill (decision D3). |

**Controllers are shared hardware.** The staging app finds and controls any WLED controller on the phone's Wi-Fi, exactly like the real app. That includes writing schedules into the controller's timers. Point it at a bench controller only.

---

## H. What to hand back

| # | What | Where it comes from | Needed for |
|---|---|---|---|
| H1 | Either the two strings `API_KEY` and `GOOGLE_APP_ID` from the staging `GoogleService-Info.plist` (F5), or just "registered": I then read them myself with `firebase apps:sdkconfig IOS --project nex-gen-lumina-22751`, which only reads | F5 | C6 |
| H2 | The Storage bucket name, only if it is not `nex-gen-lumina-22751.firebasestorage.app` | F6 | photo uploads |
| H3 | The variable **names** in Codemagic group `ios-workflow` (never values), or "only signing" | C4 | C6 |
| H4 | Your answers to decisions D1–D4 below | — | — |
| H5 | The staging app's numeric Apple ID (optional) | S2 | ledger only |

**Decisions**

- **D1.** Accept production build-number gaps (above)? Recommended: yes.
- **D2.** Keep bridge pair/reboot/reset blocked in staging? Recommended: yes, until a bridge can be flashed for staging.
- **D3.** Alexa / Google Home buttons in staging open the production skill, and linking there links a production account. Recommended: hide them in staging (a small change).
- **D4.** The staging `apiKey` will be committed in `lib/config/firebase_options_staging.dart`, the same way production's is, and this repo is public. With anonymous sign-in on, anyone holding the key can create staging users. F2's budget alert and F7's restriction limit that. The alternative is to keep the key out of git as a Codemagic secret passed with `--dart-define`. Recommended: commit it, with F7 done.
