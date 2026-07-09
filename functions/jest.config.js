/**
 * Jest config for Cloud Functions.
 *
 * Scoped to test/unit/**.test.js — pure-logic tests that run against the
 * tsc-compiled output in lib/ with NO emulator, NO firebase-admin IO, and NO
 * TypeScript transform (none is installed). Run `npm run build` first.
 *
 * Emulator / rules integration tests live under test/emulator/ (TypeScript)
 * and are intentionally NOT matched here — they require the Firestore emulator
 * and @firebase/rules-unit-testing, neither of which runs in CI-less sandboxes.
 */
module.exports = {
  testEnvironment: "node",
  testMatch: ["**/test/unit/**/*.test.js"],
};
