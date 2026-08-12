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

// Minimal in-memory Firestore fake covering exactly what fanoutToCrew touches:
//   neighborhoods/{g}.get() -> { memberUids }
//   neighborhoods/{g}/members.get() -> forEach(doc{id,data()})
//   users/{uid}.get() -> { } (no webhookUrl)
//   users/{uid}/controllers.get() -> empty (members carry controllerId[])
//   users/{uid}/commands.add(doc) -> recorded
function makeDb({ memberUids, members }) {
  const commands = {};
  const usersDoc = (uid) => ({
    get: async () => ({ data: () => ({}) }),
    collection: (sub) => {
      if (sub === "controllers") {
        return {
          get: async () => ({ forEach: () => {} }),
          // #70: the denorm branch now JOINS ids to addresses, so the fake must
          // hand back a controller doc. Without this the code under test falls
          // into its address-join catch and every command becomes no_address —
          // the assertions below would still pass, but against the degraded
          // path rather than the real one.
          doc: (id) => ({ _uid: uid, _id: id }),
        };
      }
      if (sub === "commands") {
        commands[uid] = commands[uid] || [];
        return {
          add: async (doc) => {
            commands[uid].push(doc);
            return { id: "cmd" + commands[uid].length };
          },
        };
      }
      throw new Error("unexpected users subcollection: " + sub);
    },
  });
  const db = {
    // Every named controller resolves to a real address, so the fanout under
    // test produces deliverable commands.
    getAll: async (...refs) =>
      refs.map((r) => ({
        id: r._id,
        exists: true,
        data: () => ({ ip: "10.0.0." + (r._id.length % 200) }),
      })),
    collection: (name) => {
      if (name === "neighborhoods") {
        return {
          doc: () => ({
            get: async () => ({ data: () => ({ memberUids }) }),
            collection: (sub) => {
              if (sub === "members") {
                return {
                  get: async () => ({
                    forEach: (cb) =>
                      Object.entries(members).forEach(([id, data]) =>
                        cb({ id, data: () => data })
                      ),
                  }),
                };
              }
              throw new Error("unexpected neighborhoods subcollection: " + sub);
            },
          }),
        };
      }
      if (name === "users") return { doc: usersDoc };
      throw new Error("unexpected collection: " + name);
    },
  };
  return { db, commands };
}

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
