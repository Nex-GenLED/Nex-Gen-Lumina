// A five-tick, four-account, three-sport planner scenario. NOT a test file.
//
// It exists for one property: with every ESPN flag OFF, the planner writes
// exactly what the pre-flag planner wrote. `plannerFlagsOffGolden.json` is this
// scenario's full Firestore state after every tick, captured from the base
// branch (fix/gameday-server-ab `d2e0f6e`) BEFORE any ESPN change was made. The
// flags-off test replays it on the current code and compares every document.
//
// The world (all ids synthetic, addresses RFC 5737):
//   u_alpha    allowlisted  nfl_alpha (901) #1, ncaa_falcon (801, on ESPN's default list) #2
//   u_bravo    NOT allowed  nfl_alpha (901), mlb_mariner (701) — log-only rows
//   u_charlie  allowlisted  ncaa_gator (802) — an FBS game NOT on the default list
//   u_delta    allowlisted  mlb_mariner (701) — a game that drops off the scoreboard
//
// ESPN over the evening (kickoffs: MLB 23:05Z, falcon 23:30Z, gator 00:00Z, NFL 00:15Z):
//   T1 17:50Z  all scheduled                                → starts mint
//   T2 00:30Z  all live
//   T3 03:30Z  falcon final #1; NFL live; MLB GONE from the scoreboard (its
//              03:05Z bound has passed — the pre-flag planner never caps it)
//   T4 03:35Z  falcon final #2 (its end yields to the NFL game, which outranks it)
//   T5 04:50Z  NFL still live, past its 04:45Z bound        → hard cap; MLB still gone
// Between T1 and T2 the dispatcher is modelled: every `_start` job → completed.

const { espnEvent, scoreboard, teamDoc, BASE } = require("./espnFixtures");

const T = {
  T1: Date.parse("2026-10-10T17:50:00Z"),
  T2: Date.parse("2026-10-11T00:30:00Z"),
  T3: Date.parse("2026-10-11T03:30:00Z"),
  T4: Date.parse("2026-10-11T03:35:00Z"),
  T5: Date.parse("2026-10-11T04:50:00Z"),
  // NOT in the golden (TICKS): past the football ceiling (00:15Z + 6 h) and
  // MLB's (23:05Z + 7 h), for the status-aware-cap tests. ESPN as at T5.
  T6: Date.parse("2026-10-11T06:20:00Z"),
};
const TICKS = ["T1", "T2", "T3", "T4", "T5"];

const KICK = {
  mlb: "2026-10-10T23:05:00Z",
  falcon: "2026-10-10T23:30:00Z",
  gator: "2026-10-11T00:00:00Z",
  nfl: "2026-10-11T00:15:00Z",
  fcs: "2026-10-10T22:00:00Z",
  featured: "2026-10-10T19:30:00Z",
};

const EV = {
  nfl: "9300001",
  mlb: "9300101",
  falcon: "9300201",
  gator: "9300202",
  featured: "9300203",
  fcs: "9300299",
};

const ALLOWLIST = ["u_alpha", "u_charlie", "u_delta"];

function teamConfig(slug, name, sport, espnId) {
  return {
    enabled: true,
    team_slug: slug,
    team_name: name,
    sport,
    espn_team_id: espnId,
    primary_color: 0xff123456,
    secondary_color: 0xff654321,
    effect_id: 52,
    speed: 160,
    intensity: 128,
    brightness: 200,
    design_mode: "fallback",
    design_variety: "rotating",
    skip_day_games: true,
  };
}

function seedAccount(f, uid, n, { configs, priority, bridge }) {
  f.put(`users/${uid}`, {
    owner_id: uid,
    latitude: 39.0,
    longitude: -95.0,
    game_day_team_priority: priority,
    gameday_gate_blocking: [],
  });
  f.put(`users/${uid}/controllers/ctrl_${uid}`, {
    ip: `192.0.2.${10 + n}`,
    participating_channels: [0, 1],
    participating_channels_device_ids: [0, 1],
    participating_channels_at: f.ts(T.T1 - 3 * 3600_000),
    base_ladder_asserts_segments: true,
  });
  for (const [slug, cfg] of Object.entries(configs)) {
    f.put(`users/${uid}/game_day_autopilot/${slug}`, cfg);
  }
  if (bridge) {
    f.put(`bridge_registry/BR_SYNTH_${n}`, { pairedUid: uid, status: "paired" });
    f.put(`users/${uid}/bridge_status/current`, { uptime: 1000, version: "1.2" });
  }
}

function seedWorld(f) {
  seedAccount(f, "u_alpha", 1, {
    configs: {
      nfl_alpha: teamConfig("nfl_alpha", "Alpha Team", "nfl", "901"),
      ncaa_falcon: teamConfig("ncaa_falcon", "Falcon College", "ncaaFB", "801"),
    },
    priority: ["nfl_alpha", "ncaa_falcon"],
    bridge: true,
  });
  seedAccount(f, "u_bravo", 2, {
    configs: {
      nfl_alpha: teamConfig("nfl_alpha", "Alpha Team", "nfl", "901"),
      mlb_mariner: teamConfig("mlb_mariner", "Mariner Club", "mlb", "701"),
    },
    priority: ["nfl_alpha", "mlb_mariner"],
    bridge: false,
  });
  seedAccount(f, "u_charlie", 3, {
    configs: { ncaa_gator: teamConfig("ncaa_gator", "Gator College", "ncaaFB", "802") },
    priority: ["ncaa_gator"],
    bridge: true,
  });
  seedAccount(f, "u_delta", 4, {
    configs: { mlb_mariner: teamConfig("mlb_mariner", "Mariner Club", "mlb", "701") },
    priority: ["mlb_mariner"],
    bridge: true,
  });
}

/** ESPN's status for each game at each tick. `null` = absent from the default scoreboard. */
const STATE = {
  T1: { nfl: "pre", mlb: "pre", falcon: "pre", gator: "pre" },
  T2: { nfl: "in", mlb: "in", falcon: "in", gator: "in" },
  T3: { nfl: "in", mlb: null, falcon: "post", gator: "in" },
  T4: { nfl: "in", mlb: null, falcon: "post", gator: "in" },
  T5: { nfl: "in", mlb: null, falcon: "post", gator: "post" },
  T6: { nfl: "in", mlb: null, falcon: "post", gator: "post" },
};

function events(tick) {
  const s = STATE[tick];
  const ev = (key, home, away) =>
    s[key] === null ? null : espnEvent({ id: EV[key], startIso: KICK[key], home, away, state: s[key] });
  return {
    nfl: ev("nfl", "901", "902"),
    mlb: ev("mlb", "701", "702"),
    falcon: ev("falcon", "801", "803"),
    gator: ev("gator", "802", "804"),
    featured: espnEvent({ id: EV.featured, startIso: KICK.featured, home: "805", away: "806", state: tick === "T1" ? "pre" : "post" }),
    fcs: espnEvent({ id: EV.fcs, startIso: KICK.fcs, home: "851", away: "852", state: tick === "T1" ? "pre" : "in" }),
  };
}

/**
 * The URL router for one tick. Default scoreboards for every sport; the FBS
 * dated slate for 2026-10-09..11 ET; the FCS slate (which an FBS-only reader
 * must never request); single-game lookups; team docs.
 */
function espnRoute(tick) {
  const e = events(tick);
  const live = (xs) => xs.filter((x) => x !== null);
  const byId = new Map(live(Object.values(e)).map((x) => [x.id, x]));
  // A game gone from the scoreboard is still answered by the single-game endpoint.
  if (e.mlb === null) {
    byId.set(EV.mlb, espnEvent({ id: EV.mlb, startIso: KICK.mlb, home: "701", away: "702", state: "in", name: "STATUS_RAIN_DELAY" }));
  }
  return (url) => {
    if (url === `${BASE}/football/nfl/scoreboard`) return { body: scoreboard(live([e.nfl])) };
    if (url === `${BASE}/baseball/mlb/scoreboard`) return { body: scoreboard(live([e.mlb])) };
    if (url === `${BASE}/football/college-football/scoreboard`) {
      // The default (featured) list: falcon and an unrelated game. Never gator.
      return { body: scoreboard(live([e.featured, e.falcon])) };
    }
    const m = /college-football\/scoreboard\?dates=(\d{8})&groups=(\d+)&limit=300$/.exec(url);
    if (m) {
      const [, date, group] = m;
      if (group === "81") return { body: scoreboard([e.fcs]) };
      if (date === "20261010") return { body: scoreboard(live([e.featured, e.falcon, e.gator])) };
      return { body: scoreboard([]) };
    }
    const one = /\/scoreboard\/(\d+)$/.exec(url);
    if (one) {
      const hit = byId.get(one[1]);
      return hit ? { body: hit } : { status: 404, body: { code: 404, message: "not found" } };
    }
    const team = /college-football\/teams\/(\d+)$/.exec(url);
    if (team) {
      const id = team[1];
      if (id === "851" || id === "852") return { body: teamDoc(id, "81") };
      if (/^8\d\d$/.test(id)) return { body: teamDoc(id, "80") };
      return { status: 400, body: { code: 400, message: "Failed to get league teams summary" } };
    }
    return undefined;
  };
}

/** Before a tick: the bridges heartbeat (fresh updateTime) as they would. */
function heartbeat(f) {
  for (const [n, uid] of [[1, "u_alpha"], [3, "u_charlie"], [4, "u_delta"]]) {
    void n;
    f.put(`users/${uid}/bridge_status/current`, { uptime: 1000, version: "1.2" });
  }
}

/** The dispatcher, modelled: every scheduled `_start` job completed. */
function completeStarts(f) {
  for (const [path, rec] of f.store.entries()) {
    if (/\/fire_jobs\/[^/]+_start$/.test(path) && rec.data.state === "scheduled") {
      f.patch(path, { state: "completed", outcome: "completed" });
    }
  }
}

function normalize(v) {
  if (v === null || v === undefined) return v;
  if (typeof v === "object" && typeof v.toMillis === "function") return { __ts: v.toMillis() };
  if (Array.isArray(v)) return v.map(normalize);
  if (typeof v === "object") {
    const out = {};
    for (const k of Object.keys(v).sort()) out[k] = normalize(v[k]);
    return out;
  }
  return v;
}

/**
 * Every document's data, normalised. `espnFetches` is stripped from the plan
 * log's tick summaries: it is the one key the ESPN change adds to the summary
 * (it did not exist before), and the flags-off test asserts it separately.
 */
function snapshot(f) {
  const out = {};
  for (const path of [...f.store.keys()].sort()) {
    const data = normalize(f.store.get(path).data);
    if (path.startsWith("gameday_plan_log/")) {
      if (Array.isArray(data.ticks)) data.ticks = data.ticks.map(({ espnFetches, ...rest }) => (void espnFetches, rest));
      if (data.lastSummary) {
        const { espnFetches, ...rest } = data.lastSummary;
        void espnFetches;
        data.lastSummary = rest;
      }
    }
    out[path] = data;
  }
  return out;
}

/** What changed between two snapshots: new or changed paths, and removed ones. */
function delta(prev, next) {
  const changed = {};
  for (const [p, d] of Object.entries(next)) {
    if (JSON.stringify(prev[p]) !== JSON.stringify(d)) changed[p] = d;
  }
  const removed = Object.keys(prev).filter((p) => !(p in next)).sort();
  return { changed, removed };
}

module.exports = {
  delta,
  seedAccount,
  teamConfig,
  T,
  TICKS,
  KICK,
  EV,
  ALLOWLIST,
  seedWorld,
  espnRoute,
  heartbeat,
  completeStarts,
  snapshot,
};
