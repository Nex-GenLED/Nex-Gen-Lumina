// CELEBRATION-PICKER WIRING bench run — transient state writes only. No psave,
// no /json/cfg POST, no Firestore. Snapshot -> play -> restore -> verify.
// Aborts before any write unless the controller is idle.
//
// Same discipline (and the same snapshot / pre-flight / restore / diff code) as
// evidence/gameday-rainbow-fix-2026-09-21/bench_gd_fix_verify.mjs.
//
//   node bench_gd_picker_verify.mjs <picker_payloads.json> <out-prefix> [--dry]
//
// --dry builds and prints the plan and exits. It opens no socket and sends
// nothing — it is how this script was checked on a machine that could not
// reach the bench.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const IP = process.env.BENCH_IP || '192.168.1.150';
const BASE = `http://${IP}`;
const args = process.argv.slice(2);
const DRY = args.includes('--dry');
const [PAYLOADS, OUT] = args.filter((a) => !a.startsWith('--'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sha = (s) => createHash('sha256').update(s).digest('hex').slice(0, 16);
const getText = async (p) => (await fetch(BASE + p, { signal: AbortSignal.timeout(8000) })).text();
const post = async (body) => (await fetch(BASE + '/json/state', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body), signal: AbortSignal.timeout(8000),
})).status;

// ---- payloads: written by the Dart probe from the REAL coordinator ---------
const probe = JSON.parse(readFileSync(PAYLOADS, 'utf8'));
const rows = probe.payloads;
const clone = (o) => JSON.parse(JSON.stringify(o));
const stage = (pick, n) => {
  const r = rows.find((x) => x.pick === pick && x.stage === n);
  if (!r) throw new Error(`probe has no pick=${pick} stage=${n}`);
  return r;
};
/** The same wire with `pal` forced — what the stage carries once this branch
 *  converges with the colour fix (60282a3 asserts pal:0 on every legacy stage
 *  and _applyCelebrationToStage spreads it through), or a candidate palette. */
const withPal = (wire, pal) => { const w = clone(wire); for (const s of w.seg) s.pal = pal; return w; };

// Colour-reading picks: several, deliberately different kinds of motion.
const PICKS = [28, 76, 91, 25, 113];
// The six the catalog marks as not colour-reading.
const SIX = [32, 29, 64, 42, 90, 89];
const name = (pick) => stage(pick, 1).pickName;

const plan = [
  // 0. Control: NO pick. On this branch's base that is the legacy table
  //    (the unmerged colour fix changes these ids, not this path).
  { group: 'CONTROL no pick', label: `legacy stage 2 — fx ${stage(null, 2).fx} ${stage(null, 2).fxName}`, wire: stage(null, 2).wire },
  // 1. Different picks must render differently. Stage 1 carries on/bri.
  //    Each also under pal:5 — what the picker's PREVIEW sends for a col-based
  //    effect (WledEffectsCatalog.paletteForEffect) — to see whether the look
  //    the user approved is the look that fires.
  ...PICKS.flatMap((p) => [
    { group: 'PICK pal:0 (as converged)', pick: p, label: `pick ${p} ${name(p)} — stage 1, pal:0`, wire: withPal(stage(p, 1).wire, 0) },
    { group: 'PICK pal:5 (as previewed)', pick: p, label: `pick ${p} ${name(p)} — stage 1, pal:5`, wire: withPal(stage(p, 1).wire, 5) },
  ]),
  // 2. The six — as they will ship (pal:0), and under "Color Gradient"
  //    (pal:4): what the picker's PREVIEW sends for them, and the candidate
  //    remedy in the report's decision point.
  ...SIX.flatMap((p) => [
    { group: 'SIX pal:0 (as converged)', pick: p, label: `pick ${p} ${name(p)} [${stage(p, 1).colorBehavior}] pal:0`, wire: withPal(stage(p, 1).wire, 0) },
    { group: 'SIX pal:4 (as previewed)', pick: p, label: `pick ${p} ${name(p)} [${stage(p, 1).colorBehavior}] pal:4`, wire: withPal(stage(p, 1).wire, 4) },
  ]),
  // 3. Convergence dependency: on THIS branch a chosen stage carries no `pal`,
  //    so over a look on a real palette it inherits that palette.
  { group: 'PAL setup', label: 'base look -> pal 11 on both segments', wire: { seg: [{ id: 0, pal: 11 }, { id: 1, pal: 11 }] }, noAnalyze: true },
  { group: 'PAL absent (this branch alone)', pick: 28, label: 'pick 28 Chase, pal OMITTED, over pal-11 base', wire: stage(28, 1).wire },
  { group: 'PAL 0 (as converged)', pick: 28, label: 'pick 28 Chase, pal:0, over pal-11 base', wire: withPal(stage(28, 1).wire, 0), rebase: true },
];

if (DRY) {
  for (const s of plan) console.log(JSON.stringify({ group: s.group, label: s.label, seg0: s.wire.seg[0] }));
  console.log(JSON.stringify({ dry: true, steps: plan.length, estSeconds: Math.round(plan.length * 5.4) }));
  process.exit(0);
}

// ---- colour analysis (unchanged from the colour-fix bench) -----------------
function hue(r, g, b) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  if (d === 0) return null;
  let h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  h *= 60; return h < 0 ? h + 360 : h;
}
const angDist = (a, b) => { const d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d; };
let GAMMA = 2.8;
const gam = (v) => Math.round(255 * Math.pow(v / 255, GAMMA));
function teamHues(wire) {
  const seg = wire.seg.find((s) => Array.isArray(s.col)); if (!seg) return null;
  return seg.col.slice(0, 2).filter((c) => c.some((v) => v > 0)).map(([r, g, b]) => hue(gam(r), gam(g), gam(b))).filter((h) => h !== null);
}
const PAD = 20;
function inTeamArc(h, hs) {
  if (hs.length === 1) return angDist(h, hs[0]) <= PAD;
  const [a, b] = hs; const span = angDist(a, b);
  return angDist(h, a) + angDist(h, b) <= span + 2 * PAD;
}
function summarize(buf, hs) {
  const b = new Uint8Array(buf); if (b[0] !== 0x4c) return null;
  const off = b[1] === 2 ? 4 : 2;
  const buckets = new Array(12).fill(0); let lit = 0, grey = 0, inArc = 0, offTeam = 0;
  const distinct = new Set(); const sample = [];
  for (let i = off, n = 0; i + 2 < b.length; i += 3, n++) {
    const [r, g, bl] = [b[i], b[i + 1], b[i + 2]]; const mx = Math.max(r, g, bl);
    if (mx < 8) continue;
    lit++;
    const hex = [r, g, bl].map((v) => v.toString(16).padStart(2, '0')).join('');
    distinct.add(hex); if (n % 48 === 0 && sample.length < 7) sample.push(hex);
    const h = hue(r, g, bl); const sat = (mx - Math.min(r, g, bl)) / mx;
    // Greys are NOT off-team: a strobe's white-hot frame and Fireworks 1D's
    // white-to-colour fade are part of a colour-reading effect.
    if (h === null || sat < 0.15) { grey++; continue; }
    buckets[Math.floor(h / 30) % 12]++;
    if (hs && hs.length) { if (inTeamArc(h, hs)) inArc++; else offTeam++; }
  }
  const pct = (n) => (lit ? Math.round((1000 * n) / lit) / 10 : 0);
  return { lit, grey, hueBucketsUsed: buckets.filter((n) => n > 0).length, buckets: buckets.join(','),
    inTeamArcPct: pct(inArc), offTeamPct: pct(offTeam), distinctColours: distinct.size, sample };
}
/** Share of LEDs whose colour differs between two raw frames — the MOTION
 *  signature. A still image cannot tell Chase from Strobe Mega; a series can. */
function changedPct(a, b) {
  if (!a || !b) return null;
  const x = new Uint8Array(a), y = new Uint8Array(b); const off = x[1] === 2 ? 4 : 2;
  let n = 0, ch = 0;
  for (let i = off; i + 2 < Math.min(x.length, y.length); i += 3, n++) {
    if (Math.abs(x[i] - y[i]) + Math.abs(x[i + 1] - y[i + 1]) + Math.abs(x[i + 2] - y[i + 2]) > 24) ch++;
  }
  return n ? Math.round((1000 * ch) / n) / 10 : null;
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
    const hs = teamHues(step.wire); const frames = []; const raws = [];
    // A frame SERIES, not a still: 8 frames, 400 ms apart.
    for (let i = 0; i < 8; i++) { raws.push(latest); frames.push(latest ? summarize(latest, hs) : null); await sleep(400); }
    const motion = raws.slice(1).map((f, i) => changedPct(raws[i], f));
    const ok = frames.filter(Boolean);
    const mean = (k) => (ok.length ? Math.round((10 * ok.reduce((a, f) => a + f[k], 0)) / ok.length) / 10 : null);
    const st = JSON.parse(await getText('/json/state'));
    say({ phase: 'play', group: step.group, pick: step.pick ?? null, label: step.label, status, bri: st.bri,
      expectedTeamHues: hs.map((h) => Math.round(h)), segAfter: st.seg.map((s) => ({ id: s.id, fx: s.fx, pal: s.pal })),
      signature: { meanLit: mean('lit'), meanOffTeamPct: mean('offTeamPct'), meanInTeamArcPct: mean('inTeamArcPct'),
        maxHueBuckets: Math.max(0, ...ok.map((f) => f.hueBucketsUsed)), motionChangedPct: motion },
      frames });
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
