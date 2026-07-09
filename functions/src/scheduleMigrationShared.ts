/**
 * scheduleMigrationShared — pure helpers shared by the schedule-related
 * Cloud Functions (enforceScheduleLimits, backfillSchedulesSubcollection).
 *
 * Everything here is deterministic and Firestore-free so it can be unit-tested
 * without the emulator (see test/unit/scheduleMigrationShared.test.js).
 */

/**
 * Maximum schedules per user. MUST stay in lockstep with the client-side cap
 * enforced in SchedulesNotifier at
 *   lib/features/schedule/schedule_providers.dart:461
 * (and its sibling merge path). This server sweep is defense-in-depth for
 * clients on older builds.
 */
export const MAX_SCHEDULES = 50;

/**
 * Maps a schedule id to its Firestore subcollection document id.
 *
 * PINNED to the Dart contract in
 *   lib/features/schedule/data/schedule_store_sync.dart -> scheduleSubDocId
 * Firestore document ids may not contain '/'. The array field keeps the RAW
 * id (inside the item body); this mapping is applied ONLY at the subcollection
 * boundary. It MUST stay byte-for-byte identical to the Dart implementation —
 * the parity fixture test guards a '/'-containing id.
 */
export function scheduleSubDocId(id: string): string {
  return id.includes("/") ? id.replace(/\//g, "_") : id;
}

/** Extracts a schedule's string id, or null if malformed. */
export function getScheduleId(item: unknown): string | null {
  if (item != null && typeof item === "object" && "id" in item) {
    const raw = (item as { id: unknown }).id;
    if (typeof raw === "string" && raw.length > 0) return raw;
  }
  return null;
}

export interface TrimPlan {
  /** True when trimming is required (length > max). */
  trimmed: boolean;
  /** The items to keep — the most-recently-appended `max` entries. */
  kept: unknown[];
  /** RAW ids of the removed (oldest) items, for subcollection deletes. */
  removedIds: string[];
}

/**
 * Plans a trim: keeps the last [max] items (most recent), and reports the raw
 * ids of the removed prefix so the subcollection can be trimmed identically.
 * Non-array input or already-within-cap input yields `trimmed: false`.
 */
export function planScheduleTrim(
  schedules: unknown,
  max: number = MAX_SCHEDULES,
): TrimPlan {
  if (!Array.isArray(schedules) || schedules.length <= max) {
    return { trimmed: false, kept: Array.isArray(schedules) ? schedules : [], removedIds: [] };
  }
  const kept = schedules.slice(-max);
  const removed = schedules.slice(0, schedules.length - max);
  const removedIds = removed
    .map(getScheduleId)
    .filter((id): id is string => id !== null);
  return { trimmed: true, kept, removedIds };
}

export interface BackfillPlan {
  /** Every array item mapped to its target { docId, item } upsert. */
  upserts: Array<{ docId: string; item: unknown }>;
  /** Count of array items considered. */
  arrayCount: number;
  /** Count of subcollection docs already present before this run. */
  existingCount: number;
  /** Doc ids that would be NEWLY created (not already in the subcollection). */
  newDocIds: string[];
  /** RAW ids skipped because they were malformed (no string id). */
  skippedMalformed: number;
}

/**
 * Plans an array → subcollection backfill for one user. Pure: takes the array
 * items and the set of existing subcollection doc ids, returns the upserts and
 * a diff. Idempotent by construction — once every array item's docId is in
 * [existingDocIds], `newDocIds` is empty (rerunning converges).
 */
export function planBackfill(
  arrayItems: unknown,
  existingDocIds: Iterable<string>,
): BackfillPlan {
  const items = Array.isArray(arrayItems) ? arrayItems : [];
  const existing = new Set(existingDocIds);
  const upserts: Array<{ docId: string; item: unknown }> = [];
  const newDocIds: string[] = [];
  let skippedMalformed = 0;

  for (const item of items) {
    const id = getScheduleId(item);
    if (id === null) {
      skippedMalformed++;
      continue;
    }
    const docId = scheduleSubDocId(id);
    upserts.push({ docId, item });
    if (!existing.has(docId)) newDocIds.push(docId);
  }

  return {
    upserts,
    arrayCount: items.length,
    existingCount: existing.size,
    newDocIds,
    skippedMalformed,
  };
}
