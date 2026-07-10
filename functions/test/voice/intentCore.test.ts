/**
 * intentCore.test.ts — zero-dependency tests for the voice command core.
 *
 * Runs on Node 20's built-in test runner (node:test + node:assert) — NO jest,
 * ts-jest, or any new dependency. Compiled by the existing `tsc` build to
 * lib/voice/intentCore.test.js and executed via `node --test lib/`.
 *
 * Firestore is faked in-memory (only the narrow surface intentCore uses), so no
 * emulator is needed. Scene-payload parity fixtures are derived from the Dart
 * sources cited in intentCore.ts (Scene.toWledPayload / CustomDesign.toWledPayload)
 * — key order matches so the strings are byte-identical to Dart jsonEncode.
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  executeIntent,
  awaitOutcome,
  readVoiceControlEnabled,
  resolveActivatableScenes,
} from "../../src/voice/intentCore";

// ---------------------------------------------------------------------------
// In-memory Firestore fake (collection/doc/get/set/onSnapshot only)
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
  private autoCounter = 0;
  private listenerCounter = 0;

  seed(path: string, data: Data) {
    this.docs.set(path, data);
  }
  nextAutoId() {
    return `auto-${++this.autoCounter}`;
  }
  setDoc(path: string, data: Data) {
    this.docs.set(path, data);
    const id = path.substring(path.lastIndexOf("/") + 1);
    for (const l of this.listeners.values()) {
      if (l.path === path) l.cb(new DocSnap(id, data));
    }
  }
  subscribe(path: string, id: string, cb: (s: DocSnap) => void): () => void {
    const key = ++this.listenerCounter;
    this.listeners.set(key, { path, cb });
    setImmediate(() => {
      if (this.listeners.has(key)) cb(new DocSnap(id, this.docs.get(path)));
    });
    return () => {
      this.listeners.delete(key);
    };
  }
  get listenerCount() {
    return this.listeners.size;
  }
}

class DocRef {
  constructor(public store: Store, public path: string, public id: string) {}
  collection(name: string) {
    return new ColRef(this.store, `${this.path}/${name}`);
  }
  async get() {
    return new DocSnap(this.id, this.store.docs.get(this.path));
  }
  async set(data: Data) {
    this.store.setDoc(this.path, data);
  }
  onSnapshot(onNext: (s: DocSnap) => void, _onError?: (e: Error) => void) {
    return this.store.subscribe(this.path, this.id, onNext);
  }
}

class ColRef {
  constructor(public store: Store, public path: string) {}
  doc(id?: string) {
    const realId = id ?? this.store.nextAutoId();
    return new DocRef(this.store, `${this.path}/${realId}`, realId);
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
  collection(name: string) {
    return new ColRef(this.store, name);
  }
}

// Cast helpers — the fake structurally covers the used Firestore surface.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const asDb = (s: Store): any => new Fake(s);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const path = (ref: unknown): string => (ref as any).path as string;

const UID = "u1";
const WEBHOOK = "https://home.example.com/wled";

/** A store with the flag ON, a user profile, and one controller. */
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

function readCmd(s: Store, ref: unknown): Data {
  const d = s.docs.get(path(ref));
  assert.ok(d, `expected a command doc at ${path(ref)}`);
  return d as Data;
}

// ---------------------------------------------------------------------------
// 1. Byte-correct command docs — POWER / BRIGHTNESS
// ---------------------------------------------------------------------------
test("POWER_ON writes a canonical setState doc with a STRING payload", async () => {
  const s = baseStore();
  const res = await executeIntent({
    uid: UID,
    controllerId: "ctrlA",
    intent: { kind: "POWER_ON" },
    source: "voice_google",
    db: asDb(s),
    voiceRequestId: "vr-1",
  });
  assert.ok(res.ok);
  assert.equal(res.commandRefs.length, 1);
  const cmd = readCmd(s, res.commandRefs[0]);
  assert.equal(typeof cmd.payload, "string"); // #84
  assert.equal(cmd.payload, '{"on":true}');
  assert.equal(cmd.type, "setState");
  assert.equal(cmd.controllerId, "ctrlA");
  assert.equal(cmd.controllerIp, "192.168.1.50");
  assert.equal(cmd.webhookUrl, WEBHOOK);
  assert.equal(cmd.status, "pending");
  assert.equal(cmd.source, "voice_google");
  assert.equal(cmd.voiceRequestId, "vr-1");
  assert.notEqual(cmd.createdAt, undefined);
});

test("POWER_OFF writes {on:false}", async () => {
  const s = baseStore();
  const res = await executeIntent({
    uid: UID,
    controllerId: "ctrlA",
    intent: { kind: "POWER_OFF" },
    source: "voice_alexa",
    db: asDb(s),
  });
  assert.ok(res.ok);
  const cmd = readCmd(s, res.commandRefs[0]);
  assert.equal(cmd.payload, '{"on":false}');
  assert.equal(cmd.source, "voice_alexa");
});

test("SET_BRIGHTNESS(50) → bri 128 (rounded), string payload", async () => {
  const s = baseStore();
  const res = await executeIntent({
    uid: UID,
    controllerId: "ctrlA",
    intent: { kind: "SET_BRIGHTNESS", level: 50 },
    source: "voice_google",
    db: asDb(s),
  });
  assert.ok(res.ok);
  const cmd = readCmd(s, res.commandRefs[0]);
  assert.equal(typeof cmd.payload, "string");
  assert.equal(cmd.payload, '{"bri":128}');
  assert.equal(cmd.type, "setState");
});

// ---------------------------------------------------------------------------
// 2. Scene fixture-parity (TS output === Dart-derived fixture JSON)
// ---------------------------------------------------------------------------
async function activateAndReadPayload(s: Store, sceneId: string): Promise<string> {
  const res = await executeIntent({
    uid: UID,
    controllerId: "ctrlA",
    intent: { kind: "ACTIVATE_SCENE", sceneId },
    source: "voice_google",
    db: asDb(s),
  });
  assert.ok(res.ok, "scene activation should succeed");
  const cmd = readCmd(s, res.commandRefs[0]);
  assert.equal(cmd.type, "applyJson");
  assert.equal(typeof cmd.payload, "string");
  return cmd.payload as string;
}

test("custom scene payload === Dart CustomDesign.toWledPayload fixture", async () => {
  const s = baseStore();
  s.seed(`users/${UID}/scenes/sc_custom`, {
    type: "custom",
    name: "My Custom",
    custom_design: {
      brightness: 200,
      channels: [
        {
          channel_id: 0,
          included: true,
          color_groups: [
            { start_led: 0, end_led: 10, color: [255, 0, 0, 0] },
            { start_led: 11, end_led: 20, color: [0, 0, 255, 0] },
          ],
          effect_id: 0,
          speed: 128,
          intensity: 128,
          reverse: false,
        },
        // excluded → must not appear
        { channel_id: 1, included: false, color_groups: [], effect_id: 5, speed: 100, intensity: 100, reverse: false },
        // empty groups → white fallback; nonzero fx; reversed → rev:true
        { channel_id: 2, included: true, color_groups: [], effect_id: 12, speed: 150, intensity: 90, reverse: true },
      ],
    },
  });
  const expected =
    '{"on":true,"bri":200,"seg":[' +
    '{"id":0,"col":[[255,0,0,0],[0,0,255,0]],"fx":83,"sx":128,"ix":128},' +
    '{"id":2,"col":[[255,255,255,0]],"fx":12,"sx":150,"ix":90,"rev":true}]}';
  assert.equal(await activateAndReadPayload(s, "sc_custom"), expected);
});

test("library scene payload === Dart Scene.toWledPayload(library) fixture", async () => {
  const s = baseStore();
  s.seed(`users/${UID}/scenes/sc_lib`, {
    type: "library",
    name: "Aurora",
    brightness: 180,
    library_pattern: {
      id: "p1",
      name: "Aurora",
      colors: JSON.stringify([[0, 255, 0, 0], [0, 0, 255, 0]]), // #84 stored-string
      effect_id: 47,
      speed: 200,
      intensity: 150,
      category: "nature",
    },
  });
  const expected =
    '{"on":true,"bri":180,"seg":[{"col":[[0,255,0,0],[0,0,255,0]],"fx":47,"sx":200,"ix":150}]}';
  assert.equal(await activateAndReadPayload(s, "sc_lib"), expected);
});

test("system scene payload is the stored wled_payload verbatim", async () => {
  const s = baseStore();
  s.seed(`users/${UID}/scenes/sc_sys`, {
    type: "system",
    name: "Lights Off",
    wled_payload: JSON.stringify({ on: false }),
  });
  assert.equal(await activateAndReadPayload(s, "sc_sys"), '{"on":false}');
});

// ---------------------------------------------------------------------------
// 3. Game Day activation (saved_design_payload verbatim)
// ---------------------------------------------------------------------------
test("Game Day team activates via gameday- id with verbatim saved payload", async () => {
  const s = baseStore();
  const savedPayload = '{"on":true,"bri":255,"seg":[{"id":0,"fx":17}]}';
  s.seed(`users/${UID}/game_day_autopilot/mlb_royals`, {
    team_name: "Kansas City Royals",
    saved_design_name: "Royals Twinkle",
    saved_design_payload: savedPayload,
    design_mode: "saved",
    enabled: true,
  });
  assert.equal(await activateAndReadPayload(s, "gameday-mlb_royals"), savedPayload);

  // and it appears in the activatable-scenes discovery list
  const scenes = await resolveActivatableScenes(asDb(s), UID);
  const gd = scenes.find((x) => x.sceneId === "gameday-mlb_royals");
  assert.ok(gd);
  assert.equal(gd.name, "Kansas City Royals");
  assert.equal(gd.altName, "Royals Twinkle");
  assert.equal(gd.origin, "game_day");
});

// ---------------------------------------------------------------------------
// 4. Multi-controller scene fanout (N controllers → N docs)
// ---------------------------------------------------------------------------
test("scene activation with no controller fans out to ALL controllers", async () => {
  const s = baseStore();
  s.seed(`users/${UID}/controllers/ctrlB`, { ip: "192.168.1.51", created_at: { toMillis: () => 2000 } });
  s.seed(`users/${UID}/controllers/ctrlC`, { ip: "192.168.1.52", created_at: { toMillis: () => 3000 } });
  s.seed(`users/${UID}/scenes/sc_sys`, {
    type: "system",
    name: "Lights Off",
    wled_payload: JSON.stringify({ on: false }),
  });

  const res = await executeIntent({
    uid: UID,
    controllerId: null,
    intent: { kind: "ACTIVATE_SCENE", sceneId: "sc_sys" },
    source: "voice_google",
    db: asDb(s),
  });
  assert.ok(res.ok);
  assert.equal(res.commandRefs.length, 3); // ctrlA + ctrlB + ctrlC

  const ips = res.commandRefs.map((r) => readCmd(s, r).controllerIp).sort();
  assert.deepEqual(ips, ["192.168.1.50", "192.168.1.51", "192.168.1.52"]);
  for (const r of res.commandRefs) {
    assert.equal(readCmd(s, r).payload, '{"on":false}');
  }
});

// ---------------------------------------------------------------------------
// 5. Cross-uid denied
// ---------------------------------------------------------------------------
test("cross-uid device is denied and writes nothing", async () => {
  const s = baseStore();
  const res = await executeIntent({
    uid: UID,
    controllerId: "ctrlA",
    intent: { kind: "POWER_ON" },
    source: "voice_google",
    deviceUserId: "someone_else",
    db: asDb(s),
  });
  assert.equal(res.ok, false);
  if (!res.ok) assert.equal(res.code, "cross_uid");
  // no command docs written
  const wrote = [...s.docs.keys()].some((k) => k.includes("/commands/"));
  assert.equal(wrote, false);
});

test("unknown controller id is rejected (structurally cross-uid-safe)", async () => {
  const s = baseStore();
  const res = await executeIntent({
    uid: UID,
    controllerId: "ctrl_not_mine",
    intent: { kind: "POWER_ON" },
    source: "voice_google",
    db: asDb(s),
  });
  assert.equal(res.ok, false);
  if (!res.ok) assert.equal(res.code, "unknown_controller");
});

// ---------------------------------------------------------------------------
// 6. Feature flag off → not_enabled
// ---------------------------------------------------------------------------
test("flag OFF returns not_enabled and writes nothing", async () => {
  const s = baseStore();
  s.seed("config/voice_control", { enabled: false });
  const res = await executeIntent({
    uid: UID,
    controllerId: "ctrlA",
    intent: { kind: "POWER_ON" },
    source: "voice_google",
    db: asDb(s),
  });
  assert.equal(res.ok, false);
  if (!res.ok) assert.equal(res.code, "not_enabled");
});

test("flag reader is defensive-false for missing/non-bool/error", async () => {
  const s = new Store();
  assert.equal(await readVoiceControlEnabled(asDb(s)), false); // missing doc
  s.seed("config/voice_control", { enabled: "yes" });
  assert.equal(await readVoiceControlEnabled(asDb(s)), false); // non-bool
  s.seed("config/voice_control", { enabled: true });
  assert.equal(await readVoiceControlEnabled(asDb(s)), true);
});

// ---------------------------------------------------------------------------
// 7. awaitOutcome × 3 outcomes + 8. listener cleanup
// ---------------------------------------------------------------------------
test("awaitOutcome resolves confirmed on completed and cleans up", async () => {
  const s = new Store();
  s.seed(`users/${UID}/commands/c1`, { status: "pending" });
  const ref = asDb(s).collection("users").doc(UID).collection("commands").doc("c1");
  const p = awaitOutcome(ref, 1000);
  setTimeout(() => ref.set({ status: "completed" }), 5);
  const outcome = await p;
  assert.deepEqual(outcome, { status: "confirmed" });
  assert.equal(s.listenerCount, 0); // listener torn down
});

test("awaitOutcome resolves failed with error and cleans up", async () => {
  const s = new Store();
  s.seed(`users/${UID}/commands/c2`, { status: "pending" });
  const ref = asDb(s).collection("users").doc(UID).collection("commands").doc("c2");
  const p = awaitOutcome(ref, 1000);
  setTimeout(() => ref.set({ status: "failed", error: "device offline" }), 5);
  const outcome = await p;
  assert.deepEqual(outcome, { status: "failed", error: "device offline" });
  assert.equal(s.listenerCount, 0);
});

test("awaitOutcome resolves optimistic on timeout and cleans up", async () => {
  const s = new Store();
  s.seed(`users/${UID}/commands/c3`, { status: "pending" });
  const ref = asDb(s).collection("users").doc(UID).collection("commands").doc("c3");
  const outcome = await awaitOutcome(ref, 30);
  assert.deepEqual(outcome, { status: "optimistic" });
  assert.equal(s.listenerCount, 0);
});
