# Voice Integration — Launch Checklist (B-4 GO/NO-GO)

Branch: `feat/voice-canonical-commands`. Scope: Google Smart Home + Alexa Smart
Home fulfillment routed through the canonical `intentCore` enqueuer. This
document is the launch gate + operational runbook. Update the **Results** slots
as production checks are run.

---

## 1. GO/NO-GO table (verified read-only at B-4)

| # | Gate | Verdict | Evidence |
|---|------|---------|----------|
| 1 | `voice_control.enabled` defensive-false, checked first on every Google **and** Alexa directive | ✅ PASS | Reader `functions/src/voice/intentCore.ts:103` (missing/non-bool/read-error → false). Checked first: Google `googleSmartHome.ts:50` (SYNC), `:81` (QUERY), `:128` (EXECUTE); Alexa `alexaSmartHome.ts:271` (all directives, after auth); enqueue `intentCore.ts:388`. |
| 2 | Single canonical enqueue shape; zero `power`/`brightness`/`scene` writers; legacy-absent guard present | ✅ PASS | Only writers: `intentCore.ts:444-458` (voice) and `applySyncPattern.ts:241/425` (neighborhood/game-day) — both RemoteCommand shape. `index.js:1136-1142` is the cleanup *delete*, not a writer. Legacy `executeGoogleCommand` deleted in B-3a. Guard test: `test/voice/googleSmartHome.test.ts` "no legacy command shape…". |
| 3 | #84: every voice-written payload is a String | ✅ PASS | `intentCore.ts:450` `payload: payloadString, // ALWAYS a string (#84)`. Asserted `typeof … === "string"` in every EXECUTE test (google/alexa/intentCore). |
| 4 | Scene fixture-parity: TS ports == Dart `toWledPayload` | ✅ PASS | `test/voice/intentCore.test.ts:220` custom, `:254` library, `:275` system, `:288` Game Day (verbatim). |
| 5 | `awaitOutcome` hard 4s cap + listener cleanup on all paths | ✅ PASS | `intentCore.ts:477` (`maxWaitMs = 4000`), `:484-500` (`finish → cleanup`, `settled` double-resolve guard, timer + unsubscribe cleared on confirmed/failed/timeout). |
| 6 | Alexa JWT verify (HS256, `node:crypto`) matches `alexaToken` signer; refresh re-issues new format (non-stranding); flag-off non-unlinking on both platforms | ✅ PASS | Signer `index.js:841` + `:899` (`signAlexaJwt`); verifier `alexaSmartHome.ts` via `alexaJwt.ts` `verifyAlexaJwt`. Refresh token opaque/format-independent (`index.js:849/:852`), access token re-minted from `userId` on refresh (`:888`→`signAlexaJwt`). Flag-off: Google `deviceOffline` (`googleSmartHome.ts`), Alexa `ENDPOINT_UNREACHABLE` (`alexaSmartHome.ts`); bad token → `INVALID_AUTHORIZATION_CREDENTIAL` (triggers refresh, not unlink). |
| 7 | OAuth internals untouched (`alexaAuth`/`alexaToken`/`googleAuth`/`googleToken` external contract) | ✅ PASS | `git diff ca6cc13..HEAD -- functions/index.js`: only the require block, `alexaToken`'s two access-token *format* lines, the new `alexaSmartHome` export, and the B-3a google rewire changed. No hunk touches `alexaAuth`/`googleAuth`/`googleToken`/`generateAlexaAuthCode`/`alexaUnlink`. `alexaToken` response fields + refresh rotation unchanged. |
| 8 | Deploy build tsc 0, no test artifacts in `lib/`, suite green, `node --check` | ✅ PASS | `tsc` exit 0; `lib/**/*.test.js` empty; **36/36** node:test; `node --check index.js` OK. |

**VERDICT: GO** (all 8 gates pass). Remaining items below are deployment /
console configuration, not code gates.

---

## 2. Production data hygiene — legacy command shapes

Before/after deploy, confirm no legacy-shape command docs are being written or
are stranded in queues. Run in the Firebase console (or via a service-account
script). `commands` is a subcollection, so use **collection-group** queries:

```
// A. Any Google-origin legacy docs (the old executeGoogleCommand path):
collectionGroup("commands").where("source", "==", "google_home")

// B. Any doc with a legacy command type:
collectionGroup("commands").where("type", "in", ["power", "brightness", "scene"])
```

**Results slot (fill in):**
- Query A hits: `____` (expected 0 after B-3a deploy)
- Query B hits: `____` (expected 0)
- Date run / operator: `____`

### Cleanup script (only if hits found) — DRY-RUN FIRST

`scripts/cleanup_legacy_voice_commands.js` (spec):

```js
// Usage: node scripts/cleanup_legacy_voice_commands.js [--apply]
// Default is DRY-RUN: prints matches, deletes nothing.
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
const APPLY = process.argv.includes("--apply");

(async () => {
  const snap = await db.collectionGroup("commands")
    .where("type", "in", ["power", "brightness", "scene"]).get();
  console.log(`${snap.size} legacy-shape command docs`);
  for (const doc of snap.docs) {
    console.log(`${APPLY ? "DELETE" : "DRY"} ${doc.ref.path} type=${doc.data().type}`);
    if (APPLY) await doc.ref.delete();
  }
  // Legacy docs are already inert (executeWledCommand skips empty webhookUrl;
  // the bridge ignores controllerId:"primary"), so deletion is safe cleanup,
  // not a behavior change. TTL cleanup would drain them within 7 days anyway.
})().then(() => process.exit(0));
```

Run dry-run, review the printed paths, THEN re-run with `--apply`.

---

## 3. Google Home (Action console)

- [ ] **Smart Home Action** exists (or create net-new) in the Actions on Google / Google Home console for project `icrt6menwsv2d8all8oijs021b06s5`.
- [ ] **Fulfillment URL** = deployed `googleSmartHome` function URL
      (`https://us-central1-<project>.cloudfunctions.net/googleSmartHome`).
- [ ] **Account linking**: authorization URL = `googleAuth`, token URL = `googleToken`, client id/secret = `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` from `.env` (unchanged by voice work).
- [ ] Re-test account linking end-to-end (link → SYNC returns devices with continuity: primary = `lumina-main`).
- [ ] Test utterances: "turn on/off <house>", "set <house> to 50%", "activate <scene>".
- [ ] **Certification** submission: complete the Smart Home test suite, submit for review, address findings.

---

## 4. Alexa (Smart Home skill) — **AWS TRANSPORT DECISION**

**Build-time finding: Alexa Smart Home skills do NOT support a direct-HTTPS
endpoint.** Unlike custom (interaction-model) skills — which accept an HTTPS
endpoint — a Smart Home skill's *default endpoint* must be an **AWS Lambda ARN**
(`arn:aws:lambda:…`). Amazon invokes that Lambda with the directive JSON. Our
`alexaSmartHome` is a Cloud Functions `onRequest` (HTTPS), so a **thin
Lambda→HTTPS shim is required**.

### Lambda shim spec (~30 lines, Node 20, no deps)

```js
// AWS Lambda "lumina-alexa-shim" — forwards Alexa Smart Home directives to the
// alexaSmartHome Cloud Function and returns its JSON envelope verbatim.
// Env: FULFILLMENT_URL = https://us-central1-<project>.cloudfunctions.net/alexaSmartHome
exports.handler = async (event) => {
  const url = process.env.FULFILLMENT_URL;
  const res = await fetch(url, {                       // Node 20 global fetch
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(event),                       // event IS the directive
  });
  if (!res.ok) {
    // Return a well-formed Alexa ErrorResponse so Amazon never sees a bare 5xx.
    const h = event?.directive?.header || {};
    return {
      event: {
        header: { namespace: "Alexa", name: "ErrorResponse",
          messageId: h.messageId || "err", correlationToken: h.correlationToken,
          payloadVersion: "3" },
        payload: { type: "INTERNAL_ERROR", message: "fulfillment unreachable" },
      },
    };
  }
  return await res.json();  // alexaSmartHome already returns the Alexa envelope
};
```

Notes: the shim adds ~50-150ms; keep it inside the 4s `awaitOutcome` budget.
The `alexaSmartHome` handler is transport-agnostic — it reads `req.body` as the
directive, which is exactly `event` here. No handler change needed if we later
move fully to Lambda.

### Alexa skill setup

- [ ] Create a **net-new Smart Home skill** (Alexa has account-linking only today; no skill consumed the token).
- [ ] Endpoint = the `lumina-alexa-shim` Lambda ARN (per region as required by Amazon: NA/EU/FE).
- [ ] **Account linking**: authorization URI = `alexaAuth`, access-token URI = `alexaToken`, client id/secret = `ALEXA_CLIENT_ID`/`ALEXA_CLIENT_SECRET`.
- [ ] **Set `ALEXA_JWT_SECRET`** in `functions/.env` to a **distinct, high-entropy value** (do NOT reuse `ALEXA_CLIENT_SECRET`; the fallback exists only so a forgotten var doesn't break signing). Redeploy functions after setting.
- [ ] Re-link a test account (Amazon exchanges code → `alexaToken` now issues the HS256 JWT).
- [ ] Discovery returns endpoints; test PowerController / BrightnessController / SceneController utterances.
- [ ] **Certification**: run Amazon's Smart Home validation, submit, address findings.

---

## 5. Staged rollout (both transports)

The flag reader (`intentCore.readVoiceControlEnabled`) supports isolation and
ramp via `config/voice_control`:

```jsonc
{
  "enabled": false,                 // global off
  "allowlistUids": ["<FOUNDER_UID>"], // always-on for these uids, even when off
  "rolloutPercent": 0               // 0-100; stable per-uid bucket when enabled
}
```

Precedence: allowlist → `enabled!==true` off → no `rolloutPercent` = fully on →
`0` off / `100` on → stable-hash bucket. Missing/garbage config → **false**.

Rollout order:

1. [ ] **Deploy functions flag-OFF** (`{enabled:false}`). No user sees voice; handlers return the non-unlinking flag-off responses.
2. [ ] **Founder isolation**: `{enabled:false, allowlistUids:["<FOUNDER_UID>"]}`. Only the founder account resolves enabled.
3. [ ] **Bench in BOTH transports** on the founder account:
   - **Webhook Mode** (DIY, DDNS): directive → command doc → `executeWledCommand` POSTs to the webhook. Fast, synchronous-ish.
   - **Bridge Mode** (dealer default): directive → command doc → ESP32 **polls** Firestore → executes on LAN. ⚠️ **The real UX unknown is Bridge poll latency vs the 4s `awaitOutcome` optimistic window.** If the bridge poll interval + round-trip exceeds ~4s, control directives resolve `optimistic` (spoken success) *before* the light physically changes. Measure actual bridge round-trip; if p50 > 4s, consider (a) shortening the bridge poll interval, or (b) raising the optimistic cap for Bridge-Mode users (max ~7s to stay under the ~8s platform ceiling).
   - **Results slot:** Webhook p50/p95: `____` / `____`; Bridge p50/p95: `____` / `____`; optimistic-rate: `____`.
4. [ ] **Percentage ramp**: `{enabled:true, rolloutPercent:5}` → 10 → 25 → 50 → 100, watching command-failure/optimistic metrics between steps.
5. [ ] **Certification** submitted + approved on both platforms (can run in parallel with ramp on allowlisted internal accounts).
6. [ ] **Public**: `{enabled:true}` (no `rolloutPercent`), skills published.

---

## 6. Pre-deploy env checklist

- [ ] `ALEXA_JWT_SECRET` set (distinct) in `functions/.env`.
- [ ] `GOOGLE_CLIENT_ID/SECRET`, `ALEXA_CLIENT_ID/SECRET` present (unchanged).
- [ ] `firebase deploy --only functions` (rebuilds `lib/` via `tsc`; the voice
      handlers require `./lib/voice/*`). Confirm `alexaSmartHome` + the rewired
      `googleSmartHome` deploy without prompting to delete unrelated functions.
