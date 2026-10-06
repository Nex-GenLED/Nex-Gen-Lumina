// node --test alexa-skill/shim — no dependencies; fetch is injected.
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { forward } = require("./index");

const TOKEN = "header.claims.signature";
const event = {
  directive: {
    header: { namespace: "Alexa.PowerController", name: "TurnOn", correlationToken: "ct-1" },
    endpoint: { endpointId: "lumina-main", scope: { type: "BearerToken", token: TOKEN } },
    payload: {},
  },
};

function capture() {
  const lines = [];
  const orig = console.error;
  console.error = (...a) => lines.push(a.join(" "));
  return { lines, restore: () => (console.error = orig) };
}

test("forwards the directive byte-for-byte and returns the function's JSON", async () => {
  let seen;
  const reply = { event: { header: { name: "Response" } } };
  const out = await forward(event, {
    url: "https://fulfillment.example.test/alexaSmartHome",
    fetchImpl: async (url, init) => {
      seen = { url, init };
      return { ok: true, json: async () => reply };
    },
  });
  assert.deepEqual(out, reply);
  assert.equal(seen.init.method, "POST");
  assert.equal(seen.init.body, JSON.stringify(event));
});

test("non-2xx → well-formed ErrorResponse with the correlation token", async () => {
  const c = capture();
  const out = await forward(event, {
    url: "https://fulfillment.example.test/x",
    fetchImpl: async () => ({ ok: false, status: 503 }),
  });
  c.restore();
  assert.equal(out.event.header.name, "ErrorResponse");
  assert.equal(out.event.header.correlationToken, "ct-1");
  assert.equal(out.event.endpoint.endpointId, "lumina-main");
  assert.equal(out.event.payload.type, "INTERNAL_ERROR");
  assert.ok(!c.lines.join("\n").includes(TOKEN));
});

test("timeout or network error → ErrorResponse; the token is never logged", async () => {
  const c = capture();
  const out = await forward(event, {
    url: "https://fulfillment.example.test/x",
    timeoutMs: 20,
    fetchImpl: (_u, init) => new Promise((_res, rej) => init.signal.addEventListener("abort", () => rej(init.signal.reason))),
  });
  c.restore();
  assert.equal(out.event.payload.type, "INTERNAL_ERROR");
  assert.ok(!c.lines.join("\n").includes(TOKEN));
});

test("no FULFILLMENT_URL → ErrorResponse, no request", async () => {
  const c = capture();
  let called = false;
  const out = await forward(event, { url: "", fetchImpl: async () => { called = true; } });
  c.restore();
  assert.equal(out.event.payload.type, "INTERNAL_ERROR");
  assert.equal(called, false);
});
