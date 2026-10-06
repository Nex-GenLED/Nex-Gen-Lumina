/**
 * Lumina Alexa shim — the AWS Lambda a Smart Home skill points at (Smart Home
 * skills only accept a Lambda ARN as endpoint). It forwards each directive
 * verbatim to the alexaSmartHome Cloud Function and returns its JSON.
 *
 * Holds no secret, no service account and no Firebase SDK: the access token
 * travels inside the directive and is verified by alexaSmartHome. Never logs
 * the directive (it carries the token).
 *
 * Environment: FULFILLMENT_URL = https://us-central1-<project>.cloudfunctions.net/alexaSmartHome
 * Runtime: Node 20+ (global fetch, AbortSignal.timeout). Lambda timeout 8 s.
 */
"use strict";

const TIMEOUT_MS = 7000; // Alexa allows ~8 s per directive

function errorEnvelope(event, type, message) {
  const h = (event && event.directive && event.directive.header) || {};
  const header = {
    namespace: "Alexa",
    name: "ErrorResponse",
    messageId: `shim-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
    payloadVersion: "3",
  };
  if (typeof h.correlationToken === "string") header.correlationToken = h.correlationToken;
  const ep = event && event.directive && event.directive.endpoint;
  return {
    event: {
      header,
      ...(ep && typeof ep.endpointId === "string" ? { endpoint: { endpointId: ep.endpointId } } : {}),
      payload: { type, message },
    },
  };
}

async function forward(event, { url = process.env.FULFILLMENT_URL, fetchImpl = fetch, timeoutMs = TIMEOUT_MS } = {}) {
  if (!url) {
    console.error("shim: FULFILLMENT_URL is not set");
    return errorEnvelope(event, "INTERNAL_ERROR", "fulfillment not configured");
  }
  try {
    const res = await fetchImpl(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(event),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) {
      console.error(`shim: fulfillment answered HTTP ${res.status}`);
      return errorEnvelope(event, "INTERNAL_ERROR", "fulfillment unavailable");
    }
    return await res.json();
  } catch (err) {
    console.error(`shim: fulfillment call failed (${err && err.name})`);
    return errorEnvelope(event, "INTERNAL_ERROR", "fulfillment unreachable");
  }
}

exports.handler = (event) => forward(event);
exports.forward = forward;
exports.errorEnvelope = errorEnvelope;
