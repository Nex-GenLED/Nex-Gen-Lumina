#!/usr/bin/env node
// esp32-bridge/tools/fleet_readiness.js
//
// READ-ONLY. Modifies nothing. One table of every bridge the registry knows,
// plus the gates of the bridge-firmware 1.3.0 rollout:
//   • which bridges still run < 1.3.0 (need the one USB visit),
//   • which identity each signs in as (legacy / per_bridge / legacy_fallback)
//     and whether its user's bridge_email agrees,
//   • OTA state (no_ota_partition = reflashed without the new partition table),
//   • last reset reason / watchdog phase (what #109 looks like in the field),
//   • users with more than one live bridge (bridge_email is single-valued),
//   • every distinct users.bridge_email value (must be only the shared account
//     or per-bridge accounts before the phase-R3 rules tighten the email check).
// UIDs are shown as 6-character prefixes only.
//
// Usage: node tools/fleet_readiness.js [--project=<id>] [--key=<sa.json>] [--json]

"use strict";

const path = require("path");
const admin = require("firebase-admin");

const SHARED_EMAIL = "bridge@nex-genled.com";
const PER_BRIDGE_EMAIL = /^bridge-[0-9a-f]{12}@bridges\.nex-genled\.com$/;
const DAY = 864e5;

function parseArgs(argv) {
  const a = { project: "icrt6menwsv2d8all8oijs021b06s5" };
  for (const arg of argv.slice(2)) {
    const body = arg.replace(/^--/, "");
    const eq = body.indexOf("=");
    a[eq < 0 ? body : body.slice(0, eq)] = eq < 0 ? true : body.slice(eq + 1);
  }
  return a;
}
const mask = (u) => (u ? `${String(u).slice(0, 6)}…` : "-");
const age = (ms) => (ms == null ? "never" : ms < 36e5 ? `${Math.round(ms / 6e4)}m` : ms < DAY ? `${(ms / 36e5).toFixed(1)}h` : `${(ms / DAY).toFixed(1)}d`);
const emailKind = (e) => (!e ? "unset" : e.toLowerCase() === SHARED_EMAIL ? "shared" : PER_BRIDGE_EMAIL.test(e.toLowerCase()) ? "per-bridge" : "OTHER");
const cmpVer = (a, b) => {
  const pa = String(a || "0").split(".").map(Number), pb = String(b).split(".").map(Number);
  for (let i = 0; i < 3; i++) if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) - (pb[i] || 0);
  return 0;
};

async function main() {
  const a = parseArgs(process.argv);
  admin.initializeApp({
    credential: a.key ? admin.credential.cert(require(path.resolve(a.key))) : admin.credential.applicationDefault(),
    projectId: a.project,
  });
  const db = admin.firestore();
  const now = Date.now();

  const reg = await db.collection("bridge_registry").get();
  const rows = [];
  const byUser = {};
  for (const d of reg.docs) {
    const x = d.data();
    const seenMs = x.lastSeen && x.lastSeen.toMillis ? now - x.lastSeen.toMillis() : null;
    const row = {
      device: d.id,
      fw: x.firmwareVersion || "?",
      authMode: x.authMode || (cmpVer(x.firmwareVersion, "1.3.0") < 0 ? "legacy(pre-1.3)" : "?"),
      bridgeEmail: emailKind(x.bridgeEmail),
      status: x.status || "?",
      user: x.pairedUid || "",
      seenMs,
      flash: x.flashSize || "?",
    };
    if (row.user) {
      const u = await db.doc(`users/${row.user}`).get();
      row.userBridgeEmail = u.exists ? emailKind(u.get("bridge_email")) : "NO-USER-DOC";
      // null = the registry doc does not say which account the bridge uses.
      row.userDelegatesThis = !x.bridgeEmail ? null :
        u.exists && (u.get("bridge_email") || "").toLowerCase() === x.bridgeEmail.toLowerCase();
      const hb = await db.doc(`users/${row.user}/bridge_status/current`).get();
      if (hb.exists) {
        row.hbAgeMs = now - hb.updateTime.toMillis();
        row.ota = hb.get("ota") || "";
        row.reset = hb.get("resetReason") || "";
        row.prevCause = hb.get("prevCause") || "";
        row.prevLoopPhase = hb.get("prevLoopPhase") || "";
        row.pollAgeS = hb.get("pollAgeS");
      }
      if (seenMs != null && seenMs < 30 * DAY) (byUser[row.user] = byUser[row.user] || []).push(d.id);
    }
    rows.push(row);
  }

  const users = await db.collection("users").select("bridge_email").get();
  const emailValues = {};
  users.forEach((u) => {
    const e = u.get("bridge_email");
    if (e) emailValues[emailKind(e)] = (emailValues[emailKind(e)] || 0) + 1;
  });

  const live = rows.filter((r) => r.seenMs != null && r.seenMs < 30 * DAY);
  const multi = Object.entries(byUser).filter(([, ds]) => ds.length > 1);
  const gates = {
    liveBridges30d: live.length,
    needUsbVisit: live.filter((r) => cmpVer(r.fw, "1.3.0") < 0).map((r) => r.device),
    notPerBridge: live.filter((r) => r.authMode !== "per_bridge").map((r) => `${r.device}:${r.authMode}`),
    userNotDelegatingToBridge: live.filter((r) => r.user && r.userDelegatesThis === false).map((r) => r.device),
    bridgeEmailUnknown: live.filter((r) => r.user && r.userDelegatesThis === null).map((r) => r.device),
    cannotOta: live.filter((r) => (r.ota || "").startsWith("no_ota_partition")).map((r) => r.device),
    usersWithMultipleLiveBridges: multi.map(([u, ds]) => `${mask(u)}:${ds.join("+")}`),
    usersBridgeEmailValues: emailValues,
  };
  gates.readyToDisableSharedAccount =
    gates.needUsbVisit.length === 0 && gates.notPerBridge.length === 0 &&
    gates.userNotDelegatingToBridge.length === 0 && gates.bridgeEmailUnknown.length === 0 &&
    (emailValues.OTHER || 0) === 0;

  if (a.json) {
    console.log(JSON.stringify({ at: new Date(now).toISOString(), rows: rows.map((r) => ({ ...r, user: mask(r.user) })), gates }, null, 2));
    return;
  }
  const pad = (s, n) => String(s ?? "").padEnd(n).slice(0, n);
  console.log(`bridge fleet ${new Date(now).toISOString()}  (${rows.length} registry docs)`);
  console.log([pad("device", 13), pad("fw", 7), pad("authMode", 16), pad("user", 8), pad("userEmail", 11), pad("seen", 7),
               pad("hb", 7), pad("ota", 22), pad("reset", 10), pad("prevCause/phase", 28)].join(" "));
  for (const r of rows.sort((x, y) => (x.seenMs ?? 9e15) - (y.seenMs ?? 9e15))) {
    console.log([pad(r.device, 13), pad(r.fw, 7), pad(r.authMode, 16), pad(mask(r.user), 8),
                 pad(r.userBridgeEmail || "-", 11), pad(age(r.seenMs), 7), pad(age(r.hbAgeMs), 7),
                 pad(r.ota, 22), pad(r.reset, 10), pad(r.prevCause ? `${r.prevCause}/${r.prevLoopPhase}` : "", 28)].join(" "));
  }
  console.log("\nGATES");
  console.log(JSON.stringify(gates, null, 2));
}

main().catch((e) => {
  console.error("ERROR", e.code || "", e.message);
  process.exit(1);
});
