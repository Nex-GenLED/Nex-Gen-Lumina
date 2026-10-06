/**
 * alexaSmartHome.test.ts — zero-dependency tests for the Alexa Smart Home
 * fulfillment (node:test + node:assert; same fake-Firestore + autoOutcome
 * pattern as googleSmartHome.test.ts). B-3c contract: the access token names
 * only a link (`lid`); the link record names the user; the kill switch is
 * checked on every directive; nothing identifying is sent to Amazon.
 * The emulator suite (test/emulator/voiceAlexaLink.emulator.test.ts) drives
 * the same handler through index.js against real Firestore.
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import { handleAlexaDirective } from "../../src/voice/alexaSmartHome";
import {
  opaqueEndpointKey,
  signAlexaAccessToken,
  verifyAlexaAccessToken,
} from "../../src/voice/alexaJwt";

// ---------------------------------------------------------------------------
// In-memory Firestore fake with command auto-completion
// ---------------------------------------------------------------------------
type Data = Record<string, unknown>;

class DocSnap {
  constructor(public id: string, private _data: Data | undefined) {}
  get exists() {
    return this._data !== undefined;
  }
  data() {
    return this._data;
  }
  get(field: string) {
    return this._data?.[field];
  }
}

class Store {
  docs = new Map<string, Data>();
  listeners = new Map<number, { path: string; cb: (s: DocSnap) => void }>();
  autoOutcome: "completed" | "failed" | null = null;
  autoError = "device offline";
  private autoCounter = 0;
  private listenerCounter = 0;

  seed(p: string, d: Data) {
    this.docs.set(p, d);
  }
  nextAutoId() {
    return `auto-${++this.autoCounter}`;
  }
  setDoc(p: string, d: Data) {
    this.docs.set(p, d);
    const id = p.substring(p.lastIndexOf("/") + 1);
    for (const l of this.listeners.values()) {
      if (l.path === p) l.cb(new DocSnap(id, d));
    }
    if (p.includes("/commands/") && d.status === "pending" && this.autoOutcome) {
      setImmediate(() => {
        const cur = this.docs.get(p);
        if (!cur) return;
        this.setDoc(
          p,
          this.autoOutcome === "completed"
            ? { ...cur, status: "completed" }
            : { ...cur, status: "failed", error: this.autoError }
        );
      });
    }
  }
  subscribe(p: string, id: string, cb: (s: DocSnap) => void) {
    const key = ++this.listenerCounter;
    this.listeners.set(key, { path: p, cb });
    setImmediate(() => {
      if (this.listeners.has(key)) cb(new DocSnap(id, this.docs.get(p)));
    });
    return () => {
      this.listeners.delete(key);
    };
  }
}

class DocRef {
  constructor(public store: Store, public path: string, public id: string) {}
  collection(n: string) {
    return new ColRef(this.store, `${this.path}/${n}`);
  }
  async get() {
    return new DocSnap(this.id, this.store.docs.get(this.path));
  }
  async set(d: Data) {
    this.store.setDoc(this.path, d);
  }
  onSnapshot(onNext: (s: DocSnap) => void, _onErr?: (e: Error) => void) {
    return this.store.subscribe(this.path, this.id, onNext);
  }
}

class ColRef {
  private filters: Array<[string, unknown]> = [];
  constructor(public store: Store, public path: string) {}
  doc(id?: string) {
    const r = id ?? this.store.nextAutoId();
    return new DocRef(this.store, `${this.path}/${r}`, r);
  }
  where(field: string, _op: string, value: unknown) {
    const c = new ColRef(this.store, this.path);
    c.filters = [...this.filters, [field, value]];
    return c;
  }
  limit(_n: number) {
    return this;
  }
  async get() {
    const prefix = this.path + "/";
    const docs: DocSnap[] = [];
    for (const [p, d] of this.store.docs) {
      if (!p.startsWith(prefix)) continue;
      const rest = p.slice(prefix.length);
      if (rest.includes("/")) continue;
      if (this.filters.every(([f, v]) => d[f] === v)) docs.push(new DocSnap(rest, d));
    }
    return { docs, empty: docs.length === 0, size: docs.length };
  }
}

class Fake {
  constructor(public store: Store) {}
  collection(n: string) {
    return new ColRef(this.store, n);
  }
  async getAll(...refs: DocRef[]) {
    return Promise.all(refs.map((r) => r.get()));
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const asDb = (s: Store): any => new Fake(s);

const UID = "u1";
const LID = "link-1";
const WEBHOOK = "https://home.example.com/wled";
const SECRET = "node-test-jwt-secret-0000000000000000000000";
const TOKEN = signAlexaAccessToken({ lid: LID }, SECRET);
const FAR = { toMillis: () => Date.now() + 1e10 };

function baseStore(): Store {
  const s = new Store();
  s.seed("config/voice_control", { enabled: false, allowlistUids: [UID] });
  s.seed(`oauth_refresh_tokens/${LID}`, {
    userId: UID, provider: "alexa", iss: "lumina-alexa", aud: "cid", active: true, expiresAt: FAR,
  });
  s.seed(`users/${UID}/integrations/alexa`, { isLinked: true });
  s.seed(`users/${UID}`, { webhookUrl: WEBHOOK, propertyName: "My House" });
  s.seed(`users/${UID}/controllers/ctrlA`, {
    ip: "192.0.2.50",
    name: "Front",
    created_at: { toMillis: () => 1000 },
  });
  return s;
}

function commandDocs(s: Store): Data[] {
  const out: Data[] = [];
  for (const [p, d] of s.docs) {
    if (p.includes(`users/${UID}/commands/`)) out.push(d);
  }
  return out;
}

const SCENE_EP = `scn-${opaqueEndpointKey(SECRET, UID, "scn", "scLib")}`;

function discovery(token: unknown) {
  return {
    directive: {
      header: { namespace: "Alexa.Discovery", name: "Discover" },
      payload: { scope: { type: "BearerToken", token } },
    },
  };
}
function controlDirective(namespace: string, name: string, token: unknown, endpointId: string, payload: Data = {}) {
  return {
    directive: {
      header: { namespace, name, correlationToken: "ct1" },
      endpoint: { endpointId, scope: { type: "BearerToken", token } },
      payload,
    },
  };
}
function seedScene(s: Store) {
  s.seed(`users/${UID}/scenes/scLib`, {
    type: "library",
    name: "Aurora",
    brightness: 150,
    library_pattern: { colors: "[[0,255,0,0]]", effect_id: 1, speed: 100, intensity: 100 },
  });
}

// ---------------------------------------------------------------------------
test("access token: names only the link; verify reports expired vs invalid", () => {
  const r = verifyAlexaAccessToken(TOKEN, SECRET);
  assert.ok(r.ok);
  assert.equal(r.ok && r.claims.lid, LID);
  assert.equal(r.ok && (r.claims as unknown as Data).uid, undefined);
  assert.deepEqual(verifyAlexaAccessToken(TOKEN, "another-secret-000000000000000000000"), { ok: false, reason: "invalid" });
  const old = signAlexaAccessToken({ lid: LID }, SECRET, Math.floor(Date.now() / 1000) - 7200);
  assert.deepEqual(verifyAlexaAccessToken(old, SECRET), { ok: false, reason: "expired" });
});

test("Discovery: six required fields only, opaque ids, the user's own names", async () => {
  const s = baseStore();
  seedScene(s);
  s.seed(`users/${UID}/scenes/scSys`, { type: "system", name: "Lights Off", wled_payload: "{}" });
  const res = await handleAlexaDirective(discovery(TOKEN), SECRET, asDb(s));
  assert.equal(res.event.header.name, "Discover.Response");
  const eps = res.event.payload.endpoints;
  assert.deepEqual(eps.map((e: Data) => e.endpointId), ["lumina-main", SCENE_EP]);
  for (const e of eps) {
    assert.deepEqual(Object.keys(e).sort(), [
      "capabilities", "description", "displayCategories", "endpointId", "friendlyName", "manufacturerName",
    ]);
  }
  assert.equal(eps[0].friendlyName, "Front"); // never the property name
  assert.equal(eps[1].friendlyName, "Aurora");
  const text = JSON.stringify(res);
  for (const leak of [UID, "ctrlA", "scLib", "192.0.2.50", "My House", WEBHOOK]) {
    assert.ok(!text.includes(leak), `leaks ${leak}`);
  }
});

test("kill switch OFF: Discover and control get INSUFFICIENT_PERMISSIONS, nothing written", async () => {
  const s = baseStore();
  s.seed("config/voice_control", { enabled: false, allowlistUids: [] });
  const d = await handleAlexaDirective(discovery(TOKEN), SECRET, asDb(s));
  assert.equal(d.event.header.name, "ErrorResponse");
  assert.equal(d.event.payload.type, "INSUFFICIENT_PERMISSIONS");
  const c = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, "lumina-main"), SECRET, asDb(s), 50);
  assert.equal(c.event.payload.type, "INSUFFICIENT_PERMISSIONS");
  assert.equal(c.event.endpoint.endpointId, "lumina-main");
  assert.equal(c.event.header.correlationToken, "ct1");
  assert.equal(commandDocs(s).length, 0);
});

test("PowerController TurnOn → the app's command shape + Response(powerState ON)", async () => {
  const s = baseStore();
  s.autoOutcome = "completed";
  const res = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, "lumina-main"), SECRET, asDb(s), 1000);
  assert.equal(res.event.header.name, "Response");
  assert.equal(res.context.properties[0].value, "ON");
  const docs = commandDocs(s);
  assert.equal(docs.length, 1);
  assert.deepEqual(Object.keys(docs[0]).sort(), [
    "controllerId", "controllerIp", "createdAt", "payload", "source", "status", "type", "webhookUrl",
  ]);
  assert.equal(docs[0].type, "setState");
  assert.equal(docs[0].payload, JSON.stringify({ on: true }));
  assert.equal(docs[0].source, "voice_alexa");
});

test("BrightnessController SetBrightness(50) → {bri:128}", async () => {
  const s = baseStore();
  s.autoOutcome = "completed";
  await handleAlexaDirective(
    controlDirective("Alexa.BrightnessController", "SetBrightness", TOKEN, "lumina-main", { brightness: 50 }),
    SECRET, asDb(s), 1000);
  assert.equal(commandDocs(s)[0].payload, JSON.stringify({ bri: 128 }));
});

test("SceneController Activate → applyJson fan-out + ActivationStarted", async () => {
  const s = baseStore();
  seedScene(s);
  s.seed(`users/${UID}/controllers/ctrlB`, { ip: "192.0.2.51", name: "Back", created_at: { toMillis: () => 2000 } });
  s.autoOutcome = "completed";
  const res = await handleAlexaDirective(
    controlDirective("Alexa.SceneController", "Activate", TOKEN, SCENE_EP), SECRET, asDb(s), 1000);
  assert.equal(res.event.header.name, "ActivationStarted");
  const docs = commandDocs(s);
  assert.equal(docs.length, 2);
  assert.ok(docs.every((d) => d.type === "applyJson" && typeof d.payload === "string"));
});

test("bad token → INVALID; expired → EXPIRED; nothing written", async () => {
  const s = baseStore();
  const bad = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", "a.b.c", "lumina-main"), SECRET, asDb(s));
  assert.equal(bad.event.payload.type, "INVALID_AUTHORIZATION_CREDENTIAL");
  const old = signAlexaAccessToken({ lid: LID }, SECRET, Math.floor(Date.now() / 1000) - 7200);
  const exp = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", old, "lumina-main"), SECRET, asDb(s));
  assert.equal(exp.event.payload.type, "EXPIRED_AUTHORIZATION_CREDENTIAL");
  assert.equal(commandDocs(s).length, 0);
});

test("unlinked (integration doc gone) or revoked record → INVALID", async () => {
  const s = baseStore();
  s.docs.delete(`users/${UID}/integrations/alexa`);
  const a = await handleAlexaDirective(discovery(TOKEN), SECRET, asDb(s));
  assert.equal(a.event.payload.type, "INVALID_AUTHORIZATION_CREDENTIAL");
  const t = baseStore();
  t.seed(`oauth_refresh_tokens/${LID}`, { ...(t.docs.get(`oauth_refresh_tokens/${LID}`) as Data), active: false });
  const b = await handleAlexaDirective(discovery(TOKEN), SECRET, asDb(t));
  assert.equal(b.event.payload.type, "INVALID_AUTHORIZATION_CREDENTIAL");
});

test("no signing key → INTERNAL_ERROR", async () => {
  const res = await handleAlexaDirective(discovery(TOKEN), null, asDb(baseStore()));
  assert.equal(res.event.payload.type, "INTERNAL_ERROR");
});

test("bridge mode without a paired bridge → ENDPOINT_UNREACHABLE, nothing queued", async () => {
  const s = baseStore();
  s.seed(`users/${UID}`, { webhookUrl: "" });
  const res = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, "lumina-main"), SECRET, asDb(s), 50);
  assert.equal(res.event.payload.type, "ENDPOINT_UNREACHABLE");
  assert.equal(commandDocs(s).length, 0);

  s.seed("bridge_registry/b1", { pairedUid: UID });
  s.autoOutcome = "completed";
  const ok = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, "lumina-main"), SECRET, asDb(s), 1000);
  assert.equal(ok.event.header.name, "Response");
  assert.equal(commandDocs(s).length, 1);
});

test("failed outcome → ENDPOINT_UNREACHABLE for offline, INTERNAL_ERROR otherwise", async () => {
  const s = baseStore();
  s.autoOutcome = "failed";
  s.autoError = "controller offline";
  const a = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, "lumina-main"), SECRET, asDb(s), 1000);
  assert.equal(a.event.payload.type, "ENDPOINT_UNREACHABLE");
  s.autoError = "bad payload";
  const b = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOff", TOKEN, "lumina-main"), SECRET, asDb(s), 1000);
  assert.equal(b.event.payload.type, "INTERNAL_ERROR");
});

test("optimistic (timeout) → success Response", async () => {
  const s = baseStore();
  const res = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOff", TOKEN, "lumina-main"), SECRET, asDb(s), 30);
  assert.equal(res.event.header.name, "Response");
});

test("unknown or foreign endpoint id → NO_SUCH_ENDPOINT", async () => {
  const s = baseStore();
  const foreign = `ctl-${opaqueEndpointKey(SECRET, "someone-else", "ctl", "ctrlA")}`;
  const res = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, foreign), SECRET, asDb(s), 50);
  assert.equal(res.event.payload.type, "NO_SUCH_ENDPOINT");
  assert.equal(commandDocs(s).length, 0);
});
