/**
 * B-3c pure logic — client authentication, the access token, refresh-record
 * and Pending rules, the kill-switch reader. No Firestore.
 *
 * Runs against the tsc-compiled output in lib/ — `npm run build` first.
 * The Firestore half is test/emulator/voiceAlexaLink.emulator.test.ts.
 * Every id and secret below is synthetic.
 */
const { createHmac } = require("crypto");
const {
  parseClientCredentials,
  credentialsMatch,
  sendInvalidClient,
} = require("../../lib/voice/oauthClientAuth");
const {
  readAlexaJwtSecret,
  signAlexaAccessToken,
  verifyAlexaAccessToken,
  opaqueEndpointKey,
  ACCESS_TOKEN_TTL_SEC,
  ALEXA_ISSUER,
  ALEXA_AUDIENCE,
} = require("../../lib/voice/alexaJwt");
const {
  validRefreshRecord,
  linkIsActive,
  classifyPendingIntent,
  hashRefreshToken,
  PENDING_LINK_MAX_AGE_MS,
} = require("../../lib/voice/alexaLink");
const { voiceControlEnabledFromData } = require("../../lib/voice/intentCore");

const SECRET = "unit-test-jwt-secret-00000000000000000000";
const NOW = 1_900_000_000; // seconds
const ts = (ms) => ({ toMillis: () => ms });
const b64 = (s) => Buffer.from(s).toString("base64");

describe("parseClientCredentials", () => {
  const enc = (s) => encodeURIComponent(s).replace(/%20/g, "+");
  const basic = (id, secret) => "Basic " + b64(`${enc(id)}:${enc(secret)}`);

  test("HTTP Basic, with form-encoded colons, pluses and spaces in the secret", () => {
    expect(parseClientCredentials(basic("cid", "s:e c+r%t"), {})).toEqual({
      ok: true,
      creds: { clientId: "cid", clientSecret: "s:e c+r%t" },
    });
  });

  test("scheme is case-insensitive; body client_id that agrees is fine", () => {
    const h = basic("cid", "sec").replace("Basic", "bAsIc");
    expect(parseClientCredentials(h, { client_id: "cid" }).ok).toBe(true);
  });

  test("body credentials", () => {
    expect(parseClientCredentials(undefined, { client_id: "cid", client_secret: "sec" })).toEqual({
      ok: true,
      creds: { clientId: "cid", clientSecret: "sec" },
    });
  });

  test.each([
    ["no credentials", undefined, {}],
    ["body id only", undefined, { client_id: "cid" }],
    ["body secret only", undefined, { client_secret: "sec" }],
    ["non-Basic scheme", "Bearer abc", { client_id: "cid", client_secret: "sec" }],
    ["no colon", "Basic " + b64("cidsec"), {}],
    ["not base64", "Basic !!!", {}],
    ["bad percent-encoding", "Basic " + b64("cid:%E0%A4%A"), {}],
    ["header and body disagree on id", basic("cid", "sec"), { client_id: "other" }],
    ["header and body disagree on secret", basic("cid", "sec"), { client_secret: "other" }],
    ["non-string header", ["Basic x"], {}],
  ])("refused: %s", (_l, header, body) => {
    expect(parseClientCredentials(header, body)).toEqual({ ok: false });
  });
});

describe("credentialsMatch", () => {
  const expected = { clientId: "cid", clientSecret: "sec" };
  test("exact match only", () => {
    expect(credentialsMatch({ clientId: "cid", clientSecret: "sec" }, expected)).toBe(true);
    expect(credentialsMatch({ clientId: "cid", clientSecret: "SEC" }, expected)).toBe(false);
    expect(credentialsMatch({ clientId: "cidx", clientSecret: "sec" }, expected)).toBe(false);
    expect(credentialsMatch({ clientId: "", clientSecret: "" }, expected)).toBe(false);
  });
  test("an unconfigured server is reported, never matched", () => {
    expect(credentialsMatch({ clientId: "", clientSecret: "" }, { clientId: "", clientSecret: "" })).toBe("unconfigured");
    expect(credentialsMatch({ clientId: "cid", clientSecret: "sec" }, { clientId: "cid" })).toBe("unconfigured");
  });
  test("the refusal is one fixed response", () => {
    const res = { h: {}, set(k, v) { this.h[k] = v; }, status(c) { this.code = c; return { json: (b) => { this.body = b; } }; } };
    sendInvalidClient(res);
    expect(res.code).toBe(401);
    expect(res.body).toEqual({ error: "invalid_client" });
    expect(res.h).toEqual({
      "Cache-Control": "no-store",
      Pragma: "no-cache",
      "WWW-Authenticate": 'Basic realm="lumina-alexa"',
    });
  });
});

describe("readAlexaJwtSecret — dedicated key, no fallback", () => {
  test("present and long enough", () => {
    expect(readAlexaJwtSecret({ ALEXA_JWT_SECRET: SECRET })).toBe(SECRET);
  });
  test("missing, empty or short → null, even when ALEXA_CLIENT_SECRET is set", () => {
    const client = { ALEXA_CLIENT_SECRET: "x".repeat(64) };
    expect(readAlexaJwtSecret(client)).toBeNull();
    expect(readAlexaJwtSecret({ ...client, ALEXA_JWT_SECRET: "" })).toBeNull();
    expect(readAlexaJwtSecret({ ...client, ALEXA_JWT_SECRET: "x".repeat(31) })).toBeNull();
  });
  test("signing refuses an unusable key", () => {
    expect(() => signAlexaAccessToken({ lid: "l" }, "short", NOW)).toThrow();
  });
});

describe("access token", () => {
  const sign = (claims, header = { alg: "HS256", typ: "JWT" }, key = SECRET) => {
    const input = `${Buffer.from(JSON.stringify(header)).toString("base64url")}.${Buffer.from(JSON.stringify(claims)).toString("base64url")}`;
    return `${input}.${createHmac("sha256", key).update(input).digest("base64url")}`;
  };
  const good = { lid: "link1", iss: ALEXA_ISSUER, aud: ALEXA_AUDIENCE, iat: NOW, exp: NOW + 3600 };

  test("round trip; carries no uid; one-hour lifetime", () => {
    const t = signAlexaAccessToken({ lid: "link1" }, SECRET, NOW);
    const r = verifyAlexaAccessToken(t, SECRET, NOW + 10);
    expect(r).toEqual({ ok: true, claims: good });
    expect(Object.keys(r.claims).sort()).toEqual(["aud", "exp", "iat", "iss", "lid"]);
    expect(ACCESS_TOKEN_TTL_SEC).toBe(3600);
  });

  test("past exp with everything else valid → expired", () => {
    const t = signAlexaAccessToken({ lid: "link1" }, SECRET, NOW);
    expect(verifyAlexaAccessToken(t, SECRET, NOW + 3600)).toEqual({ ok: false, reason: "expired" });
  });

  test.each([
    ["no exp", { ...good, exp: undefined }],
    ["no iat", { ...good, iat: undefined }],
    ["wrong iss", { ...good, iss: "x" }],
    ["wrong aud", { ...good, aud: "x" }],
    ["no lid", { ...good, lid: "" }],
    ["lifetime too long", { ...good, exp: NOW + 3601 }],
    ["exp before iat", { ...good, exp: NOW - 1 }],
    ["iat in the future", { ...good, iat: NOW + 120, exp: NOW + 600 }],
    ["string exp", { ...good, exp: String(NOW + 3600) }],
  ])("invalid: %s", (_l, claims) => {
    expect(verifyAlexaAccessToken(sign(claims), SECRET, NOW + 10)).toEqual({ ok: false, reason: "invalid" });
  });

  test.each([
    ["alg none", sign(good, { alg: "none", typ: "JWT" })],
    ["RS256 header", sign(good, { alg: "RS256", typ: "JWT" })],
    ["signed with another key", sign(good, undefined, "another-key-000000000000000000000000")],
    ["tampered payload", signAlexaAccessToken({ lid: "link1" }, SECRET, NOW).replace(/\.[^.]+\./, "." + Buffer.from(JSON.stringify({ ...good, lid: "other" })).toString("base64url") + ".")],
    ["custom-token shape", "eyJhbGciOiJSUzI1NiJ9.eyJ1aWQiOiJ1MSJ9.c2ln"],
    ["not a string", 42],
    ["two parts", "a.b"],
  ])("invalid: %s", (_l, token) => {
    expect(verifyAlexaAccessToken(token, SECRET, NOW + 10)).toEqual({ ok: false, reason: "invalid" });
  });

  test("no usable key → invalid, whatever the token", () => {
    const t = signAlexaAccessToken({ lid: "link1" }, SECRET, NOW);
    expect(verifyAlexaAccessToken(t, null, NOW + 10)).toEqual({ ok: false, reason: "invalid" });
    expect(verifyAlexaAccessToken(t, "short", NOW + 10)).toEqual({ ok: false, reason: "invalid" });
  });
});

describe("opaqueEndpointKey", () => {
  test("stable, keyed, and free of the inputs", () => {
    const k = opaqueEndpointKey(SECRET, "u1", "ctl", "AA00000000A1");
    expect(k).toBe(opaqueEndpointKey(SECRET, "u1", "ctl", "AA00000000A1"));
    expect(k).toMatch(/^[A-Za-z0-9_-]{24}$/);
    expect(k).not.toContain("AA00000000A1");
    expect(k).not.toBe(opaqueEndpointKey(SECRET, "u2", "ctl", "AA00000000A1"));
    expect(k).not.toBe(opaqueEndpointKey(SECRET, "u1", "scn", "AA00000000A1"));
    expect(k).not.toBe(opaqueEndpointKey("another-key-000000000000000000000000", "u1", "ctl", "AA00000000A1"));
  });
});

describe("refresh records", () => {
  const now = 1_900_000_000_000;
  const rec = {
    userId: "u1", provider: "alexa", iss: "lumina-alexa", aud: "cid", active: true, expiresAt: ts(now + 1000),
  };
  test("valid → uid", () => {
    expect(validRefreshRecord(rec, now, "cid")).toBe("u1");
    expect(validRefreshRecord(rec, now)).toBe("u1");
  });
  test.each([
    ["missing", undefined],
    ["no expiry (B-3b shape)", { userId: "u1", active: true }],
    ["expired", { ...rec, expiresAt: ts(now) }],
    ["revoked", { ...rec, active: false }],
    ["wrong issuer", { ...rec, iss: "x" }],
    ["wrong provider", { ...rec, provider: "google_home" }],
    ["no audience", { ...rec, aud: "" }],
    ["no uid", { ...rec, userId: "" }],
  ])("refused: %s", (_l, data) => {
    expect(validRefreshRecord(data, now)).toBeNull();
  });
  test("issued to another client → refused at the token endpoint", () => {
    expect(validRefreshRecord(rec, now, "other")).toBeNull();
  });
  test("link is active only when the doc says linked AND the record belongs to the uid", () => {
    expect(linkIsActive({ isLinked: true }, rec, "u1", now)).toBe(true);
    expect(linkIsActive(undefined, rec, "u1", now)).toBe(false);
    expect(linkIsActive({ linkInitiated: true }, rec, "u1", now)).toBe(false);
    expect(linkIsActive({ isLinked: true }, rec, "u2", now)).toBe(false);
  });
  test("refresh tokens are stored as SHA-256 hex", () => {
    expect(hashRefreshToken("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });
});

describe("classifyPendingIntent", () => {
  const now = 1_900_000_000_000;
  const old = ts(now - PENDING_LINK_MAX_AGE_MS - 1);
  test.each([
    ["no intent", { isLinked: true }, "keep"],
    ["nothing", undefined, "keep"],
    ["fresh pending", { linkInitiated: true, initiatedAt: ts(now - 1000) }, "keep"],
    ["stale pending only", { linkInitiated: true, initiatedAt: old }, "delete"],
    ["undated pending only", { linkInitiated: true }, "delete"],
    ["linked with a leftover flag", { linkInitiated: true, initiatedAt: ts(now), isLinked: true }, "strip"],
    ["stale pending beside other fields", { linkInitiated: true, initiatedAt: old, isLinked: false, unlinkedAt: ts(1) }, "strip"],
  ])("%s → %s", (_l, data, want) => {
    expect(classifyPendingIntent(data, now)).toBe(want);
  });
});

describe("voiceControlEnabledFromData — default OFF, empty allowlist", () => {
  test.each([
    ["no doc", undefined, "u1", false],
    ["empty doc", {}, "u1", false],
    ["enabled false, empty allowlist", { enabled: false, allowlistUids: [] }, "u1", false],
    ["allowlisted while off", { enabled: false, allowlistUids: ["u1"] }, "u1", true],
    ["someone else allowlisted", { enabled: false, allowlistUids: ["u2"] }, "u1", false],
    ["enabled is a string", { enabled: "true" }, "u1", false],
    ["allowlist not an array", { enabled: false, allowlistUids: "u1" }, "u1", false],
    ["enabled, no ramp", { enabled: true }, "u1", true],
    ["enabled, ramp 0", { enabled: true, rolloutPercent: 0 }, "u1", false],
    ["no uid", { enabled: false, allowlistUids: ["u1"] }, "", false],
  ])("%s", (_l, data, uid, want) => {
    expect(voiceControlEnabledFromData(data, uid)).toBe(want);
  });
});
