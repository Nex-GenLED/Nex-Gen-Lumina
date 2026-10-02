/**
 * espnClient — S5. Server-side ESPN scoreboard read.
 *
 * A PORT, not a new integration: the client already does exactly this
 * (lib/features/sports_alerts/services/espn_api_service.dart). The endpoint is
 * public and unauthenticated, so there is no key to provision and no quota to
 * negotiate — the same URL the app has been calling in production.
 *
 * Deliberately minimal. It answers two questions the planner needs — when does
 * this team next play, and is that game final — and nothing else.
 *
 * ─── THE SLATE FIX (2026-10-02, fix/gameday-espn-slate) ─────────────────────
 * The port dropped two things the app has. The app filters college football to
 * FBS with `groups=80` (sport_type.dart); this file read the bare scoreboard,
 * which for college football is ESPN's FEATURED list — 16 Saturday games in the
 * week it was found, none on a Friday. A team that is not featured never got a
 * start job. And the app follows a started game by its id
 * (`scoreboard/{gameId}`); this file only ever looked a game up through the
 * scoreboard, so a game ESPN dropped from the board after kickoff was never
 * ended or capped.
 *
 * Three additions, each behind its own `config/gameday_planner` flag in the
 * planner (all default OFF — with them off, every request and every answer is
 * what it was):
 *   - `fetchCollegeSlateGame` — the dated FBS scoreboards for ET yesterday,
 *     today and tomorrow, and a deterministic pick (`pickCollegeGame`).
 *   - `fetchEventById` — one game by id, for a session already started.
 *   - `fetchCollegeTeamDivision` — whether an id is FBS at all, so a config
 *     that can never appear on the FBS slate is named (`team_not_on_slate`)
 *     instead of reading as `no_game` forever.
 * And one that is not flagged, because it changes no answer: every request
 * goes through a per-tick URL cache (`EspnCache`), so a URL is fetched once per
 * tick however many accounts and teams read it.
 *
 * FBS ONLY (owner decision 2026-10-02). FCS (`groups=81`) is never requested.
 * An FBS team's game against an FCS opponent is on the FBS slate — read
 * 2026-10-02: the 10-03 FBS-vs-FCS game appears under both groups=80 and
 * groups=81 — so FBS-only loses no FBS team's game. Adding FCS is one entry in
 * COLLEGE_SLATE_GROUPS plus the division check, and an app catalog change.
 */

import { logger } from "firebase-functions";
import { CAP_RELEASE_STATUS_NAMES } from "./gameDayPlanning";

const ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports";

/** Sport → ESPN path segment. Mirrors the Dart SportType mapping. */
const ESPN_PATH: Record<string, string> = {
  nfl: "football/nfl",
  ncaaFB: "football/college-football",
  mlb: "baseball/mlb",
  nba: "basketball/nba",
  ncaaMB: "basketball/mens-college-basketball",
  wnba: "basketball/wnba",
  nhl: "hockey/nhl",
  mls: "soccer/usa.1",
  nwsl: "soccer/usa.nwsl",
  epl: "soccer/eng.1",
  fifa: "soccer/fifa.world",
  championsLeague: "soccer/uefa.champions",
};

export interface EspnGame {
  gameId: string;
  startMs: number;
  isFinal: boolean;
  isInProgress: boolean;
  statusName: string;
  /**
   * ESPN's `status.type.state`: "pre", "in" or "post"; "" when the feed omits
   * it. Read only by the flagged paths (the college pick, the status-aware cap).
   */
  statusState: string;
  homeTeamId: string;
  awayTeamId: string;
}

/** Network timeout. A slow ESPN must not hold a scheduled tick open. */
const TIMEOUT_MS = 10_000;

// ---------------------------------------------------------------------------
// One fetch per URL per tick
// ---------------------------------------------------------------------------

/** An HTTP status and, when the response was 2xx, its parsed body. */
export interface EspnResponse {
  status: number;
  json: unknown;
}

/**
 * The per-tick response cache. The planner makes one per tick and hands it to
 * every read, so each URL is requested once per tick, shared by every account.
 * The value is the request's promise, so a reader that arrives while a request
 * is in flight shares it. A network failure rejects the shared promise for
 * every reader of that URL — the same failure each would have had on its own,
 * and each still counts it.
 */
export type EspnCache = Map<string, Promise<EspnResponse>>;

function getJson(url: string, cache?: EspnCache): Promise<EspnResponse> {
  const hit = cache?.get(url);
  if (hit) return hit;
  const request = (async (): Promise<EspnResponse> => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    try {
      const res = await fetch(url, { signal: controller.signal });
      if (!res.ok) return { status: res.status, json: null };
      return { status: res.status, json: await res.json() };
    } finally {
      clearTimeout(timer);
    }
  })();
  cache?.set(url, request);
  return request;
}

// ---------------------------------------------------------------------------
// Parsing — PURE
// ---------------------------------------------------------------------------

type Obj = Record<string, unknown>;

/** The competitor ids of one scoreboard event, or null when it has no competitors. */
function competitorIds(ev: unknown): string[] | null {
  const comps = (ev as Obj | null)?.competitions;
  if (!Array.isArray(comps) || comps.length === 0) return null;
  const competitors = (comps[0] as Obj).competitors;
  if (!Array.isArray(competitors)) return null;
  return competitors.map((x) => String((x as Obj).id ?? ""));
}

/**
 * One ESPN event → EspnGame, or null when it is not an event (no competition,
 * no competitor list). Field for field what `fetchTeamGame` has always
 * returned, plus `statusState`.
 */
export function parseEspnEvent(ev: unknown): EspnGame | null {
  if (competitorIds(ev) === null) return null;
  const e = ev as Obj;
  const comp = (e.competitions as unknown[])[0] as Obj;
  const competitors = comp.competitors as unknown[];

  const status = (comp.status ?? e.status) as Obj | undefined;
  const typ = (status?.type ?? {}) as Obj;
  const name = String(typ.name ?? "");
  const startMs = Date.parse(String(e.date ?? comp.date ?? ""));

  const home = competitors.find((x) => (x as Obj).homeAway === "home") as Obj | undefined;
  const away = competitors.find((x) => (x as Obj).homeAway === "away") as Obj | undefined;

  return {
    gameId: String(e.id ?? ""),
    startMs: Number.isFinite(startMs) ? startMs : 0,
    // STATUS_FINAL is the canonical terminal value. `completed` is checked
    // alongside it because some feeds set the boolean before the name.
    isFinal: name === "STATUS_FINAL" || typ.completed === true,
    isInProgress: name === "STATUS_IN_PROGRESS" || name === "STATUS_HALFTIME",
    statusName: name,
    statusState: typeof typ.state === "string" ? typ.state : "",
    homeTeamId: String(home?.id ?? ""),
    awayTeamId: String(away?.id ?? ""),
  };
}

/**
 * The default-scoreboard rule: the FIRST event, in ESPN's order, whose
 * competitors include the team. Unchanged since S5 — the pro sports, and
 * college football with `espn_college_slate` off, still decide by it.
 */
export function findTeamGame(events: unknown, espnTeamId: string): EspnGame | null {
  if (!Array.isArray(events)) return null;
  for (const ev of events) {
    const ids = competitorIds(ev);
    if (ids === null || !ids.includes(espnTeamId)) continue;
    return parseEspnEvent(ev);
  }
  return null;
}

/**
 * Fetch the team's current/next game, or null.
 *
 * Returns null rather than throwing on a shape it does not recognise: an
 * unparseable ESPN response must skip a team for one tick, not fail the whole
 * planner run for every customer.
 */
export async function fetchTeamGame(
  sport: string,
  espnTeamId: string,
  cache?: EspnCache
): Promise<EspnGame | null> {
  const path = ESPN_PATH[sport];
  if (!path || !espnTeamId) return null;

  const res = await getJson(`${ESPN_BASE}/${path}/scoreboard`, cache);
  if (res.status < 200 || res.status >= 300) {
    logger.warn(`espnClient: HTTP ${res.status} for ${sport}`);
    return null;
  }
  return findTeamGame((res.json as { events?: unknown } | null)?.events, espnTeamId);
}

// ---------------------------------------------------------------------------
// College football — the dated FBS slate (flag `espn_college_slate`)
// ---------------------------------------------------------------------------

/** FBS. The only group read; see the FBS-ONLY note at the top of the file. */
export const COLLEGE_FBS_GROUP = "80";
export const COLLEGE_SLATE_GROUPS: readonly string[] = [COLLEGE_FBS_GROUP];
/**
 * A Saturday FBS slate is ~55 games; ESPN's own page size is far smaller and
 * a truncated slate would hide a team exactly as the featured list did.
 */
export const COLLEGE_SLATE_LIMIT = 300;
/** The calendar ESPN's college scoreboards are dated in. */
const ESPN_DATE_ZONE = "America/New_York";

/** "YYYYMMDD" for an instant, on the US Eastern calendar. */
export function etDateKey(ms: number): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: ESPN_DATE_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(ms));
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}${get("month")}${get("day")}`;
}

/**
 * ET yesterday, today and tomorrow. Yesterday catches a late game still being
 * played after midnight Eastern; tomorrow catches a start the 6-hour horizon
 * reaches across midnight. ESPN's date RANGE form returns nothing for college,
 * so each date is its own request.
 */
export function collegeSlateDates(nowMs: number): string[] {
  const today = etDateKey(nowMs);
  const y = Number(today.slice(0, 4));
  const m = Number(today.slice(4, 6));
  const d = Number(today.slice(6, 8));
  // Calendar arithmetic on the ET date itself, so a DST change cannot shift it.
  const key = (delta: number) => new Date(Date.UTC(y, m - 1, d + delta)).toISOString().slice(0, 10).replace(/-/g, "");
  return [key(-1), key(0), key(1)];
}

/** The slate's URLs: every date × every group, in that order. */
export function collegeSlateUrls(nowMs: number): string[] {
  const out: string[] = [];
  for (const date of collegeSlateDates(nowMs)) {
    for (const group of COLLEGE_SLATE_GROUPS) {
      out.push(
        `${ESPN_BASE}/${ESPN_PATH.ncaaFB}/scoreboard?dates=${date}&groups=${group}&limit=${COLLEGE_SLATE_LIMIT}`
      );
    }
  }
  return out;
}

/**
 * Which tier a game is in for the pick. `state` decides when ESPN sends it;
 * the names cover a feed that does not. "other" is everything that will not be
 * played tonight (postponed, cancelled, suspended) or that ESPN reports in a
 * shape not recognised here.
 */
export function collegeTierOf(g: EspnGame): "live" | "scheduled" | "final" | "other" {
  if (g.isFinal) return "final";
  if (CAP_RELEASE_STATUS_NAMES.has(g.statusName)) return "other";
  if (g.statusState === "in") return "live";
  if (g.statusState === "pre") return "scheduled";
  if (g.statusState === "") {
    if (g.isInProgress) return "live";
    if (g.statusName === "STATUS_SCHEDULED") return "scheduled";
  }
  return "other";
}

const byStartThenId = (a: EspnGame, b: EspnGame) =>
  a.startMs !== b.startMs ? a.startMs - b.startMs : a.gameId < b.gameId ? -1 : a.gameId > b.gameId ? 1 : 0;

/**
 * THE PICK, deterministic whatever order ESPN lists the slate in:
 *   1. a game in progress;
 *   2. else the soonest scheduled game;
 *   3. else a final still inside its end window (`finalWindowEndMs`), the most
 *      recent first — so the end path still sees the final it is counting;
 *   4. else a postponed / cancelled / suspended game inside the same window,
 *      the soonest first. Not in the approved plan's three tiers; added for
 *      parity with the default scoreboard, which keeps listing such a game. A
 *      game postponed AFTER its start was minted must still reach the end path
 *      (the shipped cap ends it at its bound); dropping it would leave the
 *      house in team colours whenever `track_started_by_id` is off;
 *   5. else nothing.
 * Ties break on start time, then game id. A game listed on two dates counts
 * once.
 */
export function pickCollegeGame(
  games: EspnGame[],
  nowMs: number,
  finalWindowEndMs: (g: EspnGame) => number
): EspnGame | null {
  const seen = new Set<string>();
  const unique = games.filter((g) => (seen.has(g.gameId) ? false : (seen.add(g.gameId), true)));
  const tier = (t: string) => unique.filter((g) => collegeTierOf(g) === t).sort(byStartThenId);
  const inWindow = (g: EspnGame) => nowMs <= finalWindowEndMs(g);
  const live = tier("live");
  if (live.length > 0) return live[0];
  const scheduled = tier("scheduled");
  if (scheduled.length > 0) return scheduled[0];
  const finals = tier("final").filter(inWindow);
  if (finals.length > 0) return finals[finals.length - 1];
  const other = tier("other").filter(inWindow);
  return other.length > 0 ? other[0] : null;
}

export interface CollegeSlateResult {
  /** The pick, or null. */
  game: EspnGame | null;
  /** The team's id is on the slate at all, in any state. */
  onSlate: boolean;
  /** Every slate request answered 2xx with an events array. */
  complete: boolean;
}

/**
 * The team's game from the dated FBS slate. A request that fails is skipped
 * (and makes the result incomplete); if EVERY request failed on the network,
 * the first failure is thrown, so the caller counts an ESPN error exactly as it
 * does for the default scoreboard.
 */
export async function fetchCollegeSlateGame(
  espnTeamId: string,
  nowMs: number,
  cache: EspnCache,
  finalWindowEndMs: (g: EspnGame) => number
): Promise<CollegeSlateResult> {
  const settled = await Promise.allSettled(collegeSlateUrls(nowMs).map((u) => getJson(u, cache)));
  if (settled.every((s) => s.status === "rejected")) {
    throw (settled[0] as PromiseRejectedResult).reason;
  }
  let complete = true;
  let onSlate = false;
  const games: EspnGame[] = [];
  for (const s of settled) {
    const events =
      s.status === "fulfilled" && s.value.status >= 200 && s.value.status < 300
        ? (s.value.json as { events?: unknown } | null)?.events
        : undefined;
    if (!Array.isArray(events)) {
      complete = false;
      continue;
    }
    for (const ev of events) {
      const ids = competitorIds(ev);
      if (ids === null || !ids.includes(espnTeamId)) continue;
      onSlate = true;
      const g = parseEspnEvent(ev);
      if (g) games.push(g);
    }
  }
  return { game: pickCollegeGame(games, nowMs, finalWindowEndMs), onSlate, complete };
}

export type TeamDivision =
  | { kind: "fbs" }
  | { kind: "not_fbs"; group: string }
  | { kind: "unknown_team" }
  | { kind: "error" };

/**
 * Is this college id an FBS team? ESPN's team document carries its conference
 * under `team.groups`, and the conference's parent is the division ("80" FBS,
 * "81" FCS). An id ESPN does not know answers 400 (404 is treated the same).
 * Anything else — a network failure, a 5xx, a document without the field — is
 * `error`: no claim is made either way. Never throws.
 */
export async function fetchCollegeTeamDivision(
  espnTeamId: string,
  cache: EspnCache
): Promise<TeamDivision> {
  try {
    const res = await getJson(
      `${ESPN_BASE}/${ESPN_PATH.ncaaFB}/teams/${encodeURIComponent(espnTeamId)}`,
      cache
    );
    if (res.status === 400 || res.status === 404) return { kind: "unknown_team" };
    if (res.status < 200 || res.status >= 300) return { kind: "error" };
    const groups = ((res.json as Obj | null)?.team as Obj | undefined)?.groups as Obj | undefined;
    const parent = (groups?.parent as Obj | undefined)?.id;
    if (typeof parent !== "string" || parent.length === 0) return { kind: "error" };
    return parent === COLLEGE_FBS_GROUP ? { kind: "fbs" } : { kind: "not_fbs", group: parent };
  } catch (err) {
    logger.warn(`espnClient: team lookup failed for ${espnTeamId}`, err);
    return { kind: "error" };
  }
}

// ---------------------------------------------------------------------------
// One game by id (flag `track_started_by_id`)
// ---------------------------------------------------------------------------

export type EventLookup =
  | { kind: "found"; game: EspnGame }
  /** ESPN answered 404: the game is gone. The planner's "ESPN went silent". */
  | { kind: "absent" }
  /** Anything else. No claim is made; the caller falls back to the scoreboard. */
  | { kind: "error" };

/**
 * One game by its ESPN id — the app's `scoreboard/{gameId}`. The response is
 * the event object itself. Never throws.
 */
export async function fetchEventById(
  sport: string,
  gameId: string,
  cache: EspnCache
): Promise<EventLookup> {
  const path = ESPN_PATH[sport];
  if (!path || !gameId) return { kind: "error" };
  try {
    const res = await getJson(`${ESPN_BASE}/${path}/scoreboard/${encodeURIComponent(gameId)}`, cache);
    if (res.status === 404) return { kind: "absent" };
    if (res.status < 200 || res.status >= 300) return { kind: "error" };
    const g = parseEspnEvent(res.json);
    // A body that is not this game is not evidence of anything.
    if (!g || g.gameId !== gameId) return { kind: "error" };
    return { kind: "found", game: g };
  } catch (err) {
    logger.warn(`espnClient: by-id lookup failed for ${sport}/${gameId}`, err);
    return { kind: "error" };
  }
}
