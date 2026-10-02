// #158 — a start is not minted for a game ESPN already reports will not be
// played tonight (status_aware_cap on). Real planner and espnClient, `fetch`
// stubbed. The scenario's allowlisted account, its NFL game (fire 23:45Z), at
// the first tick inside the 6 h horizon (17:50Z).

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { installFetchStub, espnEvent, scoreboard, BASE } = require("./support/espnFixtures");
const S = require("./support/plannerScenario");
const { runPlannerTick } = require("../../lib/planGameDayFires");

const NFL_BOARD = `${BASE}/football/nfl/scoreboard`;
const START = `users/u_alpha/fire_jobs/gd_nfl_alpha_${S.EV.nfl}_start`;
const ARMED = { enabled: true, allowlist: S.ALLOWLIST };

async function tickWith(f, ms, name, state, flags) {
  f.setNow(ms);
  S.heartbeat(f);
  const base = S.espnRoute("T1");
  const ev = espnEvent({ id: S.EV.nfl, startIso: S.KICK.nfl, home: "901", away: "902", state, name });
  const stub = installFetchStub((u) => (u === NFL_BOARD ? { body: scoreboard([ev]) } : base(u)));
  try {
    return await runPlannerTick(f.db, ms, { forcePolicy: ARMED, forceFlags: flags });
  } finally {
    stub.restore();
  }
}
function world() {
  const f = makeFakeFirestore({ now: S.T.T1 });
  S.seedWorld(f);
  return f;
}
const nflRows = (r) => r.logRows.filter((x) => x.uid === "u_alpha" && x.teamSlug === "nfl_alpha");

describe.each([
  ["STATUS_POSTPONED", "post"],
  ["STATUS_CANCELED", "post"],
  ["STATUS_SUSPENDED", "in"],
])("%s", (name, state) => {
  test("status_aware_cap ON: no start job; a named START bucket and row", async () => {
    const f = world();
    const r = await tickWith(f, S.T.T1, name, state, { statusAwareCap: true });
    expect(f.get(START)).toBeUndefined();
    // Two configs follow this game: the armed account's and the log-only one's.
    expect(r.skipped.game_not_played).toBe(2);
    expect(nflRows(r)).toEqual(expect.arrayContaining([
      expect.objectContaining({ action: "skip", reason: "game_not_played", espnStatus: name, fireAt: "2026-10-10T23:45:00.000Z" }),
    ]));
    expect(nflRows(r).some((x) => x.action === "plan_start")).toBe(false);
    // Still one START bucket per enabled config.
    const buckets = Object.values(r.skipped).reduce((a, b) => a + b, 0);
    expect(buckets + r.startsPlanned).toBe(r.configsEnabled);
  });

  test("status_aware_cap OFF: minted, as shipped", async () => {
    const f = world();
    await tickWith(f, S.T.T1, name, state, {});
    expect(f.get(START)).toBeDefined();
  });
});

test("a game ESPN reschedules (back to scheduled) mints on the next tick", async () => {
  const f = world();
  await tickWith(f, S.T.T1, "STATUS_POSTPONED", "post", { statusAwareCap: true });
  expect(f.get(START)).toBeUndefined();
  const r = await tickWith(f, S.T.T1 + 5 * 60_000, "STATUS_SCHEDULED", "pre", { statusAwareCap: true });
  expect(f.get(START)).toBeDefined();
  expect(nflRows(r).some((x) => x.reason === "game_not_played")).toBe(false);
});

test("a delayed game is NOT skipped — a delay is still a game tonight", async () => {
  const f = world();
  await tickWith(f, S.T.T1, "STATUS_DELAYED", "pre", { statusAwareCap: true });
  expect(f.get(START)).toBeDefined();
});

test("a start already minted is not withdrawn by a later postponement (#158, decision)", async () => {
  const f = world();
  await tickWith(f, S.T.T1, "STATUS_SCHEDULED", "pre", { statusAwareCap: true });
  expect(f.get(START).state).toBe("scheduled");
  const r = await tickWith(f, S.T.T1 + 5 * 60_000, "STATUS_POSTPONED", "post", { statusAwareCap: true });
  expect(f.get(START).state).toBe("scheduled");
  expect(r.skipped.start_already_planned).toBeGreaterThanOrEqual(1);
});
