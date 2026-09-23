// planGameDayFires × the team hierarchy — the REAL planner tick, driven
// through an in-memory Firestore and a mocked ESPN client.
//
// THE DEFECT (audit at 6f53707, and the +106 commit's own "Server planner
// deliberately untouched"): the planner planned every enabled team alone, and
// each team's `_end` base-restored at its own final. Two teams the same night
// → the first game to finish put the house back to base part-way through the
// second. The app fixed this at 40100cb with an ordered hierarchy, deferral,
// and hand-off; this suite pins the same semantics on the server path.
//
// Also pinned: DEFECT 2 — the app writes `lead_time_minutes_override`, the
// planner read `lead_time_minutes`, so every fire went out 30 minutes before
// kickoff whatever the user chose.
//
// Times are the evening of 2026-10-04, US Central (UTC−5), written as local
// clock hours through `at()`. Runs against compiled lib/ — `npm run build`.

jest.mock("../../lib/espnClient", () => ({
  fetchTeamGame: jest.fn(async () => null),
}));

const admin = require("firebase-admin");
const { fetchTeamGame } = require("../../lib/espnClient");
const { runPlannerTick } = require("../../lib/planGameDayFires");
const { BASE_ON_PRESET } = require("../../lib/gameDayPlanning");

const M = 60_000;
const H = 60 * M;
/** Local CDT clock → epoch ms on game day. */
const at = (h, m = 0) => Date.UTC(2026, 9, 4, h + 5, m, 0);

const UID = "u_test";
const CTRL = "ctrl_1";
const ARMED = { forcePolicy: { enabled: true, allowlist: null } };

// Real fleet colours (ARGB ints as the app stores them).
const TEAMS = {
  nfl_chiefs: { sport: "nfl", espn: "12", name: "Kansas City Chiefs", primary: 0xffe31837, secondary: 0xffffb81c },
  mlb_royals: { sport: "mlb", espn: "7", name: "Kansas City Royals", primary: 0xff004687, secondary: 0xffc09a5b },
  nba_thunder: { sport: "nba", espn: "25", name: "Oklahoma City Thunder", primary: 0xff007ac1, secondary: 0xffef6f1c },
  nhl_blues: { sport: "nhl", espn: "19", name: "St. Louis Blues", primary: 0xff002f87, secondary: 0xfffcb514 },
};
const RGB = {
  nfl_chiefs: [227, 24, 55, 0],
  mlb_royals: [0, 70, 135, 0],
  nba_thunder: [0, 122, 193, 0],
  nhl_blues: [0, 47, 135, 0],
};

// ---------------------------------------------------------------------------
// In-memory Firestore. Path-keyed, doc-id ordered, with the exact surface the
// planner uses: collection().get(), .where("f","==",v), .doc().get/set/update/
// create(), and users/{uid}.ref.set(). FieldValue sentinels are stored as-is.
// ---------------------------------------------------------------------------
function makeDb(seed) {
  const store = new Map();
  const writes = [];
  const reads = [];
  const parentOf = (p) => p.split("/").slice(0, -1).join("/");
  const idOf = (p) => p.split("/").pop();

  const snap = (path) => {
    const data = store.get(path);
    return {
      id: idOf(path),
      exists: data !== undefined,
      data: () => (data === undefined ? undefined : { ...data }),
      get: (f) => (data === undefined ? undefined : data[f]),
      ref: docRef(path),
    };
  };
  const docRef = (path) => ({
    id: idOf(path),
    path,
    collection: (name) => collRef(`${path}/${name}`),
    get: async () => { reads.push(path); return snap(path); },
    set: async (data, opts) => {
      const prev = store.get(path);
      store.set(path, opts && opts.merge && prev ? { ...prev, ...data } : { ...data });
      writes.push({ op: "set", path, data });
    },
    update: async (data) => {
      const prev = store.get(path);
      if (prev === undefined) throw new Error(`update on missing ${path}`);
      store.set(path, { ...prev, ...data });
      writes.push({ op: "update", path, data });
    },
    create: async (data) => {
      if (store.has(path)) { const e = new Error("already exists"); e.code = 6; throw e; }
      store.set(path, { ...data });
      writes.push({ op: "create", path, data });
    },
  });
  const collRef = (path, filters = []) => ({
    doc: (id) => docRef(`${path}/${id}`),
    where: (f, op, v) => {
      if (op !== "==") throw new Error(`unexpected op ${op}`);
      return collRef(path, [...filters, [f, v]]);
    },
    limit: () => collRef(path, filters),
    get: async () => {
      const docs = [...store.keys()]
        .filter((p) => parentOf(p) === path)
        .sort()
        .map(snap)
        .filter((s) => filters.every(([f, v]) => s.get(f) === v));
      return { docs, empty: docs.length === 0 };
    },
  });
  for (const [path, data] of Object.entries(seed)) store.set(path, { ...data });
  return {
    db: { collection: (name) => collRef(name) },
    store, writes, reads,
    get: (p) => store.get(p),
    job: (id) => store.get(`users/${UID}/fire_jobs/${id}`),
    session: (eventId) => store.get(`users/${UID}/game_day_sessions/${eventId}`),
    /** The dispatcher, in one line. */
    dispatched: (id) => { const j = store.get(`users/${UID}/fire_jobs/${id}`); if (!j) throw new Error(`no job ${id}`); j.state = "completed"; },
  };
}

/**
 * Seed one account: a controller with fresh participation facts (so the gate
 * arms and participation resolves), plus the given enabled configs.
 */
function seed({ user = {}, configs }) {
  const s = {
    [`users/${UID}`]: { ...user },
    [`users/${UID}/controllers/${CTRL}`]: {
      ip: "192.168.1.150",
      participating_channels: [0, 1],
      participating_channels_device_ids: [0, 1],
      participating_channels_at: { toMillis: () => at(0) },
    },
  };
  for (const [slug, over] of Object.entries(configs)) {
    const t = TEAMS[slug];
    s[`users/${UID}/game_day_autopilot/${slug}`] = {
      enabled: true,
      team_slug: slug,
      team_name: t.name,
      sport: t.sport,
      espn_team_id: t.espn,
      primary_color: t.primary,
      secondary_color: t.secondary,
      effect_id: 0,
      brightness: 200,
      ...(over || {}),
    };
  }
  return s;
}

/** ESPN state per team, mutable between ticks. */
function games(spec) {
  const byId = {};
  for (const [slug, g] of Object.entries(spec)) {
    const t = TEAMS[slug];
    byId[t.espn] = {
      gameId: g.gameId,
      startMs: g.startMs,
      isFinal: false,
      isInProgress: false,
      statusName: "STATUS_SCHEDULED",
      homeTeamId: t.espn,
      awayTeamId: "0",
      ...g,
    };
  }
  fetchTeamGame.mockImplementation(async (_sport, espnTeamId) => byId[espnTeamId] ?? null);
  const set = (slug, patch) => Object.assign(byId[TEAMS[slug].espn], patch);
  return {
    live: (slug) => set(slug, { isInProgress: true, isFinal: false, statusName: "STATUS_IN_PROGRESS" }),
    final: (slug) => set(slug, { isInProgress: false, isFinal: true, statusName: "STATUS_FINAL" }),
    set,
  };
}

const ev = (slug, gameId) => `gd_${slug}_${gameId}`;
const payloadOf = (job) => JSON.parse(job.payload);
const firstColor = (job) => payloadOf(job).seg[0].col[0];
const tick = (db, t) => runPlannerTick(db, t, ARMED);
const rows = (res, pred) => res.logRows.filter(pred);

beforeEach(() => {
  fetchTeamGame.mockReset();
  fetchTeamGame.mockImplementation(async () => null);
});

// ---------------------------------------------------------------------------
// THE HAND-OFF — the case that matters
// ---------------------------------------------------------------------------
describe("hand-off: the #1 team's game ends first, the #2 team is still live", () => {
  // Chiefs (#1) 18:00 NFL, Royals (#2) 19:00 MLB. Windows: 17:30 and 18:30.
  const CH = ev("nfl_chiefs", "401");
  const RO = ev("mlb_royals", "402");

  function scenario() {
    const f = makeDb(seed({
      user: { game_day_team_priority: ["nfl_chiefs", "mlb_royals"] },
      configs: { mlb_royals: {}, nfl_chiefs: {} }, // doc-id order puts Royals first
    }));
    const g = games({
      nfl_chiefs: { gameId: "401", startMs: at(18) },
      mlb_royals: { gameId: "402", startMs: at(19) },
    });
    return { f, g };
  }

  test("planning: the Chiefs start is written, the Royals start is DEFERRED — no job", async () => {
    const { f } = scenario();
    const r = await tick(f.db, at(13)); // both windows inside the 6 h horizon

    expect(f.job(`${CH}_start`)).toBeDefined();
    expect(f.job(`${CH}_start`).fireAt.toMillis()).toBe(at(17, 30));
    expect(f.job(`${RO}_start`)).toBeUndefined();

    expect(r.startsPlanned).toBe(1);
    expect(r.skipped).toEqual({ deferred_to_higher_priority: 1 });
    // The START invariant still reconciles: one bucket per config.
    expect(r.startsPlanned + Object.values(r.skipped).reduce((a, b) => a + b, 0)).toBe(r.configsEnabled);

    const deferred = rows(r, (x) => x.reason === "deferred_to_higher_priority");
    expect(deferred).toHaveLength(1);
    expect(deferred[0]).toMatchObject({ teamSlug: "mlb_royals", deferredTo: "nfl_chiefs", eventId: RO });
    // Deferral is tracked, not written: the Royals session carries no start.
    expect(f.session(RO)?.startPlannedAt).toBeUndefined();
  });

  test("planning is the same whichever way the docs sort — the hierarchy is walked, not doc-id order", async () => {
    // Same setup with the priority reversed puts the house with the Royals.
    const f = makeDb(seed({
      user: { game_day_team_priority: ["mlb_royals", "nfl_chiefs"] },
      configs: { mlb_royals: {}, nfl_chiefs: {} },
    }));
    games({ nfl_chiefs: { gameId: "401", startMs: at(18) }, mlb_royals: { gameId: "402", startMs: at(19) } });
    const r = await tick(f.db, at(13));
    // Royals #1: their start fires. Chiefs #2 window opens BEFORE the Royals'
    // — nothing is holding the house at 17:30 — so the Chiefs start fires too
    // and the Royals start repaints over it at 18:30 (the preempt).
    expect(f.job(`${CH}_start`)).toBeDefined();
    expect(f.job(`${RO}_start`)).toBeDefined();
    expect(r.skipped).toEqual({});
  });

  test("THE HAND-OFF: Chiefs final → the Chiefs end job carries the ROYALS design, not a base restore", async () => {
    const { f, g } = scenario();
    await tick(f.db, at(13));
    f.dispatched(`${CH}_start`);

    g.live("nfl_chiefs"); g.live("mlb_royals");
    let r = await tick(f.db, at(19, 5));
    expect(r.endsPlanned).toBe(0);
    // The deferred Royals now sit on start_time_passed, and the row says why.
    expect(rows(r, (x) => x.reason === "start_time_passed")[0]).toMatchObject({ teamSlug: "mlb_royals", deferredTo: "nfl_chiefs" });

    g.final("nfl_chiefs");
    r = await tick(f.db, at(21, 35)); // final poll 1
    expect(r.endsPlanned).toBe(0);
    expect(f.job(`${CH}_end`)).toBeUndefined();

    r = await tick(f.db, at(21, 40)); // final poll 2 → confirmed
    expect(r.endsPlanned).toBe(1);
    expect(r.handoffsPlanned).toBe(1);

    const end = f.job(`${CH}_end`);
    expect(end).toBeDefined();
    expect(end.seq).toBe("end");
    expect(end.type).toBe("applyJson");
    const p = payloadOf(end);
    expect(p.ps).toBeUndefined();               // NOT a preset load
    expect(p.on).toBe(true);
    expect(firstColor(end)).toEqual(RGB.mlb_royals); // the SURVIVOR's colours
    expect(end.handoffTo).toBe(RO);
    expect(end.handoffToTeam).toBe("mlb_royals");

    const planEnd = rows(r, (x) => x.action === "plan_end");
    expect(planEnd).toHaveLength(1);
    expect(planEnd[0]).toMatchObject({ teamSlug: "nfl_chiefs", reason: "confirmed_final", handoffTo: "mlb_royals" });

    // The survivor is now STARTED: GUARD 0 will let its own end fire, and
    // GUARD 0b knows which job lit it.
    const ro = f.session(RO);
    expect(ro.startPlannedAt).toBeDefined();
    expect(ro.startJobId).toBe(`${CH}_end`);
    expect(ro.handedOffFrom).toBe(CH);
    expect(f.session(CH).handedOffTo).toBe(RO);
    expect(f.session(CH).endFiredAt).toBeDefined();
  });

  test("…and when the Royals then end, THEIR end restores base — the last team out turns the house back", async () => {
    const { f, g } = scenario();
    await tick(f.db, at(13));
    f.dispatched(`${CH}_start`);
    g.live("nfl_chiefs"); g.live("mlb_royals");
    g.final("nfl_chiefs");
    await tick(f.db, at(21, 35));
    await tick(f.db, at(21, 40));
    f.dispatched(`${CH}_end`); // the hand-off reached the device

    g.final("mlb_royals");
    let r = await tick(f.db, at(22, 5));  // Royals counter: 0 → 1 (it was frozen while deferred)
    expect(f.job(`${RO}_end`)).toBeUndefined();
    r = await tick(f.db, at(22, 10));     // 2 → confirmed
    expect(r.endsPlanned).toBe(1);
    expect(r.handoffsPlanned).toBe(0);

    const end = f.job(`${RO}_end`);
    expect(end).toBeDefined();
    expect(payloadOf(end)).toEqual({ ps: BASE_ON_PRESET }); // base restore
    expect(end.handoffTo).toBeUndefined();
    expect(rows(r, (x) => x.action === "plan_end")[0].handoffTo).toBeUndefined();
    // No Royals start job ever existed; the hand-off job is what lit them.
    expect(f.job(`${RO}_start`)).toBeUndefined();
  });

  test("the hand-off end is refused by GUARD 0b if the hand-off job never reached the device", async () => {
    const { f, g } = scenario();
    await tick(f.db, at(13));
    f.dispatched(`${CH}_start`);
    g.live("nfl_chiefs"); g.live("mlb_royals");
    g.final("nfl_chiefs");
    await tick(f.db, at(21, 35));
    await tick(f.db, at(21, 40));
    // NOT dispatched: leave `${CH}_end` scheduled.
    g.final("mlb_royals");
    await tick(f.db, at(22, 5));
    const r = await tick(f.db, at(22, 10));
    expect(f.job(`${RO}_end`)).toBeUndefined();
    expect(r.endSkipped).toEqual({ "end:start_never_dispatched": 1 });
    expect(rows(r, (x) => x.reason === "end_skipped_start_never_dispatched")[0]).toMatchObject({ teamSlug: "mlb_royals", startJobState: "scheduled" });
  });

  test("ESPN is read once per (sport, team) per tick and each session once — the pre-pass adds no reads", async () => {
    const { f } = scenario();
    await tick(f.db, at(13));
    expect(fetchTeamGame).toHaveBeenCalledTimes(2);
    const sessionReads = f.reads.filter((p) => p.includes("/game_day_sessions/"));
    expect(sessionReads.sort()).toEqual(
      [`users/${UID}/game_day_sessions/${CH}`, `users/${UID}/game_day_sessions/${RO}`].sort()
    );
  });
});

// ---------------------------------------------------------------------------
// THE DARK-MID-GAME BUG, from the other side: the LOWER team ends first
// ---------------------------------------------------------------------------
describe("the lower-ranked team's game ends first: its end is SUPPRESSED, the house stays with #1", () => {
  // Royals (#2) 18:00 MLB, Chiefs (#1) 19:00 NFL. Windows: 17:30 and 18:30.
  const CH = ev("nfl_chiefs", "401");
  const RO = ev("mlb_royals", "402");

  function scenario() {
    const f = makeDb(seed({
      user: { game_day_team_priority: ["nfl_chiefs", "mlb_royals"] },
      configs: { mlb_royals: {}, nfl_chiefs: {} },
    }));
    const g = games({
      nfl_chiefs: { gameId: "401", startMs: at(19) },
      mlb_royals: { gameId: "402", startMs: at(18) },
    });
    return { f, g };
  }

  test("both starts fire (the Royals were alone at 17:30; the Chiefs preempt at 18:30)", async () => {
    const { f } = scenario();
    const r = await tick(f.db, at(13));
    expect(f.job(`${RO}_start`).fireAt.toMillis()).toBe(at(17, 30));
    expect(f.job(`${CH}_start`).fireAt.toMillis()).toBe(at(18, 30));
    expect(r.startsPlanned).toBe(2);
    expect(r.skipped).toEqual({});
  });

  test("Royals final while the Chiefs are live → NO base restore; recorded as not_owner", async () => {
    const { f, g } = scenario();
    await tick(f.db, at(13));
    f.dispatched(`${RO}_start`); f.dispatched(`${CH}_start`);
    g.live("mlb_royals"); g.live("nfl_chiefs");

    g.final("mlb_royals");
    await tick(f.db, at(21, 5));
    const r = await tick(f.db, at(21, 10)); // Royals confirmed final

    // BEFORE THIS CHANGE: a {"ps":N} end job was written here and the house
    // went to base in the middle of the Chiefs game.
    expect(f.job(`${RO}_end`)).toBeUndefined();
    expect(r.endsPlanned).toBe(0);
    expect(r.endSkipped).toEqual({ "end:not_owner": 1 });
    expect(rows(r, (x) => x.reason === "end_suppressed_not_owner")[0]).toMatchObject({ teamSlug: "mlb_royals", owner: "nfl_chiefs" });
    // Recorded once, so it never re-fires.
    const ro = f.session(RO);
    expect(ro.endFiredAt).toBeDefined();
    expect(ro.endOutcome).toBe("not_owner");
    expect(ro.endYieldedTo).toBe(CH);

    // …and it stays suppressed on later ticks (already_fired).
    const r2 = await tick(f.db, at(21, 15));
    expect(f.job(`${RO}_end`)).toBeUndefined();
    expect(r2.endSkipped).toEqual({});
  });

  test("then the Chiefs end: nobody is left, so THEIR end restores base", async () => {
    const { f, g } = scenario();
    await tick(f.db, at(13));
    f.dispatched(`${RO}_start`); f.dispatched(`${CH}_start`);
    g.live("mlb_royals"); g.live("nfl_chiefs");
    g.final("mlb_royals");
    await tick(f.db, at(21, 5));
    await tick(f.db, at(21, 10));

    g.final("nfl_chiefs");
    await tick(f.db, at(22, 35));
    const r = await tick(f.db, at(22, 40));
    expect(r.endsPlanned).toBe(1);
    expect(r.handoffsPlanned).toBe(0);
    expect(payloadOf(f.job(`${CH}_end`))).toEqual({ ps: BASE_ON_PRESET });
  });
});

// ---------------------------------------------------------------------------
// THREE OVERLAPPING TEAMS — the chain A → B → C → base
// ---------------------------------------------------------------------------
describe("three overlapping teams: A → B → C → base, in rank order", () => {
  // Chiefs (#1) 18:00 NFL, Thunder (#2) 19:30 NBA, Blues (#3) 20:00 NHL.
  // Windows: 17:30, 19:00, 19:30. Window ends: 22:30, 23:00, 23:30.
  const A = ev("nfl_chiefs", "401");
  const B = ev("nba_thunder", "403");
  const C = ev("nhl_blues", "404");

  function scenario() {
    const f = makeDb(seed({
      user: { game_day_team_priority: ["nfl_chiefs", "nba_thunder", "nhl_blues"] },
      configs: { nhl_blues: {}, nba_thunder: {}, nfl_chiefs: {} },
    }));
    const g = games({
      nfl_chiefs: { gameId: "401", startMs: at(18) },
      nba_thunder: { gameId: "403", startMs: at(19, 30) },
      nhl_blues: { gameId: "404", startMs: at(20) },
    });
    return { f, g };
  }

  test("only the #1 start is written; #2 and #3 both defer to #1 (not to each other)", async () => {
    const { f } = scenario();
    let r = await tick(f.db, at(13, 30)); // Blues window (19:30) is exactly at the horizon edge
    expect(f.job(`${A}_start`)).toBeDefined();
    expect(f.job(`${B}_start`)).toBeUndefined();
    expect(f.job(`${C}_start`)).toBeUndefined();
    expect(r.skipped).toEqual({ deferred_to_higher_priority: 1, outside_horizon: 1 });
    r = await tick(f.db, at(13, 35));
    expect(r.skipped).toEqual({ start_already_planned: 1, deferred_to_higher_priority: 2 });
    const deferred = rows(r, (x) => x.reason === "deferred_to_higher_priority");
    expect(deferred.map((x) => [x.teamSlug, x.deferredTo]).sort()).toEqual([
      ["nba_thunder", "nfl_chiefs"],
      ["nhl_blues", "nfl_chiefs"],
    ]);
  });

  test("A ends → B (the highest survivor, not C); B ends → C; C ends → base", async () => {
    const { f, g } = scenario();
    await tick(f.db, at(13, 30));
    await tick(f.db, at(13, 35));
    f.dispatched(`${A}_start`);
    g.live("nfl_chiefs"); g.live("nba_thunder"); g.live("nhl_blues");

    // A → B
    g.final("nfl_chiefs");
    await tick(f.db, at(21, 35));
    let r = await tick(f.db, at(21, 40));
    expect(r.handoffsPlanned).toBe(1);
    expect(firstColor(f.job(`${A}_end`))).toEqual(RGB.nba_thunder);
    expect(f.job(`${A}_end`).handoffTo).toBe(B);
    expect(f.session(B).startJobId).toBe(`${A}_end`);
    expect(f.session(C).startPlannedAt).toBeUndefined();
    f.dispatched(`${A}_end`);

    // B → C
    g.final("nba_thunder");
    await tick(f.db, at(22, 5));
    r = await tick(f.db, at(22, 10));
    expect(r.handoffsPlanned).toBe(1);
    expect(firstColor(f.job(`${B}_end`))).toEqual(RGB.nhl_blues);
    expect(f.job(`${B}_end`).handoffTo).toBe(C);
    expect(f.session(C).startJobId).toBe(`${B}_end`);
    f.dispatched(`${B}_end`);

    // C → base
    g.final("nhl_blues");
    await tick(f.db, at(22, 35));
    r = await tick(f.db, at(22, 40));
    expect(r.handoffsPlanned).toBe(0);
    expect(r.endsPlanned).toBe(1);
    expect(payloadOf(f.job(`${C}_end`))).toEqual({ ps: BASE_ON_PRESET });

    // Exactly three end jobs, no start job for B or C — the chain lit them.
    expect(f.job(`${B}_start`)).toBeUndefined();
    expect(f.job(`${C}_start`)).toBeUndefined();
  });

  test("C's game ends BEFORE B's: C never lit, so its end is nothing (no_start); B then restores base "
    + "only once C is out of its window", async () => {
    const { f, g } = scenario();
    await tick(f.db, at(13, 30));
    await tick(f.db, at(13, 35));
    f.dispatched(`${A}_start`);
    g.live("nfl_chiefs"); g.live("nba_thunder"); g.live("nhl_blues");
    g.final("nfl_chiefs");
    await tick(f.db, at(21, 35));
    await tick(f.db, at(21, 40)); // A → B
    f.dispatched(`${A}_end`);

    g.final("nhl_blues");
    let r = await tick(f.db, at(21, 50));
    r = await tick(f.db, at(21, 55));
    expect(f.job(`${C}_end`)).toBeUndefined();
    expect(rows(r, (x) => x.reason === "end_skipped_no_start")[0]).toMatchObject({ teamSlug: "nhl_blues" });

    // B ends at 22:10. C is final but its end has not fired and it is inside
    // its window (until 23:30), so — mirroring the app, where postGame is a
    // hand-off candidate — C briefly takes the house, and then C's own end
    // restores base once it confirms. Two ends, base at the end of both.
    g.final("nba_thunder");
    await tick(f.db, at(22, 5));
    r = await tick(f.db, at(22, 10));
    expect(r.handoffsPlanned).toBe(1);
    expect(firstColor(f.job(`${B}_end`))).toEqual(RGB.nhl_blues);
    f.dispatched(`${B}_end`);
    await tick(f.db, at(22, 15));
    r = await tick(f.db, at(22, 20));
    expect(payloadOf(f.job(`${C}_end`))).toEqual({ ps: BASE_ON_PRESET });
  });
});

// ---------------------------------------------------------------------------
// SINGLE TEAM — no regression
// ---------------------------------------------------------------------------
describe("a single team plans exactly as before", () => {
  const CH = ev("nfl_chiefs", "401");

  test("start at kickoff − 30 min; end is the base restore; log shape unchanged", async () => {
    const f = makeDb(seed({ configs: { nfl_chiefs: {} } }));
    const g = games({ nfl_chiefs: { gameId: "401", startMs: at(18) } });

    let r = await tick(f.db, at(13));
    expect(f.job(`${CH}_start`).fireAt.toMillis()).toBe(at(17, 30));
    expect(r).toMatchObject({ usersScanned: 1, configsEnabled: 1, startsPlanned: 1, endsPlanned: 0, handoffsPlanned: 0, skipped: {}, errors: 0 });
    const planStart = rows(r, (x) => x.action === "plan_start")[0];
    expect(Object.keys(planStart).sort()).toEqual(["action", "bytes", "channels", "eventId", "fireAt", "partitioned", "teamSlug", "uid"]);
    expect(firstColor(f.job(`${CH}_start`))).toEqual(RGB.nfl_chiefs);
    // The freshly planned start still produces this tick's no_start row for
    // the END phase, exactly as before (the session is read before the write).
    expect(r.endSkipped).toEqual({ "end:no_start": 1 });
    expect(rows(r, (x) => x.reason === "end_skipped_no_start")[0].deferredTo).toBeUndefined();

    f.dispatched(`${CH}_start`);
    g.live("nfl_chiefs");
    r = await tick(f.db, at(19));
    expect(r.skipped).toEqual({ start_already_planned: 1 });
    expect(r.endSkipped).toEqual({});

    g.final("nfl_chiefs");
    await tick(f.db, at(21, 35));
    r = await tick(f.db, at(21, 40));
    expect(r.endsPlanned).toBe(1);
    expect(r.handoffsPlanned).toBe(0);
    const end = f.job(`${CH}_end`);
    expect(payloadOf(end)).toEqual({ ps: BASE_ON_PRESET });
    expect(end.handoffTo).toBeUndefined();
    expect(Object.keys(end).sort()).toEqual(["controllerId", "createdAt", "eventId", "fireAt", "payload", "seq", "source", "state", "type"]);
    const planEnd = rows(r, (x) => x.action === "plan_end")[0];
    expect(Object.keys(planEnd).sort()).toEqual(["action", "eventId", "fireAt", "reason", "teamSlug", "uid"]);
    expect(f.session(CH).startJobId).toBeUndefined();
  });

  test("a single team with no priority field at all is unaffected", async () => {
    const f = makeDb(seed({ user: {}, configs: { nfl_chiefs: {} } }));
    games({ nfl_chiefs: { gameId: "401", startMs: at(18) } });
    const r = await tick(f.db, at(13));
    expect(r.startsPlanned).toBe(1);
    expect(r.skipped).toEqual({});
  });
});

// ---------------------------------------------------------------------------
// POSTPONED, AND NO FINAL
// ---------------------------------------------------------------------------
describe("a postponed game, and a game that never reports final", () => {
  const CH = ev("nfl_chiefs", "401");
  const RO = ev("mlb_royals", "402");

  test("a POSTPONED #1 neither blocks the #2 start nor receives the hand-off", async () => {
    const f = makeDb(seed({
      user: { game_day_team_priority: ["nfl_chiefs", "mlb_royals"] },
      configs: { mlb_royals: {}, nfl_chiefs: {} },
    }));
    // ESPN keeps the original date on a postponed game; here it has passed.
    const g = games({
      nfl_chiefs: { gameId: "401", startMs: at(12), statusName: "STATUS_POSTPONED" },
      mlb_royals: { gameId: "402", startMs: at(19) },
    });
    let r = await tick(f.db, at(14));
    expect(f.job(`${RO}_start`)).toBeDefined();        // not deferred
    expect(f.job(`${CH}_start`)).toBeUndefined();      // start_time_passed, as before
    expect(r.skipped).toEqual({ start_time_passed: 1 });
    expect(r.startsPlanned).toBe(1);

    f.dispatched(`${RO}_start`);
    g.live("mlb_royals");
    g.final("mlb_royals");
    await tick(f.db, at(22, 5));
    r = await tick(f.db, at(22, 10));
    expect(r.handoffsPlanned).toBe(0);
    expect(payloadOf(f.job(`${RO}_end`))).toEqual({ ps: BASE_ON_PRESET });
  });

  test("a #1 game that NEVER reports final holds the house for its window; the #2 end is suppressed; "
    + "no end ever fires for #1 (unchanged: the server has no fallback end)", async () => {
    const f = makeDb(seed({
      user: { game_day_team_priority: ["nfl_chiefs", "mlb_royals"] },
      configs: { mlb_royals: {}, nfl_chiefs: {} },
    }));
    const g = games({
      nfl_chiefs: { gameId: "401", startMs: at(18) },   // window 17:30 → 22:30
      mlb_royals: { gameId: "402", startMs: at(17) },   // window 16:30 → 21:00
    });
    await tick(f.db, at(12));
    f.dispatched(`${CH}_start`); f.dispatched(`${RO}_start`);
    g.live("nfl_chiefs"); g.live("mlb_royals");

    g.final("mlb_royals");
    await tick(f.db, at(20, 5));
    let r = await tick(f.db, at(20, 10));
    expect(f.job(`${RO}_end`)).toBeUndefined();
    expect(r.endSkipped).toEqual({ "end:not_owner": 1 });

    // ESPN never says final for the Chiefs. Tick past their window and beyond.
    for (const [h, m] of [[21, 0], [22, 0], [22, 35], [23, 0], [23, 30]]) {
      r = await tick(f.db, at(h, m));
      expect(r.endsPlanned).toBe(0);
    }
    expect(f.job(`${CH}_end`)).toBeUndefined();
    expect(f.job(`${RO}_end`)).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// DEFECT 2 — lead time, through the real planner
// ---------------------------------------------------------------------------
describe("lead time: the user's override moves the start fire", () => {
  const CH = ev("nfl_chiefs", "401");
  const fireAtWith = async (cfg) => {
    const f = makeDb(seed({ configs: { nfl_chiefs: cfg } }));
    games({ nfl_chiefs: { gameId: "401", startMs: at(18) } });
    await tick(f.db, at(13));
    return f.job(`${CH}_start`).fireAt.toMillis();
  };

  test("lead_time_minutes_override: 45 → fires at 17:15", async () => {
    expect(await fireAtWith({ lead_time_minutes_override: 45 })).toBe(at(17, 15));
  });
  test("legacy lead_time_minutes: 20 → 17:40", async () => {
    expect(await fireAtWith({ lead_time_minutes: 20 })).toBe(at(17, 40));
  });
  test("both set → the override wins", async () => {
    expect(await fireAtWith({ lead_time_minutes_override: 45, lead_time_minutes: 20 })).toBe(at(17, 15));
  });
  test("neither → 30 minutes, as before", async () => {
    expect(await fireAtWith({})).toBe(at(17, 30));
  });
  test("a malformed override falls through to the legacy field", async () => {
    expect(await fireAtWith({ lead_time_minutes_override: "45", lead_time_minutes: 20 })).toBe(at(17, 40));
  });
  test("the override also moves the hierarchy window: a long lead can open inside the #1 game", async () => {
    // Royals 90-minute lead: window 17:30, the same instant the Chiefs
    // (kickoff 18:00, 30-minute lead) open. Equal windows → #1 wins.
    const f = makeDb(seed({
      user: { game_day_team_priority: ["nfl_chiefs", "mlb_royals"] },
      configs: { mlb_royals: { lead_time_minutes_override: 90 }, nfl_chiefs: {} },
    }));
    games({ nfl_chiefs: { gameId: "401", startMs: at(18) }, mlb_royals: { gameId: "402", startMs: at(19) } });
    const r = await tick(f.db, at(13));
    expect(f.job(`${ev("nfl_chiefs", "401")}_start`)).toBeDefined();
    expect(f.job(`${ev("mlb_royals", "402")}_start`)).toBeUndefined();
    expect(r.skipped).toEqual({ deferred_to_higher_priority: 1 });
  });
});

// ---------------------------------------------------------------------------
// RANK SOURCES — the account that has not opened Game Day since +106
// ---------------------------------------------------------------------------
describe("rank is derived as the app derives it", () => {
  const CH = ev("nfl_chiefs", "401");
  const RO = ev("mlb_royals", "402");
  const overlap = () => games({
    nfl_chiefs: { gameId: "401", startMs: at(18) },
    mlb_royals: { gameId: "402", startMs: at(19) },
  });

  test("no game_day_team_priority yet: sports_team_priority names decide (Chiefs first)", async () => {
    const f = makeDb(seed({
      user: { sports_team_priority: ["Kansas City Chiefs", "Kansas City Royals"] },
      configs: { mlb_royals: {}, nfl_chiefs: {} },
    }));
    overlap();
    const r = await tick(f.db, at(13));
    expect(f.job(`${CH}_start`)).toBeDefined();
    expect(f.job(`${RO}_start`)).toBeUndefined();
    expect(rows(r, (x) => x.reason === "deferred_to_higher_priority")[0].deferredTo).toBe("nfl_chiefs");
  });

  test("…and sports_teams when the ordered array is empty", async () => {
    const f = makeDb(seed({
      user: { sports_team_priority: [], sports_teams: ["Kansas City Chiefs", "Kansas City Royals"] },
      configs: { mlb_royals: {}, nfl_chiefs: {} },
    }));
    overlap();
    await tick(f.db, at(13));
    expect(f.job(`${RO}_start`)).toBeUndefined();
  });

  test("the slug list, when present, overrides the names", async () => {
    const f = makeDb(seed({
      user: {
        game_day_team_priority: ["mlb_royals", "nfl_chiefs"],
        sports_team_priority: ["Kansas City Chiefs", "Kansas City Royals"],
      },
      configs: { mlb_royals: {}, nfl_chiefs: {} },
    }));
    overlap();
    await tick(f.db, at(13));
    // Royals #1 with the later window: both starts fire (Chiefs alone at
    // 17:30, Royals preempt at 18:30) — and the Chiefs end will be suppressed.
    expect(f.job(`${CH}_start`)).toBeDefined();
    expect(f.job(`${RO}_start`)).toBeDefined();
  });

  test("nothing set at all: document-id order (Royals before Chiefs), as the app's heal would", async () => {
    const f = makeDb(seed({ user: {}, configs: { mlb_royals: {}, nfl_chiefs: {} } }));
    overlap();
    await tick(f.db, at(13));
    expect(f.job(`${CH}_start`)).toBeDefined();
    expect(f.job(`${RO}_start`)).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// HAND-OFF REFUSAL — the survivor cannot be lit by this path
// ---------------------------------------------------------------------------
describe("a survivor whose design the server cannot fire falls back to base, legibly", () => {
  test("per-pixel saved design → handoff_refused row, base restore written", async () => {
    const CH = ev("nfl_chiefs", "401");
    const RO = ev("mlb_royals", "402");
    const f = makeDb(seed({
      user: { game_day_team_priority: ["nfl_chiefs", "mlb_royals"] },
      configs: {
        mlb_royals: { design_mode: "saved", saved_design_payload: { on: true, seg: [{ id: 0, i: [0, 255, 0, 0] }] } },
        nfl_chiefs: {},
      },
    }));
    const g = games({ nfl_chiefs: { gameId: "401", startMs: at(18) }, mlb_royals: { gameId: "402", startMs: at(19) } });
    await tick(f.db, at(13));
    f.dispatched(`${CH}_start`);
    g.live("nfl_chiefs"); g.live("mlb_royals");
    g.final("nfl_chiefs");
    await tick(f.db, at(21, 35));
    const r = await tick(f.db, at(21, 40));
    expect(r.handoffsPlanned).toBe(0);
    expect(r.endsPlanned).toBe(1);
    expect(payloadOf(f.job(`${CH}_end`))).toEqual({ ps: BASE_ON_PRESET });
    expect(rows(r, (x) => x.reason === "handoff_refused:saved_payload_per_pixel")[0]).toMatchObject({ teamSlug: "nfl_chiefs", handoffTo: "mlb_royals" });
    expect(f.session(RO)?.startPlannedAt).toBeUndefined();
  });
});

// Sanity: the fake honours create()-once, as the real SDK does.
test("fake Firestore: create() collides on an existing path with code 6", async () => {
  const f = makeDb({});
  const ref = f.db.collection("x").doc("y");
  await ref.create({ a: 1 });
  await expect(ref.create({ a: 2 })).rejects.toMatchObject({ code: 6 });
  expect(admin.firestore.FieldValue.serverTimestamp()).toBeDefined();
});
