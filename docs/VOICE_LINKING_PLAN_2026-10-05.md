# Voice linking: plan to make Alexa account linking and voice commands work end to end

Written 2026-10-05. Scope: Alexa first. Google Home is noted where the same code serves it.
Nothing in this plan has been deployed or written to production.

## 0. Summary

Alexa account linking has never worked for any account. Four problems block it, one behind
another:

| # | Wall | Where | Fix | Status |
|---|------|-------|-----|--------|
| 0 | XSS + open redirect on the login page | `alexaAuth`, `googleAuth` | exact redirect allowlist, JSON-escaped values, CSP | **built**: `fix/voice-auth-xss` `988c2d6` |
| 1 | `firebase.functions is not a function` after sign-in | both pages load no `firebase-functions-compat.js` | load it (10.7.1) | **built**: `fix/voice-link-page` `0b138bf` (stacked on 0) |
| 2 | `alexaToken` → 401 | reads `client_id`/`client_secret` from the body only; Amazon recommends HTTP Basic | accept Basic **and** body (§2) | to build (B-3c) |
| 3 | every directive fails | `alexaToken` returns a Firebase **custom** token; the Lambda calls `verifyIdToken`, which rejects custom tokens | B-3b's self-issued JWT, verified by `alexaSmartHome`; Lambda becomes a shim (§3) | B-3b built, hardening to build (B-3c) |

Wall 0 ships alone, first. Walls 1–3 ship together, as one deploy. Wall 1 deployed alone only
moves the failure to wall 2.

## 1. Branches

| Branch | Head | Base | Contents |
|---|---|---|---|
| `fix/voice-auth-xss` | `988c2d6` | `9be91a1` (release head) | security fix only |
| `fix/voice-link-page` | `0b138bf` + this doc | `fix/voice-auth-xss` | one script tag per page, its tests, this plan |
| `feat/voice-canonical-commands` (B-2..B-4) | `5489808` | `ca6cc13` — **755 commits behind release** | intentCore, Google rewire, Alexa Smart Home, JWT |
| `feat/voice-link-e2e` (B-3c, **to create**) | — | `fix/voice-link-page` + merge of B-3b | §6 |

**B-3b lands cleanly on the release base (verified 2026-10-05, scratch merge, nothing kept).**
Merging `5489808` onto `0b138bf` conflicts in three places, all mechanical:

- the `functions/index.js` require block: keep B-3b's requires, drop its `OPENAI_API_KEY` param,
  which release removed;
- `.gitignore`: keep both blocks;
- `functions/package.json`: keep release's jest scripts and add B-3b's runner as `test:voice`.

After that, `tsc` is clean, the unit suite is 820/820, and B-3b's own `node:test` voice tests are 36/36.
Narrow `test:voice` to `lib-test/test/voice/**/*.test.js`. As written, the glob would also run the
compiled emulator tests.

> **Never deploy from `feat/voice-canonical-commands` or the `C:\Flutter Projects\lumina-voice`
> worktree.** Its tree predates the relay fail-fast (`8b3bcdf`, deployed 2026-09-30). A
> `firebase deploy --only functions` there reverts `executeWledCommand`. Deploy only from a
> release-based branch, and only with `--only functions:<named list>`.

## 2. Amazon's token flow, exactly

Alexa uses the OAuth 2.0 **authorization code grant**:

1. The user enables the skill in the Alexa app. The app opens the **Authorization URI**
   (`alexaAuth`) with `client_id`, `response_type=code`, `state`, `scope` (if configured) and
   `redirect_uri`. The redirect URI is one of the three regional URLs
   `{https://pitangui.amazon.com | https://layla.amazon.com | https://alexa.amazon.co.jp}/api/skill/link/{vendorId}`.
2. Our page signs the user in (Firebase Auth compat, email and password). It calls
   `generateAlexaAuthCode({idToken, state})`, which stores `oauth_codes/{code}` (5 min, single use).
   The page then redirects to `redirect_uri?state=…&code=…`.
3. Amazon's servers POST `application/x-www-form-urlencoded` to the **Access Token URI**
   (`alexaToken`): `grant_type=authorization_code`, `code`, `redirect_uri`, plus client
   credentials in one of two forms. `HTTP_BASIC` sends
   `Authorization: Basic base64(urlenc(client_id) ":" urlenc(client_secret))` (RFC 6749 §2.3.1).
   `REQUEST_BODY_CREDENTIALS` sends `client_id` and `client_secret` as body fields.
4. We answer `{access_token, token_type: "Bearer", expires_in, refresh_token}`.
5. Amazon calls the skill endpoint, an **AWS Lambda ARN**, with each directive. It carries the
   access token in `directive.payload.scope.token` (Discovery) or `directive.endpoint.scope.token`
   (control and ReportState).
6. Near expiry, Amazon POSTs `grant_type=refresh_token&refresh_token=…` to the same URI with the
   same client authentication.

**The console setting to check.** Alexa developer console → the skill → **Build → Account
Linking** → section **Security Provider Information** → **"Your Client Authentication Scheme"**.
The options are **HTTP Basic (Recommended)** and **Credentials in request body** (SMAPI
`accessTokenScheme`: `HTTP_BASIC` | `REQUEST_BODY_CREDENTIALS`). Write down which is selected.
After B-3c, either works. On the same page, also read:

- the **Alexa Redirect URLs**: the vendor id at the end is `ALEXA_VENDOR_ID`;
- **Authorization URI** and **Access Token URI**: they must be the deployed `alexaAuth` and
  `alexaToken` URLs;
- **Domain List**;
- **Scope**;
- **Default Access Token Expiration Time**.

Google, for reference, sends credentials in the body by default and can be switched to Basic.

**alexaToken must accept both (B-3c).** Put the parsing in a pure module, e.g.
`src/voice/oauthClientAuth.ts`:

- **Header present** (`Authorization: Basic …`, scheme case-insensitive):
  - base64-decode, split on the **first** `:`;
  - form-urldecode each half (`+` → space, then `decodeURIComponent`);
  - malformed → `invalid_client`.
- **Body fields present** → use them.
- **Both present and different** → `invalid_client`. Both equal → accept.
- **Neither present** → `invalid_client`.
- **Compare** id and secret in constant time: HMAC both sides, then `timingSafeEqual`.
- **Fail closed.** If `ALEXA_CLIENT_ID` or `ALEXA_CLIENT_SECRET` is unset, answer 500
  `server_error`. Today the check is skipped entirely when they are unset.
- **401 `invalid_client`** carries `WWW-Authenticate: Basic realm="lumina"`.
- **Every token response** carries `Cache-Control: no-store` and `Pragma: no-cache`
  (RFC 6749 §5.1).
- **Errors** never echo `error.message`. Today's catch-all returns it.

## 3. The token the Lambda receives, and how it is verified

**Decision: a JWT that our function issues and our function verifies. The Lambda verifies
nothing; it becomes a ~30-line shim.** This is B-3b's design (token-format decision "a"), plus
the hardening below.

- `alexaToken` returns an HS256 JWT:
  - claims `{uid, iss: "lumina-alexa", aud: "alexa-smart-home", iat, exp: iat + 3600}`;
  - signed with `ALEXA_JWT_SECRET`, the only place the key lives (functions/.env).
- Amazon puts that token in each directive. The shim Lambda forwards the directive JSON verbatim
  to the `alexaSmartHome` HTTPS function and returns its response.
  - It holds no secret, no service account and no Firebase SDK.
  - B-4 checklist §4 has the shim; Smart Home skills only accept a Lambda ARN as endpoint.
- `alexaSmartHome` verifies the token (`verifyAlexaJwt`), then checks
  `users/{uid}/integrations/alexa.isLinked === true` (one read, see §4). Only then does it run
  the directive through `intentCore`.

**Why not "custom token exchanged server-side for an ID token":**

1. The Lambda would need a Google service-account key in AWS to call `verifyIdToken` and write
   Firestore. That is a long-lived, broad credential in a second cloud.
2. A Firebase ID token is a general session credential. Amazon would hold a token that works
   against Firestore as the user. In the other direction, any app ID token would pass the Lambda
   (token confusion).
3. It adds an Identity Toolkit call with the API key to every grant and refresh.

The JWT is audience-bound to one endpoint and useless anywhere else.

**Custom tokens are never accepted as ID tokens anywhere:**

- `alexaToken` stops minting them.
- `verifyAlexaJwt` accepts only HS256 signed with our secret, so an RS256 custom token or ID
  token fails the signature check.
- The legacy Lambda code (`alexa-skill/lambda/utils/firebase.js` `verifyIdToken`, and handlers
  writing the legacy `power`/`brightness` command shape) is retired, not repaired.

**Hardening B-3b needs before deploy (B-3c):**

1. **No fallback to `ALEXA_CLIENT_SECRET`.** B-3b signs with
   `ALEXA_JWT_SECRET || ALEXA_CLIENT_SECRET`, a key Amazon also holds. Require `ALEXA_JWT_SECRET`
   of ≥ 32 random bytes. If it is missing or short, `alexaToken` answers `server_error` and
   `alexaSmartHome` answers `INTERNAL_ERROR`, each with a log line.
2. **Verify more than the signature:**
   - header `alg === "HS256"` and `typ === "JWT"`;
   - `iss === "lumina-alexa"` and `aud === "alexa-smart-home"`;
   - **`exp` required** (B-3b accepts a token with no `exp` forever);
   - `iat` not in the future (60 s skew).
3. **Expired ≠ invalid.** An expired but well-signed token → `EXPIRED_AUTHORIZATION_CREDENTIAL`.
   A bad signature, wrong claims or unlinked account → `INVALID_AUTHORIZATION_CREDENTIAL`.
   B-3b returns INVALID for both and says that makes Amazon refresh. Amazon's error reference
   does not say that; EXPIRED is the documented "access token expired" type.
4. **Link check per directive** (§4), so an unlink takes effect immediately, not after up to 1 h.
5. **Privacy in Discovery cookies.** B-3b copies `userId` and `controllerIp` into every
   endpoint cookie, which Amazon stores. Drop both:
   - the uid comes from the token;
   - controller IPs are re-resolved server-side.

   Check that the `deviceUserId` cross-uid guard still has what it needs, or derive it from the
   token.
6. **Optional link gate during rollout.** `generateAlexaAuthCode` refuses, with a plain message,
   when `readVoiceControlEnabled(uid)` is false. Then a customer who finds a live skill cannot
   link before rollout. Needed only if the skill is live (blocked item B4).

## 4. Refresh tokens, link state, unlinking, and the app

**Storage.**

- `oauth_refresh_tokens/{sha256(token)}` holds `{userId, provider: "alexa", createdAt,
  lastUsedAt, active}`. Today the doc id is the raw token.
- Hash now: production has **zero** refresh tokens, so there is nothing to migrate.
- Clients cannot read or write `oauth_codes` or `oauth_refresh_tokens` (`firestore.rules`
  `allow read, write: if false`). No rules change is needed.
- Make the code redemption a **transaction**. Today two racing token requests can both see
  `used: false`.
- Store `redirect_uri` with the code. Compare it at redemption (RFC 6749 §4.1.3) when Amazon
  sends it.

**Link state written by the server** (`users/{uid}/integrations/alexa`):

- On `authorization_code` success, write `{isLinked: true, linkedAt, linkInitiated: delete,
  initiatedAt: delete}`.
- Stop writing `amazonUserId: client_id`: it stores the skill's client id under a user-id name.

**What the app shows.** Build 115 needs no change. The UI reads only this doc:

| Doc state | App shows |
|---|---|
| no doc | "Link Alexa Account" button |
| `linkInitiated: true` only | amber **Pending** + "Complete the setup in the Alexa app" (forever; nothing expires it) |
| `isLinked: true` | green **Linked** + Rediscover + Unlink (checked first, so it wins over a stale `linkInitiated`) |

**Unlinking.**

- **From the Lumina app (Unlink button).**
  - The app deletes the integration doc. Today nothing revokes the refresh token, so Amazon keeps
    a working credential.
  - B-3c adds a Firestore trigger `onAlexaIntegrationDeleted` (`users/{uid}/integrations/alexa`
    onDelete). It sets `active: false` on that user's Alexa refresh tokens.
  - Effect: the next directive fails the link check (INVALID); the next refresh gets
    `invalid_grant`; Alexa then asks the user to re-link. **No app build is needed.**
  - The same trigger fires on account purge (`recursiveDelete`). That closes the Alexa half of
    debt D-3, which `purgeUserAccount` lists as not done.
- **From the Alexa app (disable skill).**
  - Amazon discards its tokens. We are not told unless the skill subscribes to **skill events**
    (`SkillDisabled`, `SkillAccountLinked`; smart home skills support them, delivered to the
    skill endpoint).
  - In v1 our doc stays `isLinked: true`, and the app keeps showing Linked until the user taps
    Unlink. This is a known gap; skill events are v1.1. The shim already forwards every request,
    so v1.1 is server-only plus a manifest subscription.
- **The existing `alexaUnlink` HTTP endpoint** expects a Firebase ID token and nothing calls it.
  Leave it for now (no deploy); remove it in a later clean-up.

**The bench account's stuck "linkInitiated".**

- Do nothing manually. The first successful bench link writes `isLinked: true` (the UI shows
  Linked at once) and B-3c deletes `linkInitiated`/`initiatedAt` in the same write. The bench run
  then also tests the clearing.
- If you want it gone before the bench: open `users/<bench uid>/integrations/alexa` in the
  Firebase console. Confirm it holds only `linkInitiated` and `initiatedAt`, then delete the doc.
  That is a production write and your call; the app has no button for it in the Pending state.

## 5. Production touchpoints and deploys, in order

Nothing below runs until Prompt C has cleared for the Falcons at Saints game. Every functions
deploy:

- runs from a clean worktree at the exact SHA, with `functions/.env` copied from the main tree;
- uses `firebase deploy --only functions:<list> --project icrt6menwsv2d8all8oijs021b06s5`;
- is read back, then gets a `docs/BUILD_LEDGER.md` row.

**Game Day calendar to stay clear of:**

- tonight's start fire window;
- Thu 10-08 evening (TNF);
- **Fri 10-09**: 08:00–11:00 is reserved for the ESPN-slate planner deploy, and the rehearsal
  is at 18:00;
- Sat and Sun 10-10 and 10-11.

Predicted bench-bridge stale gaps (7 h 27 m cadence, ±1 h; check the watcher log for the
latest): Tue 10-06 ~13:40, Wed 10-07 ~12:00, Thu 10-08 ~10:25 (all CDT). The bench voice steps
go through the bridge; keep them outside a gap.

### Phase 1: security fix only. Tue 10-06, 09:00–12:00 CDT

| Step | Touchpoint | Who |
|---|---|---|
| 1 | Add `ALEXA_VENDOR_ID=<vendor id>` to the main tree's `functions/.env` (from the console's Alexa Redirect URLs). Leave `GOOGLE_HOME_PROJECT_ID` unset: Google linking stays refused. | Tyler |
| 2 | Deploy `functions:alexaAuth,functions:googleAuth` from `988c2d6` | Tyler / session on "approve deploy" |
| 3 | Read back (GET only, no writes): `alexaAuth?client_id=<id>&redirect_uri=https://evil.example/?amazon.com&state=s` → 400, the fixed error page and the lock-down CSP. The same request with a real redirect URL → 200 with `Content-Security-Policy` containing `nonce-`. | session |

- **User impact:** none. Linking is already broken one step later, at the missing script, so
  nothing that worked can stop working.
- **Rollback:** redeploy the two functions from `9be91a1`. That puts the XSS back; only do it if
  the deploy itself failed.

### Phase 2: linking + voice, as one change. Wed 10-07, 09:00–11:00 CDT

Fallback: Tue 10-13, the same hours.

| Step | Touchpoint | Who |
|---|---|---|
| 1 | Merge `feat/voice-link-e2e` (B-3c) into release after review; gates as in §7 | session |
| 2 | Add `ALEXA_JWT_SECRET=<≥32 random bytes, base64>` to the main tree's `functions/.env` | Tyler |
| 3 | Firestore `config/voice_control` = `{enabled: false, allowlistUids: ["<bench uid>"]}` (B-3b's reader treats missing or garbage as false) | Tyler |
| 4 | Deploy `functions:alexaAuth,functions:googleAuth,functions:generateAlexaAuthCode,functions:alexaToken,functions:alexaSmartHome,functions:onAlexaIntegrationDeleted`. **Not** `executeWledCommand`, `googleSmartHome`, `googleToken` or anything Game Day. | Tyler / session |
| 5 | AWS: deploy the shim Lambda (Node 22, no dependencies, env `FULFILLMENT_URL=<alexaSmartHome URL>`, timeout 8 s) in the skill's region (NA → us-east-1). Add the **Alexa Smart Home** trigger with **skill ID verification** on. | Tyler |
| 6 | Alexa console: skill endpoint (default) → the shim ARN. Check Account Linking per §2; add `www.gstatic.com`, `identitytoolkit.googleapis.com`, `securetoken.googleapis.com` and the functions host to Domain List. Keep the skill in **Development**. | Tyler |
| 7 | Bench run (§8) | Tyler + session |
| 8 | Ledger row; update the B-4 checklist Results slots | session |

- **Kill switch:** `config/voice_control.enabled=false` with an empty allowlist. Discovery
  returns no endpoints and control returns `ENDPOINT_UNREACHABLE`; neither unlinks anyone.
- **Rollback:**
  - redeploy `alexaAuth` and `googleAuth` from `988c2d6`, so linking stops at the page again;
  - redeploy `alexaToken` and `generateAlexaAuthCode` from `988c2d6`;
  - leave `alexaSmartHome` and the shim in place, behind the flag.

### Phase 3: later, separate approval

- Percentage rollout (B-4 §5).
- Skill events.
- Google (needs a Google Home project, `GOOGLE_HOME_PROJECT_ID`, a decision on a Google token
  format, and the app's placeholder URL fixed).
- Certification.

### Every production touchpoint, in one list

- **Functions:**
  - Phase 1: `alexaAuth`, `googleAuth`.
  - Phase 2: `alexaAuth`, `googleAuth`, `generateAlexaAuthCode`, `alexaToken`, `alexaSmartHome`
    (new), `onAlexaIntegrationDeleted` (new).
- **Env (functions/.env, main tree):** `ALEXA_VENDOR_ID` (phase 1), `ALEXA_JWT_SECRET` (phase 2).
- **Firestore config:** `config/voice_control` (phase 2).
- **Firestore data written by the functions during the bench:** `oauth_codes`,
  `oauth_refresh_tokens`, `users/<bench>/integrations/alexa`, `users/<bench>/commands`.
- **AWS:** one Lambda (shim), its trigger.
- **Alexa console:** endpoint ARN, account-linking fields.
- **Rules, indexes, app build, bridge firmware, bridge registry:** none.

## 6. Code work for B-3c (`feat/voice-link-e2e`)

Off `fix/voice-link-page`. Merge `5489808` (§1), then:

1. `src/voice/oauthClientAuth.ts`: client-credential parsing (§2), unit-tested.
2. `index.js` `alexaToken`:
   - use (1), with no-store headers;
   - hashed refresh tokens;
   - transactional code use plus the `redirect_uri` match;
   - the link write clears `linkInitiated`;
   - no `amazonUserId`;
   - no error echo;
   - JWT via the hardened signer.
3. `src/voice/alexaJwt.ts`: alg/typ/iss/aud/exp/iat checks; a `reason` (`expired` | `invalid`);
   refuse a short or missing secret.
4. `src/voice/alexaSmartHome.ts` and the `index.js` wrapper:
   - EXPIRED vs INVALID;
   - the `isLinked` read;
   - no secret fallback;
   - cookies without uid or IP.
5. `generateAlexaAuthCode`: the optional link gate (§3.6). Optionally store `redirect_uri`
   (the page passes it).
6. New `onAlexaIntegrationDeleted` (`src/voice/alexaLinkLifecycle.ts`) and its export.
7. `alexa-skill/shim/index.js`: the shim (B-4 §4), with a 7 s `AbortSignal` timeout and a
   well-formed ErrorResponse on non-2xx or timeout; it never logs `scope.token`. Mark
   `alexa-skill/lambda/` legacy in `alexa-skill/DEPLOYMENT.md`; that file still gives Firebase's
   own auth handler and `securetoken` as the Authorization and Access Token URIs, which is wrong.
8. `package.json` `test:voice` narrowed (§1).
9. Docs: this plan's status; the B-4 checklist corrections (secret fallback removed, INVALID vs
   EXPIRED, the console steps).

## 7. Test plan

**Unit (jest, `test/unit`, against `lib/`)**

- **oauthClientAuth:**
  - Basic valid;
  - Basic with `:`, `%` and `+` in the secret;
  - lowercase `basic`;
  - no colon;
  - bad base64;
  - body only;
  - both equal;
  - both different;
  - neither;
  - wrong secret → 401 with `WWW-Authenticate`;
  - server unconfigured → 500.
- **alexaJwt:**
  - round trip;
  - tampered payload and signature;
  - `alg: none`;
  - RS256 header;
  - a real-shaped Firebase custom token and ID token (synthetic) → invalid;
  - missing `exp` → invalid;
  - expired → `expired`;
  - wrong iss and aud;
  - future iat;
  - short secret → throws.
- **alexaSmartHome:**
  - expired → EXPIRED;
  - bad → INVALID;
  - unlinked uid → INVALID;
  - flag off → empty Discovery and ENDPOINT_UNREACHABLE;
  - cookies carry no uid or IP.
- **B-3b's 36 node:test cases** via `npm run test:voice`, added to the gate.
- **Link pages:** the existing `oauthLinkPage.test.js` (202) stays green.

**Shim (node:test, `alexa-skill/shim`)** with a fake `fetch`:

- forwards the body byte-for-byte;
- returns the JSON;
- non-2xx and timeout → ErrorResponse with the request's `correlationToken`;
- the token never appears in logs.

**Emulator (firestore + auth; recipe in memory/README; `--testTimeout=120000`)**

- **Full chain:**
  1. seed a user and controllers;
  2. `generateAlexaAuthCode` → `oauth_codes` doc;
  3. drive the real `alexaToken` handler with Basic → JWT + refresh token;
  4. check the integration doc: `isLinked` true, no `linkInitiated`;
  5. the refresh token is stored hashed;
  6. repeat with body credentials.
- **Rejections:**
  - code reuse → `invalid_grant`;
  - an expired code → `invalid_grant`;
  - two concurrent redemptions → exactly one succeeds.
- **Refresh:** a new JWT; then delete the integration doc → trigger → refresh → `invalid_grant`.
- **alexaSmartHome with the minted JWT:**
  - Discovery lists the seeded controllers (allowlisted uid);
  - TurnOn writes one canonical command (`type setState`, string payload, `source
    voice_alexa`); mark it completed → `Alexa.Response`;
  - with the doc deleted → INVALID.
- **Gate:** the full emulator suite, where only the two #119 cases may fail.

**Before deploy, in a browser (no sign-in):**

- Serve `alexaAuth` from the functions emulator.
- Open it in desktop Chrome with DevTools: **zero CSP violations at load**, three SDK scripts
  loaded.
- Do not submit the form: the page holds production Firebase config.
- Mobile Safari and Chrome initialise the auth iframe proactively. Expect one swallowed CSP
  report for `apis.google.com`; email and password sign-in does not need it.
- If the project enforces reCAPTCHA for email/password, the bench will show a CSP block on
  `www.google.com/recaptcha`; add those origins then.

## 8. Bench end-to-end (test Alexa developer account only)

**Who and what:**

- the Amazon **test developer account** that owns the Development-stage skill (or one beta
  tester it invites); **no customer Amazon accounts**;
- the **bench Lumina account** only;
- the bench controller through the bench bridge;
- no customer devices.

Avoid `.150` for scene steps unless the scene payload has been checked for `psave`/`pdel`.
Power and brightness are fine.

1. **Link.** Alexa app (signed in to the test account) → Skills → Your Skills → **Dev** → the
   skill → Enable.
   - The `alexaAuth` page loads. Sign in with the bench Lumina account.
   - Alexa reports success.
   - **Pass:**
     - logs show `generateAlexaAuthCode` 200 and `alexaToken` 200 (no 401);
     - `integrations/alexa` = `isLinked: true`, no `linkInitiated`;
     - the app shows **Linked**;
     - there is one hashed refresh-token doc.
2. **Discover.** "Alexa, discover devices" → the bench endpoints appear.
3. **Control.**
   - **Commands:** "turn on <name>" / "set <name> to 50 percent" / "turn off <name>".
   - **Pass:**
     - each writes one `users/<bench>/commands` doc (`source: voice_alexa`, string payload);
     - the bridge completes it;
     - the light changes;
     - Alexa says OK.
   - **Record:** p50 and p95 command round trip, and how often the 4 s wait ends `optimistic`
     (B-4 §5 Results).
4. **Refresh.** Wait 70 minutes, then run any command.
   - **Pass:** the logs show one `refresh_token` grant 200, then the command succeeds.
5. **Unlink from the app.** Tap Unlink.
   - The doc is deleted and the trigger revokes the tokens.
   - "Turn on" fails, with no light change.
   - Within a refresh cycle, the Alexa app asks to re-link.
6. **Re-link, then disable the skill in the Alexa app.** Expected v1 gap: the app still shows
   Linked. Tap Unlink to clean up.
7. **Negative.** A second Lumina account that is not allowlisted links (if the gate is off)
   → Discovery returns nothing, and control returns ENDPOINT_UNREACHABLE.

**Abort** on any 5xx loop, any command to a non-bench controller, or any write outside the bench
uid. Then flip the kill switch and roll back per Phase 2.

## 9. Game Day and the bridge

- **Linking** (`alexaAuth`, `generateAlexaAuthCode`, `alexaToken`, the trigger) touches neither
  Game Day nor the bridge.
- **Voice commands** use the **existing relay data path as a consumer**:
  - they write canonical `setState`/`applyJson` command docs to `users/{uid}/commands`, the same
    shape `applySyncPattern` writes;
  - `executeWledCommand` (unchanged, not redeployed) forwards webhook-mode ones and fails
    bridge-less accounts fast;
  - the paired bridge picks up the rest exactly as it does app commands.
- **No change** to bridge firmware, the bridge registry, `bridge_status`, the bridge rules
  deployed 10-05, or the bridge pairing flow.
- **Game Day:** a "gameday-<team>" voice scene reads
  `users/{uid}/game_day_autopilot/{team}.saved_design_payload` and applies it once. It never
  writes Game Day docs and never involves the planner, dispatcher, sweeper or leases. No Game Day
  function is in any deploy above.
- **Behavioural overlap:** a voice "turn off" during a served fire turns the lights off, the same
  as the app's power button.

## 10. App side

- **Bench and Phase 2: no build.** Linking starts in the Alexa app. The app only reads
  `integrations/alexa`, and the server now keeps it correct (link clears Pending; app Unlink
  triggers revocation).
- **Next build, not blocking:**
  1. **Android 11+.** The manifest's `<queries>` has no VIEW intent for `https` or `alexa`. The
     `alexa://` attempt has no iOS `LSApplicationQueriesSchemes` entry either. So "Link Alexa
     Account" may silently do nothing on Android: it writes Pending and returns `false`, which
     the UI ignores. Add the queries, or launch without `canLaunchUrl`.
  2. Treat a `linkInitiated` older than 24 h as not linked, or offer Cancel in Pending.
  3. Show an error when the launch fails.
  4. If a **new** skill is created rather than re-pointing the existing one,
     `alexa_service.dart` `skillId` changes, which needs a build. The bench can enable the dev
     skill from the Alexa app directly, so it is not blocked by this.
  5. Google: `google_home_service.dart` still launches a `000000YOUR_PROJECT_ID` placeholder.

## 11. Blocked on the owner

- **B1:** Alexa console, Build → Account Linking. Report:
  - the **Client Authentication Scheme** value;
  - the **vendor id** from Alexa Redirect URLs (it goes into `functions/.env` only, never the
    repo);
  - whether Authorization URI and Access Token URI are the `alexaAuth` and `alexaToken` URLs.
- **B2:** the skill's **type and endpoint**: Smart Home? which Lambda ARN? what code runs there
  now?
- **B3:** a **test Alexa developer account** (Amazon) with the skill in Development, plus a phone
  with the Alexa app signed in to it.
- **B4:** whether the skill is **live or Development-only**. This decides whether the link gate
  (§3.6) is required.
- **B5:** approval to deploy Phase 1, and later Phase 2, in the windows above. You also make the
  `.env` and `config/voice_control` writes and the AWS and console steps.

## 12. Sources

- Amazon, "Account Linking Schemas" (SMAPI): authorization-code redirect URI
  `{baseUrl}/api/skill/link/{vendorId}`, valid baseUrls pitangui/layla/alexa.amazon.co.jp, and
  `accessTokenScheme` `HTTP_BASIC` | `REQUEST_BODY_CREDENTIALS`:
  https://developer.amazon.com/en-US/docs/alexa/smapi/account-linking-schemas.html
- Amazon, "Configure an Authorization Code Grant" (console Account Linking page, Security
  Provider Information):
  https://developer.amazon.com/en-US/docs/alexa/account-linking/configure-authorization-code-grant.html
- Amazon, "Alexa.ErrorResponse" (EXPIRED vs INVALID_AUTHORIZATION_CREDENTIAL):
  https://developer.amazon.com/en-US/docs/alexa/device-apis/alexa-errorresponse.html
- Amazon, "Use Skill Events" (SkillDisabled and others, all skill models):
  https://developer.amazon.com/en-US/docs/alexa/smapi/skill-events-in-alexa-skills.html
- Google Home Developers, "OAuth 2.0 authorization" (redirect URIs
  `oauth-redirect[-sandbox].googleusercontent.com/r/{project}`; body credentials by default):
  https://developers.home.google.com/cloud-to-cloud/project/authorization
- RFC 6749 §2.3.1 (client password, Basic encoding), §4.1.3 (redirect_uri at the token endpoint),
  §5.1 (no-store).
