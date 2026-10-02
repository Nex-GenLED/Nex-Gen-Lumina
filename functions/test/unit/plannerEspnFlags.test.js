// planGameDayFires — the flags as production reads them (config/gameday_planner,
// not forced), the tracked-session selection, and #146's P4b inside a real
// tick. Real espnClient, `fetch` stubbed by URL, Firestore in memory.

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { installFetchStub, espnEvent, scoreboard, BASE } = require("./support/espnFixtures");
const S = require("./support/plannerScenario");
const { runPlannerTick, espnFlagsFrom, openSessionsByTeam, TRACK_LOOKBACK_MS } = require("../../lib/planGameDayFires");

const H = 3600_000;
const CFB = `${BASE}/football/college-football`;

// ---------------------------------------------------------------------------
describe("espnFlagsFrom — each flag on only when exactly true", () => {
  test("absent = all off (a deploy changes nothing)", () => {
    const off = { espnCollegeSlate: false, trackStartedById: false, statusAwareCap: false };
    expect(espnFlagsFrom(undefined)).toEqual(off);
    expect(espnFlagsFrom({})).toEqual(off);
    expect(espnFlagsFrom({ write_jobs: true })).toEqual(off);
  });

  test("each field independently; strings, numbers and null do not arm", () => {
    expect(espnFlagsFrom({ espn_college_slate: true })).toEqual({ espnCollegeSlate: true, trackStartedById: false, statusAwareCap: false });
    expect(espnFlagsFrom({ track_started_by_id: true })).toEqual({ espnCollegeSlate: false, trackStartedById: true, statusAwareCap: false });
    expect(espnFlagsFrom({ status_aware_cap: true })).toEqual({ espnCollegeSlate: false, trackStartedById: false, statusAwareCap: true });
    for (const v of ["true", 1, null, "yes", {}]) {
      expect(espnFlagsFrom({ espn_college_slate: v, track_started_by_id: v, status_aware_cap: v })).toEqual({
        espnCollegeSlate: false, trackStartedById: false, statusAwareCap: false,
      });
    }
  });
});

// ---------------------------------------------------------------------------
describe("openSessionsByTeam — which session a team follows", () => {
  const started = { startPlannedAt: { seconds: 1 } };
  const T = Date.parse("2026-10-11T00:00:00Z");

  test("started and not ended, for an enabled slug; the earlier of two (doubleheader)", () => {
    const m = openSessionsByTeam(
      [
        { id: "gd_mlb_m_202", data: { ...started, gameStartMs: T + 4 * H } },
        { id: "gd_mlb_m_201", data: { ...started, gameStartMs: T } },
        { id: "gd_nfl_a_301", data: { ...started, gameStartMs: T, endFiredAt: { seconds: 2 } } }, // ended
        { id: "gd_nfl_b_302", data: { gameStartMs: T } }, // never started (log-only)
        { id: "gd_nfl_c_303", data: { ...started } }, // no kickoff known
        { id: "gd_nhl_x_304", data: { ...started, gameStartMs: T } }, // slug not enabled
      ],
      ["mlb_m", "nfl_a", "nfl_b", "nfl_c"]
    );
    expect([...m.entries()]).toEqual([["mlb_m", { eventId: "gd_mlb_m_201", gameId: "201", gameStartMs: T }]]);
  });

  test("a slug that is a prefix of another is not confused with it", () => {
    const m = openSessionsByTeam(
      [{ id: "gd_nfl_a_b_401", data: { ...started, gameStartMs: T } }],
      ["nfl_a", "nfl_a_b"]
    );
    expect([...m.entries()]).toEqual([["nfl_a_b", { eventId: "gd_nfl_a_b_401", gameId: "401", gameStartMs: T }]]);
  });

  test("the lookback outlives every sport's ceiling", () => {
    const { CAP_CEILING_MS } = require("../../lib/gameDayPlanning");
    expect(TRACK_LOOKBACK_MS).toBeGreaterThan(Math.max(...Object.values(CAP_CEILING_MS)));
  });
});

// ---------------------------------------------------------------------------
describe("the production read: flags come from config/gameday_planner", () => {
  const TICK = Date.parse("2026-10-09T17:30:00Z");
  const route = (u) => {
    if (u === `${CFB}/scoreboard`) return { body: scoreboard([]) };
    if (u === `${CFB}/scoreboard?dates=20261009&groups=80&limit=300`) {
      return { body: scoreboard([espnEvent({ id: "9300400", startIso: "2026-10-09T23:00:00Z", home: "807", away: "808" })]) };
    }
    if (u.startsWith(`${CFB}/scoreboard?dates=`)) return { body: scoreboard([]) };
    return undefined;
  };
  async function tickWithConfig(config) {
    const f = makeFakeFirestore({ now: TICK });
    S.seedAccount(f, "u_charlie", 3, {
      configs: { ncaa_friday: S.teamConfig("ncaa_friday", "Friday College", "ncaaFB", "807") },
      priority: ["ncaa_friday"],
      bridge: true,
    });
    f.patch("users/u_charlie/controllers/ctrl_u_charlie", { participating_channels_at: f.ts(TICK - 3 * H) });
    if (config) f.put("config/gameday_planner", config);
    const stub = installFetchStub(route);
    try {
      return { f, r: await runPlannerTick(f.db, TICK) };
    } finally {
      stub.restore();
    }
  }
  const ARM = { write_jobs: true, uid_allowlist: ["u_charlie"] };

  test("espn_college_slate: true → the Friday game is planned", async () => {
    const { f, r } = await tickWithConfig({ ...ARM, espn_college_slate: true });
    expect(r.startsPlanned).toBe(1);
    expect(f.get("users/u_charlie/fire_jobs/gd_ncaa_friday_9300400_start")).toBeDefined();
  });

  test("absent, or the string \"true\" → off: no_game", async () => {
    for (const cfg of [ARM, { ...ARM, espn_college_slate: "true" }]) {
      const { f, r } = await tickWithConfig(cfg);
      expect(r.skipped).toEqual({ no_game: 1 });
      expect(f.get("users/u_charlie/fire_jobs/gd_ncaa_friday_9300400_start")).toBeUndefined();
    }
  });
});

// ---------------------------------------------------------------------------
describe("#146 in a real tick — a ladder measured dark", () => {
  async function tick(config, controllerOver) {
    const f = makeFakeFirestore({ now: S.T.T1 });
    S.seedAccount(f, "u_delta", 4, {
      configs: { mlb_mariner: S.teamConfig("mlb_mariner", "Mariner Club", "mlb", "701") },
      priority: ["mlb_mariner"],
      bridge: true,
    });
    f.patch("users/u_delta/controllers/ctrl_u_delta", controllerOver);
    f.put("config/gameday_planner", { write_jobs: true, uid_allowlist: ["u_delta"], ...config });
    const stub = installFetchStub(S.espnRoute("T1"));
    try {
      const r = await runPlannerTick(f.db, S.T.T1);
      return { f, r, user: f.get("users/u_delta") };
    } finally {
      stub.restore();
    }
  }
  const DARK = { base_ladder_restore_lit: false, base_ladder_dark_channels: [1] };
  const START = `users/u_delta/fire_jobs/gd_mlb_mariner_${S.EV.mlb}_start`;

  test("preflight_ladder_lit: true → the start is withheld, the skip names the reason, a row names the dark buses", async () => {
    const { f, r, user } = await tick({ preflight_ladder_lit: true }, DARK);
    expect(f.get(START)).toBeUndefined();
    expect(r.preflightSkips).toBe(1);
    expect(r.logRows).toEqual(
      expect.arrayContaining([
        { uid: "u_delta", action: "preflight_skip", reasons: ["preflight_ladder_dark"] },
        { uid: "u_delta", action: "preflight_ladder_dark", controllerId: "ctrl_u_delta", base_ladder_dark_channels: [1] },
      ])
    );
    expect(user.gameday_server).toMatchObject({ served: false, preflight: { ok: false, reasons: ["preflight_ladder_dark"] } });
  });

  test("observe mode: logged (observeOnly), nothing withheld", async () => {
    const { f, r } = await tick({ preflight_ladder_lit: true, preflight_mode: "observe" }, DARK);
    expect(f.get(START)).toBeDefined();
    expect(r.preflightObserved).toBe(1);
    expect(r.logRows).toEqual(
      expect.arrayContaining([
        { uid: "u_delta", action: "preflight_ladder_dark", controllerId: "ctrl_u_delta", base_ladder_dark_channels: [1], observeOnly: true },
      ])
    );
  });

  test("flag absent → A+B behaviour: the dark ladder is not looked at, the start mints", async () => {
    const { f, r } = await tick({}, DARK);
    expect(f.get(START)).toBeDefined();
    expect(r.logRows.some((x) => x.action === "preflight_ladder_dark")).toBe(false);
  });

  test("flag on, field not yet published → informational only; the start mints", async () => {
    const { f, user } = await tick({ preflight_ladder_lit: true }, {});
    expect(f.get(START)).toBeDefined();
    expect(user.gameday_server.preflight.info).toContain("ladder_lit_unknown");
  });

  test("\"strict\", field not yet published → withheld as preflight_ladder_unknown", async () => {
    const { f, user } = await tick({ preflight_ladder_lit: "strict" }, {});
    expect(f.get(START)).toBeUndefined();
    expect(user.gameday_server.preflight.reasons).toEqual(["preflight_ladder_unknown"]);
  });
});
