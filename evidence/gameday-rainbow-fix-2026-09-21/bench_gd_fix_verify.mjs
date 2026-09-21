// FIX VERIFICATION bench run — transient state writes only. No psave, no
// /json/cfg POST, no Firestore. Snapshot -> play -> restore -> verify.
// Aborts before any write unless the controller is idle.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const IP = '192.168.1.150';
const BASE = `http://${IP}`;
const [PAYLOADS, OUT] = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sha = (s) => createHash('sha256').update(s).digest('hex').slice(0, 16);
const getText = async (p) => (await fetch(BASE + p, { signal: AbortSignal.timeout(8000) })).text();
const post = async (body) => (await fetch(BASE + '/json/state', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body), signal: AbortSignal.timeout(8000),
})).status;

// ---- payloads: written by the Dart probe from the FIXED code --------------
const fixed = JSON.parse(readFileSync(PAYLOADS, 'utf8'));
const clone = (o) => JSON.parse(JSON.stringify(o));
const OLD_FX = { 3: 9, 15: 63, 13: 5 };
/** Reconstruct the pre-fix payload: old effect id, no `pal`. */
const asShipped = (wire) => { const w = clone(wire); for (const s of w.seg) { if (s.fx in OLD_FX) s.fx = OLD_FX[s.fx]; delete s.pal; } return w; };
/** Fix A only: corrected effect id, but `pal` still omitted. */
const withoutPal = (wire) => { const w = clone(wire); for (const s of w.seg) delete s.pal; return w; };

const td = fixed.filter((r) => r.label.includes('touchdown'));
const plan = [
  ...fixed.map((r) => ({ group: 'AFTER (fixed)', label: `${r.label} — fx ${r.fx} ${r.name}`, wire: r.wire })),
  // Same-session control: exactly what shipped, played under identical conditions.
  { group: 'BEFORE (as shipped)', label: 'chiefs touchdown stage 2 — fx 9 Rainbow, no pal', wire: asShipped(td[1].wire) },
  { group: 'BEFORE (as shipped)', label: 'chiefs touchdown stage 3 — fx 63 Pride 2015, no pal', wire: asShipped(td[2].wire) },
  // Fix B: a base look on a NON-ZERO palette (11 = Rainbow), then the stage with and without pal:0.
  { group: 'FIX-B setup', label: 'base look -> pal 11 on both segments', wire: { seg: [{ id: 0, pal: 11 }, { id: 1, pal: 11 }] }, noAnalyze: true },
  { group: 'FIX-B without pal', label: 'touchdown stage 3 fx 15, pal OMITTED, over pal-11 base', wire: withoutPal(td[2].wire) },
  { group: 'FIX-B with pal:0', label: 'touchdown stage 3 fx 15, pal:0 (as fixed), over pal-11 base', wire: td[2].wire, rebase: true },
  { group: 'FIX-B without pal', label: 'touchdown stage 2 fx 3, pal OMITTED, over pal-11 base', wire: withoutPal(td[1].wire), rebase: true },
  { group: 'FIX-B with pal:0', label: 'touchdown stage 2 fx 3, pal:0 (as fixed), over pal-11 base', wire: td[1].wire, rebase: true },
];

// ---- colour analysis ------------------------------------------------------
function hue(r, g, b) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  if (d === 0) return null;
  let h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  h *= 60; return h < 0 ? h + 360 : h;
}
const angDist = (a, b) => { const d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d; };
let GAMMA = 2.8;
const gam = (v) => Math.round(255 * Math.pow(v / 255, GAMMA));
/** Expected hues = the payload's col[0]/col[1] after the controller's gamma. */
function teamHues(wire) {
  const seg = wire.seg.find((s) => Array.isArray(s.col)); if (!seg) return null;
  return seg.col.slice(0, 2).filter((c) => c.some((v) => v > 0)).map(([r, g, b]) => hue(gam(r), gam(g), gam(b))).filter((h) => h !== null);
}
const PAD = 20;
function inTeamArc(h, hs) {
  if (hs.length === 1) return angDist(h, hs[0]) <= PAD;
  const [a, b] = hs; const span = angDist(a, b);
  // on the shorter arc between a and b (padded): dist to a + dist to b == span
  return angDist(h, a) + angDist(h, b) <= span + 2 * PAD;
}
function summarize(buf, hs) {
  const b = new Uint8Array(buf); if (b[0] !== 0x4c) return null;
  const off = b[1] === 2 ? 4 : 2;
  const buckets = new Array(12).fill(0); let lit = 0, grey = 0, inArc = 0, atEndpoint = 0, offTeam = 0;
  const distinct = new Set(); const sample = [];
  for (let i = off, n = 0; i + 2 < b.length; i += 3, n++) {
    const [r, g, bl] = [b[i], b[i + 1], b[i + 2]]; const mx = Math.max(r, g, bl);
    if (mx < 8) continue;
    lit++;
    const hex = [r, g, bl].map((v) => v.toString(16).padStart(2, '0')).join('');
    distinct.add(hex); if (n % 48 === 0 && sample.length < 7) sample.push(hex);
    const h = hue(r, g, bl); const sat = (mx - Math.min(r, g, bl)) / mx;
    if (h === null || sat < 0.15) { grey++; continue; }
    buckets[Math.floor(h / 30) % 12]++;
    if (hs && hs.length) {
      if (inTeamArc(h, hs)) inArc++; else offTeam++;
      if (hs.some((t) => angDist(h, t) <= PAD)) atEndpoint++;
    }
  }
  const pct = (n) => (lit ? Math.round((1000 * n) / lit) / 10 : 0);
  return { lit, grey, hueBucketsUsed: buckets.filter((n) => n > 0).length, buckets: buckets.join(','),
    inTeamArcPct: pct(inArc), atTeamEndpointPct: pct(atEndpoint), offTeamPct: pct(offTeam), distinctColours: distinct.size, sample };
}

const log = []; const say = (o) => { log.push(o); console.log(JSON.stringify(o)); };

// ---- snapshot -------------------------------------------------------------
const snapText = await getText('/json/state'); const snap = JSON.parse(snapText);
const cfgText = await getText('/json/cfg');
const presetsBefore = sha(await getText('/presets.json')); const cfgBefore = sha(cfgText);
try { const g = JSON.parse(cfgText)?.light?.gc?.col; if (typeof g === 'number' && g > 1) GAMMA = g; } catch {}
say({ phase: 'snapshot', on: snap.on, bri: snap.bri, ps: snap.ps, gamma: GAMMA,
  segs: snap.seg.map((s) => ({ id: s.id, on: s.on, fx: s.fx, pal: s.pal, frz: s.frz })), presetsBefore, cfgBefore });
writeFileSync(OUT + '.snapshot.json', snapText);

// PRE-FLIGHT ABORT: only an idle controller is touched.
if (snap.on !== false || snap.seg.some((s) => s.on !== false) || snap.seg.some((s) => s.frz)) {
  say({ phase: 'ABORT', reason: 'controller not idle (on / seg on / frozen). Nothing was written.' });
  writeFileSync(OUT + '.log.json', JSON.stringify(log, null, 1)); process.exit(2);
}

let latest = null;
const ws = new WebSocket(`ws://${IP}/ws`); ws.binaryType = 'arraybuffer';
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; setTimeout(() => rej(new Error('ws timeout')), 6000); });
ws.onmessage = (m) => { if (typeof m.data !== 'string') latest = m.data; };
ws.send(JSON.stringify({ lv: true }));

let restoreOk = false;
try {
  for (const step of plan) {
    if (step.rebase) { await post({ seg: [{ id: 0, pal: 11 }, { id: 1, pal: 11 }] }); await sleep(300); }
    const status = await post(step.wire);
    if (step.noAnalyze) { await sleep(600); say({ phase: 'play', group: step.group, label: step.label, status }); continue; }
    await sleep(1600); // past the 0.7 s transition
    const hs = teamHues(step.wire); const frames = [];
    for (let i = 0; i < 4; i++) { frames.push(latest ? summarize(latest, hs) : null); await sleep(700); }
    const st = JSON.parse(await getText('/json/state'));
    say({ phase: 'play', group: step.group, label: step.label, status, bri: st.bri,
      expectedTeamHues: hs.map((h) => Math.round(h)), segAfter: st.seg.map((s) => ({ id: s.id, fx: s.fx, pal: s.pal })), frames });
  }
} finally {
  try { ws.send(JSON.stringify({ lv: false })); ws.close(); } catch {}
  const segRestore = snap.seg.map(({ start, stop, len, ...rest }) => rest);
  const s1 = await post({ on: snap.on, bri: snap.bri, transition: snap.transition, seg: segRestore });
  await sleep(1200);
  const s2 = await post({ ps: snap.ps });
  await sleep(2000);
  const after = JSON.parse(await getText('/json/state'));
  const presetsAfter = sha(await getText('/presets.json')); const cfgAfter = sha(await getText('/json/cfg'));
  const diffs = [];
  const cmp = (a, b, path) => {
    if (a && b && typeof a === 'object' && typeof b === 'object') { for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) cmp(a[k], b[k], `${path}.${k}`); }
    else if (a !== b) diffs.push({ path, before: a, after: b });
  };
  cmp(snap, after, 'state');
  restoreOk = diffs.length === 0 && presetsAfter === presetsBefore && cfgAfter === cfgBefore;
  say({ phase: 'restore', postStatus: [s1, s2], stateDiffs: diffs, presetsBefore, presetsAfter, cfgBefore, cfgAfter, restoreOk });
  writeFileSync(OUT + '.after.json', JSON.stringify(after));
}
writeFileSync(OUT + '.log.json', JSON.stringify(log, null, 1));
process.exit(restoreOk ? 0 : 3);
