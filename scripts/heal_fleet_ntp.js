/**
 * heal_fleet_ntp.js — fleet-wide NTP-host repair (Vehicle 2 for 2.5.2 healer)
 *
 * WHY: A subset of the fleet has controllers whose NTP host is the stock WLED
 * default ("0.wled.pool.ntp.org"), which is unreachable on some customer
 * networks → the controller clock never syncs → NO schedule fires (a silent
 * schedule-killer clock-health detects but, before 2.5.2, nobody healed). The
 * in-app healer (controller_defaults_healer.dart) fixes this the next time each
 * user opens the app; this script fixes it PROACTIVELY for every user whose
 * bridge is online right now, without waiting for an app open — replacing truck
 * rolls.
 *
 * SCOPE — host + enable + reboot ONLY. This is the deliberate limitation:
 * the admin SDK cannot read a controller's live /json/cfg (there is no getCfg
 * bridge command, and the LAN device is unreachable from the cloud). So this
 * script CANNOT evaluate tz / coords "heal-only-broken" (that needs device
 * state). It performs the one blind-safe heal — assert the known-good host
 * (time.google.com) + enable NTP, then reboot so WLED re-attempts the sync.
 * tz / coords remain the in-app healer's job (it can read cfg on LAN). Writing
 * a good host is safe even on an already-good controller: it's the same host
 * the healer would assert and it does not touch tz/coords/brightness/segments.
 *
 * WHAT: For every user with a PAIRED, ONLINE bridge (fresh heartbeat in
 * bridge_registry.lastSeen), enqueue — per registered controller — the same
 * command docs the app's CloudRelayRepository writes (RemoteCommand.toFirestore
 * shape) that the bridge already knows how to execute:
 *   1. { type: 'applyConfig', payload: '{"if":{"ntp":{"host":"time.google.com","en":true}}}' }
 *   2. { type: 'applyJson',   payload: '{"rb":true}' }                (reboot)
 *
 *   • DRY-RUN (default): lists every target user → bridge (heartbeat age) →
 *     controller (id/ip/name). Writes NOTHING.
 *   • --confirm: enqueues the two command docs per controller.
 *
 * ONLINE gate mirrors _diag_bridge_liveness.js: a bridge is "online" when its
 * freshest bridge_registry.lastSeen is younger than STALE_MIN minutes.
 *
 * Auth: GOOGLE_APPLICATION_CREDENTIALS (ENV only), same as the diag scripts:
 *   PowerShell:  $env:GOOGLE_APPLICATION_CREDENTIALS="<path>"; node scripts/heal_fleet_ntp.js
 *   bash:        GOOGLE_APPLICATION_CREDENTIALS=<path> node scripts/heal_fleet_ntp.js
 *
 * Run (SAME protocol as the repair/wipe scripts — dry-run, review, then confirm):
 *   node scripts/heal_fleet_ntp.js              # dry-run, no writes
 *   node scripts/heal_fleet_ntp.js --confirm    # enqueue host+en + reboot
 *
 * NOT RUN as part of shipping 2.5.2 — Tyler runs dry-run → reviews the target
 * list → confirms.
 */

const admin = require('firebase-admin');

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';

// Heal target — keep in lockstep with kHealNtpHost in
// lib/features/wled/controller_defaults_healer.dart.
const HEAL_NTP_HOST = 'time.google.com';

// A bridge is "online" when its freshest lastSeen is younger than this.
// Heartbeat cadence is 30s; 10 min matches _diag_bridge_liveness.js.
const STALE_MIN = 10;

const CONFIRM = process.argv.includes('--confirm');

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('Set GOOGLE_APPLICATION_CREDENTIALS to the admin key path (ENV only).');
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT_ID,
});
const db = admin.firestore();

const CFG_PAYLOAD = JSON.stringify({
  if: { ntp: { host: HEAL_NTP_HOST, en: true } },
});
const REBOOT_PAYLOAD = JSON.stringify({ rb: true });

function isoOf(t) {
  return t?.toDate?.()?.toISOString?.() ??
    (t?._seconds ? new Date(t._seconds * 1000).toISOString() : null);
}
function ageMin(iso, nowMs) {
  return iso ? Math.round((nowMs - new Date(iso).getTime()) / 60000) : null;
}

/** Command doc mirroring RemoteCommand.toFirestore (payload is a JSON string). */
function commandDoc(type, payloadJson, controllerId, controllerIp, webhookUrl) {
  return {
    type,
    payload: payloadJson,
    controllerId: controllerId || '',
    controllerIp: controllerIp || '',
    webhookUrl: webhookUrl || '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    status: 'pending',
    source: 'heal_fleet_ntp', // provenance tag (ignored by the bridge)
  };
}

async function main() {
  console.log(
    CONFIRM
      ? `*** --confirm: enqueuing host=${HEAL_NTP_HOST}+en + reboot per controller ***`
      : 'DRY-RUN (no writes). Re-run with --confirm to enqueue.'
  );
  console.log(`Online gate: bridge lastSeen younger than ${STALE_MIN} min.\n`);

  const nowMs = Date.now();

  // 1. Index online bridges by pairedUid (freshest lastSeen per uid).
  const regSnap = await db.collection('bridge_registry').get();
  const onlineByUid = new Map(); // uid -> { deviceId, ageMin }
  for (const d of regSnap.docs) {
    const uid = d.get('pairedUid');
    if (!uid) continue;
    const age = ageMin(isoOf(d.get('lastSeen')), nowMs);
    if (age == null || age > STALE_MIN) continue; // offline / stale
    const prev = onlineByUid.get(uid);
    if (!prev || age < prev.ageMin) {
      onlineByUid.set(uid, { deviceId: d.id, ageMin: age });
    }
  }
  console.log(`Users with an ONLINE paired bridge: ${onlineByUid.size}\n`);

  let usersTargeted = 0;
  let controllersTargeted = 0;
  let commandsWritten = 0;

  for (const [uid, bridge] of onlineByUid) {
    // Optional webhook-mode URL (bridge mode leaves this empty).
    let webhookUrl = '';
    try {
      const u = await db.collection('users').doc(uid).get();
      webhookUrl = u.get('webhookUrl') || '';
    } catch (_) { /* default '' */ }

    const ctrlSnap = await db.collection('users').doc(uid).collection('controllers').get();
    const controllers = ctrlSnap.docs
      .map((c) => ({ id: c.id, ip: c.get('ip') || '', name: c.get('name') || '(unnamed)' }))
      .filter((c) => c.ip); // can't target a controller with no IP

    if (controllers.length === 0) {
      console.log(`user ${uid} — bridge ${bridge.deviceId} online ${bridge.ageMin}m — NO controllers with an IP (skipped)`);
      continue;
    }

    usersTargeted++;
    console.log(`user ${uid} — bridge ${bridge.deviceId} online ${bridge.ageMin}m ago${webhookUrl ? ' (webhook mode)' : ''}:`);
    const cmdsRef = db.collection('users').doc(uid).collection('commands');

    for (const c of controllers) {
      controllersTargeted++;
      console.log(`    controller ${c.id} ip=${c.ip} name=${JSON.stringify(c.name)} → host+en, reboot`);
      if (CONFIRM) {
        await cmdsRef.add(commandDoc('applyConfig', CFG_PAYLOAD, c.id, c.ip, webhookUrl));
        await cmdsRef.add(commandDoc('applyJson', REBOOT_PAYLOAD, c.id, c.ip, webhookUrl));
        commandsWritten += 2;
      }
    }
    console.log('');
  }

  console.log('Done.');
  console.log(`  Users targeted:       ${usersTargeted}`);
  console.log(`  Controllers targeted: ${controllersTargeted}`);
  console.log(`  Commands ${CONFIRM ? 'written' : 'that WOULD be written'}: ${CONFIRM ? commandsWritten : controllersTargeted * 2}`);
  if (!CONFIRM && controllersTargeted > 0) {
    console.log('\n  Review the target list above, then re-run with --confirm to enqueue.');
  }
  console.log('\n  NOTE: host+enable+reboot only. tz/coords heal-only-broken needs device');
  console.log('  cfg readback (unavailable via admin SDK) — that stays the in-app healer.');
  process.exit(0);
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
