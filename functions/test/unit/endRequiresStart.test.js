// INCIDENT #66 — an end for a start we never fired is an unrequested command.
//
// THE INCIDENT, verbatim from the watch:
//   05:45:21.359Z  config/gameday_planner armed, scoped to the bench uid
//   05:50:04Z      first armed tick — the writeJobs||startPlannedAt gate at
//                  planGameDayFires:499 opens; consecutiveFinalPolls 0 -> 1
//   05:55:04.001Z  counter -> 2, REQUIRED_FINAL_POLLS met,
//                  plan_end reason="confirmed_final"
//                  fire job gd_mlb_royals_401816490_end written and DISPATCHED,
//                  state=completed, payload {"ps":1} = preset "NGL On"
//   05:58:50Z      endsPlanned: 1
//   result         bench strip ON at 01:00 local, for a game finished hours
//                  earlier whose START this system never fired
//
// Every pre-existing guard passed HONESTLY: endFiredAt unset, ESPN final,
// gameStartMs known, well past minimum duration, two consecutive finals. None
// of them asked whether we started the show.
//
// Counterfactual, recorded because it is the reason the flip was scoped: under
// a GLOBAL arm this was a simultaneous 1am {"ps":1} across all ten
// Game-Day-enabled accounts, seven of which have no base layer.

const {
  decideEndSignal,
  startJobConfirmsFired,
  REQUIRED_FINAL_POLLS,
} = require('../../lib/gameDayPlanning');

// Real values from the incident.
const GAME_START_MS = 1786500600000;                 // session gameStartMs
const NOW = Date.parse('2026-08-12T05:55:04.001Z');  // the tick that fired
const ARMED_AT = Date.parse('2026-08-12T05:45:21.359Z');

/** The bench session as it actually was: everything set EXCEPT startPlannedAt. */
const staleSession = (over) => Object.assign({
  consecutiveFinalPolls: 1,   // about to become 2
  endFiredAt: undefined,
  gameStartMs: GAME_START_MS,
  startPlannedAt: undefined,  // log-only era: never written
}, over || {});

const decide = (state, nowMs) =>
  decideEndSignal({
    espnIsFinal: true,
    state,
    sport: 'mlb',
    nowMs: nowMs === undefined ? NOW : nowMs,
  });

const started = {
  startPlannedAt: ARMED_AT,
  gameStartMs: GAME_START_MS,
};

describe('#66 (a) — the bench incident, as a regression test', () => {
  test('the exact state that fired is now REFUSED with reason no_start', () => {
    const d = decide(staleSession());
    expect(d.fireEnd).toBe(false);
    expect(d.reason).toBe('no_start');
  });

  test('every OTHER guard still passes — proving no_start is what saves it', () => {
    // If this ever fails, some other guard started catching the case and the
    // regression value of the test above quietly disappears.
    const d = decide(staleSession({ startPlannedAt: ARMED_AT }));
    expect(d.fireEnd).toBe(true);
    expect(d.reason).toBe('confirmed_final');
  });

  test('no_start is checked BEFORE already_fired — a show we did not start is '
    + 'not ours to end, whatever else is true', () => {
    expect(decide(staleSession({ endFiredAt: NOW })).reason).toBe('no_start');
  });
});

describe('#66 (b) — a start created but never dispatched', () => {
  test('only dispatched/completed count as actually fired', () => {
    expect(startJobConfirmsFired('dispatched')).toBe(true);
    expect(startJobConfirmsFired('completed')).toBe(true);
  });

  test('missing, scheduled, failed, expired do NOT', () => {
    // A created-but-undispatched start leaves the house exactly as a
    // never-started one does.
    const bad = [undefined, null, 'scheduled', 'failed', 'expired', '', 'COMPLETED'];
    for (const st of bad) expect(startJobConfirmsFired(st)).toBe(false);
  });
});

describe('#66 (c) — a genuinely started show still ends', () => {
  test('startPlannedAt present + guards satisfied -> fireEnd', () => {
    expect(decide(staleSession({ startPlannedAt: ARMED_AT })).fireEnd).toBe(true);
  });

  test('the new guard does not bypass the existing ones', () => {
    expect(decideEndSignal({
      espnIsFinal: false,
      state: Object.assign({ consecutiveFinalPolls: 1 }, started),
      sport: 'mlb',
      nowMs: NOW,
    }).reason).toBe('not_final');

    expect(decide(Object.assign({ consecutiveFinalPolls: 1 }, started),
      GAME_START_MS + 60000).reason).toMatch(/^too_early/);

    expect(decide(Object.assign({ consecutiveFinalPolls: 0 }, started)).reason)
      .toBe('awaiting_confirmation:1');

    expect(decide(Object.assign({ consecutiveFinalPolls: 1, endFiredAt: NOW }, started)).reason)
      .toBe('already_fired');
  });
});

describe('#66 (d) — the ARMING TRANSITION, the thing that actually bit', () => {
  test('arm, then tick repeatedly against a stale finished game: ZERO end fires',
    () => {
      // Simulates :499 opening on arm — the counter now persists and climbs.
      // Before the guard this reached 2 and fired on the second tick.
      let session = staleSession({ consecutiveFinalPolls: 0 });
      const fired = [];
      for (let tick = 1; tick <= 10; tick++) {
        const d = decide(session);
        if (d.fireEnd) fired.push(tick);
        session = Object.assign({}, session, {
          consecutiveFinalPolls: d.nextConsecutive,
        });
      }
      expect(fired).toEqual([]);
      // The guard returns BEFORE the increment, so the counter freezes at 0
      // rather than climbing. Asserted explicitly because it is the opposite of
      // what I first assumed, and the difference matters: a frozen counter also
      // stops the pointless persisted write every tick, and it means the stale
      // session never even approaches the threshold.
      expect(session.consecutiveFinalPolls).toBe(0);
      expect(REQUIRED_FINAL_POLLS).toBe(2); // the threshold it never reaches
    });

  test('a stale session can never ACQUIRE startPlannedAt, so it never becomes '
    + 'eligible', () => {
    // startPlannedAt is only written beside a start-job create, and the start
    // path refuses a finished game on start_time_passed long before it would
    // write one. Nothing in the end path writes it. The refusal is permanent;
    // stale sessions age out when the event leaves the 6h horizon, not when a
    // counter re-trips.
    let session = staleSession({ consecutiveFinalPolls: 0 });
    for (let tick = 1; tick <= 50; tick++) {
      const d = decide(session);
      expect(d.fireEnd).toBe(false);
      session = Object.assign({}, session, {
        consecutiveFinalPolls: d.nextConsecutive,
      });
      expect(session.startPlannedAt).toBeUndefined();
    }
  });
});

describe('#66 (e) — the refusal is legible, not silent', () => {
  test('no_start is its own reason, distinct from every other refusal', () => {
    const reasons = new Set([
      decide(staleSession()).reason,
      decide(Object.assign({ consecutiveFinalPolls: 1, endFiredAt: NOW }, started)).reason,
      decideEndSignal({
        espnIsFinal: false,
        state: Object.assign({ consecutiveFinalPolls: 1 }, started),
        sport: 'mlb',
        nowMs: NOW,
      }).reason,
      decide(Object.assign({ consecutiveFinalPolls: 1 }, started), GAME_START_MS + 60000).reason,
      decide(Object.assign({ consecutiveFinalPolls: 0 }, started)).reason,
    ]);
    expect(reasons.has('no_start')).toBe(true);
    expect(reasons.size).toBe(5); // all distinct — the bucket can discriminate
  });

  test('the reason string is stable — the log bucket depends on it', () => {
    // planGameDayFires buckets on reason.split(":")[0] -> "end:no_start" and
    // pushes a logRow reason "end_skipped_no_start". A silent rename would make
    // the guard invisible in the corpus.
    expect(decide(staleSession()).reason).toBe('no_start');
    expect(decide(staleSession()).reason.split(':')[0]).toBe('no_start');
  });
});
