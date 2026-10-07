// The end guarantee (`end_ignores_gate`, 2026-10-06) — the PURE pieces.
//   gameDayPlanning.startJobMayHaveLit   "fired" widened to a failed start
//   gameDayPlanning.decideEndRemint      re-minting a dead end job (#179)
//   fireJobs.endRetryUntilMs             the 90-minute budget
//   fireJobs.shouldRetractForTeam        a scheduled end is never retracted (#178)
// The planner-level behaviour is in plannerEndGuarantee.test.js.

const G = require("../../lib/gameDayPlanning");
const F = require("../../lib/fireJobs");

const MIN = 60_000;
const H = 60 * MIN;
const NOW = Date.parse("2026-10-12T03:40:00Z");
const GAME_START = NOW - 3.5 * H;

describe("startJobMayHaveLit", () => {
  test("dispatched, completed and failed may have lit; nothing else did", () => {
    for (const s of ["dispatched", "completed", "failed"]) expect(G.startJobMayHaveLit(s)).toBe(true);
    for (const s of ["scheduled", "cancelled", "expired", "skipped", undefined, null, "", "missing"]) {
      expect(G.startJobMayHaveLit(s)).toBe(false);
    }
    // GUARD 0b itself is unchanged.
    expect(G.startJobConfirmsFired("failed")).toBe(false);
  });
});

describe("the end budget", () => {
  test("15 minutes as shipped; 90 under the guarantee; the window is a parameter", () => {
    expect(F.END_RETRY_WINDOW_MS).toBe(15 * MIN);
    expect(F.END_RETRY_WINDOW_GUARANTEED_MS).toBe(90 * MIN);
    expect(F.endRetryUntilMs(NOW)).toBe(NOW + 15 * MIN);
    expect(F.endRetryUntilMs(NOW, F.END_RETRY_WINDOW_GUARANTEED_MS)).toBe(NOW + 90 * MIN);
  });
});

describe("decideEndRemint", () => {
  const d = (over = {}) =>
    G.decideEndRemint({ endJobState: "expired", remints: 0, lastMintMs: NOW - 30 * MIN, nowMs: NOW, gameStartMs: GAME_START, ...over });

  test("the constants: six re-mints, ten minutes apart, within twelve hours of kickoff", () => {
    expect(G.END_REMINT_MAX).toBe(6);
    expect(G.END_REMINT_MIN_GAP_MS).toBe(10 * MIN);
    expect(G.END_REMINT_HORIZON_MS).toBe(12 * H);
  });

  test("completed: nothing to do", () => {
    expect(d({ endJobState: "completed" })).toEqual({ kind: "completed" });
  });

  test("scheduled or dispatched: the dispatcher is on it", () => {
    expect(d({ endJobState: "scheduled" })).toEqual({ kind: "in_progress", state: "scheduled" });
    expect(d({ endJobState: "dispatched" })).toEqual({ kind: "in_progress", state: "dispatched" });
  });

  test("expired, failed, skipped, cancelled, or no job at all: re-mint, numbered from 1", () => {
    for (const s of ["expired", "failed", "skipped", "cancelled"]) {
      expect(d({ endJobState: s })).toEqual({ kind: "remint", n: 1, priorState: s });
    }
    expect(d({ endJobState: undefined })).toEqual({ kind: "remint", n: 1, priorState: "missing" });
    expect(d({ endJobState: "expired", remints: 3 })).toEqual({ kind: "remint", n: 4, priorState: "expired" });
  });

  test("the ceiling: the sixth re-mint is the last", () => {
    expect(d({ remints: 5 })).toMatchObject({ kind: "remint", n: 6 });
    expect(d({ remints: 6 })).toEqual({ kind: "ceiling", reason: "max_remints" });
    expect(d({ remints: 60 })).toEqual({ kind: "ceiling", reason: "max_remints" });
  });

  test("the horizon: nothing is re-minted past twelve hours from kickoff", () => {
    expect(d({ gameStartMs: NOW - 12 * H + MIN })).toMatchObject({ kind: "remint" });
    expect(d({ gameStartMs: NOW - 12 * H - MIN })).toEqual({ kind: "ceiling", reason: "horizon" });
  });

  test("the spacing: not within ten minutes of the last mint; a first mint with no record is immediate", () => {
    expect(d({ lastMintMs: NOW - 9 * MIN })).toEqual({ kind: "too_soon", waitMs: MIN });
    expect(d({ lastMintMs: NOW - 10 * MIN })).toMatchObject({ kind: "remint" });
    expect(d({ lastMintMs: null })).toMatchObject({ kind: "remint" });
  });

  test("a malformed counter reads as zero", () => {
    for (const r of [undefined, null, "3", -1, NaN, {}]) {
      expect(d({ remints: r })).toMatchObject({ kind: "remint", n: 1 });
    }
  });
});
