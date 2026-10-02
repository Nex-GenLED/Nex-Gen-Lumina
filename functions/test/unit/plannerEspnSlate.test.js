// planGameDayFires × the ESPN slate fix — the REAL planner tick and the REAL
// espnClient, with `fetch` stubbed by URL and Firestore in memory. Nothing in
// this file mocks a module.
//
// The scenario (support/plannerScenario.js): four accounts, three sports, five
// ticks across one Saturday evening. Its golden was captured from the base
// branch BEFORE any ESPN change; with every flag off the planner must write
// exactly what that golden says, document for document.

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { installFetchStub, espnEvent, scoreboard, BASE } = require("./support/espnFixtures");
const S = require("./support/plannerScenario");
const golden = require("./fixtures/plannerFlagsOffGolden.json");
const { runPlannerTick } = require("../../lib/planGameDayFires");

const H = 3600_000;
const ARMED = { enabled: true, allowlist: S.ALLOWLIST };
const ALL_ON = { espnCollegeSlate: true, trackStartedById: true, statusAwareCap: true };
const CFB = `${BASE}/football/college-football`;
const job = (uid, ev, seq) => `users/${uid}/fire_jobs/${ev}_${seq}`;
const EVENTS = {
  alphaNfl: `gd_nfl_alpha_${S.EV.nfl}`,
  alphaFalcon: `gd_ncaa_falcon_${S.EV.falcon}`,
  charlieGator: `gd_ncaa_gator_${S.EV.gator}`,
  deltaMlb: `gd_mlb_mariner_${S.EV.mlb}`,
};

/** Run the scenario's ticks with the given flags; `override(tick, url)` may replace a route. */
async function runScenario({ flags = {}, ticks = S.TICKS, override } = {}) {
  const f = makeFakeFirestore({ now: S.T.T1 });
  S.seedWorld(f);
  const out = {};
  let prev = S.snapshot(f);
  for (const tick of ticks) {
    const ms = S.T[tick];
    f.setNow(ms);
    S.heartbeat(f);
    const base = S.espnRoute(tick);
    const stub = installFetchStub((u) => (override ? override(tick, u) : undefined) ?? base(u));
    const readsBefore = f.reads.length;
    let r;
    try {
      r = await runPlannerTick(f.db, ms, { forcePolicy: ARMED, forceFlags: flags });
    } finally {
      stub.restore();
    }
    const now = S.snapshot(f);
    out[tick] = { r, calls: stub.calls, reads: f.reads.slice(readsBefore), ...S.delta(prev, now) };
    if (tick === "T1") S.completeStarts(f);
    prev = S.snapshot(f);
  }
  return { f, out };
}

const rowsOf = (r, pred) => r.logRows.filter(pred);
const unique = (xs) => [...new Set(xs)];

// ---------------------------------------------------------------------------
describe("flags OFF = the planner as it was, document for document", () => {
  let run;
  beforeAll(async () => {
    run = await runScenario();
  });

  test("the golden came from the base branch, before the change", () => {
    expect(golden.generatedFrom).toBe("d2e0f6e");
    expect(Object.keys(golden.ticks)).toEqual(S.TICKS);
  });

  test.each(S.TICKS)("%s: every document written, changed or removed is identical", (tick) => {
    expect(run.out[tick].changed).toEqual(golden.ticks[tick].changed);
    expect(run.out[tick].removed).toEqual(golden.ticks[tick].removed);
  });

  test.each(S.TICKS)("%s: the same stats and log rows; the summary adds only espnFetches", (tick) => {
    const { logRows, espnFetches, ...stats } = run.out[tick].r;
    expect(stats).toEqual(golden.ticks[tick].stats);
    expect(logRows).toEqual(golden.ticks[tick].logRows);
    expect(espnFetches).toBe(run.out[tick].calls.length);
  });

  test.each(S.TICKS)("%s: the same URLs, each requested ONCE (the old planner repeated the college one)", (tick) => {
    const before = golden.ticks[tick].fetches;
    expect(run.out[tick].calls).toEqual(unique(before));
    expect(before.length).toBe(4); // nfl, ncaaFB ×2 (two college teams), mlb
    expect(run.out[tick].calls.length).toBe(3);
  });

  test("no session query, no dated slate, no single-game or team request with the flags off", () => {
    for (const tick of S.TICKS) {
      expect(run.out[tick].reads.some((r) => /^query:users\/[^/]+\/game_day_sessions$/.test(r))).toBe(false);
      expect(run.out[tick].calls.every((u) => /\/scoreboard$/.test(u))).toBe(true);
    }
  });

  test("the defect, as it stands with the flags off: the unfeatured college game is never planned, and the game that left the scoreboard never ends", () => {
    for (const tick of S.TICKS) {
      expect(rowsOf(run.out[tick].r, (x) => x.uid === "u_charlie")).toEqual([
        { uid: "u_charlie", teamSlug: "ncaa_gator", action: "skip", reason: "no_game" },
      ]);
    }
    expect(run.f.get(job("u_delta", EVENTS.deltaMlb, "start"))).toBeDefined();
    expect(run.f.get(job("u_delta", EVENTS.deltaMlb, "end"))).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
describe("espn_college_slate — a Friday FBS game off the default list", () => {
  const FRI_KICK = "2026-10-09T23:00:00Z"; // Fri 6:00 PM CDT
  const TICK = Date.parse("2026-10-09T17:30:00Z"); // fireAt 22:30Z is inside the 6 h horizon
  const EVENT = "gd_ncaa_friday_9300400";

  function fridayWorld() {
    const f = makeFakeFirestore({ now: TICK });
    S.seedAccount(f, "u_charlie", 3, {
      configs: { ncaa_friday: S.teamConfig("ncaa_friday", "Friday College", "ncaaFB", "807") },
      priority: ["ncaa_friday"],
      bridge: true,
    });
    f.put("users/u_charlie/controllers/ctrl_u_charlie", {
      ...f.get("users/u_charlie/controllers/ctrl_u_charlie"),
      participating_channels_at: f.ts(TICK - 3 * H),
    });
    return f;
  }
  const route = (u) => {
    // The featured list: Saturday games only, as found 2026-10-02.
    if (u === `${CFB}/scoreboard`) {
      return { body: scoreboard([espnEvent({ id: "9300401", startIso: "2026-10-10T16:00:00Z", home: "811", away: "812" })]) };
    }
    if (u === `${CFB}/scoreboard?dates=20261009&groups=80&limit=300`) {
      return { body: scoreboard([espnEvent({ id: "9300400", startIso: FRI_KICK, home: "807", away: "808" })]) };
    }
    if (u.startsWith(`${CFB}/scoreboard?dates=`)) return { body: scoreboard([]) };
    return undefined;
  };
  async function tick(flags) {
    const f = fridayWorld();
    const stub = installFetchStub(route);
    let r;
    try {
      r = await runPlannerTick(f.db, TICK, { forcePolicy: ARMED, forceFlags: flags });
    } finally {
      stub.restore();
    }
    return { f, r, calls: stub.calls };
  }

  test("flag ON: the start is minted — fireAt kickoff − 30 min, the team's look", async () => {
    const { f, r, calls } = await tick({ espnCollegeSlate: true });
    expect(r.startsPlanned).toBe(1);
    expect(r.errors).toBe(0);
    const start = f.get(`users/u_charlie/fire_jobs/${EVENT}_start`);
    expect(start.fireAt.toMillis()).toBe(Date.parse(FRI_KICK) - 30 * 60_000);
    expect(JSON.parse(start.payload)).toMatchObject({ on: true, bri: 200, seg: [{ id: 0, fx: 52 }, { id: 1, fx: 52 }] });
    expect(calls).toEqual([
      `${CFB}/scoreboard?dates=20261008&groups=80&limit=300`,
      `${CFB}/scoreboard?dates=20261009&groups=80&limit=300`,
      `${CFB}/scoreboard?dates=20261010&groups=80&limit=300`,
    ]);
  });

  test("flag OFF: no_game, no job — the defect", async () => {
    const { f, r, calls } = await tick({});
    expect(r.startsPlanned).toBe(0);
    expect(r.skipped).toEqual({ no_game: 1 });
    expect(f.get(`users/u_charlie/fire_jobs/${EVENT}_start`)).toBeUndefined();
    expect(calls).toEqual([`${CFB}/scoreboard`]);
  });

  test("the scenario: with the flag on, the unfeatured Saturday game mints too; the featured one is unchanged", async () => {
    const { f, out } = await runScenario({ flags: { espnCollegeSlate: true }, ticks: ["T1"] });
    expect(f.get(job("u_charlie", EVENTS.charlieGator, "start"))).toBeDefined();
    expect(f.get(job("u_alpha", EVENTS.alphaFalcon, "start")).payload).toBe(
      golden.ticks.T1.changed[`users/u_alpha/fire_jobs/${EVENTS.alphaFalcon}_start`].payload
    );
    expect(out.T1.r.startsPlanned).toBe(golden.ticks.T1.stats.startsPlanned + 1);
  });
});

// ---------------------------------------------------------------------------
describe("team_not_on_slate — an id that can never be on the FBS slate is named", () => {
  const TICK = S.T.T1;
  function world() {
    const f = makeFakeFirestore({ now: TICK });
    const accounts = [
      ["u_fcs", 5, "ncaa_fcsteam", "851"], // FCS: ESPN's team doc says group 81
      ["u_badid", 6, "ncaa_badid", "999999"], // unknown to ESPN (HTTP 400)
      ["u_bye", 7, "ncaa_byeteam", "809"], // FBS, no game in the window
    ];
    for (const [uid, n, slug, id] of accounts) {
      S.seedAccount(f, uid, n, { configs: { [slug]: S.teamConfig(slug, `Team ${n}`, "ncaaFB", id) }, priority: [slug], bridge: true });
    }
    return f;
  }
  async function tick(flags, override) {
    const f = world();
    const base = S.espnRoute("T1");
    const stub = installFetchStub((u) => (override ? override(u) : undefined) ?? base(u));
    let r;
    try {
      r = await runPlannerTick(f.db, TICK, { forcePolicy: { enabled: true, allowlist: ["u_fcs", "u_badid", "u_bye"] }, forceFlags: flags });
    } finally {
      stub.restore();
    }
    return { r, calls: stub.calls };
  }

  test("FCS and unknown ids → team_not_on_slate (own bucket, named row); an FBS bye → no_game", async () => {
    const { r, calls } = await tick({ espnCollegeSlate: true });
    expect(r.skipped).toEqual({ team_not_on_slate: 2, no_game: 1 });
    expect(rowsOf(r, (x) => x.reason === "team_not_on_slate")).toEqual([
      { uid: "u_badid", teamSlug: "ncaa_badid", action: "skip", reason: "team_not_on_slate", sport: "ncaaFB", espnTeamId: "999999", slate: "fbs", detail: "unknown_team" },
      { uid: "u_fcs", teamSlug: "ncaa_fcsteam", action: "skip", reason: "team_not_on_slate", sport: "ncaaFB", espnTeamId: "851", slate: "fbs", detail: "not_fbs:81" },
    ]);
    expect(rowsOf(r, (x) => x.uid === "u_bye")).toEqual([{ uid: "u_bye", teamSlug: "ncaa_byeteam", action: "skip", reason: "no_game" }]);
    // Three slate reads, one team document per id — and never the FCS slate.
    expect(calls.filter((u) => u.includes("/scoreboard?dates="))).toHaveLength(3);
    expect(calls.filter((u) => u.includes("/teams/")).sort()).toEqual([`${CFB}/teams/809`, `${CFB}/teams/851`, `${CFB}/teams/999999`]);
    expect(calls.some((u) => u.includes("groups=81"))).toBe(false);
    expect(unique(calls)).toEqual(calls);
  });

  test("an incomplete slate (one date failed) claims nothing: no_game, no team lookup", async () => {
    const { r, calls } = await tick({ espnCollegeSlate: true }, (u) =>
      u.includes("dates=20261011") ? { status: 500, body: {} } : undefined
    );
    expect(r.skipped).toEqual({ no_game: 3 });
    expect(calls.some((u) => u.includes("/teams/"))).toBe(false);
  });

  test("flag OFF: all three read as no_game, as before", async () => {
    const { r } = await tick({});
    expect(r.skipped).toEqual({ no_game: 3 });
  });
});

// ---------------------------------------------------------------------------
describe("track_started_by_id — a started game that leaves the scoreboard still ends", () => {
  test("ESPN still answers by id (a rain delay): the shipped cap ends it at its bound", async () => {
    const { f, out } = await runScenario({ flags: { trackStartedById: true }, ticks: ["T1", "T2", "T3"] });
    const end = f.get(job("u_delta", EVENTS.deltaMlb, "end"));
    expect(end).toBeDefined();
    expect(end.payload).toBe('{"ps":1}'); // after sunset: base ON
    expect(end.fireAt.toMillis()).toBe(S.T.T3);
    expect(rowsOf(out.T3.r, (x) => x.uid === "u_delta" && x.action === "plan_end")).toEqual([
      expect.objectContaining({ reason: "hard_cap", espnVia: "tracked" }),
    ]);
    expect(out.T3.calls).toContain(`${BASE}/baseball/mlb/scoreboard/${S.EV.mlb}`);
    // The log-only account with the same team has no started session: it is
    // NOT tracked, reads the scoreboard, and never ends anything.
    expect(rowsOf(out.T3.r, (x) => x.uid === "u_bravo" && x.teamSlug === "mlb_mariner")).toEqual([
      { uid: "u_bravo", teamSlug: "mlb_mariner", action: "skip", reason: "no_game" },
    ]);
  });

  test("ESPN 404 by id (the game is gone — silent): the cap still fires, and says why", async () => {
    const gone = (tick, u) =>
      tick !== "T1" && tick !== "T2" && u === `${BASE}/baseball/mlb/scoreboard/${S.EV.mlb}` ? { status: 404, body: { code: 404 } } : undefined;
    const { f, out } = await runScenario({ flags: { trackStartedById: true, statusAwareCap: true }, ticks: ["T1", "T2", "T3"], override: gone });
    expect(f.get(job("u_delta", EVENTS.deltaMlb, "end"))).toBeDefined();
    expect(rowsOf(out.T3.r, (x) => x.uid === "u_delta" && x.action === "plan_end")).toEqual([
      expect.objectContaining({ reason: "hard_cap", espnVia: "tracked", capStatus: "silent" }),
    ]);
  });

  test("a by-id ERROR falls back to the scoreboard (tracking only ever adds information)", async () => {
    const broken = (tick, u) => (/\/scoreboard\/\d+$/.test(u) ? { status: 503, body: {} } : undefined);
    const { out } = await runScenario({ flags: { trackStartedById: true }, override: broken });
    const notPlanLog = (changed) =>
      Object.fromEntries(Object.entries(changed).filter(([p]) => !p.startsWith("gameday_plan_log/")));
    for (const tick of S.TICKS) {
      // Every job, session, scorecard and user document is the golden's; the
      // plan log differs only in the espnErrors it now (rightly) counts.
      expect(notPlanLog(out[tick].changed)).toEqual(notPlanLog(golden.ticks[tick].changed));
      const { logRows, espnFetches, espnErrors, ...stats } = out[tick].r;
      const { espnErrors: goldenErrors, ...goldenStats } = golden.ticks[tick].stats;
      expect(stats).toEqual(goldenStats);
      expect(logRows).toEqual(golden.ticks[tick].logRows);
      void espnFetches;
      void goldenErrors;
      expect(espnErrors).toBe(tick === "T1" ? 0 : out[tick].calls.filter((u) => /\/scoreboard\/\d+$/.test(u)).length);
    }
  });

  test("a tracked game is followed by id while it lasts; the sessions query runs once per account", async () => {
    const { out } = await runScenario({ flags: { trackStartedById: true }, ticks: ["T1", "T2"] });
    expect(out.T2.calls).toEqual(
      expect.arrayContaining([
        `${BASE}/football/nfl/scoreboard/${S.EV.nfl}`,
        `${CFB}/scoreboard/${S.EV.falcon}`,
        `${BASE}/baseball/mlb/scoreboard/${S.EV.mlb}`,
      ])
    );
    const sessionQueries = out.T2.reads.filter((r) => /^query:users\/[^/]+\/game_day_sessions$/.test(r));
    // One per account with an enabled config and a controller.
    expect(sessionQueries.sort()).toEqual(["u_alpha", "u_bravo", "u_charlie", "u_delta"].map((u) => `query:users/${u}/game_day_sessions`));
  });
});

// ---------------------------------------------------------------------------
describe("status_aware_cap — held through a delay, the ceiling still fires", () => {
  let run;
  beforeAll(async () => {
    run = await runScenario({ flags: { trackStartedById: true, statusAwareCap: true }, ticks: [...S.TICKS, "T6"] });
  });

  test("T5: the NFL game is past its bound but ESPN says in progress → HELD, no end job, a named row", () => {
    expect(run.out.T5.r.endSkipped["end:cap_held_live"]).toBe(2); // NFL and the MLB rain delay
    expect(rowsOf(run.out.T5.r, (x) => x.uid === "u_alpha" && x.reason === "cap_held_live")).toEqual([
      { uid: "u_alpha", teamSlug: "nfl_alpha", eventId: EVENTS.alphaNfl, action: "skip", reason: "cap_held_live", espnStatus: "STATUS_IN_PROGRESS", ceilingAt: "2026-10-11T06:15:00.000Z" },
    ]);
    // The flags-off golden ended it here.
    expect(golden.ticks.T5.changed[`users/u_alpha/fire_jobs/${EVENTS.alphaNfl}_end`]).toBeDefined();
    expect(run.out.T5.changed[`users/u_alpha/fire_jobs/${EVENTS.alphaNfl}_end`]).toBeUndefined();
  });

  test("T3–T5: the rain-delayed MLB game (gone from the board, live by id) is held too", () => {
    for (const t of ["T3", "T4", "T5"]) {
      expect(rowsOf(run.out[t].r, (x) => x.uid === "u_delta" && x.reason === "cap_held_live")).toEqual([
        expect.objectContaining({ espnStatus: "STATUS_RAIN_DELAY", ceilingAt: "2026-10-11T06:05:00.000Z" }),
      ]);
    }
  });

  test("T6: past both ceilings → hard_cap_ceiling ends both, base ON restored", () => {
    const ends = rowsOf(run.out.T6.r, (x) => x.action === "plan_end");
    expect(ends.map((x) => [x.uid, x.reason, x.capStatus])).toEqual([
      ["u_alpha", "hard_cap_ceiling", "STATUS_IN_PROGRESS"],
      ["u_delta", "hard_cap_ceiling", "STATUS_RAIN_DELAY"],
    ]);
    expect(run.out.T6.r.hardCapsPlanned).toBe(2);
    expect(run.f.get(job("u_alpha", EVENTS.alphaNfl, "end")).payload).toBe('{"ps":1}');
    expect(run.f.get(job("u_delta", EVENTS.deltaMlb, "end")).payload).toBe('{"ps":1}');
  });

  test("the hierarchy agrees: the falcon final at T4 still yields to the held NFL game (not_owner, no restore under it)", () => {
    expect(rowsOf(run.out.T4.r, (x) => x.uid === "u_alpha" && x.teamSlug === "ncaa_falcon" && x.action === "skip" && x.reason === "end_suppressed_not_owner")).toHaveLength(1);
    expect(run.f.get(job("u_alpha", EVENTS.alphaFalcon, "end"))).toBeUndefined();
  });

  test("status_aware_cap alone (no tracking) holds the NFL game the same way", async () => {
    const { out } = await runScenario({ flags: { statusAwareCap: true }, ticks: [...S.TICKS, "T6"] });
    expect(out.T5.changed[`users/u_alpha/fire_jobs/${EVENTS.alphaNfl}_end`]).toBeUndefined();
    expect(rowsOf(out.T6.r, (x) => x.uid === "u_alpha" && x.action === "plan_end")).toEqual([
      expect.objectContaining({ reason: "hard_cap_ceiling" }),
    ]);
  });
});

// ---------------------------------------------------------------------------
describe("one fetch per URL per tick, every flag on", () => {
  test("no URL is requested twice in a tick; espnFetches counts them", async () => {
    const { out } = await runScenario({ flags: ALL_ON, ticks: [...S.TICKS, "T6"] });
    for (const t of [...S.TICKS, "T6"]) {
      expect(unique(out[t].calls)).toEqual(out[t].calls);
      expect(out[t].r.espnFetches).toBe(out[t].calls.length);
      expect(out[t].r.errors).toBe(0);
    }
  });
});
