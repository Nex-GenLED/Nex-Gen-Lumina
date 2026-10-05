/**
 * oauthLinkPage — what the Alexa and Google Home account-linking login pages
 * (alexaAuth / googleAuth in index.js) need to stay inert and stay on-site.
 *
 * THE DEFECT (audit, 2026-10-05). Both pages pasted the `state` and
 * `redirect_uri` query values straight into an inline <script> as
 * `"${value}"`, and accepted any redirect_uri that merely CONTAINED
 * "amazon.com" / "google.com". So a link like
 *   alexaAuth?redirect_uri=https://evil.example/?amazon.com&state=";…
 * served a real password page that ran attacker script and then posted the
 * fresh authorization code to an attacker host.
 *
 * THE FIX, three parts, all here so they are unit-testable:
 *   1. redirect_uri must EQUAL one of the redirect URLs the platform documents
 *      (exact string match, no parsing, no substring) — see the allowlists.
 *   2. Every value that reaches the inline script is a JSON string literal with
 *      `<`, `>`, `&`, U+2028 and U+2029 escaped, so it cannot close the script
 *      element or break out of the string.
 *   3. A Content-Security-Policy that admits only a per-response nonce and the
 *      pinned Firebase SDK path, and network calls only to Firebase Auth and
 *      this project's callable functions.
 *
 * The allowlists are built from two environment values (functions/.env), not
 * hard-coded, so no account identifier lands in this public repo:
 *   ALEXA_VENDOR_ID         — the vendor id in the skill's "Alexa Redirect URLs"
 *                             (developer console > Build > Account Linking).
 *   GOOGLE_HOME_PROJECT_ID  — the project id in Google's redirect URL.
 * Unset or empty → an empty allowlist → every request is refused. Read via
 * process.env rather than defineString() so a functions deploy never prompts
 * for them.
 */

import { randomBytes } from "crypto";

/**
 * Alexa account-linking redirect hosts, one per Alexa region (NA, EU, FE).
 * Format `{baseUrl}/api/skill/link/{vendorId}`. Source: Amazon, "Account
 * Linking Schemas" (SMAPI) — the authorization-code-grant redirect URI and its
 * valid baseUrl values:
 * https://developer.amazon.com/en-US/docs/alexa/smapi/account-linking-schemas.html
 */
export const ALEXA_REDIRECT_BASE_URLS = [
  "https://pitangui.amazon.com",
  "https://layla.amazon.com",
  "https://alexa.amazon.co.jp",
] as const;

/**
 * Google cloud-to-cloud (smart home) account-linking redirect hosts, format
 * `{host}/r/{projectId}`. Source: Google Home Developers, "OAuth 2.0
 * authorization" — production and sandbox redirect URIs:
 * https://developers.home.google.com/cloud-to-cloud/project/authorization
 */
export const GOOGLE_REDIRECT_BASE_URLS = [
  "https://oauth-redirect.googleusercontent.com",
  "https://oauth-redirect-sandbox.googleusercontent.com",
] as const;

/** The pinned Firebase JS SDK path both pages load their scripts from. */
export const FIREBASE_SDK_PATH = "https://www.gstatic.com/firebasejs/10.7.1/";

/** Firebase Auth REST hosts the compat SDK calls for email/password sign-in. */
const FIREBASE_AUTH_HOSTS = [
  "https://identitytoolkit.googleapis.com",
  "https://securetoken.googleapis.com",
];

/** Ids are opaque tokens; anything with URL syntax in it is a config error. */
const ID_PATTERN = /^[A-Za-z0-9_-]+$/;

function configuredId(raw: string | undefined): string | null {
  const id = (raw ?? "").trim();
  return id.length > 0 && ID_PATTERN.test(id) ? id : null;
}

/** The exact Alexa redirect URLs for this skill, or [] when unconfigured. */
export function alexaRedirectAllowlist(vendorId: string | undefined): string[] {
  const id = configuredId(vendorId);
  if (!id) return [];
  return ALEXA_REDIRECT_BASE_URLS.map((base) => `${base}/api/skill/link/${id}`);
}

/** The exact Google redirect URLs for this project, or [] when unconfigured. */
export function googleRedirectAllowlist(projectId: string | undefined): string[] {
  const id = configuredId(projectId);
  if (!id) return [];
  return GOOGLE_REDIRECT_BASE_URLS.map((base) => `${base}/r/${id}`);
}

/**
 * True only when `candidate` is a string EQUAL to one allowlist entry. No URL
 * parsing, so no normalisation tricks (userinfo, case, ports, trailing paths,
 * query strings, encodings) can make a different URL compare equal.
 */
export function isAllowedRedirect(
  candidate: unknown,
  allowlist: readonly string[]
): candidate is string {
  return typeof candidate === "string" && allowlist.includes(candidate);
}

/**
 * A query parameter as a non-empty string, or null. Express turns repeated
 * keys into arrays and `a[b]=c` into objects; neither is a valid OAuth value.
 */
export function queryString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/**
 * `value` as a JavaScript string literal that is safe to paste into an inline
 * <script>: JSON quoting handles `"` `\` and control characters; escaping `<`
 * `>` `&` means the text can never contain `</script` or `<!--`; U+2028/U+2029
 * are escaped for older parsers.
 */
export function scriptString(value: string): string {
  return JSON.stringify(String(value))
    .replace(/</g, "\\u003c")
    .replace(/>/g, "\\u003e")
    .replace(/&/g, "\\u0026")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}

/** A fresh CSP nonce (base64, so safe in an attribute and in the header). */
export function newCspNonce(): string {
  return randomBytes(16).toString("base64");
}

/**
 * The login page's policy. Scripts: the nonce'd inline script plus the pinned
 * SDK path only. Styles: the nonce'd <style> only. Network: Firebase Auth and
 * this project's callable functions (where generate*AuthCode lives). Nothing
 * may frame the page, change its base URL, or submit its form natively.
 */
export function linkPageCsp(nonce: string, projectId: string): string {
  return [
    "default-src 'none'",
    `script-src 'nonce-${nonce}' ${FIREBASE_SDK_PATH}`,
    `style-src 'nonce-${nonce}'`,
    `connect-src ${[
      ...FIREBASE_AUTH_HOSTS,
      `https://us-central1-${projectId}.cloudfunctions.net`,
    ].join(" ")}`,
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join("; ");
}

/** The error page's policy: nothing at all may load or run. */
export const ERROR_PAGE_CSP =
  "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

/** Minimal response surface shared by Express and the unit tests' fake. */
export interface HeaderSink {
  set(field: string, value: string): unknown;
}

/**
 * Headers for a login page response. X-Frame-Options and nosniff are restated
 * here (index.js addSecurityHeaders also sets them) so this function alone
 * defines what the page sends.
 */
export function setLinkPageHeaders(res: HeaderSink, csp: string): void {
  res.set("Content-Security-Policy", csp);
  res.set("X-Frame-Options", "DENY");
  res.set("X-Content-Type-Options", "nosniff");
  res.set("Cache-Control", "no-store");
}

/** A fixed body that never echoes any part of the request. */
export const LINK_ERROR_PAGE =
  "<!DOCTYPE html>\n" +
  '<html><head><meta charset="utf-8"><title>Link failed</title></head>' +
  "<body><p>This account-linking request is not valid. " +
  "Start linking again from the Alexa or Google Home app.</p></body></html>\n";

/** Refuse a request with the fixed error page. */
export function sendLinkPageError(
  res: HeaderSink & {
    status(code: number): { send(body: string): unknown };
  },
  status: number
): void {
  setLinkPageHeaders(res, ERROR_PAGE_CSP);
  res.set("Content-Type", "text/html; charset=utf-8");
  res.status(status).send(LINK_ERROR_PAGE);
}
