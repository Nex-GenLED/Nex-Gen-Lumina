// Game Day hierarchy — the server half of +106, as pure functions.
//
// Mirrors lib/features/autopilot/game_day_priority_resolver.dart (rules 2, 3,
// 5) and team_priority.dart (healGameDayTeamPriority). The app-side tests these
// shadow: test/features/autopilot/game_day_priority_resolver_test.dart and
// team_priority_test.dart.
//
// Runs against compiled lib/ — `npm run build` first.

const {
  leadMinutesFor,
  teamNameKey,
  profileNamesFrom,
  deriveTeamPriority,
  rankOf,
  orderByPriority,
  windowEndMs,
  isOpenAt,
  ownerAt,
  startDecision,
  handoffWinner,
  DEAD_STATUSES,
} = require("../../lib/gameDayHierarchy");
const { DEFAULT_LEAD_MINUTES, estimatedDurationMs } = require("../../lib/gameDayPlanning");

const M = 60_000;
const H = 60 * M;
const T0 = Date.UTC(2026, 9, 4, 23, 0, 0); // 2026-10-04 18:00 CDT

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

// ---------------------------------------------------------------------------
// DEFECT 2 — lead time
// ---------------------------------------------------------------------------
describe("leadMinutesFor — the field the app actually writes", () => {
  test("lead_time_minutes_override is honoured", () => {
    expect(leadMinutesFor({ lead_time_minutes_override: 45 })).toBe(45);
  });

  test("override wins over the legacy field", () => {
    expect(leadMinutesFor({ lead_time_minutes_override: 45, lead_time_minutes: 20 })).toBe(45);
  });

  test("legacy lead_time_minutes still works when no override is set", () => {
    expect(leadMinutesFor({ lead_time_minutes: 20 })).toBe(20);
  });

  test("neither → the 30-minute default", () => {
    expect(leadMinutesFor({})).toBe(DEFAULT_LEAD_MINUTES);
    expect(DEFAULT_LEAD_MINUTES).toBe(30);
  });

  test("zero is a real choice, not a missing value", () => {
    expect(leadMinutesFor({ lead_time_minutes_override: 0 })).toBe(0);
  });

  test("garbage falls through rather than producing a NaN fireAt", () => {
    for (const bad of ["45", NaN, -5, null, undefined, Infinity, {}, []]) {
      expect(leadMinutesFor({ lead_time_minutes_override: bad, lead_time_minutes: 20 })).toBe(20);
      expect(leadMinutesFor({ lead_time_minutes_override: bad })).toBe(30);
    }
  });
});

// ---------------------------------------------------------------------------
// Rank — the port of healGameDayTeamPriority
// ---------------------------------------------------------------------------
describe("deriveTeamPriority — heal-on-read, server side", () => {
  const configs = [
    { slug: "mlb_royals", teamName: "Kansas City Royals" },
    { slug: "nfl_chiefs", teamName: "Kansas City Chiefs" },
  ];

  test("stored slugs come first, in stored order", () => {
    expect(
      deriveTeamPriority({ storedSlugs: ["nfl_chiefs", "mlb_royals"], profileNames: [], configs })
    ).toEqual(["nfl_chiefs", "mlb_royals"]);
  });

  test("THE REVIEWER-DEMO SHAPE: no slug list yet, names say Chiefs first, "
    + "doc-id order says Royals first — names win", () => {
    // 20 production accounts had no game_day_team_priority on 2026-09-22; the
    // app ranks them from sports_team_priority in memory. So must the server.
    expect(
      deriveTeamPriority({
        storedSlugs: undefined,
        profileNames: ["Kansas City Chiefs", "Kansas City Royals"],
        configs,
      })
    ).toEqual(["nfl_chiefs", "mlb_royals"]);
  });

  test("name matching is case- and whitespace-insensitive (teamNameKey)", () => {
    expect(teamNameKey("  Kansas City CHIEFS ")).toBe("kansas city chiefs");
    expect(
      deriveTeamPriority({ storedSlugs: [], profileNames: ["  kansas city CHIEFS "], configs })
    ).toEqual(["nfl_chiefs", "mlb_royals"]);
  });

  test("a stored slug with no config is dropped — nothing to rank", () => {
    expect(
      deriveTeamPriority({ storedSlugs: ["nhl_blues", "mlb_royals"], profileNames: [], configs })
    ).toEqual(["mlb_royals", "nfl_chiefs"]);
  });

  test("a legacy free-text name that matches no config is dropped", () => {
    expect(
      deriveTeamPriority({
        storedSlugs: [],
        profileNames: ["Kansas City Sporting Kansas City", "Kansas City Royals"],
        configs,
      })
    ).toEqual(["mlb_royals", "nfl_chiefs"]);
  });

  test("configs missing from both lists are appended in the order given", () => {
    const three = [...configs, { slug: "nhl_blues", teamName: "St. Louis Blues" }];
    expect(
      deriveTeamPriority({ storedSlugs: ["nfl_chiefs"], profileNames: [], configs: three })
    ).toEqual(["nfl_chiefs", "mlb_royals", "nhl_blues"]);
  });

  test("nothing set at all → document-id order, and the result covers every config", () => {
    const out = deriveTeamPriority({ storedSlugs: null, profileNames: null, configs });
    expect(out).toEqual(["mlb_royals", "nfl_chiefs"]);
    for (const c of configs) expect(rankOf(c.slug, out)).toBeLessThan(out.length);
  });

  test("duplicates collapse; malformed arrays are ignored", () => {
    expect(
      deriveTeamPriority({
        storedSlugs: ["nfl_chiefs", "nfl_chiefs", 42, null],
        profileNames: "Kansas City Royals",
        configs,
      })
    ).toEqual(["nfl_chiefs", "mlb_royals"]);
  });

  test("a config with no team_name still ranks (by document order)", () => {
    expect(
      deriveTeamPriority({
        storedSlugs: [],
        profileNames: ["Kansas City Chiefs"],
        configs: [{ slug: "mlb_royals", teamName: null }, { slug: "nfl_chiefs", teamName: "Kansas City Chiefs" }],
      })
    ).toEqual(["nfl_chiefs", "mlb_royals"]);
  });
});

describe("profileNamesFrom — the app's fallback from the ordered array to sports_teams", () => {
  test("ordered array preferred", () => {
    expect(profileNamesFrom({ sports_team_priority: ["A", "B"], sports_teams: ["B", "A"] }))
      .toEqual(["A", "B"]);
  });
  test("empty ordered array → sports_teams", () => {
    expect(profileNamesFrom({ sports_team_priority: [], sports_teams: ["B", "A"] }))
      .toEqual(["B", "A"]);
  });
  test("nothing → empty", () => {
    expect(profileNamesFrom({})).toEqual([]);
    expect(profileNamesFrom({ sports_team_priority: "oops" })).toEqual([]);
  });
});

describe("rankOf / orderByPriority", () => {
  test("unlisted ranks last", () => {
    expect(rankOf("x", ["a", "b"])).toBe(2);
    expect(rankOf("a", ["a", "b"])).toBe(0);
  });

  test("orderByPriority puts #1 first and is stable for the unranked tail", () => {
    const items = ["c", "b", "d", "a"];
    expect(orderByPriority(items, ["a", "b"], (s) => s)).toEqual(["a", "b", "c", "d"]);
  });
});

// ---------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------
describe("windowEndMs / isOpenAt — the app's fallback bound and the dead statuses", () => {
  test("windowEnd = start + estimated duration + 60 min, per sport", () => {
    expect(windowEndMs(T0, "nfl")).toBe(T0 + estimatedDurationMs("nfl") + H);
    expect(windowEndMs(T0, "mlb")).toBe(T0 + 3 * H + H);
    expect(windowEndMs(T0, "nba")).toBe(T0 + 2.5 * H + H);
  });

  test("open between windowStart (inclusive) and windowEnd (exclusive)", () => {
    const w = win();
    expect(isOpenAt(w, w.windowStartMs - 1)).toBe(false);
    expect(isOpenAt(w, w.windowStartMs)).toBe(true);
    expect(isOpenAt(w, w.windowEndMs - 1)).toBe(true);
    expect(isOpenAt(w, w.windowEndMs)).toBe(false);
  });

  test("an ended, ineligible, postponed or cancelled window is never open", () => {
    expect(isOpenAt(win({ endFired: true }), T0)).toBe(false);
    expect(isOpenAt(win({ eligible: false }), T0)).toBe(false);
    for (const s of DEAD_STATUSES) expect(isOpenAt(win({ statusName: s }), T0)).toBe(false);
    expect(DEAD_STATUSES.has("STATUS_POSTPONED")).toBe(true);
    expect(DEAD_STATUSES.has("STATUS_CANCELED")).toBe(true);
  });

  test("an UNLIT window is still open — being lit is a separate question", () => {
    expect(isOpenAt(win({ startPlanned: false }), T0)).toBe(true);
  });

  test("ESPN reporting final does NOT close the window — the end firing does", () => {
    // The app counts postGame as a candidate; a glitched single `final` poll
    // must not be able to strip a live team of the house.
    expect(isOpenAt(win({ statusName: "STATUS_FINAL" }), T0)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// ownerAt — ownsLights
// ---------------------------------------------------------------------------
describe("ownerAt — exactly one team holds the house", () => {
  test("the highest-ranked lit open window owns", () => {
    const chiefs = win({ teamSlug: "nfl_chiefs", eventId: "c", rank: 0 });
    const royals = win({ teamSlug: "mlb_royals", eventId: "r", rank: 1 });
    expect(ownerAt([royals, chiefs], T0).teamSlug).toBe("nfl_chiefs");
  });

  test("REVERSING the hierarchy reverses the owner, same windows", () => {
    const chiefs = win({ teamSlug: "nfl_chiefs", eventId: "c", rank: 1 });
    const royals = win({ teamSlug: "mlb_royals", eventId: "r", rank: 0 });
    expect(ownerAt([royals, chiefs], T0).teamSlug).toBe("mlb_royals");
  });

  test("an UNLIT #1 does not own — its colours are not on the wire", () => {
    const chiefs = win({ teamSlug: "nfl_chiefs", eventId: "c", rank: 0, startPlanned: false });
    const royals = win({ teamSlug: "mlb_royals", eventId: "r", rank: 1 });
    expect(ownerAt([chiefs, royals], T0).teamSlug).toBe("mlb_royals");
  });

  test("nobody lit and open → null", () => {
    expect(ownerAt([win({ startPlanned: false })], T0)).toBeNull();
    expect(ownerAt([win({ endFired: true })], T0)).toBeNull();
    expect(ownerAt([], T0)).toBeNull();
  });

  test("equal rank → earlier window (first-come), then walk order", () => {
    const a = win({ eventId: "a", order: 1, windowStartMs: T0 - 60 * M });
    const b = win({ eventId: "b", order: 0, windowStartMs: T0 - 30 * M });
    expect(ownerAt([b, a], T0).eventId).toBe("a");
    const c = win({ eventId: "c", order: 0, windowStartMs: T0 - 60 * M });
    expect(ownerAt([a, c], T0).eventId).toBe("c");
  });
});

// ---------------------------------------------------------------------------
// startDecision — rules 2 and 3 for a START
// ---------------------------------------------------------------------------
describe("startDecision — defer to a lit higher (or first-come) incumbent", () => {
  const chiefs = (o) => win(Object.assign({ teamSlug: "nfl_chiefs", eventId: "c", rank: 0 }, o));
  const royals = (o) => win(Object.assign({ teamSlug: "mlb_royals", eventId: "r", rank: 1 }, o));

  test("the lower team's window opening inside the #1 team's game DEFERS", () => {
    const c = chiefs({ windowStartMs: T0 - 30 * M });
    const r = royals({ windowStartMs: T0 + 30 * M, gameStartMs: T0 + H });
    const d = startDecision(r, [c, r]);
    expect(d.defer).toBe(true);
    expect(d.to.teamSlug).toBe("nfl_chiefs");
  });

  test("the #1 team never defers to a lower one — it preempts on the wire", () => {
    const r = royals({ windowStartMs: T0 - 30 * M });
    const c = chiefs({ windowStartMs: T0 + 30 * M, gameStartMs: T0 + H });
    expect(startDecision(c, [r, c])).toEqual({ defer: false });
  });

  test("no deferral to an UNLIT higher team — that would leave the house on base", () => {
    const c = chiefs({ windowStartMs: T0 - 30 * M, startPlanned: false });
    const r = royals({ windowStartMs: T0 + 30 * M });
    expect(startDecision(r, [c, r])).toEqual({ defer: false });
  });

  test("no deferral when the higher team's window has not opened yet", () => {
    const c = chiefs({ windowStartMs: T0 + 2 * H, gameStartMs: T0 + 2.5 * H });
    const r = royals({ windowStartMs: T0 - 30 * M });
    expect(startDecision(r, [c, r])).toEqual({ defer: false });
  });

  test("no deferral when the higher team's game is over by the fallback bound", () => {
    const c = chiefs({ windowStartMs: T0 - 8 * H, gameStartMs: T0 - 7.5 * H, windowEndMs: T0 - 3 * H });
    const r = royals({ windowStartMs: T0 - 30 * M });
    expect(startDecision(r, [c, r])).toEqual({ defer: false });
  });

  test("no deferral to a postponed or ended higher team", () => {
    const r = royals({ windowStartMs: T0 - 30 * M });
    expect(startDecision(r, [chiefs({ statusName: "STATUS_POSTPONED" }), r])).toEqual({ defer: false });
    expect(startDecision(r, [chiefs({ endFired: true }), r])).toEqual({ defer: false });
  });

  test("equal rank: the one already holding the house wins (rule 3)", () => {
    const a = win({ eventId: "a", rank: 0, windowStartMs: T0 - 30 * M, startPlanned: true });
    const b = win({ eventId: "b", rank: 0, windowStartMs: T0, startPlanned: false });
    const d = startDecision(b, [a, b]);
    expect(d.defer).toBe(true);
    expect(d.to.eventId).toBe("a");
  });

  test("the highest incumbent is named when several are lit", () => {
    const a = win({ eventId: "a", rank: 0, windowStartMs: T0 - H });
    const b = win({ eventId: "b", rank: 1, windowStartMs: T0 - 30 * M });
    const c = win({ eventId: "c", rank: 2, windowStartMs: T0, startPlanned: false });
    expect(startDecision(c, [a, b, c]).to.eventId).toBe("a");
  });

  test("a lone team activates", () => {
    expect(startDecision(win(), [win()])).toEqual({ defer: false });
  });
});

// ---------------------------------------------------------------------------
// handoffWinner — rule 5
// ---------------------------------------------------------------------------
describe("handoffWinner — the house goes to the highest team still playing, or to base", () => {
  const chiefs = (o) => win(Object.assign({ teamSlug: "nfl_chiefs", eventId: "c", rank: 0 }, o));
  const royals = (o) => win(Object.assign({ teamSlug: "mlb_royals", eventId: "r", rank: 1 }, o));
  const blues = (o) => win(Object.assign({ teamSlug: "nhl_blues", eventId: "b", rank: 2 }, o));

  test("THE CASE THAT MATTERS: the winner ends, the other is still live → hand off, not base", () => {
    const r = royals({ startPlanned: false }); // deferred, never lit
    expect(handoffWinner([chiefs(), r], "c", T0 + 3 * H).teamSlug).toBe("mlb_royals");
  });

  test("nobody left → null, the ONLY case in which base may be restored", () => {
    expect(handoffWinner([chiefs()], "c", T0)).toBeNull();
    expect(handoffWinner([chiefs(), royals({ endFired: true })], "c", T0)).toBeNull();
  });

  test("picks the HIGHEST-priority survivor, not the next in some other order", () => {
    const r = royals({ startPlanned: false });
    const b = blues({ startPlanned: false });
    expect(handoffWinner([b, chiefs(), r], "c", T0).teamSlug).toBe("mlb_royals");
  });

  test("the relinquishing team is never its own successor", () => {
    expect(handoffWinner([chiefs()], "c", T0)).toBeNull();
  });

  test("an UNLIT survivor counts — that is who the hand-off is for", () => {
    expect(handoffWinner([chiefs(), royals({ startPlanned: false })], "c", T0).teamSlug)
      .toBe("mlb_royals");
  });

  test("a survivor ESPN already reports final still takes the house (app: postGame counts)", () => {
    // It then restores base itself once its own end confirms. Deliberate — see
    // the module header: a glitched single `final` must not restore base
    // mid-game.
    expect(handoffWinner([chiefs(), royals({ statusName: "STATUS_FINAL" })], "c", T0).teamSlug)
      .toBe("mlb_royals");
  });

  test("a postponed, cancelled, ended, or out-of-window team is not a survivor", () => {
    expect(handoffWinner([chiefs(), royals({ statusName: "STATUS_POSTPONED" })], "c", T0)).toBeNull();
    expect(handoffWinner([chiefs(), royals({ statusName: "STATUS_CANCELED" })], "c", T0)).toBeNull();
    expect(handoffWinner([chiefs(), royals({ endFired: true })], "c", T0)).toBeNull();
    expect(handoffWinner([chiefs(), royals({ windowStartMs: T0 + H })], "c", T0)).toBeNull();
    expect(handoffWinner([chiefs(), royals({ windowEndMs: T0 - 1 })], "c", T0)).toBeNull();
    expect(handoffWinner([chiefs(), royals({ eligible: false })], "c", T0)).toBeNull();
  });

  test("equal rank → earliest window, then walk order", () => {
    const a = win({ eventId: "a", rank: 1, order: 1, windowStartMs: T0 - H });
    const b = win({ eventId: "b", rank: 1, order: 0, windowStartMs: T0 - 30 * M });
    expect(handoffWinner([chiefs(), b, a], "c", T0).eventId).toBe("a");
  });
});
