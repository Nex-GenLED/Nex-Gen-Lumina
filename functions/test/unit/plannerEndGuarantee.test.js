// planGameDayFires × the end guarantee (`end_ignores_gate`, 2026-10-06), parts
// 1–3 — the REAL planner tick on the shared in-memory Firestore.
//
// PART 1, early exits. The audit (deploy plan §11) found that an end could be
// withheld not only by the gate but by the loop's early exits: a missing
// controller document, unusable participation facts, the daylight rule, a
// team disabled or deleted, a game ESPN dropped. The per-account SWEEP
// (sweepFiredSessionEnds) now ends any fired start the loop did not decide,
// from the session alone, with a base restore.
// PART 2, #179. The end's budget is 90 minutes, its command is held pickable
// for the whole of it, and a job that goes terminal without completing is
// re-minted: six times at most, ten minutes apart, within twelve hours.
// PART 3, #178. A team disabled or deleted mid-game still ends.
// With the flag absent every scenario is byte-identical to today: nothing is
// read, written or decided that was not before.
//
// Times: Sunday 2026-10-11, kickoff 19:15 CDT (00:15Z Monday); the final is
// after sunset, so the base restore is preset 1. All ids are synthetic; the
// controller address is RFC 5737.

jest.mock("../../lib/espnClient", () => ({
  fetchTeamGame: jest.fn(async () => null),
  fetchEventById: jest.fn(async () => ({ kind: "error" })),
  fetchCollegeSlateGame: jest.fn(async () => ({ game: null, onSlate: false, complete: false })),
  fetchCollegeTeamDivision: jest.fn(async () => ({ kind: "error" })),
}));

const { logger } = require("firebase-functions");
const { fetchTeamGame, fetchEventById } = require("../../lib/espnClient");
const { makeFakeFirestore } = require("./support/fakeFirestore");
const { runPlannerTick } = require("../../lib/planGameDayFires");

const SEC = 1000;
const MIN = 60 * SEC;
const H = 60 * MIN;
const KICK = Date.parse("2026-10-12T00:15:00Z");
const FIRE = KICK - 30 * MIN;
const T0 = FIRE - 5 * H - 45 * MIN; // 18:00Z, inside the horizon
const FINAL1 = KICK + 3 * H + 20 * MIN;
const FINAL2 = FINAL1 + 5 * MIN;
const NOON_KICK = Date.parse("2026-10-11T17:00:00Z");

const UID = "u_guarantee";
const CTRL = "ctrl_guarantee";
const TEAM = "nfl_gteam";
const ESPN = "24";
const GAME = "9800001";
const EVENT = `gd_${TEAM}_${GAME}`;

const ARMED = { forcePolicy: { enabled: true, allowlist: [UID] } };
const FLAG = { ...ARMED, forceFlags: { endIgnoresGate: true } };

const USER = `users/${UID}`;
const BEAT = `users/${UID}/bridge_status/current`;
const CONFIG = `users/${UID}/game_day_autopilot/${TEAM}`;
const CONTROLLER = `users/${UID}/controllers/${CTRL}`;
const JOB = (id) => `users/${UID}/fire_jobs/${id}`;
const START = JOB(`${EVENT}_start`);
const END = JOB(`${EVENT}_end`);
const SESSION = `users/${UID}/game_day_sessions/${EVENT}`;
const SCORE = `gameday_scorecard/2026-10-11/entries/${UID}_${EVENT}`;
const BASE_ON = '{"ps":1}';
const BASE_OFF = '{"ps":2}';

const controllerDoc = (f, over = {}) => ({
  ip: "192.0.2.60",
  participating_channels: [0, 1],
  participating_channels_device_ids: [0, 1],
  participating_channels_at: f.ts(T0 - 2 * 86_400_000),
  base_ladder_asserts_segments: true,
  ...over,
});

function world() {
  const f = makeFakeFirestore({ now: T0 - H });
  f.put(USER, { owner_id: UID, time_zone: "America/Chicago", latitude: 39.0, longitude: -95.0 });
  f.put(CONTROLLER, controllerDoc(f));
  f.put(CONFIG, {
    enabled: true, team_slug: TEAM, team_name: "G Team", sport: "nfl", espn_team_id: ESPN,
    primary_color: 0xff102030, secondary_color: 0xff405060, effect_id: 52, speed: 160,
    intensity: 128, brightness: 200,
  });
  f.put(`bridge_registry/BR_${UID}`, { pairedUid: UID, status: "paired" });
  f.put(`users/${UID}/debug_errors/d1`, {
    context: "routing_decisions", app_version: "2.5.10+114", timestamp: f.ts(T0 - 2 * H),
  });
  return f;
}

/** ESPN's answer for the team (scoreboard) AND by id (the sweep's path). */
function espn(state = "scheduled", kick = KICK) {
  const game = {
    gameId: GAME, startMs: kick, homeTeamId: ESPN, awayTeamId: "0",
    isFinal: state === "final", isInProgress: state === "live",
    statusName: state === "final" ? "STATUS_FINAL" : state === "live" ? "STATUS_IN_PROGRESS" : "STATUS_SCHEDULED",
    statusState: state === "final" ? "post" : state === "live" ? "in" : "pre",
  };
  fetchTeamGame.mockImplementation(async (_s, id) => (id === ESPN ? game : null));
  fetchEventById.mockImplementation(async (_s, id) => (id === GAME ? { kind: "found", game } : { kind: "error" }));
}

function beat(f, ms) {
  const was = f.now();
  f.setNow(ms);
  f.put(BEAT, { uptime: 1, version: "1.2" });
  f.setNow(was);
}
async function tick(f, ms, opts = ARMED) {
  beat(f, ms - 20 * SEC);
  f.setNow(ms);
  return runPlannerTick(f.db, ms, opts);
}
const read = async (f, path) => (await f.db.doc(path).get()).data();
const rows = (r, action) => r.logRows.filter((x) => x.action === action);
const planEnd = (r) => rows(r, "plan_end").find((x) => x.eventId === EVENT);
async function completeProbes(f) {
  const q = await f.db.collection(`users/${UID}/commands`).where("source", "==", "gameday_preflight").get();
  for (const p of q.docs) f.patch(p.ref.path, { status: "completed" });
}

/** Mint the start (gate armed, healthy), and the dispatcher fires it. */
async function startFired(f, opts, { kick = KICK, startState = "completed" } = {}) {
  const t0 = kick - 30 * MIN - 5 * H - 45 * MIN;
  espn("scheduled", kick);
  await tick(f, t0, opts);
  await completeProbes(f);
  expect(await read(f, START)).toMatchObject({ state: "scheduled" });
  f.patch(START, { state: startState });
  return t0;
}

/** Two final ticks. */
async function finals(f, opts, { kick = KICK } = {}) {
  espn("final", kick);
  const f1 = kick + 3 * H + 20 * MIN;
  const r1 = await tick(f, f1, opts);
  const r2 = await tick(f, f1 + 5 * MIN, opts);
  return { r1, r2, at: f1 + 5 * MIN };
}

/** Run a PART 1 scenario both ways: `break(f)` makes the loop leave early. */
async function bothWays(breakFn, { kick = KICK } = {}) {
  const out = {};
  for (const [name, opts] of [["on", FLAG], ["off", ARMED]]) {
    const f = world();
    await startFired(f, opts, { kick });
    await breakFn(f);
    const { r2, at } = await finals(f, opts, { kick });
    out[name] = { f, r: r2, at, end: await read(f, END), session: await read(f, SESSION) };
  }
  return out;
}

let warn;
beforeEach(() => {
  fetchTeamGame.mockReset();
  fetchEventById.mockReset();
  espn();
  warn = jest.spyOn(logger, "warn").mockImplementation(() => {});
});
afterEach(() => warn.mockRestore());

function expectSweptEnd({ r, end, session, at }, cause) {
  expect(end).toMatchObject({ seq: "end", controllerId: CTRL, payload: BASE_ON, state: "scheduled", endVia: "session_sweep" });
  expect(end.fireAt.toMillis()).toBe(at);
  expect(end.retryUntil.toMillis()).toBe(at + 90 * MIN);
  expect(end.holdUntil.toMillis()).toBe(at + 90 * MIN);
  expect(session.endFiredAt.toMillis()).toBe(at);
  expect(session).toMatchObject({ endJobId: `${EVENT}_end`, endVia: "session_sweep" });
  if (cause) expect(session.endCause).toMatch(cause);
  expect(planEnd(r)).toMatchObject({ reason: "confirmed_final", via: "session_sweep" });
  if (cause) expect(planEnd(r).cause).toMatch(cause);
  expect(r.endsPlanned).toBe(1);
  expect(r.endsSwept).toBe(1);
}

function expectNoEnd({ r, end, session }) {
  expect(end).toBeUndefined();
  expect(session.endFiredAt).toBeUndefined();
  expect(planEnd(r)).toBeUndefined();
  expect(r).not.toHaveProperty("endsSwept");
  expect(r).not.toHaveProperty("endsReminted");
  expect(JSON.stringify(r.logRows)).not.toContain("session_sweep");
}

// ---------------------------------------------------------------------------
describe("PART 1 — no early exit withholds the end of a fired start", () => {
  test("participation facts unusable at the end: flag on → swept end with the base restore; off → nothing", async () => {
    const g = await bothWays((f) => {
      f.patch(CONTROLLER, { participating_channels_at: f.ts(T0 - 100 * 86_400_000) }); // past the 90-day floor
    });
    expectSweptEnd(g.on, /^participation_/);
    expect(rows(g.on.r, "skip").some((x) => String(x.reason).startsWith("participation_"))).toBe(true);
    expectNoEnd(g.off);
    expect(rows(g.off.r, "skip").some((x) => String(x.reason).startsWith("participation_"))).toBe(true);
  });

  test("the controller document is gone: flag on → swept end targeted at the controller the START lit; off → nothing", async () => {
    const g = await bothWays(async (f) => { await f.db.doc(CONTROLLER).delete(); });
    expectSweptEnd(g.on, "no_controller");
    expect(g.on.end.controllerId).toBe(CTRL);
    expect(g.on.r.skipped).toEqual({ no_controller: 1 });
    expectNoEnd(g.off);
    expect(g.off.r.skipped).toEqual({ no_controller: 1 });
  });

  test("the daylight rule on an end (noon game, skip_day_games turned on after the start): flag on → swept end, base OFF in daylight; off → nothing", async () => {
    const g = await bothWays((f) => { f.patch(CONFIG, { skip_day_games: true }); }, { kick: NOON_KICK });
    expect(g.on.end).toMatchObject({ payload: BASE_OFF, endVia: "session_sweep" });
    expect(g.on.session.endCause).toBe("daylight_game");
    expect(g.on.r.skipped).toEqual({ daylight_game: 1 });
    expect(g.on.r.endsSwept).toBe(1);
    expectNoEnd(g.off);
    expect(g.off.r.skipped).toEqual({ daylight_game: 1 });
  });

  test("the gate flipped before the final: the loop's own path still ends it (no sweep, no second job)", async () => {
    const f = world();
    await startFired(f, FLAG);
    f.put(CONTROLLER, controllerDoc(f, { base_ladder_asserts_segments: false }));
    const { r2 } = await finals(f, FLAG);
    expect(await read(f, END)).toMatchObject({ payload: BASE_ON });
    expect(await read(f, END)).not.toHaveProperty("endVia");
    expect(planEnd(r2)).toMatchObject({ gateBypassed: true });
    expect(planEnd(r2)).not.toHaveProperty("via");
    expect(r2).not.toHaveProperty("endsSwept");
    expect(r2.endsPlanned).toBe(1);
  });

  test("a start the bridge reported failed, and the controller document gone: flag on → swept end; off → nothing", async () => {
    const g = await bothWays(async (f) => { await f.db.doc(CONTROLLER).delete(); }, {});
    void g;
    for (const [name, opts] of [["on", FLAG], ["off", ARMED]]) {
      const f = world();
      await startFired(f, opts, { startState: "failed" });
      await f.db.doc(CONTROLLER).delete();
      const { r2, at } = await finals(f, opts);
      const end = await read(f, END);
      if (name === "on") {
        expect(end).toMatchObject({ payload: BASE_ON, endVia: "session_sweep" });
        expect(end.fireAt.toMillis()).toBe(at);
      } else {
        expect(end).toBeUndefined();
        expect(JSON.stringify(r2.logRows)).not.toContain("session_sweep");
      }
    }
  });

  test("ESPN no longer lists the game (scoreboard empty, flags off for tracking): flag on → the sweep finds it by id and ends it", async () => {
    const f = world();
    await startFired(f, FLAG);
    // The scoreboard drops the game; the by-id lookup still answers.
    espn("final");
    fetchTeamGame.mockImplementation(async () => null);
    await tick(f, FINAL1, FLAG);
    const r = await tick(f, FINAL2, FLAG);
    expect(r.skipped).toEqual({ no_game: 1 });
    expect(await read(f, END)).toMatchObject({ payload: BASE_ON, endVia: "session_sweep" });
    expect((await read(f, SESSION)).endCause).toBe("no_game");
    expect(r.endsSwept).toBe(1);
  });

  test("ESPN unreadable for a dropped game: the sweep ends it on the clock at the hard cap", async () => {
    const f = world();
    await startFired(f, FLAG);
    fetchTeamGame.mockImplementation(async () => null);
    fetchEventById.mockImplementation(async () => ({ kind: "error" }));
    const before = await tick(f, KICK + 3 * H, FLAG);
    expect(await read(f, END)).toBeUndefined();
    expect(before.endSkipped).toEqual({});
    const r = await tick(f, KICK + 4.5 * H + MIN, FLAG); // past start + 3.5 h + 60 min
    expect(await read(f, END)).toMatchObject({ payload: BASE_ON, endVia: "session_sweep" });
    expect(planEnd(r)).toMatchObject({ reason: "hard_cap", via: "session_sweep", capStatus: "unavailable" });
    expect(r.hardCapsPlanned).toBe(1);
  });

  test("the sweep never double-handles: a healthy loop-decided end leaves exactly one job and no sweep rows", async () => {
    const f = world();
    await startFired(f, FLAG);
    const { r2 } = await finals(f, FLAG);
    const jobs = await f.db.collection(`users/${UID}/fire_jobs`).get();
    expect(jobs.docs.map((d) => d.id).sort()).toEqual([`${EVENT}_end`, `${EVENT}_start`]);
    expect(r2).not.toHaveProperty("endsSwept");
    expect(JSON.stringify(r2.logRows)).not.toContain("session_sweep");
  });
});

// ---------------------------------------------------------------------------
describe("PART 2 — #179: the budget, the hold, and re-minting a dead end", () => {
  async function endedAtFinal(f, opts = FLAG) {
    await startFired(f, opts);
    const { at } = await finals(f, opts);
    const end = await read(f, END);
    expect(end.retryUntil.toMillis()).toBe(at + 90 * MIN);
    expect(end.holdUntil.toMillis()).toBe(at + 90 * MIN);
    return at;
  }

  test("the bridge silent past the old 15-minute budget: the dispatched job is left alone by the planner, and completes when the bridge returns", async () => {
    const f = world();
    const at = await endedAtFinal(f);
    f.patch(END, { state: "dispatched", commandId: "cmd_1" }); // the dispatcher wrote the (held) command
    for (const m of [20, 40, 60]) {
      const r = await tick(f, at + m * MIN, FLAG);
      expect(r).not.toHaveProperty("endsReminted");
      expect(await read(f, JOB(`${EVENT}_end_r1`))).toBeUndefined();
    }
    f.patch(END, { state: "completed" }); // the bridge came back at ~75 min and ran it
    const r = await tick(f, at + 80 * MIN, FLAG);
    expect(r).not.toHaveProperty("endsReminted");
    expect(rows(r, "plan_end_remint")).toEqual([]);
    expect((await read(f, SESSION)).endRemints).toBeUndefined();
  });

  test("an outage longer than 90 minutes: the job goes terminal and the planner re-mints; the re-mint completes when the bridge returns", async () => {
    const f = world();
    const at = await endedAtFinal(f);
    f.patch(END, { state: "dispatched", commandId: "cmd_1" });
    await tick(f, at + 60 * MIN, FLAG);
    // 91 min: the sweeper expired the held command, the dispatcher ran out of budget.
    f.patch(END, { state: "expired", retryVerdict: "retry_budget_exhausted" });
    const r = await tick(f, at + 95 * MIN, FLAG);
    const r1 = await read(f, JOB(`${EVENT}_end_r1`));
    expect(r1).toMatchObject({
      eventId: EVENT, seq: "end", controllerId: CTRL, payload: BASE_ON, state: "scheduled",
      remintOf: `${EVENT}_end`, remint: 1, source: "game_day",
    });
    expect(r1.fireAt.toMillis()).toBe(at + 95 * MIN);
    expect(r1.retryUntil.toMillis()).toBe(at + 95 * MIN + 90 * MIN);
    expect(r1.holdUntil.toMillis()).toBe(at + 95 * MIN + 90 * MIN);
    const s = await read(f, SESSION);
    expect(s).toMatchObject({ endJobId: `${EVENT}_end_r1`, endRemints: 1 });
    expect(s.endRemintedAt.toMillis()).toBe(at + 95 * MIN);
    expect(rows(r, "plan_end_remint")).toEqual([
      { uid: UID, teamSlug: TEAM, eventId: EVENT, action: "plan_end_remint", fireAt: new Date(at + 95 * MIN).toISOString(), n: 1, priorJob: `${EVENT}_end`, priorState: "expired" },
    ]);
    expect(r.endsReminted).toBe(1);
    expect((await read(f, SCORE)).end).toMatchObject({ job_id: `${EVENT}_end_r1`, remints: 1, reminted_from: `${EVENT}_end`, prior_outcome: "expired" });

    // The bridge returns and runs the re-minted restore.
    f.patch(JOB(`${EVENT}_end_r1`), { state: "completed" });
    const done = await tick(f, at + 110 * MIN, FLAG);
    expect(done).not.toHaveProperty("endsReminted");
    expect(await read(f, JOB(`${EVENT}_end_r2`))).toBeUndefined();
  });

  test("a cancelled or failed end job is re-minted the same way", async () => {
    for (const state of ["cancelled", "failed", "skipped"]) {
      const f = world();
      const at = await endedAtFinal(f);
      f.patch(END, { state });
      const r = await tick(f, at + 15 * MIN, FLAG);
      expect(await read(f, JOB(`${EVENT}_end_r1`))).toMatchObject({ remintOf: `${EVENT}_end` });
      expect(rows(r, "plan_end_remint")[0]).toMatchObject({ priorState: state });
    }
  });

  test("ten minutes apart: a re-mint that dies at once is not replaced for ten minutes", async () => {
    const f = world();
    const at = await endedAtFinal(f);
    f.patch(END, { state: "expired" });
    await tick(f, at + 15 * MIN, FLAG); // r1
    f.patch(JOB(`${EVENT}_end_r1`), { state: "expired" });
    const soon = await tick(f, at + 20 * MIN, FLAG);
    expect(await read(f, JOB(`${EVENT}_end_r2`))).toBeUndefined();
    expect(soon).not.toHaveProperty("endsReminted");
    await tick(f, at + 25 * MIN, FLAG);
    expect(await read(f, JOB(`${EVENT}_end_r2`))).toMatchObject({ remint: 2, remintOf: `${EVENT}_end_r1` });
  });

  test("the hard ceiling: six re-mints, then it stops and says so", async () => {
    const f = world();
    const at = await endedAtFinal(f);
    f.patch(END, { state: "expired" });
    for (let n = 1; n <= 6; n++) {
      const r = await tick(f, at + (5 + 10 * n) * MIN, FLAG);
      expect(await read(f, JOB(`${EVENT}_end_r${n}`))).toMatchObject({ remint: n });
      expect(r.endsReminted).toBe(1);
      f.patch(JOB(`${EVENT}_end_r${n}`), { state: "expired" });
    }
    const r = await tick(f, at + 75 * MIN, FLAG);
    expect(await read(f, JOB(`${EVENT}_end_r7`))).toBeUndefined();
    expect(r).not.toHaveProperty("endsReminted");
    expect(rows(r, "skip").find((x) => x.reason === "end_remint_ceiling:max_remints")).toMatchObject({ eventId: EVENT });
    expect((await read(f, SESSION)).endRemints).toBe(6);
  });

  test("the horizon: a session whose game started more than twelve hours ago is not read at all", async () => {
    const f = world();
    const at = await endedAtFinal(f);
    f.patch(END, { state: "expired" });
    // The team is gone (so the loop does not refresh the session's kickoff from
    // ESPN each tick), and the game is a day old: outside the sweep's window.
    await f.db.doc(CONFIG).delete();
    f.patch(SESSION, { gameStartMs: at - 13 * H });
    const r = await tick(f, at + 15 * MIN, FLAG);
    expect(await read(f, JOB(`${EVENT}_end_r1`))).toBeUndefined();
    expect(r).not.toHaveProperty("endsReminted");
    expect(JSON.stringify(r.logRows)).not.toContain(EVENT);
    // Inside the window the same dead end IS re-minted.
    f.patch(SESSION, { gameStartMs: at - 11 * H });
    const again = await tick(f, at + 30 * MIN, FLAG);
    expect(await read(f, JOB(`${EVENT}_end_r1`))).toBeDefined();
    expect(again.endsReminted).toBe(1);
  });

  test("flag absent: a dead end job is never re-minted (today's behaviour)", async () => {
    const f = world();
    await startFired(f, ARMED);
    const { at } = await finals(f, ARMED);
    expect((await read(f, END)).retryUntil.toMillis()).toBe(at + 15 * MIN);
    expect(await read(f, END)).not.toHaveProperty("holdUntil");
    f.patch(END, { state: "expired" });
    const r = await tick(f, at + 20 * MIN, ARMED);
    expect(await read(f, JOB(`${EVENT}_end_r1`))).toBeUndefined();
    expect(r).not.toHaveProperty("endsReminted");
    expect(r.endSkipped).toEqual({});
  });
});

// ---------------------------------------------------------------------------
describe("PART 3 — #178: a team disabled or deleted mid-game still ends", () => {
  test("deleted after the start fired: flag on → the end is written from the session, base ON after sunset; off → nothing", async () => {
    for (const [name, opts] of [["on", FLAG], ["off", ARMED]]) {
      const f = world();
      await startFired(f, opts);
      await f.db.doc(CONFIG).delete();
      const { r2, at } = await finals(f, opts);
      expect(r2.usersScanned).toBe(0); // no enabled config: the loop never entered
      const end = await read(f, END);
      if (name === "on") {
        expect(end).toMatchObject({ payload: BASE_ON, controllerId: CTRL, endVia: "session_sweep" });
        expect(end.fireAt.toMillis()).toBe(at);
        expect((await read(f, SESSION))).toMatchObject({ endCause: "config_disabled_or_deleted", endJobId: `${EVENT}_end` });
        expect(planEnd(r2)).toMatchObject({ reason: "confirmed_final", via: "session_sweep", cause: "config_disabled_or_deleted" });
        expect(r2.endsSwept).toBe(1);
      } else {
        expect(end).toBeUndefined();
        expect(planEnd(r2)).toBeUndefined();
        expect(JSON.stringify(r2.logRows)).not.toContain("session_sweep");
      }
    }
  });

  test("disabled after the start fired: the same", async () => {
    const f = world();
    await startFired(f, FLAG);
    f.patch(CONFIG, { enabled: false });
    const { r2 } = await finals(f, FLAG);
    expect(await read(f, END)).toMatchObject({ payload: BASE_ON, endVia: "session_sweep" });
    expect((await read(f, SESSION)).endCause).toBe("config_disabled_or_deleted");
    expect(r2.endsSwept).toBe(1);
  });

  test("the restore when the config is gone follows the clock: a noon game restores base OFF", async () => {
    const f = world();
    await startFired(f, FLAG, { kick: NOON_KICK });
    await f.db.doc(CONFIG).delete();
    await finals(f, FLAG, { kick: NOON_KICK });
    expect(await read(f, END)).toMatchObject({ payload: BASE_OFF, endVia: "session_sweep" });
  });

  test("a session whose start never fired stays untouched when its team is deleted (the teardown cancelled the start)", async () => {
    const f = world();
    espn("scheduled");
    await tick(f, T0, FLAG);
    f.patch(START, { state: "cancelled", cancelled_reason: "team_deleted" });
    await f.db.doc(CONFIG).delete();
    espn("final");
    await tick(f, FINAL1, FLAG);
    const r = await tick(f, FINAL2, FLAG);
    expect(await read(f, END)).toBeUndefined();
    const s = await read(f, SESSION);
    expect(s.endFiredAt).toBeUndefined();
    expect(s).not.toHaveProperty("endJobId");
    expect(rows(r, "skip").find((x) => x.reason === "end_sweep_start_not_fired")).toMatchObject({ eventId: EVENT, startJobState: "cancelled" });
    expect(r).not.toHaveProperty("endsSwept");
  });

  test("a dead end job of a deleted team is re-minted too", async () => {
    const f = world();
    await startFired(f, FLAG);
    const { at } = await finals(f, FLAG);
    await f.db.doc(CONFIG).delete();
    f.patch(END, { state: "cancelled" });
    const r = await tick(f, at + 15 * MIN, FLAG);
    expect(await read(f, JOB(`${EVENT}_end_r1`))).toMatchObject({ payload: BASE_ON, remintOf: `${EVENT}_end` });
    expect(r.endsReminted).toBe(1);
  });
});

// ---------------------------------------------------------------------------
describe("the production read: end_ignores_gate from config/gameday_planner runs the sweep", () => {
  test("[uid]: a deleted team's fired start is ended; absent: it is not", async () => {
    for (const [cfg, expectEnd] of [[{ end_ignores_gate: [UID] }, true], [{}, false]]) {
      const f = world();
      f.put("config/gameday_planner", { write_jobs: true, uid_allowlist: [UID], ...cfg });
      const run = async (ms) => { beat(f, ms - 20 * SEC); f.setNow(ms); return runPlannerTick(f.db, ms); };
      espn("scheduled");
      await run(T0);
      await completeProbes(f);
      f.patch(START, { state: "completed" });
      await f.db.doc(CONFIG).delete();
      espn("final");
      await run(FINAL1);
      await run(FINAL2);
      expect(await read(f, END) !== undefined).toBe(expectEnd);
    }
  });
});
