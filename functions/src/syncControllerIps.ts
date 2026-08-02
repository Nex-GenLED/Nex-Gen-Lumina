/**
 * syncControllerIps — denormalizes the registered-controller IP allowlist onto
 * `users/{uid}.controller_ips`, so firestore.rules can validate the
 * `controllerIp` a client declares on a /users/{uid}/commands document.
 *
 * WHY A DENORMALIZED ARRAY, AND NOT A get() ON THE CONTROLLER DOC
 * ---------------------------------------------------------------
 * The obvious rule is:
 *
 *     get(/users/$(userId)/controllers/$(request.resource.data.controllerId))
 *       .data.ip == request.resource.data.controllerIp
 *
 * That works for the main relay path (CloudRelayRepository gets its
 * controllerId from selectedControllerIdProvider, which resolves the
 * controllers doc id BY matching its ip — lib/features/wled/wled_providers.dart:239-255,
 * so id and ip agree by construction).
 *
 * It BREAKS two shipping app writers, which is why it was rejected:
 *
 *   - lib/features/site/bridge_setup_screen.dart:617 writes `controllerId: ''`
 *     explicitly, with a real controllerIp. Bridge pairing verification.
 *   - lib/services/bridge_health_service.dart:35-46 writes NO controllerId at
 *     all, with a real controllerIp — and uses a FIXED doc id with .set(), so
 *     its second and subsequent calls are UPDATES, not creates.
 *
 * Rules go live globally and instantly; the installed fleet is on 2.5.10+59/+60
 * and cannot be changed to suit a new rule. A controllerId-keyed rule would
 * have broken bridge setup and bridge health for every existing install the
 * moment it deployed. An IP-keyed allowlist needs no controllerId and is
 * therefore compatible with all four app writers as they ship today.
 *
 * (This is a correction to SCHEDULING_ARCHITECTURE_V2.md §8, which estimated
 * ~3 h on the assumption that a controllerId get() would just work. See
 * audit/COMMAND_SAFETY.md §2.)
 *
 * DEPLOYMENT ORDER IS LOAD-BEARING — see audit/COMMAND_SAFETY.md §5:
 *   1. Deploy this trigger + the callable.        (additive, breaks nothing)
 *   2. Run backfillControllerIps.                 (populates every user)
 *   3. VERIFY population fleet-wide.
 *   4. ONLY THEN deploy the tightened firestore.rules.
 * Deploying the rule first denies every non-empty controllerIp write fleet-wide
 * and takes out remote control entirely.
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { controllerIpsFrom } from "./commandSafety";

// admin.initializeApp() is called in index.js — do not call again here.

/** The denormalized field. snake_case to match the user doc's convention. */
const FIELD = "controller_ips";

/**
 * Recompute `controller_ips` for one user from their controllers subcollection.
 * Returns the written array, or null when no write was needed.
 *
 * Writes only when the value actually changes — [controllerIpsFrom] sorts and
 * dedupes so the comparison is stable, and a controller rename or IP-unchanged
 * touch produces no user-doc write.
 */
async function recomputeForUser(
  db: admin.firestore.Firestore,
  uid: string
): Promise<string[] | null> {
  const snap = await db.collection("users").doc(uid).collection("controllers").get();
  const next = controllerIpsFrom(snap.docs.map((d) => d.data() as { ip?: unknown }));

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    // No user doc to denormalize onto. The rules guard treats a missing user
    // doc as "no allowlist" and denies non-empty controllerIp writes, which is
    // the correct conservative outcome — but log it, because a user with
    // controllers and no user doc is the P0-5 shape and worth seeing.
    logger.warn(
      `syncControllerIps: user ${uid} has ${snap.size} controller(s) but no ` +
        "user document — allowlist not written"
    );
    return null;
  }

  const current = userSnap.get(FIELD);
  const currentArr: string[] = Array.isArray(current)
    ? (current as unknown[]).filter((x): x is string => typeof x === "string")
    : [];

  const same =
    currentArr.length === next.length && currentArr.every((v, i) => v === next[i]);
  if (same) return null;

  // set/merge rather than update: tolerates a user doc that has never carried
  // the field, and never creates a doc that does not exist (guarded above).
  await userRef.set({ [FIELD]: next }, { merge: true });
  return next;
}

/**
 * Keeps the allowlist current as controllers are added, renamed, re-addressed
 * (DHCP), or removed.
 *
 * Fires on create, update AND delete of any controller doc. Delete matters most:
 * a decommissioned controller's IP must leave the allowlist, or it stays a
 * legal target forever.
 */
export const syncControllerIps = onDocumentWritten(
  {
    document: "users/{userId}/controllers/{controllerId}",
    region: "us-central1",
  },
  async (event) => {
    const uid = event.params.userId;
    try {
      const written = await recomputeForUser(admin.firestore(), uid);
      if (written) {
        logger.info(
          `syncControllerIps: ${uid} → [${written.join(", ")}]`
        );
      }
    } catch (err) {
      // Never throw: a failure here must not block controller writes. The
      // backfill callable is the recovery path.
      logger.error(`syncControllerIps: recompute failed for ${uid}`, err);
    }
  }
);

/**
 * One-shot admin backfill. Populates `controller_ips` for every user that has
 * controllers, so the tightened rule can be deployed without denying the
 * installed fleet.
 *
 * Idempotent — recomputes from source and writes only on change, so re-running
 * is free and safe.
 *
 * Auth: requires the `admin` custom claim (same convention as
 * backfillUserLocations / backfillUserDealerCodes).
 *
 * Contract:
 *   request.data: { dryRun?: boolean }   // dryRun defaults to FALSE
 *   response: {
 *     dryRun: boolean,
 *     scanned: number,        // user docs inspected
 *     updated: number,        // users whose allowlist changed
 *     unchanged: number,      // users already correct
 *     withoutControllers: number,
 *     errors: Array<{ uid: string, reason: string }>,
 *   }
 */
export const backfillControllerIps = onCall(
  { region: "us-central1", timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    if (request.auth.token.admin !== true) {
      throw new HttpsError(
        "permission-denied",
        "backfillControllerIps requires the admin custom claim."
      );
    }

    const dryRun = request.data?.dryRun === true;
    const db = admin.firestore();

    let scanned = 0;
    let updated = 0;
    let unchanged = 0;
    let withoutControllers = 0;
    const errors: Array<{ uid: string; reason: string }> = [];

    const users = await db.collection("users").get();

    for (const userDoc of users.docs) {
      scanned++;
      const uid = userDoc.id;
      try {
        const controllers = await db
          .collection("users")
          .doc(uid)
          .collection("controllers")
          .get();

        if (controllers.empty) {
          withoutControllers++;
          continue;
        }

        const next = controllerIpsFrom(
          controllers.docs.map((d) => d.data() as { ip?: unknown })
        );
        const current = userDoc.get(FIELD);
        const currentArr: string[] = Array.isArray(current)
          ? (current as unknown[]).filter((x): x is string => typeof x === "string")
          : [];
        const same =
          currentArr.length === next.length &&
          currentArr.every((v, i) => v === next[i]);

        if (same) {
          unchanged++;
          continue;
        }

        if (!dryRun) {
          await userDoc.ref.set({ [FIELD]: next }, { merge: true });
        }
        updated++;
        logger.info(
          `backfillControllerIps${dryRun ? " [DRY]" : ""}: ${uid} → ` +
            `[${next.join(", ")}]`
        );
      } catch (err) {
        errors.push({
          uid,
          reason: err instanceof Error ? err.message : String(err),
        });
      }
    }

    const summary = {
      dryRun,
      scanned,
      updated,
      unchanged,
      withoutControllers,
      errors,
    };
    logger.info("backfillControllerIps: complete", summary);
    return summary;
  }
);
