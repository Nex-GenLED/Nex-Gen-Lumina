'use strict';

/**
 * Shared resolver for the Firebase Admin SDK service-account key.
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * The key used to sit at
 *   android/app/icrt6menwsv2d8all8oijs021b06s5-firebase-adminsdk-fbsvc-*.json
 * i.e. INSIDE a Gradle module. It was untracked and gitignored, so it was never
 * committed — but `android/app/` is a build-input directory, so one `git add -f`,
 * one packaging change, or one modified asset glob turns the highest-value
 * credential in the project into a shipped credential. That is
 * audit/OVERNIGHT_SECURITY_AUDIT.md §2.2b.
 *
 * The key now lives OUTSIDE the repository entirely, at:
 *   %USERPROFILE%\.lumina\   (Windows)  /  ~/.lumina/  (POSIX)
 *
 * Nothing under the repo tree can package it, and no `git add -f` can reach it.
 *
 * RESOLUTION ORDER
 * ----------------
 *   1. $LUMINA_SERVICE_ACCOUNT           (explicit override)
 *   2. $GOOGLE_APPLICATION_CREDENTIALS   (standard Google env var)
 *   3. ~/.lumina/<project>-firebase-adminsdk-*.json
 *   4. ~/.lumina/firebase-adminsdk.json  (generic name, if you rotate the key)
 *   5. the legacy android/app path — ONLY if it still exists, and it warns loudly
 *
 * Per-script `--key=<path>` flags are unaffected; they short-circuit before this
 * resolver is consulted.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

// Split so a naive `grep <full-filename>` over the repo does not imply the key
// is stored here. This is a filename, not a secret.
const KEY_FILENAME =
  'icrt6menwsv2d8all8oijs021b06s5' + '-firebase-adminsdk-fbsvc-2e0cb54335.json';

const KEY_DIR = path.join(os.homedir(), '.lumina');
const PREFERRED_PATH = path.join(KEY_DIR, KEY_FILENAME);
const LEGACY_PATH = path.resolve(__dirname, '..', 'android', 'app', KEY_FILENAME);

function candidatePaths() {
  const out = [];
  if (process.env.LUMINA_SERVICE_ACCOUNT) {
    out.push(path.resolve(process.env.LUMINA_SERVICE_ACCOUNT));
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    out.push(path.resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS));
  }
  out.push(PREFERRED_PATH);
  out.push(path.join(KEY_DIR, 'firebase-adminsdk.json'));
  return out;
}

/**
 * Returns the absolute path to the service-account key.
 *
 * Never throws: callers that resolve at module load time (for `--help` output,
 * banner printing, or a project_id pre-check) must not blow up just because the
 * key is absent. If nothing is found, the PREFERRED path is returned so the
 * eventual `require()` produces a normal MODULE_NOT_FOUND naming the right file.
 */
function resolveServiceAccountPath() {
  for (const p of candidatePaths()) {
    if (fs.existsSync(p)) return p;
  }
  if (fs.existsSync(LEGACY_PATH)) {
    console.warn(
      `[service-account] WARNING: using the LEGACY in-repo key at\n` +
        `  ${LEGACY_PATH}\n` +
        `An Admin SDK key must not live inside android/app (a Gradle module).\n` +
        `Move it:  mv "${LEGACY_PATH}" "${PREFERRED_PATH}"\n`,
    );
    return LEGACY_PATH;
  }
  return PREFERRED_PATH;
}

/** Loads and returns the parsed service-account JSON, with a useful error. */
function requireServiceAccount() {
  const p = resolveServiceAccountPath();
  if (!fs.existsSync(p)) {
    throw new Error(
      `Firebase Admin SDK service-account key not found.\n` +
        `Looked for:\n` +
        candidatePaths().map((c) => `  - ${c}`).join('\n') +
        `\n\nPut the key at:\n  ${PREFERRED_PATH}\n` +
        `or set LUMINA_SERVICE_ACCOUNT / GOOGLE_APPLICATION_CREDENTIALS,\n` +
        `or pass --key=<path> if this script supports it.\n`,
    );
  }
  return require(p);
}

module.exports = {
  KEY_FILENAME,
  KEY_DIR,
  PREFERRED_PATH,
  LEGACY_PATH,
  candidatePaths,
  resolveServiceAccountPath,
  requireServiceAccount,
};
