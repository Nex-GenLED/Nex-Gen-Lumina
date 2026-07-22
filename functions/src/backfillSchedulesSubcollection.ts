/**
 * backfillSchedulesSubcollection — Firebase Cloud Function (callable, admin).
 *
 * Migrates each user's legacy `schedules` ARRAY (a field on the /users/{uid}
 * doc) into the /users/{uid}/schedules/{scheduleSubDocId(id)} SUBCOLLECTION,
 * preserving ids: the sanitized id becomes the document id, the RAW id is kept
 * verbatim inside the doc body (as written by the client's ScheduleItem.toJson,
 * including the already-encoded `wledPayload` String — copied verbatim, never
 * decoded). Each doc is stamped with a `sortKey` = its ARRAY INDEX so the
 * subcollection's `orderBy('sortKey')` read reproduces the user's exact legacy
 * insertion order (A-5-prime). After a user's docs are written,
 * `schedulesMigratedAt` is stamped on the user doc with a server timestamp.
 *
 * Idempotent: upserts are keyed by doc id, and sortKey is only stamped where a
 * doc has none — an already-assigned key is preserved, so a rerun never
 * renumbers and converges (the planBackfill diff reports zero NEW docs on the
 * second pass). Safe to run repeatedly.
 *
 * The planning/aggregation is the exported READ-ONLY [planFleetBackfill]; the
 * callable adds a writer callback on the non-dryRun path, and
 * scripts/backfill_dryrun.js calls the SAME function with no callback (so a
 * dry-run previews the exact numbers a real run produces, and never writes).
 *
 * Contract:
 *   request.data: {
 *     uid?:      string,   // single-user mode; omit for full-fleet batch mode
 *     dryRun?:   boolean,  // default false. When true, WRITES NOTHING.
 *     pageSize?: number,   // batch-mode page size (default 200, max 500)
 *   }
 *   response: BackfillResponse {
 *     dryRun, usersProcessed, usersWithSchedules, usersAlreadyMigrated,
 *     totalUpserts (0 when dryRun), totalNewDocs,
 *     perUser: Array<{ uid, arrayCount, existingCount, newCount,
 *       skippedMalformed, skippedDetails:[{index,reason}], migratedAlready,
 *       newDocIds:[], sortKeyAssignments:[{docId,sortKey}] }>,
 *   }
 *
 * Auth: caller must hold the `admin` custom claim (mirrors
 * backfillUserLocations). No in-app surface; run from the Firebase console,
 * functions shell, or scripts/backfill_dryrun.js (dry-run only).
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:backfillSchedulesSubcollection
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { planBackfill } from "./scheduleMigrationShared";

// admin.initializeApp() is called in index.js — do not call again here.

const DEFAULT_PAGE_SIZE = 200;
const MAX_PAGE_SIZE = 500;
const UPSERT_BATCH_SIZE = 400; // headroom under the 500 write/txn limit
const NEW_DOC_ID_SAMPLE_CAP = 25;

export interface PerUserResult {
  uid: string;
  arrayCount: number;
  existingCount: number;
  newCount: number;
  skippedMalformed: number;
  /** Per-skipped-item detail (array index + reason), from planBackfill. */
  skippedDetails: Array<{ index: number; reason: string }>;
  /** True when the user doc already carries schedulesMigratedAt (prior run). */
  migratedAlready: boolean;
  newDocIds: string[];
  /** Index→sortKey assignment sample (dryRun-visible). */
  sortKeyAssignments: Array<{ docId: string; sortKey: number }>;
}

export interface BackfillResponse {
  dryRun: boolean;
  usersProcessed: number;
  usersWithSchedules: number;
  /** Users already carrying schedulesMigratedAt (prior-run indicator). */
  usersAlreadyMigrated: number;
  totalUpserts: number;
  totalNewDocs: number;
  perUser: PerUserResult[];
}

/** One user's pending writes, handed to the callable's writer callback. */
export interface UserPlan {
  userRef: FirebaseFirestore.DocumentReference;
  upserts: Array<{ docId: string; item: unknown; sortKey: number }>;
}

/**
 * THE shared, READ-ONLY fleet planner. Pages /users (or a single uid), reads
 * each user's `schedules` array + existing subcollection docs, plans the
 * backfill via the shared `planBackfill`, and aggregates the report. It writes
 * NOTHING itself.
 *
 * When [onUserPlanned] is supplied (the callable's non-dryRun path only), each
 * user's pending writes are handed to that callback and its returned
 * written-count is added to `totalUpserts` — so write STREAMING is preserved and
 * ONLY the callable, never the dry-run script, contains .set/.commit/.update.
 *
 * Both the deployed callable and scripts/backfill_dryrun.js call this exact
 * function, so a dry-run previews the SAME numbers the real run produces (no
 * divergent reimplementation).
 */
export async function planFleetBackfill(
  db: FirebaseFirestore.Firestore,
  opts: { singleUid: string | null; pageSize: number },
  onUserPlanned?: (u: UserPlan) => Promise<number>,
): Promise<BackfillResponse> {
  const response: BackfillResponse = {
    dryRun: onUserPlanned == null,
    usersProcessed: 0,
    usersWithSchedules: 0,
    usersAlreadyMigrated: 0,
    totalUpserts: 0,
    totalNewDocs: 0,
    perUser: [],
  };

  const planOne = async (
    userDoc: FirebaseFirestore.QueryDocumentSnapshot |
      FirebaseFirestore.DocumentSnapshot,
  ): Promise<void> => {
    response.usersProcessed++;
    const arrayItems = userDoc.get("schedules");
    if (!Array.isArray(arrayItems) || arrayItems.length === 0) return;
    response.usersWithSchedules++;

    const migratedAlready = userDoc.get("schedulesMigratedAt") != null;
    if (migratedAlready) response.usersAlreadyMigrated++;

    const schedulesCol = userDoc.ref.collection("schedules");
    const existingSnap = await schedulesCol.get();
    const existing = new Map(
      existingSnap.docs.map((d) => {
        const sk = d.get("sortKey");
        return [d.id, { sortKey: typeof sk === "number" ? sk : undefined }];
      }),
    );

    const plan = planBackfill(arrayItems, existing);
    response.totalNewDocs += plan.newDocIds.length;
    response.perUser.push({
      uid: userDoc.id,
      arrayCount: plan.arrayCount,
      existingCount: plan.existingCount,
      newCount: plan.newDocIds.length,
      skippedMalformed: plan.skippedMalformed,
      skippedDetails: plan.skippedDetails.slice(0, NEW_DOC_ID_SAMPLE_CAP),
      migratedAlready,
      newDocIds: plan.newDocIds.slice(0, NEW_DOC_ID_SAMPLE_CAP),
      sortKeyAssignments: plan.sortKeyAssignments.slice(0, NEW_DOC_ID_SAMPLE_CAP),
    });

    if (onUserPlanned) {
      response.totalUpserts += await onUserPlanned({
        userRef: userDoc.ref,
        upserts: plan.upserts,
      });
    }
  };

  if (opts.singleUid) {
    const userDoc = await db.collection("users").doc(opts.singleUid).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", `User ${opts.singleUid} not found`);
    }
    await planOne(userDoc);
  } else {
    let last: FirebaseFirestore.QueryDocumentSnapshot | null = null;
    let page = 0;
    for (;;) {
      let query = db
        .collection("users")
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(opts.pageSize);
      if (last) query = query.startAfter(last.id);
      const snap = await query.get();
      if (snap.empty) break;

      for (const userDoc of snap.docs) await planOne(userDoc);

      page++;
      logger.info(
        `backfillSchedulesSubcollection: page ${page} (${snap.size} users) — ` +
          `processed=${response.usersProcessed} ` +
          `withSchedules=${response.usersWithSchedules} ` +
          `upserts=${response.totalUpserts} newDocs=${response.totalNewDocs}`,
      );

      last = snap.docs[snap.docs.length - 1];
      if (snap.size < opts.pageSize) break;
    }
  }

  return response;
}

/**
 * THE single write implementation for the backfill — used by both the deployed
 * callable (non-dryRun path) and scripts/backfill_run.js, so the write behaviour
 * never diverges. Streams a user's upserts to their /schedules subcollection
 * (batched), then stamps schedulesMigratedAt. Returns the number of docs written.
 * Only ever reached off the dryRun path; a dry run passes no writer at all.
 */
export function makeBackfillWriter(
  db: FirebaseFirestore.Firestore,
): (u: UserPlan) => Promise<number> {
  return async ({ userRef, upserts }: UserPlan): Promise<number> => {
    let written = 0;
    for (let i = 0; i < upserts.length; i += UPSERT_BATCH_SIZE) {
      const batch = db.batch();
      for (const { docId, item } of upserts.slice(i, i + UPSERT_BATCH_SIZE)) {
        batch.set(
          userRef.collection("schedules").doc(docId),
          item as FirebaseFirestore.DocumentData,
        );
      }
      await batch.commit();
      written += Math.min(UPSERT_BATCH_SIZE, upserts.length - i);
    }
    await userRef.update({
      schedulesMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return written;
  };
}

export const backfillSchedulesSubcollection = onCall(
  { region: "us-central1", timeoutSeconds: 540, memory: "512MiB" },
  async (request): Promise<BackfillResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required");
    }
    if (request.auth.token.admin !== true) {
      throw new HttpsError(
        "permission-denied",
        "backfillSchedulesSubcollection requires the admin custom claim",
      );
    }

    const data = (request.data ?? {}) as {
      uid?: unknown;
      dryRun?: unknown;
      pageSize?: unknown;
    };
    const dryRun = data.dryRun === true;
    const singleUid =
      typeof data.uid === "string" && data.uid.length > 0 ? data.uid : null;
    const pageSize = Math.min(
      typeof data.pageSize === "number" && data.pageSize > 0
        ? Math.floor(data.pageSize)
        : DEFAULT_PAGE_SIZE,
      MAX_PAGE_SIZE,
    );

    const db = admin.firestore();

    logger.info(
      `backfillSchedulesSubcollection: start ` +
        `${singleUid ? `uid=${singleUid}` : "mode=batch"} dryRun=${dryRun}`,
    );

    const response = await planFleetBackfill(
      db,
      { singleUid, pageSize },
      dryRun ? undefined : makeBackfillWriter(db),
    );
    response.dryRun = dryRun;

    logger.info(
      `backfillSchedulesSubcollection: done dryRun=${dryRun} ` +
        `processed=${response.usersProcessed} ` +
        `withSchedules=${response.usersWithSchedules} ` +
        `upserts=${response.totalUpserts} newDocs=${response.totalNewDocs}`,
    );
    return response;
  },
);
