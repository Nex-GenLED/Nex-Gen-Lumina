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
