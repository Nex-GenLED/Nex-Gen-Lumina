// _backfill_team_configs.js — TEAM CONSOLIDATION step 1.
//
// Creates a game_day_autopilot config for every users/{uid}.sports_teams[] entry
// that has none, so the store the fire path reads finally contains every team
// the customer believes they selected (audit/TEAM_SURFACES.md §4: 26 of 45
// selected teams currently never fire).
//
// enabled: false IS NOT OPTIONAL. Nine accounts would otherwise wake to Game Day
// firing for teams they never configured — a customer's lights running on a
// schedule they never set is worse than the current silence.
//
// The catalogue is parsed directly out of
// lib/features/sports_alerts/data/team_colors.dart so there is exactly ONE
// source of truth for slugs, colours, sport and espnTeamId. No hand-copied table.
//
//   node scripts/_backfill_team_configs.js --dry
//   node scripts/_backfill_team_configs.js --commit

'use strict';

const fs = require('fs');
const path = require('path');
const admin = require(
  path.resolve(__dirname, '..', 'functions', 'node_modules', 'firebase-admin')
);

const PROJECT_ID = 'icrt6menwsv2d8all8oijs021b06s5';
const args = process.argv.slice(2);
const DRY = args.includes('--dry');
const COMMIT = args.includes('--commit');
if (DRY === COMMIT) { console.error('Specify exactly one of --dry | --commit'); process.exit(2); }

// ---------------------------------------------------------------------------
// Catalogue — parsed from the Dart source, never duplicated
// ---------------------------------------------------------------------------

function loadCatalogue() {
  const src = fs.readFileSync(
    path.resolve(__dirname, '..', 'lib', 'features', 'sports_alerts', 'data', 'team_colors.dart'),
    'utf8'
  );
  const re = /'([a-z0-9_]+)':\s*TeamColors\(\s*primary:\s*Color\(0x([0-9A-Fa-f]{8})\),\s*secondary:\s*Color\(0x([0-9A-Fa-f]{8})\),\s*teamName:\s*'((?:[^'\\]|\\.)*)',\s*sport:\s*SportType\.(\w+),\s*espnTeamId:\s*'([^']*)',?\s*\)/g;
  const out = {};
  let m;
  while ((m = re.exec(src)) !== null) {
    out[m[1]] = {
      slug: m[1],
      primary: parseInt(m[2], 16),
      secondary: parseInt(m[3], 16),
      teamName: m[4].replace(/\\'/g, "'"),
      sport: m[5],
      espnTeamId: m[6],
    };
  }
  return out;
}

// ---------------------------------------------------------------------------
// Name → slug resolution
// ---------------------------------------------------------------------------

const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');

/**
 * Confirmed by Tyler 2026-08-07. These are the only hand-mapped names; anything
 * else must resolve by exact catalogue name.
 */
const ALIASES = {
  chiefs: 'nfl_chiefs',
  royals: 'mlb_royals',
  kansascitysportingkansascity: 'mls_sporting_kc',
};

/**
 * Resolve a display name to the slug(s) it should produce.
 * Returns { slugs: [...], via } | { unresolved: true }
 *
 * MULTI-SLUG NAMES — decision, Tyler 2026-08-07: CREATE BOTH, DISABLED.
 *
 * A college display name maps to two catalogue entries because the slugs split
 * by sport: `ncaa_missouri` (football) and `ncaamb_missouri` (basketball) carry
 * the identical `teamName`. Three names in the fleet do this — Kansas State
 * Wildcats, Kansas Jayhawks, Missouri Tigers — across four accounts.
 *
 * The precedent settles it rather than a guess: `ecochran08@yahoo.com` already
 * holds BOTH `ncaa_missouri` and `ncaamb_missouri`, both disabled, created
 * through the normal Game Day flow. So "a college team means both sports,
 * disabled" is existing product behaviour.
 *
 * Creating both OFFERS the choice instead of presuming one. Both arrive
 * disabled, so nothing fires either way — the customer enables whichever sport
 * they actually follow. The alternative, leaving them unmapped, means four
 * customers keep permanently dead rows in a list this change just made
 * authoritative, which is the worse outcome.
 */
function resolveSlug(displayName, catalogue) {
  const n = norm(displayName);
  if (!n) return { unresolved: true };

  if (ALIASES[n]) return { slugs: [ALIASES[n]], via: 'alias' };

  const exact = Object.values(catalogue).filter((t) => norm(t.teamName) === n);
  if (exact.length === 1) return { slugs: [exact[0].slug], via: 'exact' };
  if (exact.length > 1) {
    // Stable order so two runs produce byte-identical output.
    return { slugs: exact.map((t) => t.slug).sort(), via: 'multi-sport' };
  }

  return { unresolved: true };
}

// ---------------------------------------------------------------------------

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();
  const catalogue = loadCatalogue();
  console.log(`Mode: ${DRY ? 'DRY RUN (writes nothing)' : 'COMMIT'}`);
  console.log(`Catalogue: ${Object.keys(catalogue).length} teams parsed from team_colors.dart\n`);

  const users = await db.collection('users').get();
  let scanned = 0, wouldCreate = 0, alreadyOk = 0, created = 0;
  const unresolved = [];
  const ambiguous = [];
  const plan = [];

  for (const u of users.docs) {
    const arr = Array.isArray(u.get('sports_teams'))
      ? u.get('sports_teams').filter((x) => typeof x === 'string' && x.trim())
      : [];
    if (!arr.length) continue;
    scanned++;

    const sub = await db.collection('users').doc(u.id).collection('game_day_autopilot').get();
    const haveSlugs = new Set(sub.docs.map((d) => d.id));
    const who = u.get('email') || u.id;

    for (const name of arr) {
      const r = resolveSlug(name, catalogue);

      if (!r.slugs) {
        unresolved.push({ who, name });
        continue;
      }
      if (r.via === 'multi-sport') {
        ambiguous.push({ who, name, options: r.slugs });
      }

      // Per-SLUG, not per-name: a multi-sport name may already have one sport
      // configured and not the other, and the missing one must still be created.
      for (const slug of r.slugs) {
        if (haveSlugs.has(slug)) { alreadyOk++; continue; }

      const t = catalogue[slug];
      wouldCreate++;
      plan.push({ who, uid: u.id, name, slug: slug, via: r.via, sport: t.sport });

      if (COMMIT) {
        const ref = db.collection('users').doc(u.id)
          .collection('game_day_autopilot').doc(slug);
        // create() — NOT set(). If a config appeared since the scan, we must not
        // overwrite it; an existing config may be ENABLED with the customer's own
        // colours and design, and clobbering it back to disabled defaults would
        // be a silent regression.
        try {
          await ref.create({
            team_slug: slug,
            team_name: t.teamName,
            sport: t.sport,
            espn_team_id: t.espnTeamId,
            primary_color: t.primary,
            secondary_color: t.secondary,
            // ── The safety decision ──────────────────────────────────────
            enabled: false,
            // Catalogue defaults, matching what registerTeam seeds.
            brightness: 200,
            speed: 160,
            intensity: 128,
            effect_id: 52,
            design_mode: 'fallback',
            design_variety: 'rotating',
            motion_style: 0.5,
            skip_day_games: true,
            score_celebration_enabled: true,
            saved_design_name: null,
            saved_design_payload: null,
            backfilled_at: admin.firestore.FieldValue.serverTimestamp(),
            backfill_source: 'sports_teams_array',
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          created++;
        } catch (e) {
          if (e.code === 6 || e.code === 'already-exists') { alreadyOk++; }
          else throw e;
        }
      }
      }
    }
  }

  console.log('─'.repeat(72));
  console.log('PLAN — configs that WOULD be created (all enabled:false)');
  console.log('─'.repeat(72));
  let last = '';
  for (const p of plan) {
    if (p.who !== last) { console.log(`\n  ${p.who}`); last = p.who; }
    console.log(`     "${p.name}"  →  ${p.slug}  (${p.sport}, via ${p.via})`);
  }

  if (ambiguous.length) {
    console.log('\n' + '─'.repeat(72));
    console.log('MULTI-SPORT — BOTH slugs created (disabled); customer enables the one they follow');
    console.log('─'.repeat(72));
    for (const a of ambiguous) console.log(`  ${a.who}: "${a.name}" → ${a.options.join(" + ")}`);
  }
  if (unresolved.length) {
    console.log('\n' + '─'.repeat(72));
    console.log('UNRESOLVED — no catalogue match; left in the array');
    console.log('─'.repeat(72));
    for (const x of unresolved) console.log(`  ${x.who}: "${x.name}"`);
  }

  console.log('\n' + '─'.repeat(72));
  console.log(`users with teams   : ${scanned}`);
  console.log(`already configured : ${alreadyOk}`);
  console.log(`would create       : ${wouldCreate}${COMMIT ? `  (created: ${created})` : ''}`);
  console.log(`multi-sport names  : ${ambiguous.length} (each creates 2 configs)`);
  console.log(`unresolved         : ${unresolved.length}`);
  console.log('─'.repeat(72));
  process.exit(0);
}

main().catch((e) => { console.error(e); process.exit(1); });
