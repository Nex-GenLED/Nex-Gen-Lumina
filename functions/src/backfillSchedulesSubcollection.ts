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
 * Contract:
 *   request.data: {
 *     uid?:      string,   // single-user mode; omit for full-fleet batch mode
 *     dryRun?:   boolean,  // default false. When true, WRITES NOTHING —
 *                          // returns per-user counts + id diffs only.
 *     pageSize?: number,   // batch-mode page size (default 200, max 500)
 *   }
 *   response: {
 *     dryRun: boolean,
 *     usersProcessed: number,
 *     usersWithSchedules: number,
 *     totalUpserts: number,      // docs written (0 when dryRun)
 *     totalNewDocs: number,      // docs that did NOT already exist
 *     perUser: Array<{
 *       uid: string,
 *       arrayCount: number,
 *       existingCount: number,
 *       newCount: number,
 *       skippedMalformed: number,
 *       newDocIds: string[],     // capped sample for readability
 *       sortKeyAssignments: Array<{docId,sortKey}>,  // index→sortKey sample
 *     }>,
 *   }
 *
 * Auth: caller must hold the `admin` custom claim (mirrors
 * backfillUserLocations). No in-app surface; run from the Firebase console or
 * functions shell.
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

interface PerUserResult {
  uid: string;
  arrayCount: number;
  existingCount: number;
  newCount: number;
  skippedMalformed: number;
  newDocIds: string[];
  /** Index→sortKey assignment sample (dryRun-visible). */
  sortKeyAssignments: Array<{ docId: string; sortKey: number }>;
}

interface BackfillResponse {
  dryRun: boolean;
  usersProcessed: number;
  usersWithSchedules: number;
  totalUpserts: number;
  totalNewDocs: number;
  perUser: PerUserResult[];
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
    const response: BackfillResponse = {
      dryRun,
      usersProcessed: 0,
      usersWithSchedules: 0,
      totalUpserts: 0,
      totalNewDocs: 0,
      perUser: [],
    };

    logger.info(
      `backfillSchedulesSubcollection: start ` +
        `${singleUid ? `uid=${singleUid}` : "mode=batch"} dryRun=${dryRun}`,
    );

    const processUser = async (
      userDoc: FirebaseFirestore.QueryDocumentSnapshot |
        FirebaseFirestore.DocumentSnapshot,
    ): Promise<void> => {
      response.usersProcessed++;
      const arrayItems = userDoc.get("schedules");
      if (!Array.isArray(arrayItems) || arrayItems.length === 0) return;
      response.usersWithSchedules++;

      const schedulesCol = userDoc.ref.collection("schedules");
      const existingSnap = await schedulesCol.get();
      // docId → existing sortKey (undefined when the doc has none). Lets the
      // plan preserve already-assigned keys on rerun (never renumber).
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
        newDocIds: plan.newDocIds.slice(0, NEW_DOC_ID_SAMPLE_CAP),
        // dryRun surfaces the exact index→sortKey assignment (capped sample).
        sortKeyAssignments: plan.sortKeyAssignments.slice(0, NEW_DOC_ID_SAMPLE_CAP),
      });

      if (dryRun) return; // WRITE NOTHING

      // Upsert each array item to its subcollection doc (verbatim body).
      for (let i = 0; i < plan.upserts.length; i += UPSERT_BATCH_SIZE) {
        const batch = db.batch();
        for (const { docId, item } of plan.upserts.slice(
          i,
          i + UPSERT_BATCH_SIZE,
        )) {
          batch.set(schedulesCol.doc(docId), item as FirebaseFirestore.DocumentData);
        }
        await batch.commit();
        response.totalUpserts += Math.min(
          UPSERT_BATCH_SIZE,
          plan.upserts.length - i,
        );
      }

      // Stamp the migration marker on the user doc.
      await userDoc.ref.update({
        schedulesMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    };

    if (singleUid) {
      const userDoc = await db.collection("users").doc(singleUid).get();
      if (!userDoc.exists) {
        throw new HttpsError("not-found", `User ${singleUid} not found`);
      }
      await processUser(userDoc);
    } else {
      // Full-fleet batch mode — page through /users by document id.
      let last: FirebaseFirestore.QueryDocumentSnapshot | null = null;
      let page = 0;
      for (;;) {
        let query = db
          .collection("users")
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(pageSize);
        if (last) query = query.startAfter(last.id);
        const snap = await query.get();
        if (snap.empty) break;

        for (const userDoc of snap.docs) {
          await processUser(userDoc);
        }

        page++;
        logger.info(
          `backfillSchedulesSubcollection: page ${page} ` +
            `(${snap.size} users) — processed=${response.usersProcessed} ` +
            `withSchedules=${response.usersWithSchedules} ` +
            `upserts=${response.totalUpserts} newDocs=${response.totalNewDocs}`,
        );

        last = snap.docs[snap.docs.length - 1];
        if (snap.size < pageSize) break;
      }
    }

    logger.info(
      `backfillSchedulesSubcollection: done dryRun=${dryRun} ` +
        `processed=${response.usersProcessed} ` +
        `withSchedules=${response.usersWithSchedules} ` +
        `upserts=${response.totalUpserts} newDocs=${response.totalNewDocs}`,
    );
    return response;
  },
);
