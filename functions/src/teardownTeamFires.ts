/**
 * teardownTeamFires — #98. When a team's Game Day config is deleted, retract
 * that team's still-scheduled fires.
 *
 * WHY THIS EXISTS. Deleting a team removed its config and its profile entries
 * and left its ARMED FIRES BEHIND. `gd_mlb_royals_401816580_start` outlived
 * `mlb_royals` by hours: `state:"scheduled"`, a real 130-byte `on+bri+seg`
 * payload, a live controller, 4 h 13 m from firing, for a team the user had
 * already removed. #99 stops such a job at the dispatcher. This stops it
 * existing — the two are deliberately both present, because a job that is
 * retracted at source never depends on the gate holding.
 *
 * WHY A TRIGGER AND NOT A CALLABLE. `TeamRegistrationService.removeTeam` is
 * client-side Dart, and **the client cannot write `fire_jobs` at all**:
 * `/users/{uid}/fire_jobs/{jobId}` matches no rule in `firestore.rules` and
 * never has in the file's entire history, so Firestore denies it by default.
 * The teardown therefore has to run server-side. Hooking the config DELETE
 * rather than adding a callable means it covers EVERY route that removes a
 * team — `removeTeam`, an admin cleanup, a console delete — instead of only the
 * one path someone remembered to wire. The Royals config was not necessarily
 * removed through `removeTeam`, and a fix that only covered that path would not
 * have caught it.
 *
 * RETRACTED, NEVER DELETED. Per the 2026-08-18 convention the row is preserved
 * with `fireAt` and `payload` intact and only its state changes. The audit
 * trail is the point: a deleted row cannot answer "what was armed, and what
 * happened to it".
 */

import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";

import {
  CANCELLED_REASON_TEAM_DELETED,
  FIRE_JOBS_COLLECTION,
  shouldRetractForTeam,
} from "./fireJobs";

/**
 * Retract every still-scheduled fire belonging to [teamSlug]. Returns the doc
 * ids actually retracted.
 *
 * QUERIES ON `state` ONLY, then filters the slug IN MEMORY. A compound
 * `state == scheduled AND eventId >= ... AND eventId < ...` prefix range would
 * need a new composite index — and an index that is merely *created* rather
 * than *Enabled* fails the query at exactly the moment it is first needed.
 * A single user's `fire_jobs` is tiny (the whole FLEET held 17 documents at the
 * 2026-08-18 sweep), so the range scan buys nothing and costs a deploy-order
 * hazard.
 */
export async function retractTeamFires(args: {
  db: admin.firestore.Firestore;
  uid: string;
  teamSlug: string;
}): Promise<string[]> {
  const snap = await args.db
    .collection("users")
    .doc(args.uid)
    .collection(FIRE_JOBS_COLLECTION)
    .where("state", "==", "scheduled")
    .get();

  const retracted: string[] = [];
  for (const doc of snap.docs) {
    if (
      !shouldRetractForTeam({
        eventId: doc.get("eventId"),
        state: doc.get("state"),
        teamSlug: args.teamSlug,
      })
    ) {
      continue;
    }
    // update(), not set() and never delete(): fireAt and payload are preserved
    // exactly, and only the three retraction fields are written.
    await doc.ref.update({
      state: "cancelled",
      cancelled_reason: CANCELLED_REASON_TEAM_DELETED,
      cancelled_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    retracted.push(doc.id);
  }
  return retracted;
}

export const teardownTeamFires = onDocumentDeleted(
  {
    document: "users/{uid}/game_day_autopilot/{teamSlug}",
    region: "us-central1",
  },
  async (event) => {
    const { uid, teamSlug } = event.params;
    try {
      const retracted = await retractTeamFires({
        db: admin.firestore(),
        uid,
        teamSlug,
      });
      if (retracted.length > 0) {
        logger.info(
          `teardownTeamFires: retracted ${retracted.length} fire(s) for ` +
            `${uid}/${teamSlug} — ${retracted.join(", ")}`
        );
      }
    } catch (err) {
      // Never rethrow. A retry would re-run the scan, and the deletion that
      // triggered this has already happened — a failure here must surface as a
      // log line to act on, not as an infinite trigger retry loop.
      logger.error(
        `teardownTeamFires: FAILED for ${uid}/${teamSlug} — armed fires may ` +
          `survive their team. Retract by hand.`,
        err
      );
    }
  }
);
