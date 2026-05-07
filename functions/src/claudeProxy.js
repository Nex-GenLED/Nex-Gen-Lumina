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
    const { model, max_tokens, temperature, system, messages } = request.data;

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

    // ── Call Anthropic ───────────────────────────────────────────────────────
    const requestBody = JSON.stringify({
      model,
      max_tokens: effectiveMaxTokens,
      temperature: temperature ?? 0.2,
      system: system || '',
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

    // ── Log usage ────────────────────────────────────────────────────────────
    await usageRef.add({
      timestamp: now,
      status: 'success',
      model,
      inputTokens,
      outputTokens,
      estimatedCost,
      latency,
      hourlyCount:  hourlyCount  + 1,
      monthlyCount: monthlyCount + 1,
    });

    console.log(
      `claudeProxy ✅ model=${model} uid=${userId} ` +
      `in=${inputTokens} out=${outputTokens} ` +
      `cost=$${estimatedCost.toFixed(5)} ${latency}ms | ` +
      `hourly=${hourlyCount + 1}/${HOURLY_ABUSE_LIMIT} monthly=${monthlyCount + 1}`
    );

    return response;
  }
);

// ── Helpers ───────────────────────────────────────────────────────────────────

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