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
