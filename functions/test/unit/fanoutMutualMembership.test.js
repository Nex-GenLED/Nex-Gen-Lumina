// SYNC-1 — server-side crew membership verification for applySyncPattern's
// crew fanout. Runs against the tsc-compiled lib/ (no emulator, no admin IO —
// fanoutToCrew is driven with an in-memory fake db). Proves the self-fanout
// authorization hole is closed: a member-subcollection doc NOT backed by the
// group's memberUids[] (a one-sided / out-of-band insert) receives NO write to
// its command queue.

const {
  verifyFanoutTarget,
  fanoutToCrew,
} = require("../../lib/applySyncPattern");

// The in-memory Firestore fake lives in helpers/fakeCrewDb.js (shared with the
// #69 suite and the v1 fire suite) so every fanoutToCrew test exercises the same
// surface: batch writes, the fire record, bridge liveness, queue hygiene.
const { makeCrewDb } = require("./helpers/fakeCrewDb");
const makeDb = ({ memberUids, members }) => makeCrewDb({ memberUids, members });

const args = (initiatorUid) => ({
  groupId: "g1",
  initiatorUid,
  payloadString: "{}",
  sessionId: "s1",
  source: "sync_fanout",
});

describe("verifyFanoutTarget (pure mutual-membership decision)", () => {
  test("uid present in memberUids -> ok", () => {
    expect(verifyFanoutTarget("u1", ["u1", "u2"])).toEqual({ ok: true });
  });

  test("uid NOT in memberUids -> denied (not_in_group_member_uids)", () => {
    const v = verifyFanoutTarget("stranger", ["u1", "u2"]);
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("not_in_group_member_uids");
  });

  test("empty uid -> denied (empty_uid)", () => {
    const v = verifyFanoutTarget("", ["u1"]);
    expect(v.ok).toBe(false);
    expect(v.reason).toBe("empty_uid");
  });
});

describe("fanoutToCrew (self-fanout authorization hole closed)", () => {
  test("one-sided stranger member doc (NOT in memberUids) receives NO command", async () => {
    const { db, commands } = makeDb({
      memberUids: ["initiator"], // stranger is NOT a verified member
      members: {
        initiator: { controllerId: ["ctrl-init"] },
        stranger: { controllerId: ["ctrl-victim"] },
      },
    });

    const res = await fanoutToCrew(db, args("initiator"));

    expect((commands["initiator"] || []).length).toBe(1);
    expect((commands["stranger"] || []).length).toBe(0); // SYNC-1: victim denied
    expect(res.memberCount).toBe(1);
    expect(res.skipped).toBe(1);
  });

  test("mutually-verified member (in memberUids) DOES receive the command", async () => {
    const { db, commands } = makeDb({
      memberUids: ["initiator", "member2"],
      members: {
        initiator: { controllerId: ["ctrl-init"] },
        member2: { controllerId: ["ctrl-2"] },
      },
    });

    await fanoutToCrew(db, args("initiator"));

    expect((commands["member2"] || []).length).toBe(1);
    expect((commands["initiator"] || []).length).toBe(1);
  });

  test("unauthenticated has no path here — the HTTP handler rejects before "
      + "fanoutToCrew (token verify + initiator membership gate); this suite "
      + "covers the fanout-target layer", () => {
    // Documented boundary: verifyToken (401) and the initiator membership gate
    // (403) run in the onRequest handler upstream of fanoutToCrew.
    expect(typeof fanoutToCrew).toBe("function");
  });
});
