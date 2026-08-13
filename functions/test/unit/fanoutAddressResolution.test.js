// #70 — a crew fanout command must carry a real destination.
//
// THE DEFECT, hardware-proven on 2026-08-12. resolveMemberTargets returned
// `{id, ip:""}` for every member whose doc carried a denormalized controllerId
// ARRAY — the normal shape — on the documented assumption that "the bridge
// self-resolves its paired WLED IP". The bridge cannot do that. A's two command
// docs from the 22:03/22:04Z fanouts:
//
//   controllerId: "192_168_1_150"   controllerIp: ""
//   error: "ERROR: HTTP -1"          status: "failed"
//
// So no crew fanout had ever reached hardware. It survived three §4 runs
// because the bench bridge-sim POSTs to its own stub and never reads
// controllerIp — it reported "delivered" for the command the real bridge
// refused.
//
// Two halves are locked here: the denorm branch now JOINS ids to addresses, and
// a target that still has no address is written FAILED with a legible
// `no_address` rather than dispatched at an empty host.

const {
  mergeDenormTargets,
  resolveMemberTargets,
  buildFanoutCommandDoc,
} = require("../../lib/applySyncPattern");

/** A db fake exposing only what resolveMemberTargets touches. */
function makeDb({ controllers = {}, getAllThrows = false, scanThrows = false }) {
  let getAllCalls = 0;
  const db = {
    getAll: async (...refs) => {
      getAllCalls++;
      if (getAllThrows) throw new Error("boom");
      return refs.map((r) => {
        const hit = Object.prototype.hasOwnProperty.call(controllers, r._id);
        return {
          id: r._id,
          exists: hit,
          data: () => ({ ip: controllers[r._id] }),
        };
      });
    },
    collection: () => ({
      doc: () => ({
        collection: () => ({
          doc: (id) => ({ _id: id }),
          get: async () => {
            if (scanThrows) throw new Error("scan boom");
            return {
              forEach: (cb) =>
                Object.entries(controllers).forEach(([id, ip]) =>
                  cb({ id, data: () => ({ ip }) })
                ),
            };
          },
        }),
      }),
    }),
  };
  return { db, calls: () => getAllCalls };
}

const doc = (over) =>
  buildFanoutCommandDoc(
    Object.assign(
      {
        payloadString: "{}",
        controllerId: "c1",
        controllerIp: "192.168.1.150",
        webhookUrl: null,
        source: "sync_fanout",
        initiatorUid: "u_init",
        sessionId: "s1",
      },
      over || {}
    )
  );

describe("mergeDenormTargets (pure join)", () => {
  test("attaches the resolved address to each id", () => {
    expect(
      mergeDenormTargets(["a", "b"], { a: "192.168.1.150", b: "10.0.0.9" })
    ).toMatchObject([
      { id: "a", ip: "192.168.1.150" },
      { id: "b", ip: "10.0.0.9" },
    ]);
  });

  test("an id absent from the map resolves to empty — never invented", () => {
    expect(mergeDenormTargets(["a", "ghost"], { a: "1.2.3.4" })).toMatchObject([
      { id: "a", ip: "1.2.3.4" },
      { id: "ghost", ip: "" },
    ]);
  });

  test("blank and whitespace addresses count as unresolved", () => {
    expect(mergeDenormTargets(["a", "b"], { a: "", b: "   " })).toMatchObject([
      { id: "a", ip: "" },
      { id: "b", ip: "" },
    ]);
  });

  test("order and cardinality follow the ids, not the map", () => {
    const out = mergeDenormTargets(["b", "a"], { a: "1", b: "2", z: "9" });
    expect(out.map((t) => t.id)).toEqual(["b", "a"]);
    expect(out).toHaveLength(2);
  });
});

describe("resolveMemberTargets — SHAPE 1: denormalized controllerId array", () => {
  test("THE REGRESSION: a resolved target carries a NON-EMPTY ip", async () => {
    const { db } = makeDb({ controllers: { "192_168_1_150": "192.168.1.150" } });
    const out = await resolveMemberTargets(db, "uA", {
      controllerId: ["192_168_1_150"],
    });
    expect(out).toMatchObject([
      { id: "192_168_1_150", ip: "192.168.1.150" }]);
    // The exact assertion the old code failed. Stated separately so a future
    // refactor that reintroduces ip:"" fails on the claim, not on a deep-equal.
    expect(out[0].ip).not.toBe("");
  });

  test("multiple ids each get their own address", async () => {
    const { db } = makeDb({ controllers: { c1: "10.0.0.1", c2: "10.0.0.2" } });
    const out = await resolveMemberTargets(db, "uA", {
      controllerId: ["c1", "c2"],
    });
    expect(out).toMatchObject([
      { id: "c1", ip: "10.0.0.1" },
      { id: "c2", ip: "10.0.0.2" },
    ]);
  });

  test("non-string / empty entries are filtered before the join", async () => {
    const { db } = makeDb({ controllers: { c1: "10.0.0.1" } });
    const out = await resolveMemberTargets(db, "uA", {
      controllerId: ["c1", "", null, 42],
    });
    expect(out).toMatchObject([
      { id: "c1", ip: "10.0.0.1" }]);
  });

  test("an UNRESOLVABLE id yields a target with no address, not a guess",
    async () => {
      const { db } = makeDb({ controllers: {} });
      const out = await resolveMemberTargets(db, "uA", {
        controllerId: ["ghost"],
      });
      expect(out).toMatchObject([
      { id: "ghost", ip: "" }]);
    });

  test("a failed join does NOT fall through to the subcollection scan",
    async () => {
      // Falling back would command controllers the member never named —
      // widening the blast radius on an error path. Unknown stays unknown.
      const { db } = makeDb({
        controllers: { other: "10.9.9.9" },
        getAllThrows: true,
      });
      const out = await resolveMemberTargets(db, "uA", {
        controllerId: ["c1"],
      });
      expect(out).toMatchObject([
      { id: "c1", ip: "" }]);
    });
});

describe("resolveMemberTargets — SHAPE 2: no denorm array (fallback preserved)",
  () => {
    test("reads the controllers subcollection live, with addresses", async () => {
      const { db, calls } = makeDb({
        controllers: { c1: "10.0.0.1", c2: "10.0.0.2" },
      });
      const out = await resolveMemberTargets(db, "uA", {});
      expect(out).toMatchObject([
      { id: "c1", ip: "10.0.0.1" },
        { id: "c2", ip: "10.0.0.2" },
      ]);
      expect(calls()).toBe(0); // the join is not used by this shape
    });

    test("an empty array is not a denorm shape — it falls back", async () => {
      const { db } = makeDb({ controllers: { c1: "10.0.0.1" } });
      const out = await resolveMemberTargets(db, "uA", { controllerId: [] });
      expect(out).toMatchObject([
      { id: "c1", ip: "10.0.0.1" }]);
    });

    test("legacy single controllerIp on the member doc still wins over nothing",
      async () => {
        const { db } = makeDb({ controllers: {}, scanThrows: true });
        const out = await resolveMemberTargets(db, "uA", {
          controllerIp: "172.16.0.5",
        });
        expect(out).toMatchObject([
      { id: "", ip: "172.16.0.5" }]);
      });

    test("nothing at all -> a single addressless target", async () => {
      const { db } = makeDb({ controllers: {} });
      expect(await resolveMemberTargets(db, "uA", {})).toMatchObject([
      { id: "", ip: "" },
      ]);
    });
  });

describe("#67 — channel facts ride along on the SAME read", () => {
  // The partition needs the device's channel set. Fetching it separately would
  // double the reads for a fact that lives on the controller doc we already
  // have in hand, so resolveMemberTargets carries it out with the address.
  test("device + participating ids come back with the target", async () => {
    const db = {
      getAll: async (...refs) =>
        refs.map((r) => ({
          id: r._id,
          exists: true,
          data: () => ({
            ip: "192.168.1.150",
            participating_channels_device_ids: [0, 1],
            participating_channels: [0],
          }),
        })),
      collection: () => ({ doc: () => ({ collection: () => ({ doc: (id) => ({ _id: id }) }) }) }),
    };
    const out = await resolveMemberTargets(db, "uA", { controllerId: ["c_a"] });
    expect(out[0].deviceChannelIds).toEqual([0, 1]);
    expect(out[0].participatingChannelIds).toEqual([0]);
  });

  test("absent facts are NULL, never an empty array", async () => {
    // [] would claim "this controller has no channels" — a fabricated fact that
    // would darken everything. Null means "unknown" and triggers the fallback.
    const db = {
      getAll: async (...refs) =>
        refs.map((r) => ({ id: r._id, exists: true, data: () => ({ ip: "1.2.3.4" }) })),
      collection: () => ({ doc: () => ({ collection: () => ({ doc: (id) => ({ _id: id }) }) }) }),
    };
    const out = await resolveMemberTargets(db, "uA", { controllerId: ["c_a"] });
    expect(out[0].deviceChannelIds).toBeNull();
    expect(out[0].participatingChannelIds).toBeNull();
  });
});

describe("buildFanoutCommandDoc — an addressless command is born failed", () => {
  test("a real ip -> pending, no error field", () => {
    const d = doc();
    expect(d.status).toBe("pending");
    expect(d.error).toBeUndefined();
  });

  test("THE FIX: empty ip -> failed + no_address, never pending", () => {
    const d = doc({ controllerIp: "" });
    expect(d.status).toBe("failed");
    expect(d.error).toBe("no_address");
  });

  test("whitespace is not an address", () => {
    expect(doc({ controllerIp: "   " }).status).toBe("failed");
  });

  test("the doc is still WRITTEN — silence would be worse than a failure", () => {
    // It is the evidence that a member was meant to be commanded.
    const d = doc({ controllerIp: "" });
    expect(d.controllerId).toBe("c1");
    expect(d.payload).toBe("{}");
    expect(d.initiatorUid).toBe("u_init");
  });

  // The direction that would have broken a WORKING path. executeWledCommand
  // (functions/index.js:398) routes on webhookUrl and never reads controllerIp,
  // so a Webhook-Mode member legitimately has no IP.
  test("WEBHOOK MODE: no ip but a webhookUrl -> pending, NOT no_address", () => {
    const d = doc({ controllerIp: "", webhookUrl: "https://home.example:8080" });
    expect(d.status).toBe("pending");
    expect(d.error).toBeUndefined();
  });

  test("neither ip nor webhook -> failed", () => {
    expect(doc({ controllerIp: "", webhookUrl: "" }).status).toBe("failed");
    expect(doc({ controllerIp: "", webhookUrl: null }).status).toBe("failed");
  });

  test("a blank webhook does not rescue a blank ip", () => {
    expect(doc({ controllerIp: "", webhookUrl: "  " }).status).toBe("failed");
  });
});
