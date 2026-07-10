/**
 * alexaSmartHome.test.ts — zero-dependency tests for the Alexa Smart Home
 * fulfillment (node:test + node:assert; same fake-Firestore + autoOutcome
 * pattern as googleSmartHome.test.ts). Access tokens are the self-signed JWTs
 * issued by alexaToken (B-3b decision a), verified in-handler.
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import { handleAlexaDirective } from "../../src/voice/alexaSmartHome";
import { signAlexaJwt, verifyAlexaJwt } from "../../src/voice/alexaJwt";

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
  constructor(public store: Store, public path: string) {}
  doc(id?: string) {
    const r = id ?? this.store.nextAutoId();
    return new DocRef(this.store, `${this.path}/${r}`, r);
  }
  async get() {
    const prefix = this.path + "/";
    const docs: DocSnap[] = [];
    for (const [p, d] of this.store.docs) {
      if (p.startsWith(prefix)) {
        const rest = p.slice(prefix.length);
        if (!rest.includes("/")) docs.push(new DocSnap(rest, d));
      }
    }
    return { docs };
  }
}

class Fake {
  constructor(public store: Store) {}
  collection(n: string) {
    return new ColRef(this.store, n);
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const asDb = (s: Store): any => new Fake(s);

const UID = "u1";
const WEBHOOK = "https://home.example.com/wled";
const SECRET = "test-secret";
const TOKEN = signAlexaJwt({ uid: UID, client_id: "lumina-alexa-client" }, SECRET);

function baseStore(): Store {
  const s = new Store();
  s.seed("config/voice_control", { enabled: true });
  s.seed(`users/${UID}`, { webhookUrl: WEBHOOK, propertyName: "My House" });
  s.seed(`users/${UID}/controllers/ctrlA`, {
    ip: "192.168.1.50",
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

const COOKIE_MAIN = { userId: UID, type: "main", controllerId: "ctrlA", controllerIp: "192.168.1.50" };
const COOKIE_SCENE = { userId: UID, type: "scene", sceneId: "scSys" };

function discovery(token: unknown) {
  return {
    directive: {
      header: { namespace: "Alexa.Discovery", name: "Discover" },
      payload: { scope: { type: "BearerToken", token } },
    },
  };
}
function controlDirective(namespace: string, name: string, token: unknown, cookie: Data, payload: Data = {}) {
  return {
    directive: {
      header: { namespace, name, correlationToken: "ct1" },
      endpoint: {
        endpointId: cookie.type === "scene" ? "scene-scSys" : "lumina-main",
        scope: { type: "BearerToken", token },
        cookie,
      },
      payload,
    },
  };
}

// ---------------------------------------------------------------------------
// JWT verify path (decision a coverage)
// ---------------------------------------------------------------------------
test("alexaJwt: sign→verify round-trips; wrong secret / malformed rejected", () => {
  const claims = verifyAlexaJwt(TOKEN, SECRET);
  assert.ok(claims);
  assert.equal(claims.uid, UID);
  assert.equal(verifyAlexaJwt(TOKEN, "wrong-secret"), null);
  assert.equal(verifyAlexaJwt("a.b.c", SECRET), null);
  // expired token (exp in the past)
  const expired = signAlexaJwt({ uid: UID }, SECRET, -10);
  assert.equal(verifyAlexaJwt(expired, SECRET), null);
});

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------
test("Discovery: LIGHT endpoint (Power+Brightness) + SCENE endpoint (SceneController)", async () => {
  const s = baseStore();
  s.seed(`users/${UID}/scenes/scSys`, {
    type: "system",
    name: "Lights Off",
    wled_payload: JSON.stringify({ on: false }),
  });
  // NOTE: system scenes are skipped by resolveScenes discovery; add a real one.
  s.seed(`users/${UID}/scenes/scLib`, {
    type: "library",
    name: "Aurora",
    brightness: 150,
    library_pattern: { colors: "[[0,255,0,0]]", effect_id: 1, speed: 100, intensity: 100 },
  });

  const res = await handleAlexaDirective(discovery(TOKEN), SECRET, asDb(s));
  assert.equal(res.event.header.namespace, "Alexa.Discovery");
  assert.equal(res.event.header.name, "Discover.Response");
  const eps = res.event.payload.endpoints;

  const main = eps.find((e: { endpointId: string }) => e.endpointId === "lumina-main");
  assert.ok(main);
  const ifaces = main.capabilities.map((c: { interface: string }) => c.interface);
  assert.ok(ifaces.includes("Alexa.PowerController"));
  assert.ok(ifaces.includes("Alexa.BrightnessController"));
  assert.equal(main.friendlyName, "My House");
  assert.equal(main.cookie.controllerId, "ctrlA");

  const scene = eps.find((e: { endpointId: string }) => e.endpointId === "scene-scLib");
  assert.ok(scene);
  assert.ok(
    scene.capabilities.some((c: { interface: string }) => c.interface === "Alexa.SceneController")
  );
  assert.equal(scene.cookie.sceneId, "scLib");
});

test("Discovery: flag OFF → zero endpoints (non-unlinking)", async () => {
  const s = baseStore();
  s.seed("config/voice_control", { enabled: false });
  const res = await handleAlexaDirective(discovery(TOKEN), SECRET, asDb(s));
  assert.equal(res.event.header.name, "Discover.Response");
  assert.deepEqual(res.event.payload.endpoints, []);
});

// ---------------------------------------------------------------------------
// Control directives → canonical command docs
// ---------------------------------------------------------------------------
test("PowerController TurnOn → canonical setState doc + Response(powerState ON)", async () => {
  const s = baseStore();
  s.autoOutcome = "completed";
  const d = controlDirective("Alexa.PowerController", "TurnOn", TOKEN, COOKIE_MAIN);
  const res = await handleAlexaDirective(d, SECRET, asDb(s), 1000);

  assert.equal(res.event.header.namespace, "Alexa");
  assert.equal(res.event.header.name, "Response");
  assert.equal(res.event.header.correlationToken, "ct1");
  assert.equal(res.event.endpoint.endpointId, "lumina-main");
  assert.equal(res.context.properties[0].namespace, "Alexa.PowerController");
  assert.equal(res.context.properties[0].value, "ON");

  const c = commandDocs(s)[0];
  assert.equal(typeof c.payload, "string"); // #84
  assert.equal(c.payload, '{"on":true}');
  assert.equal(c.type, "setState");
  assert.equal(c.controllerId, "ctrlA");
  assert.equal(c.controllerIp, "192.168.1.50");
  assert.equal(c.webhookUrl, WEBHOOK);
  assert.equal(c.source, "voice_alexa");
});

test("BrightnessController SetBrightness(50) → {bri:128} canonical doc + Response", async () => {
  const s = baseStore();
  s.autoOutcome = "completed";
  const d = controlDirective("Alexa.BrightnessController", "SetBrightness", TOKEN, COOKIE_MAIN, {
    brightness: 50,
  });
  const res = await handleAlexaDirective(d, SECRET, asDb(s), 1000);
  assert.equal(res.event.header.name, "Response");
  assert.equal(res.context.properties[0].namespace, "Alexa.BrightnessController");
  assert.equal(res.context.properties[0].value, 50);
  const c = commandDocs(s)[0];
  assert.equal(typeof c.payload, "string");
  assert.equal(c.payload, '{"bri":128}');
});

test("SceneController Activate → canonical applyJson doc (fanout) + ActivationStarted", async () => {
  const s = baseStore();
  s.autoOutcome = "completed";
  s.seed(`users/${UID}/scenes/scSys`, {
    type: "system",
    name: "Lights Off",
    wled_payload: JSON.stringify({ on: false }),
  });
  const d = controlDirective("Alexa.SceneController", "Activate", TOKEN, COOKIE_SCENE);
  const res = await handleAlexaDirective(d, SECRET, asDb(s), 1000);
  assert.equal(res.event.header.namespace, "Alexa.SceneController");
  assert.equal(res.event.header.name, "ActivationStarted");
  assert.equal(res.event.endpoint.endpointId, "scene-scSys");

  const cmds = commandDocs(s);
  assert.equal(cmds.length, 1); // fanned out to the one controller
  assert.equal(cmds[0].type, "applyJson");
  assert.equal(cmds[0].payload, '{"on":false}');
  assert.equal(cmds[0].controllerId, "ctrlA");
});

// ---------------------------------------------------------------------------
// Auth + flag + outcome mappings
// ---------------------------------------------------------------------------
test("malformed/expired token → INVALID_AUTHORIZATION_CREDENTIAL, nothing written", async () => {
  const s = baseStore();
  const garbage = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", "not-a-jwt", COOKIE_MAIN),
    SECRET,
    asDb(s),
    100
  );
  assert.equal(garbage.event.header.name, "ErrorResponse");
  assert.equal(garbage.event.payload.type, "INVALID_AUTHORIZATION_CREDENTIAL");

  const expiredTok = signAlexaJwt({ uid: UID }, SECRET, -10);
  const expired = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", expiredTok, COOKIE_MAIN),
    SECRET,
    asDb(s),
    100
  );
  assert.equal(expired.event.payload.type, "INVALID_AUTHORIZATION_CREDENTIAL");
  assert.equal(commandDocs(s).length, 0);
});

test("control directive flag OFF → ENDPOINT_UNREACHABLE (never disables skill)", async () => {
  const s = baseStore();
  s.seed("config/voice_control", { enabled: false });
  const res = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, COOKIE_MAIN),
    SECRET,
    asDb(s),
    100
  );
  assert.equal(res.event.header.name, "ErrorResponse");
  assert.equal(res.event.payload.type, "ENDPOINT_UNREACHABLE");
  assert.equal(commandDocs(s).length, 0);
});

test("failed outcome → ErrorResponse (ENDPOINT_UNREACHABLE for offline, INTERNAL_ERROR otherwise)", async () => {
  const s1 = baseStore();
  s1.autoOutcome = "failed";
  s1.autoError = "device offline";
  const r1 = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, COOKIE_MAIN),
    SECRET,
    asDb(s1),
    1000
  );
  assert.equal(r1.event.payload.type, "ENDPOINT_UNREACHABLE");

  const s2 = baseStore();
  s2.autoOutcome = "failed";
  s2.autoError = "bad state";
  const r2 = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, COOKIE_MAIN),
    SECRET,
    asDb(s2),
    1000
  );
  assert.equal(r2.event.payload.type, "INTERNAL_ERROR");
});

test("optimistic (timeout) → success Response", async () => {
  const s = baseStore();
  s.autoOutcome = null; // stays pending → awaitOutcome times out
  const res = await handleAlexaDirective(
    controlDirective("Alexa.PowerController", "TurnOn", TOKEN, COOKIE_MAIN),
    SECRET,
    asDb(s),
    30
  );
  assert.equal(res.event.header.name, "Response");
  assert.equal(res.context.properties[0].value, "ON");
});
