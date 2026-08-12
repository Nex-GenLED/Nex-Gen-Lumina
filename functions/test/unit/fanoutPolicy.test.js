// config/sync_fanout group_allowlist — scoped Neighborhood Sync fanout.
//
// Deliberately mirrors writeJobsPolicy (planGameDayFires) shape-for-shape. Two
// scoping mechanisms that behave DIFFERENTLY under a typo would be worse than
// one, because the operator carries one mental model across both.
//
// What is at stake here is larger than the planner's: fanout writes commands to
// OTHER PEOPLE'S controllers. A typo that read as "global" would hand light
// control of every crew to any initiator. Hence malformed => OFF.

const {
  fanoutPolicyFrom,
  fanoutsForGroup,
  FANOUT_OFF,
} = require('../../lib/applySyncPattern');

const BENCH = '06m7bMxKNjolhsRXV5MJ';
const OTHER = 'someOtherGroupId1234';

describe('fanoutPolicyFrom — the five shapes', () => {
  test('doc absent / undefined data -> OFF', () => {
    expect(fanoutPolicyFrom(undefined)).toEqual(FANOUT_OFF);
    expect(fanoutPolicyFrom({})).toEqual(FANOUT_OFF);
  });

  test('enabled !== true -> OFF regardless of any allowlist', () => {
    expect(fanoutPolicyFrom({ enabled: false, group_allowlist: [BENCH] }))
      .toEqual(FANOUT_OFF);
    expect(fanoutPolicyFrom({ enabled: 'true', group_allowlist: [BENCH] }))
      .toEqual(FANOUT_OFF);
    expect(fanoutPolicyFrom({ enabled: 1 })).toEqual(FANOUT_OFF);
  });

  test('enabled true + list present -> those groups ONLY', () => {
    const p = fanoutPolicyFrom({ enabled: true, group_allowlist: [BENCH] });
    expect(p.enabled).toBe(true);
    expect(p.allowlist).toEqual([BENCH]);
  });

  test('enabled true + list absent -> GLOBAL', () => {
    expect(fanoutPolicyFrom({ enabled: true }))
      .toEqual({ enabled: true, allowlist: null });
    expect(fanoutPolicyFrom({ enabled: true, group_allowlist: null }))
      .toEqual({ enabled: true, allowlist: null });
  });

  test('MALFORMED allowlist -> OFF, never global', () => {
    // The direction that matters. Fanout writes commands to other people's
    // controllers; a typo widening scope would hand light control of every crew
    // to any initiator.
    for (const bad of [BENCH, { 0: BENCH }, [BENCH, 42], [BENCH, null], [BENCH, ''], 7, true]) {
      expect(fanoutPolicyFrom({ enabled: true, group_allowlist: bad }))
        .toEqual(FANOUT_OFF);
    }
  });

  test('an EMPTY array is deliberate "enabled for nobody", NOT malformed', () => {
    const p = fanoutPolicyFrom({ enabled: true, group_allowlist: [] });
    expect(p.enabled).toBe(true);
    expect(p.allowlist).toEqual([]);
    expect(fanoutsForGroup(p, BENCH)).toBe(false);
  });
});

describe('fanoutsForGroup — per-group gating', () => {
  test('OFF fans out to nobody', () => {
    expect(fanoutsForGroup(FANOUT_OFF, BENCH)).toBe(false);
  });

  test('global fans out to everybody', () => {
    const p = { enabled: true, allowlist: null };
    expect(fanoutsForGroup(p, BENCH)).toBe(true);
    expect(fanoutsForGroup(p, OTHER)).toBe(true);
  });

  test('scoped fans out ONLY to the listed group — the bench enable', () => {
    const p = fanoutPolicyFrom({ enabled: true, group_allowlist: [BENCH] });
    expect(fanoutsForGroup(p, BENCH)).toBe(true);
    expect(fanoutsForGroup(p, OTHER)).toBe(false);
  });

  test('a malformed list cannot enable the bench either — off is off', () => {
    const p = fanoutPolicyFrom({ enabled: true, group_allowlist: 'oops' });
    expect(fanoutsForGroup(p, BENCH)).toBe(false);
  });

  test('groupId matching is EXACT — no prefix or case slippage', () => {
    const p = fanoutPolicyFrom({ enabled: true, group_allowlist: [BENCH] });
    expect(fanoutsForGroup(p, BENCH.slice(0, 8))).toBe(false);
    expect(fanoutsForGroup(p, BENCH.toLowerCase())).toBe(false);
    expect(fanoutsForGroup(p, BENCH + 'x')).toBe(false);
    expect(fanoutsForGroup(p, '')).toBe(false);
  });
});

describe('parity with the planner allowlist', () => {
  test('same five shapes resolve the same way in both mechanisms', () => {
    const { writeJobsPolicyFrom } = require('../../lib/planGameDayFires');
    const cases = [
      [undefined, false],
      [{}, false],
      [{ enabled: false }, false],
      [{ enabled: true }, true],
      [{ enabled: true, list: [] }, true],
      [{ enabled: true, list: 'bad' }, false],
    ];
    for (const [shape, expectedEnabled] of cases) {
      const fan = fanoutPolicyFrom(shape && {
        enabled: shape.enabled,
        ...(shape.list !== undefined ? { group_allowlist: shape.list } : {}),
      });
      const plan = writeJobsPolicyFrom(shape && {
        write_jobs: shape.enabled,
        ...(shape.list !== undefined ? { uid_allowlist: shape.list } : {}),
      });
      expect(fan.enabled).toBe(expectedEnabled);
      expect(fan.enabled).toBe(plan.enabled);
      expect(fan.allowlist).toEqual(plan.allowlist);
    }
  });
});
