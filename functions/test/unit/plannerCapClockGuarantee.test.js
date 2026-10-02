// #159 — THE CLOCK GUARANTEE. With status_aware_cap on, a started game's cap
// fires on the clock whatever ESPN does: down, erroring, rate limiting, timing
// out, answering nothing usable, or no longer listing the game.
//
// The table these tests prove (gameDayPlanning.decideEndWithoutEspn):
//   UNAVAILABLE (HTTP 5xx / 429, timeout, network, unparseable body, a partial
//     college slate)                   → held past the bound; the CEILING fires
//   SILENT (2xx empty, game missing, single-game 404) → fires at the bound
//   status unknown, not under state "in" → fires at the bound
//   status unknown under state "in"      → live: held; the ceiling fires
// and, for every mode, NOTHING is still running past the ceiling.
//
// Real planner, real espnClient, `fetch` stubbed by URL from T3 on. The game
// under test is the scenario's NFL game for the allowlisted account (kickoff
// 00:15Z, shipped bound 04:45Z, football ceiling 06:15Z): T3 03:30Z and
// T4 03:35Z are before the bound, T5 04:50Z is past it, T6 06:20Z is past the
// ceiling. Two college modes use the unfeatured college game (kickoff 00:00Z,
// bound 04:30Z, ceiling 06:00Z).

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { installFetchStub, espnEvent, scoreboard, BASE } = require("./support/espnFixtures");
const S = require("./support/plannerScenario");
const { runPlannerTick } = require("../../lib/planGameDayFires");

const ARMED = { enabled: true, allowlist: S.ALLOWLIST };
const TICKS = [...S.TICKS, "T6"];
const NFL_BOARD = `${BASE}/football/nfl/scoreboard`;
const NFL_BY_ID = `${BASE}/football/nfl/scoreboard/${S.EV.nfl}`;
const CFB = `${BASE}/football/college-football`;
const NFL_EVENT = `gd_nfl_alpha_${S.EV.nfl}`;
const GATOR_EVENT = `gd_ncaa_gator_${S.EV.gator}`;
const NFL_CEILING = "2026-10-11T06:15:00.000Z";
const GATOR_CEILING = "2026-10-11T06:00:00.000Z";
const failing = (tick) => tick !== "T1" && tick !== "T2";

async function run(flags, override) {
  const f = makeFakeFirestore({ now: S.T.T1 });
  S.seedWorld(f);
  const out = {};
  for (const tick of TICKS) {
    f.setNow(S.T[tick]);
    S.heartbeat(f);
    const base = S.espnRoute(tick);
    const stub = installFetchStub((u) => (failing(tick) ? override(u) : undefined) ?? base(u));
    try {
      out[tick] = await runPlannerTick(f.db, S.T[tick], { forcePolicy: ARMED, forceFlags: flags });
    } finally {
      stub.restore();
    }
    expect(out[tick].errors).toBe(0);
    if (tick === "T1") S.completeStarts(f);
  }
  return { f, out };
}

const rows = (r, uid, eventId) => r.logRows.filter((x) => x.uid === uid && x.eventId === eventId);
const endRow = (r, uid, eventId) => rows(r, uid, eventId).find((x) => x.action === "plan_end");

// Each mode: how ESPN fails for the NFL game, and what the cap must do.
const nflOnly = (fn) => (u) => (u === NFL_BOARD || u === NFL_BY_ID ? fn(u) : undefined);
const nflEvent = (state, name) =>
  espnEvent({ id: S.EV.nfl, startIso: S.KICK.nfl, home: "901", away: "902", state, name });
const MODES = [
  ["HTTP 500", "unavailable", nflOnly(() => ({ status: 500, body: {} }))],
  ["HTTP 429 (rate limited)", "unavailable", nflOnly(() => ({ status: 429, body: { message: "Too Many Requests" } }))],
  ["HTTP 403", "unavailable", nflOnly(() => ({ status: 403, body: {} }))],
  ["timeout (AbortError)", "unavailable", nflOnly(() => ({ throws: "AbortError" }))],
  ["network failure", "unavailable", nflOnly(() => ({ throws: true }))],
  ["unparseable 2xx (no events, not the game)", "unavailable", nflOnly(() => ({ body: { notAScoreboard: true } }))],
  ["empty 2xx scoreboard + single-game 404", "silent",
    nflOnly((u) => (u === NFL_BY_ID ? { status: 404, body: { code: 404 } } : { body: scoreboard([]) }))],
  ["game missing: other games listed + single-game 404", "silent",
    nflOnly((u) => (u === NFL_BY_ID
      ? { status: 404, body: { code: 404 } }
      : { body: scoreboard([espnEvent({ id: "9399999", startIso: S.KICK.nfl, home: "903", away: "904", state: "in" })]) }))],
  ["status unknown (state post)", "not_live",
    nflOnly((u) => (u === NFL_BY_ID ? { body: nflEvent("post", "STATUS_NEW_THING") } : { body: scoreboard([nflEvent("post", "STATUS_NEW_THING")]) }))],
  ["status unknown under state \"in\"", "live",
    nflOnly((u) => (u === NFL_BY_ID ? { body: nflEvent("in", "STATUS_NEW_THING") } : { body: scoreboard([nflEvent("in", "STATUS_NEW_THING")]) }))],
];

const FLAG_SETS = [
  ["status_aware_cap", { statusAwareCap: true }],
  ["status_aware_cap + track_started_by_id", { statusAwareCap: true, trackStartedById: true }],
];

describe.each(FLAG_SETS)("%s — every ESPN failure mode, the NFL game", (_label, flags) => {
  test.each(MODES)("%s → %s", async (_mode, kind, override) => {
    const { f, out } = await run(flags, override);
    const end = f.get(`users/u_alpha/fire_jobs/${NFL_EVENT}_end`);

    // Before the bound nothing ends, whatever ESPN does.
    for (const t of ["T3", "T4"]) expect(endRow(out[t], "u_alpha", NFL_EVENT)).toBeUndefined();

    if (kind === "unavailable") {
      expect(rows(out.T3, "u_alpha", NFL_EVENT)).toEqual(expect.arrayContaining([
        expect.objectContaining({ reason: "espn_unavailable", ceilingAt: NFL_CEILING }),
      ]));
      // Past the bound: HELD — an outage is not evidence the game ended.
      expect(endRow(out.T5, "u_alpha", NFL_EVENT)).toBeUndefined();
      expect(rows(out.T5, "u_alpha", NFL_EVENT)).toEqual(expect.arrayContaining([
        expect.objectContaining({ reason: "cap_held_unavailable", ceilingAt: NFL_CEILING }),
      ]));
      // Past the ceiling: fired on the clock alone.
      expect(endRow(out.T6, "u_alpha", NFL_EVENT)).toMatchObject({ reason: "hard_cap_ceiling", capStatus: "espn_unavailable" });
    } else if (kind === "live") {
      expect(endRow(out.T5, "u_alpha", NFL_EVENT)).toBeUndefined();
      expect(endRow(out.T6, "u_alpha", NFL_EVENT)).toMatchObject({ reason: "hard_cap_ceiling", capStatus: "STATUS_NEW_THING" });
    } else {
      // silent / not live: the shipped bound, the first tick past it.
      expect(endRow(out.T5, "u_alpha", NFL_EVENT)).toMatchObject({
        reason: "hard_cap",
        capStatus: kind === "silent" ? "silent" : "STATUS_NEW_THING",
      });
    }

    // NONE holds past the ceiling: by T6 the end job exists, and it is the
    // base restore (after sunset: base ON).
    expect(end).toBeDefined();
    expect(end.payload).toBe('{"ps":1}');
    expect(end.fireAt.toMillis()).toBeLessThanOrEqual(S.T.T6);
  });
});

describe("college: an empty slate is silent, a partial slate is unavailable", () => {
  const SLATE = /college-football\/scoreboard\?dates=/;
  const flags = { espnCollegeSlate: true, statusAwareCap: true };

  test("empty 2xx slate (every date `events: []`) → fires at the bound", async () => {
    const { f, out } = await run(flags, (u) => (SLATE.test(u) ? { body: scoreboard([]) } : undefined));
    expect(endRow(out.T5, "u_charlie", GATOR_EVENT)).toMatchObject({ reason: "hard_cap", capStatus: "silent" });
    expect(f.get(`users/u_charlie/fire_jobs/${GATOR_EVENT}_end`)).toBeDefined();
  });

  test("one slate date failing (HTTP 500) → held past the bound, the ceiling fires", async () => {
    const { f, out } = await run(flags, (u) =>
      SLATE.test(u) ? (u.includes("dates=20261010") ? { status: 500, body: {} } : { body: scoreboard([]) }) : undefined
    );
    expect(endRow(out.T5, "u_charlie", GATOR_EVENT)).toBeUndefined();
    expect(rows(out.T5, "u_charlie", GATOR_EVENT)).toEqual(expect.arrayContaining([
      expect.objectContaining({ reason: "cap_held_unavailable", ceilingAt: GATOR_CEILING }),
    ]));
    expect(endRow(out.T6, "u_charlie", GATOR_EVENT)).toMatchObject({ reason: "hard_cap_ceiling", capStatus: "espn_unavailable" });
    expect(f.get(`users/u_charlie/fire_jobs/${GATOR_EVENT}_end`)).toBeDefined();
  });

  test("every slate request failing on the network → the same: held, then the ceiling", async () => {
    const { out } = await run(flags, (u) => (SLATE.test(u) ? { throws: true } : undefined));
    expect(endRow(out.T5, "u_charlie", GATOR_EVENT)).toBeUndefined();
    expect(endRow(out.T6, "u_charlie", GATOR_EVENT)).toMatchObject({ reason: "hard_cap_ceiling", capStatus: "espn_unavailable" });
  });
});

describe("what the guarantee does NOT change", () => {
  test("an unavailable tick neither advances nor resets the final count", async () => {
    // NFL: final at T4 (count 1), ESPN down at T5, final again at T6.
    const override = (tick) => (u) => {
      if (u !== NFL_BOARD && u !== NFL_BY_ID) return undefined;
      if (tick === "T4" || tick === "T6") {
        const ev = nflEvent("post", "STATUS_FINAL");
        return u === NFL_BY_ID ? { body: ev } : { body: scoreboard([ev]) };
      }
      if (tick === "T5") return { status: 503, body: {} };
      return undefined;
    };
    const f = makeFakeFirestore({ now: S.T.T1 });
    S.seedWorld(f);
    const sessionPath = `users/u_alpha/game_day_sessions/${NFL_EVENT}`;
    const counts = {};
    for (const tick of TICKS) {
      f.setNow(S.T[tick]);
      S.heartbeat(f);
      const base = S.espnRoute(tick);
      const ov = override(tick);
      const stub = installFetchStub((u) => ov(u) ?? base(u));
      try {
        await runPlannerTick(f.db, S.T[tick], { forcePolicy: ARMED, forceFlags: { statusAwareCap: true, trackStartedById: true } });
      } finally {
        stub.restore();
      }
      if (tick === "T1") S.completeStarts(f);
      counts[tick] = (f.get(sessionPath) || {}).consecutiveFinalPolls;
    }
    expect(counts.T4).toBe(1);
    expect(counts.T5).toBe(1); // the outage tick kept it
    // T5 is past the bound with the count at 1, ESPN unavailable: held, no end.
    // T6 is the second final — but also past the ceiling; the end fires either way.
    expect(f.get(`users/u_alpha/fire_jobs/${NFL_EVENT}_end`)).toBeDefined();
  });

  test("status_aware_cap OFF: ESPN down after the start is the shipped gap — no end at all (unchanged)", async () => {
    const { f } = await run({ trackStartedById: true }, nflOnly(() => ({ status: 500, body: {} })));
    expect(f.get(`users/u_alpha/fire_jobs/${NFL_EVENT}_end`)).toBeUndefined();
  });

  test("a game ESPN answers normally is untouched by the guarantee (the scenario's falcon final)", async () => {
    const { f, out } = await run({ statusAwareCap: true }, () => undefined);
    expect(rows(out.T4, "u_alpha", `gd_ncaa_falcon_${S.EV.falcon}`)).toEqual(expect.arrayContaining([
      expect.objectContaining({ action: "skip", reason: "end_suppressed_not_owner" }),
    ]));
    expect(f.get(`users/u_alpha/fire_jobs/gd_ncaa_falcon_${S.EV.falcon}_end`)).toBeUndefined();
  });
});
