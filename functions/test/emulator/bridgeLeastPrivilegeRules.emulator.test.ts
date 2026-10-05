/**
 * Firestore security-rules matrix for the SHARED BRIDGE IDENTITY (least
 * privilege, 2026-10-04) — 100 requests, each evaluated against the NEW
 * rules (../firestore.rules) and the OLD rules (the release-head ruleset this
 * change was cut from, read with `git show`), so every behavioural delta is
 * listed and asserted rather than inferred.
 *
 * ⚠️ NOT run by `npm test` (jest is scoped to test/unit/**.test.js). Requires
 * a running Firestore emulator. See test/emulator/README.md.
 *
 * WHY RAW REST: firmware 1.2 (esp32-bridge/src/main.cpp) talks to Firestore
 * over the REST API — a runQuery for pending commands and PATCH-with-
 * updateMask upserts for everything it writes. The SDK would not reproduce
 * those requests exactly (a PATCH upsert on a missing doc is a CREATE; an
 * updateMask names fields whose values did not change). So every request
 * here is the literal HTTP call, sent to the emulator with an unsigned mock
 * ID token (the emulator does not verify signatures).
 *
 * The shared account's address is read from the rules file (the registry's
 * isBridge() literal) and the old ruleset from git, so neither is copied
 * into this file. All ids are synthetic; IPs are RFC 5737.
 *
 * Groups:
 *   A — every operation firmware 1.2 performs: ALLOWED before and after.
 *   B — what the shared credential could do beyond the firmware: the 39
 *       ALLOW → DENY deltas, plus 8 that were already denied.
 *   C — RESIDUAL, pinned on purpose: still ALLOWED, because all bridges
 *       share one account (rules cannot tell bridges apart) or because the
 *       grant is a generic `request.auth != null` arm any session holds.
 *   D — owner / staff / installer / user pairing / anonymous paths:
 *       identical before and after.
 */

import {
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { execFileSync } from "child_process";
import { readFileSync } from "fs";

const HOST = "127.0.0.1";
const PORT = 8080;
const BASE_URL = `http://${HOST}:${PORT}`;

const NEW_PROJECT = "lumina-rules-bridge-new";
const OLD_PROJECT = "lumina-rules-bridge-old";

// The release-head ruleset this change was cut from — byte-identical to the
// ruleset deployed when it was written. Override to diff against another ref.
const BASELINE_REF =
  process.env.BRIDGE_RULES_BASELINE_REF ??
  "5e09663b01a32fbe4adf844911cdb2d0e339e633";

const NEW_RULES = readFileSync("../firestore.rules", "utf8");
const OLD_RULES: string | null = (() => {
  try {
    return execFileSync("git", ["-C", "..", "show", `${BASELINE_REF}:firestore.rules`], {
      encoding: "utf8",
      maxBuffer: 16 * 1024 * 1024,
    });
  } catch {
    return null;
  }
})();

// The shared bridge account, read from the registry's isBridge() literal.
const SHARED_ADDRESS = (/function isBridge\(\)[\s\S]*?request\.auth\.token\.email == '([^']+)'/.exec(
  NEW_RULES,
) ?? [])[1];

// ── Synthetic fixture ──────────────────────────────────────────────────────

const U_A = "customer-a"; // paired to the shared account; the "own" account
const U_B = "customer-b"; // ALSO paired to the shared account (another bridge)
const U_C = "customer-c"; // no bridge at all
const U_D = "customer-d"; // bridge_email names some other identity
const U_E = "customer-e"; // paired, no heartbeat doc yet (fresh install)
const CORP = "corporate-admin"; // user_role admin → canReadUserData
const ATTACKER_UID = "attacker-uid";

const DEV_A = "AA00000000A1"; // paired to U_A
const DEV_B = "AA00000000B2"; // paired to U_B
const DEV_C = "AA00000000C3"; // unpaired
const DEV_D = "AA00000000D4"; // pairing requested by U_C
const DEV_E = "AA00000000E5"; // legacy doc: only status/pairedUid/lastSeen
const DEV_NEW = "AA00000000F6"; // does not exist yet

class Ts {
  constructor(readonly iso: string) {}
}
const ts = (iso: string) => new Ts(iso);
type Val = string | number | boolean | null | Ts | Val[] | { [k: string]: Val };
type Fields = Record<string, Val>;

const T0 = ts("2026-10-04T12:00:00Z");
const T1 = ts("2026-10-04T12:00:05Z");
const T2 = ts("2026-10-04T12:02:00Z");

const command = (status: string, extra: Fields = {}): Fields => ({
  status,
  type: "setState",
  controllerId: "ctl-1",
  controllerIp: "192.0.2.10",
  payload: '{"on":true,"bri":128}',
  createdAt: T0,
  expiresAt: T2,
  source: "app",
  ...extra,
});

const heartbeat = (extra: Fields = {}): Fields => ({
  uptime: 86400,
  ip: "192.0.2.20",
  commands: 12,
  errors: 0,
  version: "1.2",
  wifi: true,
  heap: 150000,
  ...extra,
});

/** registerBridgeInRegistry()'s 14 fields (main.cpp:1039-1067). */
const fullRegistration = (dev: string, pairedUid: string, extra: Fields = {}): Fields => ({
  deviceId: dev,
  deviceName: `Lumina-${dev.slice(8)}`,
  apName: `Lumina-${dev.slice(8)}`,
  bridgeEmail: SHARED_ADDRESS,
  ip: "192.0.2.21",
  status: pairedUid ? "paired" : "unpaired",
  pairedUid,
  pendingUid: "",
  firmwareVersion: "1.2",
  lastSeen: T1,
  rssi: -61,
  heap: 151000,
  freeHeap: 151000,
  flashSize: 4194304,
  ...extra,
});

/** updateRegistryHeartbeat()'s 7 fields (main.cpp:1122-1151). */
const registryBeat = (pairedUid: string, extra: Fields = {}): Fields => ({
  lastSeen: T1,
  ip: "192.0.2.22",
  rssi: -62,
  heap: 152000,
  freeHeap: 152000,
  status: pairedUid ? "paired" : "unpaired",
  pairedUid,
  ...extra,
});

const userDoc = (uid: string, extra: Fields = {}): Fields => ({
  owner_id: uid,
  id: uid,
  user_role: "residential",
  dealer_code: "D1",
  ...extra,
});

const SEED: Record<string, Fields> = {
  [`users/${U_A}`]: userDoc(U_A, { bridge_email: SHARED_ADDRESS, controller_ips: ["192.0.2.10"] }),
  [`users/${U_B}`]: userDoc(U_B, { bridge_email: SHARED_ADDRESS, controller_ips: ["192.0.2.30"] }),
  [`users/${U_C}`]: userDoc(U_C, { controller_ips: ["192.0.2.40"] }),
  [`users/${U_D}`]: userDoc(U_D, { bridge_email: "another-bridge-identity", controller_ips: ["192.0.2.50"] }),
  [`users/${U_E}`]: userDoc(U_E, { bridge_email: SHARED_ADDRESS, controller_ips: ["192.0.2.60"] }),
  [`users/${CORP}`]: userDoc(CORP, { user_role: "admin", dealer_code: "" }),

  [`users/${U_A}/commands/pending1`]: command("pending"),
  [`users/${U_A}/commands/executing1`]: command("executing"),
  [`users/${U_A}/commands/completed1`]: command("completed", { completedAt: T1, result: "{}" }),
  [`users/${U_A}/commands/failed1`]: command("failed", { completedAt: T0, error: "no_bridge_paired" }),
  [`users/${U_A}/commands/expired1`]: command("expired"),
  [`users/${U_A}/commands/ping1`]: { status: "pending", type: "ping", controllerIp: "", createdAt: T0 },
  [`users/${U_B}/commands/pending1`]: command("pending", { controllerIp: "192.0.2.30" }),
  [`users/${U_C}/commands/pending1`]: command("pending", { controllerIp: "192.0.2.40" }),
  [`users/${U_D}/commands/pending1`]: command("pending", { controllerIp: "192.0.2.50" }),

  [`users/${U_A}/bridge_status/current`]: heartbeat(),
  [`users/${U_A}/controllers/ctl-1`]: { name: "Front", ip: "192.0.2.10" },

  [`bridge_registry/${DEV_A}`]: fullRegistration(DEV_A, U_A, { lastSeen: T0 }),
  [`bridge_registry/${DEV_B}`]: fullRegistration(DEV_B, U_B, { lastSeen: T0 }),
  [`bridge_registry/${DEV_C}`]: fullRegistration(DEV_C, "", { lastSeen: T0 }),
  [`bridge_registry/${DEV_D}`]: fullRegistration(DEV_D, "", {
    lastSeen: T0,
    status: "pairing",
    pendingUid: U_C,
  }),
  [`bridge_registry/${DEV_E}`]: { status: "paired", pairedUid: U_A, lastSeen: T0 },
};

// ── Actors (unsigned mock ID tokens) ───────────────────────────────────────

type Actor = Record<string, unknown> | null;

const BRIDGE: Actor = {
  sub: "shared-bridge-account",
  email: SHARED_ADDRESS,
  firebase: { sign_in_provider: "password", identities: {} },
};
const OWNER_A: Actor = { sub: U_A };
const OWNER_B: Actor = { sub: U_B };
const USER_C: Actor = { sub: U_C };
const CORP_ADMIN: Actor = { sub: CORP };
const STRANGER: Actor = { sub: "stranger-uid" };
const ANON: Actor = { sub: "anon-session", firebase: { sign_in_provider: "anonymous", identities: {} } };
const INSTALLER_D1: Actor = { sub: "staff_installer_TESTPIN", role: "installer", dealerCode: "D1" };
const UNAUTH: Actor = null;

const b64url = (s: string) => Buffer.from(s).toString("base64url");

/** Same shape as @firebase/util createMockUserToken (alg none, empty sig). */
function mockToken(actor: Record<string, unknown>, projectId: string): string {
  const sub = actor.sub as string;
  const payload = {
    iss: `https://securetoken.google.com/${projectId}`,
    aud: projectId,
    iat: 0,
    exp: 3600,
    auth_time: 0,
    sub,
    user_id: sub,
    firebase: { sign_in_provider: "custom", identities: {} },
    ...actor,
  };
  return `${b64url(JSON.stringify({ alg: "none", type: "JWT" }))}.${b64url(JSON.stringify(payload))}.`;
}

// ── REST encoding ──────────────────────────────────────────────────────────

function enc(v: Val): unknown {
  if (v instanceof Ts) return { timestampValue: v.iso };
  if (v === null) return { nullValue: null };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  return { mapValue: { fields: encFields(v) } };
}

function encFields(f: Fields): Record<string, unknown> {
  return Object.fromEntries(Object.entries(f).map(([k, v]) => [k, enc(v)]));
}

const docsUrl = (projectId: string) =>
  `${BASE_URL}/v1/projects/${projectId}/databases/(default)/documents`;

// ── Request matrix ─────────────────────────────────────────────────────────

type Op =
  | { op: "get"; path: string }
  | { op: "query"; parent: string; collection: string; status?: string }
  | { op: "patch"; path: string; fields: Fields; mask?: string[] } // firmware upsert
  | { op: "update"; path: string; fields: Fields } // SDK update(): must exist
  | { op: "set"; path: string; fields: Fields } // SDK set(): full write
  | { op: "delete"; path: string };

type Outcome = "ALLOW" | "DENY";

interface Req {
  id: string;
  label: string;
  actor: Actor;
  req: Op;
  old: Outcome;
  now: Outcome;
}

const cmd = (uid: string, id: string) => `users/${uid}/commands/${id}`;
const hb = (uid: string, id = "current") => `users/${uid}/bridge_status/${id}`;
const reg = (dev: string) => `bridge_registry/${dev}`;

const A = "ALLOW" as const;
const D = "DENY" as const;

const GROUP_A: Omit<Req, "id">[] = [
  { label: "firmware runQuery: pending commands LIMIT 5 (main.cpp:686-707)", actor: BRIDGE,
    req: { op: "query", parent: `users/${U_A}`, collection: "commands", status: "pending" }, old: A, now: A },
  { label: "firmware PATCH pending -> executing, mask [status] (:809)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { status: "executing" } }, old: A, now: A },
  { label: "firmware PATCH executing -> completed + completedAt + result (:842)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "executing1"), fields: { status: "completed", completedAt: T1, result: '{"on":true}' } }, old: A, now: A },
  { label: "firmware PATCH executing -> failed + completedAt + error (:838)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "executing1"), fields: { status: "failed", completedAt: T1, error: "ERROR: HTTP -1" } }, old: A, now: A },
  { label: "firmware ping: pending -> completed + completedAt, no result (:788-793)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "ping1"), fields: { status: "completed", completedAt: T1 } }, old: A, now: A },
  { label: "firmware no-IP failure: pending -> failed + completedAt + error (:802-806)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { status: "failed", completedAt: T1, error: "No controller IP specified" } }, old: A, now: A },
  { label: "firmware pending -> completed (its executing PATCH was lost in transit)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { status: "completed", completedAt: T1, result: "{}" } }, old: A, now: A },
  { label: "firmware heartbeat PATCH bridge_status/current, 7 fields (:983-1014)", actor: BRIDGE,
    req: { op: "patch", path: hb(U_A), fields: heartbeat({ uptime: 86430 }) }, old: A, now: A },
  { label: "firmware first heartbeat after pairing (upsert creates the doc)", actor: BRIDGE,
    req: { op: "patch", path: hb(U_E), fields: heartbeat() }, old: A, now: A },
  { label: "firmware self-registration creates the doc, unpaired (:1069-1100)", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_NEW), fields: fullRegistration(DEV_NEW, "") }, old: A, now: A },
  { label: "firmware self-registration creates the doc, paired from NVS", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_NEW), fields: fullRegistration(DEV_NEW, U_E) }, old: A, now: A },
  { label: "firmware self-registration at boot over its existing doc", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: fullRegistration(DEV_A, U_A) }, old: A, now: A },
  { label: "firmware self-registration after an NVS reset (paired -> unpaired)", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: fullRegistration(DEV_A, "") }, old: A, now: A },
  { label: "firmware registry heartbeat, paired (:1122-1160)", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: registryBeat(U_A) }, old: A, now: A },
  { label: "firmware registry heartbeat while a pairing request is open (-> unpaired)", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_D), fields: registryBeat("") }, old: A, now: A },
  { label: "firmware heartbeat re-asserts its NVS uid over an admin unpair", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_C), fields: registryBeat(U_A) }, old: A, now: A },
  { label: "firmware heartbeat after a LAN re-pair (/api/bridge/pair) to another uid", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: registryBeat(U_B) }, old: A, now: A },
  { label: "firmware pairing poll: GET its registry doc (:1180-1187)", actor: BRIDGE,
    req: { op: "get", path: reg(DEV_D) }, old: A, now: A },
  { label: "firmware pairing confirm: paired, pairedUid = pendingUid, pendingUid '' (:1243-1267)", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_D), fields: { status: "paired", pairedUid: U_C, pendingUid: "", lastSeen: T1 } }, old: A, now: A },
  { label: "firmware registry heartbeat on a legacy doc missing identity fields", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_E), fields: registryBeat(U_A) }, old: A, now: A },
  { label: "firmware self-registration over a legacy doc (fills every field)", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_E), fields: fullRegistration(DEV_E, U_A) }, old: A, now: A },
];

const GROUP_B: Omit<Req, "id">[] = [
  // commands — read
  { label: "bridge GET a single command", actor: BRIDGE,
    req: { op: "get", path: cmd(U_A, "pending1") }, old: A, now: D },
  { label: "bridge query ALL commands (history, no status filter)", actor: BRIDGE,
    req: { op: "query", parent: `users/${U_A}`, collection: "commands" }, old: A, now: D },
  { label: "bridge query completed commands", actor: BRIDGE,
    req: { op: "query", parent: `users/${U_A}`, collection: "commands", status: "completed" }, old: A, now: D },
  // commands — field tampering
  { label: "bridge rewrites payload on a pending command", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { payload: '{"on":false}' } }, old: A, now: D },
  { label: "bridge re-points controllerIp on a pending command", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { controllerIp: "192.0.2.99" } }, old: A, now: D },
  { label: "bridge rewrites controllerId", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { controllerId: "ctl-9" } }, old: A, now: D },
  { label: "bridge rewrites type", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { type: "getInfo" } }, old: A, now: D },
  { label: "bridge rewrites createdAt", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { createdAt: T2 } }, old: A, now: D },
  { label: "bridge rewrites source", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { source: "server" } }, old: A, now: D },
  { label: "bridge extends expiresAt", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { expiresAt: ts("2027-01-01T00:00:00Z") } }, old: A, now: D },
  { label: "bridge legal status change smuggling a payload change", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { status: "executing", payload: '{"on":false}' } }, old: A, now: D },
  // commands — illegal transitions
  { label: "bridge re-arms a completed command (completed -> pending)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "completed1"), fields: { status: "pending" } }, old: A, now: D },
  { label: "bridge overwrites a server failure (failed -> completed)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "failed1"), fields: { status: "completed", completedAt: T1 } }, old: A, now: D },
  { label: "bridge revives a swept command (expired -> executing)", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "expired1"), fields: { status: "executing" } }, old: A, now: D },
  { label: "bridge pending -> executing with an extra result field", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { status: "executing", result: "{}" } }, old: A, now: D },
  { label: "bridge executing -> completed without completedAt", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "executing1"), fields: { status: "completed" } }, old: A, now: D },
  { label: "bridge adds an arbitrary field, status unchanged", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { note: "x" } }, old: A, now: D },
  { label: "bridge completed with a non-string result", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "executing1"), fields: { status: "completed", completedAt: T1, result: 7 } }, old: A, now: D },
  // commands — never allowed
  { label: "bridge creates a command", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_A, "forged1"), fields: command("pending") }, old: D, now: D },
  { label: "bridge deletes a command", actor: BRIDGE,
    req: { op: "delete", path: cmd(U_A, "completed1") }, old: D, now: D },
  { label: "bridge queries an account with no bridge", actor: BRIDGE,
    req: { op: "query", parent: `users/${U_C}`, collection: "commands", status: "pending" }, old: D, now: D },
  { label: "bridge updates a command of an account with no bridge", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_C, "pending1"), fields: { status: "executing" } }, old: D, now: D },
  { label: "bridge queries an account delegated to another identity", actor: BRIDGE,
    req: { op: "query", parent: `users/${U_D}`, collection: "commands", status: "pending" }, old: D, now: D },
  // bridge_status
  { label: "bridge reads bridge_status/current", actor: BRIDGE,
    req: { op: "get", path: hb(U_A) }, old: A, now: D },
  { label: "bridge heartbeat with an extra field", actor: BRIDGE,
    req: { op: "patch", path: hb(U_A), fields: heartbeat({ note: "x" }) }, old: A, now: D },
  { label: "bridge writes a bridge_status doc other than current", actor: BRIDGE,
    req: { op: "patch", path: hb(U_A, "diag"), fields: heartbeat() }, old: A, now: D },
  { label: "bridge heartbeat with a mistyped field (uptime as string)", actor: BRIDGE,
    req: { op: "patch", path: hb(U_A), fields: heartbeat({ uptime: "86400" }) }, old: A, now: D },
  { label: "bridge heartbeat into an account with no bridge", actor: BRIDGE,
    req: { op: "patch", path: hb(U_C), fields: heartbeat() }, old: D, now: D },
  { label: "bridge deletes bridge_status/current", actor: BRIDGE,
    req: { op: "delete", path: hb(U_A) }, old: D, now: D },
  // bridge_registry — read
  { label: "bridge lists the whole registry", actor: BRIDGE,
    req: { op: "query", parent: "", collection: "bridge_registry" }, old: A, now: D },
  // bridge_registry — create
  { label: "bridge creates a registry doc in the 7-field heartbeat shape", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_NEW), fields: registryBeat(U_E) }, old: A, now: D },
  { label: "bridge creates a registry doc in the 4-field confirm shape", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_NEW), fields: { status: "paired", pairedUid: U_E, pendingUid: "", lastSeen: T1 } }, old: A, now: D },
  { label: "bridge creates a registry doc whose deviceId is not its doc id", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_NEW), fields: fullRegistration(DEV_NEW, "", { deviceId: DEV_A }) }, old: A, now: D },
  { label: "bridge creates a registry doc naming a foreign bridgeEmail", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_NEW), fields: fullRegistration(DEV_NEW, "", { bridgeEmail: "someone-else" }) }, old: A, now: D },
  { label: "bridge creates a registry doc with an extra field", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_NEW), fields: fullRegistration(DEV_NEW, "", { owner: ATTACKER_UID }) }, old: A, now: D },
  { label: "bridge creates a registry doc under a non-MAC id", actor: BRIDGE,
    req: { op: "patch", path: reg("not-a-mac"), fields: fullRegistration("not-a-mac", "") }, old: A, now: D },
  // bridge_registry — update
  { label: "bridge rewrites a doc's bridgeEmail", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: { bridgeEmail: "someone-else" } }, old: A, now: D },
  { label: "bridge rewrites a doc's deviceId", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: { deviceId: DEV_B } }, old: A, now: D },
  { label: "bridge opens a pairing request (pendingUid = a uid)", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_C), fields: { pendingUid: U_C } }, old: A, now: D },
  { label: "bridge sets status pairing", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_C), fields: { status: "pairing" } }, old: A, now: D },
  { label: "bridge sets status paired with an empty pairedUid", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: { status: "paired", pairedUid: "" } }, old: A, now: D },
  { label: "bridge adds a field outside the 14 (pairingRequestedAt)", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: { pairingRequestedAt: T1 } }, old: A, now: D },
  { label: "bridge rewrites firmwareVersion", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: { firmwareVersion: "9.9" } }, old: A, now: D },
  { label: "bridge rewrites deviceName", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: { deviceName: "Lumina-FFFF" } }, old: A, now: D },
  { label: "bridge uses the USER pairing arm (pendingUid = its own uid)", actor: BRIDGE,
    req: { op: "update", path: reg(DEV_C), fields: { status: "pairing", pendingUid: "shared-bridge-account", pairingRequestedAt: T1 } }, old: A, now: D },
  { label: "bridge deletes a registry doc", actor: BRIDGE,
    req: { op: "delete", path: reg(DEV_A) }, old: D, now: D },
  { label: "bridge writes a registry ip that is not a dotted quad", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_A), fields: { ip: "not-an-ip" } }, old: A, now: D },
];

const GROUP_C: Omit<Req, "id">[] = [
  { label: "RESIDUAL: bridge queries pending commands of ANOTHER paired account", actor: BRIDGE,
    req: { op: "query", parent: `users/${U_B}`, collection: "commands", status: "pending" }, old: A, now: A },
  { label: "RESIDUAL: bridge marks ANOTHER paired account's command executing", actor: BRIDGE,
    req: { op: "patch", path: cmd(U_B, "pending1"), fields: { status: "executing" } }, old: A, now: A },
  { label: "RESIDUAL: bridge heartbeats into ANOTHER paired account", actor: BRIDGE,
    req: { op: "patch", path: hb(U_B), fields: heartbeat() }, old: A, now: A },
  { label: "RESIDUAL: bridge re-points another device's pairedUid", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_B), fields: registryBeat(ATTACKER_UID) }, old: A, now: A },
  { label: "RESIDUAL: bridge clears another device's pairing", actor: BRIDGE,
    req: { op: "patch", path: reg(DEV_B), fields: registryBeat("") }, old: A, now: A },
  { label: "RESIDUAL: bridge GETs another device's registry doc", actor: BRIDGE,
    req: { op: "get", path: reg(DEV_B) }, old: A, now: A },
  { label: "RESIDUAL (generic arm): bridge sets bridge_email on an unpaired user doc", actor: BRIDGE,
    req: { op: "patch", path: `users/${U_C}`, fields: { bridge_email: SHARED_ADDRESS } }, old: A, now: A },
  { label: "RESIDUAL (generic arm): bridge reads another user's controller", actor: BRIDGE,
    req: { op: "get", path: `users/${U_A}/controllers/ctl-1` }, old: A, now: A },
];

const GROUP_D: Omit<Req, "id">[] = [
  { label: "owner GETs own command", actor: OWNER_A,
    req: { op: "get", path: cmd(U_A, "pending1") }, old: A, now: A },
  { label: "owner queries own commands, no filter", actor: OWNER_A,
    req: { op: "query", parent: `users/${U_A}`, collection: "commands" }, old: A, now: A },
  { label: "owner creates a command targeting own controller", actor: OWNER_A,
    req: { op: "set", path: cmd(U_A, "new1"), fields: command("pending") }, old: A, now: A },
  { label: "owner creates a command targeting a foreign IP", actor: OWNER_A,
    req: { op: "set", path: cmd(U_A, "new2"), fields: command("pending", { controllerIp: "192.0.2.99" }) }, old: D, now: D },
  { label: "owner updates own pending command payload", actor: OWNER_A,
    req: { op: "update", path: cmd(U_A, "pending1"), fields: { payload: '{"on":false}' } }, old: A, now: A },
  { label: "owner deletes own command", actor: OWNER_A,
    req: { op: "delete", path: cmd(U_A, "completed1") }, old: A, now: A },
  { label: "owner reads own bridge_status", actor: OWNER_A,
    req: { op: "get", path: hb(U_A) }, old: A, now: A },
  { label: "owner writes own bridge_status (any field)", actor: OWNER_A,
    req: { op: "patch", path: hb(U_A), fields: { note: "x" } }, old: A, now: A },
  { label: "email-less session (anonymous) keeps the user pairing arm", actor: ANON,
    req: { op: "update", path: reg(DEV_C), fields: { status: "pairing", pendingUid: "anon-session", pairingRequestedAt: T1 } }, old: A, now: A },
  { label: "another customer GETs this customer's command", actor: OWNER_B,
    req: { op: "get", path: cmd(U_A, "pending1") }, old: D, now: D },
  { label: "another customer queries this customer's commands", actor: OWNER_B,
    req: { op: "query", parent: `users/${U_A}`, collection: "commands", status: "pending" }, old: D, now: D },
  { label: "another customer updates this customer's command status", actor: OWNER_B,
    req: { op: "patch", path: cmd(U_A, "pending1"), fields: { status: "executing" } }, old: D, now: D },
  { label: "corporate admin queries a customer's commands", actor: CORP_ADMIN,
    req: { op: "query", parent: `users/${U_A}`, collection: "commands" }, old: A, now: A },
  { label: "installer (same dealer) GETs a customer's command", actor: INSTALLER_D1,
    req: { op: "get", path: cmd(U_A, "pending1") }, old: D, now: D },
  { label: "installer GETs a registry doc", actor: INSTALLER_D1,
    req: { op: "get", path: reg(DEV_A) }, old: A, now: A },
  { label: "installer lists the registry", actor: INSTALLER_D1,
    req: { op: "query", parent: "", collection: "bridge_registry" }, old: A, now: A },
  { label: "user requests pairing on an unpaired bridge (app update())", actor: USER_C,
    req: { op: "update", path: reg(DEV_C), fields: { status: "pairing", pendingUid: U_C, pairingRequestedAt: T1 } }, old: A, now: A },
  { label: "user requests pairing on a paired bridge", actor: USER_C,
    req: { op: "update", path: reg(DEV_A), fields: { status: "pairing", pendingUid: U_C, pairingRequestedAt: T1 } }, old: D, now: D },
  { label: "user requests pairing on behalf of another uid", actor: USER_C,
    req: { op: "update", path: reg(DEV_C), fields: { status: "pairing", pendingUid: U_B, pairingRequestedAt: T1 } }, old: D, now: D },
  { label: "anonymous session lists the registry", actor: ANON,
    req: { op: "query", parent: "", collection: "bridge_registry" }, old: A, now: A },
  { label: "anonymous session creates a registry doc", actor: ANON,
    req: { op: "patch", path: reg(DEV_NEW), fields: fullRegistration(DEV_NEW, "") }, old: D, now: D },
  { label: "unauthenticated GET of a registry doc", actor: UNAUTH,
    req: { op: "get", path: reg(DEV_A) }, old: D, now: D },
  { label: "installer (same dealer) writes a customer's pixelMap", actor: INSTALLER_D1,
    req: { op: "set", path: `users/${U_A}/controllers/ctl-1/pixelMap/0`, fields: { channelId: 0 } }, old: A, now: A },
  { label: "signed-in stranger updates a profile field (generic arm, unchanged)", actor: STRANGER,
    req: { op: "update", path: `users/${U_A}`, fields: { display_name: "x" } }, old: A, now: A },
];

const withIds = (prefix: string, rows: Omit<Req, "id">[]): Req[] =>
  rows.map((r, i) => ({ ...r, id: `${prefix}${String(i + 1).padStart(2, "0")}` }));

const MATRIX: Req[] = [
  ...withIds("A", GROUP_A),
  ...withIds("B", GROUP_B),
  ...withIds("C", GROUP_C),
  ...withIds("D", GROUP_D),
];

// ── Execution ──────────────────────────────────────────────────────────────

async function http(method: string, url: string, token: string | null, body?: unknown) {
  const res = await fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, text: await res.text() };
}

async function reseed(projectId: string): Promise<void> {
  const clear = await http(
    "DELETE",
    `${BASE_URL}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    null,
  );
  if (clear.status !== 200) throw new Error(`clear failed: ${clear.status} ${clear.text}`);
  const writes = Object.entries(SEED).map(([path, fields]) => ({
    update: {
      name: `projects/${projectId}/databases/(default)/documents/${path}`,
      fields: encFields(fields),
    },
  }));
  // "owner" is the emulator's rules-bypass token (what withSecurityRulesDisabled uses).
  const res = await http("POST", `${docsUrl(projectId)}:commit`, "owner", { writes });
  if (res.status !== 200) throw new Error(`seed failed: ${res.status} ${res.text}`);
}

const maskQuery = (keys: string[]) =>
  keys.map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join("&");

async function perform(projectId: string, actor: Actor, r: Op): Promise<Outcome> {
  const token = actor ? mockToken(actor, projectId) : null;
  const base = docsUrl(projectId);
  let res: { status: number; text: string };
  switch (r.op) {
    case "get":
      res = await http("GET", `${base}/${r.path}`, token);
      break;
    case "query": {
      const structuredQuery: Record<string, unknown> = {
        from: [{ collectionId: r.collection }],
        limit: 5,
      };
      if (r.status !== undefined) {
        structuredQuery.where = {
          fieldFilter: {
            field: { fieldPath: "status" },
            op: "EQUAL",
            value: { stringValue: r.status },
          },
        };
      }
      const parent = r.parent ? `${base}/${r.parent}` : base;
      res = await http("POST", `${parent}:runQuery`, token, { structuredQuery });
      break;
    }
    case "patch":
      res = await http(
        "PATCH",
        `${base}/${r.path}?${maskQuery(r.mask ?? Object.keys(r.fields))}`,
        token,
        { fields: encFields(r.fields) },
      );
      break;
    case "update":
      res = await http(
        "PATCH",
        `${base}/${r.path}?${maskQuery(Object.keys(r.fields))}&currentDocument.exists=true`,
        token,
        { fields: encFields(r.fields) },
      );
      break;
    case "set":
      res = await http("PATCH", `${base}/${r.path}`, token, { fields: encFields(r.fields) });
      break;
    case "delete":
      res = await http("DELETE", `${base}/${r.path}`, token);
      break;
  }
  if (res.status === 200) return "ALLOW";
  if (res.status === 403 && res.text.includes("PERMISSION_DENIED")) return "DENY";
  throw new Error(`unexpected ${res.status}: ${res.text.slice(0, 300)}`);
}

let newEnv: RulesTestEnvironment;
let oldEnv: RulesTestEnvironment | undefined;
const observed: Record<string, { old?: Outcome; now?: Outcome }> = {};

beforeAll(async () => {
  if (!SHARED_ADDRESS) throw new Error("could not read the shared bridge account from firestore.rules");
  newEnv = await initializeTestEnvironment({
    projectId: NEW_PROJECT,
    firestore: { rules: NEW_RULES, host: HOST, port: PORT },
  });
  if (OLD_RULES !== null) {
    oldEnv = await initializeTestEnvironment({
      projectId: OLD_PROJECT,
      firestore: { rules: OLD_RULES, host: HOST, port: PORT },
    });
  }
});

afterAll(async () => {
  const deltas = MATRIX.filter((r) => observed[r.id]?.old && observed[r.id].old !== observed[r.id].now);
  // The delta list, for the run log.
  console.log(
    `bridge rules matrix: ${MATRIX.length} requests, ${deltas.length} deltas (old -> new)\n` +
      deltas.map((r) => `  ${r.id} ${observed[r.id].old} -> ${observed[r.id].now}  ${r.label}`).join("\n"),
  );
  await newEnv?.cleanup();
  await oldEnv?.cleanup();
});

describe("bridge least-privilege matrix — NEW rules", () => {
  test("the matrix has exactly 100 requests", () => {
    expect(MATRIX.length).toBe(100);
    expect(new Set(MATRIX.map((r) => r.id)).size).toBe(100);
  });

  test.each(MATRIX.map((r) => [r.id, r.label, r] as const))("%s %s", async (_id, _label, r) => {
    await reseed(NEW_PROJECT);
    const got = await perform(NEW_PROJECT, r.actor, r.req);
    (observed[r.id] ??= {}).now = got;
    expect(got).toBe(r.now);
  });
});

(OLD_RULES !== null ? describe : describe.skip)(
  `bridge least-privilege matrix — OLD rules (${BASELINE_REF.slice(0, 7)})`,
  () => {
    test.each(MATRIX.map((r) => [r.id, r.label, r] as const))("%s %s", async (_id, _label, r) => {
      await reseed(OLD_PROJECT);
      const got = await perform(OLD_PROJECT, r.actor, r.req);
      (observed[r.id] ??= {}).old = got;
      expect(got).toBe(r.old);
    });

    test("every delta is the bridge identity losing an ALLOW, and there are exactly 39", () => {
      const deltas = MATRIX.filter((r) => observed[r.id].old !== observed[r.id].now);
      expect(deltas.map((r) => r.id)).toEqual(
        MATRIX.filter((r) => r.old !== r.now).map((r) => r.id),
      );
      expect(deltas).toHaveLength(39);
      for (const r of deltas) {
        expect(r.actor).toBe(BRIDGE);
        expect([observed[r.id].old, observed[r.id].now]).toEqual(["ALLOW", "DENY"]);
      }
      // No owner, staff, installer, user-pairing or anonymous request moved.
      for (const r of MATRIX.filter((x) => x.actor !== BRIDGE)) {
        expect(observed[r.id].now).toBe(observed[r.id].old);
      }
    });
  },
);
