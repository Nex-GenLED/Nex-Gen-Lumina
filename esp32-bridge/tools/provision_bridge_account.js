#!/usr/bin/env node
// esp32-bridge/tools/provision_bridge_account.js
//
// Per-bridge credential, server side (bridge firmware 1.3.0, #5).
// DRY-RUN BY DEFAULT: prints what it would do and changes nothing until
// --confirm. Touches exactly ONE bridge (--device) and at most ONE user (the
// registry doc's pairedUid). Never deletes anything.
//
// What it does, in order:
//   1. Reads /bridge_registry/{device} (status, pairedUid, firmware, authMode).
//   2. Ensures the Firebase Auth account for this bridge:
//        uid   bridge_<DEVICEID>                      (Admin-only; the rules anchor)
//        email bridge-<deviceid>@bridges.nex-genled.com
//      Refuses if the email already belongs to a different uid (a squatter —
//      investigate by hand). An existing account keeps its password unless
//      --reset-password (the bridge's stored password then stops working
//      until it is re-provisioned over serial).
//   3. --emit-credential: prints {"uid","email","password"} as ONE JSON line
//      on stdout for tools/provision_bridge_serial.py. Refuses when stdout is
//      a terminal, so the password is never shown on screen or in scrollback.
//      Everything else goes to stderr.
//   4. --flip-user: points the paired user's bridge_email at this bridge's
//      own email. Refused if bridge_email holds anything other than the
//      shared account or this bridge's email, or if the user has ANOTHER
//      registry doc seen in the last 30 days (a second live bridge on the
//      shared account would lose access — bridge_email is single-valued).
//      --revert-user puts the shared account back.
//
// Usage (ADC or a service-account key; --project defaults to production):
//   node tools/provision_bridge_account.js --device=A1B2C3D4E5F6
//   node tools/provision_bridge_account.js --device=A1B2C3D4E5F6 --confirm --emit-credential \
//     | python tools/provision_bridge_serial.py --port COM9
//   node tools/provision_bridge_account.js --device=A1B2C3D4E5F6 --flip-user --confirm
//
// Emulators: set FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST
// (the Admin SDK honours both) and pass --project=<emulator project>.

"use strict";

const crypto = require("crypto");
const path = require("path");
const admin = require("firebase-admin");

const SHARED_EMAIL = "bridge@nex-genled.com";
const DEFAULT_PROJECT = "icrt6menwsv2d8all8oijs021b06s5";
const DEFAULT_DOMAIN = "bridges.nex-genled.com";
const LIVE_WINDOW_MS = 30 * 24 * 3600 * 1000;

function parseArgs(argv) {
  const a = { project: DEFAULT_PROJECT, domain: DEFAULT_DOMAIN };
  for (const arg of argv.slice(2)) {
    const body = arg.replace(/^--/, "");
    const eq = body.indexOf("=");
    const k = eq < 0 ? body : body.slice(0, eq);
    a[k.replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = eq < 0 ? true : body.slice(eq + 1);
  }
  return a;
}

const log = (...m) => console.error(...m);
const mask = (uid) => (uid ? `${String(uid).slice(0, 6)}…` : "(none)");

function ageOf(ts) {
  const ms = ts && typeof ts.toMillis === "function" ? Date.now() - ts.toMillis() : null;
  if (ms === null) return { ms: null, text: "never" };
  const m = Math.round(ms / 60000);
  return { ms, text: m < 60 ? `${m}m` : m < 1440 ? `${(m / 60).toFixed(1)}h` : `${(m / 1440).toFixed(1)}d` };
}

async function main() {
  const a = parseArgs(process.argv);
  const device = String(a.device || "").toUpperCase();
  if (!/^[0-9A-F]{12}$/.test(device)) {
    log("--device=<12 hex digits> is required (esptool read-mac, colons removed, uppercase)");
    process.exit(2);
  }
  if (a.emitCredential && process.stdout.isTTY) {
    log("refusing --emit-credential to a terminal: pipe it into provision_bridge_serial.py");
    process.exit(2);
  }
  if (a.flipUser && a.revertUser) {
    log("--flip-user and --revert-user are mutually exclusive");
    process.exit(2);
  }

  admin.initializeApp({
    credential: a.key ? admin.credential.cert(require(path.resolve(a.key))) : admin.credential.applicationDefault(),
    projectId: a.project,
  });
  const db = admin.firestore();
  const auth = admin.auth();

  const uid = `bridge_${device}`;
  const email = `bridge-${device.toLowerCase()}@${a.domain}`;
  const dry = !a.confirm;
  log(`${dry ? "DRY RUN — nothing will change (add --confirm)" : "LIVE — changes will be written"}`);
  log(`project ${a.project} · device ${device} · account ${uid} <${email}>`);

  // 1. Registry
  const regSnap = await db.doc(`bridge_registry/${device}`).get();
  const reg = regSnap.exists ? regSnap.data() : null;
  if (reg) {
    log(`registry: status=${reg.status} pairedUid=${mask(reg.pairedUid)} fw=${reg.firmwareVersion} ` +
        `authMode=${reg.authMode || "(pre-1.3)"} lastSeen=${ageOf(reg.lastSeen).text} ago`);
  } else {
    log("registry: no document (a new unit registers itself on first boot)");
  }

  // 2. Auth account
  let user = null;
  try { user = await auth.getUser(uid); } catch (e) { if (e.code !== "auth/user-not-found") throw e; }
  let password = null;
  if (user) {
    if ((user.email || "").toLowerCase() !== email) {
      log(`ABORT: ${uid} exists with email ${user.email}, expected ${email}`);
      process.exit(3);
    }
    log(`auth: ${uid} exists (disabled=${user.disabled})`);
    if (a.emitCredential || a.resetPassword) {
      if (!a.resetPassword) {
        log("ABORT: account exists; its password cannot be read back. Pass --reset-password to " +
            "issue a new one (the bridge's stored password stops working until re-provisioned).");
        process.exit(3);
      }
      password = crypto.randomBytes(24).toString("base64url");
      log(`auth: ${dry ? "would reset" : "resetting"} password`);
      if (!dry) await auth.updateUser(uid, { password });
    }
  } else {
    let squatter = null;
    try { squatter = await auth.getUserByEmail(email); } catch (e) { if (e.code !== "auth/user-not-found") throw e; }
    if (squatter) {
      log(`ABORT: ${email} already belongs to uid ${mask(squatter.uid)} (not ${uid}). ` +
          "Something claimed this bridge's email — investigate by hand; do not provision.");
      process.exit(3);
    }
    password = crypto.randomBytes(24).toString("base64url");
    log(`auth: ${dry ? "would create" : "creating"} ${uid}`);
    if (!dry) {
      await auth.createUser({ uid, email, password, emailVerified: false, disabled: false,
                              displayName: `Lumina Bridge ${device}` });
    }
  }

  // 3. Credential for the serial tool
  if (a.emitCredential) {
    if (dry) {
      log("--emit-credential ignored in a dry run (nothing was created)");
    } else {
      process.stdout.write(JSON.stringify({ uid, email, password }) + "\n");
      log("credential written to stdout (pipe)");
    }
  }

  // 4. Delegation on the paired user
  if (a.flipUser || a.revertUser) {
    const owner = reg && reg.pairedUid;
    if (!owner) {
      log("ABORT: registry has no pairedUid — pair the bridge first; the app then records its email itself");
      process.exit(4);
    }
    const userRef = db.doc(`users/${owner}`);
    const current = ((await userRef.get()).get("bridge_email") || "").toLowerCase();
    log(`user ${mask(owner)}: bridge_email is ${current === SHARED_EMAIL ? "the SHARED account" : current === email ? "THIS bridge's account" : `"${current || "(unset)"}"`}`);

    if (a.flipUser) {
      if (current === email) {
        log("already delegated to this bridge — nothing to do");
      } else if (current !== SHARED_EMAIL) {
        log("ABORT: bridge_email is neither the shared account nor this bridge; not overwriting it");
        process.exit(4);
      } else {
        const others = await db.collection("bridge_registry").where("pairedUid", "==", owner).get();
        const liveOthers = others.docs.filter((d) => d.id !== device &&
          (ageOf(d.get("lastSeen")).ms ?? Infinity) < LIVE_WINDOW_MS);
        if (liveOthers.length) {
          log(`ABORT: this user has ${liveOthers.length} other bridge(s) seen in the last 30 days ` +
              `(${liveOthers.map((d) => d.id).join(", ")}). bridge_email is single-valued; reflash ` +
              "those first or decide by hand.");
          process.exit(4);
        }
        log(`${dry ? "would set" : "setting"} bridge_email -> ${email}`);
        if (!dry) await userRef.update({ bridge_email: email });
        log("revert with: --revert-user --confirm");
      }
    } else {
      if (current !== email) {
        log(`ABORT: bridge_email is not this bridge's account; refusing to revert`);
        process.exit(4);
      }
      log(`${dry ? "would set" : "setting"} bridge_email -> ${SHARED_EMAIL}`);
      if (!dry) await userRef.update({ bridge_email: SHARED_EMAIL });
    }
  }
  log("done");
}

main().catch((e) => {
  log("ERROR", e.code || "", e.message);
  process.exit(1);
});
