/**
 * B-3c — Alexa account linking and voice commands, end to end against the
 * Firestore emulator, through the REAL exported index.js handlers
 * (alexaToken, alexaSmartHome, executeWledCommand, onVoiceIntegrationDeleted,
 * sweepStaleVoiceLinks). One describe block per B-3c fix. Every block has at
 * least one case that fails on B-3b as written (feat/voice-canonical-commands
 * merged onto fix/voice-link-page); the negative-control run is recorded in
 * the commit message.
 *
 * Run (from functions/, Firestore emulator only):
 *   firebase emulators:exec --only firestore --project <test-project> \
 *     "npx jest --config jest.emulator.config.js --runInBand --testTimeout=120000 voiceAlexaLink"
 * `npm run build` first: index.js requires lib/.
 *
 * Every id, address and secret below is synthetic (RFC 5737 addresses).
 */
import * as admin from "firebase-admin";
import { createHash, createHmac } from "crypto";
import { readFileSync, readdirSync } from "fs";
import { join } from "path";

/* eslint-disable @typescript-eslint/no-explicit-any */
type Json = any;

const JWT_SECRET = "test-only-jwt-secret-000000000000000000000000";
const CLIENT_ID = "test-alexa-client";
const CLIENT_SECRET = "test:alexa client+secret"; // exercises Basic encoding
const VENDOR = "TESTVENDOR01";
const REDIRECT = `https://pitangui.amazon.com/api/skill/link/${VENDOR}`;

// Accounts: paired bridge, no bridge, webhook mode, another account.
const UID = "u_voice_alpha";
const NOBRIDGE = "u_voice_gamma";
const WEBHOOK = "u_voice_delta";
const OTHER = "u_voice_beta";

const CTL_A = "AA00000000A1"; // MAC-shaped controller ids, as in production
const CTL_B = "AA00000000A2";
const IP_A = "192.0.2.10";
const IP_B = "192.0.2.11";
const SCENE = "sceneSynthetic000001";
const TEAM = "nfl_synthetic_team";
const WEBHOOK_URL = "https://webhook.example.test/lumina";
const PROPERTY = "100 Example Street";

const ENV: Record<string, string> = {
  ALEXA_CLIENT_ID: CLIENT_ID,
  ALEXA_CLIENT_SECRET: CLIENT_SECRET,
  ALEXA_JWT_SECRET: JWT_SECRET,
  ALEXA_VENDOR_ID: VENDOR,
};

let idx: Json;
let db: admin.firestore.Firestore;
const unsubs: Array<() => void> = [];

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

function fakeRes() {
  const r: Json = { statusCode: 200, headers: {} as Record<string, string>, body: undefined };
  r.set = (k: string, v: string) => {
    r.headers[k.toLowerCase()] = v;
    return r;
  };
  r.setHeader = r.set;
  r.status = (c: number) => {
    r.statusCode = c;
    return r;
  };
  r.json = (b: unknown) => {
    r.body = b;
    return r;
  };
  r.send = (b: unknown) => {
    r.body = b;
    return r;
  };
  r.on = () => r;
  return r;
}

async function http(handler: Json, body: Json, headers: Record<string, string> = {}) {
  const req = {
    method: "POST",
    headers,
    body,
    query: {},
    header: (n: string) => headers[n.toLowerCase()],
    get: (n: string) => headers[n.toLowerCase()],
  };
  const res = fakeRes();
  await handler(req, res);
  return res;
}

function formEnc(s: string): string {
  return encodeURIComponent(s).replace(/%20/g, "+");
}
function basic(id: string, secret: string): string {
  return "Basic " + Buffer.from(`${formEnc(id)}:${formEnc(secret)}`).toString("base64");
}

function b64url(o: unknown): string {
  return Buffer.from(JSON.stringify(o)).toString("base64url");
}
function signJwt(claims: Json, secret: string, header: Json = { alg: "HS256", typ: "JWT" }): string {
  const input = `${b64url(header)}.${b64url(claims)}`;
  return `${input}.${createHmac("sha256", secret).update(input).digest("base64url")}`;
}
function jwtClaims(token: string): Json {
  return JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString("utf8"));
}
const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");
const nowSec = () => Math.floor(Date.now() / 1000);

async function clearEmulator() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const project = process.env.GCLOUD_PROJECT;
  const r = await fetch(
    `http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,
    { method: "DELETE" }
  );
  if (!r.ok) throw new Error(`emulator clear failed: ${r.status}`);
}

async function seed() {
  const ts = admin.firestore.Timestamp;
  await db.doc(`users/${UID}`).set({ propertyName: PROPERTY, webhookUrl: "" });
  await db.doc(`users/${UID}/controllers/${CTL_A}`).set({
    name: "Front Roofline", ip: IP_A, createdAt: ts.fromMillis(1_000),
  });
  await db.doc(`users/${UID}/controllers/${CTL_B}`).set({
    name: "Garage", ip: IP_B, createdAt: ts.fromMillis(2_000),
  });
  await db.doc(`users/${UID}/scenes/${SCENE}`).set({
    name: "Evening Glow", type: "library", brightness: 180,
    library_pattern: { colors: JSON.stringify([[255, 120, 0, 0]]), effect_id: 0, speed: 128, intensity: 128 },
  });
  await db.doc(`users/${UID}/game_day_autopilot/${TEAM}`).set({
    team_name: "Synthetic Team", saved_design_payload: JSON.stringify({ on: true, bri: 255 }),
  });
  await db.doc(`users/${UID}/device_state/current`).set({ on: true, brightness: 128 });
  await db.doc("bridge_registry/BR00000000B1").set({ pairedUid: UID, status: "paired" });

  await db.doc(`users/${NOBRIDGE}`).set({ webhookUrl: "" });
  await db.doc(`users/${NOBRIDGE}/controllers/${CTL_A}`).set({ name: "Porch", ip: IP_A });

  await db.doc(`users/${WEBHOOK}`).set({ webhookUrl: WEBHOOK_URL });
  await db.doc(`users/${WEBHOOK}/controllers/${CTL_A}`).set({ name: "Porch", ip: IP_A });

  await db.doc(`users/${OTHER}`).set({ webhookUrl: "" });
}

async function allowVoice(uids: string[], enabled = false) {
  await db.doc("config/voice_control").set({ enabled, allowlistUids: uids });
}

async function mintCode(uid: string, extra: Json = {}): Promise<string> {
  const code = `code_${uid}_${Math.random().toString(36).slice(2)}_padding`;
  await db.doc(`oauth_codes/${code}`).set({
    userId: uid,
    state: "s",
    used: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
    ...extra,
  });
  return code;
}

async function exchange(code: string, how: "basic" | "body" = "body", extra: Json = {}) {
  const body: Json = { grant_type: "authorization_code", code, redirect_uri: REDIRECT, ...extra };
  const headers: Record<string, string> = {};
  if (how === "basic") headers.authorization = basic(CLIENT_ID, CLIENT_SECRET);
  else Object.assign(body, { client_id: CLIENT_ID, client_secret: CLIENT_SECRET });
  return http(idx.alexaToken, body, headers);
}

async function refreshGrant(token: string) {
  return http(idx.alexaToken, {
    grant_type: "refresh_token", refresh_token: token, client_id: CLIENT_ID, client_secret: CLIENT_SECRET,
  });
}

async function link(uid: string) {
  const res = await exchange(await mintCode(uid));
  if (res.statusCode !== 200) throw new Error(`link failed: ${res.statusCode} ${JSON.stringify(res.body)}`);
  return res.body as { access_token: string; refresh_token: string; expires_in: number };
}

function directive(namespace: string, name: string, token: string, endpointId?: string, payload: Json = {}) {
  const header = { namespace, name, messageId: "m-1", correlationToken: "corr-1", payloadVersion: "3" };
  const scope = { type: "BearerToken", token };
  if (namespace === "Alexa.Discovery") {
    return { directive: { header: { ...header, correlationToken: undefined }, payload: { ...payload, scope } } };
  }
  return { directive: { header, endpoint: { endpointId, scope }, payload } };
}

async function alexa(body: Json) {
  const res = await http(idx.alexaSmartHome, body);
  return res.body;
}

/** Simulate the bridge: complete every pending command for `uid`. */
function bridgeCompletes(uid: string) {
  const u = db.collection(`users/${uid}/commands`).onSnapshot((snap) => {
    for (const ch of snap.docChanges()) {
      if (ch.type === "added" && ch.doc.get("status") === "pending") {
        ch.doc.ref.update({ status: "completed" }).catch(() => undefined);
      }
    }
  });
  unsubs.push(u);
}

async function commandDocs(uid: string) {
  return (await db.collection(`users/${uid}/commands`).get()).docs;
}

function errType(resp: Json): string | undefined {
  return resp?.event?.header?.name === "ErrorResponse" ? resp.event.payload.type : undefined;
}

async function endpoints(token: string): Promise<Json[]> {
  const r = await alexa(directive("Alexa.Discovery", "Discover", token));
  expect(r.event.header.name).toBe("Discover.Response");
  return r.event.payload.endpoints;
}

// ---------------------------------------------------------------------------

beforeAll(() => {
  Object.assign(process.env, ENV);
  jest.spyOn(console, "log").mockImplementation(() => undefined);
  jest.spyOn(console, "warn").mockImplementation(() => undefined);
  jest.spyOn(console, "error").mockImplementation(() => undefined);
  idx = require("../../index.js");
  db = admin.firestore();
}, 120000);

beforeEach(async () => {
  Object.assign(process.env, ENV);
  await clearEmulator();
  await seed();
});

afterEach(() => {
  while (unsubs.length) unsubs.pop()?.();
});

afterAll(() => {
  jest.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// 1. Dedicated signing secret, no fallback
// ---------------------------------------------------------------------------
describe("1. ALEXA_JWT_SECRET only — no fallback to ALEXA_CLIENT_SECRET", () => {
  test("missing ALEXA_JWT_SECRET: alexaToken refuses to issue, and the code is not spent", async () => {
    await allowVoice([UID]);
    delete process.env.ALEXA_JWT_SECRET;
    const code = await mintCode(UID);
    const res = await exchange(code);
    expect(res.statusCode).toBe(500);
    expect(res.body).toEqual({ error: "server_error" });
    expect((await db.doc(`oauth_codes/${code}`).get()).get("used")).toBe(false);
  });

  test("a secret shorter than 32 bytes is refused the same way", async () => {
    await allowVoice([UID]);
    process.env.ALEXA_JWT_SECRET = "too-short";
    const res = await exchange(await mintCode(UID));
    expect(res.statusCode).toBe(500);
    expect(res.body.access_token).toBeUndefined();
  });

  test("missing ALEXA_JWT_SECRET: alexaSmartHome refuses every directive", async () => {
    await allowVoice([UID]);
    const { access_token } = await link(UID);
    delete process.env.ALEXA_JWT_SECRET;
    expect(errType(await alexa(directive("Alexa.Discovery", "Discover", access_token)))).toBe("INTERNAL_ERROR");
  });
});

// ---------------------------------------------------------------------------
// 2. Expiry on every token; issuer, audience and expiry verified on every use
// ---------------------------------------------------------------------------
describe("2. every token expires; iss, aud and exp checked on every use", () => {
  test("the access token carries iss, aud, iat and a one-hour exp", async () => {
    await allowVoice([UID]);
    const { access_token, expires_in } = await link(UID);
    const c = jwtClaims(access_token);
    expect(c.iss).toBe("lumina-alexa");
    expect(c.aud).toBe("alexa-smart-home");
    expect(typeof c.iat).toBe("number");
    expect(c.exp - c.iat).toBe(3600);
    expect(expires_in).toBe(3600);
  });

  test("the refresh token is stored hashed, with an expiry about 90 days out", async () => {
    await allowVoice([UID]);
    const { refresh_token } = await link(UID);
    expect((await db.doc(`oauth_refresh_tokens/${refresh_token}`).get()).exists).toBe(false);
    const rec = (await db.doc(`oauth_refresh_tokens/${sha256(refresh_token)}`).get()).data() as Json;
    expect(rec.iss).toBe("lumina-alexa");
    expect(rec.aud).toBe(CLIENT_ID);
    const days = (rec.expiresAt.toMillis() - Date.now()) / 86_400_000;
    expect(days).toBeGreaterThan(89);
    expect(days).toBeLessThan(91);
  });

  test("a well-signed access token with no exp is rejected", async () => {
    await allowVoice([UID]);
    const { access_token } = await link(UID);
    const c = jwtClaims(access_token);
    delete c.exp;
    const forged = signJwt(c, JWT_SECRET);
    expect(errType(await alexa(directive("Alexa.Discovery", "Discover", forged)))).toBe(
      "INVALID_AUTHORIZATION_CREDENTIAL");
  });

  test.each([
    ["wrong audience", { aud: "someone-else" }],
    ["wrong issuer", { iss: "someone-else" }],
    ["no audience", { aud: undefined }],
    ["lifetime over one hour", { exp: nowSec() + 7200 }],
    ["alg none header", "ALG_NONE"],
  ])("rejected: %s", async (_label, change) => {
    await allowVoice([UID]);
    const { access_token } = await link(UID);
    const c = jwtClaims(access_token);
    let forged: string;
    if (change === "ALG_NONE") {
      forged = signJwt(c, JWT_SECRET, { alg: "none", typ: "JWT" });
    } else {
      forged = signJwt({ ...c, ...(change as Json) }, JWT_SECRET);
    }
    expect(errType(await alexa(directive("Alexa.Discovery", "Discover", forged)))).toBe(
      "INVALID_AUTHORIZATION_CREDENTIAL");
  });

  test("a refresh record without an expiry is refused (B-3b's stored shape)", async () => {
    await allowVoice([UID]);
    const raw = "legacyShapedRefreshToken000000000000000001";
    const legacy = { userId: UID, active: true, createdAt: admin.firestore.FieldValue.serverTimestamp() };
    await db.doc(`oauth_refresh_tokens/${raw}`).set(legacy);
    await db.doc(`oauth_refresh_tokens/${sha256(raw)}`).set(legacy);
    const res = await refreshGrant(raw);
    expect(res.statusCode).toBe(400);
    expect(res.body).toEqual({ error: "invalid_grant" });
  });

  test("an expired refresh record, or one issued to another client, is refused", async () => {
    await allowVoice([UID]);
    const { refresh_token } = await link(UID);
    const ref = db.doc(`oauth_refresh_tokens/${sha256(refresh_token)}`);
    await ref.update({ aud: "another-client" });
    expect((await refreshGrant(refresh_token)).statusCode).toBe(400);
    await ref.update({ aud: CLIENT_ID, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) });
    expect((await refreshGrant(refresh_token)).statusCode).toBe(400);
  });

  test("a valid refresh slides the expiry and returns a new one-hour access token", async () => {
    await allowVoice([UID]);
    const { refresh_token } = await link(UID);
    const res = await refreshGrant(refresh_token);
    expect(res.statusCode).toBe(200);
    expect(res.body.refresh_token).toBe(refresh_token);
    expect(jwtClaims(res.body.access_token).aud).toBe("alexa-smart-home");
  });
});

// ---------------------------------------------------------------------------
// 3. Nothing identifying reaches Amazon
// ---------------------------------------------------------------------------
describe("3. no uid, IP, controller address or customer identifier in anything sent to Amazon", () => {
  const FORBIDDEN = [UID, CTL_A, CTL_B, SCENE, TEAM, WEBHOOK_URL, PROPERTY, "BR00000000B1", "Synthetic Team"];
  const IPV4 = /\b\d{1,3}(?:\.\d{1,3}){3}\b/;
  const ENDPOINT_KEYS = ["capabilities", "description", "displayCategories", "endpointId", "friendlyName", "manufacturerName"];

  function assertClean(label: string, payload: unknown) {
    const s = typeof payload === "string" ? payload : JSON.stringify(payload);
    for (const f of FORBIDDEN) {
      if (s.includes(f)) throw new Error(`${label} leaks "${f}": ${s.slice(0, 400)}`);
    }
    if (IPV4.test(s)) throw new Error(`${label} leaks an IPv4 address: ${s.slice(0, 400)}`);
    if (/"cookie"/.test(s)) throw new Error(`${label} carries a cookie`);
  }

  test("token responses, discovery, every directive response and every error are clean", async () => {
    await allowVoice([UID]);
    bridgeCompletes(UID);
    const tok = await link(UID);
    assertClean("token response", tok);
    assertClean("access token claims", jwtClaims(tok.access_token));

    const eps = await endpoints(tok.access_token);
    assertClean("Discover.Response", eps);
    expect(eps.length).toBe(3); // two controllers + one scene; no Game Day design
    for (const e of eps) expect(Object.keys(e).sort()).toEqual(ENDPOINT_KEYS);

    const sent: Array<[string, unknown]> = [];
    for (const e of eps) {
      const isScene = e.displayCategories[0] === "SCENE_TRIGGER";
      const calls = isScene
        ? [directive("Alexa.SceneController", "Activate", tok.access_token, e.endpointId)]
        : [
            directive("Alexa.PowerController", "TurnOn", tok.access_token, e.endpointId),
            directive("Alexa.BrightnessController", "SetBrightness", tok.access_token, e.endpointId, { brightness: 40 }),
            directive("Alexa", "ReportState", tok.access_token, e.endpointId),
            directive("Alexa.PowerController", "TurnOff", tok.access_token, e.endpointId),
          ];
      for (const d of calls) sent.push([`${d.directive.header.name} ${e.friendlyName}`, await alexa(d)]);
    }
    sent.push(["unknown endpoint", await alexa(directive("Alexa.PowerController", "TurnOn", tok.access_token, "ctl-AAAAAAAAAAAAAAAAAAAAAAAA"))]);
    sent.push(["bad token", await alexa(directive("Alexa.PowerController", "TurnOn", "garbage", "lumina-main"))]);
    for (const [label, body] of sent) assertClean(label, body);

    const ok = sent.filter(([, b]) => (b as Json).event.header.name !== "ErrorResponse");
    expect(ok.length).toBe(9);
  });
});

// ---------------------------------------------------------------------------
// 4. Client credentials in BOTH forms; missing and wrong refused identically
// ---------------------------------------------------------------------------
describe("4. alexaToken client authentication", () => {
  test("HTTP Basic (Amazon's recommended scheme) is accepted", async () => {
    await allowVoice([UID]);
    const res = await exchange(await mintCode(UID), "basic");
    expect(res.statusCode).toBe(200);
    expect(typeof res.body.access_token).toBe("string");
  });

  test("credentials in the request body are accepted", async () => {
    await allowVoice([UID]);
    expect((await exchange(await mintCode(UID), "body")).statusCode).toBe(200);
  });

  test("missing and wrong credentials get the identical refusal", async () => {
    await allowVoice([UID]);
    const code = await mintCode(UID);
    const base = { grant_type: "authorization_code", code, redirect_uri: REDIRECT };
    const variants = [
      await http(idx.alexaToken, base),
      await http(idx.alexaToken, { ...base, client_id: CLIENT_ID, client_secret: "wrong" }),
      await http(idx.alexaToken, { ...base, client_id: "wrong", client_secret: CLIENT_SECRET }),
      await http(idx.alexaToken, base, { authorization: basic(CLIENT_ID, "wrong") }),
      await http(idx.alexaToken, base, { authorization: "Basic !!!not-base64" }),
      await http(idx.alexaToken, { ...base, client_id: "other" }, { authorization: basic(CLIENT_ID, CLIENT_SECRET) }),
    ];
    for (const r of variants) {
      expect(r.statusCode).toBe(401);
      expect(r.body).toEqual({ error: "invalid_client" });
      expect(r.headers["www-authenticate"]).toBe('Basic realm="lumina-alexa"');
      expect(r.headers["cache-control"]).toBe("no-store");
    }
    expect((await db.doc(`oauth_codes/${code}`).get()).get("used")).toBe(false);
  });

  test("an unconfigured server refuses instead of skipping the check", async () => {
    await allowVoice([UID]);
    process.env.ALEXA_CLIENT_SECRET = "";
    const res = await exchange(await mintCode(UID));
    expect(res.statusCode).toBe(500);
    expect(res.body.access_token).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// 5. Only documented Alexa behaviour
// ---------------------------------------------------------------------------
describe("5. documented error types only", () => {
  test("an expired, otherwise valid access token → EXPIRED_AUTHORIZATION_CREDENTIAL", async () => {
    await allowVoice([UID]);
    const { access_token } = await link(UID);
    const c = jwtClaims(access_token);
    const expired = signJwt({ ...c, iat: nowSec() - 7200, exp: nowSec() - 3600 }, JWT_SECRET);
    expect(errType(await alexa(directive("Alexa.Discovery", "Discover", expired)))).toBe(
      "EXPIRED_AUTHORIZATION_CREDENTIAL");
  });

  test("the handler cites Amazon's error reference and claims no refresh behaviour", () => {
    const src = readFileSync(join(__dirname, "../../src/voice/alexaSmartHome.ts"), "utf8");
    expect(src).toContain("developer.amazon.com/en-US/docs/alexa/device-apis/alexa-errorresponse.html");
    expect(src).not.toMatch(/signals Amazon to refresh|triggers? (a )?refresh/i);
  });
});

// ---------------------------------------------------------------------------
// 6. The app's command queue, relay eligibility and fail-fast; nothing else
// ---------------------------------------------------------------------------
describe("6. voice commands use the app's command queue and its rules", () => {
  const APP_KEYS = ["controllerId", "controllerIp", "createdAt", "payload", "source", "status", "type", "webhookUrl"];

  test("a command doc has the app's shape (plus source) and a string payload", async () => {
    await allowVoice([UID]);
    const { access_token } = await link(UID);
    const r = await alexa(directive("Alexa.PowerController", "TurnOn", access_token, "lumina-main"));
    expect(r.event.header.name).toBe("Response"); // optimistic after 4 s: nothing completes it
    const docs = await commandDocs(UID);
    expect(docs).toHaveLength(1);
    const d = docs[0].data();
    expect(Object.keys(d).sort()).toEqual(APP_KEYS);
    expect(typeof d.payload).toBe("string");
    expect(d).toMatchObject({ type: "setState", controllerId: CTL_A, controllerIp: IP_A, webhookUrl: "", source: "voice_alexa" });
  });

  test("bridge mode with no paired bridge: nothing is queued; Alexa hears ENDPOINT_UNREACHABLE", async () => {
    await allowVoice([NOBRIDGE]);
    const { access_token } = await link(NOBRIDGE);
    const r = await alexa(directive("Alexa.PowerController", "TurnOn", access_token, "lumina-main"));
    expect(errType(r)).toBe("ENDPOINT_UNREACHABLE");
    expect(await commandDocs(NOBRIDGE)).toHaveLength(0);
  });

  test("webhook mode queues with the account's webhook URL, as the app does", async () => {
    await allowVoice([WEBHOOK]);
    const { access_token } = await link(WEBHOOK);
    await alexa(directive("Alexa.PowerController", "TurnOff", access_token, "lumina-main"));
    const docs = await commandDocs(WEBHOOK);
    expect(docs).toHaveLength(1);
    expect(docs[0].get("webhookUrl")).toBe(WEBHOOK_URL);
  });

  test("a queued voice command goes through executeWledCommand's fail-fast like any command", async () => {
    await allowVoice([UID]);
    const { access_token } = await link(UID);
    await alexa(directive("Alexa.PowerController", "TurnOn", access_token, "lumina-main"));
    const [doc] = await commandDocs(UID);
    await db.doc("bridge_registry/BR00000000B1").delete(); // bridge unpaired after queueing
    await idx.executeWledCommand.run({ data: await doc.ref.get(), params: { userId: UID, commandId: doc.id } });
    const after = (await doc.ref.get()).data() as Json;
    expect(after.status).toBe("failed");
    expect(after.error).toBe("no_bridge_paired");
  });

  test("Game Day designs, controllers and the bridge registry are never touched", async () => {
    await allowVoice([UID]);
    bridgeCompletes(UID);
    const snapshot = async () => JSON.stringify(await Promise.all([
      db.collection(`users/${UID}/game_day_autopilot`).get().then((s) => s.docs.map((d) => d.data())),
      db.collection(`users/${UID}/controllers`).get().then((s) => s.docs.map((d) => [d.id, d.data()])),
      db.collection("bridge_registry").get().then((s) => s.docs.map((d) => [d.id, d.data()])),
    ]));
    const before = await snapshot();
    const { access_token } = await link(UID);
    const eps = await endpoints(access_token);
    expect(eps.map((e) => e.friendlyName)).not.toContain("Synthetic Team");
    for (const e of eps) {
      const d = e.displayCategories[0] === "SCENE_TRIGGER"
        ? directive("Alexa.SceneController", "Activate", access_token, e.endpointId)
        : directive("Alexa.PowerController", "TurnOn", access_token, e.endpointId);
      await alexa(d);
    }
    expect(await snapshot()).toBe(before);
  });

  test("the voice modules make no network calls and do not name Game Day or the registry", () => {
    const dir = join(__dirname, "../../src/voice");
    for (const f of readdirSync(dir).filter((n) => n.endsWith(".ts"))) {
      const src = readFileSync(join(dir, f), "utf8");
      expect([f, /\bfetch\(|require\(["']https?["']\)|from ["']https?["']|axios|dgram|from ["']net["']/.test(src)])
        .toEqual([f, false]);
      expect([f, /game_day|bridge_registry/.test(src)]).toEqual([f, false]);
    }
  });
});

// ---------------------------------------------------------------------------
// 7. Kill switch: default OFF, empty allowlist, checked on every request
// ---------------------------------------------------------------------------
describe("7. config/voice_control kill switch", () => {
  async function linkedThenSwitch(config: Json | null) {
    await allowVoice([UID]);
    const tok = await link(UID);
    if (config === null) await db.doc("config/voice_control").delete();
    else await db.doc("config/voice_control").set(config);
    return tok;
  }

  test.each([
    ["no config doc (the default)", null],
    ["enabled false, empty allowlist", { enabled: false, allowlistUids: [] }],
    ["another account allowlisted", { enabled: false, allowlistUids: [OTHER] }],
  ])("%s: every directive gets INSUFFICIENT_PERMISSIONS and nothing is queued", async (_l, config) => {
    const { access_token } = await linkedThenSwitch(config);
    for (const d of [
      directive("Alexa.Discovery", "Discover", access_token),
      directive("Alexa.PowerController", "TurnOn", access_token, "lumina-main"),
      directive("Alexa.BrightnessController", "SetBrightness", access_token, "lumina-main", { brightness: 10 }),
      directive("Alexa", "ReportState", access_token, "lumina-main"),
    ]) {
      const r = await alexa(d);
      expect(errType(r)).toBe("INSUFFICIENT_PERMISSIONS");
      expect(r.event.payload.message).toBe("Voice control is not enabled for this account.");
    }
    expect(await commandDocs(UID)).toHaveLength(0);
  });

  test("a new link is refused while the account is not enabled", async () => {
    await db.doc("config/voice_control").delete();
    const res = await exchange(await mintCode(UID));
    expect(res.statusCode).toBe(400);
    expect(res.body).toEqual({ error: "invalid_grant" });
    expect((await db.doc(`users/${UID}/integrations/alexa`).get()).exists).toBe(false);
  });

  test("switching off never breaks an existing link: refresh still works", async () => {
    const { refresh_token } = await linkedThenSwitch(null);
    expect((await refreshGrant(refresh_token)).statusCode).toBe(200);
  });

  test("allowlisted account works", async () => {
    await allowVoice([UID]);
    bridgeCompletes(UID);
    const { access_token } = await link(UID);
    const r = await alexa(directive("Alexa.PowerController", "TurnOn", access_token, "lumina-main"));
    expect(r.event.header.name).toBe("Response");
  });
});

// ---------------------------------------------------------------------------
// 8. Unlinking revokes; stuck "Pending" clears
// ---------------------------------------------------------------------------
describe("8. unlink and Pending", () => {
  test("a successful link clears linkInitiated / initiatedAt", async () => {
    await allowVoice([UID]);
    await db.doc(`users/${UID}/integrations/alexa`).set({
      linkInitiated: true, initiatedAt: admin.firestore.Timestamp.fromMillis(Date.now() - 3 * 86_400_000),
    });
    await link(UID);
    const d = (await db.doc(`users/${UID}/integrations/alexa`).get()).data() as Json;
    expect(d.isLinked).toBe(true);
    expect(d.linkInitiated).toBeUndefined();
    expect(d.initiatedAt).toBeUndefined();
  });

  test("app Unlink (doc delete): directives stop at once; the trigger revokes the refresh token", async () => {
    await allowVoice([UID]);
    const { access_token, refresh_token } = await link(UID);
    const ref = db.doc(`users/${UID}/integrations/alexa`);
    const snap = await ref.get();
    await ref.delete();
    expect(errType(await alexa(directive("Alexa.Discovery", "Discover", access_token)))).toBe(
      "INVALID_AUTHORIZATION_CREDENTIAL");
    await idx.onVoiceIntegrationDeleted.run({ data: snap, params: { userId: UID, provider: "alexa" } });
    const rec = (await db.doc(`oauth_refresh_tokens/${sha256(refresh_token)}`).get()).data() as Json;
    expect(rec.active).toBe(false);
    expect((await refreshGrant(refresh_token)).body).toEqual({ error: "invalid_grant" });
  });

  test("the daily sweep clears stale Pending intents and nothing else", async () => {
    const old = admin.firestore.Timestamp.fromMillis(Date.now() - 2 * 86_400_000);
    const fresh = admin.firestore.Timestamp.fromMillis(Date.now() - 3_600_000);
    await db.doc(`users/${UID}/integrations/alexa`).set({ linkInitiated: true, initiatedAt: old }); // the bench account's shape
    await db.doc(`users/${NOBRIDGE}/integrations/alexa`).set({ linkInitiated: true, initiatedAt: fresh });
    await db.doc(`users/${WEBHOOK}/integrations/alexa`).set({ linkInitiated: true, initiatedAt: old, isLinked: true });
    await db.doc(`users/${OTHER}/integrations/google_home`).set({ linkInitiated: true, initiatedAt: old, isLinked: false });
    await db.doc(`users/${OTHER}/integrations/other_provider`).set({ linkInitiated: true, initiatedAt: old });

    await idx.sweepStaleVoiceLinks.run({});

    expect((await db.doc(`users/${UID}/integrations/alexa`).get()).exists).toBe(false);
    expect((await db.doc(`users/${NOBRIDGE}/integrations/alexa`).get()).get("linkInitiated")).toBe(true);
    const linked = (await db.doc(`users/${WEBHOOK}/integrations/alexa`).get()).data() as Json;
    expect(linked).toEqual({ isLinked: true });
    const g = (await db.doc(`users/${OTHER}/integrations/google_home`).get()).data() as Json;
    expect(g).toEqual({ isLinked: false });
    expect((await db.doc(`users/${OTHER}/integrations/other_provider`).get()).get("linkInitiated")).toBe(true);
  });
});
