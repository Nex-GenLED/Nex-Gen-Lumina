// sweepExpiredCommands × A1 — the REAL sweeper tick on the shared in-memory
// Firestore. Every assertion reads the command back with a plain .get() on the
// production path users/{uid}/commands/{id}.
//
// A1 (plan step A, 2026-10-01): an `executing` doc older than 180 s is
// terminated as failed/stuck_executing, guarded so a concurrent `completed`
// from the bridge always wins. The pending pass is unchanged in behaviour but
// now uses the same guarded write (its old "re-check" re-read its own query).
//
// Runs against compiled lib/ — `npm run build` (npm test does it).

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { runSweepTick } = require("../../lib/sweepExpiredCommands");
const {
  STUCK_EXECUTING_AFTER_MS,
  DEFAULT_COMMAND_TTL_MS,
} = require("../../lib/commandSafety");
const {
  EXPIRED_BRIDGE_OFFLINE_TEXT,
  EXPIRED_NO_BRIDGE_TEXT,
} = require("../../lib/relayEligibility");

const NOW = Date.UTC(2026, 9, 8, 23, 0, 0); // a Thursday evening, UTC
const S = 1000;
const UID = "u_sweep";
const CMD = (id) => `users/${UID}/commands/${id}`;

function world(extra = {}, { paired = true } = {}) {
  const f = makeFakeFirestore({ now: NOW });
  if (paired) f.put("bridge_registry/BR_TEST_01", { pairedUid: UID, status: "paired" });
  f.put(`users/${UID}`, { owner_id: UID });
  for (const [id, data] of Object.entries(extra)) f.put(CMD(id), data);
  return f;
}
const cmd = (status, ageMs, more = {}) => ({
  type: "applyJson",
  payload: "{}",
  controllerId: "ctrl_a",
  status,
  createdAt: { toMillis: () => NOW - ageMs },
  ...more,
});

describe("pass 2 (A1): executing older than 180 s → failed / stuck_executing", () => {
  test("a stuck claim is terminated, with no completedAt (the bridge never finished it)", async () => {
    const f = world({ c1: cmd("executing", STUCK_EXECUTING_AFTER_MS + 5 * S) });
    const r = await runSweepTick(f.db, NOW);

    const c1 = (await f.db.doc(CMD("c1")).get()).data();
    expect(c1.status).toBe("failed");
    expect(c1.error).toBe("stuck_executing");
    expect(c1.stuckSweptAt.toMillis()).toBe(NOW);
    expect(c1.completedAt).toBeUndefined();
    expect(r.stuck).toBe(1);
    expect(r.stuckPerUser).toEqual({ [UID]: 1 });
  });

  test("a claim younger than the threshold is left alone", async () => {
    const f = world({ c1: cmd("executing", STUCK_EXECUTING_AFTER_MS - 10 * S) });
    const r = await runSweepTick(f.db, NOW);
    expect((await f.db.doc(CMD("c1")).get()).get("status")).toBe("executing");
    expect(r.stuck).toBe(0);
  });

  test("COMPLETED WINS: the bridge reports between the sweeper's read and its write", async () => {
    const f = world({ c1: cmd("executing", 10 * 60 * S) });
    // The sweeper has queried; before its write lands, the bridge's PATCH
    // (mask: status, completedAt, result) arrives.
    f.beforeNextWrite(() =>
      f.patch(CMD("c1"), { status: "completed", completedAt: { toMillis: () => NOW }, result: "{}" })
    );
    const r = await runSweepTick(f.db, NOW);

    const c1 = (await f.db.doc(CMD("c1")).get()).data();
    expect(c1.status).toBe("completed");
    expect(c1.error).toBeUndefined();
    expect(r.stuck).toBe(0);
    expect(r.raced).toBe(1);
  });

  test("the 11-stuck-docs shape is cleared in one tick", async () => {
    const docs = {};
    for (let i = 0; i < 11; i++) docs[`s${i}`] = cmd("executing", (i + 1) * 86_400 * S);
    const f = world(docs);
    const r = await runSweepTick(f.db, NOW);
    expect(r.stuck).toBe(11);
    for (let i = 0; i < 11; i++) {
      expect((await f.db.doc(CMD(`s${i}`)).get()).get("status")).toBe("failed");
    }
  });

  test("idempotent: a second tick finds nothing", async () => {
    const f = world({ c1: cmd("executing", 10 * 60 * S) });
    await runSweepTick(f.db, NOW);
    const writesAfterFirst = f.writes.length;
    const r2 = await runSweepTick(f.db, NOW + 60 * S);
    expect(r2.stuck).toBe(0);
    expect(r2.expired).toBe(0);
    expect(f.writes.length).toBe(writesAfterFirst);
  });

  test("an executing doc with no createdAt is never touched — never on a guess", async () => {
    const f = world({ c1: { status: "executing", controllerId: "ctrl_a" } });
    await runSweepTick(f.db, NOW);
    expect((await f.db.doc(CMD("c1")).get()).get("status")).toBe("executing");
  });

  test("terminal docs are never touched, however old", async () => {
    const old = 30 * 86_400 * S;
    const f = world({
      a: cmd("completed", old),
      b: cmd("failed", old, { error: "ERROR: HTTP -1" }),
      c: cmd("expired", old),
      d: cmd("timeout", old),
    });
    await runSweepTick(f.db, NOW);
    for (const [id, status] of [["a", "completed"], ["b", "failed"], ["c", "expired"], ["d", "timeout"]]) {
      const doc = (await f.db.doc(CMD(id)).get()).data();
      expect(doc.status).toBe(status);
      expect(doc.stuckSweptAt).toBeUndefined();
      expect(doc.expiredAt).toBeUndefined();
    }
  });
});

describe("pass 1: pending → expired (behaviour unchanged, write now guarded)", () => {
  test("a paired account's expired command says the bridge was offline", async () => {
    const f = world({ p1: cmd("pending", DEFAULT_COMMAND_TTL_MS + 5 * S) });
    const r = await runSweepTick(f.db, NOW);
    const p1 = (await f.db.doc(CMD("p1")).get()).data();
    expect(p1.status).toBe("expired");
    expect(p1.error).toBe(EXPIRED_BRIDGE_OFFLINE_TEXT);
    expect(p1.expiredAt.toMillis()).toBe(NOW);
    expect(r.expired).toBe(1);
    expect(r.noBridge).toBe(0);
  });

  test("an account with no paired bridge gets the no-bridge text", async () => {
    const f = world({ p1: cmd("pending", DEFAULT_COMMAND_TTL_MS + 5 * S) }, { paired: false });
    const r = await runSweepTick(f.db, NOW);
    expect((await f.db.doc(CMD("p1")).get()).get("error")).toBe(EXPIRED_NO_BRIDGE_TEXT);
    expect(r.noBridge).toBe(1);
  });

  test("an explicit expiresAt still wins over the default TTL", async () => {
    const f = world({
      voice: cmd("pending", 70 * S, { expiresAt: { toMillis: () => NOW - 10 * S } }),
      longer: cmd("pending", 130 * S, { expiresAt: { toMillis: () => NOW + 60 * S } }),
    });
    await runSweepTick(f.db, NOW);
    expect((await f.db.doc(CMD("voice")).get()).get("status")).toBe("expired");
    expect((await f.db.doc(CMD("longer")).get()).get("status")).toBe("pending");
  });

  test("CLAIM WINS: the bridge claims a pending doc between the read and the write", async () => {
    // Before 2026-10-02 this overwrote the claim with `expired`. Now the
    // precondition refuses, and the bridge's state stands.
    const f = world({ p1: cmd("pending", DEFAULT_COMMAND_TTL_MS + 5 * S) });
    f.beforeNextWrite(() => f.patch(CMD("p1"), { status: "executing" }));
    const r = await runSweepTick(f.db, NOW);
    expect((await f.db.doc(CMD("p1")).get()).get("status")).toBe("executing");
    expect(r.expired).toBe(0);
    expect(r.raced).toBe(1);
  });

  test("a pending doc younger than its TTL is left alone", async () => {
    const f = world({ p1: cmd("pending", 30 * S) });
    await runSweepTick(f.db, NOW);
    expect((await f.db.doc(CMD("p1")).get()).get("status")).toBe("pending");
  });
});

describe("pass isolation", () => {
  test("a failed PENDING query does not stop the stuck pass, and the tick says so", async () => {
    const f = world({ s1: cmd("executing", 10 * 60 * S) });
    const real = f.db.collectionGroup;
    const db = {
      ...f.db,
      collectionGroup: (name) => {
        const q = real(name);
        return {
          ...q,
          where: (field, op, v) => {
            const next = q.where(field, op, v);
            if (field === "status" && v === "pending") {
              const boom = { where: () => boom, limit: () => boom, get: async () => { throw Object.assign(new Error("FAILED_PRECONDITION: index"), { code: 9 }); } };
              return boom;
            }
            return next;
          },
        };
      },
    };
    const r = await runSweepTick(db, NOW);
    expect(r.pendingQueryFailed).toBe(true);
    expect(r.stuckQueryFailed).toBe(false);
    expect(r.stuck).toBe(1);
    expect((await f.db.doc(CMD("s1")).get()).get("error")).toBe("stuck_executing");
  });
});
