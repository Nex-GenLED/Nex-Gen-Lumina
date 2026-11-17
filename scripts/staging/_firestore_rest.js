/**
 * Minimal Firestore REST helpers for the staging scripts.
 *
 * Auth is the operator's own gcloud credential (`gcloud auth
 * print-access-token`) plus the `x-goog-user-project` quota header — the same
 * read-only approach the earlier production audits used. No service-account
 * key is read. Nothing here chooses a project: every caller passes one, and
 * the callers hard-code which project they may touch.
 */

"use strict";

const { execSync } = require("child_process");

const PRODUCTION_PROJECT = "icrt6menwsv2d8all8oijs021b06s5";
const STAGING_PROJECT = "nex-gen-lumina-22751";

function accessToken() {
  // execSync (not execFileSync): gcloud is a .cmd shim on Windows.
  return execSync("gcloud auth print-access-token", { encoding: "utf8" }).trim();
}

function docsBase(project) {
  return `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
}

async function call(project, method, url, body) {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken()}`,
      "x-goog-user-project": project,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${url.replace(/\?.*$/, "")} -> HTTP ${res.status}: ${text.slice(0, 300)}`);
  }
  return text ? JSON.parse(text) : {};
}

/** GET every document of a top-level collection (paged). Read-only. */
async function listCollection(project, collection) {
  const out = [];
  let pageToken = "";
  do {
    const q = `pageSize=300${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ""}`;
    const page = await call(project, "GET", `${docsBase(project)}/${collection}?${q}`);
    for (const d of page.documents || []) out.push(d);
    pageToken = page.nextPageToken || "";
  } while (pageToken);
  return out;
}

/** Encode a plain JS value as a Firestore REST Value. */
function encode(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (typeof v === "string") return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } };
  if (typeof v === "object") return { mapValue: { fields: encodeFields(v) } };
  throw new Error(`cannot encode ${typeof v}`);
}

function encodeFields(obj) {
  const fields = {};
  for (const [k, val] of Object.entries(obj)) fields[k] = encode(val);
  return fields;
}

/**
 * Commit full-document writes ({path, fields}) in batches of 400. `fields`
 * must already be REST-encoded. Each write replaces the document.
 */
async function commitWrites(project, writes) {
  const prefix = `projects/${project}/databases/(default)/documents`;
  for (let i = 0; i < writes.length; i += 400) {
    const chunk = writes.slice(i, i + 400).map((w) => ({
      update: { name: `${prefix}/${w.path}`, fields: w.fields },
    }));
    await call(project, "POST", `${docsBase(project)}:commit`, { writes: chunk });
  }
}

module.exports = {
  PRODUCTION_PROJECT,
  STAGING_PROJECT,
  listCollection,
  encode,
  encodeFields,
  commitWrites,
};
