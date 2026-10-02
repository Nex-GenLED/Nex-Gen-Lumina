// espnClient — the ESPN slate fix (fix/gameday-espn-slate). Runs against
// compiled lib/ with `fetch` stubbed by URL; no network.
//
// Fixtures (support/espnFixtures.js) are ESPN's shapes as read 2026-10-02, with
// synthetic ids: the default (featured) scoreboard, the dated FBS slate, the
// FCS slate (which must never be requested), the single-game endpoint and the
// team document.

const E = require("../../lib/espnClient");
const { espnEvent, scoreboard, teamDoc, installFetchStub, BASE } = require("./support/espnFixtures");

const CFB = `${BASE}/football/college-football`;
const slateUrl = (date, group = "80") => `${CFB}/scoreboard?dates=${date}&groups=${group}&limit=300`;
// Saturday 2026-10-10, 18:00 CDT.
const NOW = Date.parse("2026-10-10T23:00:00Z");
const H = 3600_000;
const ceilingFootball = (g) => g.startMs + 6 * H;

let stub = null;
afterEach(() => {
  if (stub) stub.restore();
  stub = null;
});
const route = (fn) => {
  stub = installFetchStub(fn);
  return stub;
};

const ev = (id, home, away, startIso, state, name) => espnEvent({ id, startIso, home, away, state, name });

// ---------------------------------------------------------------------------
describe("the default scoreboard (pro sports, and college with the flag off) is unchanged", () => {
  test("fetchTeamGame: the bare scoreboard URL, first matching event, the same fields plus statusState", async () => {
    route((u) =>
      u === `${BASE}/football/nfl/scoreboard`
        ? {
            body: scoreboard([
              ev("1", "11", "12", "2026-10-11T17:00:00Z", "pre"),
              ev("2", "13", "901", "2026-10-11T20:25:00Z", "in"),
              ev("3", "901", "14", "2026-10-18T17:00:00Z", "pre"),
            ]),
          }
        : undefined
    );
    const g = await E.fetchTeamGame("nfl", "901");
    expect(stub.calls).toEqual([`${BASE}/football/nfl/scoreboard`]);
    expect(g).toEqual({
      gameId: "2",
      startMs: Date.parse("2026-10-11T20:25:00Z"),
      isFinal: false,
      isInProgress: true,
      statusName: "STATUS_IN_PROGRESS",
      statusState: "in",
      homeTeamId: "13",
      awayTeamId: "901",
    });
  });

  test("college football on the default list: the featured game is found, an unfeatured one is not (the defect)", async () => {
    route((u) =>
      u === `${CFB}/scoreboard`
        ? { body: scoreboard([ev("10", "801", "803", "2026-10-10T23:30:00Z", "pre")]) }
        : undefined
    );
    expect((await E.fetchTeamGame("ncaaFB", "801")).gameId).toBe("10");
    expect(await E.fetchTeamGame("ncaaFB", "802")).toBeNull();
  });

  test("HTTP error → null; a network failure throws (the planner counts it); unknown sport → no request", async () => {
    route(() => ({ status: 503, body: {} }));
    expect(await E.fetchTeamGame("nfl", "901")).toBeNull();
    stub.restore();
    route(() => ({ throws: true }));
    await expect(E.fetchTeamGame("nfl", "901")).rejects.toThrow("network down");
    stub.restore();
    route(() => undefined);
    expect(await E.fetchTeamGame("cricket", "1")).toBeNull();
    expect(await E.fetchTeamGame("nfl", "")).toBeNull();
    expect(stub.calls).toEqual([]);
  });

  test("an event without competitors is skipped, not fatal", async () => {
    route(() => ({ body: { events: [{ id: "x" }, { id: "y", competitions: [{}] }, ev("4", "901", "2", "2026-10-11T17:00:00Z")] } }));
    expect((await E.fetchTeamGame("nfl", "901")).gameId).toBe("4");
  });
});

// ---------------------------------------------------------------------------
describe("one fetch per URL per tick", () => {
  test("a shared cache: N readers of one URL → one request", async () => {
    route(() => ({ body: scoreboard([ev("1", "901", "902", "2026-10-11T17:00:00Z")]) }));
    const cache = new Map();
    await Promise.all(["901", "902", "903", "901"].map((t) => E.fetchTeamGame("nfl", t, cache)));
    await E.fetchTeamGame("nfl", "904", cache);
    expect(stub.calls).toHaveLength(1);
    expect(cache.size).toBe(1);
  });

  test("a network failure is shared too: every reader of that URL sees it, one request", async () => {
    route(() => ({ throws: true }));
    const cache = new Map();
    await expect(E.fetchTeamGame("nfl", "901", cache)).rejects.toThrow();
    await expect(E.fetchTeamGame("nfl", "902", cache)).rejects.toThrow();
    expect(stub.calls).toHaveLength(1);
  });

  test("without a cache every call requests (the pre-fix shape, kept for callers that pass none)", async () => {
    route(() => ({ body: scoreboard([]) }));
    await E.fetchTeamGame("nfl", "901");
    await E.fetchTeamGame("nfl", "902");
    expect(stub.calls).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
describe("the dated FBS slate", () => {
  test("ET yesterday / today / tomorrow, groups=80 only, limit 300 — FCS (81) is never requested", () => {
    expect(E.collegeSlateUrls(NOW)).toEqual([
      slateUrl("20261009"),
      slateUrl("20261010"),
      slateUrl("20261011"),
    ]);
    expect(E.collegeSlateUrls(NOW).some((u) => u.includes("groups=81"))).toBe(false);
  });

  test("dates are the ET calendar: 03:30Z Sunday is still Saturday in New York", () => {
    expect(E.etDateKey(Date.parse("2026-10-11T03:30:00Z"))).toBe("20261010");
    expect(E.etDateKey(Date.parse("2026-10-11T04:30:00Z"))).toBe("20261011");
    expect(E.collegeSlateDates(Date.parse("2026-10-11T03:30:00Z"))).toEqual(["20261009", "20261010", "20261011"]);
  });

  test("across the DST change and month / year ends the dates are still consecutive", () => {
    // 2026-11-01 is the US fall-back Sunday.
    expect(E.collegeSlateDates(Date.parse("2026-11-01T12:00:00Z"))).toEqual(["20261031", "20261101", "20261102"]);
    expect(E.collegeSlateDates(Date.parse("2027-01-01T03:00:00Z"))).toEqual(["20261230", "20261231", "20270101"]);
  });

  test("a Friday FBS game that is NOT on the default list is found on the slate", async () => {
    const friday = Date.parse("2026-10-09T18:00:00Z");
    route((u) => {
      if (u === slateUrl("20261009")) return { body: scoreboard([ev("20", "802", "804", "2026-10-10T00:00:00Z", "pre")]) };
      if (u.includes("/scoreboard?dates=")) return { body: scoreboard([]) };
      return undefined;
    });
    const r = await E.fetchCollegeSlateGame("802", friday, new Map(), ceilingFootball);
    expect(r).toMatchObject({ onSlate: true, complete: true });
    expect(r.game.gameId).toBe("20");
    expect(stub.calls).toEqual([slateUrl("20261008"), slateUrl("20261009"), slateUrl("20261010")]);
  });

  test("an FCS-vs-FCS game is ignored: it is not on the FBS slate, so its teams are not on it either", async () => {
    route((u) => {
      if (u === slateUrl("20261010", "81")) return { body: scoreboard([ev("30", "851", "852", "2026-10-10T22:00:00Z", "in")]) };
      if (u.includes("groups=80")) return { body: scoreboard([ev("31", "801", "803", "2026-10-10T23:30:00Z", "pre")]) };
      return undefined;
    });
    const r = await E.fetchCollegeSlateGame("851", NOW, new Map(), ceilingFootball);
    expect(r).toEqual({ game: null, onSlate: false, complete: true });
    expect(stub.calls.some((u) => u.includes("groups=81"))).toBe(false);
  });

  test("an FBS team playing an FCS opponent is on the FBS slate (as ESPN lists it)", async () => {
    route((u) =>
      u === slateUrl("20261010") ? { body: scoreboard([ev("32", "801", "851", "2026-10-10T23:45:00Z", "pre")]) } : { body: scoreboard([]) }
    );
    expect((await E.fetchCollegeSlateGame("801", NOW, new Map(), ceilingFootball)).game.gameId).toBe("32");
  });

  test("a failed date makes the read incomplete but keeps what the others found; all failed → throws", async () => {
    route((u) => (u === slateUrl("20261010") ? { status: 500, body: {} } : { body: scoreboard([]) }));
    expect(await E.fetchCollegeSlateGame("801", NOW, new Map(), ceilingFootball)).toEqual({ game: null, onSlate: false, complete: false });
    stub.restore();
    route(() => ({ throws: true }));
    await expect(E.fetchCollegeSlateGame("801", NOW, new Map(), ceilingFootball)).rejects.toThrow();
  });

  test("three reads, shared by every team on the slate", async () => {
    route(() => ({ body: scoreboard([ev("40", "801", "803", "2026-10-10T23:30:00Z"), ev("41", "802", "804", "2026-10-11T00:00:00Z")]) }));
    const cache = new Map();
    await E.fetchCollegeSlateGame("801", NOW, cache, ceilingFootball);
    await E.fetchCollegeSlateGame("802", NOW, cache, ceilingFootball);
    await E.fetchCollegeSlateGame("899", NOW, cache, ceilingFootball);
    expect(stub.calls).toHaveLength(3);
  });
});

// ---------------------------------------------------------------------------
describe("the pick — deterministic, whatever ESPN's order", () => {
  const g = (id, startIso, state, name) => E.parseEspnEvent(ev(id, "801", "803", startIso, state, name));
  const pick = (games, now = NOW) => E.pickCollegeGame(games, now, ceilingFootball);

  test("in progress beats scheduled beats final", () => {
    const fin = g("1", "2026-10-09T23:00:00Z", "post");
    const sch = g("2", "2026-10-11T00:00:00Z", "pre");
    const live = g("3", "2026-10-10T20:00:00Z", "in");
    for (const order of [[fin, sch, live], [live, fin, sch], [sch, live, fin]]) {
      expect(pick(order).gameId).toBe("3");
    }
    expect(pick([fin, sch]).gameId).toBe("2");
  });

  test("the SOONEST scheduled game, ties broken by game id", () => {
    const a = g("9", "2026-10-11T00:00:00Z", "pre");
    const b = g("5", "2026-10-10T23:30:00Z", "pre");
    const c = g("7", "2026-10-10T23:30:00Z", "pre");
    expect(pick([a, b, c]).gameId).toBe("5");
    expect(pick([c, a, b]).gameId).toBe("5");
  });

  test("a final only inside its end window (the football ceiling), the most recent first", () => {
    const old = g("1", "2026-10-09T17:00:00Z", "post");
    const recent = g("2", "2026-10-10T17:00:00Z", "post");
    expect(pick([old, recent], Date.parse("2026-10-10T22:59:00Z")).gameId).toBe("2"); // 17:00 + 6 h = 23:00
    expect(pick([old, recent], Date.parse("2026-10-10T23:00:01Z"))).toBeNull();
  });

  test("postponed / cancelled / suspended: the LAST tier, inside the end window only", () => {
    const pp = g("1", "2026-10-10T20:00:00Z", "post", "STATUS_POSTPONED");
    const cx = g("2", "2026-10-10T21:00:00Z", "post", "STATUS_CANCELED");
    // Suspended outranks `state: "in"` — no more play tonight.
    const sus = g("3", "2026-10-10T19:00:00Z", "in", "STATUS_SUSPENDED");
    expect(E.collegeTierOf(sus)).toBe("other");
    expect(pick([pp, cx, sus]).gameId).toBe("3"); // soonest
    expect(pick([pp, g("4", "2026-10-10T19:00:00Z", "post")]).gameId).toBe("4"); // a final in window first
    expect(pick([pp, g("6", "2026-10-09T17:00:00Z", "post")]).gameId).toBe("1"); // that final is out of window
    expect(pick([pp, g("5", "2026-10-11T00:00:00Z", "pre")]).gameId).toBe("5");
    // Out of window: 20:00Z + 6 h = 02:00Z.
    expect(pick([pp], Date.parse("2026-10-11T02:00:01Z"))).toBeNull();
  });

  test("a duplicate listing counts once", () => {
    const one = g("8", "2026-10-11T00:00:00Z", "pre");
    expect(pick([one, { ...one }]).gameId).toBe("8");
  });

  test("a feed without `state` falls back to the status names", () => {
    const noState = (id, name) => ({ ...g(id, "2026-10-10T23:00:00Z", "pre", name), statusState: "" });
    expect(E.collegeTierOf({ ...noState("1", "STATUS_IN_PROGRESS"), isInProgress: true })).toBe("live");
    expect(E.collegeTierOf(noState("2", "STATUS_SCHEDULED"))).toBe("scheduled");
    expect(E.collegeTierOf(noState("3", "STATUS_DELAYED"))).toBe("other");
  });
});

// ---------------------------------------------------------------------------
describe("one game by id (tracking)", () => {
  test("found: the event object itself; absent: 404; anything else: error (no claim)", async () => {
    const live = ev("401", "901", "902", "2026-10-11T00:15:00Z", "in", "STATUS_RAIN_DELAY");
    route((u) => {
      if (u === `${BASE}/football/nfl/scoreboard/401`) return { body: live };
      if (u === `${BASE}/football/nfl/scoreboard/402`) return { status: 404, body: { code: 404 } };
      if (u === `${BASE}/football/nfl/scoreboard/403`) return { status: 502, body: {} };
      if (u === `${BASE}/football/nfl/scoreboard/404`) return { body: ev("999", "1", "2", "2026-10-11T00:15:00Z") };
      if (u === `${BASE}/football/nfl/scoreboard/405`) return { throws: true };
      return undefined;
    });
    const c = new Map();
    const found = await E.fetchEventById("nfl", "401", c);
    expect(found.kind).toBe("found");
    expect(found.game).toMatchObject({ gameId: "401", statusName: "STATUS_RAIN_DELAY", statusState: "in", isFinal: false });
    expect(await E.fetchEventById("nfl", "402", c)).toEqual({ kind: "absent" });
    expect(await E.fetchEventById("nfl", "403", c)).toEqual({ kind: "error" });
    expect(await E.fetchEventById("nfl", "404", c)).toEqual({ kind: "error" }); // a different game
    expect(await E.fetchEventById("nfl", "405", c)).toEqual({ kind: "error" }); // network
    expect(await E.fetchEventById("cricket", "1", c)).toEqual({ kind: "error" });
  });
});

// ---------------------------------------------------------------------------
describe("is this id an FBS team at all (team_not_on_slate)", () => {
  test("parent group 80 → fbs; 81 → not_fbs; 400 → unknown_team; no field / 5xx / network → error", async () => {
    route((u) => {
      if (u === `${CFB}/teams/801`) return { body: teamDoc("801", "80") };
      if (u === `${CFB}/teams/851`) return { body: teamDoc("851", "81") };
      if (u === `${CFB}/teams/999999`) return { status: 400, body: { code: 400, message: "Failed to get league teams summary" } };
      if (u === `${CFB}/teams/7`) return { body: { team: { id: "7" } } };
      if (u === `${CFB}/teams/8`) return { status: 503, body: {} };
      if (u === `${CFB}/teams/9`) return { throws: true };
      return undefined;
    });
    const c = new Map();
    expect(await E.fetchCollegeTeamDivision("801", c)).toEqual({ kind: "fbs" });
    expect(await E.fetchCollegeTeamDivision("851", c)).toEqual({ kind: "not_fbs", group: "81" });
    expect(await E.fetchCollegeTeamDivision("999999", c)).toEqual({ kind: "unknown_team" });
    expect(await E.fetchCollegeTeamDivision("7", c)).toEqual({ kind: "error" });
    expect(await E.fetchCollegeTeamDivision("8", c)).toEqual({ kind: "error" });
    expect(await E.fetchCollegeTeamDivision("9", c)).toEqual({ kind: "error" });
  });
});
