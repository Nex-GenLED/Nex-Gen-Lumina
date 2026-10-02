// ESPN fixture builders + a URL-routed `fetch` stub. NOT a test file.
//
// The shapes are ESPN's public site API as read on 2026-10-02 (read-only GETs):
//   scoreboard            { events: [event] }
//   scoreboard/{eventId}  the event object itself (200), or 404 { code, message }
//   teams/{teamId}        { team: { id, groups: { id, parent: { id: "80"|"81" } } } },
//                         or 400 for an id ESPN does not know
// An event carries `status.type.{name,state,completed}` on the event AND on
// competitions[0]; the planner reads the competition's first.
//
// Every id here is synthetic. Team names are invented; no fixture is a copy of
// a real ESPN response.

function espnEvent({ id, startIso, home, away, state = "pre", name, completed }) {
  const statusName =
    name ??
    (state === "in" ? "STATUS_IN_PROGRESS" : state === "post" ? "STATUS_FINAL" : "STATUS_SCHEDULED");
  const status = {
    type: {
      name: statusName,
      state,
      completed: completed ?? (state === "post" && statusName === "STATUS_FINAL"),
    },
  };
  return {
    id: String(id),
    date: startIso,
    status,
    competitions: [
      {
        date: startIso,
        status,
        competitors: [
          { id: String(home), homeAway: "home", team: { abbreviation: `H${home}` } },
          { id: String(away), homeAway: "away", team: { abbreviation: `A${away}` } },
        ],
      },
    ],
  };
}

const scoreboard = (events) => ({ events });

function teamDoc(id, parentGroup) {
  return {
    team: {
      id: String(id),
      displayName: `Team ${id}`,
      groups: { id: "99", parent: { id: String(parentGroup) }, isConference: true },
    },
  };
}

const BASE = "https://site.api.espn.com/apis/site/v2/sports";

/**
 * Install a `global.fetch` stub. `route(url)` returns `{ status, body }`, or
 * `{ throws: true }` for a network failure (`{ throws: "AbortError" }` for the
 * client's 10 s timeout, which rejects fetch with that error name), or
 * undefined for a 404. Returns `{ calls, restore }`; `calls` is every URL
 * requested, in order.
 */
function installFetchStub(route) {
  const calls = [];
  const original = global.fetch;
  global.fetch = async (url) => {
    const u = String(url);
    calls.push(u);
    const r = route(u);
    if (r && r.throws) {
      const e = new Error(r.throws === "AbortError" ? "This operation was aborted (stub)" : "network down (stub)");
      if (typeof r.throws === "string") e.name = r.throws;
      throw e;
    }
    const status = r ? r.status ?? 200 : 404;
    const body = r ? r.body : { code: 404, message: "not found (stub)" };
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => JSON.parse(JSON.stringify(body)),
      text: async () => JSON.stringify(body),
    };
  };
  return {
    calls,
    restore: () => {
      global.fetch = original;
    },
  };
}

module.exports = { espnEvent, scoreboard, teamDoc, installFetchStub, BASE };
