// planGameDayFires × `end_ignores_gate` (2026-10-06) — the REAL planner tick on
// the shared in-memory Firestore.
//
// THE INCIDENT, 2026-10-05, bench account. A start minted at the morning tick
// fired on the server path at 18:46:38 CDT (the dispatcher does not consult
// the gate). At 15:50 CDT the owner had added a fourth controller bus, so the
// readiness gate had flipped to `gated_ladder_bad`. ESPN's final was seen at
// 22:30:05 CDT. Every tick after it logged `plan_end confirmed_final
// scopedOut:true` — `writeJobs = allowlisted && gate.armed` — and wrote no end
// job. The team colours stayed on the house for hours.
//
// THE RULE. The gate exists to stop a NEW show on a house whose base cannot be
// restored with certainty. It must never keep a show this system already
// started from ending. With `end_ignores_gate` on for the account:
//   - the END of a FIRED start is written while the account is allowlisted,
//     whatever the gate says, by every end path: confirmed final, the hard
//     cap, the status-aware cap and its ceiling;
//   - "fired" is GUARD 0b's test, unchanged: the start job (the team's own
//     `_start`, or the relinquisher's `_end` for a team lit by hand-off) is
//     `dispatched` or `completed`. A start that is `scheduled`, `cancelled`,
//     `expired`, `skipped`, `failed` or missing never commanded the controller,
//     so no end is written, as before;
//   - starts keep the gate exactly as before, and a hand-off (the survivor's
//     start) is refused under a blocking gate: the end restores base;
//   - an account that is no longer allowlisted, or `write_jobs:false`, still
//     gets no end (log-only), as before.
// With the flag absent every document is byte-identical to the planner as it
// was. All ids here are synthetic; the controller address is RFC 5737.

jest.mock("../../lib/espnClient", () => ({
  fetchTeamGame: jest.fn(async () => null),
  fetchEventById: jest.fn(async () => ({ kind: "error" })),
  fetchCollegeSlateGame: jest.fn(async () => ({ game: null, onSlate: false, complete: false })),
  fetchCollegeTeamDivision: jest.fn(async () => ({ kind: "error" })),
}));

const { logger } = require("firebase-functions");
const { fetchTeamGame } = require("../../lib/espnClient");
const { makeFakeFirestore } = require("./support/fakeFirestore");
const { snapshot } = require("./support/plannerScenario");
const { runPlannerTick } = require("../../lib/planGameDayFires");
const { startJobConfirmsFired } = require("../../lib/gameDayPlanning");

const SEC = 1000;
const MIN = 60 * SEC;
const H = 60 * MIN;
// An evening game: Sunday 2026-10-11, kickoff 19:15 CDT (00:15Z Monday). Its
// final comes after sunset (about 18:50 CDT at the test coordinates), so the
// base restore is base ON, preset 1.
const KICK = Date.parse("2026-10-12T00:15:00Z");
const FIRE = KICK - 30 * MIN; // 23:45:00Z
const T0 = FIRE - 5 * H - 45 * MIN; // 18:00Z, inside the 6 h horizon
const FINAL1 = KICK + 3 * H + 20 * MIN; // first tick ESPN says final
const FINAL2 = FINAL1 + 5 * MIN; // second: REQUIRED_FINAL_POLLS met
// A noon game: kickoff 12:00 CDT (17:00Z); its final is in daylight → preset 2.
const NOON_KICK = Date.parse("2026-10-11T17:00:00Z");

const UID = "u_endgate";
const OTHER = "u_someone_else";
const CTRL = "ctrl_endgate";
const TEAM = "nfl_endteam";
const ESPN = "23";
const GAME = "9600001";
const EVENT = `gd_${TEAM}_${GAME}`;
const LOWER = "mlb_lowerteam";
const LOWER_ESPN = "77";
const LOWER_GAME = "9600002";
const LOWER_EVENT = `gd_${LOWER}_${LOWER_GAME}`;

const ARMED = { forcePolicy: { enabled: true, allowlist: [UID] } };
const withFlags = (forceFlags) => ({ ...ARMED, forceFlags });
const FLAG = withFlags({ endIgnoresGate: true });
const NOT_ALLOWLISTED = { forcePolicy: { enabled: true, allowlist: [OTHER] }, forceFlags: { endIgnoresGate: true } };
const KILL_SWITCH = { forcePolicy: { enabled: false, allowlist: null }, forceFlags: { endIgnoresGate: true } };

const USER = `users/${UID}`;
const BEAT = `users/${UID}/bridge_status/current`;
const CONFIG = (slug = TEAM) => `users/${UID}/game_day_autopilot/${slug}`;
const CONTROLLER = `users/${UID}/controllers/${CTRL}`;
const JOB = (seq, event = EVENT) => `users/${UID}/fire_jobs/${event}_${seq}`;
const SESSION = (event = EVENT) => `users/${UID}/game_day_sessions/${event}`;
const DAYKEY = "2026-10-11"; // the game's LOCAL date (CDT)
const SCORE = (event = EVENT) => `gameday_scorecard/${DAYKEY}/entries/${UID}_${event}`;
const BASE_ON = '{"ps":1}';
const BASE_OFF = '{"ps":2}';

const controllerDoc = (f, over = {}) => ({
  ip: "192.0.2.40",
  participating_channels: [0, 1],
  participating_channels_device_ids: [0, 1],
  participating_channels_at: f.ts(T0 - 2 * 86_400_000),
  base_ladder_asserts_segments: true,
  ...over,
});

const teamConfig = (slug, espnId, sport = "nfl") => ({
  enabled: true, team_slug: slug, team_name: `Team ${slug}`, sport, espn_team_id: espnId,
  primary_color: 0xff102030, secondary_color: 0xff405060, effect_id: 52, speed: 160,
  intensity: 128, brightness: 200,
});

function world({ lower = false } = {}) {
  const f = makeFakeFirestore({ now: T0 - H });
  f.put(USER, {
    owner_id: UID, time_zone: "America/Chicago", latitude: 39.0, longitude: -95.0,
    ...(lower ? { game_day_team_priority: [TEAM, LOWER] } : {}),
  });
  f.put(CONTROLLER, controllerDoc(f));
  f.put(CONFIG(), teamConfig(TEAM, ESPN));
  if (lower) f.put(CONFIG(LOWER), teamConfig(LOWER, LOWER_ESPN, "mlb"));
  f.put(`bridge_registry/BR_${UID}`, { pairedUid: UID, status: "paired" });
  f.put(`users/${UID}/debug_errors/d1`, {
    context: "routing_decisions", app_version: "2.5.10+114", timestamp: f.ts(T0 - 2 * H),
  });
  return f;
}

/** ESPN for the main team; `games` may add other ids. */
function espn(state = "scheduled", { kick = KICK, games = {} } = {}) {
  const shape = (gameId, k, s, home) => ({
    gameId, startMs: k, homeTeamId: home, awayTeamId: "0",
    isFinal: s === "final", isInProgress: s === "live",
    statusName: s === "final" ? "STATUS_FINAL" : s === "live" ? "STATUS_IN_PROGRESS" : "STATUS_SCHEDULED",
  });
  fetchTeamGame.mockImplementation(async (_s, id) => {
    if (id === ESPN) return shape(GAME, kick, state, ESPN);
    const g = games[id];
    return g ? shape(g.gameId, g.kick, g.state, id) : null;
  });
}

/** The bridge lands a heartbeat at `ms`. */
function beat(f, ms) {
  const was = f.now();
  f.setNow(ms);
  f.put(BEAT, { uptime: 1, version: "1.2" });
  f.setNow(was);
}

/** A planner tick at `ms`, after a fresh heartbeat unless `stale`. */
async function tick(f, ms, opts = ARMED, { stale = false } = {}) {
  if (!stale) beat(f, ms - 20 * SEC);
  f.setNow(ms);
  return runPlannerTick(f.db, ms, opts);
}

const read = async (f, path) => (await f.db.doc(path).get()).data();
const rows = (r, action) => r.logRows.filter((x) => x.action === action);
const planEnd = (r, event = EVENT) => rows(r, "plan_end").find((x) => x.eventId === event);

/** The readiness gate flips: the base ladder no longer asserts every segment. */
function gateFlips(f) {
  f.put(CONTROLLER, controllerDoc(f, { base_ladder_asserts_segments: false }));
}

/** The dispatcher fired a job: its state as the bridge left it. */
const fired = (f, jobPath, state = "completed") => f.patch(jobPath, { state });

/** The P6 probe answered, as a healthy bridge would. */
async function completeProbes(f) {
  const q = await f.db.collection(`users/${UID}/commands`).where("source", "==", "gameday_preflight").get();
  for (const p of q.docs) f.patch(p.ref.path, { status: "completed" });
}

/** The incident's shape: mint, gate flips, the start fires, ESPN finals. */
async function incident(f, opts, { kick = KICK, final1 = FINAL1, startState = "completed" } = {}) {
  const t0 = kick - 30 * MIN - 5 * H - 45 * MIN; // inside the horizon for THIS game
  espn("scheduled", { kick });
  const mint = await tick(f, t0, opts);
  await completeProbes(f);
  expect(await read(f, JOB("start"))).toMatchObject({ state: "scheduled" });
  // The gate flips at the afternoon tick, before the start fires.
  gateFlips(f);
  const gated = await tick(f, t0 + 3 * H, opts);
  // The dispatcher fires the already-minted start, gate or no gate.
  fired(f, JOB("start"), startState);
  espn("final", { kick });
  const r1 = await tick(f, final1, opts);
  const r2 = await tick(f, final1 + 5 * MIN, opts);
  return { mint, gated, r1, r2 };
}

let warn;
beforeEach(() => {
  fetchTeamGame.mockReset();
  espn();
  warn = jest.spyOn(logger, "warn").mockImplementation(() => {});
});
afterEach(() => warn.mockRestore());

// ---------------------------------------------------------------------------
describe("the 2026-10-05 incident, replayed", () => {
  test("flag absent (pinned): the gate flips, the start fires, the final is confirmed, and NO end is written — scopedOut:true every tick", async () => {
    const f = world();
    const { gated, r1, r2 } = await incident(f, ARMED);
    expect(rows(gated, "gate").map((x) => x.reason)).toContain("gated_ladder_bad");
    expect((await read(f, USER)).gameday_gate_blocking).toEqual(["gated_ladder_bad"]);

    expect(planEnd(r1)).toBeUndefined(); // first final: not confirmed yet
    expect(planEnd(r2)).toMatchObject({ reason: "confirmed_final", scopedOut: true });
    expect(planEnd(r2)).not.toHaveProperty("gateBypassed");
    expect(await read(f, JOB("end"))).toBeUndefined();
    expect((await read(f, SESSION())).endFiredAt).toBeUndefined();
    expect(r2).not.toHaveProperty("endsGateBypassed");

    // …and it stays that way: the next tick logs the same and writes nothing.
    const r3 = await tick(f, FINAL2 + 5 * MIN, ARMED);
    expect(planEnd(r3)).toMatchObject({ reason: "confirmed_final", scopedOut: true });
    expect(await read(f, JOB("end"))).toBeUndefined();
  });

  test("end_ignores_gate on: the end IS written — the base restore, retry budget, session, scorecard, and the row says the gate was bypassed", async () => {
    const f = world();
    const { r2 } = await incident(f, FLAG);
    expect((await read(f, USER)).gameday_gate_blocking).toEqual(["gated_ladder_bad"]);

    const end = await read(f, JOB("end"));
    expect(end).toMatchObject({
      eventId: EVENT, seq: "end", controllerId: CTRL, type: "applyJson",
      payload: BASE_ON, state: "scheduled", source: "game_day",
    });
    expect(end.fireAt.toMillis()).toBe(FINAL2);
    // The end guarantee's budget (#179): 90 minutes, and the command is held
    // pickable for the whole of it.
    expect(end.retryUntil.toMillis()).toBe(FINAL2 + 90 * MIN);
    expect(end.holdUntil.toMillis()).toBe(FINAL2 + 90 * MIN);
    expect(end).not.toHaveProperty("handoffTo");

    const s = await read(f, SESSION());
    expect(s.endFiredAt.toMillis()).toBe(FINAL2);
    expect(s.consecutiveFinalPolls).toBe(2);

    expect(planEnd(r2)).toMatchObject({ reason: "confirmed_final", gateBypassed: true });
    expect(planEnd(r2)).not.toHaveProperty("scopedOut");
    expect(r2.endsPlanned).toBe(1);
    expect(r2.endsGateBypassed).toBe(1);

    const sc = await read(f, SCORE());
    expect(sc.end).toMatchObject({ job_id: `${EVENT}_end`, reason: "confirmed_final", state: "scheduled", gate_bypassed: true });
    expect(sc.end.espn_final_seen_at.toMillis()).toBe(FINAL1);

    // The gate is not touched, and the account is still not served: this is
    // an end, not a licence.
    expect((await read(f, USER)).gameday_server.served).toBe(false);

    // The next tick: already fired, nothing more.
    const r3 = await tick(f, FINAL2 + 5 * MIN, FLAG);
    expect(planEnd(r3)).toBeUndefined();
    expect(r3.endSkipped).toEqual({});
    expect(r3).not.toHaveProperty("endsGateBypassed");
  });

  test("the first final alone still does not end it: two consecutive finals, as before", async () => {
    const f = world();
    const { r1 } = await incident(f, FLAG);
    expect(r1.endsPlanned).toBe(0);
    expect(planEnd(r1)).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
describe("the caps bypass the gate the same way", () => {
  const BOUND = KICK + 3.5 * H + 60 * MIN; // start + estimatedDuration(nfl) + 60 min

  async function capped(f, opts, { espnState = "live", at = BOUND + MIN } = {}) {
    espn("scheduled");
    await tick(f, T0, opts);
    await completeProbes(f);
    gateFlips(f);
    fired(f, JOB("start"));
    espn(espnState);
    return tick(f, at, opts);
  }

  test("hard cap, flag absent: capped, logged, scopedOut — no job", async () => {
    const f = world();
    const r = await capped(f, ARMED);
    expect(planEnd(r)).toMatchObject({ reason: "hard_cap", scopedOut: true });
    expect(await read(f, JOB("end"))).toBeUndefined();
  });

  test("hard cap, flag on: the end is written with the base restore", async () => {
    const f = world();
    const r = await capped(f, FLAG);
    expect(planEnd(r)).toMatchObject({ reason: "hard_cap", gateBypassed: true });
    expect(await read(f, JOB("end"))).toMatchObject({ payload: BASE_ON, state: "scheduled" });
    expect(r.hardCapsPlanned).toBe(1);
    expect(r.endsGateBypassed).toBe(1);
  });

  test("a game ESPN still shows scheduled past the bound is capped too (the no-final case)", async () => {
    const f = world();
    const r = await capped(f, FLAG, { espnState: "scheduled" });
    expect(planEnd(r)).toMatchObject({ reason: "hard_cap", gateBypassed: true });
    expect(await read(f, JOB("end"))).toBeDefined();
  });

  test("status-aware cap: held while ESPN says live, then the ceiling ends it past the gate", async () => {
    const f = world();
    const opts = withFlags({ endIgnoresGate: true, statusAwareCap: true });
    const held = await capped(f, opts, { espnState: "live", at: BOUND + MIN });
    expect(rows(held, "skip").find((x) => x.reason === "cap_held_live")).toMatchObject({ eventId: EVENT });
    expect(await read(f, JOB("end"))).toBeUndefined();
    const CEILING = KICK + 6 * H; // football
    const r = await tick(f, CEILING + MIN, opts);
    expect(planEnd(r)).toMatchObject({ reason: "hard_cap_ceiling", gateBypassed: true });
    expect(await read(f, JOB("end"))).toMatchObject({ payload: BASE_ON });
    expect(r.hardCapsPlanned).toBe(1);
  });

  test("status-aware cap, flag absent: the ceiling is reached and still scopedOut", async () => {
    const f = world();
    const opts = withFlags({ statusAwareCap: true });
    await capped(f, opts, { espnState: "live", at: BOUND + MIN });
    const r = await tick(f, KICK + 6 * H + MIN, opts);
    expect(planEnd(r)).toMatchObject({ reason: "hard_cap_ceiling", scopedOut: true });
    expect(await read(f, JOB("end"))).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
describe("'fired' is GUARD 0b's definition: a start that never commanded the controller gets no end", () => {
  test("startJobConfirmsFired: exactly dispatched or completed", () => {
    expect(startJobConfirmsFired("dispatched")).toBe(true);
    expect(startJobConfirmsFired("completed")).toBe(true);
    for (const s of ["scheduled", "cancelled", "expired", "skipped", "failed", undefined, null, ""]) {
      expect(startJobConfirmsFired(s)).toBe(false);
    }
  });

  test("a start the bridge reported FAILED: flag on → the end is written (a partial apply is lit enough); flag absent → no end, as before", async () => {
    const on = world();
    const { r2 } = await incident(on, FLAG, { startState: "failed" });
    expect(await read(on, JOB("end"))).toMatchObject({ payload: BASE_ON });
    expect(planEnd(r2)).toMatchObject({ reason: "confirmed_final", gateBypassed: true });
    const off = world();
    const o = await incident(off, ARMED, { startState: "failed" });
    expect(await read(off, JOB("end"))).toBeUndefined();
    expect(o.r2.endSkipped).toEqual({ "end:start_never_dispatched": 1 });
  });

  test.each(["scheduled", "cancelled", "expired", "skipped"])(
    "start job %s + gate blocking + flag on: end_skipped_start_never_dispatched, no job",
    async (state) => {
      const f = world();
      const { r2 } = await incident(f, FLAG, { startState: state });
      expect(await read(f, JOB("end"))).toBeUndefined();
      expect(r2.endSkipped).toEqual({ "end:start_never_dispatched": 1 });
      expect(rows(r2, "skip").find((x) => x.reason === "end_skipped_start_never_dispatched")).toMatchObject({ startJobState: state });
      expect((await read(f, SESSION())).endFiredAt).toBeUndefined();
      expect(r2).not.toHaveProperty("endsGateBypassed");
    }
  );

  test("start job missing entirely: no end", async () => {
    const f = world();
    espn("scheduled");
    await tick(f, T0, FLAG);
    await f.db.doc(JOB("start")).delete();
    gateFlips(f);
    espn("final");
    await tick(f, FINAL1, FLAG);
    const r = await tick(f, FINAL2, FLAG);
    expect(rows(r, "skip").find((x) => x.reason === "end_skipped_start_never_dispatched")).toMatchObject({ startJobState: "missing" });
    expect(await read(f, JOB("end"))).toBeUndefined();
  });

  test("a start still dispatched (in flight) counts as fired: the end is written", async () => {
    const f = world();
    await incident(f, FLAG, { startState: "dispatched" });
    expect(await read(f, JOB("end"))).toMatchObject({ payload: BASE_ON });
  });

  test("a start still scheduled is unchanged: it keeps waiting, and no end is written for it", async () => {
    const f = world();
    espn("scheduled");
    await tick(f, T0, FLAG);
    gateFlips(f);
    const r = await tick(f, T0 + 3 * H, FLAG);
    expect(await read(f, JOB("start"))).toMatchObject({ state: "scheduled" });
    expect(r.skipped).toEqual({ start_already_planned: 1 });
    expect(await read(f, JOB("end"))).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
describe("the allowlist still decides: an account the policy no longer arms gets no end (defined)", () => {
  test("removed from uid_allowlist after the start fired: plan_end is logged scopedOut, no job, endFiredAt unset", async () => {
    const f = world();
    espn("scheduled");
    await tick(f, T0, FLAG);
    await completeProbes(f);
    gateFlips(f);
    fired(f, JOB("start"));
    espn("final");
    await tick(f, FINAL1, NOT_ALLOWLISTED);
    const r = await tick(f, FINAL2, NOT_ALLOWLISTED);
    expect(planEnd(r)).toMatchObject({ reason: "confirmed_final", scopedOut: true });
    expect(planEnd(r)).not.toHaveProperty("gateBypassed");
    expect(await read(f, JOB("end"))).toBeUndefined();
    expect((await read(f, SESSION())).endFiredAt).toBeUndefined();
    // Put back on the allowlist: the end follows on the next tick.
    const back = await tick(f, FINAL2 + 5 * MIN, FLAG);
    expect(planEnd(back)).toMatchObject({ reason: "confirmed_final", gateBypassed: true });
    expect(await read(f, JOB("end"))).toMatchObject({ payload: BASE_ON });
  });

  test("write_jobs off (the kill switch) after the start fired: no end, no scopedOut flag either (log-only era shape)", async () => {
    const f = world();
    espn("scheduled");
    await tick(f, T0, FLAG);
    await completeProbes(f);
    fired(f, JOB("start"));
    espn("final");
    await tick(f, FINAL1, KILL_SWITCH);
    const r = await tick(f, FINAL2, KILL_SWITCH);
    expect(planEnd(r)).toMatchObject({ reason: "confirmed_final" });
    expect(planEnd(r)).not.toHaveProperty("scopedOut");
    expect(await read(f, JOB("end"))).toBeUndefined();
  });

  test("the flag scoped to another account changes nothing for this one", async () => {
    const f = world();
    const { r2 } = await incident(f, withFlags({ endIgnoresGate: [OTHER] }));
    expect(planEnd(r2)).toMatchObject({ scopedOut: true });
    expect(await read(f, JOB("end"))).toBeUndefined();
    const g = world();
    await incident(g, withFlags({ endIgnoresGate: [UID] }));
    expect(await read(g, JOB("end"))).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
describe("served false and pre-flight failing: the end is still written", () => {
  test("stale bridge + gated ladder at the final: preflight names both, served is false, and the end job exists", async () => {
    const f = world();
    espn("scheduled");
    await tick(f, T0, FLAG);
    await completeProbes(f);
    gateFlips(f);
    fired(f, JOB("start"));
    espn("final");
    beat(f, FINAL1 - 30 * MIN); // the bridge's last word, long before
    await tick(f, FINAL1, FLAG, { stale: true });
    const r = await tick(f, FINAL2, FLAG, { stale: true });
    const gs = (await read(f, USER)).gameday_server;
    expect(gs.served).toBe(false);
    expect(gs.preflight.reasons).toEqual(["preflight_bridge_stale", "preflight_ladder_bad", "preflight_gated"]);
    expect(await read(f, JOB("end"))).toMatchObject({ payload: BASE_ON });
    expect(planEnd(r)).toMatchObject({ gateBypassed: true });
  });
});

// ---------------------------------------------------------------------------
describe("starts stay gated exactly as before", () => {
  test("gate blocking + flag on: a new start is NOT minted (scopedOut), while the fired show's end is", async () => {
    const f = world({ lower: true });
    // The main team's game starts and fires; the lower team's game is tomorrow.
    espn("scheduled", { games: { [LOWER_ESPN]: { gameId: LOWER_GAME, kick: KICK + 20 * H, state: "scheduled" } } });
    await tick(f, T0, FLAG);
    await completeProbes(f);
    gateFlips(f);
    fired(f, JOB("start"));
    espn("final", { games: { [LOWER_ESPN]: { gameId: LOWER_GAME, kick: KICK + 20 * H, state: "scheduled" } } });
    await tick(f, FINAL1, FLAG);
    const r = await tick(f, FINAL2, FLAG);
    expect(await read(f, JOB("end"))).toBeDefined();
    // The lower team's start is now inside the horizon and would mint — the gate says no.
    const later = await tick(f, KICK + 20 * H - 30 * MIN - 5 * H, FLAG);
    expect(rows(later, "plan_start").find((x) => x.eventId === LOWER_EVENT)).toMatchObject({ scopedOut: true });
    expect(await read(f, JOB("start", LOWER_EVENT))).toBeUndefined();
    void r;
  });

  test("pre-flight failing (stale bridge), gate armed, flag on: a new start is withheld, as before", async () => {
    const f = world();
    espn("scheduled");
    beat(f, T0 - 10 * MIN);
    const r = await tick(f, T0, FLAG, { stale: true });
    expect(await read(f, JOB("start"))).toBeUndefined();
    expect(r.preflightSkips).toBe(1);
  });
});

// ---------------------------------------------------------------------------
describe("hand-off under a blocking gate: the survivor's start is refused, the end restores base", () => {
  const LOWER_KICK = KICK - 15 * MIN; // the lower team's game starts first (fire 23:30Z); the owner's at 23:45Z
  const games = (state, lowerState) => ({
    [LOWER_ESPN]: { gameId: LOWER_GAME, kick: LOWER_KICK, state: lowerState },
    ...(state ? {} : {}),
  });
  const SLOT = (ms) => ms; // readability

  async function bothLit(f, opts) {
    espn("scheduled", { games: games(null, "scheduled") });
    await tick(f, SLOT(LOWER_KICK - 30 * MIN - 5 * H), opts); // both inside the horizon: lower mints, owner mints
    await completeProbes(f);
    expect(await read(f, JOB("start", LOWER_EVENT))).toMatchObject({ state: "scheduled" });
    expect(await read(f, JOB("start"))).toMatchObject({ state: "scheduled" });
    fired(f, JOB("start", LOWER_EVENT));
    fired(f, JOB("start"));
  }

  test("gate ARMED (control): the owner's final hands the house to the still-live lower team", async () => {
    const f = world({ lower: true });
    await bothLit(f, FLAG);
    espn("final", { games: games(null, "live") });
    await tick(f, FINAL1, FLAG);
    const r = await tick(f, FINAL2, FLAG);
    const end = await read(f, JOB("end"));
    expect(end.handoffTo).toBe(LOWER_EVENT);
    expect(end.payload).toContain('"fx":52');
    expect(planEnd(r)).toMatchObject({ handoffTo: LOWER });
    expect(planEnd(r)).not.toHaveProperty("gateBypassed");
    expect(r.handoffsPlanned).toBe(1);
  });

  test("gate BLOCKING + flag on: the end is written as the base restore, the hand-off is refused and named", async () => {
    const f = world({ lower: true });
    await bothLit(f, FLAG);
    gateFlips(f);
    espn("final", { games: games(null, "live") });
    await tick(f, FINAL1, FLAG);
    const r = await tick(f, FINAL2, FLAG);
    const end = await read(f, JOB("end"));
    expect(end.payload).toBe(BASE_ON);
    expect(end).not.toHaveProperty("handoffTo");
    expect(planEnd(r)).toMatchObject({ reason: "confirmed_final", gateBypassed: true });
    expect(planEnd(r)).not.toHaveProperty("handoffTo");
    expect(rows(r, "skip").find((x) => x.reason === "handoff_refused:gate_blocking")).toMatchObject({ eventId: EVENT, handoffTo: LOWER });
    expect(r.handoffsPlanned).toBe(0);
    expect(r.endsGateBypassed).toBe(1);
    expect((await read(f, SESSION(LOWER_EVENT)))).not.toHaveProperty("handedOffFrom");
  });

  test("gate BLOCKING, flag absent: scopedOut, no job, and the hand-off row is what it always was", async () => {
    const f = world({ lower: true });
    await bothLit(f, ARMED);
    gateFlips(f);
    espn("final", { games: games(null, "live") });
    await tick(f, FINAL1, ARMED);
    const r = await tick(f, FINAL2, ARMED);
    expect(planEnd(r)).toMatchObject({ scopedOut: true, handoffTo: LOWER });
    expect(rows(r, "skip").find((x) => x.reason === "handoff_refused:gate_blocking")).toBeUndefined();
    expect(await read(f, JOB("end"))).toBeUndefined();
  });

  test("a team lit by hand-off (its start is the relinquisher's end job) ends past a later gate flip", async () => {
    // The lower team's game starts AFTER the owner's (fire 00:00Z, the owner's
    // 23:45Z), so its own start is DEFERRED and it is lit only by the hand-off.
    const LATE_KICK = KICK + 15 * MIN;
    const late = (state) => ({ [LOWER_ESPN]: { gameId: LOWER_GAME, kick: LATE_KICK, state } });
    const f = world({ lower: true });
    espn("scheduled", { games: late("scheduled") });
    await tick(f, T0, FLAG); // the owner mints
    await tick(f, T0 + 5 * MIN, FLAG); // the lower team enters the horizon: deferred
    await completeProbes(f);
    expect(await read(f, JOB("start"))).toMatchObject({ state: "scheduled" });
    expect(await read(f, JOB("start", LOWER_EVENT))).toBeUndefined();
    fired(f, JOB("start"));
    espn("final", { games: late("live") });
    await tick(f, FINAL1, FLAG);
    const h = await tick(f, FINAL2, FLAG); // the owner's end hands off
    expect(planEnd(h)).toMatchObject({ handoffTo: LOWER });
    expect((await read(f, JOB("end"))).handoffTo).toBe(LOWER_EVENT);
    fired(f, JOB("end")); // the dispatcher lit the lower team's design
    const ls = await read(f, SESSION(LOWER_EVENT));
    expect(ls.startJobId).toBe(`${EVENT}_end`);
    expect(ls.startPlannedAt).toBeDefined();

    gateFlips(f);
    espn("final", { games: late("final") });
    const L1 = FINAL2 + 40 * MIN;
    await tick(f, L1, FLAG);
    const r = await tick(f, L1 + 5 * MIN, FLAG);
    expect(planEnd(r, LOWER_EVENT)).toMatchObject({ reason: "confirmed_final", gateBypassed: true });
    expect(await read(f, JOB("end", LOWER_EVENT))).toMatchObject({ payload: BASE_ON });
    expect(r.endsGateBypassed).toBe(1);
  });
});

// ---------------------------------------------------------------------------
describe("the restore payload is unchanged by the bypass: base ON after sunset, base OFF in daylight", () => {
  test("evening game → {ps:1}", async () => {
    const f = world();
    await incident(f, FLAG);
    expect((await read(f, JOB("end"))).payload).toBe(BASE_ON);
  });

  test("noon game → {ps:2}", async () => {
    const f = world();
    const NOON_FINAL1 = NOON_KICK + 3 * H + 20 * MIN; // 15:20 CDT, daylight
    await incident(f, FLAG, { kick: NOON_KICK, final1: NOON_FINAL1 });
    expect((await read(f, JOB("end"))).payload).toBe(BASE_OFF);
  });
});

// ---------------------------------------------------------------------------
describe("flag absent = the planner as it was", () => {
  test("gate ARMED throughout: flags off vs on, every document identical through start, final and end", async () => {
    async function run(opts) {
      const f = world();
      espn("scheduled");
      await tick(f, T0, opts);
      await completeProbes(f);
      fired(f, JOB("start"));
      espn("final");
      await tick(f, FINAL1, opts);
      await tick(f, FINAL2, opts);
      return snapshot(f);
    }
    const off = await run(ARMED);
    const on = await run(FLAG);
    // With the gate armed the flag changes exactly three things, all additive
    // and all on the end it wrote: the longer retry budget, the command hold,
    // and the session's pointer to its end job. Nothing else moves.
    const endPath = JOB("end");
    const sessionPath = SESSION();
    const strip = (snap) => {
      const out = JSON.parse(JSON.stringify(snap));
      delete out[endPath].retryUntil;
      delete out[endPath].holdUntil;
      delete out[sessionPath].endJobId;
      for (const p of Object.keys(out)) {
        if (p.startsWith("gameday_scorecard/") && out[p].end) delete out[p].end.retry_until;
      }
      return out;
    };
    expect(strip(on)).toEqual(strip(off));
    expect(on[endPath].retryUntil).toEqual({ __ts: FINAL2 + 90 * MIN });
    expect(on[endPath].holdUntil).toEqual({ __ts: FINAL2 + 90 * MIN });
    expect(off[endPath].retryUntil).toEqual({ __ts: FINAL2 + 15 * MIN });
    expect(off[endPath]).not.toHaveProperty("holdUntil");
    expect(on[sessionPath].endJobId).toBe(`${EVENT}_end`);
    expect(off[sessionPath]).not.toHaveProperty("endJobId");
    expect(JSON.stringify(on)).not.toContain("gateBypassed");
    expect(JSON.stringify(on)).not.toContain("endsGateBypassed");
    expect(JSON.stringify(on)).not.toContain("session_sweep");
    expect(JSON.stringify(on)).toContain('"end"'); // the end was written on both runs
  });
});

// ---------------------------------------------------------------------------
describe("the production read: config/gameday_planner.end_ignores_gate", () => {
  const ARM = { write_jobs: true, uid_allowlist: [UID] };

  async function incidentWithConfig(config) {
    const f = world();
    f.put("config/gameday_planner", { ...ARM, ...config });
    const run = async (ms) => { beat(f, ms - 20 * SEC); f.setNow(ms); return runPlannerTick(f.db, ms); };
    espn("scheduled");
    await run(T0);
    await completeProbes(f);
    gateFlips(f);
    fired(f, JOB("start"));
    espn("final");
    await run(FINAL1);
    const r = await run(FINAL2);
    return { f, r, end: await read(f, JOB("end")) };
  }

  test("absent: no end, no warning", async () => {
    const { r, end } = await incidentWithConfig({});
    expect(end).toBeUndefined();
    expect(planEnd(r)).toMatchObject({ scopedOut: true });
    expect(warn).not.toHaveBeenCalled();
  });

  test("[uid] and true: the end is written", async () => {
    for (const v of [[UID], true]) {
      const { r, end } = await incidentWithConfig({ end_ignores_gate: v });
      expect(end).toMatchObject({ payload: BASE_ON });
      expect(r.endsGateBypassed).toBe(1);
    }
  });

  test("a list naming only another account: nothing, and no warning", async () => {
    const { end } = await incidentWithConfig({ end_ignores_gate: [OTHER] });
    expect(end).toBeUndefined();
    expect(warn).not.toHaveBeenCalled();
  });

  test("malformed: off, and logged", async () => {
    for (const v of ["true", 1, [UID, 7], { [UID]: true }]) {
      warn.mockClear();
      const { end } = await incidentWithConfig({ end_ignores_gate: v });
      expect(end).toBeUndefined();
      expect(warn.mock.calls.some((c) => String(c[0]).includes("config/gameday_planner.end_ignores_gate is malformed"))).toBe(true);
    }
  });
});
