/**
 * Steps A + B (2026-10-02) against the Firestore emulator — the REAL planner
 * and dispatcher ticks on real Firestore semantics, read back with plain
 * .get()s.
 *
 * ⚠️ NOT run by `npm test`. From functions/:
 *   firebase emulators:exec --only firestore --project lumina-fn-test \
 *     "npx jest --config jest.emulator.config.js --runInBand test/emulator/gameDayServerAB"
 *
 * The unit suite proves the decisions on an in-memory fake. These prove the
 * Firestore properties the code RELIES ON, which a fake can only imitate:
 *   • DocumentSnapshot.updateTime advances on a mask-only PATCH-style update
 *     (P2 reads the heartbeat's server update time; the bridge writes no
 *     timestamp field)
 *   • a dotted-path update replaces the named nested fields and leaves their
 *     siblings alone (the planner's gameday_server write must never clobber the
 *     dispatcher's last_fire)
 *   • FieldValue.increment on a dotted nested path (scorecard start.attempts)
 *   • update() on an absent document fails and creates nothing (the dispatcher
 *     never invents a scorecard entry for a pre-deploy session)
 *   • the A2 reschedule transaction against a real job document
 * Synthetic ids only; documentation-range IPs.
 */

jest.mock("../../src/espnClient", () => ({ fetchTeamGame: jest.fn() }));

import * as admin from "firebase-admin";
import { fetchTeamGame } from "../../src/espnClient";
import { runPlannerTick } from "../../src/planGameDayFires";
import { runDispatchTick } from "../../src/dispatchFireJobs";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("FIRESTORE_EMULATOR_HOST is unset — refusing to run against production");
}
if (!admin.apps.length) {
  admin.initializeApp({ projectId: "lumina-fn-test" });
}
const db = admin.firestore();

const UID = "u_emu_ab";
const CTRL = "ctrl_emu_ab";
const TEAM = "nfl_emuteam";
const ESPN = "31";
const GAME = "9300001";
const EVENT = `gd_${TEAM}_${GAME}`;
const MIN = 60_000;
const ARMED = { forcePolicy: { enabled: true, allowlist: [UID] } };

// The 2026-10-01 production start payload (identifier-free), reproduced by the
// same inputs as gameDayBenchRegression.test.js.
const LIVE_START_PAYLOAD =
  '{"on":true,"bri":200,"seg":[' +
  '{"id":0,"on":true,"fx":52,"sx":160,"ix":128,"col":[[49,29,0,0],[255,60,0,0]]},' +
  '{"id":1,"on":true,"fx":52,"sx":160,"ix":128,"col":[[49,29,0,0],[255,60,0,0]]},' +
  '{"id":2,"on":true,"fx":52,"sx":160,"ix":128,"col":[[49,29,0,0],[255,60,0,0]]}]}';

async function wipe(): Promise<void> {
  for (const group of [
    "commands", "fire_jobs", "game_day_sessions", "game_day_autopilot", "controllers",
    "bridge_status", "debug_errors", "entries",
  ]) {
    const snap = await db.collectionGroup(group).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  for (const col of ["bridge_registry", "gameday_scorecard", "gameday_plan_log", "config", "fire_metrics", "users"]) {
    const snap = await db.collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

beforeEach(wipe);
afterAll(wipe);

async function seedAccount(kickoffMs: number): Promise<void> {
  await db.doc(`users/${UID}`).set({
    owner_id: UID, time_zone: "America/Chicago", latitude: 39.0, longitude: -95.0,
    game_day_team_priority: [TEAM],
    // The dispatcher's field, already present: the planner must not touch it.
    gameday_server: { last_fire: { event_id: "gd_prior_1", seq: "end", state: "completed" } },
  });
  await db.doc(`users/${UID}/controllers/${CTRL}`).set({
    ip: "192.0.2.30",
    participating_channels: [0, 1, 2],
    participating_channels_device_ids: [0, 1, 2],
    participating_channels_at: admin.firestore.Timestamp.fromMillis(Date.now() - 86_400_000),
    base_ladder_asserts_segments: true,
  });
  await db.doc(`users/${UID}/game_day_autopilot/${TEAM}`).set({
    enabled: true, team_slug: TEAM, team_name: "Emu Team", sport: "nfl", espn_team_id: ESPN,
    primary_color: 0xff311d00, secondary_color: 0xffff3c00, effect_id: 52, speed: 160,
    intensity: 128, brightness: 200, design_mode: "fallback", skip_day_games: false,
  });
  await db.doc("bridge_registry/BR_EMU_AB").set({ pairedUid: UID, status: "paired" });
  // The bridge's heartbeat: a mask update with NO timestamp field. P2 reads
  // the document's server updateTime.
  await db.doc(`users/${UID}/bridge_status/current`).set({ uptime: 1 });
  await db.doc(`users/${UID}/bridge_status/current`).update({ uptime: 2, version: "1.2" });
  (fetchTeamGame as jest.Mock).mockImplementation(async (_s: string, id: string) =>
    id === ESPN
      ? {
          gameId: GAME, startMs: kickoffMs, homeTeamId: ESPN, awayTeamId: "0",
          isFinal: false, isInProgress: false, statusName: "STATUS_SCHEDULED",
        }
      : null
  );
}

describe("planner tick on real Firestore (B1/B2/B3)", () => {
  test("mints the byte-identical start; publishes gameday_server without touching last_fire; scorecard; P6 probe", async () => {
    const now = Date.now();
    const kickoff = now + 5 * 60 * MIN;
    await seedAccount(kickoff);

    // P2's input, read the way the planner reads it.
    const hb = await db.doc(`users/${UID}/bridge_status/current`).get();
    expect(hb.updateTime).toBeDefined();
    expect(Math.abs(hb.updateTime!.toMillis() - Date.now())).toBeLessThan(60_000);

    const r = await runPlannerTick(db, now, ARMED);
    expect(r.errors).toBe(0);
    expect(r.preflightSkips).toBe(0);

    const start = (await db.doc(`users/${UID}/fire_jobs/${EVENT}_start`).get()).data()!;
    expect(start.payload).toBe(LIVE_START_PAYLOAD);
    expect(start.fireAt.toMillis()).toBe(kickoff - 30 * MIN);
    expect(start.retryUntil.toMillis()).toBe(kickoff);

    const gs = (await db.doc(`users/${UID}`).get()).get("gameday_server");
    expect(gs.served).toBe(true);
    expect(gs.teams).toEqual([TEAM]);
    expect(gs.preflight).toMatchObject({ ok: true, reasons: [], mode: "enforce" });
    expect(gs.next_fire.event_id).toBe(EVENT);
    // Dotted-path update: the sibling the dispatcher owns is intact.
    expect(gs.last_fire).toEqual({ event_id: "gd_prior_1", seq: "end", state: "completed" });

    const session = (await db.doc(`users/${UID}/game_day_sessions/${EVENT}`).get()).data()!;
    const key = session.scorecard_key as string;
    const sc = (await db.doc(`gameday_scorecard/${key}/entries/${UID}_${EVENT}`).get()).data()!;
    expect(sc).toMatchObject({ served: true, preflight_ok: true, bridge_fw: "1.2" });
    expect(sc.start.state).toBe("scheduled");

    const probes = await db.collection(`users/${UID}/commands`).where("source", "==", "gameday_preflight").get();
    expect(probes.size).toBe(1);
    expect(probes.docs[0].get("type")).toBe("getInfo");
  });
});

describe("dispatcher tick on real Firestore (A2 + B3)", () => {
  async function seedDispatched(withScorecard: boolean) {
    const now = Date.now();
    await db.doc(`users/${UID}`).set({ owner_id: UID });
    await db.doc(`users/${UID}/controllers/${CTRL}`).set({ ip: "192.0.2.30" });
    await db.doc(`users/${UID}/game_day_autopilot/${TEAM}`).set({ enabled: true });
    await db.doc("bridge_registry/BR_EMU_AB").set({ pairedUid: UID, status: "paired" });
    const fireAt = admin.firestore.Timestamp.fromMillis(now - 4 * MIN);
    await db.doc(`users/${UID}/fire_jobs/${EVENT}_start`).set({
      eventId: EVENT, seq: "start", controllerId: CTRL, fireAt, type: "applyJson",
      payload: LIVE_START_PAYLOAD, state: "dispatched", source: "game_day", attempts: 1,
      retryUntil: admin.firestore.Timestamp.fromMillis(now + 20 * MIN),
      commandId: "cmd_attempt_1",
    });
    await db.doc(`users/${UID}/commands/cmd_attempt_1`).set({
      type: "applyJson", controllerId: CTRL, status: "expired",
      error: "Command expired before the bridge picked it up (bridge offline or unreachable at fire time).",
      createdAt: admin.firestore.Timestamp.fromMillis(now - 4 * MIN),
    });
    if (withScorecard) {
      await db.doc(`users/${UID}/game_day_sessions/${EVENT}`).set({ scorecard_key: "2026-10-11" });
      await db.doc(`gameday_scorecard/2026-10-11/entries/${UID}_${EVENT}`).set({
        served: true, start: { state: "dispatched", attempts: 1, job_id: `${EVENT}_start` },
        stuck_executing_count: 0,
      });
    }
    return now;
  }

  test("an expired attempt is rescheduled transactionally; the scorecard records it with nested increments", async () => {
    const now = await seedDispatched(true);
    const r = await runDispatchTick(db, now);
    expect(r.retried).toBe(1);

    const job = (await db.doc(`users/${UID}/fire_jobs/${EVENT}_start`).get()).data()!;
    expect(job.state).toBe("scheduled");
    expect(job.fireAt.toMillis()).toBe(now + 30_000);
    expect(job.lastOutcome).toBe("expired");
    expect(job.lastCommandId).toBe("cmd_attempt_1");
    expect(job.retries).toBe(1);

    const sc = (await db.doc(`gameday_scorecard/2026-10-11/entries/${UID}_${EVENT}`).get()).data()!;
    expect(sc.start).toMatchObject({ state: "scheduled", retries: 1, last_outcome: "expired", attempts: 1, job_id: `${EVENT}_start` });
  });

  test("with no scorecard entry (a pre-deploy session), update() creates nothing", async () => {
    const now = await seedDispatched(false);
    await runDispatchTick(db, now);
    const entries = await db.collectionGroup("entries").get();
    expect(entries.size).toBe(0);
    expect((await db.doc(`users/${UID}/fire_jobs/${EVENT}_start`).get()).get("state")).toBe("scheduled");
  });
});
