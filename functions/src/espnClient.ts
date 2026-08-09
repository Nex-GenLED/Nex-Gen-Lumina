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
 */

import { logger } from "firebase-functions";

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
  homeTeamId: string;
  awayTeamId: string;
}

/** Network timeout. A slow ESPN must not hold a scheduled tick open. */
const TIMEOUT_MS = 10_000;

/**
 * Fetch the team's current/next game, or null.
 *
 * Returns null rather than throwing on a shape it does not recognise: an
 * unparseable ESPN response must skip a team for one tick, not fail the whole
 * planner run for every customer.
 */
export async function fetchTeamGame(
  sport: string,
  espnTeamId: string
): Promise<EspnGame | null> {
  const path = ESPN_PATH[sport];
  if (!path || !espnTeamId) return null;

  const url =
    `https://site.api.espn.com/apis/site/v2/sports/${path}/scoreboard`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let json: unknown;
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) {
      logger.warn(`espnClient: HTTP ${res.status} for ${sport}`);
      return null;
    }
    json = await res.json();
  } finally {
    clearTimeout(timer);
  }

  const events = (json as { events?: unknown })?.events;
  if (!Array.isArray(events)) return null;

  for (const ev of events) {
    const e = ev as Record<string, unknown>;
    const comps = e.competitions;
    if (!Array.isArray(comps) || comps.length === 0) continue;
    const comp = comps[0] as Record<string, unknown>;
    const competitors = comp.competitors;
    if (!Array.isArray(competitors)) continue;

    const ids = competitors.map((x) =>
      String((x as Record<string, unknown>).id ?? "")
    );
    if (!ids.includes(espnTeamId)) continue;

    const status = (comp.status ?? e.status) as Record<string, unknown> | undefined;
    const typ = (status?.type ?? {}) as Record<string, unknown>;
    const name = String(typ.name ?? "");
    const startMs = Date.parse(String(e.date ?? comp.date ?? ""));

    const home = competitors.find(
      (x) => (x as Record<string, unknown>).homeAway === "home"
    ) as Record<string, unknown> | undefined;
    const away = competitors.find(
      (x) => (x as Record<string, unknown>).homeAway === "away"
    ) as Record<string, unknown> | undefined;

    return {
      gameId: String(e.id ?? ""),
      startMs: Number.isFinite(startMs) ? startMs : 0,
      // STATUS_FINAL is the canonical terminal value. `completed` is checked
      // alongside it because some feeds set the boolean before the name.
      isFinal: name === "STATUS_FINAL" || typ.completed === true,
      isInProgress: name === "STATUS_IN_PROGRESS" || name === "STATUS_HALFTIME",
      statusName: name,
      homeTeamId: String(home?.id ?? ""),
      awayTeamId: String(away?.id ?? ""),
    };
  }
  return null;
}
