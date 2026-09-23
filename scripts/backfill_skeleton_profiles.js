#!/usr/bin/env node
//
// backfill_skeleton_profiles.js — write the "unlinked" skeleton profile for
// email Auth accounts that have NO users/{uid} document.
//
// DRY RUN BY DEFAULT. Nothing is written without --confirm.
//
// ── WHY ──────────────────────────────────────────────────────────────────
//
// residential-path-audit-2026-09-23 §1.3 / §3.3 / §9.3.4: production holds
// email/password Auth accounts with no profile document at all (32 on
// 2026-09-23). Each one hits the Path C race on its next sign-in — the FCM
// token store may create users/{uid} as a {fcmToken, fcmTokenUpdatedAt}
// stub before the router's lazy skeleton, and the skeleton is guarded on
// `doc.exists`, so the stub becomes permanent and UserModel.fromJson throws.
//
// Writing the skeleton up front removes those accounts from the race
// regardless of which app build they run, and lets the installer wizard's
// existing-account branch find them once §9.1(4) ships.
//
// The healUserProfile Cloud Function (functions/src/healUserProfile.ts)
// repairs a stub AFTER it is created; this script prevents one for accounts
// that do not have a document yet. They compose: whichever runs first, the
// other finds owner_id set and skips.
//
// ── WHAT IT WRITES (per candidate, set with merge:true) ──────────────────
//
//   id                 = uid
//   owner_id           = uid
//   email              = Auth email
//   display_name       = Auth displayName, else the email's local part
//   created_at         = Auth creation time (Timestamp)
//   updated_at         = serverTimestamp()
//   installation_role  = 'unlinked'
//   welcome_completed  = false
//
// Same keys and values as route_guards.dart createUnlinkedUserProfile
// (:28-41), so a later client skeleton merge changes nothing.
//
// ── WHO IS A CANDIDATE ───────────────────────────────────────────────────
//
//   • Auth user WITH an email          (anonymous sessions are never touched)
//   • uid does not start with staff_   (mintStaffToken custom-token sessions)
//   • no users/{uid} document          (a stub WITH an email is reported but
//                                       NOT written here — that is the
//                                       healer's job, and today there are 0)
//   Disabled accounts are included and flagged; a disabled account cannot
//   sign in, so the skeleton is inert until it is re-enabled.
//
//   Test accounts vs real customers are NOT separated by this script — the
//   audit says to do that by dealer follow-up, not by script. The dry run
//   prints creation / last-sign-in dates so a human can decide.
//
// ── SAFETY ───────────────────────────────────────────────────────────────
//
//   • --confirm re-checks each document inside a transaction and skips it if
//     it exists with owner_id set (created between the listing and the
//     write). A stub that appeared in between is merged over, never replaced.
//   • Idempotent: a second --confirm run finds every candidate already
//     provisioned and writes nothing.
//   • Prints 6-character uid prefixes and the email DOMAIN only, unless
//     --show-emails is given. Never writes a report file.
//
// ── USAGE ────────────────────────────────────────────────────────────────
//
//   node scripts/backfill_skeleton_profiles.js                 # dry run (ADC)
//   node scripts/backfill_skeleton_profiles.js --show-emails   # dry run, full emails
//   node scripts/backfill_skeleton_profiles.js --key=<sa.json> # dry run, SA key
//   node scripts/backfill_skeleton_profiles.js --confirm       # APPLY
//
// Target project: icrt6menwsv2d8all8oijs021b06s5

'use strict';

const admin = require('firebase-admin');
const path = require('path');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const STAFF_UID_PREFIX = 'staff_';
const UNLINKED_ROLE = 'unlinked';

function parseArgs(argv) {
  const args = { dryRun: true, keyPath: null, showEmails: false, exclude: new Set() };
  for (const a of argv.slice(2)) {
    if (a === '--confirm') args.dryRun = false;
    else if (a === '--dry-run') args.dryRun = true;
    else if (a === '--show-emails') args.showEmails = true;
    else if (a.startsWith('--key=')) args.keyPath = a.slice('--key='.length);
    else if (a.startsWith('--exclude=')) {
      a.slice('--exclude='.length)
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .filter(Boolean)
        .forEach((s) => args.exclude.add(s));
    } else if (a === '--help' || a === '-h') {
      console.log(
        'Usage: node scripts/backfill_skeleton_profiles.js [--confirm] [--dry-run] [--show-emails] [--exclude=<uid|email>,...] [--key=<path>]\n' +
          '\n' +
          '  --confirm      Apply the writes. Without it, dry run (default).\n' +
          '  --show-emails  Print full emails instead of the domain only.\n' +
          '  --exclude=     Comma-separated uids or emails to leave alone (service\n' +
          '                 accounts such as the bridge fleet login are Auth users\n' +
          '                 with an email but are not customers and need no profile).\n' +
          '  --key=<path>   Service-account JSON. Default: gcloud ADC.\n',
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

async function listAllAuthUsers(auth) {
  const out = [];
  let token;
  do {
    const page = await auth.listUsers(1000, token);
    out.push(...page.users);
    token = page.pageToken;
  } while (token);
  return out;
}

function isSet(v) {
  if (v === undefined || v === null) return false;
  if (typeof v === 'string' && v.trim() === '') return false;
  return true;
}

function displayNameFor(user) {
  const dn = (user.displayName || '').trim();
  if (dn) return { value: dn, source: 'auth' };
  const local = (user.email || '').split('@')[0].trim();
  return { value: local || 'User', source: local ? 'email-local' : 'fallback' };
}

function creationTimestamp(user) {
  const ms = Date.parse((user.metadata && user.metadata.creationTime) || '');
  return Number.isFinite(ms) ? admin.firestore.Timestamp.fromMillis(ms) : admin.firestore.Timestamp.now();
}

function day(s) {
  const d = new Date(s || 0);
  return isNaN(d) || !s ? '-' : d.toISOString().slice(0, 10);
}

function redact(email, show) {
  if (show) return email;
  const at = email.indexOf('@');
  return at < 0 ? '***' : '***@' + email.slice(at + 1);
}

/** Builds the exact document merged for one candidate. */
function skeletonFor(user) {
  const dn = displayNameFor(user);
  return {
    fields: {
      id: user.uid,
      owner_id: user.uid,
      email: user.email,
      display_name: dn.value,
      created_at: creationTimestamp(user),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
      installation_role: UNLINKED_ROLE,
      welcome_completed: false,
    },
    displayNameSource: dn.source,
  };
}

async function main() {
  const args = parseArgs(process.argv);
  initApp(args.keyPath);
  const db = admin.firestore();
  const auth = admin.auth();

  console.log('backfill_skeleton_profiles — ' + (args.dryRun ? 'DRY RUN (no writes)' : '*** APPLY ***'));
  console.log('project: ' + PROJECT_ID + '\n');

  const users = await listAllAuthUsers(auth);
  const emailUsers = users.filter((u) => !!u.email && !u.uid.startsWith(STAFF_UID_PREFIX));
  console.log('Auth users: ' + users.length + '  with email (non-staff): ' + emailUsers.length);

  // One getAll per 200 refs — reads only id + owner_id.
  const existing = new Map(); // uid → { exists, ownerIdSet }
  for (let i = 0; i < emailUsers.length; i += 200) {
    const chunk = emailUsers.slice(i, i + 200);
    const snaps = await db.getAll(
      ...chunk.map((u) => db.collection('users').doc(u.uid)),
      { fieldMask: ['owner_id'] },
    );
    snaps.forEach((s) => existing.set(s.id, { exists: s.exists, ownerIdSet: s.exists && isSet(s.get('owner_id')) }));
  }

  const candidates = [];
  const stubsWithEmail = [];
  const excluded = [];
  let provisioned = 0;
  for (const u of emailUsers) {
    const e = existing.get(u.uid);
    if (!e.exists) {
      if (args.exclude.has(u.uid.toLowerCase()) || args.exclude.has(String(u.email).toLowerCase())) {
        excluded.push(u);
      } else {
        candidates.push(u);
      }
    } else if (!e.ownerIdSet) stubsWithEmail.push(u);
    else provisioned++;
  }

  console.log('  already provisioned (doc with owner_id): ' + provisioned);
  console.log('  stub doc WITH email (NOT written here; healer/decision): ' + stubsWithEmail.length);
  console.log('  excluded by --exclude (no doc, left alone): ' + excluded.length);
  console.log('  CANDIDATES (email Auth account, no users doc): ' + candidates.length + '\n');

  candidates.sort((a, b) => new Date(b.metadata.lastSignInTime || 0) - new Date(a.metadata.lastSignInTime || 0));

  const since = new Date('2026-09-01T00:00:00Z');
  const stats = { auth: 0, 'email-local': 0, fallback: 0, disabled: 0, signedInSince0901: 0, createdSince0901: 0 };
  console.log('uid     created     lastSignIn  disabled dn-source    email');
  const plans = [];
  for (const u of candidates) {
    const plan = skeletonFor(u);
    plans.push({ user: u, plan });
    stats[plan.displayNameSource]++;
    if (u.disabled) stats.disabled++;
    if (new Date(u.metadata.lastSignInTime || 0) >= since) stats.signedInSince0901++;
    if (new Date(u.metadata.creationTime || 0) >= since) stats.createdSince0901++;
    console.log(
      u.uid.slice(0, 6).padEnd(7) + ' ' +
        day(u.metadata.creationTime).padEnd(11) + ' ' +
        day(u.metadata.lastSignInTime).padEnd(11) + ' ' +
        String(u.disabled).padEnd(8) + ' ' +
        plan.displayNameSource.padEnd(12) + ' ' +
        redact(u.email, args.showEmails),
    );
  }

  console.log('\nWrite template (every candidate, set with merge:true):');
  console.log(
    JSON.stringify(
      {
        id: '<uid>',
        owner_id: '<uid>',
        email: '<auth email>',
        display_name: '<auth displayName | email local part>',
        created_at: '<Timestamp: Auth creation time>',
        updated_at: '<serverTimestamp()>',
        installation_role: UNLINKED_ROLE,
        welcome_completed: false,
      },
      null,
      2,
    ),
  );
  console.log('\nCounts:');
  console.log('  candidates:                     ' + candidates.length);
  console.log('  display_name from Auth:         ' + stats.auth);
  console.log('  display_name from email local:  ' + stats['email-local']);
  console.log('  display_name fallback "User":   ' + stats.fallback);
  console.log('  disabled accounts (inert):      ' + stats.disabled);
  console.log('  signed in since 2026-09-01:     ' + stats.signedInSince0901);
  console.log('  created since 2026-09-01:       ' + stats.createdSince0901);

  if (args.dryRun) {
    console.log('\nDRY RUN — nothing written. Re-run with --confirm to apply.');
    return;
  }

  console.log('\nApplying…');
  let written = 0;
  let skipped = 0;
  for (const { user, plan } of plans) {
    const ref = db.collection('users').doc(user.uid);
    const outcome = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists && isSet(snap.get('owner_id'))) return 'skip:provisioned-meanwhile';
      // Merge over an empty doc or a stub that appeared since the listing;
      // never overwrite a key that is now set.
      const fields = {};
      for (const [k, v] of Object.entries(plan.fields)) {
        if (!snap.exists || !isSet(snap.get(k))) fields[k] = v;
      }
      tx.set(ref, fields, { merge: true });
      return 'written:' + Object.keys(fields).length + ' keys';
    });
    if (outcome.startsWith('written')) written++;
    else skipped++;
    console.log('  ' + user.uid.slice(0, 6) + '  ' + outcome);
  }
  console.log('\nDone. written=' + written + ' skipped=' + skipped);
}

main().catch((err) => {
  console.error('FAILED:', err && err.message ? err.message : err);
  process.exit(1);
});
