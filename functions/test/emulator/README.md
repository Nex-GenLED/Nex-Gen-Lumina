# Emulator / rules integration tests

These tests are **NOT run by `npm test`** (jest is scoped to
`test/unit/**/*.test.js`). They require the Firebase emulator suite and extra
dev dependencies that are not installed in the default/offline sandbox:

- `@firebase/rules-unit-testing` (Firestore security-rules harness)
- `firebase-functions-test` (already a devDependency)
- A running **Firestore emulator** (`firebase emulators:start --only firestore`)
- Java (required by the emulator)

## Running

```bash
cd functions
npm i -D @firebase/rules-unit-testing ts-jest @types/jest
# point jest at the emulator suite (separate config or --testMatch):
firebase emulators:exec --only firestore \
  "npx jest --config jest.emulator.config.js"
```

You will also need a jest TypeScript transform (`ts-jest`) since these files are
`.ts`; the default `npm test` deliberately avoids one because the pure-logic
unit tests run against compiled JS in `lib/`.

### Tests that also need the Auth emulator

`healUserProfile.emulator.test.ts` looks users up in Firebase Auth, so it needs
the **Auth emulator** as well. The repo's `firebase.json` declares only the
Firestore emulator; rather than editing it, point the CLI at a config that
declares both (any directory, e.g. a scratch one):

```json
{ "emulators": { "firestore": { "port": 8080 }, "auth": { "port": 9099 }, "ui": { "enabled": false } } }
```

```bash
cd functions
firebase --config /path/to/that/firebase.json emulators:exec --only firestore,auth \
  --project lumina-fn-test \
  "npx jest --config jest.emulator.config.js --runInBand test/emulator/healUserProfile"
```

The test throws at load time if `FIREBASE_AUTH_EMULATOR_HOST` is unset, so a
Firestore-only run fails that one file loudly instead of silently talking to
production Auth.

## What they cover

- `schedulesRules.emulator.test.ts` — owner can read/write
  `/users/{uid}/schedules/{id}`; a DIFFERENT authenticated uid is DENIED
  (proves the parent-doc `|| request.auth != null` grant was NOT inherited);
  unauthenticated is denied; `config/schedules_subcollection` is readable by an
  authenticated user.
- `scheduleFunctions.emulator.test.ts` — `backfillSchedulesSubcollection`
  idempotency (run twice → identical subcollection state) and dryRun
  (writes nothing); `enforceScheduleLimits` trims the array and the
  subcollection consistently inside its transaction.
- `healUserProfile.emulator.test.ts` — the `users/{uid}` onCreate profile
  healer: a stub for an email user is healed with exactly the seven
  `UserModel.fromJson` keys (created_at = Auth creation time); a full profile
  is untouched; set keys are never overwritten; anonymous, `staff_*` and
  Auth-less uids are skipped; idempotent; a stub and a racing client skeleton
  converge in either order. Also the `assignReferralCode` gate: assigns for
  an email user, skips anonymous / `staff_*` / Auth-less uids without writing
  a `referral_codes` doc.
- `bridgeLeastPrivilegeRules.emulator.test.ts` — the shared bridge identity
  limited to what firmware 1.2 does. 100 raw REST requests (the firmware's own
  runQuery and PATCH-with-updateMask calls, sent with unsigned mock tokens),
  each run against the current rules AND the ruleset at
  `BRIDGE_RULES_BASELINE_REF` (read with `git show`; the old-rules half is
  skipped if git cannot produce it). Asserts every firmware operation is still
  allowed, the 39 ALLOW → DENY deltas are all the bridge identity, the pinned
  residuals stay allowed, and no owner / staff / installer / user-pairing /
  anonymous request changes.

### Dealer-tools suites (2026-11-17)

Need a firebase.json declaring the emulators each file uses (do not edit the
repo's): `firestore` for the rules and trigger/callable suites, `firestore` +
`storage` for the storage suite, `firestore` + `auth` for
createCustomerAccount. Run the storage suite with `--project` equal to the
project id the test uses (`GCLOUD_PROJECT`, default `demo-dealer-tools`):
Storage rules resolve `firestore.get()` against the CLI project.

- `dealerToolsRulesDiff.emulator.test.ts` — 16 personas × 61 requests run
  against `git show ${DEALER_TOOLS_BASELINE_REF:-0a364ce0}:firestore.rules`
  (byte-identical to production) and the working tree; asserts the delta set
  equals the item-tagged expected set exactly. `DIFF_EXPECT=none` asserts no
  deltas, `DIFF_ITEMS=1,2` limits expectations, `DIFF_OUT=<file>` writes both
  matrices as JSON.
- `dealerToolsRules.emulator.test.ts` — items 1-6 as named allow/deny cases,
  including the customers who lose sales_jobs, dealer_orders, payouts,
  pricing_defaults and material lists.
- `dealerToolsStorage.emulator.test.ts` — sales_jobs/** and sales/** storage
  rules: dealer scoping through the job doc, pre-save draft uploads, image
  type, 10 MB cap, signature immutability, wrap-up re-shoot.
- `createCustomerAccount.emulator.test.ts`, `notifyDay2Team.emulator.test.ts`,
  `onSalesJobStatusChanged.emulator.test.ts` — the callable auth gates, the
  sent markers and the dealer SMS toggle. Senders are jest mocks, `resend` and
  `twilio` are tripwire modules that throw if constructed, FCM is injected:
  nothing leaves the machine.
