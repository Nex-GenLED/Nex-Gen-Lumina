// write_jobs policy — the allowlist that makes a SCOPED flip possible.
//
// Motivation, verbatim from the §7.2d / S5 log audit (2026-08-12) that blocked
// the global flip:
//
//   F1 — the end-fire path has never planned and CANNOT in log-only mode.
//        startPlannedAt is written only inside `if (writeJobs)`, and the
//        consecutive-final counter only persists when
//        `writeJobs || session.startPlannedAt`, so in log-only mode
//        consecutiveFinalPolls never advances past 1 and REQUIRED_FINAL_POLLS=2
//        is never reached. endsPlanned is 0 in the entire corpus, by
//        construction. The end path first executes in production.
//   F2 — the flip drives a real customer immediately, not just the bench:
//        ecochran08@yahoo.com had a plan_start row for the same event.
//   F3 — that customer has NO base layer (0 schedules), so if the never-yet-run
//        end fire fails there is no everyday boundary to reclaim the house.
//        Census: 7 of 10 Game-Day-enabled accounts are in that state.
//
// The allowlist lets the end path execute exactly once, on the bench, with a
// floor underneath it, instead of on seven no-floor customers at once.

const {
  writeJobsPolicyFrom,
  writesJobsFor,
  WRITE_JOBS_OFF,
} = require('../../lib/planGameDayFires');

const BENCH = 'wrQRUUKyXyc0deyuu0ORS6wsovO2';
const ELLIE = '5oHhaEaf6icmK2RlOWQMkESAXUG3';

describe('writeJobsPolicyFrom — the five shapes, fail-safe in every direction', () => {
  test('doc absent / undefined data -> OFF', () => {
    expect(writeJobsPolicyFrom(undefined)).toEqual(WRITE_JOBS_OFF);
    expect(writeJobsPolicyFrom({})).toEqual(WRITE_JOBS_OFF);
  });

  test('write_jobs !== true -> OFF regardless of any allowlist', () => {
    // A list present with the flag off must never arm anything.
    expect(writeJobsPolicyFrom({ write_jobs: false, uid_allowlist: [BENCH] }))
      .toEqual(WRITE_JOBS_OFF);
    expect(writeJobsPolicyFrom({ write_jobs: 'true', uid_allowlist: [BENCH] }))
      .toEqual(WRITE_JOBS_OFF);
    expect(writeJobsPolicyFrom({ write_jobs: 1 })).toEqual(WRITE_JOBS_OFF);
  });

  test('write_jobs true + list present -> armed for those uids ONLY', () => {
    const p = writeJobsPolicyFrom({ write_jobs: true, uid_allowlist: [BENCH] });
    expect(p.enabled).toBe(true);
    expect(p.allowlist).toEqual([BENCH]);
  });

  test('write_jobs true + list absent -> GLOBAL', () => {
    expect(writeJobsPolicyFrom({ write_jobs: true }))
      .toEqual({ enabled: true, allowlist: null });
    expect(writeJobsPolicyFrom({ write_jobs: true, uid_allowlist: null }))
      .toEqual({ enabled: true, allowlist: null });
  });

  test('MALFORMED allowlist -> OFF, not global', () => {
    // The important direction. Somebody who wrote uid_allowlist INTENDED to
    // scope the flip; if it does not parse, treating it as "global" turns a
    // typo into a fleet-wide arm across seven no-floor accounts (F3).
    for (const bad of [
      'wrQRUUKy...',            // string, not array
      { 0: BENCH },             // object
      [BENCH, 42],              // non-string member
      [BENCH, null],
      [BENCH, ''],              // empty uid matches nobody but signals a mistake
      123,
    ]) {
      expect(writeJobsPolicyFrom({ write_jobs: true, uid_allowlist: bad }))
        .toEqual(WRITE_JOBS_OFF);
    }
  });

  test('an EMPTY array is deliberate "armed for nobody", NOT malformed', () => {
    const p = writeJobsPolicyFrom({ write_jobs: true, uid_allowlist: [] });
    expect(p.enabled).toBe(true);
    expect(p.allowlist).toEqual([]);
    expect(writesJobsFor(p, BENCH)).toBe(false);
  });
});

describe('writesJobsFor — per-uid arming', () => {
  test('OFF arms nobody', () => {
    expect(writesJobsFor(WRITE_JOBS_OFF, BENCH)).toBe(false);
  });

  test('global arms everybody', () => {
    const p = { enabled: true, allowlist: null };
    expect(writesJobsFor(p, BENCH)).toBe(true);
    expect(writesJobsFor(p, ELLIE)).toBe(true);
  });

  test('scoped arms ONLY the listed uid — the bench flip', () => {
    const p = writeJobsPolicyFrom({ write_jobs: true, uid_allowlist: [BENCH] });
    expect(writesJobsFor(p, BENCH)).toBe(true);
    expect(writesJobsFor(p, ELLIE)).toBe(false);
    expect(writesJobsFor(p, 'anyone-else')).toBe(false);
  });

  test('a malformed list cannot arm the bench either — off is off', () => {
    const p = writeJobsPolicyFrom({ write_jobs: true, uid_allowlist: 'oops' });
    expect(writesJobsFor(p, BENCH)).toBe(false);
  });

  test('uid matching is exact — no prefix or case slippage', () => {
    const p = writeJobsPolicyFrom({ write_jobs: true, uid_allowlist: [BENCH] });
    expect(writesJobsFor(p, BENCH.slice(0, 10))).toBe(false);
    expect(writesJobsFor(p, BENCH.toUpperCase())).toBe(false);
    expect(writesJobsFor(p, BENCH + 'x')).toBe(false);
  });
});
