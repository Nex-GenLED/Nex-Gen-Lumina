// functions/src/claudeProxy.js
//
// PLACEMENT:  functions/src/claudeProxy.js
// index.js already exports this — no changes needed there.
//
// SETUP (one-time):
//   1. Open functions/.env
//   2. Add:  ANTHROPIC_API_KEY=sk-ant-YOUR_KEY_HERE
//   3. Confirm .env is in .gitignore
//   4. Deploy: firebase deploy --only functions
//
// NOTE: admin and https are required here but db is initialized LAZILY
// inside the handler (not at module level) to avoid the initializeApp()
// race condition with index.js.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const https = require('https');

// ── Constants ─────────────────────────────────────────────────────────────────

const ALLOWED_MODELS = [
  'claude-haiku-4-5-20251001',
  'claude-opus-4-6',
];

const HOURLY_ABUSE_LIMIT = 50;   // Hard block — abuse/runaway only
const MONTHLY_SOFT_LIMIT = 500;  // Warn only — never blocks (free phase)
const MAX_TOKENS = 1024;

const PRICING = {
  'claude-haiku-4-5-20251001': { input: 0.00025 / 1000, output: 0.00125 / 1000 },
  'claude-opus-4-6':           { input: 0.015   / 1000, output: 0.075   / 1000 },
};

// ── Handler ───────────────────────────────────────────────────────────────────

exports.claudeProxy = onCall(
  { region: 'us-central1', timeoutSeconds: 60 },
  async (request) => {

    // db initialized HERE (lazy) — not at module level
    const db = admin.firestore();

    // ── Auth ────────────────────────────────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userId = request.auth.uid;
    const now = admin.firestore.Timestamp.now();
    const usageRef = db.collection('users').doc(userId).collection('claude_usage');

    // ── Hourly abuse check (hard block) ─────────────────────────────────────
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const hourlySnap = await usageRef
      .where('timestamp', '>', admin.firestore.Timestamp.fromDate(oneHourAgo))
      .where('status', '==', 'success')
      .get();

    const hourlyCount = hourlySnap.size;

    if (hourlyCount >= HOURLY_ABUSE_LIMIT) {
      console.warn(`claudeProxy ABUSE BLOCK: uid=${userId} hourly=${hourlyCount}`);
      throw new HttpsError(
        'resource-exhausted',
        'Too many requests. Please slow down and try again in a few minutes.'
      );
    }

    // ── Monthly soft check (warn only — never blocks) ────────────────────────
    const monthStart = new Date();
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);

    const monthlySnap = await usageRef
      .where('timestamp', '>', admin.firestore.Timestamp.fromDate(monthStart))
      .where('status', '==', 'success')
      .get();

    const monthlyCount = monthlySnap.size;

    if (monthlyCount >= MONTHLY_SOFT_LIMIT) {
      console.warn(
        `claudeProxy SOFT LIMIT: uid=${userId} monthly=${monthlyCount}/${MONTHLY_SOFT_LIMIT} — allowed (free phase)`
      );
    }

    // ── Validate request ─────────────────────────────────────────────────────
    const { model, max_tokens, temperature, system, messages, clientNow, clientTimeZone } = request.data;

    if (!model || !messages || !Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError('invalid-argument', 'Missing required fields: model, messages');
    }

    if (!ALLOWED_MODELS.includes(model)) {
      console.error(`claudeProxy invalid model: ${model} uid=${userId}`);
      throw new HttpsError('invalid-argument', `Model not permitted: ${model}`);
    }

    const effectiveMaxTokens = Math.min(max_tokens || MAX_TOKENS, MAX_TOKENS);

    // ── API key ──────────────────────────────────────────────────────────────
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      console.error('ANTHROPIC_API_KEY not set in functions/.env');
      throw new HttpsError('internal', 'AI service not configured.');
    }

    // ── Temporal grounding (day-part bug fix) ────────────────────────────────
    // The model used to write a day-part word that contradicted the actual
    // scheduled time — e.g. "tonight" on a 10:11 AM schedule — because it had
    // no anchor to the user's real local clock and guessed. Inject an
    // authoritative current-time block + explicit resolution rules into the
    // FRONT of the system prompt on EVERY call so the model resolves
    // "tonight"/"tomorrow" against the real clock and never infers a day-part.
    const groundedSystem = _buildTemporalContext(clientNow, clientTimeZone) + (system || '');

    // ── Call Anthropic ───────────────────────────────────────────────────────
    const requestBody = JSON.stringify({
      model,
      max_tokens: effectiveMaxTokens,
      temperature: temperature ?? 0.2,
      system: groundedSystem,
      messages,
    });

    const startTime = Date.now();
    let response;

    try {
      response = await _callAnthropicApi(apiKey, requestBody);
    } catch (err) {
      const errMsg = err.message || 'unknown';
      // Tag credit-balance failures so they're greppable in Cloud Logging:
      //   gcloud logging read 'jsonPayload.event="anthropic_credit_exhausted"'
      if (/credit balance/i.test(errMsg)) {
        console.error(JSON.stringify({
          event: 'anthropic_credit_exhausted',
          uid: userId,
          model,
          message: errMsg,
        }));
      } else {
        console.error(`claudeProxy Anthropic error: uid=${userId}`, errMsg);
      }
      await usageRef.add({
        timestamp: now,
        status: 'failed',
        model,
        error: errMsg,
        latency: Date.now() - startTime,
      });
      throw new HttpsError('internal', `Lumina AI error: ${errMsg}`);
    }

    const latency = Date.now() - startTime;
    const inputTokens  = response.usage?.input_tokens  || 0;
    const outputTokens = response.usage?.output_tokens || 0;
    const estimatedCost = _estimateCost(model, inputTokens, outputTokens);

    // ── Truncation detection (truncation safety net, Layer 1) ────────────────
    // When the model hits the output token cap, Anthropic sets
    // stop_reason="max_tokens" and the body is a PARTIAL reply — its JSON is
    // cut mid-object. Returning it as an ordinary success let the client parse
    // a half-payload, which leaked raw JSON into the chat bubble AND silently
    // dropped schedules. Surface an explicit `truncated` flag so the client
    // can discard the partial and show a friendly message instead. We still
    // return the (partial) response object so usage/diagnostics are intact —
    // the flag is the contract the client keys off, not the body.
    const truncated = response.stop_reason === 'max_tokens';
    if (truncated) {
      console.warn(
        `claudeProxy TRUNCATED: model=${model} uid=${userId} ` +
        `out=${outputTokens} (stop_reason=max_tokens) — flagging truncated:true`
      );
    }

    // ── Log usage ────────────────────────────────────────────────────────────
    await usageRef.add({
      timestamp: now,
      status: 'success',
      model,
      inputTokens,
      outputTokens,
      estimatedCost,
      latency,
      truncated,
      hourlyCount:  hourlyCount  + 1,
      monthlyCount: monthlyCount + 1,
    });

    console.log(
      `claudeProxy ✅ model=${model} uid=${userId} ` +
      `in=${inputTokens} out=${outputTokens} ` +
      `cost=$${estimatedCost.toFixed(5)} ${latency}ms | ` +
      `hourly=${hourlyCount + 1}/${HOURLY_ABUSE_LIMIT} monthly=${monthlyCount + 1}`
    );

    // Explicit truncated flag alongside the native stop_reason. The client
    // checks either, so the contract holds even if Anthropic's field shape
    // changes. Non-mutating spread keeps every original field intact.
    return { ...response, truncated };
  }
);

// ── Helpers ───────────────────────────────────────────────────────────────────

// Builds the authoritative current-time + day-part-rule block prepended to the
// system prompt on every call. Prefers the server clock formatted into the
// caller's IANA zone (server time is trustworthy; Intl resolves the zone with
// no extra deps), then the client's device-local datetime string, then UTC.
// Returns a string that always ends with two newlines so it cleanly precedes
// the caller's own system prompt.
function _buildTemporalContext(clientNow, clientTimeZone) {
  const tz =
    typeof clientTimeZone === 'string' && clientTimeZone.trim()
      ? clientTimeZone.trim()
      : null;

  let nowLabel = null;
  if (tz) {
    try {
      nowLabel = new Intl.DateTimeFormat('en-US', {
        timeZone: tz,
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
      }).format(new Date());
    } catch (e) {
      // Invalid IANA string — fall through to the client-reported value.
      nowLabel = null;
    }
  }
  if (!nowLabel && typeof clientNow === 'string' && clientNow.trim()) {
    nowLabel = clientNow.trim();
  }
  if (!nowLabel) {
    nowLabel = new Date().toISOString() + ' (UTC — user local time unknown)';
  }

  const tzLine = tz ? ` Timezone: ${tz}.` : '';
  return (
    `CURRENT DATE & TIME (authoritative — this is the real current clock): ${nowLabel}.${tzLine}\n` +
    `TIME & DAY-PART RULES (override any other guidance below):\n` +
    `• Never infer or guess AM/PM or a day-part (morning/afternoon/evening/night/tonight). Use the explicit clock time from the user's request or the scheduled time verbatim.\n` +
    `• Resolve relative words ("tonight", "tomorrow", "this morning", "later") ONLY against the CURRENT DATE & TIME above. "tonight" means the evening of today's date; never apply it to a morning or afternoon time.\n` +
    `• If a requested time is ambiguous, choose the NEXT FUTURE occurrence from the current time — never default to night or evening.\n` +
    `• Your confirmation text MUST NOT contain a day-part word that contradicts the scheduled clock time (e.g. do NOT say "tonight" for a 10:11 AM schedule). When in doubt, state the explicit time, e.g. "at 10:11 AM".\n\n`
  );
}

function _estimateCost(model, inputTokens, outputTokens) {
  const p = PRICING[model] || PRICING['claude-haiku-4-5-20251001'];
  return (inputTokens * p.input) + (outputTokens * p.output);
}

function _callAnthropicApi(apiKey, requestBody) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.anthropic.com',
      path: '/v1/messages',
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(requestBody),
      },
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(parsed);
          } else {
            const errMsg = parsed?.error?.message || `HTTP ${res.statusCode}`;
            reject(new Error(errMsg));
          }
        } catch (e) {
          reject(new Error(`Failed to parse Anthropic response: ${body}`));
        }
      });
    });

    req.on('error', (e) => reject(e));
    req.write(requestBody);
    req.end();
  });
}