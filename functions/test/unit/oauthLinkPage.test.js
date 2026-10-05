/**
 * Account-linking login pages (alexaAuth / googleAuth) — security fix
 * 2026-10-05: exact redirect_uri allowlists, script-safe values, CSP.
 *
 * Two layers:
 *   1. The pure helpers in lib/oauthLinkPage.
 *   2. The REAL exported handlers from index.js, driven with a fake
 *      request/response. Each served page's inline script is then run in a
 *      vm sandbox (fake `firebase`, `document`, `window`) to prove a hostile
 *      value arrives as inert data and survives the whole submit flow intact.
 *
 * Runs against the tsc-compiled output in lib/ — `npm run build` first.
 * Every id below is synthetic.
 */

const vm = require("vm");
const {
  ALEXA_REDIRECT_BASE_URLS,
  GOOGLE_REDIRECT_BASE_URLS,
  FIREBASE_SDK_PATH,
  ERROR_PAGE_CSP,
  LINK_ERROR_PAGE,
  alexaRedirectAllowlist,
  googleRedirectAllowlist,
  isAllowedRedirect,
  queryString,
  scriptString,
  linkPageCsp,
} = require("../../lib/oauthLinkPage");

const VENDOR = "TESTVENDOR01";
const GPROJECT = "demo-voice-project";
const ALEXA_CLIENT = "test-alexa-client";
const GOOGLE_CLIENT = "test-google-client";

const ALEXA_OK = [
  `https://pitangui.amazon.com/api/skill/link/${VENDOR}`,
  `https://layla.amazon.com/api/skill/link/${VENDOR}`,
  `https://alexa.amazon.co.jp/api/skill/link/${VENDOR}`,
];
const GOOGLE_OK = [
  `https://oauth-redirect.googleusercontent.com/r/${GPROJECT}`,
  `https://oauth-redirect-sandbox.googleusercontent.com/r/${GPROJECT}`,
];

// Substring, userinfo, lookalike, scheme, case, suffix and encoding tricks.
const ALEXA_TRICKS = [
  "https://evil.example/?amazon.com",
  "https://evil.example/alexa.amazon",
  `https://evil.example/?${ALEXA_OK[0]}`,
  `https://evil.example/#${ALEXA_OK[0]}`,
  `https://pitangui.amazon.com@evil.example/api/skill/link/${VENDOR}`,
  `https://pitangui.amazon.com:443@evil.example/api/skill/link/${VENDOR}`,
  `https://user:pass@pitangui.amazon.com/api/skill/link/${VENDOR}`,
  `https://pitangui.amazon.com.evil.example/api/skill/link/${VENDOR}`,
  `https://pitangui-amazon.com/api/skill/link/${VENDOR}`,
  `https://pitangui.arnazon.com/api/skill/link/${VENDOR}`,
  `https://amazon.com.evil.example/api/skill/link/${VENDOR}`,
  `https://evilamazon.com/api/skill/link/${VENDOR}`,
  `http://pitangui.amazon.com/api/skill/link/${VENDOR}`,
  `https://PITANGUI.amazon.com/api/skill/link/${VENDOR}`,
  `https://pitangui.amazon.com:8443/api/skill/link/${VENDOR}`,
  `${ALEXA_OK[0]}/`,
  `${ALEXA_OK[0]}?next=https://evil.example`,
  `${ALEXA_OK[0]}#x`,
  `${ALEXA_OK[0]}/../../evil`,
  `https://pitangui.amazon.com/api/skill/link/OTHERVENDOR`,
  `https://pitangui.amazon.com/api/skill/link/${VENDOR.toLowerCase()}`,
  `https://pitangui.amazon.com/api/skill/link/%54ESTVENDOR01`,
  `https://pitangui.amazon.com%2F@evil.example/api/skill/link/${VENDOR}`,
  `https://www.amazon.com/ap/signin`,
  `javascript:alert(1)//${ALEXA_OK[0]}`,
  `JAVASCRIPT:alert(document.domain)`,
  ` ${ALEXA_OK[0]}`,
  `${ALEXA_OK[0]} `,
];
const GOOGLE_TRICKS = [
  "https://evil.example/?google.com",
  "https://evil.example/googleusercontent.com",
  "https://accounts.google.com/o/oauth2/auth",
  `https://evil.example/?${GOOGLE_OK[0]}`,
  `https://oauth-redirect.googleusercontent.com@evil.example/r/${GPROJECT}`,
  `https://oauth-redirect.googleusercontent.com.evil.example/r/${GPROJECT}`,
  `https://oauth-redirect.googleusercontent.co/r/${GPROJECT}`,
  `https://oauth-redirect.googIeusercontent.com/r/${GPROJECT}`,
  `https://evil.googleusercontent.com/r/${GPROJECT}`,
  `http://oauth-redirect.googleusercontent.com/r/${GPROJECT}`,
  `${GOOGLE_OK[0]}/`,
  `${GOOGLE_OK[0]}?x=1`,
  `https://oauth-redirect.googleusercontent.com/r/other-project`,
  `javascript:alert(1)//${GOOGLE_OK[0]}`,
];

// Each hostile value must reach the page only as data.
const PAYLOADS = [
  `"`,
  `'`,
  `<>`,
  `"; globalThis.__pwned = 1; //`,
  `'; globalThis.__pwned = 1; //`,
  `</script><script>globalThis.__pwned = 1</script>`,
  `</SCRIPT ><img src=x onerror="globalThis.__pwned=1">`,
  `<!--<script>`,
  `javascript:globalThis.__pwned=1`,
  `\\"; globalThis.__pwned = 1; //`,
  `\u2028globalThis.__pwned = 1;\u2029`,
  "${globalThis.__pwned = 1}",
  `&lt;script&gt;`,
];

// ---------------------------------------------------------------------------
// 1. Pure helpers
// ---------------------------------------------------------------------------

describe("redirect allowlists", () => {
  test("Alexa: the three regional redirect URLs, exactly", () => {
    expect(ALEXA_REDIRECT_BASE_URLS).toEqual([
      "https://pitangui.amazon.com",
      "https://layla.amazon.com",
      "https://alexa.amazon.co.jp",
    ]);
    expect(alexaRedirectAllowlist(VENDOR)).toEqual(ALEXA_OK);
  });

  test("Google: production and sandbox redirect URLs, exactly", () => {
    expect(GOOGLE_REDIRECT_BASE_URLS).toEqual([
      "https://oauth-redirect.googleusercontent.com",
      "https://oauth-redirect-sandbox.googleusercontent.com",
    ]);
    expect(googleRedirectAllowlist(GPROJECT)).toEqual(GOOGLE_OK);
  });

  test("unset, empty or malformed ids give an empty allowlist (fail closed)", () => {
    for (const bad of [undefined, "", "   ", "a/b", "a?b", "a b", "x@y", "../x", "a#b"]) {
      expect(alexaRedirectAllowlist(bad)).toEqual([]);
      expect(googleRedirectAllowlist(bad)).toEqual([]);
    }
  });

  test("allowed URLs pass", () => {
    for (const u of ALEXA_OK) expect(isAllowedRedirect(u, ALEXA_OK)).toBe(true);
    for (const u of GOOGLE_OK) expect(isAllowedRedirect(u, GOOGLE_OK)).toBe(true);
  });

  test.each(ALEXA_TRICKS)("Alexa trick rejected: %s", (u) => {
    expect(isAllowedRedirect(u, ALEXA_OK)).toBe(false);
  });

  test.each(GOOGLE_TRICKS)("Google trick rejected: %s", (u) => {
    expect(isAllowedRedirect(u, GOOGLE_OK)).toBe(false);
  });

  test("non-strings are rejected even when they contain an allowed URL", () => {
    expect(isAllowedRedirect([ALEXA_OK[0]], ALEXA_OK)).toBe(false);
    expect(isAllowedRedirect({ toString: () => ALEXA_OK[0] }, ALEXA_OK)).toBe(false);
    expect(isAllowedRedirect(undefined, ALEXA_OK)).toBe(false);
    expect(isAllowedRedirect(ALEXA_OK[0], [])).toBe(false);
  });
});

describe("queryString", () => {
  test("only non-empty strings survive", () => {
    expect(queryString("abc")).toBe("abc");
    expect(queryString("")).toBeNull();
    expect(queryString(["a", "b"])).toBeNull();
    expect(queryString({ a: "b" })).toBeNull();
    expect(queryString(undefined)).toBeNull();
    expect(queryString(7)).toBeNull();
  });
});

describe("scriptString", () => {
  test.each(PAYLOADS)("round-trips and cannot break out: %s", (p) => {
    const lit = scriptString(p);
    expect(lit).not.toMatch(/[<>&\u2028\u2029]/);
    const ctx = vm.createContext({});
    expect(vm.runInContext(`(${lit})`, ctx)).toBe(p);
    expect(vm.runInContext(`const v = ${lit}; typeof globalThis.__pwned`, ctx)).toBe("undefined");
  });
});

describe("CSP", () => {
  const csp = linkPageCsp("NONCE123", "demo-project");

  test("scripts: the nonce and the pinned SDK path only", () => {
    expect(csp).toContain(`script-src 'nonce-NONCE123' ${FIREBASE_SDK_PATH};`);
    expect(FIREBASE_SDK_PATH).toBe("https://www.gstatic.com/firebasejs/10.7.1/");
  });

  test("no inline, eval, wildcard or scheme-wide sources anywhere", () => {
    expect(csp).not.toMatch(/unsafe-inline|unsafe-eval|strict-dynamic|\*|https: |data:|blob:/);
  });

  test("network: Firebase Auth and this project's functions host only", () => {
    expect(csp).toContain(
      "connect-src https://identitytoolkit.googleapis.com https://securetoken.googleapis.com " +
        "https://us-central1-demo-project.cloudfunctions.net;"
    );
  });

  test("default none, no framing, no base or native form submission", () => {
    for (const d of ["default-src 'none'", "frame-ancestors 'none'", "base-uri 'none'", "form-action 'none'"]) {
      expect(csp).toContain(d);
    }
  });
});

// ---------------------------------------------------------------------------
// 2. The real handlers from index.js
// ---------------------------------------------------------------------------

function fakeRes() {
  const r = { statusCode: 200, headers: {}, body: undefined };
  r.set = (k, v) => {
    r.headers[k.toLowerCase()] = v;
    return r;
  };
  r.setHeader = r.set;
  r.status = (c) => {
    r.statusCode = c;
    return r;
  };
  r.send = (b) => {
    r.body = b;
    return r;
  };
  r.json = (b) => {
    r.body = JSON.stringify(b);
    return r;
  };
  r.on = () => r;
  return r;
}

async function call(handler, query) {
  const req = {
    method: "GET",
    query,
    headers: {},
    header: () => undefined,
    get: () => undefined,
  };
  const res = fakeRes();
  await handler(req, res);
  return res;
}

const INLINE_SCRIPT = /<script nonce="([^"]+)">([\s\S]*?)<\/script>/;

/**
 * Run the page's inline script with fakes; submit the form; report.
 * `namespaces`, when given, limits the fake `firebase` to the namespaces the
 * page's SDK scripts really define (see sdkNamespaces below).
 */
async function runPage(html, { namespaces } = {}) {
  const m = html.match(INLINE_SCRIPT);
  if (!m) throw new Error("no nonce'd inline script");
  const elements = {};
  const el = (id) =>
    (elements[id] = elements[id] || {
      id,
      value: id === "email" ? "user@example.test" : "pw",
      style: {},
      disabled: false,
      textContent: "",
      handlers: {},
      addEventListener(type, fn) {
        this.handlers[type] = fn;
      },
    });
  const calls = [];
  const firebase = {
    initializeApp: () => ({}),
    auth: () => ({
      signInWithEmailAndPassword: async () => ({
        user: { getIdToken: async () => "fake-id-token" },
      }),
    }),
    functions: () => ({
      httpsCallable: (name) => async (data) => {
        calls.push({ name, data });
        return { data: { code: "FAKECODE" } };
      },
    }),
  };
  if (namespaces) {
    for (const ns of ["auth", "functions"]) {
      if (!namespaces.has(ns)) delete firebase[ns];
    }
  }
  const sandbox = {
    firebase,
    document: { getElementById: el },
    window: { location: { href: "about:blank" } },
    console: { log() {}, error() {} },
  };
  vm.createContext(sandbox);
  vm.runInContext(
    `${m[2]}\n;globalThis.__captured = { redirectUri, state };`,
    sandbox
  );
  await el("loginForm").handlers.submit({ preventDefault() {} });
  return { sandbox, calls, captured: sandbox.__captured, nonce: m[1], errorText: el("error").textContent };
}

/**
 * Load the REAL Firebase compat bundles a page names into a vm context and
 * return that context. The page pins 10.7.1 on gstatic; the npm `firebase`
 * devDependency ships the same CDN bundles under the same file names (a newer
 * version), and the namespace each one registers (firebase.auth,
 * firebase.functions, …) is the same. Network is disabled: any fetch throws.
 */
function sdkContext(html) {
  const fs = require("fs");
  const path = require("path");
  const dir = path.dirname(require.resolve("firebase/package.json"));
  const srcs = [...html.matchAll(/<script src="([^"]+)"><\/script>/g)].map((m) => m[1]);
  const quiet = { log() {}, info() {}, warn() {}, error() {}, debug() {} };
  const ctx = {
    console: quiet,
    setTimeout,
    clearTimeout,
    navigator: { userAgent: "node" },
    fetch: () => {
      throw new Error("network disabled in test");
    },
  };
  ctx.self = ctx;
  ctx.window = ctx;
  vm.createContext(ctx);
  for (const src of srcs) {
    expect(src.startsWith(FIREBASE_SDK_PATH)).toBe(true);
    const file = src.slice(FIREBASE_SDK_PATH.length);
    vm.runInContext(fs.readFileSync(path.join(dir, file), "utf8"), ctx, { filename: file });
  }
  return { ctx, files: srcs.map((s) => s.slice(FIREBASE_SDK_PATH.length)) };
}

/** Which page-used namespaces the page's own SDK scripts really define. */
function sdkNamespaces(html) {
  const { ctx } = sdkContext(html);
  return new Set(["auth", "functions"].filter((ns) => typeof ctx.firebase[ns] === "function"));
}

describe("alexaAuth / googleAuth handlers (index.js)", () => {
  let idx;
  const saved = {};
  const ENV = {
    GCLOUD_PROJECT: "demo-voice-project",
    ALEXA_CLIENT_ID: ALEXA_CLIENT,
    GOOGLE_CLIENT_ID: GOOGLE_CLIENT,
    ALEXA_VENDOR_ID: VENDOR,
    GOOGLE_HOME_PROJECT_ID: GPROJECT,
  };

  beforeAll(() => {
    for (const [k, v] of Object.entries(ENV)) {
      saved[k] = process.env[k];
      process.env[k] = v;
    }
    // The handlers log every refusal; keep the run readable.
    jest.spyOn(console, "error").mockImplementation(() => {});
    idx = require("../../index.js");
  }, 120000);

  afterAll(() => {
    console.error.mockRestore();
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  });

  const PROVIDERS = [
    { name: "alexaAuth", client: ALEXA_CLIENT, ok: ALEXA_OK, tricks: ALEXA_TRICKS, envKey: "ALEXA_VENDOR_ID", callable: "generateAlexaAuthCode" },
    { name: "googleAuth", client: GOOGLE_CLIENT, ok: GOOGLE_OK, tricks: GOOGLE_TRICKS, envKey: "GOOGLE_HOME_PROJECT_ID", callable: "generateGoogleAuthCode" },
  ];

  for (const p of PROVIDERS) {
    describe(p.name, () => {
      const h = () => idx[p.name];

      test("every allowed redirect URL serves the page with CSP and framing/sniffing headers", async () => {
        for (const uri of p.ok) {
          const res = await call(h(), { client_id: p.client, redirect_uri: uri, state: "s1", response_type: "code" });
          expect(res.statusCode).toBe(200);
          const { nonce } = await runPage(res.body);
          const csp = res.headers["content-security-policy"];
          expect(csp).toBe(linkPageCsp(nonce, "icrt6menwsv2d8all8oijs021b06s5"));
          expect(res.body).toContain(`<style nonce="${nonce}">`);
          expect(res.headers["x-frame-options"]).toBe("DENY");
          expect(res.headers["x-content-type-options"]).toBe("nosniff");
          expect(res.headers["cache-control"]).toBe("no-store");
          // Every <script> is the nonce'd inline one or the pinned SDK path.
          const tags = res.body.match(/<script\b[^>]*>/gi);
          for (const t of tags) {
            expect(t === `<script nonce="${nonce}">` || t.startsWith(`<script src="${FIREBASE_SDK_PATH}`)).toBe(true);
          }
        }
      });

      test("a fresh nonce per response", async () => {
        const q = { client_id: p.client, redirect_uri: p.ok[0], state: "s" };
        const a = await call(h(), q);
        const b = await call(h(), q);
        expect(a.body.match(INLINE_SCRIPT)[1]).not.toBe(b.body.match(INLINE_SCRIPT)[1]);
      });

      test.each(p.tricks)("tricky redirect_uri refused with a page that echoes nothing: %s", async (uri) => {
        const res = await call(h(), { client_id: p.client, redirect_uri: uri, state: "s" });
        expect(res.statusCode).toBe(400);
        expect(res.body).toBe(LINK_ERROR_PAGE);
        expect(res.headers["content-security-policy"]).toBe(ERROR_PAGE_CSP);
      });

      test.each(PAYLOADS)("hostile redirect_uri refused, nothing echoed: %s", async (payload) => {
        for (const uri of [payload, `${p.ok[0]}${payload}`, `${payload}${p.ok[0]}`]) {
          const res = await call(h(), { client_id: p.client, redirect_uri: uri, state: payload });
          expect(res.statusCode).toBe(400);
          expect(res.body).toBe(LINK_ERROR_PAGE);
        }
      });

      test("repeated or nested redirect_uri keys are refused (old .includes() on an array passed)", async () => {
        for (const uri of [["https://evil.example", "amazon.com", "google.com"], [p.ok[0]], { a: p.ok[0] }]) {
          const res = await call(h(), { client_id: p.client, redirect_uri: uri, state: "s" });
          expect(res.statusCode).toBe(400);
          expect(res.body).not.toContain("<script");
        }
      });

      test.each(PAYLOADS)("hostile state is inert through render, script and submit: %s", async (payload) => {
        const res = await call(h(), { client_id: p.client, redirect_uri: p.ok[0], state: payload });
        expect(res.statusCode).toBe(200);
        expect(res.body.match(/<script\b/gi)).toHaveLength(4); // 3 SDK + 1 inline
        if (payload.length > 2 && /[<>&]/.test(payload)) expect(res.body).not.toContain(payload);
        const { sandbox, captured, calls } = await runPage(res.body);
        expect(sandbox.__pwned).toBeUndefined();
        expect(captured.state).toBe(payload);
        expect(captured.redirectUri).toBe(p.ok[0]);
        expect(calls).toHaveLength(1);
        expect(calls[0].name).toBe(p.callable);
        expect(sandbox.window.location.href).toBe(
          `${p.ok[0]}?state=${encodeURIComponent(payload)}&code=FAKECODE`
        );
      });

      test.each(PAYLOADS)("hostile client_id refused, nothing echoed: %s", async (payload) => {
        const res = await call(h(), { client_id: payload, redirect_uri: p.ok[0], state: "s" });
        expect(res.statusCode).toBe(400);
        expect(res.body).toBe("Invalid client_id");
        expect(res.headers["content-security-policy"]).toBe(ERROR_PAGE_CSP);
      });

      test("missing parameters refused under the lock-down policy", async () => {
        const res = await call(h(), { client_id: p.client, redirect_uri: p.ok[0] });
        expect(res.statusCode).toBe(400);
        expect(res.body).toBe("Missing required OAuth parameters");
        expect(res.headers["content-security-policy"]).toBe(ERROR_PAGE_CSP);
        expect(res.headers["x-frame-options"]).toBe("DENY");
        expect(res.headers["x-content-type-options"]).toBe("nosniff");
      });

      test("no allowlist configured → every request refused", async () => {
        const prev = process.env[p.envKey];
        delete process.env[p.envKey];
        try {
          for (const uri of p.ok) {
            const res = await call(h(), { client_id: p.client, redirect_uri: uri, state: "s" });
            expect(res.statusCode).toBe(400);
            expect(res.body).toBe(LINK_ERROR_PAGE);
          }
        } finally {
          process.env[p.envKey] = prev;
        }
      });
    });
  }

  test("alexaAuth: the server-minted state reaches the callable as data", async () => {
    const res = await call(idx.alexaAuth, {
      client_id: ALEXA_CLIENT,
      redirect_uri: ALEXA_OK[1],
      state: `</script>"'`,
    });
    const { calls } = await runPage(res.body);
    const minted = JSON.parse(Buffer.from(calls[0].data.state, "base64").toString("utf8"));
    expect(minted.originalState).toBe(`</script>"'`);
    expect(calls[0].data.idToken).toBe("fake-id-token");
  });

  // -------------------------------------------------------------------------
  // The link fix: both pages call firebase.functions(), which only exists
  // once firebase-functions-compat.js is loaded. Without it the call threw
  // "firebase.functions is not a function" in the browser right after a
  // successful sign-in, so no account was ever linked.
  // -------------------------------------------------------------------------
  describe("SDK scripts cover every firebase namespace the page calls", () => {
    for (const p of [
      { name: "alexaAuth", client: ALEXA_CLIENT, ok: ALEXA_OK, callable: "generateAlexaAuthCode" },
      { name: "googleAuth", client: GOOGLE_CLIENT, ok: GOOGLE_OK, callable: "generateGoogleAuthCode" },
    ]) {
      const page = async () =>
        (await call(idx[p.name], { client_id: p.client, redirect_uri: p.ok[0], state: "s" })).body;

      test(`${p.name}: a compat script, in load order, for each namespace used`, async () => {
        const html = await page();
        const inline = html.match(INLINE_SCRIPT)[2];
        const used = new Set([...inline.matchAll(/firebase\.(\w+)\(/g)].map((m) => m[1]));
        expect([...used].sort()).toEqual(["auth", "functions", "initializeApp"]);
        const { files } = sdkContext(html);
        expect(files).toEqual([
          "firebase-app-compat.js", // defines firebase.initializeApp; must load first
          "firebase-auth-compat.js",
          "firebase-functions-compat.js",
        ]);
      });

      test(`${p.name}: the real SDK defines firebase.functions and the callable builds`, async () => {
        const { ctx } = sdkContext(await page());
        expect(typeof ctx.firebase.functions).toBe("function");
        const callable = vm.runInContext(
          `firebase.initializeApp({ apiKey: "k", projectId: "demo-voice-project" });
           firebase.functions().httpsCallable(${JSON.stringify(p.callable)})`,
          ctx
        );
        expect(typeof callable).toBe("function");
      });

      test(`${p.name}: sign-in → callable → redirect completes with the real namespaces`, async () => {
        const html = await page();
        const namespaces = sdkNamespaces(html);
        expect([...namespaces].sort()).toEqual(["auth", "functions"]);
        const { sandbox, calls, errorText } = await runPage(html, { namespaces });
        expect(errorText).toBe("");
        expect(calls.map((c) => c.name)).toEqual([p.callable]);
        expect(sandbox.window.location.href).toBe(`${p.ok[0]}?state=s&code=FAKECODE`);
      });
    }
  });
});
