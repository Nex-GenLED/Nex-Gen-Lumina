// #98 — removeTeam tears down the team's still-scheduled fires.
//
// THE GAP IT CLOSES. Deleting a team stripped its profile entries and deleted
// its config and LEFT ITS ARMED FIRES BEHIND. `gd_mlb_royals_401816580_start`
// outlived `mlb_royals` by hours — state "scheduled", a real 130-byte
// on+bri+seg payload, a live controller, 4 h 13 m from firing.
//
// RETRACTED, NEVER DELETED (2026-08-18 convention): state -> "cancelled" plus
// cancelled_reason/cancelled_at, with fireAt and payload preserved. A deleted
// row cannot answer "what was armed, and what happened to it".
//
// Runs against compiled lib/ — `npm run build` first.

const {
  shouldRetractForTeam,
  CANCELLED_REASON_TEAM_DELETED,
} = require("../../lib/fireJobs");
const { retractTeamFires } = require("../../lib/teardownTeamFires");

// Fake Firestore: a users/{uid}/fire_jobs collection with a .where("state","==")
// query. Records every update so the test can assert what was written.
function makeDb(jobs) {
  const updates = [];
  const deletes = [];
  const docs = Object.entries(jobs).map(([id, data]) => ({
    id,
    get: (f) => data[f],
    ref: {
      update: async (patch) => { updates.push({ id, patch }); Object.assign(data, patch); },
      delete: async () => { deletes.push(id); },
    },
  }));
  const db = {
    collection: () => ({
      doc: () => ({
        collection: () => ({
          where: (field, op, value) => ({
            get: async () => ({
              docs: docs.filter((d) => {
                if (field !== "state" || op !== "==") throw new Error("unexpected query");
                return d.get("state") === value;
              }),
            }),
          }),
        }),
      }),
    }),
  };
  return { db, updates, deletes };
}

const royalsScheduled = () => ({
  gd_mlb_royals_401816580_start: {
    eventId: "gd_mlb_royals_401816580",
    state: "scheduled",
    fireAt: "TS_2026-08-18T23:10:00Z",
    payload: '{"on":true,"bri":180,"seg":[]}',
  },
});

// ---------------------------------------------------------------------------
// The pure selector
// ---------------------------------------------------------------------------
describe("shouldRetractForTeam", () => {
  test("the Royals ghost is selected", () => {
    expect(shouldRetractForTeam({
      eventId: "gd_mlb_royals_401816580", state: "scheduled", teamSlug: "mlb_royals",
    })).toBe(true);
  });

  test("ANOTHER team's scheduled fire is NOT selected", () => {
    expect(shouldRetractForTeam({
      eventId: "gd_nfl_chiefs_401816490", state: "scheduled", teamSlug: "mlb_royals",
    })).toBe(false);
  });

  // THE PREFIX TRAP. A literal startsWith("gd_" + slug) match would retract a
  // DIFFERENT team whose slug merely begins with this one.
  test("a slug that is a PREFIX of another team does not capture it", () => {
    expect(shouldRetractForTeam({
      eventId: "gd_ncaa_missouri_state_999", state: "scheduled", teamSlug: "ncaa_missouri",
    })).toBe(false);
    // ...and the real one still matches.
    expect(shouldRetractForTeam({
      eventId: "gd_ncaa_missouri_999", state: "scheduled", teamSlug: "ncaa_missouri",
    })).toBe(true);
  });

  test("ONLY scheduled is retractable — dispatched is already in flight", () => {
    for (const state of ["dispatched", "completed", "failed", "expired", "skipped", "cancelled"]) {
      expect(shouldRetractForTeam({
        eventId: "gd_mlb_royals_401816580", state, teamSlug: "mlb_royals",
      })).toBe(false);
    }
  });
});

// ---------------------------------------------------------------------------
// The teardown
// ---------------------------------------------------------------------------
describe("retractTeamFires — the deleted team's fires are retracted", () => {
  test("writes state/cancelled_reason/cancelled_at and NOTHING else", async () => {
    const jobs = royalsScheduled();
    const { db, updates } = makeDb(jobs);
    const out = await retractTeamFires({ db, uid: "u1", teamSlug: "mlb_royals" });

    expect(out).toEqual(["gd_mlb_royals_401816580_start"]);
    expect(updates).toHaveLength(1);
    expect(Object.keys(updates[0].patch).sort()).toEqual(
      ["cancelled_at", "cancelled_reason", "state"]
    );
    expect(updates[0].patch.state).toBe("cancelled");
    expect(updates[0].patch.cancelled_reason).toBe("team_deleted");
    expect(updates[0].patch.cancelled_reason).toBe(CANCELLED_REASON_TEAM_DELETED);
  });

  test("NEVER deletes — fireAt and payload survive intact", async () => {
    const jobs = royalsScheduled();
    const { db, deletes } = makeDb(jobs);
    await retractTeamFires({ db, uid: "u1", teamSlug: "mlb_royals" });

    expect(deletes).toEqual([]);
    const row = jobs.gd_mlb_royals_401816580_start;
    expect(row.fireAt).toBe("TS_2026-08-18T23:10:00Z");
    expect(row.payload).toBe('{"on":true,"bri":180,"seg":[]}');
  });

  test("leaves ANOTHER team's scheduled fire untouched", async () => {
    const jobs = Object.assign(royalsScheduled(), {
      gd_nfl_chiefs_401816490_start: {
        eventId: "gd_nfl_chiefs_401816490", state: "scheduled", payload: "{}",
      },
    });
    const { db, updates } = makeDb(jobs);
    const out = await retractTeamFires({ db, uid: "u1", teamSlug: "mlb_royals" });

    expect(out).toEqual(["gd_mlb_royals_401816580_start"]);
    expect(updates.map((u) => u.id)).not.toContain("gd_nfl_chiefs_401816490_start");
    expect(jobs.gd_nfl_chiefs_401816490_start.state).toBe("scheduled");
  });

  test("does NOT rewrite history — completed/dispatched rows are left alone", async () => {
    const jobs = {
      gd_mlb_royals_1_start: { eventId: "gd_mlb_royals_1", state: "completed" },
      gd_mlb_royals_2_start: { eventId: "gd_mlb_royals_2", state: "dispatched" },
    };
    const { db, updates } = makeDb(jobs);
    const out = await retractTeamFires({ db, uid: "u1", teamSlug: "mlb_royals" });

    expect(out).toEqual([]);
    expect(updates).toEqual([]);
  });

  test("a team with no fires retracts nothing and does not throw", async () => {
    const { db, updates } = makeDb({});
    await expect(
      retractTeamFires({ db, uid: "u1", teamSlug: "mlb_royals" })
    ).resolves.toEqual([]);
    expect(updates).toEqual([]);
  });

  test("retracts EVERY scheduled fire for the team, start and end alike", async () => {
    const jobs = {
      gd_mlb_royals_401816580_start: { eventId: "gd_mlb_royals_401816580", state: "scheduled" },
      gd_mlb_royals_401816580_end: { eventId: "gd_mlb_royals_401816580", state: "scheduled" },
      gd_mlb_royals_401816599_start: { eventId: "gd_mlb_royals_401816599", state: "scheduled" },
    };
    const { db } = makeDb(jobs);
    const out = await retractTeamFires({ db, uid: "u1", teamSlug: "mlb_royals" });
    expect(out).toHaveLength(3);
    for (const row of Object.values(jobs)) expect(row.state).toBe("cancelled");
  });
});
