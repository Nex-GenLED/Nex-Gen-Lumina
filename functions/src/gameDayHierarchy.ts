/**
 * gameDayHierarchy — the user's team hierarchy, ported to the planner.
 *
 * PURE. No firebase-admin, no network. Mirrors
 *   lib/features/autopilot/game_day_priority_resolver.dart  (rules 2, 3, 5)
 *   lib/features/autopilot/team_priority.dart                (the rank heal)
 * so the server plans the same evening the app would run.
 *
 * WHY THIS EXISTS. Build +106 shipped the hierarchy in the APP only: the
 * ordered slug list `game_day_team_priority` decides which team's game owns the
 * house, a lower-ranked team whose game overlaps is DEFERRED (tracked, not lit),
 * and when the owner's game ends the house is HANDED OFF to the highest-ranked
 * team still playing rather than restored. planGameDayFires.ts read neither
 * priority field and planned every enabled team independently, each `_end`
 * base-restoring at its own final — so on the server path the first game to
 * finish put the house back to base part-way through the second. The +106
 * commit says so explicitly ("Server planner deliberately untouched").
 *
 * WHAT IS MIRRORED, AND WHAT THE SERVER HAS NO ANALOGUE FOR
 *   Rule 1  Neighborhood Sync wins the same game — NOT ported. The planner has
 *           no sync candidates; sync fan-out is a separate function.
 *   Rule 2  Team priority — ported. Lower index wins; unlisted ranks last.
 *   Rule 3  Equal rank → first-come-first-served — ported. The app stamps an
 *           activation instant; the server's analogue is the earlier lead
 *           window, then document-id order (the order both loops walk).
 *   Rule 5  Hand-off on end — ported. See `handoffWinner`.
 *   Phases  preGame / liveGame / postGame collapse to "the lead window has
 *           opened and the end has not fired". The app counts postGame as a
 *           hand-off candidate (its 30-minute wind-down is part of the show),
 *           so a team ESPN already reports final, whose end has not yet fired,
 *           is still a candidate here. Deliberate: the one genuinely bad
 *           outcome is a base restore mid-game on a glitched single `final`
 *           poll, and a survivor that then ends restores base itself.
 *   Bound   The app's liveGame fallback declares a game over at
 *           start + estimatedDuration + 60 min when no final ever arrives.
 *           `windowEndMs` is that bound; past it a team neither owns nor
 *           receives a hand-off. A postponed/cancelled game takes no part.
 *   Celebrations  the server has none (S5b unbuilt), so "only the owner
 *           celebrates" has nothing to gate. Recorded, not ported.
 *   Last team's end  the app turns the house OFF
 *           (onResumeNormalSchedule → togglePower(false)); the server restores
 *           BASE (baseRestorePayload). The server is right and is unchanged.
 */

import { DEFAULT_LEAD_MINUTES, fallbackEndMs } from "./gameDayPlanning";

// ---------------------------------------------------------------------------
// Lead time — DEFECT 2
// ---------------------------------------------------------------------------

/**
 * The app writes `lead_time_minutes_override`
 * (game_day_autopilot_config.dart toFirestore, providers.dart :1389). The
 * planner read `lead_time_minutes`, a field nothing writes, so every fire went
 * out at the 30-minute default whatever the user chose.
 *
 * Precedence: the override the app writes → the legacy field (kept so a
 * hand-written document still works) → DEFAULT_LEAD_MINUTES. A non-finite or
 * negative value falls through rather than producing a NaN fireAt. The app's
 * field is NOT renamed — it is mid-release and must not need a rebuild.
 */
export function leadMinutesFor(config: Record<string, unknown>): number {
  for (const key of ["lead_time_minutes_override", "lead_time_minutes"]) {
    const v = config[key];
    if (typeof v === "number" && Number.isFinite(v) && v >= 0) return v;
  }
  return DEFAULT_LEAD_MINUTES;
}

// ---------------------------------------------------------------------------
// Rank — the port of healGameDayTeamPriority
// ---------------------------------------------------------------------------

/** Case/whitespace-insensitive key for a team display name — `teamNameKey`. */
export function teamNameKey(name: string): string {
  return name.trim().toLowerCase();
}

const strings = (v: unknown): string[] =>
  Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];

/**
 * The ordered display-name list the app ranks from when the slug list is
 * empty: `sports_team_priority`, falling back to the unordered `sports_teams`
 * mirror exactly as `gameDayTeamPriorityProvider` does.
 */
export function profileNamesFrom(user: Record<string, unknown>): string[] {
  const ordered = strings(user.sports_team_priority);
  return ordered.length > 0 ? ordered : strings(user.sports_teams);
}

export interface TeamRow {
  /** Config document id — the slug. */
  slug: string;
  /** The config's own `team_name`, written from kTeamColors at creation. */
  teamName: string | null;
}

/**
 * Port of `healGameDayTeamPriority`, so an account that has not opened Game
 * Day since +106 (and so has no `game_day_team_priority` yet) ranks here
 * exactly as the app ranks it in memory.
 *
 * Rules, in order:
 *   1. stored slugs that still have a config, in stored order;
 *   2. profile names translated to slugs, in profile order, skipping ones
 *      already present — the app translates through kTeamColors; the server
 *      has no catalogue, so it matches the config document's own `team_name`,
 *      which the app wrote from that same catalogue;
 *   3. any remaining config, in the order given (document-id order).
 *
 * The result covers EVERY config, so `rankOf` never falls to "unlisted" for a
 * team that is actually enabled.
 */
export function deriveTeamPriority(args: {
  storedSlugs: unknown;
  profileNames: unknown;
  configs: TeamRow[];
}): string[] {
  const configSet = new Set(args.configs.map((c) => c.slug));
  const byName = new Map<string, string>();
  for (const c of args.configs) {
    if (!c.teamName) continue;
    const k = teamNameKey(c.teamName);
    if (!byName.has(k)) byName.set(k, c.slug);
  }
  const out: string[] = [];
  const seen = new Set<string>();
  const add = (slug: string | undefined) => {
    if (!slug) return;
    if (!configSet.has(slug)) return; // no config ⇒ nothing to rank
    if (seen.has(slug)) return;
    seen.add(slug);
    out.push(slug);
  };
  for (const s of strings(args.storedSlugs)) add(s);
  for (const n of strings(args.profileNames)) add(byName.get(teamNameKey(n)));
  for (const c of args.configs) add(c.slug);
  return out;
}

/** Rank in the list. Lower = higher priority. Unlisted ranks last. */
export function rankOf(slug: string, priority: string[]): number {
  const i = priority.indexOf(slug);
  return i === -1 ? priority.length : i;
}

/**
 * Port of `orderConfigsByPriority`: highest priority FIRST, stable.
 *
 * The planner walks the hierarchy, not document-id order, for the same reason
 * the app's evaluate loop does: the #1 team must plan first so a lower team
 * evaluated on the same tick sees it holding the house and defers, instead of
 * both planning starts and the later fire repainting the house.
 */
export function orderByPriority<T>(
  items: T[],
  priority: string[],
  slugOf: (t: T) => string
): T[] {
  return items
    .map((item, order) => ({ item, order, rank: rankOf(slugOf(item), priority) }))
    .sort((a, b) => a.rank - b.rank || a.order - b.order)
    .map((x) => x.item);
}

// ---------------------------------------------------------------------------
// Windows — one team's one game, as the planner sees it this tick
// ---------------------------------------------------------------------------

export interface TeamWindow {
  teamSlug: string;
  eventId: string;
  rank: number;
  /** Position in the hierarchy walk — the rule-3 tie-break of last resort. */
  order: number;
  /** startMs − lead: when this team's own start would fire. */
  windowStartMs: number;
  gameStartMs: number;
  /** startMs + estimatedDuration + 60 min: the app's fallback "game over". */
  windowEndMs: number;
  /** ESPN statusName. Postponed / cancelled games take no part. */
  statusName: string;
  /** False when this game will never be lit (daylight-only, skipped). */
  eligible: boolean;
  /**
   * `startPlannedAt` is set: this system wrote the team's start, or handed the
   * house to it. Lit, or about to be. Updated in memory as the tick proceeds.
   */
  startPlanned: boolean;
  /** `endFiredAt` is set. Updated in memory as the tick proceeds. */
  endFired: boolean;
}

/** ESPN statuses under which a game cannot own, block, or receive the house. */
export const DEAD_STATUSES: ReadonlySet<string> = new Set([
  "STATUS_POSTPONED",
  "STATUS_CANCELED",
  "STATUS_CANCELLED",
]);

/**
 * The app's fallback end: estimated duration plus a 60-minute buffer. The same
 * bound the hard cap fires at (`fallbackEndMs`), so a game stops owning the
 * house at the instant its capped end is due.
 */
export function windowEndMs(gameStartMs: number, sport: string): number {
  return fallbackEndMs(gameStartMs, sport);
}

/** "Still playing" at `t`: the lead window has opened and nothing has ended it. */
export function isOpenAt(w: TeamWindow, t: number): boolean {
  return (
    w.eligible &&
    !w.endFired &&
    !DEAD_STATUSES.has(w.statusName) &&
    w.windowStartMs <= t &&
    t < w.windowEndMs
  );
}

/** Rules 2 and 3: lower rank, then earlier window, then walk order. */
function outranks(a: TeamWindow, b: TeamWindow): boolean {
  if (a.rank !== b.rank) return a.rank < b.rank;
  if (a.windowStartMs !== b.windowStartMs) return a.windowStartMs < b.windowStartMs;
  return a.order < b.order;
}

/**
 * Who holds the house at `t` — the app's `ownsLights`, exactly one at a time.
 *
 * Only LIT windows compete (`startPlanned`). A team whose start was refused or
 * missed never put its design on the wire; letting it "own" would make a
 * lower team's end yield to it, and the previous colours would stay up until
 * the base layer's next boundary with nothing to correct them.
 */
export function ownerAt(windows: TeamWindow[], t: number): TeamWindow | null {
  let best: TeamWindow | null = null;
  for (const w of windows) {
    if (!isOpenAt(w, t) || !w.startPlanned) continue;
    if (best === null || outranks(w, best)) best = w;
  }
  return best;
}

/**
 * The END's ownership question: is a lit team that OUTRANKS `self` still
 * playing at `t`? Then `self`'s design is not what is on the house, and its end
 * must not touch it. Null means `self` holds the house and its end may hand
 * off or restore.
 *
 * Asked about `self` directly rather than through `ownerAt(t) === self`, and
 * the difference is the hard cap. The two agree whenever `self` is itself open
 * — every confirmed final, since `decideEndSignal` caps the first tick after
 * the bound. They disagree once `self`'s own window has closed: `ownerAt` no
 * longer counts it, so a LOWER lit team still playing would read as the owner
 * and the capped #1's end would be suppressed — its colours left over the #2
 * game with nothing to hand the house back. The app hands off there
 * (fallback → postGame → handoffWinner), and so does this.
 */
export function outrankedBy(
  windows: TeamWindow[],
  self: TeamWindow,
  t: number
): TeamWindow | null {
  let best: TeamWindow | null = null;
  for (const w of windows) {
    if (w.eventId === self.eventId) continue;
    if (!isOpenAt(w, t) || !w.startPlanned) continue;
    if (!outranks(w, self)) continue;
    if (best === null || outranks(w, best)) best = w;
  }
  return best;
}

export type StartDecision =
  | { defer: false }
  | { defer: true; to: TeamWindow };

/**
 * Rules 2 and 3 for a START — the app's `resolve()` for a candidate whose
 * window is opening. Does this team's start fire, or does it DEFER to a team
 * that will already hold the house at that moment?
 *
 * DEFERRED means: no start job. The team is tracked (its window and session
 * exist) so that a later hand-off can light it — the app's insight that
 * "deferral has to be a session, not an absence" — but its own design must
 * not go on the wire over the #1 team's.
 *
 * Only a LIT incumbent causes deferral, for the same reason `ownerAt` requires
 * it: deferring to a team that will never light leaves the house on base for
 * the whole of this team's game.
 *
 * Equal rank: the incumbent already planned, and its window opened at or
 * before this one's — it came first. That is rule 3 without a clock.
 */
export function startDecision(
  candidate: TeamWindow,
  windows: TeamWindow[]
): StartDecision {
  const t = candidate.windowStartMs;
  let incumbent: TeamWindow | null = null;
  for (const w of windows) {
    if (w.eventId === candidate.eventId) continue;
    if (!isOpenAt(w, t) || !w.startPlanned) continue;
    if (w.rank > candidate.rank) continue; // lower priority: this team preempts it
    if (incumbent === null || outranks(w, incumbent)) incumbent = w;
  }
  return incumbent ? { defer: true, to: incumbent } : { defer: false };
}

/**
 * RULE 5 — hand-off on end. The highest-priority team still playing at `t`,
 * excluding the one relinquishing. Null means nothing is left to hand off to,
 * and null is the ONLY case in which the planner may write a base restore.
 *
 * `startPlanned` is deliberately NOT required here, unlike `ownerAt`: a
 * survivor that was deferred, or that missed or was refused its own start, is
 * exactly the team the hand-off should now light.
 */
export function handoffWinner(
  windows: TeamWindow[],
  relinquishingEventId: string,
  t: number
): TeamWindow | null {
  let best: TeamWindow | null = null;
  for (const w of windows) {
    if (w.eventId === relinquishingEventId) continue;
    if (!isOpenAt(w, t)) continue;
    if (best === null || outranks(w, best)) best = w;
  }
  return best;
}
