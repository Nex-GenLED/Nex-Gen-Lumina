#!/usr/bin/env node
'use strict';

/**
 * pixelmap_cleanup_dry_run.js — stacked-segment cleanup for ONE controller's
 * pixelMap, dry run by default (+113).
 *
 * WHAT IT FINDS (the same two rules as lib/features/design/roofline_repair.dart;
 * keep them in step):
 *   * a segment with the same id as an earlier one AND the same lights
 *     (pixel_count, type, architectural_role, name) → REMOVE the later one;
 *   * a segment with the same stored start_pixel as an earlier one AND the
 *     same lights → REMOVE the later one;
 *   * a segment with the same id as an earlier one but DIFFERENT lights →
 *     RENAME it (`<id>_2`), never remove it.
 * Adjacent identical neighbours are REPORTED and left alone.
 *
 * WHAT IT NEVER DOES: change a kept segment's start/count, touch
 * source_pixel_count, or write anything without --confirm.
 *
 * WITH --confirm, per channel that has work, in one batch:
 *   1. merge-write segments_backup / segments_backup_at / segments_backup_reason
 *      with the channel's CURRENT segments (reversible: copy it back);
 *   2. update `segments` to the kept list (start_pixel rebased channel-local,
 *      sort_order renumbered, exactly as the app's write boundary does).
 *
 * Run (read-only):
 *   node scripts/pixelmap_cleanup_dry_run.js --uid=<uid> [--controller=<id>]
 * Write (after approval):
 *   node scripts/pixelmap_cleanup_dry_run.js --uid=<uid> --controller=<id> --confirm
 */

const path = require('path');
const admin = require('firebase-admin');
const { resolveServiceAccountPath } = require('./_service_account');

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    return m ? [m[1], m[2] === undefined ? true : m[2]] : [a, true];
  }),
);

if (!args.uid) {
  console.error('usage: --uid=<uid> [--controller=<controllerId>] [--confirm] [--key=<path>]');
  process.exit(2);
}

const keyPath = args.key ? String(args.key) : resolveServiceAccountPath();
const sa = require(path.resolve(keyPath));
admin.initializeApp({ credential: admin.credential.cert(sa), projectId: sa.project_id });
const db = admin.firestore();

const sig = (s) =>
  `${s.pixel_count}|${s.type || 'run'}|${s.architectural_role || ''}|${s.name || ''}`;

function planChannel(segments) {
  const kept = [];
  const removed = [];
  const renamed = [];
  const keptById = new Map();
  const keptByStart = new Map();
  const usedIds = new Set(segments.map((s) => s.id));
  for (const s of segments) {
    const same = keptById.get(s.id);
    if (same) {
      if (sig(same) === sig(s)) {
        removed.push({
          segment: s,
          keptInstead: same,
          reason: same.start_pixel === s.start_pixel ? 'stacked copy' : 'duplicate id',
        });
        continue;
      }
      let n = 2;
      let fresh = `${s.id}_${n}`;
      while (usedIds.has(fresh)) fresh = `${s.id}_${++n}`;
      usedIds.add(fresh);
      const r = { ...s, id: fresh };
      renamed.push({ segment: s, newId: fresh });
      kept.push(r);
      keptById.set(fresh, r);
      (keptByStart.get(s.start_pixel) || keptByStart.set(s.start_pixel, []).get(s.start_pixel)).push(r);
      continue;
    }
    const stacked = (keptByStart.get(s.start_pixel) || []).filter((k) => sig(k) === sig(s));
    if (stacked.length) {
      removed.push({ segment: s, keptInstead: stacked[0], reason: 'stacked copy' });
      continue;
    }
    kept.push(s);
    keptById.set(s.id, s);
    (keptByStart.get(s.start_pixel) || keptByStart.set(s.start_pixel, []).get(s.start_pixel)).push(s);
  }
  const suspects = [];
  let run = [];
  for (const s of kept) {
    if (run.length && sig(run[run.length - 1]) === sig(s)) run.push(s);
    else {
      if (run.length > 1) suspects.push(run);
      run = [s];
    }
  }
  if (run.length > 1) suspects.push(run);
  return { kept, removed, renamed, suspects, hasWork: removed.length > 0 || renamed.length > 0 };
}

const desc = (s) =>
  `"${s.name}" (${s.type || 'run'}${s.architectural_role ? '/' + s.architectural_role : ''}) ` +
  `lights ${s.start_pixel + 1}-${s.start_pixel + s.pixel_count} [id ${s.id}]`;

function rebase(kept) {
  let start = 0;
  return kept.map((s, i) => {
    const out = { ...s, start_pixel: start, sort_order: i };
    start += s.pixel_count;
    return out;
  });
}

(async () => {
  const uid = String(args.uid);
  const ctrlCol = db.collection(`users/${uid}/controllers`);
  const ctrlIds = args.controller ? [String(args.controller)] : (await ctrlCol.get()).docs.map((d) => d.id);
  if (!ctrlIds.length) {
    console.log('no controllers under that user');
    return;
  }
  let totalWork = 0;
  for (const cid of ctrlIds) {
    const pm = await db.collection(`users/${uid}/controllers/${cid}/pixelMap`).get();
    console.log(`\ncontroller ${cid.slice(0, 8)}…  pixelMap docs: ${pm.size}`);
    const batch = db.batch();
    let work = 0;
    for (const d of pm.docs) {
      const x = d.data() || {};
      const segs = x.segments || [];
      const p = planChannel(segs);
      const sum = segs.reduce((a, s) => a + (s.pixel_count || 0), 0);
      console.log(`  channel doc ${d.id}: ${segs.length} segments, ${sum} lights mapped, strip ${x.source_pixel_count}`);
      if (!p.hasWork) {
        console.log('    nothing to clean up');
      } else {
        for (const r of p.removed) console.log(`    REMOVE ${desc(r.segment)} — ${r.reason} of ${desc(r.keptInstead)}`);
        for (const r of p.renamed) console.log(`    RENAME ${desc(r.segment)} -> id ${r.newId}`);
        const keptSum = p.kept.reduce((a, s) => a + s.pixel_count, 0);
        console.log(`    KEEP ${p.kept.length} segments, ${keptSum} lights (after save, lights renumber channel-local):`);
        for (const s of rebase(p.kept)) console.log(`      ${desc(s)}`);
        if (x.segments_backup) console.log('    NOTE this doc already carries a segments_backup; --confirm would overwrite it');
      }
      for (const g of p.suspects) console.log(`    NOTE identical neighbours left alone: ${g.map(desc).join(', ')}`);
      if (p.hasWork && args.confirm) {
        batch.set(
          d.ref,
          {
            segments_backup: segs,
            segments_backup_at: admin.firestore.Timestamp.now(),
            segments_backup_reason: 'duplicate cleanup (script)',
          },
          { merge: true },
        );
        batch.update(d.ref, { segments: rebase(p.kept), updated_at: admin.firestore.Timestamp.now() });
        work++;
      }
      if (p.hasWork) totalWork++;
    }
    if (args.confirm && work > 0) {
      await batch.commit();
      console.log(`  WROTE ${work} channel doc(s) (backup + cleaned segments)`);
    }
  }
  console.log(`\n${totalWork} channel doc(s) with work. ${args.confirm ? 'Written.' : 'DRY RUN — nothing written. Add --confirm to apply.'}`);
})().catch((e) => {
  console.error('ERR', e);
  process.exit(1);
});
