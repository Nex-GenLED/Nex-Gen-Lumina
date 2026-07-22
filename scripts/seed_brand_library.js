#!/usr/bin/env node
/**
 * seed_brand_library.js
 *
 * Seeds the global /brand_library Firestore collection with two sources, in
 * order:
 *
 *   Phase 1 — Manual brands (verifiedBy: "nex-gen-manual")
 *     Read from ./brands_to_seed.json. Only entries with confidence === "high"
 *     are seeded; entries marked "verify" are listed for human review and
 *     SKIPPED. This is intentional — wrong brand colors mean wrong customer
 *     designs, so we never seed unverified hex codes.
 *
 *   Phase 2 — Brandfetch claimed brands (verifiedBy: "brandfetch-claimed")
 *     Read from ./brandfetch_domains.json. The Brandfetch API is queried for
 *     each entry, but ONLY brands with `claimed: true` (verified by the
 *     trademark holder) are accepted. Unclaimed entries are skipped — they
 *     are not authoritative.
 *
 * brands_to_seed.json schema (per entry):
 *   {
 *     "name": "Brand Name",
 *     "industry": "restaurant" | "insurance" | "bank" | "retail" |
 *                 "realestate" | "fitness" | "hotel" | "healthcare" |
 *                 "salon" | "auto",
 *     "domain": "brand.com",
 *     "colors": [
 *       { "name": "Color Name", "hex": "#RRGGBB",
 *         "role": "primary" | "secondary" | "accent" }
 *     ],
 *     "confidence": "high" | "verify",
 *     // Optional — per-brand custom design cards beyond the five
 *     // canonical auto-generated designs (Solid/Breathe/Chase/Event
 *     // Mode/Welcome). Mirrors lib/models/commercial/brand_custom_design.dart.
 *     "customDesigns": [
 *       {
 *         "designId": "shimmer",
 *         "displayName": "Shimmer",
 *         "wledEffectName": "Twinkle",
 *         "wledEffectId": 50,
 *         "effectParams": { "sx": 96, "ix": 200 },
 *         "description": "Subtle jewelry-like glimmer",
 *         "mood": "elegant"
 *       }
 *     ]
 *   }
 *
 * SAFETY RULES (enforced):
 *   1. Defaults to DRY-RUN. Pass --commit to actually write.
 *   2. Never overwrites an existing /brand_library/{brandId} doc — existing
 *      brands are skipped. This protects approved corrections from being
 *      reverted by a re-run.
 *   3. confidence !== "high" is auto-skipped in Phase 1.
 *   4. claimed !== true is auto-skipped in Phase 2.
 *
 * -------------------------------------------------------------------
 * SETUP
 * -------------------------------------------------------------------
 * 1. Create scripts/.env from scripts/.env.example and put your
 *    Brandfetch API key in BRANDFETCH_API_KEY. Get a key at
 *    brandfetch.com.
 *
 * 2. Make the Firebase service account available in one of two ways:
 *
 *      a. CLI flag (recommended, mirrors other scripts in this dir):
 *         --key=android/app/icrt6menwsv2d8all8oijs021b06s5-firebase-adminsdk-fbsvc-2e0cb54335.json
 *
 *      b. Environment variable:
 *         export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *
 *    If neither is provided, the script falls back to the project's
 *    bundled service account at the path above. That file is gitignored
 *    via *firebase-adminsdk*.json.
 *
 * 3. DRY RUN (default — safe, no writes):
 *      node scripts/seed_brand_library.js
 *
 * 4. COMMIT (writes to Firestore):
 *      node scripts/seed_brand_library.js --commit
 *
 *    Skip a phase:
 *      node scripts/seed_brand_library.js --commit --no-brandfetch
 *      node scripts/seed_brand_library.js --commit --no-manual
 */

'use strict';

const path = require('path');
const fs = require('fs');

// Optional: load .env if dotenv is installed and scripts/.env exists.
try {
  require('dotenv').config({ path: path.join(__dirname, '.env') });
} catch (_) {
  // dotenv missing is fine — env vars can be set externally.
}

const admin = require('firebase-admin');
const fetch = require('node-fetch');

// ─── CLI args ───────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const COMMIT = args.includes('--commit');
const SKIP_MANUAL = args.includes('--no-manual');
const SKIP_BRANDFETCH = args.includes('--no-brandfetch');
const keyArg = args.find((a) => a.startsWith('--key='));
const KEY_PATH = keyArg
  ? keyArg.slice('--key='.length)
  : process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    path.join(
      __dirname,
      '..',
      'android',
      'app',
      'icrt6menwsv2d8all8oijs021b06s5-firebase-adminsdk-fbsvc-2e0cb54335.json'
    );

// ─── Validation ─────────────────────────────────────────────────────────────

if (!fs.existsSync(KEY_PATH)) {
  console.error(`❌ Service account key not found at: ${KEY_PATH}`);
  console.error(
    'Pass --key=/path/to/service-account.json or set GOOGLE_APPLICATION_CREDENTIALS.'
  );
  process.exit(1);
}

if (!SKIP_BRANDFETCH && !process.env.BRANDFETCH_API_KEY) {
  console.error('❌ BRANDFETCH_API_KEY is not set.');
  console.error('Either:');
  console.error('  • Add it to scripts/.env (copy from scripts/.env.example)');
  console.error('  • Export it: BRANDFETCH_API_KEY=xxx node scripts/seed_brand_library.js');
  console.error('  • Skip Phase 2: node scripts/seed_brand_library.js --no-brandfetch');
  console.error('');
  console.error('Get your key at brandfetch.com.');
  process.exit(1);
}

// ─── Firebase init ──────────────────────────────────────────────────────────

const serviceAccount = require(KEY_PATH);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// ─── Helpers ────────────────────────────────────────────────────────────────

/**
 * Convert a company name to a stable, URL-safe brandId.
 * "State Farm" → "state-farm"
 * "RE/MAX" → "remax"
 * "@properties" → "properties"
 */
function toBrandId(name) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .trim();
}

/**
 * Generate search terms for arrayContains queries from the brand-search UI.
 * "State Farm" → ["state farm", "statefarm", "state", "farm"]
 */
function toSearchTerms(name) {
  const lower = name.toLowerCase().trim();
  const noSpaces = lower.replace(/\s/g, '');
  const words = lower.split(/\s+/).filter((w) => w.length > 2);
  const set = new Set([lower, noSpaces, ...words]);
  return [...set].filter((t) => t.length > 0);
}

/**
 * Generate a lighting signature based on industry + dominant color warmth.
 *
 * Industry overrides come first (well-known mood mapping per category);
 * fallback uses warm-vs-cool heuristic on the primary color.
 */
function generateSignature(colors, industry) {
  const fallback = {
    primaryEffect: 'breathe',
    speed: 'medium',
    intensity: 'medium',
    mood: 'professional',
  };

  const industries = {
    restaurant: { primaryEffect: 'chase', speed: 'fast', intensity: 'high', mood: 'energetic' },
    insurance: { primaryEffect: 'breathe', speed: 'slow', intensity: 'medium', mood: 'trustworthy' },
    bank: { primaryEffect: 'solid', speed: 'slow', intensity: 'low', mood: 'stable' },
    retail: { primaryEffect: 'chase', speed: 'medium', intensity: 'high', mood: 'inviting' },
    realestate: { primaryEffect: 'fade', speed: 'slow', intensity: 'medium', mood: 'welcoming' },
    fitness: { primaryEffect: 'chase', speed: 'fast', intensity: 'high', mood: 'energetic' },
    hotel: { primaryEffect: 'breathe', speed: 'slow', intensity: 'medium', mood: 'luxurious' },
    healthcare: { primaryEffect: 'solid', speed: 'slow', intensity: 'low', mood: 'calm' },
    salon: { primaryEffect: 'fade', speed: 'medium', intensity: 'medium', mood: 'elegant' },
    auto: { primaryEffect: 'chase', speed: 'medium', intensity: 'high', mood: 'dynamic' },
  };

  if (industries[industry]) return industries[industry];

  const primary = colors && colors[0];
  if (!primary || !primary.hex) return fallback;

  const hex = primary.hex.replace('#', '');
  if (hex.length !== 6) return fallback;
  const r = parseInt(hex.substr(0, 2), 16);
  const g = parseInt(hex.substr(2, 2), 16);
  const b = parseInt(hex.substr(4, 2), 16);
  const isWarm = r > g && r > b;

  return {
    primaryEffect: isWarm ? 'chase' : 'breathe',
    speed: isWarm ? 'medium' : 'slow',
    intensity: 'medium',
    mood: isWarm ? 'energetic' : 'professional',
  };
}

// ─── Seed one brand (skip if already exists) ────────────────────────────────

/**
 * Convert the simple {name, hex, role} entries from brands_to_seed.json
 * into the existing BrandColor.toJson() shape from
 * lib/models/commercial/brand_color.dart so Flutter can deserialize
 * /brand_library entries without a parallel color model.
 *
 * BrandColor JSON shape (snake_case, from project convention):
 *   { id, color_name, hex_code, role_tag, active_in_engine }
 *
 * The hex_code field is stored without the leading '#' to match how the
 * existing BrandIdentityScreen writes user-entered colors.
 */
function toBrandColorJson(rawColor, brandId, index) {
  const hex = (rawColor.hex || '').replace(/^#/, '').trim().toUpperCase();
  return {
    id: `bc_${brandId}_${index}`,
    color_name: rawColor.name || `Color ${index + 1}`,
    hex_code: hex,
    role_tag: (rawColor.role || 'primary').toLowerCase(),
    active_in_engine: true,
  };
}

/**
 * Convert the in-memory signature object into snake_case Firestore shape.
 */
function toSignatureJson(sig) {
  return {
    primary_effect: sig.primaryEffect,
    speed: sig.speed,
    intensity: sig.intensity,
    mood: sig.mood,
  };
}

/**
 * Convert a single customDesign entry from brands_to_seed.json into the
 * snake_case Firestore shape consumed by
 * lib/models/commercial/brand_custom_design.dart.
 *
 * Accepts either camelCase keys (the JSON convention used by other
 * fields in this seeder) or snake_case keys (defensive — in case the
 * JSON is hand-edited). Missing or invalid fields fall back to safe
 * defaults rather than throwing, mirroring how the Dart model defaults
 * on the read side.
 */
function toCustomDesignJson(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const designId = (raw.designId || raw.design_id || '').toString().trim();
  const displayName = (raw.displayName || raw.display_name || '').toString().trim();
  if (!designId || !displayName) return null;
  const params = raw.effectParams || raw.effect_params || {};
  const out = {
    design_id: designId,
    display_name: displayName,
    wled_effect_name: (raw.wledEffectName || raw.wled_effect_name || '').toString(),
    wled_effect_id:
      typeof raw.wledEffectId === 'number'
        ? raw.wledEffectId
        : typeof raw.wled_effect_id === 'number'
          ? raw.wled_effect_id
          : 0,
    effect_params: params && typeof params === 'object' ? params : {},
    mood: (raw.mood || 'professional').toString(),
  };
  const desc = raw.description;
  if (typeof desc === 'string' && desc.trim().length > 0) {
    out.description = desc.trim();
  }
  return out;
}

async function seedBrand(brand, source) {
  const brandId = toBrandId(brand.name);
  if (!brandId) return { status: 'failed', reason: 'invalid brand id' };

  const ref = db.collection('brand_library').doc(brandId);

  if (COMMIT) {
    const existing = await ref.get();
    if (existing.exists) {
      return { status: 'skipped', reason: 'already exists' };
    }
  }

  const signature = generateSignature(brand.colors, brand.industry);
  const colorsJson = (brand.colors || []).map((c, i) =>
    toBrandColorJson(c, brandId, i)
  );

  // Optional per-brand custom design cards. Empty array when the JSON
  // entry omits the field — the Flutter side already defaults to []
  // for legacy docs that have no field at all, but writing the empty
  // array here keeps newly-seeded docs self-describing.
  const customDesignsJson = Array.isArray(brand.customDesigns)
    ? brand.customDesigns.map(toCustomDesignJson).filter(Boolean)
    : [];

  // Snake_case at the document level matches the project convention used
  // by every other Flutter model (see lib/models/commercial/brand_color.dart
  // for the canonical example). Read by Flutter via fromJson on the
  // BrandLibraryEntry model in Part 3.
  const doc = {
    brand_id: brandId,
    company_name: brand.name,
    search_terms: toSearchTerms(brand.name),
    industry: brand.industry,
    colors: colorsJson,
    signature: toSignatureJson(signature),
    verified_by: source,
    last_verified: admin.firestore.FieldValue.serverTimestamp(),
    correction_count: 0,
    status: 'verified',
    custom_designs: customDesignsJson,
  };

  if (!COMMIT) {
    return { status: 'dry-run', doc, brandId };
  }

  await ref.set(doc);
  return { status: 'seeded', brandId };
}

// ─── Brandfetch fetch (claimed: true filter is mandatory) ──────────────────

async function fetchBrandfetch(name, domain, industry) {
  const url = `https://api.brandfetch.io/v2/brands/${domain}`;
  let res;
  try {
    res = await fetch(url, {
      headers: { Authorization: `Bearer ${process.env.BRANDFETCH_API_KEY}` },
    });
  } catch (e) {
    return { error: `network error: ${e.message}` };
  }

  if (res.status === 404) return { error: 'not found in Brandfetch' };
  if (res.status === 429) return { error: 'rate limited' };
  if (!res.ok) return { error: `HTTP ${res.status}` };

  const data = await res.json();

  // CRITICAL: skip unclaimed brands. claimed: true means the trademark
  // holder has verified the profile.
  if (!data.claimed) return { error: 'unclaimed (skipped)' };

  // Extract colors. Brandfetch returns an array of {hex, type} entries.
  const colors = [];
  if (Array.isArray(data.colors)) {
    data.colors.forEach((c, i) => {
      if (!c || !c.hex) return;
      const role = i === 0 ? 'primary' : i === 1 ? 'secondary' : 'accent';
      const colorName = i === 0 ? 'Primary' : i === 1 ? 'Secondary' : 'Accent';
      colors.push({ name: colorName, hex: c.hex, role });
    });
  }

  if (colors.length === 0) return { error: 'no colors returned' };

  return { brand: { name, industry, colors } };
}

// ─── Main ───────────────────────────────────────────────────────────────────

async function main() {
  console.log('');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(' Brand Library Seeder');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(` Mode:        ${COMMIT ? 'COMMIT (writes to Firestore)' : 'DRY RUN (no writes)'}`);
  console.log(` Service key: ${path.relative(process.cwd(), KEY_PATH)}`);
  console.log(` Project:     ${serviceAccount.project_id}`);
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('');

  if (!COMMIT) {
    console.log('ℹ  Running in DRY RUN mode. Pass --commit to write to Firestore.');
    console.log('');
  }

  let totalSeeded = 0;
  let totalSkipped = 0;
  let totalFailed = 0;
  const flagged = [];

  // ─── Phase 1: manual brands ─────────────────────────────────────────────
  if (!SKIP_MANUAL) {
    console.log('── Phase 1: Manual brands (nex-gen-manual) ──');
    let raw;
    try {
      raw = require('./brands_to_seed.json');
    } catch (e) {
      console.log(`❌ Failed to load brands_to_seed.json: ${e.message}`);
      raw = [];
    }

    // Filter out _section divider entries (used for readability in the JSON)
    // and any malformed entries missing name/colors.
    const manualBrands = raw.filter(
      (b) => b && b.name && Array.isArray(b.colors) && b.colors.length > 0
    );

    const highConfidence = manualBrands.filter((b) => b.confidence === 'high');
    const verifyNeeded = manualBrands.filter((b) => b.confidence !== 'high');

    console.log(
      `   ${manualBrands.length} total, ` +
        `${highConfidence.length} high-confidence (eligible), ` +
        `${verifyNeeded.length} flagged for verification (skipped)`
    );

    if (verifyNeeded.length > 0) {
      console.log('');
      console.log('   ⚠  Brands flagged for verification — these will NOT be seeded:');
      verifyNeeded.forEach((b) => {
        flagged.push(b.name);
        console.log(`      - ${b.name} (${b.industry})`);
      });
      console.log('');
      console.log(
        '   Verify the hex codes against official brand guidelines, then'
      );
      console.log('   change "confidence": "verify" to "high" in brands_to_seed.json.');
      console.log('');
    }

    for (const brand of highConfidence) {
      try {
        const result = await seedBrand(brand, 'nex-gen-manual');
        const brandId = result.brandId || toBrandId(brand.name);
        if (result.status === 'seeded') {
          console.log(`   ✅ Seeded: ${brand.name} → ${brandId}`);
          totalSeeded++;
        } else if (result.status === 'dry-run') {
          console.log(`   📝 Would seed: ${brand.name} → ${brandId}`);
          totalSeeded++;
        } else if (result.status === 'skipped') {
          console.log(`   ⏭  Skipped: ${brand.name} (${result.reason})`);
          totalSkipped++;
        } else {
          console.log(`   ❌ Failed: ${brand.name} (${result.reason})`);
          totalFailed++;
        }
      } catch (e) {
        console.log(`   ❌ Failed: ${brand.name} — ${e.message}`);
        totalFailed++;
      }
    }
  }

  // ─── Phase 2: Brandfetch claimed-only ───────────────────────────────────
  if (!SKIP_BRANDFETCH) {
    console.log('');
    console.log('── Phase 2: Brandfetch claimed-only (brandfetch-claimed) ──');

    let brandfetchList = [];
    try {
      brandfetchList = require('./brandfetch_domains.json');
    } catch (e) {
      console.log(`   (no brandfetch_domains.json found — skipping Phase 2)`);
      brandfetchList = [];
    }

    // Don't re-fetch brands we already covered manually. Filter out
    // _section divider entries that are present in the JSON for readability.
    let manualNames = new Set();
    if (!SKIP_MANUAL) {
      try {
        const raw = require('./brands_to_seed.json');
        manualNames = new Set(
          raw.filter((b) => b && b.name).map((b) => b.name.toLowerCase())
        );
      } catch (_) {}
    }

    console.log(`   ${brandfetchList.length} domains to attempt`);
    console.log(`   (claimed: true filter is mandatory — unclaimed entries skipped)`);
    console.log('');

    for (const entry of brandfetchList) {
      if (!entry || !entry.name || !entry.domain) continue;
      if (manualNames.has(entry.name.toLowerCase())) {
        console.log(`   ⏭  Skipped: ${entry.name} (already in manual list)`);
        continue;
      }

      const fetched = await fetchBrandfetch(entry.name, entry.domain, entry.industry);
      if (fetched.error) {
        console.log(`   ⚠  ${entry.name}: ${fetched.error}`);
        totalFailed++;
        await sleep(500);
        continue;
      }

      try {
        const result = await seedBrand(fetched.brand, 'brandfetch-claimed');
        const brandId = result.brandId || toBrandId(entry.name);
        if (result.status === 'seeded') {
          console.log(`   ✅ Seeded: ${entry.name} → ${brandId}`);
          totalSeeded++;
        } else if (result.status === 'dry-run') {
          console.log(`   📝 Would seed: ${entry.name} → ${brandId}`);
          totalSeeded++;
        } else if (result.status === 'skipped') {
          console.log(`   ⏭  Skipped: ${entry.name} (${result.reason})`);
          totalSkipped++;
        } else {
          console.log(`   ❌ Failed: ${entry.name} (${result.reason})`);
          totalFailed++;
        }
      } catch (e) {
        console.log(`   ❌ Failed: ${entry.name} — ${e.message}`);
        totalFailed++;
      }

      // Polite rate limit: 2 requests per second.
      await sleep(500);
    }
  }

  // ─── Summary ────────────────────────────────────────────────────────────
  console.log('');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(' Done');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(` ${COMMIT ? 'Seeded' : 'Would seed'}:  ${totalSeeded}`);
  console.log(` Skipped:           ${totalSkipped}`);
  console.log(` Failed:            ${totalFailed}`);
  if (flagged.length > 0) {
    console.log(` Flagged (verify):  ${flagged.length}`);
  }
  if (!COMMIT) {
    console.log('');
    console.log(' This was a DRY RUN. Re-run with --commit to actually write.');
  }
  console.log('═══════════════════════════════════════════════════════════════');
  process.exit(0);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((err) => {
  console.error('');
  console.error('Fatal error:', err);
  process.exit(1);
});
