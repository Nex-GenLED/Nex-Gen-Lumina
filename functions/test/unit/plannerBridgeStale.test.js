// planGameDayFires × the bridge write gap (2026-10-05) — the REAL planner tick
// on the shared in-memory Firestore. Every outcome is read back with a plain
// .get() on the production path.
//
// THE FIELD FACT. A firmware-1.2 bridge stops landing Firestore writes for
// about ten minutes at a time, a few times a day, without rebooting. P2 wants
// a heartbeat under 5 minutes old, so each gap fails one or two planner ticks.
// Before this change each of those ticks published `served:false, teams:[]`,
// and an app (builds 114/115) open on the home network during them read "not
// served" and armed its own lease for a game the server was about to run.
//
//   A   `preflight_bridge_grace`  P2's window: 5 min → 15 min
//   B2  `served_sticky`           `served` rides through < 30 min of P2 failure
//
// Times: Sunday 2026-10-11, kickoff 12:00 CDT (17:00Z), lead 30 → fire 16:30Z.
// The 6 h planning horizon opens at 10:30:00Z. All ids are synthetic; the
// controller address is documentation-range (RFC 5737).

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

const SEC = 1000;
const MIN = 60 * SEC;
const H = 60 * MIN;
const KICK = Date.parse("2026-10-11T17:00:00Z");
const FIRE = KICK - 30 * MIN; // 16:30:00Z
const OPEN = FIRE - 6 * H; // 10:30:00Z — the first instant a start may be minted is just after this
const UID = "u_gap";
const OTHER = "u_someone_else";
const CTRL = "ctrl_gap";
const TEAM = "nfl_gapteam";
const ESPN = "22";
const GAME = "9400001";
const EVENT = `gd_${TEAM}_${GAME}`;
const DAYKEY = "2026-10-11";
const STALE = "preflight_bridge_stale";

const ARMED = { forcePolicy: { enabled: true, allowlist: [UID] } };
const withFlags = (forceFlags) => ({ ...ARMED, forceFlags });
const STICKY = withFlags({ servedSticky: true });
const GRACE = withFlags({ preflightBridgeGrace: true });
const BOTH = withFlags({ servedSticky: true, preflightBridgeGrace: true });

const USER = `users/${UID}`;
const BEAT = `users/${UID}/bridge_status/current`;
const CONFIG = `users/${UID}/game_day_autopilot/${TEAM}`;
const CONTROLLER = `users/${UID}/controllers/${CTRL}`;
const JOB = (seq) => `users/${UID}/fire_jobs/${EVENT}_${seq}`;
const SCORE = `gameday_scorecard/${DAYKEY}/entries/${UID}_${EVENT}`;
const iso = (ms) => new Date(ms).toISOString();

const controllerDoc = (f, over = {}) => ({
  ip: "192.0.2.30",
  participating_channels: [0, 1],
  participating_channels_device_ids: [0, 1],
  participating_channels_at: f.ts(OPEN - 2 * 86_400_000),
  base_ladder_asserts_segments: true,
  ...over,
});

function world() {
  const f = makeFakeFirestore({ now: OPEN - H });
  f.put(USER, { owner_id: UID, time_zone: "America/Chicago", latitude: 39.0, longitude: -95.0 });
  f.put(CONTROLLER, controllerDoc(f));
  f.put(CONFIG, {
    enabled: true, team_slug: TEAM, team_name: "Gap Team", sport: "nfl", espn_team_id: ESPN,
    primary_color: 0xff102030, secondary_color: 0xff405060, effect_id: 52, speed: 160,
    intensity: 128, brightness: 200,
  });
  f.put(`bridge_registry/BR_${UID}`, { pairedUid: UID, status: "paired" });
  // A current app build, so pre-flight's informational list stays empty.
  f.put(`users/${UID}/debug_errors/d1`, {
    context: "routing_decisions", app_version: "2.5.10+114", timestamp: f.ts(OPEN - 2 * H),
  });
  return f;
}

function espn(state = "scheduled", kick = KICK) {
  fetchTeamGame.mockImplementation(async (_s, id) =>
    id === ESPN
      ? {
          gameId: GAME, startMs: kick, homeTeamId: ESPN, awayTeamId: "0",
          isFinal: state === "final", isInProgress: state === "live",
          statusName: state === "final" ? "STATUS_FINAL" : state === "live" ? "STATUS_IN_PROGRESS" : "STATUS_SCHEDULED",
        }
      : null
  );
}

/** The bridge lands a heartbeat at `ms` (the document's server updateTime). */
function beat(f, ms) {
  const was = f.now();
  f.setNow(ms);
  f.put(BEAT, { uptime: 1, version: "1.2" });
  f.setNow(was);
}

async function tick(f, ms, opts = ARMED) {
  f.setNow(ms);
  return runPlannerTick(f.db, ms, opts);
}

const read = async (f, path) => (await f.db.doc(path).get()).data();
const server = async (f) => (await read(f, USER)).gameday_server;
const rows = (r, action) => r.logRows.filter((x) => x.action === action);
const probes = async (f) =>
  (await f.db.collection(`users/${UID}/commands`).where("source", "==", "gameday_preflight").get()).docs;

/** The P6 probe answered, as a healthy bridge would: nothing else may fail pre-flight. */
async function completeProbes(f) {
  for (const p of await probes(f)) f.patch(p.ref.path, { status: "completed" });
}

/**
 * The app's own rule, restated (game_day_server_status.dart, `servesTeamAt`,
 * builds 114 and 115): served, the planner's `checked_at` no older than
 * 30 minutes, and the team listed. False = the phone runs Game Day itself and,
 * on the home network, arms its lease.
 */
function appServesTeam(gs, nowMs, team = TEAM) {
  if (!gs || gs.served !== true || !gs.checked_at) return false;
  if (nowMs - gs.checked_at.toMillis() > 30 * MIN) return false;
  return Array.isArray(gs.teams) && gs.teams.includes(team);
}

// A ~10.5-minute gap straddling the moment the horizon opens. Last heartbeat
// 10:25:00Z; the bridge is silent until 10:35:30Z. Planner ticks at :20 s.
const GAP = {
  lastBeat: OPEN - 5 * MIN, // 10:25:00
  tA: OPEN - 5 * MIN + 20 * SEC, // 10:25:20  fresh (20 s)   — before the horizon
  tB: OPEN + 20 * SEC, // 10:30:20  stale (5:20)   — the start is due to be minted
  tC: OPEN + 5 * MIN + 20 * SEC, // 10:35:20  stale (10:20)
  resumes: OPEN + 10 * MIN, // 10:40:00  heartbeats again (the tick sees 20 s)
  tD: OPEN + 10 * MIN + 20 * SEC, // 10:40:20  fresh
};

/** Run the gap; return what was published and what the app would read, tick by tick. */
async function runGap(f, opts) {
  const out = {};
  beat(f, GAP.lastBeat);
  for (const k of ["tA", "tB", "tC"]) {
    const r = await tick(f, GAP[k], opts);
    const gs = await server(f);
    out[k] = { r, gs, app: appServesTeam(gs, GAP[k]), job: await read(f, JOB("start")) };
  }
  beat(f, GAP.resumes);
  const r = await tick(f, GAP.tD, opts);
  const gs = await server(f);
  out.tD = { r, gs, app: appServesTeam(gs, GAP.tD), job: await read(f, JOB("start")) };
  return out;
}

let warn;
beforeEach(() => {
  fetchTeamGame.mockReset();
  espn();
  warn = jest.spyOn(logger, "warn").mockImplementation(() => {});
});
afterEach(() => warn.mockRestore());

// ---------------------------------------------------------------------------
describe("flags absent — the planner as it was (the defect, pinned)", () => {
  test("a ten-minute write gap publishes served:false, and the app reads 'not served' until the bridge writes again", async () => {
    const f = world();
    const g = await runGap(f, ARMED);

    expect(g.tA.gs).toMatchObject({ served: true, teams: [TEAM] });
    expect(g.tA.app).toBe(true);

    // The first stale tick: exactly what A+B shipped.
    expect(g.tB.gs).toMatchObject({
      served: false, teams: [], next_fire: null,
      preflight: { ok: false, reasons: [STALE], info: [], mode: "enforce" },
    });
    expect(g.tB.gs.checked_at.toMillis()).toBe(GAP.tB);
    expect(g.tB.gs).not.toHaveProperty("stale_since");
    expect(g.tB.app).toBe(false);
    expect(g.tB.job).toBeUndefined();

    // The second: nothing changed, so nothing is written (on-change).
    expect(g.tC.gs.checked_at.toMillis()).toBe(GAP.tB);
    expect(g.tC.app).toBe(false);

    // Recovery.
    expect(g.tD.gs).toMatchObject({ served: true, teams: [TEAM] });
    expect(g.tD.app).toBe(true);
    expect(g.tD.job.fireAt.toMillis()).toBe(FIRE);

    for (const k of ["tA", "tB", "tC", "tD"]) {
      expect(g[k].r).not.toHaveProperty("servedHeld");
      expect(rows(g[k].r, "served_held")).toEqual([]);
      expect(rows(g[k].r, "served_hold_expired")).toEqual([]);
    }
    expect(g.tD.gs).not.toHaveProperty("stale_since");
  });

  test("an explicit false, an empty list and a list naming another account are all OFF", async () => {
    for (const forceFlags of [
      { servedSticky: false, preflightBridgeGrace: false },
      { servedSticky: [], preflightBridgeGrace: [] },
      { servedSticky: [OTHER], preflightBridgeGrace: [OTHER] },
    ]) {
      const g = await runGap(world(), withFlags(forceFlags));
      expect(g.tB.gs.served).toBe(false);
      expect(g.tB.gs).not.toHaveProperty("stale_since");
      expect(g.tB.gs.preflight.reasons).toEqual([STALE]);
    }
  });
});

// ---------------------------------------------------------------------------
describe("B2 — served_sticky: a ten-minute gap never flips served", () => {
  test("served, teams and a fresh checked_at on every tick; the real reasons in preflight; no start on a stale tick; the start mints on the first good tick, on time", async () => {
    const f = world();
    const g = await runGap(f, STICKY);

    // Before the gap.
    expect(g.tA.gs).toMatchObject({ served: true, teams: [TEAM], preflight: { ok: true, reasons: [] } });
    expect(g.tA.gs).not.toHaveProperty("stale_since");

    // Both stale ticks: HELD.
    for (const k of ["tB", "tC"]) {
      const { r, gs, job } = g[k];
      expect(gs.served).toBe(true);
      expect(gs.teams).toEqual([TEAM]);
      expect(gs.checked_at.toMillis()).toBe(GAP[k]); // the app's heartbeat keeps moving
      expect(gs.preflight).toMatchObject({ ok: false, reasons: [STALE], info: [], mode: "enforce" });
      expect(gs.preflight.at.toMillis()).toBe(GAP[k]);
      expect(gs.stale_since.toMillis()).toBe(GAP.tB); // set once, carried
      expect(gs.next_fire).toBeNull(); // nothing is scheduled: no start was minted

      // Nothing minted — pre-flight still withholds the start. (Nothing probed
      // either: exactly one probe exists after the whole run, asserted below,
      // and it is written in the tick that mints.)
      expect(job).toBeUndefined();
      expect(r.p6Probes).toBe(0);
      expect(r.preflightSkips).toBe(1);
      expect(rows(r, "preflight_skip")).toEqual([{ uid: UID, action: "preflight_skip", reasons: [STALE] }]);
      expect(r.logRows.find((x) => x.action === "plan_start")).toMatchObject({ preflightSkipped: true });

      // …and the hold is on the record.
      expect(r.servedHeld).toBe(1);
      expect(rows(r, "served_held")).toEqual([
        { uid: UID, action: "served_held", reason: STALE, staleSince: iso(GAP.tB) },
      ]);
    }
    // (The scorecard's skipped-start entry during the gap has its own test below.)

    // The first good tick: minted, with the fire time it always had.
    expect(g.tD.job).toMatchObject({ seq: "start", state: "scheduled" });
    expect(g.tD.job.fireAt.toMillis()).toBe(FIRE);
    expect(g.tD.job.retryUntil.toMillis()).toBe(KICK);
    expect(g.tD.gs).toMatchObject({
      served: true, teams: [TEAM], preflight: { ok: true, reasons: [] },
      next_fire: { event_id: EVENT, seq: "start" },
    });
    expect(g.tD.gs.checked_at.toMillis()).toBe(GAP.tD);
    expect(g.tD.gs).not.toHaveProperty("stale_since"); // the run ended
    expect(g.tD.r).not.toHaveProperty("servedHeld");
    expect((await read(f, SCORE)).served).toBe(true);
    expect(await probes(f)).toHaveLength(1);

    // What the app reads: served on every tick, and at every minute between.
    expect([g.tA.app, g.tB.app, g.tC.app, g.tD.app]).toEqual([true, true, true, true]);
  });

  test("the app's view, minute by minute across the gap: before = not served for ten minutes; after = served throughout", async () => {
    async function timeline(opts) {
      const f = world();
      beat(f, GAP.lastBeat);
      const seen = [];
      const at = async (ms) => seen.push(appServesTeam(await server(f), ms));
      await tick(f, GAP.tA, opts);
      for (let m = 0; m < 5; m++) await at(GAP.tA + m * MIN);
      await tick(f, GAP.tB, opts);
      for (let m = 0; m < 5; m++) await at(GAP.tB + m * MIN);
      await tick(f, GAP.tC, opts);
      for (let m = 0; m < 5; m++) await at(GAP.tC + m * MIN);
      beat(f, GAP.resumes);
      await tick(f, GAP.tD, opts);
      for (let m = 0; m < 5; m++) await at(GAP.tD + m * MIN);
      return seen.map((s) => (s ? "S" : "-")).join("");
    }
    //                       10:25  10:30  10:35  10:40   (five one-minute reads each)
    expect(await timeline(ARMED)).toBe("SSSSS" + "-----" + "-----" + "SSSSS");
    expect(await timeline(STICKY)).toBe("SSSSS" + "SSSSS" + "SSSSS" + "SSSSS");
  });

  test("the withheld start is still on the scorecard as skipped, with its reason, while it is withheld", async () => {
    const f = world();
    beat(f, GAP.lastBeat);
    await tick(f, GAP.tA, STICKY);
    await tick(f, GAP.tB, STICKY);
    expect(await read(f, SCORE)).toMatchObject({
      served: false, preflight_ok: false, preflight_reasons: [STALE], start: null,
    });
    // The account-level statement and the event-level one are different facts:
    // the account is still served; this tick did not mint this start.
    expect((await server(f)).served).toBe(true);
  });

  test("a single stale tick (the common case) is held the same way", async () => {
    const f = world();
    beat(f, GAP.lastBeat);
    await tick(f, GAP.tA, STICKY);
    await tick(f, GAP.tB, STICKY);
    expect(await server(f)).toMatchObject({ served: true, teams: [TEAM] });
    beat(f, GAP.tC - 20 * SEC);
    const r = await tick(f, GAP.tC, STICKY);
    const gs = await server(f);
    expect(gs).toMatchObject({ served: true, preflight: { ok: true } });
    expect(gs).not.toHaveProperty("stale_since");
    expect(r).not.toHaveProperty("servedHeld");
    expect((await read(f, JOB("start"))).fireAt.toMillis()).toBe(FIRE);
  });

  test("the hold is scoped: a uid list naming this account holds; a list naming another does not", async () => {
    const held = await runGap(world(), withFlags({ servedSticky: [UID] }));
    expect(held.tB.gs.served).toBe(true);
    const notHeld = await runGap(world(), withFlags({ servedSticky: [OTHER] }));
    expect(notHeld.tB.gs.served).toBe(false);
  });
});

// ---------------------------------------------------------------------------
describe("B2 — a held tick never mints, and a start is never minted late", () => {
  // The game reaches ESPN only once the gap has begun, with its fire time
  // INSIDE the gap: kickoff 17:00Z, fire 16:30:00Z; last heartbeat 16:20:00Z.
  const L = {
    lastBeat: FIRE - 10 * MIN, // 16:20:00
    tA: FIRE - 10 * MIN + 20 * SEC, // 16:20:20  fresh; ESPN has no game yet
    tB: FIRE - 5 * MIN + 20 * SEC, // 16:25:20  stale; the game appears, fire in 4:40
    tC: FIRE + 20 * SEC, // 16:30:20  stale; fire time just passed
    resumes: FIRE + 5 * MIN, // 16:35:00
    tD: FIRE + 5 * MIN + 20 * SEC, // 16:35:20  fresh; fire time 5:20 ago
  };

  test.each([["flags absent", ARMED], ["served_sticky on", STICKY]])(
    "%s: no start on the stale ticks, and none after the fire time has passed",
    async (_name, opts) => {
      const f = world();
      fetchTeamGame.mockImplementation(async () => null);
      beat(f, L.lastBeat);
      const a = await tick(f, L.tA, opts);
      expect(a.skipped).toEqual({ no_game: 1 });
      expect(await server(f)).toMatchObject({ served: true, teams: [TEAM] });

      espn();
      await tick(f, L.tB, opts);
      expect(await read(f, JOB("start"))).toBeUndefined();
      await tick(f, L.tC, opts);
      expect(await read(f, JOB("start"))).toBeUndefined();

      beat(f, L.resumes);
      const d = await tick(f, L.tD, opts);
      // NOT minted late: the fire time is behind us, and that is the answer.
      expect(await read(f, JOB("start"))).toBeUndefined();
      expect(d.skipped).toEqual({ start_time_passed: 1 });
      expect(rows(d, "skip").find((x) => x.reason === "start_time_passed")).toMatchObject({ teamSlug: TEAM, eventId: EVENT });
      expect(await probes(f)).toHaveLength(0);
      expect((await server(f)).served).toBe(true);
    }
  );

  test("the two differ only in what was PUBLISHED during the gap (debt: the held case leaves this start to nobody)", async () => {
    async function published(opts) {
      const f = world();
      fetchTeamGame.mockImplementation(async () => null);
      beat(f, L.lastBeat);
      await tick(f, L.tA, opts);
      espn();
      await tick(f, L.tB, opts);
      const atB = (await server(f)).served;
      await tick(f, L.tC, opts);
      return [atB, (await server(f)).served];
    }
    expect(await published(ARMED)).toEqual([false, false]);
    expect(await published(STICKY)).toEqual([true, true]);
  });
});

// ---------------------------------------------------------------------------
describe("B2 — a bridge stale past 30 minutes: served follows, with the reasons", () => {
  const T0 = OPEN + 90 * MIN + 20 * SEC; // 12:00:20 — inside the horizon
  const S = T0 + 5 * MIN; // the first tick P2 fails (heartbeat 5:20 old)

  async function staleRun(f, opts) {
    beat(f, T0 - 20 * SEC);
    await tick(f, T0, opts); // mints the start; served
    await completeProbes(f);
    const held = [];
    for (let i = 0; i <= 5; i++) {
      const at = S + i * 5 * MIN; // S … S+25 min
      const r = await tick(f, at, opts);
      held.push({ at, r, gs: await server(f) });
    }
    return held;
  }

  test("held for six ticks (S … S+25 min), then at 31 minutes: served false, teams empty, the reason published", async () => {
    const f = world();
    const held = await staleRun(f, STICKY);
    for (const { at, r, gs } of held) {
      expect(gs).toMatchObject({ served: true, teams: [TEAM], preflight: { ok: false, reasons: [STALE] } });
      expect(gs.checked_at.toMillis()).toBe(at);
      expect(gs.stale_since.toMillis()).toBe(S);
      // The start minted before the gap is still the next fire, untouched.
      expect(gs.next_fire).toMatchObject({ event_id: EVENT, seq: "start" });
      expect(r.servedHeld).toBe(1);
      expect(appServesTeam(gs, at)).toBe(true);
    }

    const flipAt = S + 31 * MIN;
    const r = await tick(f, flipAt, STICKY);
    const gs = await server(f);
    expect(gs).toMatchObject({
      served: false, teams: [], next_fire: null,
      preflight: { ok: false, reasons: [STALE], info: [], mode: "enforce" },
    });
    expect(gs.checked_at.toMillis()).toBe(flipAt);
    expect(gs.stale_since.toMillis()).toBe(S); // when the run began stays on the record
    expect(appServesTeam(gs, flipAt)).toBe(false);
    expect(r).not.toHaveProperty("servedHeld");
    expect(rows(r, "served_held")).toEqual([]);
    expect(rows(r, "served_hold_expired")).toEqual([
      { uid: UID, action: "served_hold_expired", reason: STALE, staleSince: iso(S) },
    ]);
    expect(r.preflightSkips).toBe(1);

    // The start minted before the gap is a job, not a published opinion: it stands.
    expect(await read(f, JOB("start"))).toMatchObject({ state: "scheduled" });

    // The next stale tick: nothing changed, nothing written, no second expiry.
    const r2 = await tick(f, flipAt + 5 * MIN, STICKY);
    const gs2 = await server(f);
    expect(gs2.served).toBe(false);
    expect(gs2.checked_at.toMillis()).toBe(flipAt);
    expect(rows(r2, "served_hold_expired")).toEqual([]);
  });

  test("the hold ends at 30 minutes of failing ticks, not before: S+25 holds, S+30 flips", async () => {
    const f = world();
    const held = await staleRun(f, STICKY);
    expect(held[5].at).toBe(S + 25 * MIN);
    expect(held[5].gs.served).toBe(true);
    await tick(f, S + 30 * MIN, STICKY);
    expect((await server(f)).served).toBe(false);
  });

  test("recovery: the first good tick flips served back, restores the teams and clears the run", async () => {
    const f = world();
    await staleRun(f, STICKY);
    await tick(f, S + 31 * MIN, STICKY);
    expect((await server(f)).served).toBe(false);

    const back = S + 36 * MIN;
    beat(f, back - 20 * SEC);
    const r = await tick(f, back, STICKY);
    const gs = await server(f);
    expect(gs).toMatchObject({
      served: true, teams: [TEAM], preflight: { ok: true, reasons: [] },
      next_fire: { event_id: EVENT, seq: "start" },
    });
    expect(gs.checked_at.toMillis()).toBe(back);
    expect(gs).not.toHaveProperty("stale_since");
    expect(r.preflightSkips).toBe(0);
    expect(appServesTeam(gs, back)).toBe(true);

    // A NEW gap after recovery is a new run, with its own 30 minutes.
    const again = back + 5 * MIN;
    await tick(f, again, STICKY);
    const gs3 = await server(f);
    expect(gs3.served).toBe(true);
    expect(gs3.stale_since.toMillis()).toBe(again);
  });

  test("flags absent, the same 31 minutes: served false from the first stale tick", async () => {
    const f = world();
    const held = await staleRun(f, ARMED);
    expect(held[0].gs).toMatchObject({ served: false, teams: [], preflight: { reasons: [STALE] } });
    expect(held[0].gs.checked_at.toMillis()).toBe(S);
    expect(held[5].gs.checked_at.toMillis()).toBe(S); // on-change: one write
    expect(held[5].gs).not.toHaveProperty("stale_since");
  });
});

// ---------------------------------------------------------------------------
describe("B2 — what a hold is NOT", () => {
  test("any other failing reason beside the stale bridge flips served at once", async () => {
    const f = world();
    beat(f, GAP.lastBeat);
    await tick(f, GAP.tA, STICKY);
    expect((await server(f)).served).toBe(true);
    // The ladder fact disappears as well: this is no longer just a write gap.
    f.put(CONTROLLER, controllerDoc(f, { base_ladder_asserts_segments: undefined }));
    const r = await tick(f, GAP.tB, STICKY);
    const gs = await server(f);
    expect(gs).toMatchObject({ served: false, teams: [] });
    expect(gs.preflight.reasons).toEqual([STALE, "preflight_ladder_unknown"]);
    expect(r).not.toHaveProperty("servedHeld");
    expect(rows(r, "served_held")).toEqual([]);
    // P2 IS failing, so the run is on the record.
    expect(gs.stale_since.toMillis()).toBe(GAP.tB);
  });

  test("an account that was never served is not made served by a stale first tick", async () => {
    const f = world();
    beat(f, GAP.lastBeat);
    const r = await tick(f, GAP.tB, STICKY); // the first tick this account ever had
    let gs = await server(f);
    expect(gs).toMatchObject({ served: false, teams: [], preflight: { reasons: [STALE] } });
    expect(gs.stale_since.toMillis()).toBe(GAP.tB);
    expect(r).not.toHaveProperty("servedHeld");

    await tick(f, GAP.tC, STICKY);
    expect((await server(f)).checked_at.toMillis()).toBe(GAP.tB); // unchanged → not rewritten

    beat(f, GAP.resumes);
    await tick(f, GAP.tD, STICKY);
    gs = await server(f);
    expect(gs.served).toBe(true);
    expect(gs).not.toHaveProperty("stale_since");
  });

  test("it never gates an END: a final during a held gap is still written, and scored", async () => {
    const f = world();
    const T0 = OPEN + 30 * MIN;
    beat(f, T0 - 20 * SEC);
    await tick(f, T0, STICKY);
    await completeProbes(f);
    f.patch(JOB("start"), { state: "completed" });
    espn("final");
    const firstFinal = KICK + 3 * H + 20 * MIN;
    beat(f, firstFinal - 6 * MIN); // the gap began six minutes before the final
    await tick(f, firstFinal, STICKY);
    const r = await tick(f, firstFinal + 5 * MIN, STICKY);
    expect(r.endsPlanned).toBe(1);
    expect((await read(f, JOB("end"))).payload).toBe('{"ps":2}'); // a noon game ends in daylight: base OFF
    expect((await read(f, SCORE)).end).toMatchObject({ job_id: `${EVENT}_end`, reason: "confirmed_final" });
    const gs = await server(f);
    expect(gs.served).toBe(true); // held
    expect(gs.preflight.reasons).toEqual([STALE]);
  });

  test("observe mode withholds nothing, so nothing is held: served by the verdict path, as before", async () => {
    const f = world();
    const opts = withFlags({ servedSticky: true, preflightMode: "observe" });
    beat(f, GAP.lastBeat);
    await tick(f, GAP.tA, opts);
    const r = await tick(f, GAP.tB, opts);
    const gs = await server(f);
    expect(gs).toMatchObject({ served: true, preflight: { ok: false, reasons: [STALE], mode: "observe" } });
    expect(r).not.toHaveProperty("servedHeld");
    expect(await read(f, JOB("start"))).toBeDefined(); // observe mints
    expect(gs.stale_since.toMillis()).toBe(GAP.tB); // the run is still tracked
  });

  test("a team disabled during a held gap: served false at once, and the run is cleared", async () => {
    const f = world();
    beat(f, GAP.lastBeat);
    await tick(f, GAP.tA, STICKY);
    await tick(f, GAP.tB, STICKY);
    expect((await server(f)).stale_since.toMillis()).toBe(GAP.tB);
    f.patch(CONFIG, { enabled: false });
    await tick(f, GAP.tC, STICKY);
    const gs = await server(f);
    expect(gs).toMatchObject({ served: false, teams: [], next_fire: null });
    expect(gs).not.toHaveProperty("stale_since");
  });

  test("the publish kill switch still wins: nothing is written, held or not", async () => {
    const f = world();
    const opts = withFlags({ servedSticky: true, publishServerStatus: false });
    beat(f, GAP.lastBeat);
    await tick(f, GAP.tA, opts);
    await tick(f, GAP.tB, opts);
    expect((await read(f, USER)).gameday_server).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
describe("A — preflight_bridge_grace: P2's window is 15 minutes", () => {
  const T0 = OPEN + 30 * MIN;

  async function oneTick(ageMs, opts) {
    const f = world();
    beat(f, T0 - ageMs);
    const r = await tick(f, T0, opts);
    return { f, r, gs: await server(f), job: await read(f, JOB("start")) };
  }

  test("the boundary: a heartbeat 14:59 old mints; 15:00 mints; 15:01 is stale and withheld", async () => {
    for (const age of [14 * MIN + 59 * SEC, 15 * MIN]) {
      const { r, gs, job } = await oneTick(age, GRACE);
      expect(gs).toMatchObject({ served: true, preflight: { ok: true, reasons: [] } });
      expect(job.fireAt.toMillis()).toBe(FIRE);
      expect(r.preflightSkips).toBe(0);
    }
    const late = await oneTick(15 * MIN + 1 * SEC, GRACE);
    expect(late.gs).toMatchObject({ served: false, preflight: { ok: false, reasons: [STALE] } });
    expect(late.job).toBeUndefined();
    expect(late.r.preflightSkips).toBe(1);
  });

  test("flag absent: the boundary is where it always was — 4:59 mints, 5:01 is stale", async () => {
    expect((await oneTick(4 * MIN + 59 * SEC, ARMED)).job).toBeDefined();
    const late = await oneTick(5 * MIN + 1 * SEC, ARMED);
    expect(late.job).toBeUndefined();
    expect(late.gs.preflight.reasons).toEqual([STALE]);
  });

  test("no heartbeat document at all is stale with the flag on", async () => {
    const f = world();
    const r = await tick(f, T0, GRACE);
    expect((await server(f)).preflight.reasons).toEqual([STALE]);
    expect(r.preflightSkips).toBe(1);
  });

  test("scoped: a uid list naming this account widens it; a list naming another leaves 5 minutes", async () => {
    expect((await oneTick(10 * MIN, withFlags({ preflightBridgeGrace: [UID] }))).job).toBeDefined();
    expect((await oneTick(10 * MIN, withFlags({ preflightBridgeGrace: [OTHER] }))).job).toBeUndefined();
  });

  test("the ten-minute gap with A on: P2 never fails, so the start mints on its first tick and nothing is skipped", async () => {
    const g = await runGap(world(), GRACE);
    expect(g.tB.job.fireAt.toMillis()).toBe(FIRE); // 5:20 old — inside 15 min
    for (const k of ["tA", "tB", "tC", "tD"]) {
      expect(g[k].gs).toMatchObject({ served: true, teams: [TEAM], preflight: { ok: true, reasons: [] } });
      expect(g[k].gs).not.toHaveProperty("stale_since");
      expect(g[k].r.preflightSkips).toBe(0);
      expect(g[k].app).toBe(true);
    }
  });
});

// ---------------------------------------------------------------------------
describe("A and B2 together", () => {
  test("the ten-minute gap: nothing fails, nothing is held, no stale_since is ever written", async () => {
    const f = world();
    const g = await runGap(f, BOTH);
    for (const k of ["tA", "tB", "tC", "tD"]) {
      expect(g[k].gs.served).toBe(true);
      expect(g[k].gs).not.toHaveProperty("stale_since");
      expect(g[k].r).not.toHaveProperty("servedHeld");
    }
    expect(f.writes.some((w) => JSON.stringify(w).includes("stale_since"))).toBe(false);
  });

  test("a dead bridge: P2 fails once the heartbeat is past 15 min, served holds 30 min more, then follows", async () => {
    const f = world();
    const T0 = OPEN + 30 * MIN + 20 * SEC;
    beat(f, T0 - 20 * SEC); // the last heartbeat this bridge ever lands
    await tick(f, T0, BOTH);
    await completeProbes(f);
    // +5, +10, +15 min: inside the 15-minute window (15:20 at the third is not).
    await tick(f, T0 + 5 * MIN, BOTH);
    await tick(f, T0 + 10 * MIN, BOTH);
    expect((await server(f)).preflight.ok).toBe(true);
    const first = T0 + 15 * MIN; // heartbeat 15:20 old → P2 fails for the first time
    await tick(f, first, BOTH);
    let gs = await server(f);
    expect(gs).toMatchObject({ served: true, preflight: { ok: false, reasons: [STALE] } });
    expect(gs.stale_since.toMillis()).toBe(first);
    await tick(f, first + 25 * MIN, BOTH);
    expect((await server(f)).served).toBe(true);
    await tick(f, first + 30 * MIN, BOTH); // 45:20 after the last heartbeat
    gs = await server(f);
    expect(gs).toMatchObject({ served: false, teams: [], preflight: { reasons: [STALE] } });
  });
});

// ---------------------------------------------------------------------------
describe("a healthy account: the flags change nothing at all", () => {
  test("three fresh ticks, flags off vs both on: every document is identical", async () => {
    async function run(opts) {
      const f = world();
      for (const at of [GAP.tA, GAP.tB, GAP.tC]) {
        beat(f, at - 20 * SEC);
        await tick(f, at, opts);
      }
      return snapshot(f);
    }
    const off = await run(ARMED);
    const on = await run(BOTH);
    expect(on).toEqual(off);
    expect(JSON.stringify(on)).not.toContain("stale_since");
    expect(JSON.stringify(on)).not.toContain("servedHeld");
  });
});

// ---------------------------------------------------------------------------
describe("the production read: both flags come from config/gameday_planner", () => {
  const ARM = { write_jobs: true, uid_allowlist: [UID] };

  async function gapWithConfig(config) {
    const f = world();
    f.put("config/gameday_planner", { ...ARM, ...config });
    beat(f, GAP.lastBeat);
    f.setNow(GAP.tA);
    await runPlannerTick(f.db, GAP.tA);
    f.setNow(GAP.tB);
    const r = await runPlannerTick(f.db, GAP.tB);
    return { f, r, gs: await server(f), job: await read(f, JOB("start")) };
  }

  test("both absent: the old behaviour, and no warning", async () => {
    const { gs, job } = await gapWithConfig({});
    expect(gs).toMatchObject({ served: false, teams: [], preflight: { reasons: [STALE] } });
    expect(gs).not.toHaveProperty("stale_since");
    expect(job).toBeUndefined();
    expect(warn).not.toHaveBeenCalled();
  });

  test("served_sticky: [uid] → held; served_sticky: true → held", async () => {
    for (const v of [[UID], true]) {
      const { gs, job, r } = await gapWithConfig({ served_sticky: v });
      expect(gs).toMatchObject({ served: true, teams: [TEAM], preflight: { ok: false, reasons: [STALE] } });
      expect(gs.stale_since.toMillis()).toBe(GAP.tB);
      expect(job).toBeUndefined();
      expect(r.servedHeld).toBe(1);
    }
  });

  test("preflight_bridge_grace: [uid] → the 5:20-old heartbeat passes and the start mints", async () => {
    const { gs, job } = await gapWithConfig({ preflight_bridge_grace: [UID] });
    expect(gs).toMatchObject({ served: true, preflight: { ok: true, reasons: [] } });
    expect(job.fireAt.toMillis()).toBe(FIRE);
  });

  test("a list naming only another account leaves this one exactly as before", async () => {
    const { gs, job } = await gapWithConfig({ served_sticky: [OTHER], preflight_bridge_grace: [OTHER] });
    expect(gs.served).toBe(false);
    expect(gs).not.toHaveProperty("stale_since");
    expect(job).toBeUndefined();
    expect(warn).not.toHaveBeenCalled();
  });

  test("a malformed value is OFF, and is logged so the failed flip is seen", async () => {
    for (const [key, v] of [
      ["served_sticky", "true"], ["served_sticky", 30], ["served_sticky", [UID, 7]],
      ["preflight_bridge_grace", "true"], ["preflight_bridge_grace", 15], ["preflight_bridge_grace", { [UID]: true }],
    ]) {
      warn.mockClear();
      const { gs, job } = await gapWithConfig({ [key]: v });
      expect(gs.served).toBe(false);
      expect(gs).not.toHaveProperty("stale_since");
      expect(job).toBeUndefined();
      expect(warn.mock.calls.some((c) => String(c[0]).includes(`config/gameday_planner.${key} is malformed`))).toBe(true);
    }
  });

  test("removing the flag mid-run stops the hold on the next tick and clears the run when it is next written", async () => {
    const { f } = await gapWithConfig({ served_sticky: [UID] });
    expect((await server(f)).served).toBe(true);
    f.put("config/gameday_planner", ARM); // the rollback write: field removed
    f.setNow(GAP.tC);
    await runPlannerTick(f.db, GAP.tC);
    const gs = await server(f);
    expect(gs).toMatchObject({ served: false, teams: [], preflight: { reasons: [STALE] } });
    expect(gs).not.toHaveProperty("stale_since");
  });
});
