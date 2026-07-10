/**
 * Jest config for the EMULATOR integration tests (test/emulator/*.emulator.test.ts).
 *
 * Requires a running Firestore emulator — driven via:
 *   firebase emulators:exec --only firestore "npm run test:emulator"
 *
 * Separate from jest.config.js (the pure-JS unit suite) because these are
 * TypeScript, need a ts-jest transform, and hit real Firestore/rules through
 * the emulator. Run in-band so the two suites don't race the shared emulator.
 */
module.exports = {
  testEnvironment: "node",
  testMatch: ["**/test/emulator/**/*.emulator.test.ts"],
  transform: {
    "^.+\\.ts$": [
      "ts-jest",
      {
        tsconfig: {
          esModuleInterop: true,
          strict: true,
          noUnusedLocals: false,
          skipLibCheck: true,
          target: "es2022",
          module: "commonjs",
        },
      },
    ],
  },
};
