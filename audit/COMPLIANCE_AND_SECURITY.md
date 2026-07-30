# Lumina — Compliance & Security Pre-Submission Audit

**Window B.** Scope: store-rejection surface + user-data exposure only. Feature logic is Window A's charter and was not audited here.
**Repo state:** `main` @ `393af46`, working tree clean (only untracked `audit/`).
**Date:** 2026-07-30
**Method:** static read of the repo, plus live read-only queries against Firebase project `icrt6menwsv2d8all8oijs021b06s5` (deployed rulesets, Identity Platform config, App Check service state) using the already-authenticated gcloud/firebase CLI. Nothing was written, deployed, or changed.

### How to read this

Every finding cites `path:line`. Where I could verify something against the live project I say so and give the command's result. Where I could not, it is in §4 "Verify in console" with the specific thing to check — not asserted.

**Three things I could not do, stated up front:**
1. I did not run the Firestore emulator suite. The isolation matrix in §2 is **derived from the deployed rule text**, not executed. Rule-derived results are strong for *deny* claims and strong for *allow* claims where the rule is an unconditional grant, but they are not the same as a passing test.
2. I have no App Store Connect or Play Console access. Every declaration-side item (nutrition labels, data safety form, age rating, review notes content, whether the reviewer account exists in Firebase Auth) is in §4.
3. iOS has never been pod-installed in this checkout (no `ios/Podfile.lock`, no `ios/Pods/`), so pod-level privacy manifests were checked from the pub cache rather than from a resolved Pods tree.

---

## 1. Submission-blocking checklist

| # | Item | Verdict | Evidence |
|---|---|---|---|
| 1.1 | Completeness — placeholder/lorem/dev screens | **PASS** — revised from CONDITIONAL, see §2.6(b) | No `coming soon` / `lorem` / `placeholder` / `TODO:` strings in any `lib/**/*.dart` UI literal. `kSimulationMode` is **`false`** — [app_providers.dart:17](lib/app_providers.dart#L17). CLAUDE.md claims it is hardcoded `true`; that doc is stale. Window A's stub findings (their F-6 false-success controls, F-8 toast) sit on `/commercial`, which has **no in-app navigation and no deep-link entry vector** — §2.6(b). `/media` and `/dealer/payouts` were checked directly and contain no stubs. Two cosmetics: login screen renders a hardcoded `'v2.2.0'` — [login_page.dart:541](lib/features/auth/login_page.dart#L541) — vs `2.5.10+58` in [pubspec.yaml:5](pubspec.yaml#L5); and Window A's "zero raw exception strings in UI" is **not quite right** — [payout_approval_screen.dart:223,250,264](lib/features/referrals/screens/payout_approval_screen.dart#L223) render `Failed: $e`. P3, unreachable screen. |
| 1.2 | Demo/reviewer account path | **PASS (code) / UNVERIFIED (account exists)** | Reviewer identified by email at [reviewer_seed_service.dart:18-26](lib/services/reviewer_seed_service.dart#L18-L26); profile + installation seeded on first sign-in at [:31-121](lib/services/reviewer_seed_service.dart#L31-L121); repository forced to `DemoWledRepository` **before** any IP/connectivity gate at [wled_providers.dart:152-155](lib/features/wled/wled_providers.dart#L152-L155); dashboard hardware check short-circuits at [wled_dashboard_page.dart:206-209](lib/features/dashboard/wled_dashboard_page.dart#L206-L209); route guards bypass the linked-installation requirement at [route_guards.dart:26,201,285,298](lib/route_guards.dart#L26). Chain is genuinely hardware-independent. **The one thing I cannot verify: that `reviewer@Nex-GenLED.com` exists in Firebase Auth with a known password.** See §4. |
| 1.3 | 5.1.1(v) in-app account deletion | **PARTIAL** | Button exists and is reachable — [security_settings_screen.dart:175-188](lib/features/site/security_settings_screen.dart#L175-L188), route [app_router.dart:1006](lib/app_router.dart#L1006). Backing call deletes **only the top-level user document** — [user_service.dart:277-284](lib/services/user_service.dart#L277-L284) — then the auth user. No subcollection cascade, no Storage cleanup. See F-5. |
| 1.4 | Privacy manifests | **FAIL (app-level absent)** | No `PrivacyInfo.xcprivacy` anywhere in the repo (glob `**/PrivacyInfo.xcprivacy` → 0 results). Plugin-level spot check: `shared_preferences_foundation`, `flutter_secure_storage`, `geolocator_apple`, `image_picker_ios`, `url_launcher_ios`, `connectivity_plus`, `network_info_plus`, `permission_handler_apple` all ship one; `path_provider_foundation-2.6.0`, `flutter_blue_plus-2.2.1`, `speech_to_text-7.3.0` do not. See F-9. |
| 1.5 | Info.plist purpose strings | **PARTIAL** | All required keys present — [Info.plist:60-99](ios/Runner/Info.plist#L60-L99). `NSLocalNetworkUsageDescription` present **and** `NSBonjourServices` correctly declares `_wled._tcp` + `_http._tcp` at [:48-52](ios/Runner/Info.plist#L48-L52) — this is the one most likely to have been missed and it is right. Two strings describe capabilities the app does not have. See F-10. |
| 1.6 | Nutrition labels vs. reality | **MISMATCH (policy side)** | Outbound flows enumerated below. Published privacy policy at `nex-genled.com/privacy-policy` (fetched, live, genuine) lists device IDs, IP/network location, name, email, usage/crash data — and **does not mention photos or physical addresses**, both of which the app collects and transmits. See F-6. |
| 1.7 | Sign in with Apple | **PASS / N/A** | No social login exists. `grep` for `signInWithApple|GoogleSignIn|google_sign_in|FacebookAuth` → 0 matches in `lib/`; no such packages in [pubspec.yaml](pubspec.yaml). Live Identity Platform config confirms only `email` (password) + `anonymous` are enabled. Equivalence requirement does not trigger. |
| 1.8 | 3.1.1 IAP | **PASS** | No `in_app_purchase`/StoreKit dependency, no subscription/paywall/premium surface, no external purchase link (`grep` for shop/store/buy/checkout/stripe URLs → 0). Dealer hardware ordering (`/dealer_orders`, status `payment_pending → payment_confirmed`) is B2B physical-goods ordering with no in-app payment collection — outside 3.1.1. |
| 1.9 | 5.2 Intellectual property | **RISK — but not the risk the brief assumed** | The app does **not** display third-party logos. `BrandLibraryEntry` has no logo/icon field — [brand_library_entry.dart:16-60](lib/models/commercial/brand_library_entry.dart#L16-L60) — it carries `company_name` + `colors` only. Brandfetch is never called from `lib/` or `functions/`; it is used offline by [scripts/seed_brand_library.js:349-352](scripts/seed_brand_library.js#L349-L352) to populate a corporate-curated Firestore catalog. The live IP surface is **sports marks**: 155+ full team names and league names hardcoded and shown in-app — [team_color_database.dart:5,302-308](lib/data/team_color_database.dart#L302-L308). See F-11. |
| 1.10a | Export compliance | **QUESTIONABLE** | `ITSAppUsesNonExemptEncryption = false` — [Info.plist:58-59](ios/Runner/Info.plist#L58-L59). App ships `encrypt: ^5.0.3` and an `EncryptionService` that encrypts user data ([user_service.dart:293](lib/services/user_service.dart#L293)). See F-14. |
| 1.10b | Support + privacy URLs live | **PARTIAL** | Privacy policy live and real (fetched). Site has a `/contact` page. **No Terms of Service page exists on the site or in the app.** In-app the only legal link is Privacy Policy — [settings_page.dart:538-543](lib/features/site/settings_page.dart#L538-L543). |
| 1.10c | Orientation / iPad / min iOS | **PASS** | Portrait + both landscape on iPhone, all four on iPad — [Info.plist:31-43](ios/Runner/Info.plist#L31-L43). Deployment target 15.0 ([Podfile:2](ios/Podfile#L2), `IPHONEOS_DEPLOYMENT_TARGET = 15.0`). Sane. |
| 2.2 | Play account deletion (in-app **and** web URL) | **FAIL (web URL)** | In-app path exists (1.3). No public deletion-request URL on `nex-genled.com`; the privacy policy directs users to email `General@Nex-GenLED.com`. See F-8. |
| 2.3 | Target API level | **PASS TODAY / DEADLINE RISK** | `targetSdk = 35`, `compileSdk = 35`, `minSdkVersion = 24` — `android/app/build.gradle`. See F-13 for the deadline. |
| 2.4 | Foreground service types | **PASS** | No FGS ships. Both our declarations *and* the plugin-injected copies are stripped via `tools:node="remove"` — [AndroidManifest.xml:27-30](android/app/src/main/AndroidManifest.xml#L27-L30) (permissions), [:131-140](android/app/src/main/AndroidManifest.xml#L131-L140) (geolocator + flutter_background_service services). `RECEIVE_BOOT_COMPLETED` and `AD_ID` likewise removed. This is unusually well done. |
| 2.5 | Android 13+ notification permission | **PASS** | `POST_NOTIFICATIONS` declared — [AndroidManifest.xml:56](android/app/src/main/AndroidManifest.xml#L56). Runtime request fires for all users at cold start via [main.dart:204](lib/main.dart#L204) → [sync_notification_service.dart:153](lib/features/neighborhood/services/sync_notification_service.dart#L153). |
| 2.6 | 16 KB page-size compatibility | **PASS (ELF) / UNVERIFIED (zip)** | Parsed `PT_LOAD` `p_align` on the built arm64 libs: `libapp.so` = 0x10000, `libflutter.so` = 0x10000, `libdatastore_shared_counter.so` = 0x4000 — all ≥ 16 KB. Only three native libs in the merged set. Flutter 3.41.2 / Dart 3.11.0. AGP is 8.3.2 (`android/build.gradle`), which predates automatic 16 KB *zip* alignment; ELF alignment is satisfied but archive-level alignment on the actual upload artifact is unverified. See §4. |
| 2.7 | Unused manifest permissions | **PASS, one to justify** | Every declared permission maps to a real use. `RECORD_AUDIO` ([:54](android/app/src/main/AndroidManifest.xml#L54)) is used by `speech_to_text` for voice control — legitimate, but see F-10 for the iOS string that over-claims it. `usesCleartextTraffic="true"` ([:84](android/app/src/main/AndroidManifest.xml#L84)) is required for LAN HTTP to WLED but is global rather than domain-scoped (F-15). |
| 2.8 | Restricted permissions needing a declaration form | **PASS** | No `ACCESS_BACKGROUND_LOCATION` (deliberately, with rationale at [:10-16](android/app/src/main/AndroidManifest.xml#L10-L16)), no `QUERY_ALL_PACKAGES`, no SMS/Call Log, no `MANAGE_EXTERNAL_STORAGE`, no FGS. Nothing that triggers a declaration form. |
| 3.1 | **Firestore rules deployment drift** | **PASS — VERIFIED LIVE** | Fetched deployed ruleset `6333afad-5add-4fbb-9652-124d1e21de80` (release `cloud.firestore`, updated 2026-07-25T18:19:43Z) via the Firebase Rules REST API and diffed against `firestore.rules` at HEAD: **0 differing lines**. Storage ruleset `5a1247a5-...` (updated 2026-01-20) differs from `storage.rules` **in comments and trailing newline only** — semantically identical. **There is no drift.** |
| 4.1 | ToS / EULA / privacy reachable in-app | **FAIL** | Privacy Policy only. No ToS, no EULA — anywhere. |
| 4.2 | Liability line (supplemental/decorative, not life-safety, not UL 924) | **FAIL** | `grep -rniE "UL 924\|life.?safety\|decorative only\|supplemental\|emergency lighting"` across `lib/`, `docs/`, `marketing/` → **zero matches**. The language does not exist in this repo. See F-4. |

---

## 2. Isolation matrix

**Deployed rules = repo rules (verified, §1 row 3.1), so this matrix describes production.**

### The multiplier: anonymous auth is enabled in production

```
GET identitytoolkit.googleapis.com/admin/v2/projects/icrt6.../config
  → signIn.anonymous.enabled = true
  → signIn.email.enabled = true (passwordRequired)
```

This is the single most important fact in this report. Every rule written as `request.auth != null` does **not** mean "a Lumina customer". It means **anyone on the internet**, with no account, no email, no payment, and no rate limit — one unauthenticated REST call to `accounts:signUp` with the public API key from [firebase_options.dart:50](lib/firebase_options.dart#L50) mints a token. Read every row below with that substitution in mind.

The grant is load-bearing, not accidental: the installer wizard writes customer docs under `signInAnonymously()`, and the rules say so explicitly at [firestore.rules:283-292](firestore.rules#L283-L292). It cannot simply be deleted without breaking installs.

### UID harvest — Window A's open question, now CONFIRMED

Window A's handoff ([audit/HANDOFF_TO_WINDOW_B.md:97-133](audit/HANDOFF_TO_WINDOW_B.md#L97-L133)) confirmed the cross-tenant *write* grants but flagged that the whole severity call hinged on an unverified UID-harvest step. It is verified. Three independent sources, all `allow read: if request.auth != null` with no query-shape constraint (so `list` is permitted, not just `get`):

| Source | Rule | Field harvested | Confirmed by |
|---|---|---|---|
| `/bridge_registry/{deviceId}` | [firestore.rules:677](firestore.rules#L677) | `pairedUid` (customer UID), plus `ip` (LAN IP) and `bridgeEmail` | Firmware writes them in cleartext — [esp32-bridge/src/main.cpp:1041-1047](esp32-bridge/src/main.cpp#L1041) (`pairedUid`, `ip`, `status`, `bridgeEmail`). App's own reader confirms the shape — [bridge_discovery_service.dart:118-119](lib/services/bridge_discovery_service.dart#L118-L119). The client filters `status == 'unpaired'`; the **rule does not**, so an attacker simply omits the filter. |
| `/neighborhoods/{groupId}` | [firestore.rules:1751](firestore.rules#L1751) | `memberUids[]`, `creatorUid` | [neighborhood_models.dart:132-134](lib/features/neighborhood/neighborhood_models.dart#L132-L134) |
| `/installations/{installationId}` | [firestore.rules:1152-1154](firestore.rules#L1152-L1154) | `primary_user_id` | Rule comment at [:1144-1151](firestore.rules#L1144) explicitly flags this disjunct as knowingly left open |

**Chain is closed: anonymous token → list `/bridge_registry` → every paired customer's UID → the write grants below.**

### Matrix

Legend — **DENY** = rule provably denies. **ALLOW** = unconditional grant in rule text. All results are rule-derived (static), not emulator-executed.

| # | Boundary | Result | Rule | Notes |
|---|---|---|---|---|
| I-1 | Customer A **reads** B's profile `/users/{B}` | **DENY** | [firestore.rules:263-268](firestore.rules#L263-L268) | Scoped to owner / media-admin / matching dealer staff. Correct. |
| I-2 | Customer A **overwrites** B's profile | **ALLOW** ❌ | [firestore.rules:355-360](firestore.rules#L355-L360) | `|| request.auth != null` sits outside the `cannotModifyCriticalFields()` guard, so that guard constrains only the owner branch. Includes B's **`schedules` array** — [user_model.dart:245-246,648](lib/models/user_model.dart#L245-L246) confirms schedules are still a field on the user doc. **Destructive: A can blank B's entire schedule set.** |
| I-3 | Customer A **creates** a doc at `/users/{B}` | **ALLOW** ❌ | [firestore.rules:344-349](firestore.rules#L344-L349) | Same paren structure. |
| I-4 | Customer A **reads** B's controllers | **ALLOW** ❌ | [firestore.rules:383](firestore.rules#L383) | Exposes controller IPs and names. |
| I-5 | Customer A **deletes** B's controllers | **ALLOW** ❌ | [firestore.rules:396](firestore.rules#L396) | **Data loss.** Also `create` ([:389](firestore.rules#L389)) and `update` ([:392](firestore.rules#L392)). |
| I-6 | Customer A reads B's **pixel map** | **DENY** | [firestore.rules:412-418](firestore.rules#L412-L418) | Owner-only read; staff-claim write. Explicitly hardened, and the comment bans the broad pattern for new rules. The ruleset is internally inconsistent — this is the correct shape, four lines below I-4/I-5 which are not. |
| I-7 | Customer A reads B's **schedules subcollection** | **DENY** | [firestore.rules:436-438](firestore.rules#L436-L438) | Owner-only, no fallback. Correct. (Moot while the array backend is live — flag `config/schedules_subcollection` defaults `enabled=false`.) |
| I-8 | Customer A reads B's properties / geofences / roofline / commands / bridge_status | **DENY** | [:470](firestore.rules#L470), [:485](firestore.rules#L485), [:502](firestore.rules#L502), [:443](firestore.rules#L443), [:458](firestore.rules#L458) | All `canReadUserData`-gated. Correct — this is where home addresses and geofence coordinates live. |
| I-9 | Customer A writes into B's `/referrals` | **ALLOW** ⚠️ | [firestore.rules:546,550](firestore.rules#L546-L550) | Deliberate (prospect writes to referrer's subcollection). Low impact; no read exposure. |
| I-10 | Dealer X reads dealer Y's customers | **DENY** | [firestore.rules:88-90,263-268](firestore.rules#L88-L90) | The D3-S2 sweep that removed `hasMediaAccess()`'s dealer member did its job. |
| I-11 | Dealer X reads/writes Y's pricing, inventory, catalog, config, ship-to | **DENY** | [:1577](firestore.rules#L1577), [:1599-1606](firestore.rules#L1599), [:1646-1653](firestore.rules#L1646), [:1667-1674](firestore.rules#L1667), [:1684-1691](firestore.rules#L1684), [:1701-1708](firestore.rules#L1701) | All 19 D3-S2 sites verified individually scoped. The ship-to fix ([:1661-1675](firestore.rules#L1661)) closed a shipment-redirection hole. Good work. |
| I-12 | Customer reads/writes their own dealer's pricing | **DENY** | [firestore.rules:55-61](firestore.rules#L55-L61) | `isDealerStaffAccount()` requires `user_role in ['dealer','admin']`, not just a matching `dealer_code`. Correct — this was a real hole and it is closed. |
| I-13 | Any user enumerates the dealer network | **DENY** | [firestore.rules:1003-1005](firestore.rules#L1003-L1005) | |
| I-14 | Any user lists `/installers` (cleartext `fullPin`) | **DENY** | [firestore.rules:1120](firestore.rules#L1120) | Admin/owner only. The escalation path documented at [:1058-1120](firestore.rules#L1058) is closed. PINs are still cleartext at rest — F-12. |
| I-15 | Any user reads every installation record | **ALLOW** ⚠️ | [firestore.rules:1152-1154](firestore.rules#L1152-L1154) | Exposes `primary_user_id`, `dealer_code`, `installer_code`, and per [reviewer_seed_service.dart:110-113](lib/services/reviewer_seed_service.dart#L110-L113) the doc shape includes `address`, `city`, `state`, `zipCode`. **This is a customer-address read path.** Knowingly left open. |
| I-16 | Non-member **reads** any neighborhood group | **ALLOW** ❌ | [firestore.rules:1751](firestore.rules#L1751) | Group doc carries `streetName`, `city`, `latitude`, `longitude`, `inviteCode` — [neighborhood_models.dart:128-140](lib/features/neighborhood/neighborhood_models.dart#L128-L140). **Precise home-block coordinates of every crew, fleet-wide.** |
| I-17 | Non-member **reads** any crew's member roster | **ALLOW** ❌ | [firestore.rules:1775](firestore.rules#L1775) | Bare `request.auth != null` — not even membership-scoped. Member docs carry `displayName`, `controllerIp`, `ledCount` — [neighborhood_models.dart:301-318](lib/features/neighborhood/neighborhood_models.dart#L301-L318). |
| I-18 | Non-member **joins** a crew uninvited | **ALLOW** ❌ | [firestore.rules:1761-1766](firestore.rules#L1761-L1766) + [:1785](firestore.rules#L1785) | Group `update` allows any caller who puts their own uid in `memberUids`; member `create` allows self-create. **`inviteCode` is never checked server-side** — the rule comment says membership toggling is "enforced app-side". Combined with I-16 (invite codes are readable anyway) there is no barrier at all. |
| I-19 | Having self-joined, non-member reads/writes crew commands, schedules, syncEvents, sessions, autopilot | **ALLOW** ❌ | [firestore.rules:1806-1828](firestore.rules#L1806-L1828) | `isGroupMemberLookup()` checks only that `members/{uid}` exists — which I-18 lets the attacker create. |
| I-20 | Self-joined attacker drives **other members' lights** via crew fanout | **DENY today / ALLOW if the flag flips** ⚠️ | [applySyncPattern.ts:134-190](functions/src/applySyncPattern.ts#L134-L190) | The function is well built: ID-token verified ([:84](functions/src/applySyncPattern.ts#L84)), `decoded.uid == initiatorUid` ([:120](functions/src/applySyncPattern.ts#L120)), membership gate ([:134-147](functions/src/applySyncPattern.ts#L134)), fanout targets cross-checked against `memberUids[]` ([:437-449](functions/src/applySyncPattern.ts#L437)), consent-skip honored, rate limited. **But every one of those gates is satisfied by an I-18 self-join.** Held shut only by `config/sync_fanout.enabled = false` ([firestore.rules:1487-1494](firestore.rules#L1487-L1494), console-only flip). **Do not flip that flag until I-18 is fixed.** |
| I-21 | Attacker hijacks an already-paired bridge | **DENY** | [firestore.rules:691-695](firestore.rules#L691-L695) | Pairing-request update requires `resource.data.status == 'unpaired'`. Correct. |
| I-22 | Attacker claims an **unpaired** bridge they don't own | **ALLOW** ⚠️ | [firestore.rules:691-695](firestore.rules#L691-L695) | Any authed caller may write `pendingUid = own uid` on any unpaired bridge, and I-16-class listing makes unpaired bridges enumerable. Window of exposure = between a bridge powering on and its owner completing pairing. What binds device→account is first-writer-wins on `pendingUid`, not proof of possession. |
| I-23 | Attacker registers a `deviceId` they don't own | **DENY** | [firestore.rules:682](firestore.rules#L682) | `create` requires the shared bridge account's email. Note: **one shared credential for the whole fleet** ([:646](firestore.rules#L646)), acknowledged in-comment as future work — any extracted bridge firmware yields it. |
| I-24 | Customer A reads B's **Storage** (house photos) | **ALLOW** ❌ | [storage.rules:5-7](storage.rules#L5-L7), **verified deployed** | `match /users/{userId}/{allPaths=**} { allow read: if request.auth != null; }`. `read` grants `list`. Combined with the confirmed UID harvest: anonymous token → UID list → `list` + download every customer's house photo. Write is correctly owner-scoped. |
| I-25 | Sales signatures / job photos in Storage | **DENY (fails closed)** ⚠️ | [storage.rules](storage.rules) has no `sales_jobs/**` rule | Uploads target `sales_jobs/{jobId}/signature_*.png` ([customer_signature_screen.dart:83](lib/features/sales/screens/customer_signature_screen.dart#L83)) and `sales_jobs/{jobId}/prospect/photo_*.jpg` ([prospect_info_screen.dart:163](lib/features/sales/screens/prospect_info_screen.dart#L163)). Default-deny → these writes fail. Safe direction, but it is an uncovered path — and it means customer contract signatures are not being stored. Flagging for Window A. |
| I-26 | Unauthenticated caller invokes `createCustomerAccount` | **ALLOW** ❌ | [createCustomerAccount.ts:135-165](functions/src/createCustomerAccount.ts#L135-L165) | No `request.auth` check of any kind. See F-2. |
| I-27 | Unauthenticated caller invokes `mintStaffToken` | **ALLOW by design** ⚠️ | [staffAuth.ts:424-440](functions/src/staffAuth.ts#L424-L440) | Deliberate (PIN is the credential). Mitigated by per-IP rate limit ([:461-472](functions/src/staffAuth.ts#L461)), SHA-256 hashing, audit log, `dealer.isActive` enforcement. Residual: 4–6 digit PIN, IP-bucketed limiting only, no App Check. See F-7. |
| I-28 | Other callables enforce auth | **PASS** | | `openaiProxy` ([index.js:159-163](functions/index.js#L159-L163)), `processScheduleCommand` ([:656](functions/src/processScheduleCommand.ts#L656)), `sendSyncNotification` ([:34](functions/src/sendSyncNotification.ts#L34)), `redeemReferralCode`, `notifyDay2Team`, `notifyReferrerOfApproval`, `generateAlexaAuthCode`, and all three backfills (which additionally require an `admin: true` claim). `createCustomerAccount` is the sole gap. |

---

## 2.5 Cross-window reconciliation (Window A landed after my first pass)

Window A's `FEATURE_STATUS_MATRIX.md` arrived at 11:47. Three of its findings land inside my charter. I re-verified each against the code rather than inheriting it.

### (a) Can a reviewer reach the false-success surfaces? — router role gating is weaker than it looks

Window A rated their F-6 (Commercial Schedule: "All channels paused" / "Running default" / "Override applied", all three backed by `// TODO`) as **P2 because `/commercial` is orphaned and no client navigates to it**. That reasoning is sound as far as *in-app navigation* goes. It is not the whole reachability story, and the gap is in my charter, so I checked the router myself.

Three verified facts from [route_guards.dart:50-310](lib/route_guards.dart#L50-L310):

1. **The demo-browsing restricted list omits the commercial surface.** [route_guards.dart:54](lib/route_guards.dart#L54) is `const restricted = ['/installer', '/sales', '/admin', '/dealer']`. `/commercial` and `/media` are not in it. When `isDemoBrowsingFlag` is set, every other route returns `null` (allowed) — including for an **unauthenticated** session, via the `isDemoBrowsingFlag` disjunct at [:93](lib/route_guards.dart#L93). The demo is offered on the login screen ([login_page.dart:489](lib/features/auth/login_page.dart#L489)), which is a path a reviewer plausibly takes.
2. **There is no per-route role gate for `/dealer/*` or `/media`.** `isInstallerRoute` covers only `/installer` + `/admin`, `isSalesRoute` only `/sales` ([:71-74](lib/route_guards.dart#L71-L74)). Everything else falls through to the generic protected-route branch, which for a customer with `installation_role == 'primary'` and a valid installation ends in an unconditional `return null` — allow ([:294-296](lib/route_guards.dart#L294)). So `/dealer/payouts` and `/media` are router-reachable by an ordinary signed-in customer.
3. ~~**Both platforms register the `lumina://` scheme**, so Window A's seven orphaned routes are addressable.~~ **RETRACTED — see §2.6(b). This is false, and I should not have repeated it from Window A without checking.** The `lumina://` scheme is registered, but nothing maps a URI path to a GoRouter route. Deep links are handled exclusively by [deep_link_service.dart:44-90](lib/features/voice/deep_link_service.dart#L44-L90), which is a **closed allow-list** (`power`, `brightness`, `scene`, …); an unmatched first path segment returns `null` and no navigation occurs. Flutter's automatic deep-linking is **off on both platforms** — neither `flutter_deeplinking_enabled` (Android manifest) nor `FlutterDeepLinkingEnabled` (Info.plist) is present, verified by grep. **The orphaned routes have no external entry vector.**

**What this does and does not change.** Facts 1 and 2 stand: the router grants by default and role separation rests on Firestore rules, not navigation. But with fact 3 retracted there is **no way for a reviewer or an attacker to reach these screens at all** — no in-app navigation, no deep link. F-25 survives as an architectural finding, not a live exposure, and is re-tiered accordingly.

**Net effect on my 1.1 verdict:** revised to **PASS** — see §2.6(b). The `/commercial` deletion is still worth doing, but it is now hygiene rather than a submission gate.

### (b) Account deletion — Window A found a mechanism I missed, and we disagree on tier

Window A independently reached the same defect (their F-1) and added something I did not have: **deleting an account strands the paired ESP32 bridge in an unrecoverable state.** The pairing lives in the bridge's NVS and in `/bridge_registry`, and [firestore.rules:700](firestore.rules#L700) is `allow delete: if false` — so nothing releases it. Recovery requires physically locating the device and re-flashing.

This is not theoretical, and the proof was sitting in my own P2 pile. I filed the two hardcoded UIDs at [firestore.rules:669-672](firestore.rules#L669-L672) as F-17, "dead weight, tidy it up". Window A correctly read them as **evidence that this failure has already happened twice in production** — the comment at [:649-663](firestore.rules#L649) says one bridge was "physically unlocatable at wipe time". I under-read that. F-17 is re-scoped below.

**On tier:** Window A assigns P0 and explicitly asks you to arbitrate ([their §6 Q2](audit/FEATURE_STATUS_MATRIX.md)). I am **keeping mine at P1**, and I want the disagreement visible rather than silently resolved:

- Their P0 rests on a charter rule of theirs — "orphaning requiring a truck roll = P0" — which is not a limb of my taxonomy.
- Under my taxonomy the honest read is: not approval-preventing (the button works and the account does disappear, which is what a reviewer tests), no cross-tenant exposure, and the retained data is the user's own. That leaves the legal/privacy limb, which is real but is a *retention* failure, not a breach.
- Both of us agree no reviewer hits it. Per your explicit instruction — nothing on the critical path unless approval-preventing — P1 is the disciplined call.

**But the tier is the least useful part of this finding.** Two independent windows converged on it from opposite directions, it has a named guideline, a published privacy-policy commitment behind it, and a twice-realized hardware cost. **It is the first thing I would fix after the F-1/F-2/F-3 rules work, regardless of what letter it carries.**

**Answering Window A's dependency question** (their F-1 remediation step 2, "touches `bridge_registry` write rules — coordinate with Window B"): **no rule change is needed.** A deletion-cleanup Cloud Function runs under the Admin SDK, which bypasses security rules entirely — the same property that makes `createCustomerAccount` dangerous in F-2 makes this safe and easy. Write the function to find `bridge_registry` docs with `pairedUid == uid`, reset `status: 'unpaired'` and clear `pairedUid`. `allow delete: if false` is irrelevant to it. Do **not** relax that rule to accommodate the cleanup — the client must stay unable to touch registry docs (I-21/I-22).

### (c) Non-conflicts worth recording

- Window A rates the reviewer/demo path **COMPLETE** across five call sites. That independently corroborates my §1 row 1.2. Two windows, same conclusion, different methods.
- Their bench result — schedule firing failed reproducibly (their F-2) — **does not touch the review path**. The reviewer account is forced onto `DemoWledRepository` before any network call ([wled_providers.dart:152-155](lib/features/wled/wled_providers.dart#L152-L155)), so a controller-side firing defect cannot surface during App Review. It is a severe launch-readiness item and not a submission item.
- Their §5 lists Neighborhood Sync + fanout as **UNVERIFIED, not traced**. That is the feature-behaviour side; my F-3 covers the rules side. Neither of us traced the other's half — combined, the feature has been audited for isolation but not for correctness.

---

## 2.6 Follow-up analysis (bounded questions, 2026-07-30)

### (a) UID exposure is not closeable by hiding UIDs

**Q1a — already answered in the original Part 3.2; pointing rather than redoing.** The UID-harvest table in §2 ("UID harvest — Window A's open question, now CONFIRMED") already traced Neighborhood Sync as a harvest path and listed it as source 2 of 3: `/neighborhoods/{groupId}` read is `request.auth != null` ([firestore.rules:1751](firestore.rules#L1751)) and the group doc carries `memberUids[]` + `creatorUid` ([neighborhood_models.dart:132-134](lib/features/neighborhood/neighborhood_models.dart#L132-L134)). Rows I-16 through I-20 cover the fanout boundary. **The premise that `bridge_registry` was the only path was never my finding — I documented three.** One is stronger than I recorded, and there is a fourth I missed:

**Q1b — complete enumeration.**

| # | Path | Rule | What it yields | Coverage |
|---|---|---|---|---|
| U-1 | `/referral_codes/{code}` | [firestore.rules:709](firestore.rules#L709) `allow read: if request.auth != null`, no query constraint | **The document body is `{'uid': <user uid>}`** — written at [referral_program_screen.dart:76](lib/features/site/referral_program_screen.dart#L76), read back at [referral_attribution_service.dart:14](lib/features/referrals/services/referral_attribution_service.dart#L14) and [prospect_info_screen.dart:119](lib/features/sales/screens/prospect_info_screen.dart#L119) | **Every user.** `assignReferralCode` is an `onDocumentCreated` trigger on user creation ([assignReferralCode.ts:34](functions/src/assignReferralCode.ts#L34)), so this is a complete UID directory. **This is the worst one and I missed it in the first pass.** |
| U-2 | `/neighborhoods/{groupId}/members/{memberUid}` | [firestore.rules:1775](firestore.rules#L1775) bare `request.auth != null` | **The document ID *is* the UID.** No field extraction needed | Every crew member |
| U-3 | `/neighborhoods/{groupId}` | [firestore.rules:1751](firestore.rules#L1751) | `memberUids[]`, `creatorUid` | Every crew member |
| U-4 | `/bridge_registry/{deviceId}` | [firestore.rules:677](firestore.rules#L677) | `pairedUid` | Users with a bridge only |
| U-5 | `/installations/{id}` | [firestore.rules:1152-1154](firestore.rules#L1152-L1154) | `primary_user_id` | Every installed customer |
| U-6 | `/sales_jobs/{id}/materialList`, `/materialLedger` | [firestore.rules:1553,1558](firestore.rules#L1553) `read: if request.auth != null` | Any `createdBy`/actor uid in ledger entries | Job actors — not verified field-by-field; flagged rather than asserted |
| U-7 | Crew subcollections after a self-join (I-18) | [firestore.rules:1806-1828](firestore.rules#L1806) | `SyncEvent.createdBy` ([neighborhood_models.dart:505](lib/features/neighborhood/neighborhood_models.dart#L505)) | Secondary; requires I-18 first |

**Not a source:** Firebase Storage. `match /users/{userId}/{allPaths=**}` grants read *below* a known uid; there is no rule matching the `users/` prefix itself, so the bucket cannot be enumerated to discover uids. Storage is a **consumer** of harvested uids (I-24), not a producer. Also not sources: `debug_errors` (owner-only), `invitations` (scoped), `campaigns` / `brand_library_corrections` (owner-or-admin), analytics rater/voter subcollections (`read: if false`).

**Q1c — verdict: the `status=='unpaired'` gate closes one instance out of six or seven, and the framing is wrong.**

Gating `bridge_registry` list removes U-4. U-1 alone replaces it completely and with better coverage — `/referral_codes` is a full-population UID directory, readable by any anonymous session, with no query constraint. Closing all of U-1…U-7 is neither achievable nor the right goal: **Firebase UIDs are identifiers, not secrets.** They appear in shared documents by design, and any system that treats "attacker doesn't know the UID" as the control will keep growing new leaks every time a collection gains an owner field.

**The real fix is at the resource, not the identifier.** The vulnerability is that [firestore.rules:383](firestore.rules#L383) (read), [:389](firestore.rules#L389) (create), [:392](firestore.rules#L392) (update) and [:395](firestore.rules#L395) (delete) collapse to `request.auth != null`, and [:355-360](firestore.rules#L355-L360) does the same for the user doc. Narrow those and the harvest becomes irrelevant. **My original F-1 remediation (a) was half-right — the Storage half is a genuine fix because it closes a resource; the `bridge_registry` half is enumeration-hiding and should be dropped from the plan.** Corrected estimate: see F-1 below.

**Q1d — the `request.auth != null` disjunct at :395 is load-bearing, but only on a failure path — which makes narrowing much cheaper than 16h.**

The wizard restores real staff claims before touching controllers. [`_restoreInstallerAuth`](lib/features/installer/installer_setup_wizard.dart#L737) calls `signInWithCustomToken` at [:741](lib/features/installer/installer_setup_wizard.dart#L741) and is invoked at [:840](lib/features/installer/installer_setup_wizard.dart#L840); the controller migration runs later at [:933](lib/features/installer/installer_setup_wizard.dart#L933) → [`migrateInstallerControllersToCustomer`](lib/features/installer/installer_setup_wizard.dart#L138-L200), which `batch.set`s into the customer path and `batch.delete`s from the installer path. **On the happy path the caller holds `role: 'installer'` + `dealerCode`,** so `hasStaffClaim(dealerCodeOf(userId))` would authorize the customer-side writes — the broad grant is not needed.

The dependency is the **fallback**: custom tokens live one hour ([:749-750](lib/features/installer/installer_setup_wizard.dart#L749) comment), and on expiry `_restoreInstallerAuth` drops to `signInAnonymously()` at [:756](lib/features/installer/installer_setup_wizard.dart#L756) with `_installerClaimsRestored = false`. A long install — pixel walk plus roofline capture is exactly that — exceeds an hour, and then a claim-scoped rule would fail the migration mid-install.

So: **not incidental, but the load-bearing case is token expiry, not the design.** The fix is to refresh the staff token instead of falling back to anonymous, then narrow the rule — substantially smaller than the "slice 4/5 wizard rework" the rules file anticipates.

One residual I could not settle from the file: `batch.delete(sourceCol.doc(...))` targets `users/{fromUid}/controllers`, and whether `isOwner(fromUid)` holds after the custom-token re-sign depends on whether the staff-token uid equals the uid the controllers were created under. Name it as a test case rather than assume it: if it does not hold, the source-side delete needs its own allowance.

**Revised estimate for closing F-1 properly: 6h** — 2h rule narrowing (`isOwner || hasStaffClaim(dealerCodeOf(userId))` on `/controllers` and the user doc), 2h token refresh in `_restoreInstallerAuth`, 2h install regression on real hardware. Down from 16h, and it closes the vulnerability rather than hiding the enumeration. **Confidence: Medium** — contingent on the `fromUid` ownership question above.

### (b) Route class: the class is smaller than it looked, and it has no entry vector

**Q2a — no.** Neither orphaned screen contains the stub pattern. `MediaLandingScreen` ([lib/features/installer/media_landing_screen.dart](lib/features/installer/media_landing_screen.dart)) returned **zero** hits for TODO / FIXME / not-implemented / mock / placeholder. `PayoutApprovalScreen` ([lib/features/referrals/screens/payout_approval_screen.dart](lib/features/referrals/screens/payout_approval_screen.dart)) has real backing logic — its snackbars sit in try/catch around actual writes and surface `Failed: $e` on error ([:223,250,264](lib/features/referrals/screens/payout_approval_screen.dart#L223)), which is the opposite of the false-success pattern. Window A's F-6 class appears to be specific to the abandoned commercial shell, not a repo-wide habit. *Scope limit: I checked these two screens because Q2a named them; this is not a fleet-wide stub sweep, and Window A's §5 leaves ~two-thirds of routes untraced.*

**Q2b — row 1.1 does not stay conditional; it goes to PASS, and for a stronger reason than the `/commercial` deletion.** Verified above in §2.5(a) fact 3: deep links are parsed by a closed allow-list ([deep_link_service.dart:59-90](lib/features/voice/deep_link_service.dart#L59-L90)) and Flutter's automatic deep-linking is disabled on both platforms. Combined with "no client navigates there", the stub screens are unreachable by any means available to a reviewer. Row revised.

**Q2c — cost comparison, and my recommendation is the class fix, but not urgently.**

| Option | Cost | Closes |
|---|---|---|
| Delete routes one at a time | ~1h each × 7 | One instance each; new routes re-inherit "allow" |
| **Class fix**: add `/commercial` + `/media` to the [route_guards.dart:54](lib/route_guards.dart#L54) restricted list, add a `/dealer` prefix check alongside `isInstallerRoute`/`isSalesRoute`, and make the generic branch deny-by-default for unknown prefixes | 4h | The class, permanently |

**Recommend the class fix** — it is cheaper than deleting four routes and it changes the default from allow to deny, which is the actual defect. But with no entry vector (Q2d), this is **P2 hygiene, not a launch gate**. Do it in the point release. Deleting `/commercial` remains worthwhile on Window A's own grounds (retires their 16h F-6), not on mine.

**Q2d — in-app URL construction only; not reachable via `lumina://` on either platform.** Three verified facts: (1) [deep_link_service.dart:59-90](lib/features/voice/deep_link_service.dart#L59-L90) switches on the first path segment against a fixed list and returns `null` otherwise — it never hands a path to GoRouter; (2) `flutter_deeplinking_enabled` is absent from the Android manifest and `FlutterDeepLinkingEnabled` is absent from Info.plist, so Flutter's automatic URI→route mechanism is off; (3) the `autoVerify="true"` on [AndroidManifest.xml:107](android/app/src/main/AndroidManifest.xml#L107) is **inert** — `autoVerify` applies only to `http`/`https` App Links, not to a custom `lumina` scheme, so it grants nothing here. Since nothing in `lib/` navigates to these routes either, they are unreachable at runtime.

### (c) Account-deletion arbitration — recorded as a split

Accepted. The merged item was two defects with different mechanisms, different tiers, and different fixes. Split below as **F-5a (P1)** and **F-5b (P0)**.

**Both documents should reflect the split.** I have applied it here. I have **not** edited `audit/FEATURE_STATUS_MATRIX.md` — the standing constraint for this task names `audit/COMPLIANCE_AND_SECURITY.md` as my only write, and it is another window's deliverable. Window A's F-1 row and their §6 Q2 need the corresponding edit; flagging rather than silently reaching into their file.

**And a correction that changes the remediation both windows proposed.** Window A's F-1 step 2 — reset the registry doc so "the hardware is reclaimable without a re-flash" — **does not work**, and I repeated it in §2.5(b). The firmware only polls for pairing changes **while unpaired**: `pollPairingRequest` returns early unless `currentStatus == "pairing"` ([main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220)), and the loop comment at [:241](esp32-bridge/src/main.cpp#L241) scopes the poll to the unpaired state. A paired bridge never observes an unpair. Its UID lives in NVS ([:1234](esp32-bridge/src/main.cpp#L1234) `prefs.putString("uid", pendingUid)`) and it re-asserts `pairedUid` from NVS on every heartbeat ([:1046](esp32-bridge/src/main.cpp#L1046)), so an Admin-SDK reset of the registry doc is **overwritten on the bridge's next beat**. `prefs.clear()` exists at [:507](esp32-bridge/src/main.cpp#L507) but is a local reset path, not remotely triggerable.

Consequence: **the truck roll is a firmware limitation, not a backend one.** The cleanup function is still required — it is what makes the F-5a data deletion real — but it does not reclaim hardware until the firmware gains an unpair poll.

**Operational implication of the hardcoded blocklist, and what to do about it.** [firestore.rules:669-672](firestore.rules#L669-L672) is currently the *only* thing stopping an orphaned bridge from writing, and because it is a literal array in the ruleset, **every future orphan costs a rules edit plus a production deploy**, with the orphan writing freely until that lands. That is an incident-response path with a deploy in the loop, and per the deploy-order checklist below, every rules deploy hits every app version in the field at once. Three consequences:

1. **It raises the cleanup function's priority** — not because it fixes the truck roll (it does not) but because each deletion under the current design mints a permanent rules-maintenance liability. Moved up in the checklist.
2. **The blocklist should be data-driven, not grown.** Replace the literal array with a lookup against an Admin-SDK-only collection — `!exists(/databases/$(database)/documents/blocked_bridges/$(deviceId))`. One extra document read per registry write, well inside the 10-lookup budget. This respects the standing constraint exactly: `/bridge_registry` keeps `allow delete: if false`, clients still cannot touch registry docs, and the new collection has no client write rule at all. ~2h.
3. **The real retirement is firmware.** Once a paired bridge polls for `status == 'unpaired'` and clears its own NVS, the cleanup function reclaims hardware, the blocklist becomes unnecessary, and the two stranded devices at [firestore.rules:669-672](firestore.rules#L669-L672) become recoverable. Estimate deferred — firmware is outside my charter — but it is the only thing that removes the truck roll.

---

## 3. Findings

### P0-BLOCK

> **All five P0s are fixable server-side or in text — none requires a new binary.** They gate *go-live*, not the *upload*. If you want to submit while these are open, submit; but do not ship the store listing live and do not flip `config/sync_fanout` until F-1/F-2/F-3 land.

---

**F-1 — Anonymous auth + `request.auth != null` grants = unauthenticated cross-tenant read, overwrite, and delete of customer data**
`firestore.rules:355-360, 344-349, 383-396, 1751, 1775, 1761-1766` · `storage.rules:5-7`

**P0 justification — concrete mechanism, all steps verified:**
1. `POST accounts:signUp` with the public API key from [firebase_options.dart:50](lib/firebase_options.dart#L50) → anonymous ID token. No account, no email. *(Anonymous provider confirmed enabled on the live project.)*
2. Unfiltered `list /bridge_registry` → `pairedUid` for every paired customer. *(Rule [:677](firestore.rules#L677) permits `list`; firmware writes the field, [main.cpp:1041-1047](esp32-bridge/src/main.cpp#L1041).)*
3. For each UID: `list`/`get` `/users/{uid}/controllers` → controller IDs, names, LAN IPs. *([:383](firestore.rules#L383))*
4. `delete` those controller docs → **the customer's system is unregistered from their account.** *([:396](firestore.rules#L396))*
5. `update /users/{uid}` with `schedules: []` → **their entire automation set is destroyed.** *([:355-360](firestore.rules#L355-L360); schedules confirmed on the user doc at [user_model.dart:648](lib/models/user_model.dart#L648).)*
6. Storage `list`/`download` `users/{uid}/` → **their house photo.** *([storage.rules:6](storage.rules#L6), verified deployed.)*

Hits three P0 limbs at once: data loss (4, 5), privacy breach (3, 6), and it is remotely reachable by anyone. Window A confirmed steps 4–5 and correctly declined to assign severity pending step 2; step 2 is now confirmed.

**Constraint that makes this non-trivial:** the broad grant is load-bearing. The installer wizard writes customer docs under `signInAnonymously()` and holds no claim at that moment — [firestore.rules:283-292](firestore.rules#L283-L292). The documented structural fix (re-mint the staff token instead of going anonymous) is already scoped in-repo as "slice 4/5". Deleting the disjunct without that will break every install.

**REVISED SEQUENCING (§2.6(a) supersedes my first proposal).** My original plan had two halves; one was right and one was wrong.

- **Right, keep:** Storage read → owner-only. That closes a *resource* (step 6) and breaks nothing. 1h.
- **Wrong, drop:** gating the `/bridge_registry` read. That is enumeration-hiding, and §2.6(a) enumerates **six other UID paths** — chief among them `/referral_codes`, whose documents are literally `{'uid': …}` and which covers the entire user population ([referral_program_screen.dart:76](lib/features/site/referral_program_screen.dart#L76), [firestore.rules:709](firestore.rules#L709)). Closing U-4 while U-1 stands buys nothing. **UIDs are identifiers, not secrets — do not build a control on their confidentiality.**
- **The actual fix:** narrow the resource rules. `/controllers` read/create/update/delete ([:383](firestore.rules#L383), [:389](firestore.rules#L389), [:392](firestore.rules#L392), [:395](firestore.rules#L395)) and the user doc ([:355-360](firestore.rules#L355-L360)) → `isOwner(userId) || hasStaffClaim(dealerCodeOf(userId))`. Per §2.6(a) Q1d the wizard already holds real staff claims at the migration call site, so this breaks nothing on the happy path; it needs a staff-token refresh to survive the 1-hour TTL on long installs.

**Estimate:** 1h Storage + 6h resource narrowing (2h rules, 2h token refresh in `_restoreInstallerAuth`, 2h hardware install regression) = **7h total**, down from my original 18h. **Confidence: High** on the vulnerability and on the Storage half; **Medium** on the 6h — contingent on the `fromUid` ownership question named in §2.6(a).

---

**F-2 — `createCustomerAccount` Cloud Function has no authentication check**
[functions/src/createCustomerAccount.ts:135-165](functions/src/createCustomerAccount.ts#L135-L165), [:317-338](functions/src/createCustomerAccount.ts#L317-L338)

The handler goes straight from `onCall(...)` to reading `request.data`. `request.auth` is never referenced. Gen-2 callables deploy public by default; the only gate is that `jobId` must name an existing `/sales_jobs` doc — and any authenticated (i.e. anonymous) caller can create one, since [firestore.rules:1546](firestore.rules#L1546) is `allow create: if request.auth != null`.

Three distinct abuses:
- **Branded email to arbitrary addresses.** [:238](functions/src/createCustomerAccount.ts#L238) generates a real password-reset link and [:266-278](functions/src/createCustomerAccount.ts#L266) sends a Nex-Gen-branded welcome email via Resend. Attacker-chosen recipient, attacker-chosen `displayName`. Phishing-grade, from your domain, at your sender reputation.
- **Unauthenticated account creation** at [:219-223](functions/src/createCustomerAccount.ts#L219).
- **Privilege manipulation of an *existing* customer.** Since the C2 change at [:194-214](functions/src/createCustomerAccount.ts#L194), an existing email no longer short-circuits — it falls through to the seed at [:321-338](functions/src/createCustomerAccount.ts#L321), which writes `dealer_code: <attacker-supplied>` and `installation_role: 'primary'` onto that customer's `/users` doc **with the Admin SDK, which bypasses security rules entirely.** This defeats the D0 `reassignsDealerCode()` guard at [firestore.rules:334-338](firestore.rules#L334-L338) — that guard only constrains client writes.

**P0 justification:** unauthenticated write path that reassigns a privilege field on another tenant's document, plus outbound branded email to arbitrary recipients.

**Fix:** add a staff/admin claim check at the top of the handler, matching the pattern `setAccountProfile` already uses ([setAccountProfile.ts:248-261](functions/src/setAccountProfile.ts#L248-L261)).
**Estimate:** 2h (1h change, 1h verifying the install wrap-up screen still holds a claim at that call site). **Confidence: High** on the gap; **Medium** on the estimate — if the wrap-up screen turns out to be in an anonymous session there, this inherits F-1's sequencing.

---

**F-3 — Neighborhood Sync: fleet-wide read of home coordinates, and uninvited crew join**
[firestore.rules:1751, 1775, 1761-1766, 1785](firestore.rules#L1751)

Two separate defects in one feature.

*Read.* `/neighborhoods/{groupId}` is `allow read: if request.auth != null` with no query constraint. Group docs carry `streetName`, `city`, `latitude`, `longitude` and `inviteCode` ([neighborhood_models.dart:128-140](lib/features/neighborhood/neighborhood_models.dart#L128-L140)). The members subcollection is *also* bare `request.auth != null` ([:1775](firestore.rules#L1775)) and carries `displayName` + `controllerIp` ([:301-318](lib/features/neighborhood/neighborhood_models.dart#L301-L318)). An anonymous token lists **every crew in the fleet with block-level coordinates and named residents**. The rule comment justifies the open read with "discover nearby public groups" — but it does not distinguish public from private groups, even though `isPublic` exists on the model ([:130](lib/features/neighborhood/neighborhood_models.dart#L130)).

*Write.* Group `update` grants anyone who inserts their own uid into `memberUids` ([:1765](firestore.rules#L1765)); member `create` is self-create ([:1785](firestore.rules#L1785)). **`inviteCode` is never verified server-side** — the rule says joining is "enforced app-side", which is not enforcement. Self-join then satisfies `isGroupMemberLookup()` and unlocks the crew's commands/schedules/syncEvents ([:1806-1828](firestore.rules#L1806)).

The SYNC-1 hardening in `fanoutToCrew` ([applySyncPattern.ts:409-460](functions/src/applySyncPattern.ts#L409)) is genuinely good work and closes the *creator-fabricates-a-victim* direction. It does not close this one, because a self-joined attacker is in `memberUids[]` legitimately. Light-control impact is currently held shut only by `config/sync_fanout.enabled = false`.

**P0 justification:** cross-tenant read of precise residence coordinates tied to names, by an unauthenticated party.
**Estimate:** 4h (scope group read to `isPublic == true` or membership; membership-scope the member roster; move invite-code validation into a callable). **Confidence: High.**

---

**F-4 — No liability / not-life-safety / not-UL-924 language anywhere in the product**
No file. `grep -rniE "UL 924|life.?safety|decorative only|supplemental|emergency lighting"` over `lib/`, `docs/`, `marketing/` returns zero.

The app has no Terms of Service and no EULA (§1 row 4.1), and the only in-app legal link is the privacy policy ([settings_page.dart:538-543](lib/features/site/settings_page.dart#L538-L543)). Nothing in the product states the system is decorative/supplemental, is not life-safety equipment, and is not UL 924 listed. The app markets to commercial properties (Fleet Dashboard, commercial scheduling, dealer-installed sites), which is precisely the context where a facility manager could treat scheduled exterior lighting as egress or security lighting.

**P0 justification:** the legal/liability limb of the taxonomy, and you pre-classified it as such. I agree with that call, and note it costs nothing to clear: it is a text change, deployable in the same pass as the privacy-policy edit in F-6.
**Estimate:** 2h (draft + place in an in-app Legal screen alongside the privacy link + add to store metadata). **Confidence: High** that it is absent; **Low** on wording adequacy — that is a question for counsel, not for me.

---

**F-5b — Account deletion strands the paired bridge irrecoverably — P0**
[firestore.rules:700](firestore.rules#L700), [esp32-bridge/src/main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220), [:1234](esp32-bridge/src/main.cpp#L1234), [:1046](esp32-bridge/src/main.cpp#L1046)

*Arbitration recorded — Window A's position stands on this half. See §2.6(c).*

Deleting an account releases nothing on the hardware side. The pairing lives in two places, neither touched by the deletion: the bridge's own NVS (`prefs.putString("uid", pendingUid)` at [main.cpp:1234](esp32-bridge/src/main.cpp#L1234)) and `/bridge_registry/{deviceId}`, which is `allow delete: if false` at [firestore.rules:700](firestore.rules#L700). The device keeps heartbeating into a dead UID, and the only in-field remedy is to physically locate it and re-flash.

**P0 justification:** a truck roll to recover a customer's installed hardware, triggered by a supported in-app action. Two production instances already, both memorialized as hardcoded blocked UIDs at [firestore.rules:669-672](firestore.rules#L669-L672) — the comment at [:649-663](firestore.rules#L649) records one bridge as "physically unlocatable at wipe time". This is not a projected risk; it is a realized cost, twice.

**Critical correction to the remediation both windows proposed.** Window A's step 2 — reset the registry doc so the hardware is "reclaimable without a re-flash" — **does not work, and I repeated the error in §2.5(b).** A paired bridge never polls for an unpair: `pollPairingRequest` returns early unless `currentStatus == "pairing"` ([main.cpp:1219-1220](esp32-bridge/src/main.cpp#L1219-L1220)), and the poll is scoped to the unpaired state ([:241](esp32-bridge/src/main.cpp#L241)). The bridge re-asserts `pairedUid` from NVS on every heartbeat ([:1046](esp32-bridge/src/main.cpp#L1046)), so an Admin-SDK reset is overwritten within one beat.

**So the fix is in two parts, and only the second removes the truck roll:**
1. *Backend, now:* Admin-SDK cleanup that resets the registry doc **and** adds the deviceId to a data-driven `blocked_bridges` collection (§2.6(c)), so the orphan stops writing without a rules deploy per incident. **4h.**
2. *Firmware, owner-decided:* a paired bridge polls for `status == 'unpaired'` and clears its own NVS. Only this makes the device self-reclaiming and retires the blocklist entirely. **Estimate deferred — firmware is outside my charter.**

**Standing constraint respected:** `/bridge_registry` keeps `allow delete: if false`; the cleanup runs under the Admin SDK and bypasses rules; no client write path is added.
**Confidence: High** on the mechanism and the firmware limitation; **Medium** on part 1's estimate.

---

**F-5a — Account deletion does not delete the account's data, and can leave a half-deleted state — P1**
[user_service.dart:277-284](lib/services/user_service.dart#L277-L284), [security_settings_screen.dart:100-124](lib/features/site/security_settings_screen.dart#L100-L124)

*Listed here for adjacency with F-5b; tier is P1. Arbitration in §2.6(c): my position stands on this half.*

`deleteUser()` is a single `.doc(userId).delete()`. Firestore does not cascade. Everything under `/users/{uid}/` survives indefinitely: `controllers`, `schedules`, `properties`, `geofences` (**home coordinates**), `commands`, `designs`, `patterns`, `pixelMap`, `brand_profile`, `commercial_*`, `debug_errors`. Storage `users/{uid}/house_photo.jpg` survives. Top-level `/installations` (with `address`, `city`, `zipCode`) survives. Orphaned rows in `/referrals`, `/sales_jobs`, `/referral_codes` (which is also UID path U-1) survive.

Two aggravators:
- **The published privacy policy commits to it.** The live page states data will be deleted or anonymized within 30 days of account deletion. No process implements that. A published commitment the system does not fulfil is a materially worse exposure than silence.
- **Ordering bug.** [security_settings_screen.dart:104-106](lib/features/site/security_settings_screen.dart#L104-L106) deletes the profile document *before* `user.delete()`. `user.delete()` throws `requires-recent-login` for any session older than ~5 minutes — handled at [:112-114](lib/features/site/security_settings_screen.dart#L112) with "Please sign in again", by which point **the profile is already gone and the auth account still exists**. The user is left signed in with no profile and no way to complete deletion. A reviewer testing this on a warm session will very likely hit exactly this.

**Why P1:** the in-app control exists and is reachable in 3 taps, which is what 5.1.1(v) tests and what a reviewer can observe; the residue is server-side and invisible to review. The ordering bug is user-visible but degrades to a confusing message, not a crash. This is a compliance/erasure exposure, not an approval blocker.
**Estimate:** 8h (recursive Admin-SDK delete over `/users/{uid}` + Storage prefix, plus reordering the client to re-auth before deleting anything). Shares a cleanup function with F-5b part 1, so building them together saves ~2h. **Confidence: High** on the gap, **Medium** on the estimate — the subcollection list must be enumerated exhaustively or the fix is cosmetic.

---

### P1-LAUNCH

**F-6 — Privacy policy omits two categories the app actually collects**
Live page vs. [user_model.dart:105-108,180](lib/models/user_model.dart#L105-L108), [image_upload_service.dart:59](lib/services/image_upload_service.dart#L59)

The policy discloses device IDs, IP/network-derived location, name, email, usage and crash data. The app also collects and transmits: **home address** (`address`) and **geocoded precise coordinates** (`latitude`/`longitude`) on the user doc; **photographs of the user's home** to Storage; and job-site photos/signatures in the sales flow. It also sends the typed address to third parties for geocoding.

This is simultaneously a store-declaration mismatch (both Apple nutrition labels and Play Data safety must match actual behavior), a legal exposure, and — because coordinates are involved — the highest-sensitivity category in both forms.

Complete outbound-flow inventory (from `grep -rhoE "https?://[a-zA-Z0-9.-]+" lib`):

| Destination | Data sent | Notes |
|---|---|---|
| Firebase (Auth / Firestore / Storage / Functions / FCM) | Everything above + FCM token | First-party |
| `places.googleapis.com` (43× `images.unsplash.com` aside) | Typed address fragments | Google Places Autocomplete |
| `photon.komoot.io` | Address fragments | Geocoding fallback |
| `nominatim.openstreetmap.org` | Address fragments | OSM. Their usage policy prohibits autocomplete-style querying and requires an identifying User-Agent — F-16 |
| `api.open-meteo.com` | **Latitude/longitude** | Weather |
| `site.api.espn.com` | Team selections | Unofficial endpoint |
| `images.unsplash.com` | IP + request metadata (43 references) | Image CDN |

**Estimate:** 2h to correct the policy page + align both store forms. **Confidence: High.**

---

**F-7 — App Check is not enabled, at all**
Verified live: `firebaseappcheck.googleapis.com` returns `SERVICE_DISABLED` for the project — the API has **never been enabled**, so enforcement cannot exist. No `firebase_app_check` dependency in [pubspec.yaml](pubspec.yaml); zero references to App Check in `lib/` or `functions/`.

Every Firestore path, Storage object and callable is reachable by `curl` with the public API key, not only by the app. This is the enabler that turns each finding above from "a malicious app user" into "a script". It also removes the only practical defense against distributed brute force of `mintStaffToken` (F-12): the per-IP limiter at [staffAuth.ts:461-472](functions/src/staffAuth.ts#L461) buckets by IP, so a 4-digit PIN across ~100 source IPs is well within reach.

**Estimate:** 8h (enable, add the plugin, register DeviceCheck/App Attest + Play Integrity, ship in monitor-only mode first, then enforce). **Confidence: High** on the absence; **Medium** on the estimate — monitor-mode soak time is the unknown, and enforcing before the soak will lock out real users.

---

**F-8 — No public web URL for account-deletion requests (Play requirement)**
The Play Console Data safety form requires a publicly reachable URL where a user can request account and data deletion *without installing the app*. The privacy policy directs users to email `General@Nex-GenLED.com`; the site footer has `/contact` but no deletion page. An email address is not a URL.
**Estimate:** 1h (a `/delete-account` page describing the in-app path and a request form/mailto). **Confidence: Medium** — Play has accepted policy-page sections containing deletion instructions in some cases; confirm the exact field requirement in the console.

---

**F-9 — No app-level `PrivacyInfo.xcprivacy`**
Absent from the repo entirely. Most plugins ship their own (checked in pub cache: `shared_preferences_foundation`, `flutter_secure_storage`, `geolocator_apple`, `image_picker_ios`, `url_launcher_ios`, `connectivity_plus`, `network_info_plus`, `permission_handler_apple` — all present). `path_provider_foundation-2.6.0`, `flutter_blue_plus-2.2.1` and `speech_to_text-7.3.0` do not. There is no app-target manifest to declare required-reason API use by your own Swift ([AppDelegate.swift](ios/Runner/AppDelegate.swift), [SiriShortcutsPlugin.swift](ios/Runner/SiriShortcutsPlugin.swift)) or by those plugins, and no `NSPrivacyTracking`/`NSPrivacyCollectedDataTypes` declaration.

Typical failure mode is the automated **ITMS-91053 "Missing API declaration"** email after upload, which has escalated to a hard rejection. Cheap insurance: add a manifest declaring `NSPrivacyTracking=false`, the collected data types (matching F-6's corrected list), and the file-timestamp / user-defaults / disk-space / boot-time reason codes as applicable.
**Estimate:** 2h. **Confidence: Medium** — whether it blocks depends on which required-reason APIs the unmanifested pods actually call, which I cannot determine without a resolved Pods tree.

---

**F-10 — Two iOS purpose strings describe capabilities the app does not have**
[Info.plist:86-89](ios/Runner/Info.plist#L86-L89)

- `NSCameraUsageDescription`: *"Camera access is required for AR spatial mapping of your lights."* There is **no ARKit or ARCore anywhere** (`grep -rniE "ARKit|arcore|arSession"` → 0). Camera is plain `image_picker` capture — [demo_photo_screen.dart:39](lib/features/demo/demo_photo_screen.dart#L39), [controller_setup_screen.dart:1596](lib/features/installer/screens/controller_setup_screen.dart#L1596), and four sales screens. It takes photos.
- `NSMicrophoneUsageDescription`: *"...voice-to-text control and audio-reactive lighting."* Voice-to-text is real (`speech_to_text`). Audio-reactive lighting is not implemented in the app — CLAUDE.md itself describes the interface as in-progress with the mic on the WLED hardware, not the phone.

Purpose strings that claim more than the app does are a 5.1.1 finding, and the camera one specifically invites "where is the AR feature?" from a reviewer. Rewrite both to what the code does.
**Estimate:** 0.5h. **Confidence: High.**

---

**F-11 — Sports team names and league marks are hardcoded and displayed**
[team_color_database.dart:302-308](lib/data/team_color_database.dart#L302-L308) and following

155+ registered team marks in full ("Buffalo Bills", "Miami Dolphins", "New England Patriots"...) plus league names (NFL, NBA, MLB, NHL, MLS, WNBA, NCAA), surfaced in a user-facing Game Day feature and in the reviewer seed ([reviewer_seed_service.dart:53-54](lib/services/reviewer_seed_service.dart#L53-L54)).

Mitigating: colors are unprotectable as such, no logos or wordmark artwork ship, and there is no claim of affiliation that I found. Aggravating: full team names used as feature labels, and league names as organizing categories, go beyond nominative color reference. This is a business/legal call, not a code question — the cheapest launch answer, if counsel is uneasy, is to render city + color name ("Kansas City Red/Gold") instead of the mark.

The Brandfetch concern in the brief does not apply as posed: **no third-party logos are displayed** and the app never calls Brandfetch. The exposure there is narrower — brand *names* + derived color palettes in a corporate catalog, sourced offline by [scripts/seed_brand_library.js](scripts/seed_brand_library.js). Whether Brandfetch's terms permit redistributing derived palettes into a product catalog is still worth a read of their ToS, but it is a script-side and business-side question, not shipped-app behavior.

**Estimate:** 0.5h to gate the feature; 40h+ if a full mark-free redesign is wanted. **Confidence: Low on severity** — this is a legal judgment. Escalated in §5.

---

**F-12 — Installer PINs stored in cleartext; `mintStaffToken` is unauthenticated with per-IP limiting only**
[firestore.rules:1058-1120](firestore.rules#L1058-L1120) (documents the cleartext `fullPin` at rest), [staffAuth.ts:424-472](functions/src/staffAuth.ts#L424-L472)

The read leak is closed (I-14: admin/owner only). The residue is that the credential is a 4–6 digit number stored in plaintext, the master installer PIN is fleet-shared and never rotated, and the minting endpoint is unauthenticated by design with an IP-bucketed limiter and no App Check (F-7). The rules file already names PIN hashing as the correct follow-up.
**Estimate:** 8h (hash at rest + migration + then relax the `/installers` read to `hasStaffClaim(dealerCode)`, which also un-breaks the dealer Team tab). **Confidence: Medium.**

---

**F-13 — `targetSdk 35` against an approaching Play deadline**
`android/app/build.gradle`

Play's annual target-API requirement moves each August. `targetSdk = 35` satisfies the current requirement; the next step (API 36) has a deadline that likely falls around **2026-08-31 — roughly one month from today**. If submission slips past it, updates get blocked at upload.
**Estimate:** 4h to move to 36 and regression-test permissions/FGS behavior. **Confidence: Low on the date** — this is the single most likely thing in this report to be stale. Confirm the exact deadline and required level in the Play Console before deciding whether to move now or after launch.

---

### P2-FOLLOW

- **F-14 — Export compliance answer may be wrong.** `ITSAppUsesNonExemptEncryption = false` ([Info.plist:58-59](ios/Runner/Info.plist#L58)) while the app ships `encrypt: ^5.0.3` and an `EncryptionService` that encrypts user data at rest ([user_service.dart:293](lib/services/user_service.dart#L293)). HTTPS alone is exempt; proprietary AES over user data may still fall under an exemption but the self-classification should be made deliberately rather than by default. *1h · Low confidence — export-control question, not an engineering one.*
- **F-15 — `usesCleartextTraffic="true"` is global.** [AndroidManifest.xml:84](android/app/src/main/AndroidManifest.xml#L84). Required for LAN HTTP to WLED, but should be a `networkSecurityConfig` scoped to private address ranges so plaintext is not permitted to arbitrary hosts. *2h · High.*
- **F-16 — Nominatim usage policy.** `nominatim.openstreetmap.org` is called for geocoding; OSM's policy forbids autocomplete-style querying and requires an identifying User-Agent. Verify call frequency and headers. *1h · Medium.*
- **F-17 — Hardcoded blocked UIDs are an incident-response path with a deploy in the loop — RE-SCOPED TWICE.** [firestore.rules:669-672](firestore.rules#L669-L672), marked TEMPORARY on 2026-05-27 and still present. I first filed this as housekeeping; Window A correctly read it as evidence of two orphaned production bridges (now F-5b). The third reading is the operational one: because the blocklist is a **literal array in the ruleset**, every future orphan costs a rules edit plus a production deploy — which, per the deploy-order checklist, goes live against every app version in the field simultaneously — and the orphan writes freely until it lands. **Do not grow this list.** Replace it with `!exists(/databases/$(database)/documents/blocked_bridges/$(deviceId))` against an Admin-SDK-only collection, landed together with F-5b part 1. Keeps `/bridge_registry` at `allow delete: if false` and adds no client write path. The two existing entries stay until F-5b part 2 (firmware unpair) makes the devices reclaimable — **they do not retire with the cleanup function alone**, contrary to what I wrote in §2.5(b). *2h, bundled with F-5b · High.*
- **F-18 — `/demo_leads` `allow update: if true`.** [firestore.rules:1349](firestore.rules#L1349). Anyone who learns a lead ID can overwrite that prospect's record. `list` is correctly admin-gated and `get` is capability-URL reasoning, which holds. *1h · High.*
- **F-19 — Analytics counters are blind-writable.** [firestore.rules:884,903,929,940](firestore.rules#L884). Read is `false`, so this is vandalism of aggregates, not a breach. *2h · High.*
- **F-20 — Storage has no rule for `sales_jobs/**`** (I-25). Fails closed, so signatures and job photos are not being stored. Correct security direction, broken feature — hand to Window A. *1h · High.*
- **F-21 — One shared Firebase credential for the entire bridge fleet.** [firestore.rules:641-646](firestore.rules#L641-L646). Extracting one bridge's firmware yields the fleet credential. Already acknowledged in-comment as future work. *16h · Medium.*
- **F-22 — Unpaired-bridge claim is first-writer-wins** (I-22). No proof of possession binds a device to an account during the pairing window. *4h · Medium.*
- **F-23 — Login screen version string is hardcoded `'v2.2.0'`** vs `2.5.10+58`. [login_page.dart:541](lib/features/auth/login_page.dart#L541). Cosmetic, but it is on the first screen a reviewer sees and contradicts the submitted version. *0.5h · High.*
- **F-25 — Route layer grants by default; role separation rests entirely on Firestore rules.** The demo-browsing restricted list ([route_guards.dart:54](lib/route_guards.dart#L54)) omits `/commercial` and `/media`; there is no per-route gate for `/dealer/*` or `/media`, so the generic branch returns `null` (allow) for any `primary` customer ([:294-296](lib/route_guards.dart#L294)). **No live exposure:** §2.6(b) establishes there is no external entry vector (closed-allow-list deep-link parser, Flutter auto-deep-linking off on both platforms) and nothing in `lib/` navigates to these routes; and even if reached, I-11/I-13/I-14 deny the underlying reads, so a customer gets a permission error, not data. The defect is architectural — new routes inherit "allow" and the only backstop is the rules layer. Fix the class, not the instances: add `/commercial` + `/media` to the restricted list, add a `/dealer` prefix check beside `isInstallerRoute`/`isSalesRoute`, make unknown prefixes deny-by-default. Cheaper than deleting four routes individually. *4h · High. Point release, not a launch gate.*
- **F-26 — `/referral_codes` is a complete UID directory readable by any session.** [firestore.rules:709](firestore.rules#L709) is `allow read: if request.auth != null` with no query constraint, and the documents are literally `{'uid': <user uid>}` ([referral_program_screen.dart:76](lib/features/site/referral_program_screen.dart#L76)). `assignReferralCode` fires on user creation ([assignReferralCode.ts:34](functions/src/assignReferralCode.ts#L34)), so coverage is the whole population — this is path U-1 in §2.6(a) and the strongest of the seven. **Filed P2 deliberately and consistently with my own verdict: UIDs are identifiers, not secrets, and the fix for the harvest chain is the resource rules in F-1, not this.** Worth closing anyway as defense-in-depth and because the code→uid mapping enables referral-attribution fraud. Narrow to a `get`-only allowance (the signup flow looks up one known code; it never lists). *1h · High.*

### P3-DEBT

- Reviewer-reveal button only autofills the email, not the password — the gesture adds little over typing it from the review notes.
- `flutter_background_service` remains a dependency though the service is stripped from the manifest; dead weight in the binary.
- `cannotModifyCriticalFields()` ([firestore.rules:103-107](firestore.rules#L103-L107)) reads `resource.data.email` unguarded; would error on a doc lacking `email` (currently unreachable, since the branch is short-circuited by the broad grant).
- `functions/src/claudeProxy.js` ships a `sk-ant-YOUR_KEY_HERE` placeholder and is exported from [index.js:7](functions/index.js#L7) — confirm it is intentionally inert.
- Consider consolidating the four "hidden gesture" entry points into one documented staff-access path.

---

## 4. Verify in console — I could not confirm these from the repo

**Treat every version/date threshold in this report as needing confirmation. They move.**

| # | What to check | Where | Why it matters |
|---|---|---|---|
| V-1 | **Does `reviewer@Nex-GenLED.com` exist in Firebase Auth, with a password that matches what is in the review notes?** Sign in as it on a clean device with no controller on the network and walk the full flow. | Firebase Console → Authentication | If this account does not exist or the password is stale, it is an automatic 2.1 rejection. Everything else about the reviewer path is correct in code; this is the one link I cannot see. |
| V-2 | Current App Review notes text — does it name the reviewer credentials, and does it disclose the hidden 5-tap staff gesture? | App Store Connect → App Information | Undisclosed staff functionality is a 2.3.1 exposure (F-24 below). Disclosure is free; omission is not. |
| V-3 | Exact current Play target-API requirement and its deadline date | Play Console → Dashboard → policy status | F-13. Most likely stale item in this report. |
| V-4 | 16 KB **archive** alignment of the actual upload artifact — `zipalign -c -P 16 -v 4 <apk>`, or upload to an internal testing track and read the pre-launch report | Play Console | ELF alignment verified PASS; AGP 8.3.2 predates automatic zip-level 16 KB alignment. |
| V-5 | Nutrition labels and Data safety form vs. F-6's corrected inventory | ASC + Play Console | Must include home address, precise location, photos, and the third-party geocoding/weather destinations. |
| V-6 | Play Data safety account-deletion URL field — is a policy-page section accepted, or is a dedicated URL required? | Play Console → Data safety | F-8. |
| V-7 | Age rating questionnaire answers vs. actual content | ASC + Play | Not derivable from code. |
| V-8 | API key restrictions on the three Google API keys in [firebase_options.dart:50,59,67](lib/firebase_options.dart#L50) — bundle-ID/package restriction and per-API allowlists (Places is billable and abusable) | Google Cloud Console → Credentials | These are client keys and not secrets, but an unrestricted Places-enabled key is a billing-abuse vector. |
| V-9 | Firebase Auth email-enumeration protection setting | Firebase Console → Authentication → Settings | Not returned in the config read I performed. |
| V-10 | Whether Cloud Functions are IAM-restricted or public invokers | GCP Console → Cloud Run/Functions → Permissions | Determines whether F-2 is reachable from off-app. Assume public until confirmed otherwise — that is the default. |
| V-11 | Firestore/Storage **backup or PITR** configuration | Firebase Console | F-1's delete path destroys data with no recovery unless PITR is on. Changes F-1's blast radius materially. |
| V-12 | Brandfetch API terms of service, current text | brandfetch.com/terms | Whether derived color palettes may be redistributed in a product catalog (F-11). |
| V-13 | Support URL and marketing URL are live and current | ASC | Site has `/contact`; confirm what is actually filed. |

**One thing to rotate, unrelated to the app:** my read of the Identity Platform config returned the project's SCRYPT `signerKey`. I have not reproduced it anywhere in this report. It is a project-level secret that any principal with project access can read; no action is required, but be aware that a compromised admin account exposes it.

**F-24 — Hidden staff suite (raised here rather than as a separate finding).** [login_page.dart:74-102](lib/features/auth/login_page.dart#L74-L102) implements two invisible 5-tap gestures: on the logo → the full staff PIN screen (Installer / Sales / Dealer / Corporate), and on the version line → the reviewer button. Guideline 2.3.1 prohibits hidden, dormant or undocumented features. Reviewers routinely accept gated enterprise modes **when disclosed in the review notes**; undisclosed, a reviewer who discovers it has grounds to reject, and one who does not discover it may later treat it as concealed functionality. **P1, fixed by writing two sentences in V-2.** *0.5h · Medium.*

---

## 5. Open questions for Tyler

1. **Sequencing F-1.** The broad `request.auth != null` grant on `/users` and `/controllers` is deliberate and load-bearing for the installer wizard's anonymous session, and the repo already scopes the real fix as "slice 4/5". Do you want (a) the two-hour partial that collapses the attack chain at the harvest and Storage steps and leaves the write grants in place, or (b) the full re-mint before launch? I recommend (a) now and (b) as the first post-launch item — (b) touches the install flow, which is the last thing you want destabilized in launch week.

2. **`config/sync_fanout`.** It is `false` and console-only. Given I-18/I-20, **please do not flip it until F-3 lands.** Is there a plan to activate it near launch that I should flag against?

3. **Sports team marks (F-11).** Colors are safe; 155 full team names and league names in a shipped feature are a judgment call I am not qualified to make. Has counsel looked at Game Day? If not, is gating the feature for launch acceptable, or is it a headline feature you need?

4. **Brandfetch (F-11).** The app never calls it and displays no logos — the exposure is that `scripts/seed_brand_library.js` derives color palettes from their API into your catalog. Is there a paid Brandfetch tier or license already in place that covers this?

5. **Anonymous auth.** Is it required anywhere other than the installer wizard? If the wizard is the only consumer, disabling the provider after the re-mint fix would remove the multiplier under a large fraction of this report in one setting.

6. **Deletion promise (F-5).** The published policy commits to deletion within 30 days. Is there a manual backend process today that I'm not seeing, or is that commitment currently unbacked? The answer changes whether F-5 is an engineering gap or a live compliance gap.

7. **`sales_jobs/**` Storage (I-25/F-20).** Customer signature uploads are hitting a default-deny path, so signed contracts are not being stored. That is Window A's territory functionally, but I need to know whether to write a Storage rule for it — and if so, who should be allowed to read signed contracts.

8. **Terms of Service.** Is there a ToS/EULA document that exists outside this repo and simply is not linked, or does it need to be written? Answer changes F-4's estimate from 2h to a legal engagement.

9. **Two arbitrations are Window A's, not mine — but they change my rows, so flagging them here too.** (a) Their Q2, the account-deletion tier: I hold P1, they hold P0, reconciled in §2.5(b); either way it is the first non-rules fix. (b) Their Q3, Phase 6 commercial retirement: **deleting the `/commercial` route is the cheapest fix in either document** — ~1h, it retires their 16h F-6 remediation and turns my 1.1 row from CONDITIONAL PASS to clean PASS. If Phase 6 is still the plan, do it before submission.

---

### Bottom line

**Nothing in this report prevents you from uploading a build.** The submission-side surface is in better shape than expected: the reviewer path is real and hardware-independent, foreground services and the AD_ID permission are properly stripped, 16 KB ELF alignment passes, no social login means no Sign in with Apple obligation, no IAP surface, and — verified live — **there is no Firestore rules deployment drift**, which was the thing this codebase has been bitten by before.

What blocks *go-live* is data isolation. Anonymous authentication is enabled in production, and enough rules are written as `request.auth != null` that an unauthenticated party can harvest customer UIDs — from **at least seven** paths, not one (§2.6(a)) — then read their controllers, delete them, wipe their schedules, and download photographs of their homes. One Cloud Function accepts unauthenticated calls that create accounts and rewrite an existing customer's dealer assignment. Neighborhood Sync exposes block-level coordinates fleet-wide.

**The correction that matters most for planning:** my first pass proposed gating the `/bridge_registry` read as half of the cheap mitigation. That was wrong, and §2.6(a) retracts it. `/referral_codes` alone is a complete UID directory for every user in the system, so hiding one path buys nothing. **UIDs are identifiers, not secrets.** The fix is to narrow the resource rules on `/controllers` and the user doc — 6h with a staff-token refresh, not the 16h wizard rework the ruleset anticipates, because the wizard already holds real staff claims at the call site and only loses them to a one-hour token TTL.

Revised: **D1–D3 in the checklist below are ~7 hours and close everything externally reachable.** D4 is the deep fix and is gated on app adoption, not on effort. Then the liability text, then the deletion split.

Second correction: account deletion is **two** defects, not one — the erasure gap (P1, mine) and the bridge orphaning (P0, Window A's). And the bridge half does **not** have the fix either window proposed: a paired bridge never polls for an unpair, so resetting the registry doc is overwritten on the next heartbeat. That truck roll is a firmware limitation.

---

## 6. DEPLOY-ORDER CHECKLIST

**The premise that makes ordering matter.** `firebase deploy --only firestore:rules` is **atomic, immediate, and global**. There is no staged rollout, no percentage, no per-version targeting. The moment it lands it governs *every app version in the field simultaneously* — every installed customer build, every dealer's phone mid-install, and **whatever binary the App Review reviewer is running**. A rules deploy is not like shipping an app update; it cannot be held back for old clients and it cannot be rolled forward gradually. Per §1 row 3.1, deployed rules currently match HEAD exactly, so the repo is the correct baseline to diff against — and the last deploy was 2026-07-25.

**Consequence for submission:** if you tighten rules while a build is in review, the reviewer's session is subject to the new rules. Tighten *before* submitting and verify, or tighten *after* approval — never during.

### Pre-flight (before any deploy)

| ☐ | Step | Why |
|---|---|---|
| ☐ | Capture the current deployed ruleset as a rollback artifact: `GET firebaserules.googleapis.com/v1/projects/{p}/rulesets/{id}` (the method used in §1 row 3.1) | There is no "undo deploy". Rollback = re-deploying the old text. Have it on disk first. |
| ☐ | Confirm `firestore.rules` at HEAD still diffs clean against deployed | If drift appeared since 2026-07-25, resolve it before layering changes on top |
| ☐ | Confirm `config/sync_fanout.enabled == false` in the console | I-20: fanout must stay shut until F-3 lands |
| ☐ | Have a real bridge in a **known-unpaired** state on the bench, plus one **paired** | Steps V-2/V-3 below need both |

### Deploy order

Each group is one deploy. **Verify before proceeding to the next.** Rules and Functions deploy separately; where a change spans both, deploy the *permissive* side first so no window exists where the client is denied by rules that the function has not yet compensated for.

| # | Change | Surface | Deploy with |
|---|---|---|---|
| **D1** | F-2 — auth check on `createCustomerAccount` | Functions only | `--only functions:createCustomerAccount` |
| **D2** | F-1 Storage half — `users/{userId}` read → owner-only | Storage rules only | `--only storage` |
| **D3** | F-3 — neighborhood group + member read scoping; invite-code check moved server-side | Firestore rules **+** a new callable | Deploy the **callable first**, then the rules. Reversing this leaves joins broken between the two deploys. |
| **D4** | F-1 resource half — `/controllers` + user-doc rules → `isOwner \|\| hasStaffClaim`, **paired with** the `_restoreInstallerAuth` token refresh | Firestore rules **+ an app build** | ⚠️ **The app change must ship and be adopted BEFORE the rules tighten.** See "the D4 trap" below. |
| **D5** | F-5b part 1 + F-17 — cleanup function, `blocked_bridges` collection, rule swapped from the literal array to an `exists()` lookup | Functions **+** Firestore rules | Function and collection first; rule swap second |
| **D6** | F-26 — `/referral_codes` read narrowed to `get` | Firestore rules | Low risk, can ride with D5 |

**The D4 trap — the one that can break the fleet.** D4 narrows `/controllers` to `isOwner || hasStaffClaim`. Installers running an *older build* have no token-refresh logic, so on any install lasting over an hour their session has already fallen back to anonymous ([installer_setup_wizard.dart:756](lib/features/installer/installer_setup_wizard.dart#L756)) and holds no claim. The tightened rule denies their controller migration **mid-install, in a customer's driveway**, with no client-side error path built for it. Rules cannot distinguish app versions. So: ship the app build with the token refresh, confirm dealer adoption, *then* deploy D4. If that sequencing is not acceptable before launch, **defer D4 entirely** — D1–D3 already collapse the externally-reachable chain, and D4 is the deep fix rather than the urgent one.

### Mandatory re-verification BEFORE submission

Run all four against the **tightened** rules. Each names what breaks if skipped.

| ☐ | Flow | How | If skipped |
|---|---|---|---|
| ☐ | **V-1 Reviewer demo path** | Sign in as `reviewer@Nex-GenLED.com` on a device with **no controller on the network**. Confirm: seed writes succeed, dashboard loads, `DemoWledRepository` is selected ([wled_providers.dart:152-155](lib/features/wled/wled_providers.dart#L152-L155)), power/brightness/scenes respond, Settings → Security → Delete Account renders. | The reviewer account writes `/users/{uid}` and `/installations/{id}` on first sign-in ([reviewer_seed_service.dart:86-121](lib/services/reviewer_seed_service.dart#L86-L121)). A tightened user-doc rule that does not account for a self-owned create leaves the reviewer at `/link-account` with no installation — **a guaranteed 2.1 rejection, caused by a backend change the build cannot see.** This is the single highest-value check on the page. |
| ☐ | **V-2 Bridge self-registration** | Factory-fresh/unpaired bridge, power on, confirm it creates `/bridge_registry/{deviceId}` and heartbeats. | `create` requires the shared bridge account email ([firestore.rules:682](firestore.rules#L682)) and now also passes the `blocked_bridges` lookup after D5. A malformed `exists()` path denies **every bridge in the fleet** on its next heartbeat — silent, and it looks like a firmware fault. |
| ☐ | **V-3 Bridge pairing handshake** | From the app, pair the unpaired bridge: app writes `pendingUid`, bridge polls ([main.cpp:1214-1253](esp32-bridge/src/main.cpp#L1214-L1253)), promotes to `paired`, confirms. | The pairing update rule is a compound of `isBridge()`, `status == 'unpaired'`, `pendingUid == request.auth.uid` and the blocklist ([firestore.rules:691-695](firestore.rules#L691-L695)). D5 edits that expression. Break it and **no new bridge can ever be paired** — the failure appears only at the customer's house, during a paid install. |
| ☐ | **V-4 Installer wizard, end to end** | Full run on real hardware: staff PIN → customer account creation → `_restoreInstallerAuth` → add controllers → **controller migration** → pixel-map capture → wrap-up. Run one deliberately **over 60 minutes** to exercise the token-TTL path. | This is the flow D1 and D4 both touch and the one the broad grants exist for. The >60-minute run is the point: it is the only way to catch the D4 trap before a dealer does. Skipping it risks installs failing in the field with no rollback except re-deploying old rules. |

**Additional gate:** if D3 shipped, confirm `config/sync_fanout` is still `false` before submitting. Nothing in the deploy sequence should flip it, but verify rather than assume.

### Order of the non-deploy work (app build + text)

These carry no rules risk and can proceed in parallel with the above.

| # | Item | Est |
|---|---|---|
| 1 | F-4 — liability / not-life-safety text + a Legal screen | 2h |
| 2 | F-10, F-23 — purpose strings, login version string | 1h |
| 3 | F-6 — privacy policy correction, then both store forms | 2h |
| 4 | Window A F-6 — delete `/commercial` (if Phase 6 stands) | 1h |
| 5 | F-5a — deletion cascade, sharing D5's cleanup function | 8h (−2h if built with D5) |
| 6 | F-9 — app-level `PrivacyInfo.xcprivacy` | 2h |

**Two things not to do:** do not flip `config/sync_fanout` before D3, and do not remove the blocked-UID entries at [firestore.rules:669-672](firestore.rules#L669-L672) until F-5b **part 2** (firmware unpair) ships — the cleanup function alone does not make those two devices safe to unblock (§2.6(c)).
