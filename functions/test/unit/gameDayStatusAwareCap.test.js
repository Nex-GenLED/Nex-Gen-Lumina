// The STATUS-AWARE hard cap (flag `status_aware_cap`), as pure functions.
//
// Owner decision 2026-10-02: no cap while ESPN reports the game in progress,
// at halftime or delayed; fire it when ESPN goes silent or reports postponed or
// cancelled; a PER-SPORT absolute ceiling (football kickoff + 6 h); the 3.5 h
// football estimate unchanged for the daylight rule.
//
// Two properties carry the weight:
//   1. With the flag off (no `cap`, or statusAware false) decideEndSignal is the
//      shipped function — proven over a dense matrix, not a few cases.
//   2. With it on, a cap only ever moves LATER: every ceiling sits above its
//      sport's shipped bound, and nothing but ESPN's positive "live" holds it.
// Tick-level behaviour is in plannerEspnSlate.test.js. Runs against lib/.

const P = require("../../lib/gameDayPlanning");

const M = 60_000;
const H = 60 * M;
const T0 = Date.UTC(2026, 9, 10, 23, 30, 0); // a 6:30 PM CDT kickoff

const SPORTS = ["nfl", "ncaaFB", "mlb", "nba", "wnba", "ncaaMB", "nhl", "mls", "nwsl", "epl", "fifa", "championsLeague", "unknown_sport"];

const started = (over = {}) => ({ startPlannedAt: { seconds: 1 }, gameStartMs: T0, consecutiveFinalPolls: 0, ...over });

// ---------------------------------------------------------------------------
describe("the ceilings", () => {
  test("football is kickoff + 6 h (the owner's number); every sport's is documented in the table", () => {
    expect(P.capCeilingMs(T0, "nfl")).toBe(T0 + 6 * H);
    expect(P.capCeilingMs(T0, "ncaaFB")).toBe(T0 + 6 * H);
    expect(P.capCeilingMs(T0, "mlb")).toBe(T0 + 7 * H);
    expect(P.capCeilingMs(T0, "nba")).toBe(T0 + 4.5 * H);
    expect(P.capCeilingMs(T0, "wnba")).toBe(T0 + 4.5 * H);
    expect(P.capCeilingMs(T0, "ncaaMB")).toBe(T0 + 4.5 * H);
    expect(P.capCeilingMs(T0, "nhl")).toBe(T0 + 5 * H);
    for (const s of ["mls", "nwsl", "epl", "fifa", "championsLeague"]) expect(P.capCeilingMs(T0, s)).toBe(T0 + 5 * H);
    expect(P.capCeilingMs(T0, "unknown_sport")).toBe(P.fallbackEndMs(T0, "unknown_sport") + H);
  });

  test("every ceiling is LATER than the shipped bound — the status-aware cap never ends a game earlier", () => {
    for (const s of SPORTS) {
      expect(P.capCeilingMs(T0, s)).toBeGreaterThan(P.fallbackEndMs(T0, s));
    }
  });

  test("the football estimate is unchanged at 3.5 h (the daylight rule reads it)", () => {
    expect(P.estimatedDurationMs("nfl")).toBe(3.5 * H);
    expect(P.estimatedDurationMs("ncaaFB")).toBe(3.5 * H);
    expect(P.fallbackEndMs(T0, "ncaaFB")).toBe(T0 + 4.5 * H);
  });
});

// ---------------------------------------------------------------------------
describe("espnReportsLive — what holds the cap", () => {
  const g = (statusName, statusState = "", isFinal = false) => ({ statusName, statusState, isFinal });

  test("in progress, halftime, between periods and delays hold it", () => {
    for (const n of ["STATUS_IN_PROGRESS", "STATUS_HALFTIME", "STATUS_END_PERIOD", "STATUS_DELAYED", "STATUS_RAIN_DELAY"]) {
      expect(P.espnReportsLive(g(n))).toBe(true);
    }
    // A delay before the start (ESPN may say state "pre") is a game still to be played tonight.
    expect(P.espnReportsLive(g("STATUS_DELAYED", "pre"))).toBe(true);
    // Any status ESPN files under state "in".
    expect(P.espnReportsLive(g("STATUS_FIRST_HALF", "in"))).toBe(true);
  });

  test("postponed, cancelled, suspended, final, scheduled, unknown and silence do NOT", () => {
    for (const n of ["STATUS_POSTPONED", "STATUS_CANCELED", "STATUS_CANCELLED", "STATUS_SUSPENDED", "STATUS_FORFEIT", "STATUS_ABANDONED"]) {
      expect(P.espnReportsLive(g(n))).toBe(false);
      expect(P.espnReportsLive(g(n, "in"))).toBe(false); // the release name wins over state
    }
    expect(P.espnReportsLive(g("STATUS_FINAL", "post", true))).toBe(false);
    expect(P.espnReportsLive(g("STATUS_IN_PROGRESS", "in", true))).toBe(false); // completed wins
    expect(P.espnReportsLive(g("STATUS_SCHEDULED", "pre"))).toBe(false);
    expect(P.espnReportsLive(g("STATUS_SOMETHING_NEW", "post"))).toBe(false);
    expect(P.espnReportsLive(g("", ""))).toBe(false); // a silent (gone) game
  });
});

// ---------------------------------------------------------------------------
describe("flag OFF — decideEndSignal is the shipped function", () => {
  test("no `cap`, `cap.statusAware: false` and the shipped call agree on a dense matrix", () => {
    const states = [
      started(),
      started({ consecutiveFinalPolls: 1 }),
      started({ gameStartMs: undefined }),
      started({ endFiredAt: { seconds: 2 } }),
      { gameStartMs: T0 }, // never started (#66)
    ];
    let n = 0;
    for (const sport of SPORTS) {
      for (const state of states) {
        for (const espnIsFinal of [false, true]) {
          for (let t = T0 - H; t <= T0 + 9 * H; t += 5 * M) {
            const base = P.decideEndSignal({ espnIsFinal, state, sport, nowMs: t });
            for (const espnLive of [false, true]) {
              expect(P.decideEndSignal({ espnIsFinal, state, sport, nowMs: t, cap: { statusAware: false, espnLive } })).toEqual(base);
            }
            n++;
          }
        }
      }
    }
    expect(n).toBeGreaterThan(10_000);
  });

  test("the shipped cap still fires at the bound while ESPN says live", () => {
    const d = P.decideEndSignal({ espnIsFinal: false, state: started(), sport: "ncaaFB", nowMs: T0 + 4.5 * H + 1 });
    expect(d).toEqual({ fireEnd: true, reason: "hard_cap", nextConsecutive: 0 });
  });
});

// ---------------------------------------------------------------------------
describe("flag ON — held while live, fired on silence / postponement, the ceiling always", () => {
  const on = (espnLive, nowMs, sport = "ncaaFB", state = started(), espnIsFinal = false) =>
    P.decideEndSignal({ espnIsFinal, state, sport, nowMs, cap: { statusAware: true, espnLive } });
  const bound = T0 + 4.5 * H;
  const ceiling = T0 + 6 * H;

  test("before the bound nothing changes, live or not", () => {
    for (const t of [T0, T0 + 2 * H, bound]) {
      expect(on(true, t)).toEqual(P.decideEndSignal({ espnIsFinal: false, state: started(), sport: "ncaaFB", nowMs: t }));
      expect(on(false, t)).toEqual(P.decideEndSignal({ espnIsFinal: false, state: started(), sport: "ncaaFB", nowMs: t }));
    }
  });

  test("past the bound, live → HELD (a lightning delay), up to and including the ceiling", () => {
    for (const t of [bound + 1, bound + H, ceiling]) {
      expect(on(true, t)).toEqual({ fireEnd: false, reason: "cap_held_live", nextConsecutive: 0 });
    }
  });

  test("the ceiling fires even while ESPN still says live", () => {
    expect(on(true, ceiling + 1)).toEqual({ fireEnd: true, reason: "hard_cap_ceiling", nextConsecutive: 0 });
  });

  test("past the bound, not live (silent, postponed, cancelled) → the cap fires at the bound as shipped", () => {
    expect(on(false, bound + 1)).toEqual({ fireEnd: true, reason: "hard_cap", nextConsecutive: 0 });
  });

  test("a held game whose feed then goes silent is ended on that tick", () => {
    expect(on(true, bound + H).fireEnd).toBe(false);
    expect(on(false, bound + H + 5 * M)).toMatchObject({ fireEnd: true, reason: "hard_cap" });
  });

  test("the guards still come first: never started, already ended, no start time", () => {
    expect(on(true, ceiling + H, "ncaaFB", { gameStartMs: T0 }).reason).toBe("no_start");
    expect(on(true, ceiling + H, "ncaaFB", started({ endFiredAt: { seconds: 2 } })).reason).toBe("already_fired");
    expect(on(false, ceiling + H, "ncaaFB", started({ gameStartMs: undefined })).fireEnd).toBe(false);
  });

  test("a confirmed final is still a confirmed final (two polls), held cap or not", () => {
    const d = on(false, T0 + 3 * H, "ncaaFB", started({ consecutiveFinalPolls: 1 }), true);
    expect(d).toEqual({ fireEnd: true, reason: "confirmed_final", nextConsecutive: 2 });
  });

  test("MLB: a rain delay holds to kickoff + 7 h", () => {
    expect(on(true, T0 + 4 * H + 1, "mlb").reason).toBe("cap_held_live");
    expect(on(true, T0 + 7 * H + 1, "mlb").reason).toBe("hard_cap_ceiling");
  });
});

// ---------------------------------------------------------------------------
describe("capBoundMs — the hierarchy window closes when the cap fires", () => {
  test("off, or not live: the shipped bound; on and live: the ceiling", () => {
    for (const s of SPORTS) {
      expect(P.capBoundMs({ gameStartMs: T0, sport: s, statusAware: false, espnLive: true })).toBe(P.fallbackEndMs(T0, s));
      expect(P.capBoundMs({ gameStartMs: T0, sport: s, statusAware: true, espnLive: false })).toBe(P.fallbackEndMs(T0, s));
      expect(P.capBoundMs({ gameStartMs: T0, sport: s, statusAware: true, espnLive: true })).toBe(P.capCeilingMs(T0, s));
    }
  });
});
