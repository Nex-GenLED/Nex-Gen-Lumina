/**
 * Pure-logic unit tests for the schedule migration helpers.
 *
 * Runs against the tsc-compiled output in ../../lib (run `npm run build`
 * first). No emulator / firebase-admin needed — these cover the tricky,
 * IO-free logic: the id mapping (Dart-parity), trim planning, and backfill
 * diff / idempotency.
 */

const {
  MAX_SCHEDULES,
  scheduleSubDocId,
  getScheduleId,
  planScheduleTrim,
  planBackfill,
} = require("../../lib/scheduleMigrationShared");

const mk = (id, extra = {}) => ({
  id,
  timeLabel: "7:00 PM",
  repeatDays: ["Mon"],
  actionLabel: "Pattern: Warm White",
  enabled: true,
  ...extra,
});

describe("MAX_SCHEDULES", () => {
  test("is 50, matching the client cap (schedule_providers.dart:461)", () => {
    expect(MAX_SCHEDULES).toBe(50);
  });
});

describe("scheduleSubDocId — parity with Dart schedule_store_sync.dart", () => {
  // FIXTURES: expected outputs are the Dart scheduleSubDocId contract —
  //   slash-free id => unchanged; every '/' => '_'.
  // If the Dart mapping ever changes, THIS fixture must change in lockstep.
  const cases = [
    ["abc123", "abc123"],
    ["a/b/c", "a_b_c"],
    ["x/y", "x_y"],
    ["/leading", "_leading"],
    ["trailing/", "trailing_"],
    ["a//b", "a__b"],
    ["no-slashes-uuid-4f3a", "no-slashes-uuid-4f3a"],
  ];
  for (const [input, expected] of cases) {
    test(`"${input}" -> "${expected}"`, () => {
      expect(scheduleSubDocId(input)).toBe(expected);
    });
  }

  test("the two mappings agree on a '/'-containing id (parity assertion)", () => {
    // The Dart contract: id.contains('/') ? id.replaceAll('/', '_') : id.
    const dartContract = (id) => (id.includes("/") ? id.replace(/\//g, "_") : id);
    for (const id of ["a/b/c", "plain", "//", "p/q"]) {
      expect(scheduleSubDocId(id)).toBe(dartContract(id));
    }
  });
});

describe("getScheduleId", () => {
  test("extracts a valid string id", () => {
    expect(getScheduleId(mk("s1"))).toBe("s1");
  });
  test("returns null for malformed items", () => {
    expect(getScheduleId(null)).toBeNull();
    expect(getScheduleId({})).toBeNull();
    expect(getScheduleId({ id: 42 })).toBeNull();
    expect(getScheduleId({ id: "" })).toBeNull();
    expect(getScheduleId("not-an-object")).toBeNull();
  });
});

describe("planScheduleTrim", () => {
  test("no trim when within cap", () => {
    const items = [mk("a"), mk("b")];
    const plan = planScheduleTrim(items, 50);
    expect(plan.trimmed).toBe(false);
    expect(plan.removedIds).toEqual([]);
    expect(plan.kept).toEqual(items);
  });

  test("no trim / empty for non-array", () => {
    const plan = planScheduleTrim(undefined, 50);
    expect(plan.trimmed).toBe(false);
    expect(plan.kept).toEqual([]);
    expect(plan.removedIds).toEqual([]);
  });

  test("keeps the most recent `max`, removes the oldest prefix ids", () => {
    const items = Array.from({ length: 53 }, (_, i) => mk(`s${i}`));
    const plan = planScheduleTrim(items, 50);
    expect(plan.trimmed).toBe(true);
    expect(plan.kept).toHaveLength(50);
    // Removed = the first 3 (oldest).
    expect(plan.removedIds).toEqual(["s0", "s1", "s2"]);
    // Kept = last 50, so s2 gone, s3..s52 present.
    expect(getScheduleId(plan.kept[0])).toBe("s3");
    expect(getScheduleId(plan.kept[49])).toBe("s52");
  });

  test("idempotent: re-planning the kept set does not trim", () => {
    const items = Array.from({ length: 60 }, (_, i) => mk(`s${i}`));
    const first = planScheduleTrim(items, 50);
    const second = planScheduleTrim(first.kept, 50);
    expect(second.trimmed).toBe(false);
    expect(second.removedIds).toEqual([]);
  });

  test("removedIds skips malformed items but still trims", () => {
    const items = [
      { id: 123 }, // malformed — no string id
      ...Array.from({ length: 51 }, (_, i) => mk(`s${i}`)),
    ];
    const plan = planScheduleTrim(items, 50);
    expect(plan.trimmed).toBe(true);
    expect(plan.kept).toHaveLength(50);
    // 2 removed (52 - 50): the malformed one (skipped) + s0.
    expect(plan.removedIds).toEqual(["s0"]);
  });
});

describe("planBackfill", () => {
  test("fresh backfill: all docs are new", () => {
    const items = [mk("a"), mk("b/c"), mk("d")];
    const plan = planBackfill(items, []);
    expect(plan.arrayCount).toBe(3);
    expect(plan.existingCount).toBe(0);
    expect(plan.upserts.map((u) => u.docId)).toEqual(["a", "b_c", "d"]);
    expect(plan.newDocIds).toEqual(["a", "b_c", "d"]);
    expect(plan.skippedMalformed).toBe(0);
  });

  test("slash id maps to sanitized docId, raw item preserved in upsert", () => {
    const item = mk("a/b/c", { wledPayload: '{"on":true,"seg":[{"col":[[255,0,0,0]]}]}' });
    const plan = planBackfill([item], []);
    expect(plan.upserts[0].docId).toBe("a_b_c");
    // Raw id kept verbatim in the body; wledPayload String untouched.
    expect(plan.upserts[0].item.id).toBe("a/b/c");
    expect(plan.upserts[0].item.wledPayload).toBe(item.wledPayload);
  });

  test("idempotency: converged state yields zero new docs on rerun", () => {
    const items = [mk("a"), mk("b/c"), mk("d")];
    const firstDocIds = planBackfill(items, []).upserts.map((u) => u.docId);
    const second = planBackfill(items, firstDocIds);
    expect(second.newDocIds).toEqual([]);
    // Still upserts everything (overwrite converges) but nothing is new.
    expect(second.upserts).toHaveLength(3);
  });

  test("counts malformed items as skipped, not upserted", () => {
    const plan = planBackfill([mk("a"), { id: 7 }, null, mk("b")], []);
    expect(plan.skippedMalformed).toBe(2);
    expect(plan.upserts.map((u) => u.docId)).toEqual(["a", "b"]);
  });

  test("non-array input yields an empty plan", () => {
    const plan = planBackfill(undefined, []);
    expect(plan.arrayCount).toBe(0);
    expect(plan.upserts).toEqual([]);
    expect(plan.newDocIds).toEqual([]);
  });
});
