// planGameDayFires — the flags as production reads them (config/gameday_planner,
// not forced), the tracked-session selection, and #146's P4b inside a real
// tick. Real espnClient, `fetch` stubbed by URL, Firestore in memory.

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { installFetchStub, espnEvent, scoreboard, BASE } = require("./support/espnFixtures");
const S = require("./support/plannerScenario");
const { runPlannerTick, espnFlagsFrom, espnFlagsFor, openSessionsByTeam, TRACK_LOOKBACK_MS } = require("../../lib/planGameDayFires");
const { flagScopeFrom, flagOnFor } = require("../../lib/gameDayPlanning");
const { ladderLitModeFrom } = require("../../lib/gameDayPreflight");

const H = 3600_000;
const CFB = `${BASE}/football/college-football`;
const OFF = { espnCollegeSlate: false, trackStartedById: false, statusAwareCap: false };

// ---------------------------------------------------------------------------
describe("#157 — a flag is exactly true (fleet-wide) or a uid list (only those accounts)", () => {
  test("true → every account", () => {
    expect(flagScopeFrom(true)).toEqual({ all: true });
    expect(flagOnFor(flagScopeFrom(true), "u_any")).toBe(true);
  });

  test("a list containing the uid → on; a list without it → off; an empty list → nobody", () => {
    const scope = flagScopeFrom(["u_bench", "u_other"]);
    expect(flagOnFor(scope, "u_bench")).toBe(true);
    expect(flagOnFor(scope, "u_friendly")).toBe(false);
    expect(flagOnFor(flagScopeFrom([]), "u_bench")).toBe(false);
  });

  test("wrong types are OFF — never armed, never widened", () => {
    for (const v of [undefined, null, false, "true", "u_bench", 1, 0, {}, { u_bench: true }, [1], ["u_bench", 2], [""], ["u_bench", null], [["u_bench"]]]) {
      expect(flagScopeFrom(v)).toBeNull();
      expect(flagOnFor(flagScopeFrom(v), "u_bench")).toBe(false);
    }
  });

  test("espnFlagsFrom / espnFlagsFor: absent = all off; each field independently, per account", () => {
    for (const data of [undefined, {}, { write_jobs: true }]) {
      expect(espnFlagsFor(espnFlagsFrom(data), "u_bench")).toEqual(OFF);
    }
    const flags = espnFlagsFrom({ espn_college_slate: ["u_bench"], track_started_by_id: true, status_aware_cap: "true" });
    expect(espnFlagsFor(flags, "u_bench")).toEqual({ espnCollegeSlate: true, trackStartedById: true, statusAwareCap: false });
    expect(espnFlagsFor(flags, "u_friendly")).toEqual({ espnCollegeSlate: false, trackStartedById: true, statusAwareCap: false });
  });

  test("preflight_ladder_lit: true, \"strict\" (fleet-wide), or a uid list for \"on\"", () => {
    expect(ladderLitModeFrom({ preflight_ladder_lit: true }, "u_x")).toBe("on");
    expect(ladderLitModeFrom({ preflight_ladder_lit: "strict" }, "u_x")).toBe("strict");
    expect(ladderLitModeFrom({ preflight_ladder_lit: ["u_bench"] }, "u_bench")).toBe("on");
    expect(ladderLitModeFrom({ preflight_ladder_lit: ["u_bench"] }, "u_friendly")).toBe("off");
    expect(ladderLitModeFrom({ preflight_ladder_lit: [] }, "u_bench")).toBe("off");
    expect(ladderLitModeFrom({ preflight_ladder_lit: ["u_bench"] })).toBe("off"); // no uid → off
    for (const v of ["on", 1, ["u_bench", 3], { strict: true }]) {
      expect(ladderLitModeFrom({ preflight_ladder_lit: v }, "u_bench")).toBe("off");
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
describe("#157 in a real tick — a bench-only flip after a second account is allowlisted", () => {
  const TICK = Date.parse("2026-10-09T17:30:00Z");
  const route = (u) => {
    if (u === `${CFB}/scoreboard`) return { body: scoreboard([]) };
    if (u === `${CFB}/scoreboard?dates=20261009&groups=80&limit=300`) {
      return { body: scoreboard([espnEvent({ id: "9300400", startIso: "2026-10-09T23:00:00Z", home: "807", away: "808" })]) };
    }
    if (u.startsWith(`${CFB}/scoreboard?dates=`)) return { body: scoreboard([]) };
    return undefined;
  };
  async function tick(config) {
    const f = makeFakeFirestore({ now: TICK });
    for (const [uid, n] of [["u_bench", 3], ["u_friendly", 8]]) {
      S.seedAccount(f, uid, n, {
        configs: { ncaa_friday: S.teamConfig("ncaa_friday", "Friday College", "ncaaFB", "807") },
        priority: ["ncaa_friday"],
        bridge: true,
      });
      f.patch(`users/${uid}/controllers/ctrl_${uid}`, { participating_channels_at: f.ts(TICK - 3 * H) });
    }
    f.put("config/gameday_planner", { write_jobs: true, uid_allowlist: ["u_bench", "u_friendly"], ...config });
    const stub = installFetchStub(route);
    try {
      const r = await runPlannerTick(f.db, TICK);
      return { f, r, calls: stub.calls };
    } finally {
      stub.restore();
    }
  }
  const JOB = (uid) => `users/${uid}/fire_jobs/gd_ncaa_friday_9300400_start`;

  test("espn_college_slate: [bench] — the bench mints; the other allowlisted account keeps the old path", async () => {
    const { f, r } = await tick({ espn_college_slate: ["u_bench"] });
    expect(f.get(JOB("u_bench"))).toBeDefined();
    expect(f.get(JOB("u_friendly"))).toBeUndefined();
    expect(r.logRows).toEqual(expect.arrayContaining([
      { uid: "u_friendly", teamSlug: "ncaa_friday", action: "skip", reason: "no_game" },
    ]));
  });

  test("true — both mint; [] — neither; a malformed list — neither", async () => {
    const both = await tick({ espn_college_slate: true });
    expect([both.f.get(JOB("u_bench")), both.f.get(JOB("u_friendly"))].every(Boolean)).toBe(true);
    for (const v of [[], ["u_bench", 7], "u_bench"]) {
      const none = await tick({ espn_college_slate: v });
      expect(none.f.get(JOB("u_bench"))).toBeUndefined();
      expect(none.f.get(JOB("u_friendly"))).toBeUndefined();
    }
  });

  test("track_started_by_id: [bench] — only the bench's sessions are queried and followed by id", async () => {
    const { f } = await tick({ espn_college_slate: true });
    for (const uid of ["u_bench", "u_friendly"]) f.patch(JOB(uid), { state: "completed" });
    const live = Date.parse("2026-10-10T00:30:00Z");
    f.setNow(live);
    for (const uid of ["u_bench", "u_friendly"]) f.put(`users/${uid}/bridge_status/current`, { uptime: 1, version: "1.2" });
    f.put("config/gameday_planner", {
      write_jobs: true, uid_allowlist: ["u_bench", "u_friendly"],
      espn_college_slate: true, track_started_by_id: ["u_bench"],
    });
    const readsBefore = f.reads.length;
    const stub = installFetchStub((u) =>
      u === `${CFB}/scoreboard/9300400`
        ? { body: espnEvent({ id: "9300400", startIso: "2026-10-09T23:00:00Z", home: "807", away: "808", state: "in" }) }
        : route(u)
    );
    try {
      await runPlannerTick(f.db, live);
    } finally {
      stub.restore();
    }
    const sessionQueries = f.reads.slice(readsBefore).filter((x) => /^query:users\/[^/]+\/game_day_sessions$/.test(x));
    expect(sessionQueries).toEqual(["query:users/u_bench/game_day_sessions"]);
    expect(stub.calls).toContain(`${CFB}/scoreboard/9300400`);
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

  test("a uid list: on for the listed account only (#157)", async () => {
    const listed = await tick({ preflight_ladder_lit: ["u_delta"] }, DARK);
    expect(listed.f.get(START)).toBeUndefined();
    expect(listed.user.gameday_server.preflight.reasons).toEqual(["preflight_ladder_dark"]);
    const other = await tick({ preflight_ladder_lit: ["u_someone_else"] }, DARK);
    expect(other.f.get(START)).toBeDefined();
  });

  test("\"strict\", field not yet published → withheld as preflight_ladder_unknown", async () => {
    const { f, user } = await tick({ preflight_ladder_lit: "strict" }, {});
    expect(f.get(START)).toBeUndefined();
    expect(user.gameday_server.preflight.reasons).toEqual(["preflight_ladder_unknown"]);
  });
});
