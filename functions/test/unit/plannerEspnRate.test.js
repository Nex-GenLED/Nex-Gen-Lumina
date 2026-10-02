// ESPN request rate per planner tick — today's fleet and 10x — with the flags
// off and on. Real planner, real espnClient, `fetch` stubbed and counted.
//
// TODAY (shape, not identities): ~10 enabled configs over 10 distinct
// sport/team pairs, one of them college football. The pre-fix planner fetched
// one default scoreboard per distinct sport/team pair, so ~10 a tick.
// 10x: ten times the accounts and four times the distinct teams (leagues cap
// how many distinct teams there can be).
//
// The bound the tests pin, for any fleet:
//   requests per tick ≤ sports with an enabled config        (default boards)
//                     + 3                                    (FBS dates, flag on)
//                     + distinct started games               (by id, flag on)
//                     + distinct college ids missing a full slate (team docs)
// None of the terms grows with the number of ACCOUNTS.

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { installFetchStub, espnEvent, scoreboard, teamDoc, BASE } = require("./support/espnFixtures");
const S = require("./support/plannerScenario");
const { runPlannerTick } = require("../../lib/planGameDayFires");

const MINT = Date.parse("2026-10-10T17:50:00Z");
const LIVE = Date.parse("2026-10-11T01:00:00Z");
const KICK = "2026-10-11T00:15:00Z";
const PATH = { nfl: "football/nfl", mlb: "baseball/mlb", nhl: "hockey/nhl", mls: "soccer/usa.1", ncaaFB: "football/college-football" };

/** A pool of distinct sport/team pairs; each team plays its own game. */
function pool(counts) {
  const out = [];
  let id = 1000;
  for (const [sport, n] of Object.entries(counts)) {
    for (let i = 0; i < n; i++) {
      id++;
      out.push({ sport, team: String(id), game: String(9_500_000 + id), slug: `${sport.toLowerCase()}_t${id}` });
    }
  }
  return out;
}
const TODAY = pool({ nfl: 6, mlb: 1, nhl: 1, mls: 1, ncaaFB: 1 }); // 10 pairs, 5 sports
const TENX = pool({ nfl: 24, mlb: 4, nhl: 4, mls: 4, ncaaFB: 4 }); // 40 pairs, 5 sports

function fleet(teams, accounts) {
  const f = makeFakeFirestore({ now: MINT });
  const uids = [];
  for (let n = 1; n <= accounts; n++) {
    const t = teams[(n - 1) % teams.length];
    const uid = `u_rate_${n}`;
    uids.push(uid);
    S.seedAccount(f, uid, n, { configs: { [t.slug]: S.teamConfig(t.slug, `Team ${t.team}`, t.sport, t.team) }, priority: [t.slug], bridge: true });
  }
  return { f, uids };
}

function route(teams, state) {
  const ev = (t) => espnEvent({ id: t.game, startIso: KICK, home: t.team, away: "1", state });
  const bySport = {};
  for (const t of teams) (bySport[t.sport] = bySport[t.sport] || []).push(ev(t));
  const byGame = new Map(teams.map((t) => [t.game, ev(t)]));
  return (u) => {
    for (const [sport, path] of Object.entries(PATH)) {
      if (u === `${BASE}/${path}/scoreboard`) return { body: scoreboard(bySport[sport] || []) };
    }
    if (u.includes("/college-football/scoreboard?dates=")) {
      return { body: scoreboard(u.includes("dates=20261010") ? bySport.ncaaFB || [] : []) };
    }
    const one = /\/scoreboard\/(\d+)$/.exec(u);
    if (one) return byGame.has(one[1]) ? { body: byGame.get(one[1]) } : { status: 404, body: {} };
    const team = /\/college-football\/teams\/(\d+)$/.exec(u);
    if (team) return { body: teamDoc(team[1], "80") };
    return undefined;
  };
}

/** Mint every start, model the dispatcher, then measure a live tick. */
async function measure(teams, accounts, flags) {
  const { f, uids } = fleet(teams, accounts);
  const counts = {};
  for (const [label, ms, state] of [["mint", MINT, "pre"], ["live", LIVE, "in"]]) {
    f.setNow(ms);
    for (const uid of uids) f.put(`users/${uid}/bridge_status/current`, { uptime: 1, version: "1.2" });
    const stub = installFetchStub(route(teams, state));
    let r;
    try {
      r = await runPlannerTick(f.db, ms, { forcePolicy: { enabled: true, allowlist: null }, forceFlags: flags });
    } finally {
      stub.restore();
    }
    expect(new Set(stub.calls).size).toBe(stub.calls.length); // one request per URL
    expect(r.espnFetches).toBe(stub.calls.length);
    expect(r.errors).toBe(0);
    counts[label] = { calls: stub.calls.length, starts: r.startsPlanned, r };
    if (label === "mint") S.completeStarts(f);
  }
  return counts;
}

const ON = { espnCollegeSlate: true, trackStartedById: true, statusAwareCap: true };
const distinctPairs = (teams) => new Set(teams.map((t) => `${t.sport}/${t.team}`)).size;
const sports = (teams) => new Set(teams.map((t) => t.sport)).size;

describe("requests per tick", () => {
  test("TODAY, flags off: one per sport (5), where the pre-fix planner made one per sport/team pair (10)", async () => {
    const c = await measure(TODAY, 14, {});
    expect(distinctPairs(TODAY)).toBe(10);
    expect(c.mint.starts).toBe(14);
    expect(c.mint.calls).toBe(5);
    expect(c.live.calls).toBe(5);
  });

  test("TODAY, flags on: 4 pro boards + 3 FBS dates before the starts; one by-id read per started game after", async () => {
    const c = await measure(TODAY, 14, ON);
    expect(c.mint.calls).toBe(4 + 3);
    expect(c.live.calls).toBe(10); // every account's game is started and tracked
  });

  test("10x, flags off: still one per sport (5) — the pre-fix planner would make 40", async () => {
    const c = await measure(TENX, 140, {});
    expect(distinctPairs(TENX)).toBe(40);
    expect(c.mint.starts).toBe(140);
    expect(c.mint.calls).toBe(5);
    expect(c.live.calls).toBe(5);
  });

  test("10x, flags on: 7 before the starts, one per distinct live game (40) after — never per account", async () => {
    const c = await measure(TENX, 140, ON);
    expect(c.mint.calls).toBe(7);
    expect(c.live.calls).toBe(40);
  });

  test("ten times the ACCOUNTS on today's teams costs nothing extra", async () => {
    const a = await measure(TODAY, 14, ON);
    const b = await measure(TODAY, 140, ON);
    expect(b.mint.calls).toBe(a.mint.calls);
    expect(b.live.calls).toBe(a.live.calls);
  });

  test("the bound holds in every case", async () => {
    for (const [teams, accounts] of [[TODAY, 14], [TENX, 140]]) {
      for (const flags of [{}, ON]) {
        const c = await measure(teams, accounts, flags);
        const games = distinctPairs(teams);
        for (const tick of ["mint", "live"]) {
          expect(c[tick].calls).toBeLessThanOrEqual(sports(teams) + 3 + games);
        }
      }
    }
  });
});
