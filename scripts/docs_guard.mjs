#!/usr/bin/env node
// docs_guard.mjs — the documentation staleness guard.
//
// Run from the repo root:   node scripts/docs_guard.mjs            (checks the maintained docs)
//                           node scripts/docs_guard.mjs --links-all (also checks every link under docs/)
//
// Exit code 1 when any FAIL is printed. No dependencies, no network, no Flutter toolchain.
//
// What it checks (scope: docs/FACTS.md, docs/guides/**/*.md, docs/drive-exports/**/*.md):
//   1. Bold labels (**Like This**, up to 6 words, starting with a capital or digit) exist as string
//      literals somewhere under lib/ (case-insensitive), or are listed in scripts/docs_guard_allow.txt.
//      A bold path "A → B → C" is checked part by part.
//   2. Routes (/settings/..., /setup/...) exist in lib/app_router.dart; repo paths (lib/, docs/,
//      scripts/, test/, functions/, esp32-bridge/) exist on disk; markdown links resolve.
//   3. Build numbers never exceed pubspec.yaml; each guide carries "Describes build:" and
//      "Last verified:" (warn when older than 90 days).
//   4. Every fact id cited (T-…) exists in docs/FACTS.md. A fact whose status is unshipped
//      (BUILT NOT SHIPPED, NOT BUILT, NEVER WORKED, NOT REACHABLE, NOT IN RELEASE) may be cited in a
//      paragraph only if that paragraph says it is coming / not available / does not.
//   5. Banned phrases from docs/guides/internal/33-claims-policy.md (that page and FACTS.md are exempt).
//   6. Credential, address and identity patterns: email, phone, private IP (192.168.4.1 allowed),
//      MAC, 12-hex id, 28-character uid, "PIN ####", password values.
//
// Keep this file dependency-free; it runs in CI's "Test and analyze" step and on any laptop.

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, resolve, relative, sep } from 'node:path';

const ROOT = resolve(process.argv[1], '..', '..');
const LINKS_ALL = process.argv.includes('--links-all');
const fails = [];
const warns = [];
const fail = (f, l, m) => fails.push(`FAIL ${rel(f)}:${l}: ${m}`);
const warn = (f, l, m) => warns.push(`WARN ${rel(f)}:${l}: ${m}`);
const rel = (f) => relative(ROOT, f).split(sep).join('/');

function walk(dir, pred, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) {
      if (['node_modules', 'build', '.dart_tool', '.git'].includes(name)) continue;
      walk(p, pred, out);
    } else if (pred(p)) out.push(p);
  }
  return out;
}

// ---------- 1. literals from lib/ ----------
const literals = new Set();
for (const f of walk(join(ROOT, 'lib'), (p) => p.endsWith('.dart'))) {
  const src = readFileSync(f, 'utf8');
  const re = /'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"/g;
  let m;
  while ((m = re.exec(src))) {
    const raw = (m[1] ?? m[2] ?? '').replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/\$\{[^}]*\}|\$[A-Za-z_]\w*/g, '').trim();
    if (!raw) continue;
    literals.add(raw.toLowerCase());
    literals.add(raw.replace(/[…:.!?]+$/, '').trim().toLowerCase());
  }
}
const routerSrc = existsSync(join(ROOT, 'lib/app_router.dart')) ? readFileSync(join(ROOT, 'lib/app_router.dart'), 'utf8') : '';
const allowFile = join(ROOT, 'scripts/docs_guard_allow.txt');
const allow = new Set(existsSync(allowFile) ? readFileSync(allowFile, 'utf8').split(/\r?\n/).map((s) => s.trim().toLowerCase()).filter((s) => s && !s.startsWith('#')) : []);

// ---------- facts ----------
const factsPath = join(ROOT, 'docs/FACTS.md');
const facts = new Map(); // id -> status
if (existsSync(factsPath)) {
  for (const line of readFileSync(factsPath, 'utf8').split(/\r?\n/)) {
    const m = /^\|\s*(T-[A-Z]+\d+)\s*\|(.*)$/.exec(line);
    if (!m) continue;
    const cells = m[2].split('|').map((s) => s.trim());
    facts.set(m[1], cells[1] ?? '');
  }
} else fail(factsPath, 0, 'docs/FACTS.md is missing');
const UNSHIPPED = /BUILT NOT SHIPPED|NOT BUILT|NEVER WORKED|NOT REACHABLE|NOT IN RELEASE/;
const QUALIFIER = /\b(coming|not available|never|not yet|cannot|can't|does not|doesn't|do not|don't|is not|isn't|are not|aren't|no longer|not shipped|not deployed|not built|unreachable|withdrawn|removed)\b/i;

// ---------- pubspec ----------
const pubspec = readFileSync(join(ROOT, 'pubspec.yaml'), 'utf8');
const pubBuild = Number((/^version:\s*\d+\.\d+\.\d+\+(\d+)/m.exec(pubspec) ?? [])[1] ?? 0);

// ---------- banned phrases ----------
const BANNED = [
  [/quinled/i, 'web-flasher name'],
  [/\bre-?flash/i, 'reflash'],
  [/\bflash(ing|ed)?\s+(the|a|your|this)\s+(controller|firmware|unit)/i, 'flashing a controller'],
  [/\b0\.1[45]\.\d\b/, 'a WLED version number (keep versions in FACTS.md only)'],
  [/\bAlexa\b/i, 'Alexa'],
  [/Google (Home|Assistant)/i, 'Google Home / Assistant'],
  [/lifetime warranty/i, 'lifetime warranty'],
  [/http:\/\/<bridge-ip>/i, 'bridge web address'],
  [/Factory Reset button/i, 'bridge Factory Reset button'],
  [/\bbridge.{0,20}(dashboard|web page)/i, 'bridge dashboard or web page (unless stating there is none)'],
  [/Upload system logs/i, 'Upload system logs (does not exist)'],
  [/Lumina-XXXX/i, 'Lumina-XXXX'],
  [/from the App Store|from Google Play|download (the )?Lumina( app)? from/i, 'store download instruction'],
  [/\bAR\b|augmented reality/, 'AR'],
  [/military-grade|bank-level/i, 'marketing security phrase'],
  [/\bSOC\s?2\b/i, 'SOC 2'],
  [/Repair base lighting/i, 'Repair base lighting card (not shipped)'],
  [/Use this controller/i, 'Use this controller (not shipped)'],
  [/Opening the app (at home )?repairs/i, 'repair-on-open claim'],
  [/OpenAI/i, 'OpenAI'],
];
const BANNED_NEGATION_OK = /\b(no|not|never|none|without|isn't|is not|does not|there is no|wrong|untrue|withdrawn)\b/i;

// ---------- PII patterns ----------
const PII = [
  [/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}/, 'email address'],
  [/\(?\b\d{3}\)?[-. ]\d{3}[-. ]\d{4}\b/, 'phone number'],
  [/\b(?:192\.168|10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b/, 'private IP address'],
  [/\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/, 'MAC address'],
  [/\b(?=[0-9A-Fa-f]{12}\b)(?=[0-9A-Fa-f]{0,11}[A-Fa-f])[0-9A-Fa-f]{12}\b/, '12-character hex id'],
  [/\b(?=[A-Za-z0-9]{28}\b)(?=[A-Za-z0-9]*\d)(?=[A-Za-z0-9]*[A-Z])(?=[A-Za-z0-9]*[a-z])[A-Za-z0-9]{28}\b/, '28-character id'],
  [/\bPIN\b[^\n|]{0,20}\b\d{4}\b/, 'PIN value'],
  [/password[^\n`]{0,12}(?:is|:|=|→)\s*`?(?!<)(?=[A-Za-z0-9!@#$%^&*]*\d)[A-Za-z0-9!@#$%^&*]{6,}/i, 'password value'],
];
const PII_OK = [/192\.168\.4\.1/, /4\.3\.2\.1/, /AA00000000A1/, /192\.0\.2\./];

// ---------- scope ----------
const scope = [factsPath, ...walk(join(ROOT, 'docs/guides'), (p) => p.endsWith('.md')), ...walk(join(ROOT, 'docs/drive-exports'), (p) => p.endsWith('.md'))].filter(existsSync);
// A file whose first three lines carry "docs_guard: allow-banned" may quote banned phrases (it is a policy page or an export of one).
const exemptBanned = (f) => /FACTS\.md$|33-claims-policy\.md$|31-release-notes\.md$/.test(f) || readFileSync(f, 'utf8').split(/\r?\n/, 3).join('\n').includes('docs_guard: allow-banned');

for (const file of scope) {
  const text = readFileSync(file, 'utf8');
  const lines = text.split(/\r?\n/);
  const isGuide = /docs[\\/]guides[\\/]/.test(file);
  const isFacts = file === factsPath;

  // 3. build stamps
  if (isGuide) {
    if (!/Describes build:\s*2\.5\.10\+\d+/.test(text)) fail(file, 1, 'missing "Describes build: 2.5.10+N"');
    const lv = /Last verified:\s*(\d{4}-\d{2}-\d{2})/.exec(text);
    if (!lv) fail(file, 1, 'missing "Last verified: YYYY-MM-DD"');
    else if ((Date.now() - Date.parse(lv[1])) / 86400000 > 90) warn(file, 1, `last verified ${lv[1]} is older than 90 days`);
  }

  let inCode = false;
  let para = [];
  const paras = []; // [{start, text}]
  lines.forEach((ln, i) => {
    if (/^\s*```/.test(ln)) inCode = !inCode;
    if (!inCode && ln.trim() === '') { if (para.length) paras.push({ start: i + 1 - para.length, text: para.join('\n') }); para = []; }
    else if (!inCode) para.push(ln);
  });
  if (para.length) paras.push({ start: lines.length + 1 - para.length, text: para.join('\n') });

  inCode = false;
  lines.forEach((ln, idx) => {
    const n = idx + 1;
    if (/^\s*```/.test(ln)) { inCode = !inCode; return; }
    if (inCode) return;
    const noCode = ln.replace(/`[^`]*`/g, '``');

    // 1. bold labels
    if (!isFacts) {
      for (const m of noCode.matchAll(/\*\*([^*\n]+?)\*\*/g)) {
        if (/[:?]\s*$/.test(m[1])) continue; // a bold lead-in ("If you don't:") or FAQ question is structure, not a label
        for (let part of m[1].split('→')) {
          part = part.trim().replace(/[.:]+$/, '');
          if (!part || !/^[A-Z0-9"]/.test(part) || part.split(/\s+/).length > 6) continue;
          const key = part.replace(/^"|"$/g, '').toLowerCase();
          if (allow.has(key) || literals.has(key) || /^T-[A-Z]+\d+$/.test(part)) continue;
          fail(file, n, `bold label "${part}" is not a string literal in lib/ (add it to scripts/docs_guard_allow.txt only if it is real)`);
        }
      }
    }

    // 2. routes and paths
    for (const m of noCode.matchAll(/(?<![\w/.])(\/(?:settings|setup|installer|demo|first-run|welcome|roofline-setup-wizard)(?:\/[a-z0-9-]+)*)\b/g)) {
      if (!routerSrc.includes(`'${m[1]}'`) && !routerSrc.includes(`'${m[1].split('/').pop()}'`)) fail(file, n, `route ${m[1]} not found in lib/app_router.dart`);
    }
    for (const m of ln.matchAll(/\b((?:lib|docs|scripts|test|functions|esp32-bridge)\/[A-Za-z0-9_.+/-]+?)(?::\d+(?:[–-]\d+)?(?:,\d+(?:[–-]\d+)?)*)?(?=[\s)`'",;:]|$)/g)) {
      const p = m[1].replace(/[.,]+$/, '');
      if (!existsSync(join(ROOT, p))) fail(file, n, `path ${p} does not exist`);
    }
    for (const m of ln.matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)) {
      const target = m[1].split('#')[0];
      if (!target || /^(https?:|mailto:|tel:)/.test(target)) continue;
      const abs = target.startsWith('/') ? join(ROOT, target) : resolve(dirname(file), target);
      if (!existsSync(abs)) fail(file, n, `link target ${target} does not exist`);
    }

    // 3. build numbers
    for (const m of ln.matchAll(/2\.5\.10\+(\d+)/g)) if (Number(m[1]) > pubBuild) fail(file, n, `build 2.5.10+${m[1]} is above pubspec (+${pubBuild})`);

    // 4. fact ids
    for (const m of ln.matchAll(/\bT-[A-Z]+\d+\b/g)) if (!facts.has(m[0])) fail(file, n, `fact ${m[0]} is not in docs/FACTS.md`);

    // 5. banned phrases
    if (!exemptBanned(file)) {
      for (const [re, why] of BANNED) {
        if (re.test(noCode)) {
          // allow a sentence that negates the claim ("there is no bridge web page", "Alexa is not available")
          const sentence = noCode.split(/(?<=[.!?])\s+/).find((s) => re.test(s)) ?? noCode;
          if (BANNED_NEGATION_OK.test(sentence) && !/quinled|0\.1[45]\.\d|OpenAI|Lumina-XXXX|Upload system logs/i.test(sentence)) continue;
          fail(file, n, `banned phrase (${why}); see docs/guides/internal/33-claims-policy.md`);
        }
      }
    }

    // 6. PII
    for (const [re, kind] of PII) {
      const m = re.exec(ln);
      if (m && !PII_OK.some((ok) => ok.test(m[0]))) fail(file, n, `${kind} pattern found; documents never carry one`);
    }
  });

  // 4b. unshipped facts cited inline must be qualified
  if (isGuide) {
    for (const p of paras) {
      if (/^\*?Facts:/m.test(p.text)) continue; // the footer list is a citation index, not a claim
      for (const m of p.text.matchAll(/\bT-[A-Z]+\d+\b/g)) {
        const st = facts.get(m[0]) ?? '';
        if (UNSHIPPED.test(st) && !QUALIFIER.test(p.text)) fail(file, p.start, `${m[0]} is ${st.split(';')[0]} but the paragraph does not say it is coming / not available`);
      }
    }
  }
}

// --links-all: every markdown link under docs/ (archive and engineering notes included), as warnings outside the scope
if (LINKS_ALL) {
  for (const file of walk(join(ROOT, 'docs'), (p) => p.endsWith('.md'))) {
    if (scope.includes(file)) continue;
    const lines = readFileSync(file, 'utf8').split(/\r?\n/);
    lines.forEach((ln, idx) => {
      for (const m of ln.matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)) {
        const target = m[1].split('#')[0];
        if (!target || /^(https?:|mailto:|tel:)/.test(target)) continue;
        const abs = target.startsWith('/') ? join(ROOT, target) : resolve(dirname(file), target);
        if (!existsSync(abs)) warn(file, idx + 1, `link target ${target} does not exist`);
      }
    });
  }
}

for (const w of warns) console.log(w);
for (const f of fails) console.log(f);
console.log(`docs_guard: ${scope.length} files checked, ${facts.size} facts, ${fails.length} failure(s), ${warns.length} warning(s)`);
process.exit(fails.length ? 1 : 0);
