/**
 * assignReferralCode — Firebase Cloud Function
 *
 * Firestore onCreate trigger for /users/{uid}.
 * Generates a unique 8-char referral code (LUM-XXXX) and writes it to:
 *   - /users/{uid}/referralCode   (user's own doc)
 *   - /referral_codes/{code}      (reverse-lookup for redemption)
 *
 * Collision-safe: retries up to 5 times if the generated code already exists.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:assignReferralCode
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

// admin.initializeApp() is called in index.js — do not call again here.

const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const CODE_LEN = 4;
const MAX_ATTEMPTS = 5;

function generateCode(): string {
  let result = "";
  for (let i = 0; i < CODE_LEN; i++) {
    result += CHARS.charAt(Math.floor(Math.random() * CHARS.length));
  }
  return `LUM-${result}`;
}

export const assignReferralCode = onDocumentCreated(
  { document: "users/{uid}", region: "us-central1" },
  async (event) => {
    const uid = event.params.uid;
    const db = admin.firestore();

    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const code = generateCode();
      const codeRef = db.collection("referral_codes").doc(code);

      try {
        await db.runTransaction(async (tx) => {
          const existing = await tx.get(codeRef);
          if (existing.exists) {
            throw new Error("collision");
          }
          tx.set(codeRef, { uid });
          tx.update(db.collection("users").doc(uid), { referralCode: code });
        });

        console.log(`Assigned referral code ${code} to user ${uid}`);
        return;
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === "collision") {
          console.warn(
            `Referral code collision on attempt ${attempt + 1}, retrying...`
          );
          continue;
        }
        console.error(`Failed to assign referral code to ${uid}:`, err);
        throw err;
      }
    }

    console.error(
      `Exhausted ${MAX_ATTEMPTS} attempts assigning referral code to ${uid}`
    );
  }
);
