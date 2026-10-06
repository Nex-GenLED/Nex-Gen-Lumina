/**
 * googleSmartHome.test.ts — zero-dependency tests for the Google Smart Home
 * fulfillment rewired through intentCore (node:test + node:assert; same pattern
 * as intentCore.test.ts). Firestore is faked in-memory, with an `autoOutcome`
 * knob that simulates the bridge/webhook completing a queued command so
 * awaitOutcome resolves fast and deterministically.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";

import { handleSync, handleExecute } from "../../src/voice/googleSmartHome";

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
    // Simulate the bridge/webhook driving a queued command to a terminal state.
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

const onOff = (on: boolean, cd: Data) => ({
  commands: [
    {
      devices: [{ id: "lumina-main", customData: cd }],
      execution: [{ command: "action.devices.commands.OnOff", params: { on } }],
    },
  ],
});

// ---------------------------------------------------------------------------
// SYNC
// ---------------------------------------------------------------------------
test("SYNC: primary device keeps legacy id + nickname set (continuity)", async () => {
  const s = baseStore();
  s.seed(`users/${UID}/scenes/sc1`, {
    type: "custom",
    name: "Sunset",
    custom_design: { brightness: 100, channels: [] },
  });
  s.seed(`users/${UID}/scenes/sc2`, {
    type: "library",
    name: "Aurora",
    brightness: 150,
    library_pattern: { colors: "[[0,255,0,0]]", effect_id: 1, speed: 100, intensity: 100 },
  });

  const res = await handleSync("r1", UID, asDb(s));
  const devices = res.payload.devices;
  assert.equal(devices.length, 3); // lumina-main + 2 scenes

  // Byte-identical to the legacy handleGoogleSync primary device (id + name).
  const primary = devices[0];
  assert.equal(primary.id, "lumina-main");
  assert.deepEqual(primary.name, {
    name: "My House",
    defaultNames: ["Lumina Lights", "House Lights"],
    nicknames: ["My House", "outdoor lights", "house lights"],
  });

  const scenes = devices.filter(
    (d: { type: string }) => d.type === "action.devices.types.SCENE"
  );
  assert.equal(scenes.length, 2);
});

test("SYNC: flag OFF → deviceOffline errorCode (never authFailure/unlink)", async () => {
  const s = baseStore();
  s.seed("config/voice_control", { enabled: false });
  const res = await handleSync("r1", UID, asDb(s));
  assert.equal(res.payload.errorCode, "deviceOffline");
  assert.equal(res.payload.devices, undefined);
});

// ---------------------------------------------------------------------------
// EXECUTE — canonical command docs
// ---------------------------------------------------------------------------
test("EXECUTE OnOff → canonical setState doc (string payload) + SUCCESS", async () => {
  const s = baseStore();
  s.autoOutcome = "completed";
  const payload = onOff(true, {
    userId: UID,
    type: "main",
    controllerId: "ctrlA",
    controllerIp: "192.168.1.50",
  });
  const res = await handleExecute("r1", UID, payload, asDb(s), 1000);
  assert.deepEqual(res.payload.commands[0], {
    ids: ["lumina-main"],
    status: "SUCCESS",
    states: { on: true },
  });
  const cmds = commandDocs(s);
  assert.equal(cmds.length, 1);
  const c = cmds[0];
  assert.equal(typeof c.payload, "string"); // #84
  assert.equal(c.payload, '{"on":true}');
  assert.equal(c.type, "setState");
  assert.equal(c.controllerId, "ctrlA");
  assert.equal(c.controllerIp, "192.168.1.50");
  assert.equal(c.webhookUrl, WEBHOOK);
  assert.equal(c.source, "voice_google");
});

test("EXECUTE BrightnessAbsolute(50) → {bri:128} canonical doc + SUCCESS", async () => {
  const s = baseStore();
  s.autoOutcome = "completed";
  const payload = {
    commands: [
      {
        devices: [
          {
            id: "lumina-main",
            customData: { userId: UID, controllerId: "ctrlA", controllerIp: "192.168.1.50" },
          },
        ],
        execution: [
          { command: "action.devices.commands.BrightnessAbsolute", params: { brightness: 50 } },
        ],
      },
    ],
  };
  const res = await handleExecute("r1", UID, payload, asDb(s), 1000);
  assert.equal(res.payload.commands[0].status, "SUCCESS");
  assert.deepEqual(res.payload.commands[0].states, { on: true, brightness: 50 });
  const c = commandDocs(s)[0];
  assert.equal(typeof c.payload, "string");
  assert.equal(c.payload, '{"bri":128}');
  assert.equal(c.type, "setState");
});

test("EXECUTE ActivateScene → canonical applyJson doc, fanned out + SUCCESS", async () => {
  const s = baseStore();
  s.autoOutcome = "completed";
  s.seed(`users/${UID}/scenes/scSys`, {
    type: "system",
    name: "Lights Off",
    wled_payload: JSON.stringify({ on: false }),
  });
  const payload = {
    commands: [
      {
        devices: [
          { id: "scene-scSys", customData: { userId: UID, type: "scene", sceneId: "scSys" } },
        ],
        execution: [{ command: "action.devices.commands.ActivateScene", params: {} }],
      },
    ],
  };
  const res = await handleExecute("r1", UID, payload, asDb(s), 1000);
  assert.equal(res.payload.commands[0].status, "SUCCESS");
  const cmds = commandDocs(s);
  assert.equal(cmds.length, 1); // unscoped → fanned out to the one controller
  const c = cmds[0];
  assert.equal(c.type, "applyJson");
  assert.equal(typeof c.payload, "string");
  assert.equal(c.payload, '{"on":false}');
  assert.equal(c.controllerId, "ctrlA");
});

// ---------------------------------------------------------------------------
// EXECUTE — flag, outcome mappings
// ---------------------------------------------------------------------------
test("EXECUTE flag OFF → deviceOffline, nothing written", async () => {
  const s = baseStore();
  s.seed("config/voice_control", { enabled: false });
  const res = await handleExecute("r1", UID, onOff(true, { controllerId: "ctrlA" }), asDb(s), 100);
  assert.equal(res.payload.commands[0].status, "ERROR");
  assert.equal(res.payload.commands[0].errorCode, "deviceOffline");
  assert.equal(commandDocs(s).length, 0);
});

test("EXECUTE failed outcome → ERROR (deviceOffline for offline, hardError otherwise)", async () => {
  const s1 = baseStore();
  s1.autoOutcome = "failed";
  s1.autoError = "device offline";
  const r1 = await handleExecute("r1", UID, onOff(true, { controllerId: "ctrlA" }), asDb(s1), 1000);
  assert.equal(r1.payload.commands[0].status, "ERROR");
  assert.equal(r1.payload.commands[0].errorCode, "deviceOffline");

  const s2 = baseStore();
  s2.autoOutcome = "failed";
  s2.autoError = "bad state";
  const r2 = await handleExecute("r2", UID, onOff(true, { controllerId: "ctrlA" }), asDb(s2), 1000);
  assert.equal(r2.payload.commands[0].errorCode, "hardError");
});

test("EXECUTE optimistic (timeout) → SUCCESS", async () => {
  const s = baseStore();
  s.autoOutcome = null; // command stays pending → awaitOutcome times out
  const res = await handleExecute("r1", UID, onOff(true, { controllerId: "ctrlA" }), asDb(s), 30);
  assert.equal(res.payload.commands[0].status, "SUCCESS");
});

// ---------------------------------------------------------------------------
// Legacy-shape-absent guard
// ---------------------------------------------------------------------------
test("no legacy command shape (power/brightness/primary) in index.js or src", () => {
  const functionsRoot = path.resolve(__dirname, "../../..");
  const indexJs = fs.readFileSync(path.join(functionsRoot, "index.js"), "utf8");

  const srcTexts: string[] = [];
  const walk = (dir: string) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const fp = path.join(dir, e.name);
      if (e.isDirectory()) walk(fp);
      else if (e.name.endsWith(".ts")) srcTexts.push(fs.readFileSync(fp, "utf8"));
    }
  };
  walk(path.join(functionsRoot, "src"));
  const combined = indexJs + "\n" + srcTexts.join("\n");

  assert.doesNotMatch(
    combined,
    /controllerId:\s*["']primary["']/,
    "legacy hardcoded primary controllerId must be gone"
  );
  assert.doesNotMatch(combined, /type:\s*["']power["']/, "legacy type 'power' must be gone");
  assert.doesNotMatch(
    combined,
    /type:\s*["']brightness["']/,
    "legacy type 'brightness' must be gone"
  );
  assert.doesNotMatch(
    indexJs,
    /collection\(["']commands["']\)\.add\(/,
    "no legacy .add() command write in index.js"
  );
});
