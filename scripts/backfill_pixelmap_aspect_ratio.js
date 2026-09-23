#!/usr/bin/env node
//
// backfill_pixelmap_aspect_ratio.js — stamp `source_aspect_ratio` onto
// users/{uid}/controllers/{cid}/pixelMap/{channel} documents that lack it.
//
// DRY RUN BY DEFAULT. Nothing is written without --confirm.
//
// ── WHY ──────────────────────────────────────────────────────────────────
//
// residential-path-audit-2026-09-23 §0 / §3.4 / §9.1(12) / §9.3.5:
// PixelMapChannel.toJson (lib/models/pixel_map_channel.dart:217-230) never
// emits source_aspect_ratio, so 24 of 24 production pixelMap docs lack it.
// The painter's assert that would catch a mis-projection is release-stripped
// (roofline_light_painter.dart:517-524), so a map drawn on a photo of one
// aspect ratio and shown at another silently lands on the wrong LEDs.
//
// ── ORDERING — DO NOT RUN BEFORE +107 ────────────────────────────────────
//
// The client must first learn the field (§9.1(12): model + writer + reader).
// Until then this backfill is inert (the reader ignores unknown keys) AND
// fragile: the current writer saves the whole document from toJson(), so
// the next client save of that channel drops the backfilled key again. Run
// it once the +107 writer round-trips the field.
//
// ── WHERE THE VALUE COMES FROM (per doc, first match wins) ───────────────
//
//   1. users/{uid}.roofline_mask.source_aspect_ratio — the aspect ratio of
//      the house photo at the moment the roofline was traced. The pixel map
//      was drawn on the same photo, so this is the value the painter needs.
//      (20 users carry one on 2026-09-23.)
//   2. users/{uid}.house_photo_url — the photo's intrinsic width/height,
//      read from the image header (PNG / JPEG / GIF / WebP). A JPEG whose
//      EXIF orientation is 5–8 is displayed transposed; such a photo is
//      reported as AMBIGUOUS and left unresolved for a human, never guessed.
//   3. otherwise UNRESOLVED (reported, not written).
//
// ── WHAT IT WRITES (per resolved doc, update) ────────────────────────────
//
//   { source_aspect_ratio: <number, width / height> }
//
// One key, nothing else. Never overwrites a doc that already has the field.
//
// ── PRIVACY ──────────────────────────────────────────────────────────────
//
// Prints 6-character uid / controller-id prefixes and channel doc ids only.
// The photo is read for its header and discarded; nothing is saved to disk.
//
// ── USAGE ────────────────────────────────────────────────────────────────
//
//   node scripts/backfill_pixelmap_aspect_ratio.js                # dry run (ADC)
//   node scripts/backfill_pixelmap_aspect_ratio.js --no-photo     # dry run, skip photo downloads
//   node scripts/backfill_pixelmap_aspect_ratio.js --key=<sa.json>
//   node scripts/backfill_pixelmap_aspect_ratio.js --confirm      # APPLY (after +107)
//
// Target project: icrt6menwsv2d8all8oijs021b06s5

'use strict';

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const FIELD = 'source_aspect_ratio';
const PIXELMAP_PATH = /^users\/([^/]+)\/controllers\/([^/]+)\/pixelMap\/([^/]+)$/;

function parseArgs(argv) {
  const args = { dryRun: true, keyPath: null, photo: true, skipStaff: false };
  for (const a of argv.slice(2)) {
    if (a === '--confirm') args.dryRun = false;
    else if (a === '--dry-run') args.dryRun = true;
    else if (a === '--no-photo') args.photo = false;
    else if (a === '--skip-staff') args.skipStaff = true;
    else if (a.startsWith('--key=')) args.keyPath = a.slice('--key='.length);
    else if (a === '--help' || a === '-h') {
      console.log(
        'Usage: node scripts/backfill_pixelmap_aspect_ratio.js [--confirm] [--dry-run] [--no-photo] [--skip-staff] [--key=<path>]\n' +
          '\n' +
          '  --confirm    Apply the writes. Without it, dry run (default).\n' +
          '  --no-photo   Do not download house photos for the fallback.\n' +
          '  --skip-staff Leave pixelMap docs under staff_* uids alone (leftovers\n' +
          '               of installer sessions; no customer reads them).\n' +
          '  --key=<path> Service-account JSON. Default: gcloud ADC.\n',
      );
      process.exit(0);
    } else {
      console.error('Unknown argument: ' + a);
      process.exit(2);
    }
  }
  return args;
}

function initApp(keyPath) {
  if (keyPath) {
    const creds = require(path.resolve(keyPath));
    admin.initializeApp({ credential: admin.credential.cert(creds), projectId: PROJECT_ID });
  } else {
    process.env.GOOGLE_CLOUD_QUOTA_PROJECT = process.env.GOOGLE_CLOUD_QUOTA_PROJECT || PROJECT_ID;
    admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: PROJECT_ID });
  }
}

// ── Image header parsing (no dependencies) ───────────────────────────────

/** Returns {width, height, format, exifOrientation} or null when unreadable. */
function imageSize(buf) {
  if (buf.length >= 24 && buf.toString('ascii', 1, 4) === 'PNG' && buf[0] === 0x89) {
    return { format: 'png', width: buf.readUInt32BE(16), height: buf.readUInt32BE(20), exifOrientation: 1 };
  }
  if (buf.length >= 10 && buf.toString('ascii', 0, 3) === 'GIF') {
    return { format: 'gif', width: buf.readUInt16LE(6), height: buf.readUInt16LE(8), exifOrientation: 1 };
  }
  if (buf.length >= 30 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') {
    const chunk = buf.toString('ascii', 12, 16);
    if (chunk === 'VP8 ') {
      return { format: 'webp', width: buf.readUInt16LE(26) & 0x3fff, height: buf.readUInt16LE(28) & 0x3fff, exifOrientation: 1 };
    }
    if (chunk === 'VP8L') {
      const b0 = buf[21], b1 = buf[22], b2 = buf[23], b3 = buf[24];
      return {
        format: 'webp',
        width: 1 + (((b1 & 0x3f) << 8) | b0),
        height: 1 + (((b3 & 0x0f) << 10) | (b2 << 2) | ((b1 & 0xc0) >> 6)),
        exifOrientation: 1,
      };
    }
    if (chunk === 'VP8X') {
      return { format: 'webp', width: 1 + buf.readUIntLE(24, 3), height: 1 + buf.readUIntLE(27, 3), exifOrientation: 1 };
    }
    return null;
  }
  if (buf.length >= 4 && buf[0] === 0xff && buf[1] === 0xd8) {
    let off = 2;
    let orientation = 1;
    let dims = null;
    while (off + 4 <= buf.length) {
      if (buf[off] !== 0xff) break;
      const marker = buf[off + 1];
      if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
        off += 2;
        continue;
      }
      if (marker === 0xd9 || marker === 0xda) break; // EOI / SOS: header is over
      const len = buf.readUInt16BE(off + 2);
      if (marker === 0xe1 && buf.toString('ascii', off + 4, off + 10) === 'Exif\0\0') {
        orientation = exifOrientation(buf, off + 10, off + 2 + len) || orientation;
      }
      const isSOF =
        (marker >= 0xc0 && marker <= 0xc3) ||
        (marker >= 0xc5 && marker <= 0xc7) ||
        (marker >= 0xc9 && marker <= 0xcb) ||
        (marker >= 0xcd && marker <= 0xcf);
      if (isSOF && !dims) {
        dims = { height: buf.readUInt16BE(off + 5), width: buf.readUInt16BE(off + 7) };
      }
      off += 2 + len;
    }
    return dims ? { format: 'jpeg', ...dims, exifOrientation: orientation } : null;
  }
  return null;
}

/** Reads EXIF IFD0 tag 0x0112 (Orientation) from a TIFF block; null if absent. */
function exifOrientation(buf, tiffStart, end) {
  if (tiffStart + 8 > end) return null;
  const le = buf.toString('ascii', tiffStart, tiffStart + 2) === 'II';
  const u16 = (o) => (le ? buf.readUInt16LE(o) : buf.readUInt16BE(o));
  const u32 = (o) => (le ? buf.readUInt32LE(o) : buf.readUInt32BE(o));
  if (u16(tiffStart + 2) !== 0x2a) return null;
  const ifd0 = tiffStart + u32(tiffStart + 4);
  if (ifd0 + 2 > end) return null;
  const n = u16(ifd0);
  for (let i = 0; i < n; i++) {
    const e = ifd0 + 2 + i * 12;
    if (e + 12 > end) return null;
    if (u16(e) === 0x0112) return u16(e + 8);
  }
  return null;
}

async function fetchPhoto(url) {
  // 1. The stored value is normally a Firebase Storage download URL that
  //    carries its own token — a plain GET works.
  try {
    const res = await fetch(url);
    if (res.ok) return Buffer.from(await res.arrayBuffer());
  } catch (_) {
    /* fall through */
  }
  // 2. Otherwise read the object with the admin credential.
  const m = url.match(/\/v0\/b\/([^/]+)\/o\/([^?]+)/);
  if (!m) throw new Error('unrecognised photo URL shape');
  const [buf] = await admin.storage().bucket(m[1]).file(decodeURIComponent(m[2])).download();
  return buf;
}

// ── Resolution ────────────────────────────────────────────────────────────

function finitePositive(v) {
  return typeof v === 'number' && Number.isFinite(v) && v > 0;
}

async function resolveForUser(db, uid, opts, cache) {
  if (cache.has(uid)) return cache.get(uid);
  const out = { source: 'unresolved', value: null, reason: 'no_mask_no_photo', photo: null };
  const snap = await db.collection('users').doc(uid).get({ fieldMask: ['roofline_mask', 'house_photo_url'] });
  const mask = snap.exists ? snap.get('roofline_mask') : null;
  const maskRatio = mask && mask[FIELD];
  if (finitePositive(maskRatio)) {
    out.source = 'roofline_mask';
    out.value = maskRatio;
    out.reason = null;
  } else {
    const url = snap.exists ? snap.get('house_photo_url') : null;
    if (typeof url === 'string' && url) {
      if (!opts.photo) {
        out.reason = 'photo_skipped(--no-photo)';
      } else {
        try {
          const buf = await fetchPhoto(url);
          const size = imageSize(buf);
          if (!size || !size.width || !size.height) {
            out.reason = 'photo_unreadable';
          } else if (size.exifOrientation >= 5) {
            out.reason = 'AMBIGUOUS: EXIF orientation ' + size.exifOrientation + ' (displayed transposed)';
            out.photo = size;
          } else {
            out.source = 'house_photo';
            out.value = size.width / size.height;
            out.reason = null;
            out.photo = size;
          }
        } catch (e) {
          out.reason = 'photo_fetch_failed: ' + (e.message || e);
        }
      }
    }
  }
  cache.set(uid, out);
  return out;
}

async function main() {
  const args = parseArgs(process.argv);
  initApp(args.keyPath);
  const db = admin.firestore();

  console.log('backfill_pixelmap_aspect_ratio — ' + (args.dryRun ? 'DRY RUN (no writes)' : '*** APPLY ***'));
  console.log('project: ' + PROJECT_ID + '\n');

  const cg = await db.collectionGroup('pixelMap').select(FIELD, 'channel_index', 'source_pixel_count').get();
  const all = cg.docs.filter((d) => PIXELMAP_PATH.test(d.ref.path));
  const staffDocs = all.filter((d) => d.ref.path.split('/')[1].startsWith('staff_'));
  const docs = args.skipStaff ? all.filter((d) => !staffDocs.includes(d)) : all;
  console.log('pixelMap docs (collection group): ' + cg.size + '  under users/*/controllers/*: ' + all.length);
  console.log('  under staff_* uids: ' + staffDocs.length + (args.skipStaff ? '  (skipped: --skip-staff)' : '  (included; pass --skip-staff to leave them)'));

  const has = docs.filter((d) => finitePositive(d.get(FIELD)));
  const missing = docs.filter((d) => !finitePositive(d.get(FIELD)));
  console.log('  already have ' + FIELD + ': ' + has.length);
  console.log('  missing ' + FIELD + ':      ' + missing.length + '\n');

  const cache = new Map();
  const plans = [];
  const counts = { roofline_mask: 0, house_photo: 0, unresolved: 0 };
  console.log('uid     ctrl    channel-doc   ch  src_px  source          value    note');
  for (const d of missing) {
    const [, uid, cid, ch] = d.ref.path.match(PIXELMAP_PATH);
    const r = await resolveForUser(db, uid, args, cache);
    counts[r.source]++;
    if (r.value != null) plans.push({ ref: d.ref, value: r.value });
    console.log(
      uid.slice(0, 6).padEnd(7) + ' ' +
        cid.slice(0, 6).padEnd(7) + ' ' +
        ch.slice(0, 13).padEnd(13) + ' ' +
        String(d.get('channel_index')).padEnd(3) + ' ' +
        String(d.get('source_pixel_count')).padEnd(7) + ' ' +
        r.source.padEnd(15) + ' ' +
        (r.value != null ? r.value.toFixed(4) : '-').padEnd(8) + ' ' +
        (r.reason || (r.photo ? r.photo.format + ' ' + r.photo.width + 'x' + r.photo.height : '')),
    );
  }

  console.log('\nWrite (per resolved doc): update({ "' + FIELD + '": <value> })');
  console.log('\nCounts:');
  console.log('  docs missing the field:         ' + missing.length);
  console.log('  would write from roofline_mask: ' + counts.roofline_mask);
  console.log('  would write from house photo:   ' + counts.house_photo);
  console.log('  unresolved (not written):       ' + counts.unresolved);
  console.log('  distinct users touched:         ' + new Set(missing.map((d) => d.ref.path.split('/')[1])).size);

  if (args.dryRun) {
    console.log('\nDRY RUN — nothing written. Re-run with --confirm to apply (only after +107 ships the field).');
    return;
  }

  console.log('\nApplying…');
  let written = 0;
  let skipped = 0;
  for (const { ref, value } of plans) {
    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return 'skip:deleted-meanwhile';
      if (finitePositive(snap.get(FIELD))) return 'skip:has-field-meanwhile';
      tx.update(ref, { [FIELD]: value });
      return 'written';
    });
    if (outcome === 'written') written++;
    else skipped++;
    console.log('  ' + ref.path.split('/').slice(1).map((s, i) => (i % 2 === 0 ? s.slice(0, 6) : s)).join('/') + '  ' + outcome);
  }
  console.log('\nDone. written=' + written + ' skipped=' + skipped);
}

main().catch((err) => {
  console.error('FAILED:', err && err.message ? err.message : err);
  process.exit(1);
});
