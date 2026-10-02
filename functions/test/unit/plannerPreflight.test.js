// planGameDayFires × B1 (pre-flight) / B2 (gameday_server) / B3 (scorecard) —
// the REAL planner tick on the shared in-memory Firestore. Every outcome is
// read back with a plain .get() on the production path.
//
// Times: Sunday 2026-10-11, kickoff 12:00 CDT (17:00Z), lead 30 → fire 16:30Z.

jest.mock("../../lib/espnClient", () => ({
  fetchTeamGame: jest.fn(async () => null),
}));

const { fetchTeamGame } = require("../../lib/espnClient");
const { makeFakeFirestore } = require("./support/fakeFirestore");
const { runPlannerTick } = require("../../lib/planGameDayFires");

const MIN = 60_000;
const H = 60 * MIN;
const KICK = Date.parse("2026-10-11T17:00:00Z");
const FIRE = KICK - 30 * MIN;
const T0 = KICK - 5 * H - 30 * MIN; // first tick inside the 6 h horizon
const UID = "u_pre";
const OTHER = "u_scoped_out";
const CTRL = "ctrl_pre";
const TEAM = "nfl_preteam";
const ESPN = "21";
const GAME = "9200001";
const EVENT = `gd_${TEAM}_${GAME}`;
const DAYKEY = "2026-10-11";

const ARMED = { forcePolicy: { enabled: true, allowlist: [UID] } };
const USER = (uid = UID) => `users/${uid}`;
const JOB = (seq, uid = UID) => `users/${uid}/fire_jobs/${EVENT}_${seq}`;
const SESSION = (uid = UID) => `users/${uid}/game_day_sessions/${EVENT}`;
const SCORE = (uid = UID) => `gameday_scorecard/${DAYKEY}/entries/${uid}_${EVENT}`;

function account(f, uid, { controller = {}, registry = true, config = {} } = {}) {
  f.put(USER(uid), { owner_id: uid, time_zone: "America/Chicago", latitude: 39.0, longitude: -95.0 });
  f.put(`users/${uid}/controllers/${CTRL}`, {
    ip: "192.0.2.20",
    participating_channels: [0, 1],
    participating_channels_device_ids: [0, 1],
    participating_channels_at: f.ts(T0 - 2 * 86_400_000),
    base_ladder_asserts_segments: true,
    ...controller,
  });
  f.put(`users/${uid}/game_day_autopilot/${TEAM}`, {
    enabled: true, team_slug: TEAM, team_name: "Pre Team", sport: "nfl", espn_team_id: ESPN,
    primary_color: 0xff102030, secondary_color: 0xff405060, effect_id: 52, speed: 160,
    intensity: 128, brightness: 200, ...config,
  });
  if (registry) f.put(`bridge_registry/BR_${uid}`, { pairedUid: uid, status: "paired" });
}

function world(opts = {}) {
  const f = makeFakeFirestore({ now: T0 });
  account(f, UID, opts);
  return f;
}

function espn(state = "scheduled") {
  fetchTeamGame.mockImplementation(async (_s, id) =>
    id === ESPN
      ? {
          gameId: GAME, startMs: KICK, homeTeamId: ESPN, awayTeamId: "0",
          isFinal: state === "final", isInProgress: state === "live",
          statusName: state === "final" ? "STATUS_FINAL" : state === "live" ? "STATUS_IN_PROGRESS" : "STATUS_SCHEDULED",
        }
      : null
  );
}

/** Advance the clock; the bridge heartbeats `heartbeatAgeMs` before the tick. */
async function tickAt(f, ms, { opts = ARMED, heartbeatAgeMs = 20_000, uid = UID } = {}) {
  if (heartbeatAgeMs !== null) {
    f.setNow(ms - heartbeatAgeMs);
    f.put(`users/${uid}/bridge_status/current`, { uptime: 1, version: "1.2" });
  }
  f.setNow(ms);
  return runPlannerTick(f.db, ms, opts);
}

const read = async (f, path) => (await f.db.doc(path).get()).data();
const probes = async (f, uid = UID) =>
  (await f.db.collection(`users/${uid}/commands`).where("source", "==", "gameday_preflight").get()).docs;

beforeEach(() => {
  fetchTeamGame.mockReset();
  espn();
});

// ---------------------------------------------------------------------------
describe("an account that passes every check", () => {
  test("start minted; gameday_server served; scorecard entry; P6 probe 1 in the same tick", async () => {
    const f = world();
    f.put(`users/${UID}/debug_errors/d1`, {
      context: "routing_decisions", app_version: "2.5.10+113", timestamp: f.ts(T0 - H),
    });
    const r = await tickAt(f, T0);
    expect(r.startsPlanned).toBe(1);
    expect(r.preflightSkips).toBe(0);
    expect(r.p6Probes).toBe(1);

    const start = await read(f, JOB("start"));
    expect(start.fireAt.toMillis()).toBe(FIRE);

    const gs = (await read(f, USER())).gameday_server;
    expect(gs.served).toBe(true);
    expect(gs.teams).toEqual([TEAM]);
    expect(gs.preflight).toMatchObject({ ok: true, reasons: [], info: [], mode: "enforce" });
    expect(gs.next_fire).toMatchObject({ event_id: EVENT, team_slug: TEAM, seq: "start" });
    expect(gs.next_fire.fire_at.toMillis()).toBe(FIRE);
    expect(gs.checked_at.toMillis()).toBe(T0);

    const sc = await read(f, SCORE());
    expect(sc).toMatchObject({
      uid: UID, event_id: EVENT, team_slug: TEAM, sport: "nfl", served: true,
      preflight_ok: true, preflight_reasons: [], controllers_total: 1, controllers_fired: 0,
      bridge_fw: "1.2", end: null, celebrations: null, stuck_executing_count: 0,
      lease_residue_rows: null, app_foreground_during_game: null,
      reasserts: { planned: 0, completed: 0, user_override: 0 },
    });
    expect(sc.start).toMatchObject({ job_id: `${EVENT}_start`, state: "scheduled", attempts: 0 });
    expect(sc.start.fire_at.toMillis()).toBe(FIRE);
    expect(sc.start.retry_until.toMillis()).toBe(KICK);
    expect(sc.game_start.toMillis()).toBe(KICK);
    expect(await read(f, `gameday_scorecard/${DAYKEY}`)).toMatchObject({ date: DAYKEY });

    const pr = await probes(f);
    expect(pr).toHaveLength(1);
    expect(pr[0].id).toMatch(/^fire_gdpre_/);
    expect(pr[0].data()).toMatchObject({ type: "getInfo", controllerId: CTRL, controllerIp: "192.0.2.20", status: "pending" });

    const s = await read(f, SESSION());
    expect(s.scorecard_key).toBe(DAYKEY);
    expect(s.preflight_p6.verdict).toBe("pending");
    expect(s.preflight_p6.probes[0].commandId).toBe(pr[0].id);
  });

  test("P7 is information only: an old app build is reported, the start still fires", async () => {
    const f = world();
    f.put(`users/${UID}/debug_errors/d1`, {
      context: "routing_decisions", app_version: "2.5.10+112", timestamp: f.ts(T0 - H),
    });
    await tickAt(f, T0);
    expect(await read(f, JOB("start"))).toBeDefined();
    expect((await read(f, USER())).gameday_server.preflight.info).toEqual(["lease_hygiene_unknown"]);
  });
});

// ---------------------------------------------------------------------------
describe("each failing check withholds the START, names itself, and is on the scorecard", () => {
  const cases = [
    ["P1 no paired bridge", { registry: false }, {}, "preflight_no_bridge"],
    ["P2 heartbeat 10 min old", {}, { heartbeatAgeMs: 10 * MIN }, "preflight_bridge_stale"],
    ["P2 no heartbeat doc at all", {}, { heartbeatAgeMs: null }, "preflight_bridge_stale"],
    ["P3 participation 40 days old", { controller: { participating_channels_at: { toMillis: () => T0 - 40 * 86_400_000 } } }, {}, "preflight_no_participation"],
    ["P4 ladder unverified", { controller: { base_ladder_asserts_segments: undefined } }, {}, "preflight_ladder_unknown"],
    ["P4 ladder bad", { controller: { base_ladder_asserts_segments: false } }, {}, null],
  ];
  test.each(cases)("%s", async (_name, worldOpts, tickOpts, reason) => {
    const f = world(worldOpts);
    const r = await tickAt(f, T0, tickOpts);
    expect(await read(f, JOB("start"))).toBeUndefined();
    expect((await probes(f))).toHaveLength(0);

    const gs = (await read(f, USER())).gameday_server;
    expect(gs.served).toBe(false);
    expect(gs.teams).toEqual([]);
    expect(gs.next_fire).toBeNull();
    if (reason !== null) {
      // An armed account: pre-flight is the deciding factor.
      expect(gs.preflight.reasons).toEqual([reason]);
      expect(r.preflightSkips).toBe(1);
      expect(r.logRows.filter((x) => x.action === "preflight_skip")).toEqual([
        { uid: UID, action: "preflight_skip", reasons: [reason] },
      ]);
      expect(r.logRows.find((x) => x.action === "plan_start")).toMatchObject({ preflightSkipped: true });
      const sc = await read(f, SCORE());
      expect(sc).toMatchObject({ served: false, preflight_ok: false, preflight_reasons: [reason], start: null });
    } else {
      // ladder_bad also GATES the account (gated_ladder_bad), so writeJobs is
      // already false — pre-flight reports, the gate decided.
      expect(gs.preflight.reasons).toEqual(["preflight_ladder_bad", "preflight_gated"]);
      expect(r.preflightSkips).toBe(0);
    }
    // The START accounting still reconciles: one bucket per config.
    expect(r.startsPlanned + Object.values(r.skipped).reduce((a, b) => a + b, 0)).toBe(r.configsEnabled);
  });

  test("P5: a gated account (no device facts) reports preflight_gated", async () => {
    const f = world({ controller: { participating_channels_device_ids: undefined } });
    await tickAt(f, T0);
    const gs = (await read(f, USER())).gameday_server;
    expect(gs.served).toBe(false);
    expect(gs.preflight.reasons).toEqual(["preflight_no_participation", "preflight_gated"]);
  });

  test("recovery: a stale heartbeat withholds this tick; the next fresh tick mints", async () => {
    const f = world();
    await tickAt(f, T0, { heartbeatAgeMs: 10 * MIN });
    expect(await read(f, JOB("start"))).toBeUndefined();
    await tickAt(f, T0 + 5 * MIN);
    expect(await read(f, JOB("start"))).toBeDefined();
    expect((await read(f, USER())).gameday_server.served).toBe(true);
    expect((await read(f, SCORE())).served).toBe(true);
  });

  test("a pre-flight skip is written to the scorecard once per reason set, not every tick", async () => {
    const f = world({ registry: false });
    await tickAt(f, T0);
    const writesAfterFirst = f.writes.filter((w) => w.path === SCORE()).length;
    await tickAt(f, T0 + 5 * MIN);
    expect(f.writes.filter((w) => w.path === SCORE()).length).toBe(writesAfterFirst);
  });
});

// ---------------------------------------------------------------------------
describe("observe mode (read from config/gameday_planner, not forced)", () => {
  const observeConfig = (f, extra = {}) =>
    f.put("config/gameday_planner", { write_jobs: true, uid_allowlist: [UID], preflight_mode: "observe", ...extra });

  test("a failing check is logged and published, but the start is minted", async () => {
    const f = world({ controller: { base_ladder_asserts_segments: undefined } });
    observeConfig(f);
    const r = await tickAt(f, T0, { opts: {} });
    expect(await read(f, JOB("start"))).toBeDefined();
    expect(r.preflightObserved).toBe(1);
    expect(r.preflightSkips).toBe(0);
    expect(r.logRows.find((x) => x.action === "preflight_skip")).toMatchObject({ observeOnly: true });
    const gs = (await read(f, USER())).gameday_server;
    expect(gs.served).toBe(true);
    expect(gs.preflight).toMatchObject({ ok: false, reasons: ["preflight_ladder_unknown"], mode: "observe" });
  });

  test("a typo in preflight_mode is enforce, not observe", async () => {
    const f = world({ controller: { base_ladder_asserts_segments: undefined } });
    observeConfig(f, { preflight_mode: "Observe" });
    await tickAt(f, T0, { opts: {} });
    expect(await read(f, JOB("start"))).toBeUndefined();
  });

  test("publish_server_status:false in the config stops every gameday_server write", async () => {
    const f = world();
    f.put("config/gameday_planner", { write_jobs: true, uid_allowlist: [UID], publish_server_status: false });
    await tickAt(f, T0, { opts: {} });
    expect(await read(f, JOB("start"))).toBeDefined();
    expect((await read(f, USER())).gameday_server).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
describe("P6 — reachability, per event", () => {
  async function mint(f) {
    await tickAt(f, T0);
    return (await read(f, SESSION())).preflight_p6.probes[0].commandId;
  }
  const settle = (f, id, status, error) =>
    f.patch(`users/${UID}/commands/${id}`, { status, ...(error ? { error } : {}) });

  test("two consecutive failures 5 min apart SKIP the start (skipped, never cancelled)", async () => {
    const f = world();
    const p1 = await mint(f);
    settle(f, p1, "expired", "Command expired before the bridge picked it up (bridge offline or unreachable at fire time).");

    await tickAt(f, T0 + 5 * MIN);
    const s1 = await read(f, SESSION());
    expect(s1.preflight_p6.probes).toHaveLength(2);
    const p2 = s1.preflight_p6.probes[1].commandId;
    expect(p2).not.toBe(p1);
    expect((await read(f, JOB("start"))).state).toBe("scheduled"); // one failure skips nothing

    settle(f, p2, "failed", "ERROR: HTTP -1");
    const r = await tickAt(f, T0 + 10 * MIN);
    const start = await read(f, JOB("start"));
    expect(start.state).toBe("skipped");
    expect(start.skipReason).toBe("preflight_controller_unreachable");
    expect(r.preflightSkips).toBe(1);
    const s2 = await read(f, SESSION());
    expect(s2).toMatchObject({ served: false, served_reason: "preflight_controller_unreachable" });
    expect(s2.preflight_p6.verdict).toBe("unreachable");
    const sc = await read(f, SCORE());
    expect(sc.served).toBe(false);
    expect(sc.start).toMatchObject({ state: "skipped", outcome: "preflight_controller_unreachable" });
    expect(sc.preflight_reasons).toContain("preflight_controller_unreachable");

    // The account stays unserved, with the reason, until that game's kickoff …
    await tickAt(f, T0 + 15 * MIN);
    const gs = (await read(f, USER())).gameday_server;
    expect(gs.served).toBe(false);
    expect(gs.preflight.reasons).toEqual(["preflight_controller_unreachable"]);
    // … and is served again after it.
    await tickAt(f, KICK + MIN);
    expect((await read(f, USER())).gameday_server.served).toBe(true);
  });

  test("probe 1 completes → verdict ok, no further probes", async () => {
    const f = world();
    const p1 = await mint(f);
    settle(f, p1, "completed");
    await tickAt(f, T0 + 5 * MIN);
    await tickAt(f, T0 + 10 * MIN);
    expect((await read(f, SESSION())).preflight_p6.verdict).toBe("ok");
    expect(await probes(f)).toHaveLength(1);
    expect((await read(f, JOB("start"))).state).toBe("scheduled");
  });

  test("observe mode: unreachable is recorded and logged; the start is NOT skipped", async () => {
    const f = world();
    f.put("config/gameday_planner", { write_jobs: true, uid_allowlist: [UID], preflight_mode: "observe" });
    await tickAt(f, T0, { opts: {} });
    const p1 = (await read(f, SESSION())).preflight_p6.probes[0].commandId;
    settle(f, p1, "failed", "ERROR: HTTP -1");
    await tickAt(f, T0 + 5 * MIN, { opts: {} });
    const p2 = (await read(f, SESSION())).preflight_p6.probes[1].commandId;
    settle(f, p2, "failed", "ERROR: HTTP -1");
    const r = await tickAt(f, T0 + 10 * MIN, { opts: {} });
    expect((await read(f, JOB("start"))).state).toBe("scheduled");
    expect((await read(f, SESSION())).preflight_p6.verdict).toBe("unreachable");
    expect(r.logRows.find((x) => x.reason === "preflight_controller_unreachable")).toMatchObject({ observeOnly: true });
  });

  test("no probe within 3 min of the fire — a late-minted start is not delayed by its own check", async () => {
    const f = world();
    await tickAt(f, FIRE - 2 * MIN);
    expect(await read(f, JOB("start"))).toBeDefined();
    expect(await probes(f)).toHaveLength(0);
  });

  test("one failure, then too close for a second probe: the start stands", async () => {
    const f = world();
    const p1 = await mint(f);
    settle(f, p1, "failed", "ERROR: HTTP -1");
    await tickAt(f, FIRE - 2 * MIN);
    expect(await probes(f)).toHaveLength(1);
    expect((await read(f, JOB("start"))).state).toBe("scheduled");
  });

  test("a probe is not written past an in-flight command; it is retried next tick", async () => {
    const f = world();
    f.put(`users/${UID}/commands/app1`, {
      type: "applyJson", status: "pending", controllerId: CTRL, createdAt: f.ts(T0 - 10_000),
    });
    const r = await tickAt(f, T0);
    expect(r.logRows.find((x) => x.action === "preflight_probe_deferred")).toMatchObject({ reason: "in_flight" });
    expect(await probes(f)).toHaveLength(0);
    f.patch(`users/${UID}/commands/app1`, { status: "completed" });
    await tickAt(f, T0 + 5 * MIN);
    expect(await probes(f)).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
describe("pre-flight never blocks an END", () => {
  test("a heartbeat gone stale at the final: the end is still written, and scored", async () => {
    const f = world();
    await tickAt(f, T0);
    f.patch(JOB("start"), { state: "completed" });
    espn("final");
    const firstFinal = KICK + 3 * H + 20 * MIN;
    await tickAt(f, firstFinal, { heartbeatAgeMs: 30 * MIN });
    const r = await tickAt(f, firstFinal + 5 * MIN, { heartbeatAgeMs: 35 * MIN });
    expect(r.endsPlanned).toBe(1);
    const end = await read(f, JOB("end"));
    // A noon game finishes in daylight: the restore is base OFF (preset 2).
    expect(end.payload).toBe('{"ps":2}');
    const sc = await read(f, SCORE());
    expect(sc.end).toMatchObject({ job_id: `${EVENT}_end`, reason: "confirmed_final", state: "scheduled" });
    expect(sc.end.espn_final_seen_at.toMillis()).toBe(firstFinal);
    // …while the account itself now reads as not served (stale bridge).
    expect((await read(f, USER())).gameday_server.preflight.reasons).toEqual(["preflight_bridge_stale"]);
  });
});

// ---------------------------------------------------------------------------
describe("B2 — publish cadence and ownership", () => {
  const statusWrites = (f, uid) =>
    f.writes.filter((w) => w.op === "update" && w.path === USER(uid) && "gameday_server.checked_at" in w.data);

  test("a served account is written EVERY tick (the D1 heartbeat)", async () => {
    const f = world();
    await tickAt(f, T0);
    await tickAt(f, T0 + 5 * MIN);
    expect(statusWrites(f, UID)).toHaveLength(2);
    expect((await read(f, USER())).gameday_server.checked_at.toMillis()).toBe(T0 + 5 * MIN);
  });

  test("a scoped-out account is written once, then only on change — and pays no pre-flight reads", async () => {
    const f = world();
    account(f, OTHER);
    await tickAt(f, T0);
    f.setNow(T0 + 5 * MIN - 20_000);
    f.put(`users/${OTHER}/bridge_status/current`, { uptime: 1 });
    await tickAt(f, T0 + 5 * MIN);
    expect(statusWrites(f, OTHER)).toHaveLength(1);
    const gs = (await read(f, USER(OTHER))).gameday_server;
    expect(gs).toMatchObject({ served: false, teams: [], preflight: null, next_fire: null });
    expect(f.reads.filter((p) => p === `users/${OTHER}/bridge_status/current`)).toHaveLength(0);
    expect(await read(f, `users/${OTHER}/fire_jobs/${EVENT}_start`)).toBeUndefined();
  });

  test("the dispatcher-owned last_fire survives every planner write", async () => {
    const f = world();
    f.patch(USER(), { gameday_server: { last_fire: { event_id: "gd_x_1", seq: "end", state: "completed" } } });
    await tickAt(f, T0);
    const gs = (await read(f, USER())).gameday_server;
    expect(gs.last_fire).toEqual({ event_id: "gd_x_1", seq: "end", state: "completed" });
    expect(gs.served).toBe(true);
  });

  test("forced publish off writes nothing", async () => {
    const f = world();
    await tickAt(f, T0, { opts: { ...ARMED, forceFlags: { publishServerStatus: false } } });
    expect((await read(f, USER())).gameday_server).toBeUndefined();
  });

  test("a served account whose last team is disabled flips to served:false", async () => {
    const f = world();
    await tickAt(f, T0);
    f.patch(`users/${UID}/game_day_autopilot/${TEAM}`, { enabled: false });
    await tickAt(f, T0 + 5 * MIN);
    const gs = (await read(f, USER())).gameday_server;
    expect(gs.served).toBe(false);
    expect(gs.teams).toEqual([]);
  });

  test("a per-pixel saved design is not a served team (the server refuses it)", async () => {
    const f = world({
      config: { design_mode: "saved", saved_design_payload: { seg: [{ i: [0, "FF0000", 1, "00FF00"] }] } },
    });
    await tickAt(f, T0);
    const gs = (await read(f, USER())).gameday_server;
    expect(gs.served).toBe(true);
    expect(gs.teams).toEqual([]);
  });
});
