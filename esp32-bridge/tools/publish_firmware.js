#!/usr/bin/env node
// esp32-bridge/tools/publish_firmware.js
//
// Publishes a SIGNED bridge image to an OTA channel (bridge firmware 1.3.0, #4).
// DRY-RUN BY DEFAULT; nothing is uploaded or written until --confirm.
//
//   1. Re-checks the manifest from sign_firmware.py against the .bin (size +
//      SHA-256). It does not re-verify the signature (no key here) — run
//      `sign_firmware.py verify` first; the bridge refuses a bad signature
//      anyway.
//   2. Uploads the image to Storage  bridge-firmware/<version>/firmware-<sha8>.bin
//      (no download token; storage.rules lets only bridge identities read it).
//   3. Writes Firestore bridge_firmware/<channel>:
//        { version, board, size, sha256, sig, url, devices, minVersion, enabled,
//          publishedAt, publishedBy }
//      devices is REQUIRED and explicit: a comma list of deviceIds, or "*" for
//      every bridge on the channel. Staged rollout = widen this list.
//
// Kill switch: --disable --channel=<c> --confirm sets enabled:false (bridges
// stop taking that manifest; already-installed bridges are unaffected).
//
// Usage:
//   node tools/publish_firmware.js --manifest=m.json --bin=firmware.bin \
//     --channel=beta --devices=A1B2C3D4E5F6 --bucket=<storage bucket> [--min-version=1.3.0] [--confirm]
//
// The bucket is DefaultFirebaseOptions' storageBucket (lib/firebase_options.dart).
// Emulators: FIRESTORE_EMULATOR_HOST / FIREBASE_STORAGE_EMULATOR_HOST.

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const admin = require("firebase-admin");

const DEFAULT_PROJECT = "icrt6menwsv2d8all8oijs021b06s5";
const CHANNELS = ["bench", "beta", "stable"];

function parseArgs(argv) {
  const a = { project: DEFAULT_PROJECT };
  for (const arg of argv.slice(2)) {
    const body = arg.replace(/^--/, "");
    const eq = body.indexOf("=");
    const k = eq < 0 ? body : body.slice(0, eq);
    a[k.replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = eq < 0 ? true : body.slice(eq + 1);
  }
  return a;
}

const log = (...m) => console.log(...m);
const die = (msg, code = 2) => { console.error(`ABORT: ${msg}`); process.exit(code); };

async function main() {
  const a = parseArgs(process.argv);
  if (!CHANNELS.includes(a.channel)) die(`--channel must be one of ${CHANNELS.join(", ")}`);
  const dry = !a.confirm;

  admin.initializeApp({
    credential: a.key ? admin.credential.cert(require(path.resolve(a.key))) : admin.credential.applicationDefault(),
    projectId: a.project,
    storageBucket: a.bucket,
  });
  const db = admin.firestore();
  const ref = db.doc(`bridge_firmware/${a.channel}`);

  log(dry ? "DRY RUN — nothing will change (add --confirm)" : "LIVE — changes will be written");

  if (a.disable) {
    log(`${dry ? "would set" : "setting"} bridge_firmware/${a.channel}.enabled = false`);
    if (!dry) await ref.set({ enabled: false, disabledAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return;
  }

  if (!a.manifest || !a.bin || !a.bucket) die("--manifest, --bin and --bucket are required");
  if (!a.devices) die('--devices is required: a comma list of deviceIds, or "*" for the whole channel');
  const devices = a.devices === "*" ? ["*"] : String(a.devices).split(",").map((d) => d.trim().toUpperCase());
  if (devices[0] !== "*" && !devices.every((d) => /^[0-9A-F]{12}$/.test(d))) die("each device must be 12 hex digits");

  const m = JSON.parse(fs.readFileSync(a.manifest, "utf8"));
  const blob = fs.readFileSync(a.bin);
  const sha = crypto.createHash("sha256").update(blob).digest("hex");
  if (blob.length !== m.size || sha !== String(m.sha256).toLowerCase()) die("the .bin does not match the manifest");
  if (!/^\d+\.\d+\.\d+$/.test(m.version) || !m.sig) die("manifest is missing version or sig");
  if (m.bench && a.channel !== "bench") die("this is a BENCH image; it may only go to the bench channel");
  if (!m.bench && a.channel === "bench") log("note: publishing a release image to the bench channel");

  const objectPath = `bridge-firmware/${m.version}/firmware-${sha.slice(0, 8)}.bin`;
  const url = `https://firebasestorage.googleapis.com/v0/b/${a.bucket}/o/${encodeURIComponent(objectPath)}?alt=media`;

  const current = (await ref.get()).data() || null;
  if (current) {
    log(`channel ${a.channel} now: version=${current.version} enabled=${current.enabled} devices=${JSON.stringify(current.devices)}`);
  } else {
    log(`channel ${a.channel} now: (no manifest)`);
  }

  const doc = {
    version: m.version,
    board: m.board || "esp32dev",
    size: m.size,
    sha256: sha,
    sig: m.sig,
    url,
    devices,
    minVersion: a.minVersion || "",
    enabled: true,
    publishedAt: admin.firestore.FieldValue.serverTimestamp(),
    publishedBy: os.userInfo().username,
  };
  log(`${dry ? "would upload" : "uploading"} gs://${a.bucket}/${objectPath} (${m.size} bytes)`);
  log(`${dry ? "would write" : "writing"} bridge_firmware/${a.channel}: ` +
      JSON.stringify({ ...doc, sig: `${m.sig.slice(0, 12)}…`, publishedAt: "(server time)" }, null, 2));
  if (dry) return;

  const file = admin.storage().bucket().file(objectPath);
  await file.save(blob, { resumable: false, contentType: "application/octet-stream",
                          metadata: { cacheControl: "private, max-age=0" } });
  await ref.set(doc);
  log("published");
}

main().catch((e) => {
  console.error("ERROR", e.code || "", e.message);
  process.exit(1);
});
