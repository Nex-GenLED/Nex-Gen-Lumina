// #99 — the dispatch-time team-config existence gate.
//
// WHAT IT IS FOR, and it was caught in the wild, not imagined:
// `gd_mlb_royals_401816580_start` was planned while `mlb_royals` existed, the
// team was deleted afterwards, and NOTHING tore the job down. It sat
// `state:"scheduled"` with a real 130-byte `on+bri+seg` payload aimed at a live
// controller (192_168_1_150), 4 h 13 m from firing, for a team the user had
// removed. The planner's `.where("enabled","==",true)` was true when the row was
// written and says nothing about dispatch time.
//
// Runs against compiled lib/ — `npm run build` first.

const {
  checkTeamConfigGate,
  teamSlugFromEventId,
  CONFIG_GATE_SKIP_REASON,
} = require("../../lib/fireJobs");

// ---------------------------------------------------------------------------
// Fake Firestore. Object literal, same shape as the other unit tests use — no
// emulator, no IO. `configs` maps teamSlug -> doc data (or absent for deleted).
// ---------------------------------------------------------------------------
function makeDb({ configs = {}, reads = [] } = {}) {
  const db = {
    collection: (c1) => ({
      doc: (uid) => ({
        collection: (c2) => ({
          doc: (slug) => ({
            get: async () => {
              reads.push({ c1, uid, c2, slug });
              const data = configs[slug];
              return {
                exists: data !== undefined,
                get: (field) => (data === undefined ? undefined : data[field]),
              };
            },
          }),
        }),
      }),
    }),
  };
  return { db, reads };
}

const ROYALS_EVENT = "gd_mlb_royals_401816580";

// ---------------------------------------------------------------------------
// teamSlugFromEventId — the parsing trap
// ---------------------------------------------------------------------------
describe("teamSlugFromEventId — slugs contain underscores", () => {
  // THE TRAP. A greedy /^gd_(.+)_(\d+)$/ returns "mlb_royals_40181649" + "0"
  // here. That slug does not exist, so the gate would refuse EVERY Game Day
  // fire in the fleet. Every live slug below is a real one from the fleet.
  test.each([
    ["gd_mlb_royals_401816580", "mlb_royals"],
    ["gd_mls_sporting_kc_401816490", "mls_sporting_kc"],
    ["gd_ncaamb_kansas_state_555", "ncaamb_kansas_state"],
    ["gd_nwsl_kc_current_1", "nwsl_kc_current"],
    ["gd_nfl_chiefs_401816490", "nfl_chiefs"],
  ])("%s -> %s", (eventId, slug) => {
    expect(teamSlugFromEventId(eventId)).toBe(slug);
  });

  test("a slug ending in digits still parses (49ers-shaped)", () => {
    expect(teamSlugFromEventId("gd_nfl_49ers_401816490")).toBe("nfl_49ers");
  });

  test("NON-Game-Day ids yield null — the gate must not apply to them", () => {
    // A fire job that is not a Game Day event has no team config, and must
    // never be terminal-skipped for failing to have one.
    for (const id of ["health_192_168_1_150_123", "sync_abc", "gd_noDigits", ""]) {
      expect(teamSlugFromEventId(id)).toBeNull();
    }
  });

  test("non-string eventId yields null rather than throwing", () => {
    for (const v of [undefined, null, 42, {}, []]) {
      expect(teamSlugFromEventId(v)).toBeNull();
    }
  });
});

// ---------------------------------------------------------------------------
// The gate — BOTH directions
// ---------------------------------------------------------------------------
describe("checkTeamConfigGate — the ghost shape is refused", () => {
  test("CONFIG DELETED AFTER PLANNING -> refused (the Royals case)", async () => {
    const { db } = makeDb({ configs: {} }); // mlb_royals is gone
    const r = await checkTeamConfigGate({ db, uid: "u1", eventId: ROYALS_EVENT });
    expect(r.ok).toBe(false);
    expect(r.reason).toBe("config_missing_or_disabled");
    expect(r.reason).toBe(CONFIG_GATE_SKIP_REASON);
  });

  test("config present but enabled:false -> refused", async () => {
    const { db } = makeDb({ configs: { mlb_royals: { enabled: false } } });
    const r = await checkTeamConfigGate({ db, uid: "u1", eventId: ROYALS_EVENT });
    expect(r.ok).toBe(false);
    expect(r.reason).toBe(CONFIG_GATE_SKIP_REASON);
  });

  test("enabled is STRICTLY === true; truthy look-alikes are NOT armed", async () => {
    // Mirrors the planner's .where("enabled","==",true). A string "true" or a 1
    // would pass a loose check and arm a team Firestore itself would not select.
    for (const v of ["true", 1, {}, [], "yes"]) {
      const { db } = makeDb({ configs: { mlb_royals: { enabled: v } } });
      const r = await checkTeamConfigGate({ db, uid: "u1", eventId: ROYALS_EVENT });
      expect(r.ok).toBe(false);
    }
  });

  test("config exists but has NO enabled field -> refused", async () => {
    const { db } = makeDb({ configs: { mlb_royals: { sport: "mlb" } } });
    const r = await checkTeamConfigGate({ db, uid: "u1", eventId: ROYALS_EVENT });
    expect(r.ok).toBe(false);
  });
});

describe("checkTeamConfigGate — a live team still dispatches", () => {
  // The other direction, and it is the one that matters: a gate that refuses
  // everything would also "fix" the Royals case, while breaking Game Day.
  test("VALID enabled config -> passes", async () => {
    const { db } = makeDb({ configs: { mlb_royals: { enabled: true } } });
    const r = await checkTeamConfigGate({ db, uid: "u1", eventId: ROYALS_EVENT });
    expect(r.ok).toBe(true);
    expect(r.reason).toBeUndefined();
  });

  test("enabled config with the other real fleet fields -> passes", async () => {
    const { db } = makeDb({
      configs: {
        nfl_chiefs: {
          enabled: true,
          sport: "nfl",
          espn_team_id: "12",
          team_name: "Kansas City Chiefs",
        },
      },
    });
    const r = await checkTeamConfigGate({
      db, uid: "u1", eventId: "gd_nfl_chiefs_401816490",
    });
    expect(r.ok).toBe(true);
  });

  test("a NON-Game-Day job passes WITHOUT reading any config", async () => {
    // The health probe path shares fire_jobs shape. It has no team, so the gate
    // must not read, and must not refuse.
    const { db, reads } = makeDb({ configs: {} });
    const r = await checkTeamConfigGate({
      db, uid: "u1", eventId: "health_192_168_1_150_1787104515",
    });
    expect(r.ok).toBe(true);
    expect(reads).toHaveLength(0);
  });

  test("reads the RIGHT path: users/{uid}/game_day_autopilot/{teamSlug}", async () => {
    const { db, reads } = makeDb({ configs: { mlb_royals: { enabled: true } } });
    await checkTeamConfigGate({ db, uid: "u_bench", eventId: ROYALS_EVENT });
    expect(reads).toEqual([
      { c1: "users", uid: "u_bench", c2: "game_day_autopilot", slug: "mlb_royals" },
    ]);
  });

  test("a read error PROPAGATES — never silently fail-open or fail-closed", async () => {
    // A transient Firestore fault must not become a permanent skip. It reaches
    // the dispatcher's per-job try/catch and is counted as an error.
    const db = {
      collection: () => ({
        doc: () => ({
          collection: () => ({
            doc: () => ({ get: async () => { throw new Error("firestore boom"); } }),
          }),
        }),
      }),
    };
    await expect(
      checkTeamConfigGate({ db, uid: "u1", eventId: ROYALS_EVENT })
    ).rejects.toThrow("firestore boom");
  });
});
