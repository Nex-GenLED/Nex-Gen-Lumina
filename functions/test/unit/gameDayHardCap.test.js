// The Game Day HARD CAP, as pure functions.
//
// THE DEFECT: a game ESPN never marks final — postponed after the start fired,
// suspended, a feed that stops updating — never ended server-side. Every tick
// read `not_final`, forever, and the house held team colours until the base
// layer's next boundary. The app never had this hole: its liveGame fallback
// declares a game over at start + estimatedDuration + 60 min
// (game_day_autopilot_service.dart, "FALLBACK timer", `now.isAfter(...)`).
// The planner now ends the game at that same instant.
//
// Tick-level behaviour (hand-off, suppression, GUARD 0b, base restore) is in
// plannerHierarchy.test.js. Runs against compiled lib/ — `npm run build` first.

const {
  FALLBACK_END_BUFFER_MS,
  MIN_PLAUSIBLE_DURATION_MS,
  MIN_PLAUSIBLE_DURATION_DEFAULT_MS,
  decideEndSignal,
  estimatedDurationMs,
  fallbackEndMs,
} = require("../../lib/gameDayPlanning");
const { windowEndMs, ownerAt, outrankedBy } = require("../../lib/gameDayHierarchy");

const M = 60_000;
const H = 60 * M;
const T0 = Date.UTC(2026, 9, 4, 23, 0, 0); // 2026-10-04 18:00 CDT

// Every sport the app can configure (SportType), plus one it cannot.
const SPORTS = ["nfl", "ncaaFB", "mlb", "nba", "wnba", "ncaaMB", "nhl", "mls", "nwsl", "fifa", "championsLeague", "unknown_sport"];

// ---------------------------------------------------------------------------
// The bound
// ---------------------------------------------------------------------------
describe("fallbackEndMs — the app's fallback bound", () => {
  test("start + estimatedDuration + 60 min, the app's own buffer", () => {
    expect(FALLBACK_END_BUFFER_MS).toBe(60 * M);
    expect(fallbackEndMs(T0, "nfl")).toBe(T0 + 3.5 * H + H);
    expect(fallbackEndMs(T0, "mlb")).toBe(T0 + 3 * H + H);
    expect(fallbackEndMs(T0, "nhl")).toBe(T0 + 2.5 * H + H);
  });

  test("the hierarchy's 'still playing' window ends at the SAME instant, for every sport", () => {
    // A game must stop owning the house at the moment its capped end is due —
    // otherwise the owner check and the cap would disagree about who holds it.
    for (const s of SPORTS) {
      expect(windowEndMs(T0, s)).toBe(fallbackEndMs(T0, s));
      expect(fallbackEndMs(T0, s)).toBe(T0 + estimatedDurationMs(s) + FALLBACK_END_BUFFER_MS);
    }
  });

  test("the cap can never fire before GUARD 2's minimum plausible duration, for any sport", () => {
    for (const s of SPORTS) {
      const min = MIN_PLAUSIBLE_DURATION_MS[s] ?? MIN_PLAUSIBLE_DURATION_DEFAULT_MS;
      expect(fallbackEndMs(T0, s)).toBeGreaterThan(T0 + min);
    }
  });
});

// ---------------------------------------------------------------------------
// decideEndSignal — the cap, behind the guards that matter
// ---------------------------------------------------------------------------
describe("decideEndSignal — the hard cap", () => {
  const started = (o = {}) => ({ gameStartMs: T0, startPlannedAt: T0 - 30 * M, ...o });
  const BOUND = T0 + 3 * H + H; // mlb
  const decide = (nowMs, espnIsFinal = false, state = started()) =>
    decideEndSignal({ espnIsFinal, state, sport: "mlb", nowMs });

  test("ESPN never says final: nothing ends up to and AT the bound — strictly after, as the app's isAfter", () => {
    for (const t of [T0 + 2 * H, T0 + 3 * H, BOUND - 1, BOUND]) {
      const d = decide(t);
      expect(d.fireEnd).toBe(false);
      expect(d.reason).toBe("not_final");
      expect(d.nextConsecutive).toBe(0);
    }
  });

  test("the first instant past the bound ends the game: hard_cap", () => {
    const d = decide(BOUND + 1);
    expect(d).toEqual({ fireEnd: true, reason: "hard_cap", nextConsecutive: 0 });
  });

  test("and it stays capped on every later tick until the end is recorded", () => {
    for (const t of [BOUND + 5 * M, BOUND + 3 * H, BOUND + 48 * H]) {
      expect(decide(t).reason).toBe("hard_cap");
    }
  });

  test("GUARD 0 still comes first: a show this system did not start is never capped", () => {
    // #66 — ending a show we did not start is an unrequested lights-ON.
    const d = decide(BOUND + 10 * H, false, started({ startPlannedAt: undefined }));
    expect(d.fireEnd).toBe(false);
    expect(d.reason).toBe("no_start");
    expect(decide(BOUND + 10 * H, false, started({ startPlannedAt: null })).reason).toBe("no_start");
  });

  test("GUARD 3 still comes first: a recorded end is never capped again", () => {
    const d = decide(BOUND + 10 * H, false, started({ endFiredAt: T0 + 2 * H }));
    expect(d.fireEnd).toBe(false);
    expect(d.reason).toBe("already_fired");
  });

  test("no known game start → no cap; it refuses rather than assuming one", () => {
    const noStart = started({ gameStartMs: undefined });
    expect(decide(BOUND + 10 * H, false, noStart)).toMatchObject({ fireEnd: false, reason: "not_final" });
    expect(decide(BOUND + 10 * H, true, noStart)).toMatchObject({ fireEnd: false, reason: "no_game_start" });
  });

  test("a single final past the bound: capped, and the final count is carried, not reset", () => {
    const d = decide(BOUND + M, true);
    expect(d).toEqual({ fireEnd: true, reason: "hard_cap", nextConsecutive: 1 });
  });

  test("a confirmed final past the bound keeps ESPN's label — hard_cap names only unconfirmed ends", () => {
    const d = decide(BOUND + M, true, started({ consecutiveFinalPolls: 1 }));
    expect(d).toEqual({ fireEnd: true, reason: "confirmed_final", nextConsecutive: 2 });
  });

  test("inside the bound, the ESPN guards are exactly as before", () => {
    expect(decide(T0 + 3.5 * H, true).reason).toBe("awaiting_confirmation:1");
    expect(decide(T0 + 3.5 * H, true, started({ consecutiveFinalPolls: 1 })).reason).toBe("confirmed_final");
    expect(decide(T0 + 10 * M, true, started({ consecutiveFinalPolls: 1 })).reason).toMatch(/^too_early/);
  });

  test("the bound is per sport", () => {
    const at = (sport, t) =>
      decideEndSignal({ espnIsFinal: false, state: started(), sport, nowMs: t }).reason;
    expect(at("nfl", T0 + 4.5 * H)).toBe("not_final");
    expect(at("nfl", T0 + 4.5 * H + 1)).toBe("hard_cap");
    expect(at("nba", T0 + 3.5 * H)).toBe("not_final");
    expect(at("nba", T0 + 3.5 * H + 1)).toBe("hard_cap");
    // An NBA-length bound does not cap an NFL game early.
    expect(at("nfl", T0 + 3.5 * H + 1)).toBe("not_final");
  });

  test("the reason string is stable — the plan log buckets and counts on it", () => {
    expect(decide(BOUND + 1).reason.split(":")[0]).toBe("hard_cap");
  });
});

// ---------------------------------------------------------------------------
// outrankedBy — the END's ownership question, asked of the ending team
// ---------------------------------------------------------------------------

/** A lit, open, in-progress NFL window starting at T0 unless overridden. */
function win(over) {
  return Object.assign(
    {
      teamSlug: "t",
      eventId: "gd_t_1",
      rank: 0,
      order: 0,
      windowStartMs: T0 - 30 * M,
      gameStartMs: T0,
      windowEndMs: T0 + 3.5 * H + H,
      statusName: "STATUS_IN_PROGRESS",
      eligible: true,
      startPlanned: true,
      endFired: false,
    },
    over || {}
  );
}

describe("outrankedBy — does a lit team ABOVE this one still hold the house?", () => {
  const thunder = (o) => win({ teamSlug: "nba_thunder", eventId: "th", rank: 0, order: 0, ...o });
  const chiefs = (o) => win({ teamSlug: "nfl_chiefs", eventId: "ch", rank: 1, order: 1, ...o });

  test("the top lit team is outranked by nobody", () => {
    expect(outrankedBy([thunder(), chiefs()], thunder(), T0)).toBeNull();
  });

  test("a lower team is outranked by the lit higher team still playing", () => {
    const w = [thunder(), chiefs()];
    expect(outrankedBy(w, w[1], T0).eventId).toBe("th");
  });

  test("an UNLIT higher team does not outrank — its colours are not on the wire", () => {
    const w = [thunder({ startPlanned: false }), chiefs()];
    expect(outrankedBy(w, w[1], T0)).toBeNull();
  });

  test("a higher team whose window closed, or whose end fired, does not outrank", () => {
    expect(outrankedBy([thunder({ windowEndMs: T0 - 1 }), chiefs()], chiefs(), T0)).toBeNull();
    expect(outrankedBy([thunder({ endFired: true }), chiefs()], chiefs(), T0)).toBeNull();
    expect(outrankedBy([thunder({ statusName: "STATUS_POSTPONED" }), chiefs()], chiefs(), T0)).toBeNull();
  });

  test("THE CAP CASE: the #1's own window has closed, a LOWER lit team still plays — #1 is NOT outranked", () => {
    // Thunder (#1) capped at its bound; Chiefs (#2, lit before Thunder preempted)
    // still inside theirs. ownerAt no longer counts Thunder and names the
    // Chiefs — which would suppress Thunder's end and leave Thunder colours over
    // the Chiefs game. The ending team is asked directly instead.
    const now = T0 + 2 * H;
    const th = thunder({ windowEndMs: now - 1 });
    const w = [th, chiefs()];
    expect(ownerAt(w, now).eventId).toBe("ch");     // the question that was wrong here
    expect(outrankedBy(w, th, now)).toBeNull();      // the question that is asked now
  });

  test("whenever the ending team is itself open, it agrees exactly with `ownerAt(t) !== self`", () => {
    // Every pre-cap end: a confirmed final fires inside the window (the cap
    // takes the first tick after it). Same answer, same team named.
    const cases = [
      [thunder(), chiefs()],
      [thunder({ startPlanned: false }), chiefs()],
      [thunder({ endFired: true }), chiefs()],
      [thunder(), chiefs({ rank: 0, order: 1, windowStartMs: T0 - H })],
      [thunder({ rank: 2 }), chiefs(), win({ teamSlug: "x", eventId: "x", rank: 0, order: 2 })],
    ];
    for (const w of cases) {
      for (const self of w) {
        if (self.endFired || !self.startPlanned) continue; // never an ending team
        const o = ownerAt(w, T0);
        const viaOwner = o !== null && o.eventId !== self.eventId ? o.eventId : null;
        const viaSelf = outrankedBy(w, self, T0);
        expect(viaSelf === null ? null : viaSelf.eventId).toBe(viaOwner);
      }
    }
  });
});
