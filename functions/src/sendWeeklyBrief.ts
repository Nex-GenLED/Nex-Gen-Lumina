/**
 * sendWeeklyBrief — Scheduled Firebase Cloud Function
 *
 * Fires every Sunday at 18:30 UTC. For each user with autopilot enabled and
 * weekly schedule preview enabled, reads upcoming autopilot_events, calls
 * Claude Haiku to generate a short push notification body, and sends an FCM
 * push with a deep-link to the autopilot schedule screen.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:sendWeeklyBrief
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import * as https from "https";

// admin.initializeApp() is called in index.js — do not call again here.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AutopilotEventDoc {
  scheduledTime: admin.firestore.Timestamp;
  sourceDetail: string;
  patternName: string;
  eventType: string;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SYSTEM_PROMPT =
  "You are Lumina, the AI behind a smart LED lighting app. " +
  "Write a 1-2 sentence push notification body for a weekly schedule preview. " +
  "Address the user by first name. Mention 2-3 specific highlights from the " +
  "event list (game days, holidays, special events). Keep it under 120 characters " +
  "total. Sound warm and smart. No emojis. No markdown. Never say I or as an AI.";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Compute the upcoming week window: Monday 00:00 UTC through Sunday 23:59 UTC.
 * Since this function fires on Sunday, "upcoming" means the day after.
 */
function getUpcomingWeekWindow(): { monday: Date; sunday: Date } {
  const now = new Date();
  const dayOfWeek = now.getUTCDay(); // 0=Sun, 1=Mon …
  const daysUntilMonday = dayOfWeek === 0 ? 1 : 8 - dayOfWeek;

  const monday = new Date(now);
  monday.setUTCDate(now.getUTCDate() + daysUntilMonday);
  monday.setUTCHours(0, 0, 0, 0);

  const sunday = new Date(monday);
  sunday.setUTCDate(monday.getUTCDate() + 6);
  sunday.setUTCHours(23, 59, 59, 999);

  return { monday, sunday };
}

/**
 * Call Claude Haiku directly via HTTPS — mirrors the pattern in claudeProxy.js.
 */
function callClaudeHaiku(
  apiKey: string,
  systemPrompt: string,
  userMessage: string,
): Promise<string> {
  return new Promise((resolve, reject) => {
    const requestBody = JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 100,
      temperature: 0.4,
      system: systemPrompt,
      messages: [{ role: "user", content: userMessage }],
    });

    const options: https.RequestOptions = {
      hostname: "api.anthropic.com",
      path: "/v1/messages",
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
        "content-length": Buffer.byteLength(requestBody),
      },
    };

    const req = https.request(options, (res) => {
      let body = "";
      res.on("data", (chunk: string) => { body += chunk; });
      res.on("end", () => {
        try {
          const parsed = JSON.parse(body);
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            const text =
              parsed?.content?.[0]?.text ?? "";
            resolve(text.trim());
          } else {
            const errMsg = parsed?.error?.message || `HTTP ${res.statusCode}`;
            reject(new Error(errMsg));
          }
        } catch (e) {
          reject(new Error(`Failed to parse Anthropic response: ${body}`));
        }
      });
    });

    req.on("error", (e: Error) => reject(e));
    req.write(requestBody);
    req.end();
  });
}

/**
 * Small delay helper to avoid FCM rate limits.
 */
function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Cloud Function
// ---------------------------------------------------------------------------

export const sendWeeklyBrief = onSchedule(
  {
    schedule: "every sunday 18:30",
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const messaging = admin.messaging();
    const apiKey = process.env.ANTHROPIC_API_KEY;

    if (!apiKey) {
      console.error("sendWeeklyBrief: ANTHROPIC_API_KEY not set");
      return;
    }

    const { monday, sunday } = getUpcomingWeekWindow();
    const weekStartISO = monday.toISOString().split("T")[0];
    const mondayTimestamp = admin.firestore.Timestamp.fromDate(monday);
    const sundayTimestamp = admin.firestore.Timestamp.fromDate(sunday);

    console.log(`sendWeeklyBrief: starting for week of ${weekStartISO}`);

    // ── Query eligible users ───────────────────────────────────────
    let usersSnapshot: admin.firestore.QuerySnapshot;
    try {
      usersSnapshot = await db
        .collection("users")
        .where("autopilot_enabled", "==", true)
        .where("weekly_schedule_preview_enabled", "==", true)
        .get();
    } catch (err) {
      console.error("sendWeeklyBrief: failed to query users:", err);
      return;
    }

    console.log(
      `sendWeeklyBrief: found ${usersSnapshot.size} eligible users`
    );

    let sentCount = 0;
    let skipCount = 0;
    let errorCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      const uid = userDoc.id;
      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken as string | undefined;
      const firstName = ((userData?.display_name as string) ?? "").split(" ")[0] || "there";

      // ── Skip users with no FCM token ──────────────────────────────
      if (!fcmToken) {
        skipCount++;
        continue;
      }

      try {
        // ── Fetch autopilot events for the upcoming week ────────────
        const eventsSnap = await db
          .collection("users")
          .doc(uid)
          .collection("autopilot_events")
          .where("scheduledTime", ">=", mondayTimestamp)
          .where("scheduledTime", "<=", sundayTimestamp)
          .orderBy("scheduledTime", "asc")
          .limit(20)
          .get();

        const events: AutopilotEventDoc[] = eventsSnap.docs.map(
          (d) => d.data() as AutopilotEventDoc
        );

        // ── Build notification body ─────────────────────────────────
        let notificationBody: string;

        if (events.length === 0) {
          // Fallback for zero events
          notificationBody =
            `${firstName}, your lights are set to warm white all week. Tap to customize.`;
          notificationBody = notificationBody.slice(0, 120);
        } else {
          // Build event summary for AI
          const eventLines = events.map((e) => {
            const date = e.scheduledTime.toDate().toUTCString();
            const detail = e.sourceDetail || e.patternName || e.eventType;
            return `- ${date}: ${detail} (${e.eventType})`;
          });

          const userMessage =
            `User's first name: ${firstName}\n` +
            `Upcoming week events (${events.length} total):\n` +
            eventLines.join("\n");

          try {
            notificationBody = await callClaudeHaiku(
              apiKey,
              SYSTEM_PROMPT,
              userMessage,
            );

            notificationBody = notificationBody.slice(0, 120);

            // Sanity check
            if (!notificationBody || notificationBody.length === 0) {
              notificationBody =
                `${firstName}, your lights are set to warm white all week. Tap to customize.`;
              notificationBody = notificationBody.slice(0, 120);
            }
          } catch (aiErr) {
            console.warn(
              `sendWeeklyBrief: AI failed for ${uid}, using fallback:`,
              aiErr,
            );
            notificationBody =
              `${firstName}, your lights are set to warm white all week. Tap to customize.`;
            notificationBody = notificationBody.slice(0, 120);
          }
        }

        // ── Send FCM push ───────────────────────────────────────────
        await messaging.send({
          token: fcmToken,
          notification: {
            title: "Your Week in Lights \u2728",
            body: notificationBody,
          },
          data: {
            type: "weekly_brief",
            route: "/autopilot-schedule",
            date: weekStartISO,
          },
          android: {
            notification: {
              channelId: "autopilot_weekly",
              priority: "high" as const,
              defaultSound: true,
            },
            priority: "high" as const,
          },
          apns: {
            payload: {
              aps: {
                alert: {
                  title: "Your Week in Lights \u2728",
                  body: notificationBody,
                },
                sound: "default",
                badge: 1,
              },
            },
          },
        });

        sentCount++;
      } catch (err: unknown) {
        errorCount++;

        // Clean up invalid tokens
        const errorCode = (err as { code?: string })?.code;
        if (
          errorCode === "messaging/invalid-registration-token" ||
          errorCode === "messaging/registration-token-not-registered"
        ) {
          console.log(`sendWeeklyBrief: removing stale token for ${uid}`);
          await db.collection("users").doc(uid).update({
            fcmToken: admin.firestore.FieldValue.delete(),
          });
        } else {
          console.error(`sendWeeklyBrief: failed to notify ${uid}:`, err);
        }
      }

      // ── 60ms delay between FCM sends ──────────────────────────────
      await delay(60);
    }

    console.log(
      `sendWeeklyBrief: done — sent=${sentCount}, skipped=${skipCount}, errors=${errorCount}`
    );
  }
);
