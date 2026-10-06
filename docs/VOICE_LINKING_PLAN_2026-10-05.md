# Voice linking: Alexa account linking and voice commands, end to end

Written 2026-10-05; updated the same evening for B-3c (`feat/voice-link-e2e`). Scope: Alexa.
Google Home is noted where the same code serves it. **Nothing here is deployed.** No production
doc, config, console or AWS resource has been written.

## 0. Status

| # | Wall | Fix | Branch |
|---|------|-----|--------|
| 0 | XSS + open redirect on the login pages | exact redirect allowlist, JSON-escaped values, nonce CSP | `fix/voice-auth-xss` `988c2d6`; ships alone (Phase 1) |
| 1 | `firebase.functions is not a function` after sign-in | load `firebase-functions-compat.js` 10.7.1 | `fix/voice-link-page` `0b138bf`; ships only with B-3c |
| 2 | `alexaToken` → 401 under HTTP Basic | accept Basic **and** body; missing and wrong refused identically | `feat/voice-link-e2e` (B-3c) |
| 3 | every directive fails: a custom token used as access token | self-issued HS256 access token verified by `alexaSmartHome`; the Lambda is a secret-free shim | `feat/voice-link-e2e` (B-3c) |

B-3c also closes every B-3b defect found in review (§3).

## 1. Branches

| Branch | Head | Contents |
|---|---|---|
| `fix/voice-auth-xss` | `988c2d6` | security fix only, off release `9be91a1` |
| `fix/voice-link-page` | `24b9ff3` | + compat tag (`0b138bf`) + the first version of this plan |
| `feat/voice-canonical-commands` (B-2..B-4) | `5489808` | intentCore, Google rewire, Alexa Smart Home (B-3b) |
| `feat/voice-link-e2e` (**B-3c**) | see the push | `996fa87` = B-3b merged onto `24b9ff3` **as written** (the negative-control baseline); then the B-3c fixes and this update |

Merge notes (`996fa87`):

- three mechanical conflicts:
  - the `index.js` require block (keep B-3b's requires, drop the `OPENAI_API_KEY` param release
    removed);
  - `.gitignore` (both blocks);
  - `package.json` (release's jest scripts plus B-3b's runner as `test:voice`, narrowed to
    `lib-test/test/voice/**`);
- it also brings B-3b's `tsconfig.test.json` and `docs/VOICE_LAUNCH_CHECKLIST.md`.

Where that checklist disagrees with this plan, **this plan wins**: no client-secret fallback, no
"INVALID makes Amazon refresh", Alexa kill-switch responses, and the Phase 2 order.

> **Never deploy from `feat/voice-canonical-commands` or the `lumina-voice` worktree.** Its tree
> predates the relay fail-fast (`8b3bcdf`); a functions deploy there reverts `executeWledCommand`.
> Deploy only named functions, from the merged release head.

## 2. Amazon's flow and client authentication

**Authorization code grant:**

1. The Alexa app opens `alexaAuth` with `client_id`, `response_type=code`, `state`, `scope` and
   `redirect_uri`. The redirect URI is one of
   `{https://pitangui.amazon.com | https://layla.amazon.com | https://alexa.amazon.co.jp}/api/skill/link/{vendorId}`.
2. The page signs the user in and calls `generateAlexaAuthCode({idToken, state, redirectUri})`.
   That stores a 5-minute, single-use code bound to that redirect URL, then the page redirects
   with `state` and `code`.
3. Amazon POSTs `grant_type=authorization_code&code&redirect_uri` to `alexaToken`, with client
   credentials as **HTTP Basic** (`Authorization: Basic base64(urlenc(id):urlenc(secret))`) or
   **in the body** (`client_id`, `client_secret`).
4. `alexaToken` answers `{access_token, token_type: "Bearer", expires_in: 3600, refresh_token}`
   with `Cache-Control: no-store`.
5. Directives reach the shim Lambda. The token is in `directive.payload.scope.token` (Discover),
   `directive.payload.grantee.token` (AcceptGrant) or `directive.endpoint.scope.token`
   (everything else).
6. Amazon refreshes with `grant_type=refresh_token`, using the same client authentication.

**Console setting to read, not change:** Alexa developer console → the skill → **Build →
Account Linking → Security Provider Information → "Your Client Authentication Scheme"**.
The options are **HTTP Basic (Recommended)** and **Credentials in request body** (SMAPI
`accessTokenScheme`). **B-3c accepts both.**

`alexaToken` client authentication (`src/voice/oauthClientAuth.ts`):

- **Header present:** it must be well-formed Basic. Each half is form-urldecoded. Any body
  `client_id`/`client_secret` must agree with it.
- **No header:** the body must carry both fields.
- **Comparison:** constant time (HMAC digests and `timingSafeEqual`, both halves always
  compared).
- **Missing, malformed or wrong credentials:** the identical refusal, `401
  {"error":"invalid_client"}` with `WWW-Authenticate: Basic realm="lumina-alexa"` and no-store.
  The code is not spent.
- **Server not configured** (`ALEXA_CLIENT_ID`/`ALEXA_CLIENT_SECRET` empty): `500 server_error`,
  never a skipped check.

## 3. Tokens, keys and the B-3b fixes

| B-3c fix | What it does now | Where |
|---|---|---|
| 1. Dedicated key | `ALEXA_JWT_SECRET` from the function environment (`process.env`, so a deploy never prompts), ≥ 32 bytes. Missing or short: `alexaToken` → `500 server_error` before any code is spent; `alexaSmartHome` → `INTERNAL_ERROR`. **No fallback to `ALEXA_CLIENT_SECRET`.** | `alexaJwt.readAlexaJwtSecret` |
| 2. Expiry everywhere | Access token: HS256 JWT `{lid, iss: "lumina-alexa", aud: "alexa-smart-home", iat, exp = iat + 3600}`. Verify pins header alg/typ; requires iss, aud, iat and exp; rejects a lifetime over 1 h and iat in the future. Refresh token: 32 random bytes, stored only as SHA-256 (`oauth_refresh_tokens/{lid}`) with `{userId, provider, iss, aud: <client id>, active, createdAt, lastUsedAt, expiresAt}`. 90 days, sliding on each use; a record without `expiresAt`, past it, revoked, or issued to another client is refused. | `alexaJwt.ts`, `alexaLink.validRefreshRecord` |
| 3. Nothing identifying to Amazon | **The access token carries no uid**: the handler reads the uid from the refresh record. Discovery sends per endpoint exactly `endpointId, manufacturerName, description, friendlyName, displayCategories, capabilities`. No cookie, no additionalAttributes. Details below. | `alexaSmartHome.ts` |
| 4. Both credential forms | §2 | `oauthClientAuth.ts` |
| 5. Documented behaviour only | Expired but well-signed → `EXPIRED_AUTHORIZATION_CREDENTIAL`; anything else → `INVALID_AUTHORIZATION_CREDENTIAL`. Amazon documents the meaning of each type, not what Alexa does next; the code relies on no refresh behaviour (source cited in the code). | `alexaSmartHome.ts` header |
| 6. The app's command queue | Commands are written to `users/{uid}/commands` with the app's seven fields plus `source`, and a string payload. Before writing, the **same relay-eligibility predicate** as the app and `executeWledCommand` runs (`relayEligibility.hasPairedBridge`): bridge mode with no paired bridge queues nothing and returns `ENDPOINT_UNREACHABLE`; a lookup error fails open, as the trigger does. Queued commands meet `executeWledCommand`'s fail-fast like any app command. No controller I/O, no Game Day reads or writes (Game Day designs are no longer voice-activatable), no bridge-registry writes, no rules change. | `intentCore.executeIntent` |
| 7. Kill switch | `config/voice_control`; a missing doc is **OFF** with an empty allowlist. Read on **every** directive (one batched read with the link doc). A disabled or non-allowlisted account gets `INSUFFICIENT_PERMISSIONS` (Discover accepts it), message "Voice control is not enabled for this account.", and nothing else: no reads past that point, no writes. A **new link** is refused too (`generateAlexaAuthCode` → permission-denied; `alexaToken` code exchange → `invalid_grant`). **Refresh is not gated**, so switching off never breaks an existing link. | `alexaSmartHome.ts`, `alexaLink.ts`, `index.js` |
| 8. Unlink and Pending | §4 | `alexaLink.ts`, `index.js` |

**What Amazon receives, exactly.** Discovery returns per endpoint:

- **`endpointId`:** `lumina-main` (the primary controller: oldest by createdAt, the existing
  deviceResolver contract), `ctl-<k>` (other controllers) or `scn-<k>` (activatable scenes).
  `<k>` is a 24-character keyed hash (`HMAC(ALEXA_JWT_SECRET, uid|kind|id)`). It is never a
  uid, controller doc id (MAC-shaped), IP or scene doc id.
- **`friendlyName`:** the controller's or scene's own name as typed in the app; the API needs a
  spoken name. An unnamed primary is "House Lights" and other unnamed controllers "Lights N".
  The profile's `propertyName` (often an address) is never used.
- **`manufacturerName` / `description`:** fixed strings.
- **`displayCategories`:** `LIGHT` or `SCENE_TRIGGER`.
- **`capabilities`:** Alexa, PowerController and BrightnessController, or Alexa and
  SceneController.

Responses carry:

- a header with a fresh `messageId` and Amazon's `correlationToken`;
- the `endpointId` Amazon sent, only if it has one of our shapes;
- `powerState`/`brightness` properties;
- fixed `ErrorResponse` messages (Amazon uses them for logging only).

Token responses carry `access_token` (no uid inside), `token_type`, `expires_in` and an opaque
`refresh_token`.

**Key rotation note.** `ALEXA_JWT_SECRET` also keys endpoint ids. Rotating it invalidates every
access token (Amazon refreshes, so links survive) and re-keys endpoint ids (devices re-discover as
new; routines must be re-pointed). Rotate only as a planned operation.

## 4. Unlinking and the Pending state

- **Link.** A successful code exchange writes `integrations/alexa = {isLinked: true, linkedAt}`
  and **deletes `linkInitiated`/`initiatedAt`** in the same batch, so Pending ends the moment a
  link succeeds.
- **Unlink from the Lumina app.** The Unlink button deletes the integration doc.
  1. From that instant every directive fails the per-directive link check: `isLinked` must be
     true and the token's refresh record valid. Result: `INVALID_AUTHORIZATION_CREDENTIAL`.
  2. The new trigger **`onVoiceIntegrationDeleted`** (`users/{uid}/integrations/{provider}`
     onDelete) sets `active: false` and `revokedAt` on every refresh token the user holds for
     that provider: `oauth_refresh_tokens` for alexa, `google_oauth_refresh_tokens` for
     google_home.
  3. Amazon's next refresh gets `invalid_grant`.

  The same trigger fires on account purge. **No app build is needed.**
- **Disable in the Alexa app.** Amazon drops its tokens without telling us. The app keeps showing
  Linked until the user taps Unlink. Known v1 gap; skill events (`SkillDisabled`) are v1.1.
- **Stuck Pending.** The new daily **`sweepStaleVoiceLinks`** (09:15 UTC) scans
  `users/*/integrations/{alexa|google_home}`:
  - `linkInitiated` older than 24 h and nothing else in the doc → the doc is deleted (app shows
    "Link Alexa Account");
  - stale but other fields present (e.g. a Google DISCONNECT's `isLinked: false`) → the two flags
    are removed;
  - a linked doc with a leftover flag → the flag is removed;
  - fresh intents (< 24 h) and other providers are untouched.
- **The bench account's current Pending.** Its doc holds only `linkInitiated`/`initiatedAt` from
  10-05, so it clears either way, with **no manual write**:
  1. at the bench link (step 7 below), or
  2. at the first `sweepStaleVoiceLinks` run after the Phase 2 deploy (09:15 UTC the next
     morning).

## 5. Deploy order and windows

**Hard gate:** nothing below runs until Prompt C has cleared. Every functions deploy:

- runs from a clean worktree at the merged release SHA, with `functions/.env` copied from the
  main tree;
- uses `firebase deploy --only functions:<list> --project icrt6menwsv2d8all8oijs021b06s5`;
- is read back, then gets a `docs/BUILD_LEDGER.md` row.

**Avoid (Game Day):**

- Mon 10-05 evening;
- Thu 10-08 from 17:30 CDT (TNF);
- **all of Fri 10-09**: 08:00–11:00 is the ESPN planner deploy, 18:00 the rehearsal, and there is
  a bridge gap ~08:49;
- Sat–Sun 10-10/11;
- Mon 10-12 evening.

Before each window, read (read-only) that day's `fire_jobs` / planner schedule to confirm no fire
is due. Postseason MLB day games are the one weekday risk.

**Predicted bench-bridge stale gaps** (7.46 h from 10-05 20:18Z, ±1 h):

| UTC | CDT |
|---|---|
| 10-06 03:45 | Mon 22:45 |
| 10-06 11:13 | Tue 06:13 |
| 10-06 18:40 | Tue 13:40 |
| 10-07 02:08 | Tue 21:08 |
| 10-07 09:36 | Wed 04:36 |
| 10-07 17:03 | Wed 12:03 |
| 10-08 00:31 | Wed 19:31 |
| 10-08 15:26 | Thu 10:26 |
| 10-08 22:54 | Thu 17:54 |

Bench voice steps go through the bridge; keep them outside these ±1 h windows.

### Phase 1: security fix only. Tue 10-06, 09:00–11:30 CDT

| Step | Action | Who |
|---|---|---|
| 1 | `ALEXA_VENDOR_ID=<vendor id>` into main `functions/.env` (from the console's Alexa Redirect URLs; never into the repo) | Tyler |
| 2 | Deploy `functions:alexaAuth,functions:googleAuth` from `988c2d6` (or the merged release head carrying it) | on Tyler's word |
| 3 | Read back (GET only): an `evil.example/?amazon.com` redirect → 400 fixed page with the lock-down CSP; a real redirect URL → 200 with `Content-Security-Policy: … 'nonce-…'` | session |

No user impact: linking already fails later. Rollback: the two functions from `9be91a1`.

### Phase 2: linking + voice, one change. Wed 10-07, deploy 08:30–09:30 CDT, bench 09:30–10:50 CDT

The window avoids the Wed ~12:03 gap (11:03–13:03). Afternoon fallback: bench 13:15–16:00 CDT the
same day. Next fallback: Thu 10-08, bench 11:30–16:30 CDT (after the 10:26 gap, before TNF).

| Step | Action | Who |
|---|---|---|
| 1 | Merge `feat/voice-link-e2e` into release after review; gates (§7) on the merge result | session on Tyler's word |
| 2 | Main `functions/.env`: `ALEXA_JWT_SECRET=<48 random bytes, base64>` (e.g. `openssl rand -base64 48`), plus the step 1 vendor id if not already there | Tyler |
| 3 | Firestore `config/voice_control` = `{enabled: false, allowlistUids: ["<bench uid>"]}`. Required **before** the bench link: new links are refused for non-allowlisted accounts. | Tyler |
| 4 | Deploy `functions:alexaAuth,functions:googleAuth,functions:generateAlexaAuthCode,functions:alexaToken,functions:alexaSmartHome,functions:onVoiceIntegrationDeleted,functions:sweepStaleVoiceLinks`. **Not** `executeWledCommand`, `googleSmartHome`, `googleToken`, or anything Game Day / bridge. | on Tyler's word |
| 5 | Read back: `alexaToken` with no credentials → `401 invalid_client` + `WWW-Authenticate`; `alexaSmartHome` with a garbage token → `INVALID_AUTHORIZATION_CREDENTIAL` envelope | session |
| 6 | AWS: create the shim Lambda from `alexa-skill/shim/index.js` (Node 22, no dependencies, env `FULFILLMENT_URL=<alexaSmartHome URL>`, timeout 8 s) in the skill's region (NA → us-east-1); add the **Alexa Smart Home** trigger with **skill ID verification**. Alexa console: default endpoint → the shim ARN; Account Linking: Authorization URI = `alexaAuth`, Access Token URI = `alexaToken`, Domain List += `www.gstatic.com`, `identitytoolkit.googleapis.com`, `securetoken.googleapis.com`, the functions host. Keep the skill in **Development**. | Tyler |
| 7 | Bench run (§8) | Tyler + session |
| 8 | Ledger row; B-4 checklist Results slots | session |

- **Kill switch:** delete `config/voice_control` (or empty the allowlist). Every directive then
  gets `INSUFFICIENT_PERMISSIONS`; links survive.
- **Rollback:**
  - `alexaAuth`, `googleAuth`, `generateAlexaAuthCode` and `alexaToken` from `988c2d6`;
  - the shim and `alexaSmartHome` stay behind the switch;
  - the two new functions can stay (the trigger only revokes; the sweep only clears stale
    intents) or be deleted.

### Every production touchpoint

- **Functions:**
  - Phase 1: `alexaAuth`, `googleAuth`.
  - Phase 2: those two plus `generateAlexaAuthCode`, `alexaToken`, `alexaSmartHome` (new),
    `onVoiceIntegrationDeleted` (new), `sweepStaleVoiceLinks` (new).
- **Env:** `ALEXA_VENDOR_ID`, `ALEXA_JWT_SECRET`.
- **Firestore config:** `config/voice_control`.
- **Data written by the functions:** `oauth_codes`, `oauth_refresh_tokens`,
  `users/<bench>/integrations/alexa`, `users/<bench>/commands`. Stale intents are deleted or
  stripped by the sweep.
- **AWS:** one Lambda + trigger.
- **Alexa console:** endpoint ARN, account-linking fields.
- **Rules, indexes, app build, bridge firmware, bridge registry, Game Day:** none.

## 6. What changed in B-3c (files)

- `functions/src/voice/`:
  - `alexaJwt.ts`: rewritten; the key reader, no uid, claims, reasons, endpoint keys.
  - `oauthClientAuth.ts`: new.
  - `alexaLink.ts`: new; token endpoint, refresh records, revocation, sweep.
  - `alexaSmartHome.ts`: rewritten handler.
  - `intentCore.ts`: eligibility, app shape, no Game Day, pure kill-switch reader.
  - `googleSmartHome.ts`: maps `no_bridge`.
  - `deviceResolver.ts`: exports the oldest-first loader.
- `functions/index.js`:
  - `generateAlexaAuthCode`: kill switch, redirect binding, no error echo;
  - the `alexaAuth` page passes `redirectUri`;
  - `alexaToken` and `alexaSmartHome` wrappers;
  - two new exports.
- `alexa-skill/shim/`: the Lambda and its test.
- Tests:
  - `functions/test/emulator/voiceAlexaLink.emulator.test.ts` (new, 36);
  - `functions/test/unit/voiceAlexaAuth.test.js` (new);
  - `functions/test/voice/*` updated to the B-3c contract (fixture IPs now RFC 5737).

## 7. Test results (2026-10-05)

- **Unit (jest):** 888/888, 29 suites.
- **Voice (`npm run test:voice`, node:test):** 43/43.
- **Shim (`node --test alexa-skill/shim/index.test.js`):** 4/4.
- **Emulator** (`--testTimeout=120000`, firestore + auth): 456/458; the only failures are the two
  known #119 cases.
- **New B-3c emulator file:** 36/36.
- **Negative control:** the same 36-case emulator file run against `996fa87` (B-3b as written):
  **30 fail**, every fix block included. The 6 that pass cover behaviour B-3b already had right:
  - body credentials accepted;
  - webhook-mode queueing;
  - `executeWledCommand` fail-fast on a voice command;
  - no Game Day / controller / registry writes in that run;
  - refresh still working with the switch off;
  - an allowlisted account works.

  The Game Day half of fix 6 fails on B-3b in the static-scan case and in the node:test
  "Game Day designs are not voice-activatable" case.

**Before deploy, in a browser (no sign-in):**

- Serve `alexaAuth` from the functions emulator and check there are zero CSP violations at load.
- Expect one swallowed report for `apis.google.com` on mobile; email and password sign-in does
  not need it.
- A reCAPTCHA-enforcing project would need `www.google.com/recaptcha` added.

## 8. Bench end to end (test Alexa developer account only)

**Who and what:**

- the Amazon **test developer account** that owns the Development-stage skill, with no customer
  Amazon accounts;
- the **bench Lumina account** (allowlisted);
- the bench controller through the bench bridge.

Avoid scene steps on `.150` unless the scene payload is checked for `psave`/`pdel`.

1. **Link.** Alexa app → Skills → Your Skills → Dev → the skill → Enable → sign in on the
   `alexaAuth` page.
   - **Pass:**
     - `generateAlexaAuthCode` 200, `alexaToken` 200 (never 401);
     - `integrations/alexa` = `{isLinked, linkedAt}` with no `linkInitiated`;
     - the app shows **Linked**;
     - there is one hashed refresh record.
2. **Discover.**
   - **Pass:**
     - `lumina-main`, any `ctl-…` and `scn-…` endpoints with the app's names;
     - nothing else in the response.
3. **"Turn on / set 50 percent / turn off <name>".**
   - **Pass:**
     - one `users/<bench>/commands` doc per command (`source: voice_alexa`, string payload);
     - the bridge completes it;
     - the light changes.
   - **Record:** p50/p95 and how often the 4 s wait ends optimistic.
4. **Refresh.** After 70 minutes, any command.
   - **Pass:** one `refresh_token` grant 200, then success.
5. **Kill switch.** Empty the allowlist.
   - **Pass:** the next command fails (logs show `INSUFFICIENT_PERMISSIONS`); no command doc.
     Note what Alexa actually says; Amazon does not document the spoken text.
   - Restore the allowlist.
6. **Unlink in the app.**
   - **Pass:**
     - the next command fails;
     - the refresh record shows `active: false`;
     - Alexa asks to re-link within a refresh cycle.
7. **Re-link**, then disable the skill in the Alexa app. Expected v1 gap: the app shows Linked
   until Unlink.

**Abort** on any 5xx loop, a command to a non-bench controller, or a write outside the bench uid.
Then use the kill switch and roll back.

## 9. Game Day and the bridge

- **Linking** touches neither Game Day nor the bridge.
- **Voice commands** are consumers of the existing relay path, exactly like app commands: the same
  queue, document shape, eligibility rule and fail-fast trigger.
- **No change** to bridge firmware, bridge registry, bridge rules, pairing, or any Game Day
  function or data. Voice no longer reads Game Day designs.

## 10. App side

- **No build for Phase 2 or the bench.**
- **Next build, not blocking:**
  - Android 11+ `<queries>` / iOS `LSApplicationQueriesSchemes` for the Link button;
  - show a launch failure;
  - optional Cancel in Pending (the sweep now clears it within a day);
  - `skillId` changes only if a new skill is created;
  - Google's placeholder URL.

## 11. Blocked on the owner

- **B1:** Account Linking page values:
  - Client Authentication Scheme (either works now);
  - the vendor id;
  - the Authorization and Access Token URIs.
- **B2:** skill type (Smart Home?), current endpoint ARN, and what code runs there.
- **B3:** a test Alexa developer account + a phone with the Alexa app signed into it.
- **B4:** whether the skill is live or Development-only. New links are now gated by the kill
  switch either way.
- **B5:** the go for each phase, plus the `.env`, `config/voice_control`, AWS and console steps.

## 12. Sources

- Amazon, Account Linking Schemas (redirect URI format, `accessTokenScheme`):
  https://developer.amazon.com/en-US/docs/alexa/smapi/account-linking-schemas.html
- Amazon, Configure an Authorization Code Grant:
  https://developer.amazon.com/en-US/docs/alexa/account-linking/configure-authorization-code-grant.html
- Amazon, Alexa.ErrorResponse (EXPIRED vs INVALID_AUTHORIZATION_CREDENTIAL,
  INSUFFICIENT_PERMISSIONS; messages are for logging):
  https://developer.amazon.com/en-US/docs/alexa/device-apis/alexa-errorresponse.html
- Amazon, Alexa.Discovery (endpoint fields; Discover error types):
  https://developer.amazon.com/en-US/docs/alexa/device-apis/alexa-discovery.html
- Amazon, Use Skill Events:
  https://developer.amazon.com/en-US/docs/alexa/smapi/skill-events-in-alexa-skills.html
- Google Home Developers, OAuth 2.0 authorization:
  https://developers.home.google.com/cloud-to-cloud/project/authorization
- RFC 6749 §2.3.1, §4.1.3, §5.1, §5.2.
