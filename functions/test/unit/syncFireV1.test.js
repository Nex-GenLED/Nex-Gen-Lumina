// Neighborhood Sync v1 — the crew FIRE.
//
// One Start tap → one command per member controller, written in ONE batch, plus
// a fire record the initiator can be told the truth from. These tests lock the
// four things that make v1 survive the relay's known failure modes:
//
//   1. bridge liveness  — a member whose bridge has not heartbeat within
//                         BRIDGE_LIVE_WINDOW_MS is recorded `no_bridge` and NOT
//                         commanded (no 90 s in-flight corpse in their queue)
//   2. queue hygiene    — an older pending sync command is superseded before the
//                         new one lands (≤5-per-poll, unordered pickup), and an
//                         `executing` command older than STUCK_EXECUTING_MS is
//                         cleared; other writers' commands are never touched
//   3. expiry           — every sync command carries expiresAt = +90 s and a
//                         syncFire back-pointer; the doc id is deterministic
//   4. read-back        — pollSyncFire mirrors bridge outcomes into the fire
//                         record and settles open targets to `no_response`
//                         past expiry, so "sent" is never reported as "done"
//
// Runs against the tsc-compiled lib/ with in-memory fakes (no emulator).

const {
  fanoutToCrew,
  classifyDeliveryRoute,
  planQueueHygiene,
  syncCommandDocId,
  fireTargetKey,
  SYNC_COMMAND_TTL_MS,
  BRIDGE_LIVE_WINDOW_MS,
  STUCK_EXECUTING_MS,
} = require("../../lib/applySyncPattern");
const {
  deriveTargetStatus,
  summarizeFireTargets,
  refreshFireStatus,
} = require("../../lib/pollSyncFire");
const { makeCrewDb } = require("./helpers/fakeCrewDb");

const NOW = 1_800_000_000_000;
const A = "uid_a";
const B = "uid_b";

const run = (db, extra = {}) =>
  fanoutToCrew(db, {
    groupId: "g1",
    initiatorUid: A,
    payloadString: '{"on":true,"seg":[{"fx":0,"col":[[255,0,0]]}]}',
    sessionId: "",
    source: "sync_fanout",
    nowMs: NOW,
    ...extra,
  });

const twoMembers = {
  [A]: { displayName: "Alice", controllerId: ["ctrl_a"] },
  [B]: { displayName: "Bob", controllerId: ["ctrl_b"] },
};

describe("classifyDeliveryRoute (pure)", () => {
  test("webhook URL wins regardless of heartbeat", () => {
    expect(
      classifyDeliveryRoute({ webhookUrl: "https://h", bridgeHeartbeatMs: null, nowMs: NOW })
        .route
    ).toBe("webhook");
  });
  test("fresh heartbeat → bridge", () => {
    const r = classifyDeliveryRoute({
      webhookUrl: null,
      bridgeHeartbeatMs: NOW - 30_000,
      nowMs: NOW,
    });
    expect(r.route).toBe("bridge");
  });
  test("stale heartbeat → no_bridge, with the age in the reason", () => {
    const r = classifyDeliveryRoute({
      webhookUrl: null,
      bridgeHeartbeatMs: NOW - BRIDGE_LIVE_WINDOW_MS - 1000,
      nowMs: NOW,
    });
    expect(r.route).toBe("no_bridge");
    expect(r.reason).toMatch(/heartbeat_stale_121s/);
  });
  test("no heartbeat ever → no_bridge", () => {
    expect(
      classifyDeliveryRoute({ webhookUrl: null, bridgeHeartbeatMs: null, nowMs: NOW }).route
    ).toBe("no_bridge");
  });
});

describe("planQueueHygiene (pure)", () => {
  test("pending → supersede; old executing → stuck; fresh executing → left", () => {
    const plan = planQueueHygiene(
      [
        { id: "p1", status: "pending", createdAtMs: NOW - 5000 },
        { id: "x_old", status: "executing", createdAtMs: NOW - STUCK_EXECUTING_MS - 1 },
        { id: "x_new", status: "executing", createdAtMs: NOW - 2000 },
        { id: "x_unknown_age", status: "executing", createdAtMs: null },
      ],
      NOW
    );
    expect(plan.supersede).toEqual(["p1"]);
    expect(plan.stuck).toEqual(["x_old"]);
  });
});

describe("ids (pure)", () => {
  test("deterministic command id and target key; empty controller id gets an ordinal", () => {
    expect(syncCommandDocId("F1", "80_f3_da", 0)).toBe("sync_F1_80_f3_da");
    expect(syncCommandDocId("F1", "", 2)).toBe("sync_F1_c2");
    expect(fireTargetKey("uid", "80_f3_da", 0)).toBe("uid__80_f3_da");
    expect(syncCommandDocId("F.1/x", "a.b", 0)).toBe("sync_F_1_x_a_b");
  });
});

describe("fanoutToCrew v1 — write shape", () => {
  test("two live members → two commands in ONE batch, a fire record, expiresAt +90 s", async () => {
    const { db, commands, fires, batchCommits } = makeCrewDb({
      memberUids: [A, B],
      members: twoMembers,
      nowMs: NOW,
      heartbeatAgeMs: 20_000,
    });
    const out = await run(db);

    expect(out.fireId).toBe("fire1");
    expect(out.memberCount).toBe(2);
    expect(out.commandCount).toBe(2);
    expect(out.noBridge).toBe(0);
    expect(out.expiresAtMs).toBe(NOW + SYNC_COMMAND_TTL_MS);
    expect(batchCommits()).toBe(1);

    expect(commands[A]).toHaveLength(1);
    expect(commands[B]).toHaveLength(1);
    const cmd = commands[B][0];
    expect(cmd._id).toBe("sync_fire1_ctrl_b");
    expect(cmd.status).toBe("pending");
    expect(cmd.source).toBe("sync_fanout");
    expect(cmd.expiresAt.toMillis()).toBe(NOW + SYNC_COMMAND_TTL_MS);
    expect(cmd.syncFire).toEqual({ groupId: "g1", fireId: "fire1", key: `${B}__ctrl_b` });
    expect(cmd.payload).toBe('{"on":true,"seg":[{"fx":0,"col":[[255,0,0]]}]}');
    // Never a tb, never a frz, never a preset op — the v1 contract.
    expect(cmd.payload).not.toMatch(/"tb"|"frz"|"psave"|"pdel"/);

    expect(fires).toHaveLength(1);
    const fire = fires[0].data;
    expect(fire.initiatorUid).toBe(A);
    expect(fire.summary).toEqual({
      memberCount: 2,
      commandCount: 2,
      skipped: 0,
      noAddress: 0,
      noBridge: 0,
    });
    expect(fire.targets[`${B}__ctrl_b`]).toMatchObject({
      uid: B,
      displayName: "Bob",
      controllerId: "ctrl_b",
      route: "bridge",
      status: "pending",
      commandPath: `users/${B}/commands/sync_fire1_ctrl_b`,
    });
  });

  test("a member whose bridge is silent is recorded no_bridge and NOT commanded; the other still is", async () => {
    const { db, commands, fires } = makeCrewDb({
      memberUids: [A, B],
      members: twoMembers,
      nowMs: NOW,
      heartbeatAgeByUid: { [A]: 10_000, [B]: null },
    });
    const out = await run(db);

    expect(out.commandCount).toBe(1);
    expect(out.noBridge).toBe(1);
    expect(commands[A]).toHaveLength(1);
    expect(commands[B] || []).toHaveLength(0); // no corpse in Bob's queue
    const t = fires[0].data.targets[`${B}__ctrl_b`];
    expect(t.status).toBe("no_bridge");
    expect(t.reason).toBe("no_heartbeat_ever");
    expect(t.commandPath).toBeNull();
  });

  test("a stale heartbeat (older than the window) counts as no_bridge", async () => {
    const { db, commands } = makeCrewDb({
      memberUids: [A],
      members: { [A]: twoMembers[A] },
      nowMs: NOW,
      heartbeatAgeMs: BRIDGE_LIVE_WINDOW_MS + 5_000,
    });
    const out = await run(db);
    expect(out.noBridge).toBe(1);
    expect(commands[A] || []).toHaveLength(0);
  });

  test("a webhook-mode member is commanded even with no heartbeat", async () => {
    const { db, commands } = makeCrewDb({
      memberUids: [A],
      members: { [A]: twoMembers[A] },
      nowMs: NOW,
      heartbeatAgeMs: null,
      webhookByUid: { [A]: "https://alice.duckdns.org" },
    });
    const out = await run(db);
    expect(out.commandCount).toBe(1);
    expect(commands[A][0].webhookUrl).toBe("https://alice.duckdns.org");
  });

  test("no address → recorded no_address and written FAILED (never dispatched), as #70", async () => {
    const { db, commands, fires } = makeCrewDb({
      memberUids: [A],
      members: { [A]: twoMembers[A] },
      nowMs: NOW,
      ipByController: { ctrl_a: "" },
    });
    const out = await run(db);
    expect(out.noAddress).toBe(1);
    expect(out.commandCount).toBe(0);
    expect(commands[A][0].status).toBe("failed");
    expect(commands[A][0].error).toBe("no_address");
    expect(fires[0].data.targets[`${A}__ctrl_a`].status).toBe("no_address");
  });

  test("a paused non-initiator is recorded skipped on the fire (legible), not commanded", async () => {
    const { db, commands, fires } = makeCrewDb({
      memberUids: [A, B],
      members: {
        [A]: twoMembers[A],
        [B]: { ...twoMembers[B], participationStatus: "paused" },
      },
      nowMs: NOW,
    });
    const out = await run(db);
    expect(out.skipped).toBe(1);
    expect(commands[B] || []).toHaveLength(0);
    const skipped = Object.values(fires[0].data.targets).filter((t) => t.status === "skipped");
    expect(skipped).toHaveLength(1);
    expect(skipped[0]).toMatchObject({ uid: B, displayName: "Bob", reason: "paused" });
  });
});

describe("fanoutToCrew v1 — queue hygiene", () => {
  test("an older pending sync command is superseded in the same batch; a stuck executing one is failed", async () => {
    const { db, commands, updates } = makeCrewDb({
      memberUids: [A],
      members: { [A]: twoMembers[A] },
      nowMs: NOW,
      inFlightByUid: {
        [A]: [
          { id: "sync_old_ctrl_a", status: "pending", createdAtMs: NOW - 4000 },
          { id: "sync_dead_ctrl_a", status: "executing", createdAtMs: NOW - 200_000 },
          { id: "sync_live_ctrl_a", status: "executing", createdAtMs: NOW - 3000 },
        ],
      },
    });
    await run(db);

    expect(commands[A]).toHaveLength(1); // the new one
    const ups = updates[A];
    expect(ups.map((u) => u.id).sort()).toEqual(["sync_dead_ctrl_a", "sync_old_ctrl_a"]);
    const sup = ups.find((u) => u.id === "sync_old_ctrl_a").data;
    expect(sup.status).toBe("superseded");
    expect(sup.supersededBy).toBe("fire1");
    const stuck = ups.find((u) => u.id === "sync_dead_ctrl_a").data;
    expect(stuck.status).toBe("failed");
    expect(stuck.error).toMatch(/stuck_executing/);
  });

  test("hygiene queries are scoped to source == sync_fanout (other writers untouched)", async () => {
    // The fake only ever returns sync_fanout rows for the (source, status)
    // query — this test pins that the code ASKS with that filter by asserting
    // the fake's captured filter set contains source == sync_fanout.
    let capturedFilters = null;
    const { db } = makeCrewDb({
      memberUids: [A],
      members: { [A]: twoMembers[A] },
      nowMs: NOW,
    });
    const users = db.collection("users");
    const orig = users.doc;
    users.doc = (uid) => {
      const d = orig(uid);
      const oc = d.collection;
      d.collection = (sub) => {
        const c = oc(sub);
        if (sub === "commands") {
          const ow = c.where;
          c.where = (f, op, v) => {
            capturedFilters = capturedFilters || [];
            capturedFilters.push([f, op, v]);
            return ow(f, op, v);
          };
        }
        return c;
      };
      return d;
    };
    db.collection = ((origCol) => (name) => (name === "users" ? users : origCol(name)))(
      db.collection
    );
    await run(db);
    expect(capturedFilters).toEqual(
      expect.arrayContaining([["source", "==", "sync_fanout"]])
    );
  });
});

describe("pollSyncFire — pure helpers", () => {
  test("deriveTargetStatus: open past expiry → no_response; terminal untouched", () => {
    expect(deriveTargetStatus("pending", NOW + 100_000, NOW + 90_000)).toBe("no_response");
    expect(deriveTargetStatus("executing", NOW + 100_000, NOW + 90_000)).toBe("no_response");
    expect(deriveTargetStatus("pending", NOW + 10_000, NOW + 90_000)).toBe("pending");
    expect(deriveTargetStatus("completed", NOW + 100_000, NOW + 90_000)).toBe("completed");
    expect(deriveTargetStatus("no_bridge", NOW + 100_000, NOW + 90_000)).toBe("no_bridge");
  });

  test("summarizeFireTargets counts and settles correctly", () => {
    const s = summarizeFireTargets([
      "completed",
      "completed",
      "failed",
      "pending",
      "no_response",
      "no_bridge",
      "no_address",
      "skipped",
    ]);
    expect(s).toEqual({
      total: 8,
      commanded: 5,
      confirmed: 2,
      failed: 1,
      waiting: 1,
      noResponse: 1,
      noBridge: 1,
      noAddress: 1,
      skipped: 1,
      settled: false,
    });
    expect(summarizeFireTargets(["completed", "no_bridge"]).settled).toBe(true);
    expect(summarizeFireTargets([]).settled).toBe(true);
  });
});

/** Fake db for refreshFireStatus: one fire doc + command docs by path. */
function makeFireDb({ fire, commandsByPath }) {
  const fireUpdates = [];
  const fireRef = {
    get: async () => ({ exists: true, data: () => fire }),
    update: async (u) => {
      fireUpdates.push(u);
    },
  };
  const db = {
    collection: () => ({
      doc: () => ({ collection: () => ({ doc: () => fireRef }) }),
    }),
    doc: (path) => ({ _path: path }),
    getAll: async (...refs) =>
      refs.map((r) => {
        const d = commandsByPath[r._path];
        return d ? { exists: true, data: () => d } : { exists: false };
      }),
  };
  return { db, fireUpdates };
}

describe("refreshFireStatus (read-back)", () => {
  const fire = () => ({
    createdAtMs: NOW,
    expiresAt: { toMillis: () => NOW + SYNC_COMMAND_TTL_MS },
    targets: {
      [`${A}__ca`]: {
        uid: A,
        displayName: "Alice",
        controllerId: "ca",
        route: "bridge",
        status: "pending",
        reason: "heartbeat_fresh",
        commandPath: `users/${A}/commands/sync_f_ca`,
      },
      [`${B}__cb`]: {
        uid: B,
        displayName: "Bob",
        controllerId: "cb",
        route: "bridge",
        status: "pending",
        reason: "heartbeat_fresh",
        commandPath: `users/${B}/commands/sync_f_cb`,
      },
      [`c__none`]: {
        uid: "c",
        displayName: "Carol",
        controllerId: "cc",
        route: "no_bridge",
        status: "no_bridge",
        reason: "no_heartbeat_ever",
        commandPath: null,
      },
    },
  });

  test("mirrors completed/failed from the command docs; waits on the rest", async () => {
    const { db, fireUpdates } = makeFireDb({
      fire: fire(),
      commandsByPath: {
        [`users/${A}/commands/sync_f_ca`]: {
          status: "completed",
          completedAt: { toMillis: () => NOW + 1500 },
        },
        [`users/${B}/commands/sync_f_cb`]: { status: "executing" },
      },
    });
    const r = await refreshFireStatus(db, "g1", "f", NOW + 2000);
    const byUid = Object.fromEntries(r.targets.map((t) => [t.uid, t]));
    expect(byUid[A].status).toBe("completed");
    expect(byUid[A].completedAtMs).toBe(NOW + 1500);
    expect(byUid[B].status).toBe("executing");
    expect(byUid["c"].status).toBe("no_bridge");
    expect(r.summary).toMatchObject({ confirmed: 1, waiting: 1, noBridge: 1, settled: false });
    // Only the CHANGED targets are written back.
    expect(fireUpdates).toHaveLength(1);
    expect(Object.keys(fireUpdates[0]).sort()).toEqual(
      [
        "lastPolledAt",
        `targets.${A}__ca.completedAtMs`,
        `targets.${A}__ca.error`,
        `targets.${A}__ca.status`,
        `targets.${B}__cb.completedAtMs`,
        `targets.${B}__cb.error`,
        `targets.${B}__cb.status`,
      ].sort()
    );
  });

  test("past expiry, still-open targets settle to no_response and the record is updated", async () => {
    const { db, fireUpdates } = makeFireDb({
      fire: fire(),
      commandsByPath: {
        [`users/${A}/commands/sync_f_ca`]: { status: "completed" },
        [`users/${B}/commands/sync_f_cb`]: { status: "pending" }, // bridge never came
      },
    });
    const r = await refreshFireStatus(db, "g1", "f", NOW + SYNC_COMMAND_TTL_MS + 1);
    const bob = r.targets.find((t) => t.uid === B);
    expect(bob.status).toBe("no_response");
    expect(bob.error).toMatch(/No response before expiry/);
    expect(r.summary).toMatchObject({ confirmed: 1, noResponse: 1, waiting: 0, settled: true });
    expect(fireUpdates[0][`targets.${B}__cb.status`]).toBe("no_response");
  });

  test("a bridge failure (controller unreachable) is reported as failed with the bridge's error", async () => {
    const { db } = makeFireDb({
      fire: fire(),
      commandsByPath: {
        [`users/${A}/commands/sync_f_ca`]: { status: "failed", error: "ERROR: HTTP -1" },
        [`users/${B}/commands/sync_f_cb`]: { status: "completed" },
      },
    });
    const r = await refreshFireStatus(db, "g1", "f", NOW + 12_000);
    const alice = r.targets.find((t) => t.uid === A);
    expect(alice.status).toBe("failed");
    expect(alice.error).toBe("ERROR: HTTP -1");
    expect(r.summary).toMatchObject({ confirmed: 1, failed: 1, settled: true });
  });
});
