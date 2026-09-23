/**
 * Neighborhood Sync v1 — crew fire against the REAL Firestore emulator.
 *
 * ⚠️ NOT run by `npm test`. Requires FIRESTORE_EMULATOR_HOST (set by
 * `firebase emulators:exec --only firestore ...`). See test/emulator/README.md.
 *
 * The unit suite (test/unit/syncFireV1.test.js) proves the logic with fakes;
 * this suite proves the parts a fake cannot: batch create with deterministic
 * ids, the two-equality hygiene query, `updateTime` on the heartbeat doc, and
 * the dotted-path fire-record update that pollSyncFire writes.
 */

import * as admin from "firebase-admin";
import {
  fanoutToCrew,
  SYNC_COMMAND_TTL_MS,
  syncCommandDocId,
} from "../../src/applySyncPattern";
import { refreshFireStatus } from "../../src/pollSyncFire";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: "lumina-fn-test" });
}
const db = admin.firestore();

const A = "uid_alice";
const B = "uid_bob";
const C = "uid_carol";
const G = "g_v1";
const PAYLOAD =
  '{"on":true,"bri":128,"seg":[{"fx":0,"sx":128,"ix":128,"pal":5,"grp":1,"spc":0,"col":[[0,80,255,0],[0,0,0,0],[0,0,0,0]]}]}';

async function wipe(): Promise<void> {
  // listDocuments() (not get()) so MISSING parent docs that only exist as
  // subcollection ancestors — users/{uid} here — are wiped too.
  const cols = ["neighborhoods", "users"];
  for (const c of cols) {
    const refs = await db.collection(c).listDocuments();
    for (const ref of refs) {
      await db.recursiveDelete(ref);
    }
  }
}

async function seedCrew(): Promise<void> {
  await db.doc(`neighborhoods/${G}`).set({
    creatorUid: A,
    memberUids: [A, B, C],
    name: "v1 bench crew",
  });
  await db.doc(`neighborhoods/${G}/members/${A}`).set({
    displayName: "Alice",
    controllerId: ["ca"],
    participationStatus: "active",
  });
  await db.doc(`neighborhoods/${G}/members/${B}`).set({
    displayName: "Bob",
    controllerId: ["cb"],
    participationStatus: "active",
  });
  await db.doc(`neighborhoods/${G}/members/${C}`).set({
    displayName: "Carol",
    controllerId: ["cc"],
    participationStatus: "active",
  });
  await db.doc(`users/${A}/controllers/ca`).set({ ip: "192.168.1.173" });
  await db.doc(`users/${B}/controllers/cb`).set({
    ip: "192.168.1.150",
    participating_channels_device_ids: [0, 1],
    participating_channels: [0, 1],
  });
  await db.doc(`users/${C}/controllers/cc`).set({ ip: "10.0.0.9" });
  // Alice and Bob have live bridges (fresh heartbeat = updateTime now).
  await db.doc(`users/${A}/bridge_status/current`).set({ uptime: 1 });
  await db.doc(`users/${B}/bridge_status/current`).set({ uptime: 1 });
  // Carol has never had a bridge heartbeat.
}

beforeEach(async () => {
  await wipe();
  await seedCrew();
});

describe("fanoutToCrew v1 on the emulator", () => {
  test("writes one command per live member in one batch, records the fire, supersedes the old one", async () => {
    // Bob has an older sync command nobody picked up.
    await db.doc(`users/${B}/commands/sync_old_cb`).set({
      type: "applyJson",
      payload: "{}",
      source: "sync_fanout",
      status: "pending",
      controllerIp: "192.168.1.150",
      createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 5000),
    });
    // And an unrelated writer's pending command that must NOT be touched.
    await db.doc(`users/${B}/commands/other_writer`).set({
      type: "ping",
      source: "health_probe",
      status: "pending",
      createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 5000),
    });

    const now = Date.now();
    const out = await fanoutToCrew(db, {
      groupId: G,
      initiatorUid: A,
      payloadString: PAYLOAD,
      sessionId: "",
      source: "sync_fanout",
      nowMs: now,
    });

    expect(out.memberCount).toBe(3);
    expect(out.commandCount).toBe(2); // Alice + Bob
    expect(out.noBridge).toBe(1); // Carol
    expect(out.expiresAtMs).toBe(now + SYNC_COMMAND_TTL_MS);

    const a = await db.doc(`users/${A}/commands/${syncCommandDocId(out.fireId, "ca", 0)}`).get();
    const b = await db.doc(`users/${B}/commands/${syncCommandDocId(out.fireId, "cb", 0)}`).get();
    expect(a.exists).toBe(true);
    expect(b.exists).toBe(true);
    expect(a.data()!.status).toBe("pending");
    expect(a.data()!.controllerIp).toBe("192.168.1.173");
    expect(a.data()!.expiresAt.toMillis()).toBe(now + SYNC_COMMAND_TTL_MS);
    expect(a.data()!.syncFire).toEqual({ groupId: G, fireId: out.fireId, key: `${A}__ca` });
    expect(typeof a.data()!.payload).toBe("string");
    // Bob's doc is partitioned across his two published channels (#67).
    const bobSeg = JSON.parse(b.data()!.payload).seg;
    expect(bobSeg).toHaveLength(2);
    expect(bobSeg[0]).toMatchObject({ id: 0, on: true, fx: 0 });
    expect(bobSeg[1]).toMatchObject({ id: 1, on: true, fx: 0 });
    // Alice's is passed through untouched (no channel facts published).
    expect(JSON.parse(a.data()!.payload)).toEqual(JSON.parse(PAYLOAD));

    // Carol: nothing written, recorded no_bridge.
    const carolCmds = await db.collection(`users/${C}/commands`).get();
    expect(carolCmds.size).toBe(0);

    // Hygiene: the old sync command is superseded; the other writer's is not.
    expect((await db.doc(`users/${B}/commands/sync_old_cb`).get()).data()!.status).toBe("superseded");
    expect((await db.doc(`users/${B}/commands/other_writer`).get()).data()!.status).toBe("pending");

    // Fire record.
    const fire = await db.doc(`neighborhoods/${G}/fires/${out.fireId}`).get();
    expect(fire.exists).toBe(true);
    const targets = fire.data()!.targets;
    expect(targets[`${A}__ca`].status).toBe("pending");
    expect(targets[`${B}__cb`].status).toBe("pending");
    expect(targets[`${C}__cc`].status).toBe("no_bridge");
    expect(targets[`${C}__cc`].reason).toBe("no_heartbeat_ever");
    expect(fire.data()!.summary).toEqual({
      memberCount: 3,
      commandCount: 2,
      skipped: 0,
      noAddress: 0,
      noBridge: 1,
    });
  });
});

describe("refreshFireStatus v1 on the emulator", () => {
  test("mirrors bridge outcomes; an unpicked command settles to no_response after expiry", async () => {
    const now = Date.now();
    const out = await fanoutToCrew(db, {
      groupId: G,
      initiatorUid: A,
      payloadString: PAYLOAD,
      sessionId: "",
      source: "sync_fanout",
      nowMs: now,
    });

    // Bridge A completes; bridge B claims then fails (controller unreachable).
    await db
      .doc(`users/${A}/commands/${syncCommandDocId(out.fireId, "ca", 0)}`)
      .update({ status: "completed", completedAt: admin.firestore.Timestamp.now() });
    await db
      .doc(`users/${B}/commands/${syncCommandDocId(out.fireId, "cb", 0)}`)
      .update({ status: "failed", error: "ERROR: HTTP -1" });

    const r1 = await refreshFireStatus(db, G, out.fireId, now + 3000);
    const byUid = Object.fromEntries(r1.targets.map((t) => [t.uid, t]));
    expect(byUid[A].status).toBe("completed");
    expect(byUid[B].status).toBe("failed");
    expect(byUid[B].error).toBe("ERROR: HTTP -1");
    expect(byUid[C].status).toBe("no_bridge");
    expect(r1.summary).toMatchObject({ confirmed: 1, failed: 1, noBridge: 1, waiting: 0, settled: true });

    // The durable record was updated with dotted paths.
    const fire = await db.doc(`neighborhoods/${G}/fires/${out.fireId}`).get();
    expect(fire.data()!.targets[`${A}__ca`].status).toBe("completed");
    expect(fire.data()!.targets[`${B}__cb`].error).toBe("ERROR: HTTP -1");
    expect(fire.data()!.lastPolledAt).toBeDefined();
  });

  test("a command nobody picked up is reported no_response once the fire expires", async () => {
    const now = Date.now();
    const out = await fanoutToCrew(db, {
      groupId: G,
      initiatorUid: A,
      payloadString: PAYLOAD,
      sessionId: "",
      source: "sync_fanout",
      nowMs: now,
    });
    // Nobody touches the commands.
    const early = await refreshFireStatus(db, G, out.fireId, now + 10_000);
    expect(early.summary.waiting).toBe(2);
    expect(early.summary.settled).toBe(false);

    const late = await refreshFireStatus(db, G, out.fireId, now + SYNC_COMMAND_TTL_MS + 1);
    expect(late.summary.waiting).toBe(0);
    expect(late.summary.noResponse).toBe(2);
    expect(late.summary.settled).toBe(true);
    const fire = await db.doc(`neighborhoods/${G}/fires/${out.fireId}`).get();
    expect(fire.data()!.targets[`${A}__ca`].status).toBe("no_response");
    // The command docs themselves are left for the sweeper (still pending).
    const a = await db.doc(`users/${A}/commands/${syncCommandDocId(out.fireId, "ca", 0)}`).get();
    expect(a.data()!.status).toBe("pending");
  });
});
