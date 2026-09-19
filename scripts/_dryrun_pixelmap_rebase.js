// _dryrun_pixelmap_rebase.js
//
// DRY RUN ONLY. READ-ONLY. There is NO write path in this file — it issues one
// Firestore collection-group `runQuery` and prints a report. It exists so a
// human can decide what (if anything) to do about production pixelMap
// documents written before the 2.5.10+101 fix.
//
// BACKGROUND (design-studio-audit-2026-09-19 F4; followup N1b/N1c):
// `RooflineSegment.start_pixel` is CHANNEL-LOCAL — LED 0 is the first LED of the
// segment's own hardware channel. Until +101 one writer
// (RooflineConfiguration.recalculateStartPixels) numbered segments
// CUMULATIVELY across every channel, and the Roofline Setup Wizard saved every
// segment with no channel at all. Readers treat start_pixel as channel-local,
// so such a map selects / paints the wrong LEDs, or none.
//
// WHAT IT REPORTS, per /users/{uid}/controllers/{cid}/pixelMap/{channel} doc:
//   - stored start_pixel vs the channel-local value re-derived from segment
//     order + pixel_count (segments are a gapless ordered run in every writer,
//     so start_pixel is DERIVED data);
//   - whether the mapped total fits source_pixel_count (the bus length
//     recorded at map time).
// and classifies each doc:
//   OK        — already channel-local and fits.
//   REBASE    — start_pixel is offset; re-deriving it makes the doc valid.
//               Mechanical. Corrected values are listed.
//   OVERFLOW  — the mapped total is LARGER than source_pixel_count: the
//               segments describe more LEDs than the strip has (e.g. a whole
//               roof saved onto channel 1). Re-basing alone does NOT make it
//               valid. Needs a human / a remap.
//   REBASE+OVERFLOW — both.
// and, independently, flags PARTIAL: the map covers fewer LEDs than the strip.
// That is not corruption — the mapped part is valid and fully usable; the
// rest of the strip simply is not mapped yet. Listed so it is not mistaken
// for damage.
//
// PRIVACY: prints counts, indices and 6-character id prefixes only. No names,
// emails, addresses, segment names or design content are read into the report.
//
// Usage (gcloud ADC — no service-account key, no node_modules):
//   FS_TOKEN=$(gcloud auth print-access-token) node scripts/_dryrun_pixelmap_rebase.js [--json out.json]

'use strict';

const fs = require('fs');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

// ── Firestore REST value decoding ───────────────────────────────────────────
function dec(v) {
  if (v == null) return null;
  if ('integerValue' in v) return parseInt(v.integerValue, 10);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(dec);
  if ('mapValue' in v) {
    const o = {};
    for (const [k, x] of Object.entries(v.mapValue.fields || {})) o[k] = dec(x);
    return o;
  }
  return null;
}

async function runQuery(token, pageToken) {
  // Collection group over every `pixelMap` subcollection. READ.
  const body = {
    structuredQuery: {
      from: [{ collectionId: 'pixelMap', allDescendants: true }],
      orderBy: [{ field: { fieldPath: '__name__' }, direction: 'ASCENDING' }],
      limit: 300,
      ...(pageToken ? { startAt: { values: [{ referenceValue: pageToken }], before: false } } : {}),
    },
  };
  const res = await fetch(`${BASE}:runQuery`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'x-goog-user-project': PROJECT_ID,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`runQuery HTTP ${res.status}: ${await res.text()}`);
  return (await res.json()).filter((r) => r.document).map((r) => r.document);
}

(async () => {
  const token = process.env.FS_TOKEN;
  if (!token) {
    console.error('Set FS_TOKEN=$(gcloud auth print-access-token)');
    process.exitCode = 2;
    return;
  }
  const jsonOut = process.argv.includes('--json')
    ? process.argv[process.argv.indexOf('--json') + 1] : null;

  const docs = [];
  let cursor = null;
  for (;;) {
    const page = await runQuery(token, cursor);
    docs.push(...page);
    if (page.length < 300) break;
    cursor = page[page.length - 1].name;
  }

  const rows = [];
  for (const d of docs) {
    // …/documents/users/{uid}/controllers/{cid}/pixelMap/{channel}
    const parts = d.name.split('/documents/')[1].split('/');
    if (parts[0] !== 'users' || parts[2] !== 'controllers' || parts[4] !== 'pixelMap') continue;
    const [, uid, , cid, , channelDoc] = parts;
    const f = {};
    for (const [k, v] of Object.entries(d.fields || {})) f[k] = dec(v);
    const channelIndex = Number.isInteger(f.channel_index) ? f.channel_index : parseInt(channelDoc, 10);
    const segs = (f.segments || []).map((s) => ({
      start: s.start_pixel ?? 0,
      count: s.pixel_count ?? 0,
      type: s.type ?? 'run',
      anchors: (s.anchor_pixels || []).length,
      segChannel: s.channel_index ?? 0,
    }));

    let cursorPx = 0;
    const corrected = [];
    let needsRebase = false;
    for (const s of segs) {
      corrected.push(cursorPx);
      if (s.start !== cursorPx) needsRebase = true;
      cursorPx += s.count;
    }
    const mapped = cursorPx;
    const source = f.source_pixel_count ?? 0;
    const overflow = source > 0 && mapped > source;
    const partial = source > 0 && mapped < source;
    // Would the STORED values fit the recorded strip as they are?
    const storedEnd = segs.reduce((m, s) => Math.max(m, s.start + s.count), 0);
    const storedOutOfRange = source > 0 && storedEnd > source;
    // How many of this channel's LEDs the editor's tools can reach TODAY.
    let reachable = 0;
    for (const s of segs) {
      for (let i = s.start; i < s.start + s.count; i++) if (i >= 0 && i < source) reachable++;
    }

    rows.push({
      user: uid.slice(0, 6), staffUid: uid.startsWith('staff_'),
      controller: cid.slice(0, 6), channel: channelIndex,
      segments: segs.length, mapped, source,
      storedStarts: segs.map((s) => s.start), correctedStarts: corrected,
      types: [...new Set(segs.map((s) => s.type))],
      anchors: segs.reduce((n, s) => n + s.anchors, 0),
      segChannelMismatch: segs.some((s) => s.segChannel !== channelIndex),
      isStaleStored: f.is_stale === true,
      needsRebase, overflow, partial, storedOutOfRange,
      reachableToday: source > 0 ? `${reachable}/${source}` : 'n/a',
      klass: needsRebase && overflow ? 'REBASE+OVERFLOW' : needsRebase ? 'REBASE' : overflow ? 'OVERFLOW' : 'OK',
      updatedAt: (f.updated_at || '').slice(0, 10),
    });
  }

  rows.sort((a, b) => (a.user + a.controller).localeCompare(b.user + b.controller) || a.channel - b.channel);

  const by = (k) => rows.reduce((m, r) => ((m[r[k]] = (m[r[k]] || 0) + 1), m), {});
  const affected = rows.filter((r) => r.klass !== 'OK');
  const installs = (rs) => new Set(rs.map((r) => `${r.user}/${r.controller}`)).size;
  const users = (rs) => new Set(rs.map((r) => r.user)).size;

  console.log(`pixelMap docs read: ${rows.length}  |  controllers: ${installs(rows)}  |  users: ${users(rows)}`);
  console.log('by class:', JSON.stringify(by('klass')));
  console.log(`affected docs: ${affected.length}  |  affected controllers (installs): ${installs(affected)}  |  affected users: ${users(affected)}`);
  console.log(`  of which under a staff_* uid (never handed off): ${affected.filter((r) => r.staffUid).length} docs`);
  console.log(`PARTIAL maps (valid, just incomplete — NOT counted as affected): ${rows.filter((r) => r.partial).length} docs`);
  console.log(`docs whose stored is_stale flag is true: ${rows.filter((r) => r.isStaleStored).length}`);
  console.log(`segment types fleet-wide: ${JSON.stringify(rows.reduce((m, r) => (r.types.forEach((t) => (m[t] = (m[t] || 0) + 1)), m), {}))}`);
  console.log('');
  console.log('user   ctrl   ch segs mapped source  class           reachable  stored start_pixel → corrected');
  for (const r of rows) {
    const change = r.needsRebase ? `${JSON.stringify(r.storedStarts)} → ${JSON.stringify(r.correctedStarts)}` : '(unchanged)';
    console.log(
      `${r.user} ${r.controller} ${String(r.channel).padStart(2)} ${String(r.segments).padStart(4)} ` +
      `${String(r.mapped).padStart(6)} ${String(r.source).padStart(6)}  ${r.klass.padEnd(15)} ${r.reachableToday.padEnd(10)} ${change}` +
      (r.partial ? '  [partial map]' : '') + (r.staffUid ? '  [staff uid]' : '') + (r.segChannelMismatch ? '  [seg.channel_index ≠ doc]' : ''));
  }
  if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify({ generatedAt: new Date().toISOString(), rows }, null, 1));
  console.log('\nDRY RUN — nothing was written. This script has no write path.');
})().catch((e) => {
  console.error(String(e));
  process.exitCode = 1;
});
