// #69 — pause mutes the CREW, not yourself.
//
// TYLER'S DECISION, 2026-08-13, quoted because the rule is a product choice and
// not derivable from the code:
//
//   "pause does NOT mute your own broadcast. A paused member who initiates
//    receives their own command; pause continues to mute INCOMING broadcasts."
//
// THE DEFECT. The `if (fanoutEnabled)` arm of applySyncPattern RETURNS, so the
// host-only self-write below it never runs while the flag is on. With fanout on,
// the initiator's own command can only come from the fanout loop iterating the
// roster — and that loop skipped them for being paused. A paused member pressing
// broadcast lit the whole crew and not their own house, and ONLY when the flag
// was on: with fanout off the host path never consults participationStatus, so
// the same user action worked. Flag-dependent behaviour for one button.
//
// Found on the first successful two-node run (3/4, 2026-08-12), where the server
// said `members=1 commands=1 skipped=1` and the harness discarded all three
// numbers.

const {
  fanoutToCrew,
  isMemberSkipped,
} = require("../../lib/applySyncPattern");

const A = "uid_initiator";
const B = "uid_other";

/** Minimal in-memory Firestore covering exactly what fanoutToCrew touches. */
function makeDb({ members }) {
  const commands = {};
  const memberUids = Object.keys(members);
  const usersDoc = (uid) => ({
    get: async () => ({ data: () => ({}) }),
    collection: (sub) => {
      if (sub === "controllers") {
        return {
          get: async () => ({ forEach: () => {} }),
          doc: (id) => ({ _id: id }),
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
    getAll: async (...refs) =>
      refs.map((r) => ({
        id: r._id,
        exists: true,
        data: () => ({ ip: "192.168.1.150" }),
      })),
    collection: (name) => {
      if (name === "neighborhoods") {
        return {
          doc: () => ({
            get: async () => ({ data: () => ({ memberUids }) }),
            collection: () => ({
              get: async () => ({
                forEach: (cb) =>
                  Object.entries(members).forEach(([id, data]) =>
                    cb({ id, data: () => data })
                  ),
              }),
            }),
          }),
        };
      }
      if (name === "users") return { doc: usersDoc };
      throw new Error("unexpected collection: " + name);
    },
  };
  return { db, commands };
}

const run = (db) =>
  fanoutToCrew(db, {
    groupId: "g1",
    initiatorUid: A,
    payloadString: '{"seg":[{"fx":88}]}',
    sessionId: "s1",
    source: "sync_fanout",
  });

const paused = { participationStatus: "paused", controllerId: ["c_a"] };
const active = { participationStatus: "active", controllerId: ["c_b"] };

describe("#69 (a) — a PAUSED INITIATOR is served", () => {
  // The 3/4 run, as a regression scenario: A paused, B active, A broadcasts.
  test("the exact 2026-08-12 configuration now serves BOTH members", async () => {
    const { db, commands } = makeDb({
      members: { [A]: paused, [B]: active },
    });
    const out = await run(db);

    expect(out.memberCount).toBe(2);
    expect(out.commandCount).toBe(2);
    expect(out.skipped).toBe(0); // was 1 — A, silently
    expect(commands[A]).toHaveLength(1);
    expect(commands[B]).toHaveLength(1);
  });

  test("the initiator's command is a REAL one, not a placeholder", async () => {
    // A served-but-undeliverable command would satisfy the counters and still
    // leave the initiator's house dark — the #70 failure mode.
    const { db, commands } = makeDb({ members: { [A]: paused, [B]: active } });
    await run(db);
    const cmd = commands[A][0];
    expect(cmd.status).toBe("pending");
    expect(cmd.error).toBeUndefined();
    expect(cmd.controllerIp).toBe("192.168.1.150");
    expect(cmd.payload).toBe('{"seg":[{"fx":88}]}');
  });

  test("optedOut does not mute the initiator either", async () => {
    // The decision is about pause, but isMemberSkipped covers both states and
    // the exemption is keyed on identity, so both must behave the same.
    const { db, commands } = makeDb({
      members: { [A]: { participationStatus: "optedOut", controllerId: ["c_a"] } },
    });
    const out = await run(db);
    expect(out.skipped).toBe(0);
    expect(commands[A]).toHaveLength(1);
  });
});

describe("#69 (b) — an ACTIVE initiator is served (unchanged)", () => {
  test("no regression in the ordinary case", async () => {
    const { db, commands } = makeDb({
      members: { [A]: { ...active, controllerId: ["c_a"] }, [B]: active },
    });
    const out = await run(db);
    expect(out.memberCount).toBe(2);
    expect(out.commandCount).toBe(2);
    expect(out.skipped).toBe(0);
    expect(commands[A]).toHaveLength(1);
  });
});

describe("#69 (c) — a PAUSED NON-INITIATOR is still skipped", () => {
  // The half of pause that must NOT change. If this ever goes green-by-serving,
  // pause has stopped meaning anything.
  test("B paused, A active: B receives NOTHING", async () => {
    const { db, commands } = makeDb({
      members: {
        [A]: { ...active, controllerId: ["c_a"] },
        [B]: { participationStatus: "paused", controllerId: ["c_b"] },
      },
    });
    const out = await run(db);

    expect(out.memberCount).toBe(1);
    expect(out.commandCount).toBe(1);
    expect(out.skipped).toBe(1);
    expect(commands[A]).toHaveLength(1);
    expect(commands[B]).toBeUndefined();
  });

  test("the predicate itself is untouched", () => {
    // The fix is an identity exemption at the call site, NOT a relaxed
    // predicate. If someone later "simplifies" it into isMemberSkipped, this
    // fails and says so.
    expect(isMemberSkipped("paused")).toBe(true);
    expect(isMemberSkipped("optedOut")).toBe(true);
    expect(isMemberSkipped("active")).toBe(false);
  });
});

describe("#69 (d) — the skip stays LEGIBLE: count AND reason", () => {
  test("skipped is counted", async () => {
    const { db } = makeDb({
      members: {
        [A]: { ...active, controllerId: ["c_a"] },
        [B]: { participationStatus: "paused", controllerId: ["c_b"] },
      },
    });
    expect((await run(db)).skipped).toBe(1);
  });

  test("and the REASON is logged, naming the member and the status", async () => {
    // This branch used to be silent: it incremented `skipped` and returned. The
    // 3/4 run therefore reported skipped:1 with no reason anywhere, and the
    // cause had to be recovered by reading the roster by hand. A count without a
    // reason is what made #69 cost a diagnosis round.
    const warn = jest.spyOn(console, "warn").mockImplementation(() => {});
    try {
      const { db } = makeDb({
        members: {
          [A]: { ...active, controllerId: ["c_a"] },
          [B]: { participationStatus: "paused", controllerId: ["c_b"] },
        },
      });
      await run(db);
      const line = warn.mock.calls.map((c) => String(c[0])).join("\n");
      expect(line).toContain(B);
      expect(line).toContain("participationStatus=paused");
    } finally {
      warn.mockRestore();
    }
  });

  test("a SERVED paused initiator logs no skip line", async () => {
    // The corollary: silence on the happy path. A warning for a member who WAS
    // served would be its own kind of illegible.
    const warn = jest.spyOn(console, "warn").mockImplementation(() => {});
    try {
      const { db } = makeDb({ members: { [A]: paused, [B]: active } });
      await run(db);
      const line = warn.mock.calls.map((c) => String(c[0])).join("\n");
      expect(line).not.toContain("participationStatus=");
    } finally {
      warn.mockRestore();
    }
  });
});
