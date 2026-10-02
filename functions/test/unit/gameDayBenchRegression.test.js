// BENCH REGRESSION — the 2026-10-01 live server fire, replayed.
//
// On 2026-10-01 the bench account ran a server-only Game Day start (TNF,
// kickoff 00:15Z 10-02): the planner minted `${event}_start` at its 17:45Z
// tick with fireAt 23:45:00Z, the dispatcher fired it 3.9 s late, and the
// bridge completed it in 1.95 s. The START payload below is that job's
// `payload` string, read back from production after the fire, byte for byte.
// It carries no identifiers (colours and effect parameters only).
//
// Everything else here is a SYNTHETIC copy of the session's inputs — synthetic
// uid, controller id, documentation-range IP, team slug and ESPN ids — shaped
// exactly like the bench documents the planner read that day (team config in
// the app's addTeam shape; participation [0,1,2] with the full device set;
// base ladder verified; a paired bridge heartbeating).
//
// THE PROPERTY: with every A/B change applied, an account that passes every
// check mints the SAME start and end documents it minted before — same
// payload bytes, same keys — plus exactly the one additive field A2 defines
// (`retryUntil`). If a later change alters a byte of either payload or adds a
// field, this fails and says which.
//
// ESPN SLATE FIX (2026-10-02). Both tests run twice: with every ESPN flag off,
// and with all three ON (`espn_college_slate`, `track_started_by_id`,
// `status_aware_cap`). For a normal NFL game the bytes must not move: the
// default scoreboard still finds it, tracking by id finds the same game, and
// the status-aware cap never comes into play for a game that finals.

jest.mock("../../lib/espnClient", () => ({
  fetchTeamGame: jest.fn(async () => null),
  fetchEventById: jest.fn(async () => ({ kind: "error" })),
  fetchCollegeSlateGame: jest.fn(async () => ({ game: null, onSlate: false, complete: false })),
  fetchCollegeTeamDivision: jest.fn(async () => ({ kind: "error" })),
}));

const { fetchTeamGame, fetchEventById } = require("../../lib/espnClient");
const { makeFakeFirestore } = require("./support/fakeFirestore");
const { runPlannerTick } = require("../../lib/planGameDayFires");

// ── captured from production, 2026-10-01 (identifier-free) ─────────────────
const LIVE_START_PAYLOAD =
  '{"on":true,"bri":200,"seg":[' +
  '{"id":0,"on":true,"fx":52,"sx":160,"ix":128,"col":[[49,29,0,0],[255,60,0,0]]},' +
  '{"id":1,"on":true,"fx":52,"sx":160,"ix":128,"col":[[49,29,0,0],[255,60,0,0]]},' +
  '{"id":2,"on":true,"fx":52,"sx":160,"ix":128,"col":[[49,29,0,0],[255,60,0,0]]}]}';
/** The keys the live start job carried at creation (before dispatch wrote more). */
const LIVE_START_KEYS = ["controllerId", "createdAt", "eventId", "fireAt", "payload", "seq", "source", "state", "type"];
/** After sunset the end restores base ON — the planner's own `{ps:1}`. */
const EXPECTED_END_PAYLOAD = '{"ps":1}';
const KICKOFF_MS = 1790900100000; // 2026-10-02T00:15:00Z
const START_FIRE_AT_MS = Date.parse("2026-10-01T23:45:00Z");
const PLANNER_TICK_MS = Date.parse("2026-10-01T17:45:14Z"); // first tick inside the 6 h horizon

// ── synthetic inputs ───────────────────────────────────────────────────────
const UID = "u_bench_synthetic";
const CTRL = "ctrl_bench_synthetic";
const TEAM = "nfl_benchteam";
const ESPN_TEAM = "5";
const GAME = "9100001";
const EVENT = `gd_${TEAM}_${GAME}`;
const ARMED = { forcePolicy: { enabled: true, allowlist: [UID] } };
const ESPN_FLAG_SETS = [
  ["every ESPN flag off", {}],
  ["every ESPN flag on", { espnCollegeSlate: true, trackStartedById: true, statusAwareCap: true }],
];

function benchWorld(now) {
  const f = makeFakeFirestore({ now });
  f.put(`users/${UID}`, {
    owner_id: UID,
    // City-level coordinates (not an address); after-sunset at the final.
    latitude: 39.0,
    longitude: -95.0,
    game_day_team_priority: [TEAM],
    gameday_gate_blocking: [],
  });
  f.put(`users/${UID}/controllers/${CTRL}`, {
    ip: "192.0.2.150",
    participating_channels: [0, 1, 2],
    participating_channels_device_ids: [0, 1, 2],
    participating_channels_at: f.ts(now - 3 * 3600_000),
    base_ladder_asserts_segments: true,
  });
  f.put(`users/${UID}/game_day_autopilot/${TEAM}`, {
    enabled: true,
    team_slug: TEAM,
    team_name: "Bench Team",
    sport: "nfl",
    espn_team_id: ESPN_TEAM,
    primary_color: 0xff311d00,
    secondary_color: 0xffff3c00,
    effect_id: 52,
    speed: 160,
    intensity: 128,
    brightness: 200,
    design_mode: "fallback",
    design_variety: "rotating",
    skip_day_games: true,
  });
  f.put("bridge_registry/BR_BENCH_SYNTH", { pairedUid: UID, status: "paired" });
  f.put(`users/${UID}/bridge_status/current`, { uptime: 1000, version: "1.2" });
  return f;
}

function espn(state) {
  const game = {
    gameId: GAME,
    startMs: KICKOFF_MS,
    homeTeamId: ESPN_TEAM,
    awayTeamId: "0",
    isFinal: state === "final",
    isInProgress: state === "live",
    statusName: state === "final" ? "STATUS_FINAL" : state === "live" ? "STATUS_IN_PROGRESS" : "STATUS_SCHEDULED",
  };
  fetchTeamGame.mockImplementation(async (_sport, id) => (id === ESPN_TEAM ? game : null));
  // Tracking by id (flag on) reads the same game the scoreboard does.
  fetchEventById.mockImplementation(async (_sport, id) => (id === GAME ? { kind: "found", game } : { kind: "absent" }));
}

const read = async (f, path) => (await f.db.doc(path).get()).data();
let flags = {};
const tickAt = async (f, ms) => {
  f.setNow(ms);
  // The bridge heartbeats every 30 s; keep its status fresh at every tick.
  f.put(`users/${UID}/bridge_status/current`, { uptime: 1000, version: "1.2" });
  return runPlannerTick(f.db, ms, { ...ARMED, forceFlags: flags });
};

beforeEach(() => {
  fetchTeamGame.mockReset();
  fetchEventById.mockReset();
});

describe.each(ESPN_FLAG_SETS)("%s", (_label, flagSet) => {
beforeEach(() => {
  flags = flagSet;
});

test("the start job is byte-identical to tonight's, plus only retryUntil", async () => {
  espn("scheduled");
  const f = benchWorld(PLANNER_TICK_MS);
  const r = await tickAt(f, PLANNER_TICK_MS);
  expect(r.startsPlanned).toBe(1);
  expect(r.errors).toBe(0);

  const start = await read(f, `users/${UID}/fire_jobs/${EVENT}_start`);
  expect(start.payload).toBe(LIVE_START_PAYLOAD);
  expect(Object.keys(start).sort()).toEqual([...LIVE_START_KEYS, "retryUntil"].sort());
  expect(start).toMatchObject({
    eventId: EVENT,
    seq: "start",
    controllerId: CTRL,
    type: "applyJson",
    state: "scheduled",
    source: "game_day",
  });
  expect(start.fireAt.toMillis()).toBe(START_FIRE_AT_MS);
  // A2: lead 30 → retries stop at kickoff.
  expect(start.retryUntil.toMillis()).toBe(KICKOFF_MS);
});

test("the end job after two ESPN finals is byte-identical too, plus only retryUntil", async () => {
  espn("scheduled");
  const f = benchWorld(PLANNER_TICK_MS);
  await tickAt(f, PLANNER_TICK_MS);
  // The dispatcher fired it (the live run: completed in 1.95 s).
  f.patch(`users/${UID}/fire_jobs/${EVENT}_start`, { state: "completed", outcome: "completed" });

  espn("live");
  await tickAt(f, Date.parse("2026-10-02T01:00:00Z"));
  espn("final");
  await tickAt(f, Date.parse("2026-10-02T03:20:00Z"));
  expect(await read(f, `users/${UID}/fire_jobs/${EVENT}_end`)).toBeUndefined(); // one final is not enough
  const endTick = Date.parse("2026-10-02T03:25:00Z");
  const r = await tickAt(f, endTick);
  expect(r.endsPlanned).toBe(1);

  const end = await read(f, `users/${UID}/fire_jobs/${EVENT}_end`);
  expect(end.payload).toBe(EXPECTED_END_PAYLOAD);
  expect(Object.keys(end).sort()).toEqual([...LIVE_START_KEYS, "retryUntil"].sort());
  expect(end).toMatchObject({
    eventId: EVENT,
    seq: "end",
    controllerId: CTRL,
    type: "applyJson",
    state: "scheduled",
    source: "game_day",
  });
  expect(end.fireAt.toMillis()).toBe(endTick);
  expect(end.retryUntil.toMillis()).toBe(endTick + 15 * 60_000);
});
});

test("the flags-on pass really followed the game by id once its start existed", async () => {
  flags = ESPN_FLAG_SETS[1][1];
  espn("scheduled");
  const f = benchWorld(PLANNER_TICK_MS);
  await tickAt(f, PLANNER_TICK_MS);
  expect(fetchEventById).not.toHaveBeenCalled(); // nothing was started before this tick
  f.patch(`users/${UID}/fire_jobs/${EVENT}_start`, { state: "completed", outcome: "completed" });
  espn("live");
  await tickAt(f, Date.parse("2026-10-02T01:00:00Z"));
  expect(fetchEventById).toHaveBeenCalledWith("nfl", GAME, expect.any(Map));
});
