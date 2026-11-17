/**
 * Shared fixtures for the dealer-tools rules suites:
 *   dealerToolsRulesDiff.emulator.test.ts   (before/after allow matrix)
 *   dealerToolsRules.emulator.test.ts       (items 1-6, named allow/deny cases)
 *   dealerToolsStorage.emulator.test.ts     (item 7, storage.rules)
 *
 * Every identity here is synthetic. Staff uids follow mintStaffToken's
 * `staff_<mode>_<pin>` shape with a NON-numeric suffix, so no fixture can
 * collide with a real 4-digit PIN (only the `staff_` prefix is meaningful to
 * any rule). Dealer codes 01 and 02 are used because the rules compare codes
 * by value only; nothing here reads production data.
 */

import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { Timestamp, doc, setDoc } from "firebase/firestore";

export const D1 = "01";
export const D2 = "02";

/** A persona: null = unauthenticated; otherwise a uid plus custom claims. */
export type Persona = { uid: string; token?: Record<string, unknown> } | null;

export const PERSONAS: Record<string, Persona> = {
  // Not signed in at all.
  unauth: null,
  // A Firebase anonymous sign-in (the installer wizard's fallback session).
  anonSession: {
    uid: "anon_session_uid",
    token: { firebase: { sign_in_provider: "anonymous" } },
  },
  // A customer stamped with dealer_code 01 by the installer wizard (the
  // population R1/R2 are about), reading their OWN user doc and installation.
  custA: { uid: "cust_a_uid" },
  // A second customer of dealer 01.
  custB: { uid: "cust_b_uid" },
  // A self-signup customer: has a profile, no dealer_code.
  custSelf: { uid: "cust_self_uid" },
  // A customer who stamped installer_dealer_code 01 on their own doc. Nothing
  // in the app writes that field; the /users update rule does not guard it.
  custIdc: { uid: "cust_idc_uid" },
  // A user_role 'dealer' ACCOUNT of dealer 01 (isDealerStaffAccount). Zero of
  // these exist in production; included because it is the identity several of
  // the changed predicates name.
  dealerAcct01: { uid: "dealer_acct_01_uid" },
  // A user_role 'admin' account (corporate, isUserRoleAdmin / isMediaOrAdmin).
  corpAdminAcct: { uid: "corp_admin_acct_uid" },
  // A user_role 'media' account (isMediaOrAdmin).
  mediaAcct: { uid: "media_acct_uid" },
  // Staff PIN sessions (mintStaffToken claim shapes, staffAuth.ts:540-554).
  sales01: {
    uid: "staff_sales_FIXTURE01",
    token: { role: "salesperson", dealerCode: D1, source: "installer_doc" },
  },
  sales02: {
    uid: "staff_sales_FIXTURE02",
    token: { role: "salesperson", dealerCode: D2, source: "installer_doc" },
  },
  inst01: {
    uid: "staff_installer_FIXTURE01",
    token: { role: "installer", dealerCode: D1, source: "installer_doc" },
  },
  inst02: {
    uid: "staff_installer_FIXTURE02",
    token: { role: "installer", dealerCode: D2, source: "installer_doc" },
  },
  // An admin-role installers doc of dealer 01 mints role admin + dealerCode 01.
  admin01: {
    uid: "staff_admin_FIXTURE01",
    token: { role: "admin", dealerCode: D1, source: "installer_doc" },
  },
  // The master admin PIN mints role admin + dealerCode 55 (MASTER_DEALER_CODE).
  admin55: {
    uid: "staff_admin_FIXTURE55",
    token: { role: "admin", dealerCode: "55", source: "master" },
  },
  // Owner: role owner, NO dealerCode claim.
  owner: { uid: "staff_owner_FIXTURE", token: { role: "owner", source: "master" } },
};

export const PERSONA_KEYS = Object.keys(PERSONAS);

/** Rules-unit-testing context for a persona. */
export function ctxFor(env: RulesTestEnvironment, key: string) {
  const p = PERSONAS[key];
  if (p === undefined) throw new Error(`unknown persona ${key}`);
  if (p === null) return env.unauthenticatedContext();
  return env.authenticatedContext(p.uid, p.token ?? {});
}

/** A user profile with the fields UserModel.toJson always writes. */
function profile(uid: string, extra: Record<string, unknown>) {
  return {
    id: uid,
    owner_id: uid,
    email: `${uid}@example.com`,
    display_name: uid,
    user_role: "residential",
    ...extra,
  };
}

/**
 * EXACTLY the key set SalesJob.toJson emits (lib/features/sales/models/
 * sales_models.dart, toJson) for a fresh draft from prospect_info_screen.dart
 * _saveAndContinue — the write that creates a job (set(merge:true) on a new
 * id via SalesJobService.updateJob).
 */
export function draftJobPayload(id: string, dealerCode: string, salespersonUid: string) {
  const now = Timestamp.fromDate(new Date("2026-11-17T15:00:00Z"));
  return {
    id,
    jobNumber: "NXG-20261117-001",
    dealerCode,
    salespersonUid,
    prospect: {
      id,
      firstName: "Pat",
      lastName: "Example",
      email: "pat@example.com",
      phone: "",
      address: "1 Example St",
      city: "Exampleton",
      state: "MO",
      zipCode: "00000",
      referrerUid: "",
      referralCode: "",
      homePhotoUrls: [],
      salespersonNotes: "",
      createdAt: now,
    },
    zones: [],
    status: "draft",
    totalPriceUsd: 0,
    estimateSentAt: null,
    estimateSignedAt: null,
    customerSignatureUrl: null,
    day1Date: null,
    day2Date: null,
    createdAt: now,
    updatedAt: now,
    systemVoltage: "v24",
    linkedUserId: null,
    channelRuns: [],
    powerInjectionPoints: [],
    controllerMount: null,
    homePhotoPath: null,
    day1Notes: null,
    day2Notes: null,
    day1CompletedTaskIds: [],
    day2CompletedTaskIds: [],
    day1TechUid: null,
    day2TechUid: null,
    day1CompletedAt: null,
    day2CompletedAt: null,
    estimateBreakdown: null,
    installCompletePhotoUrls: [],
    actualMaterialUsage: null,
    depositCollected: false,
    depositCollectedAt: null,
    depositCollectedBy: null,
    depositAmount: null,
    finalPaymentCollected: false,
    finalPaymentCollectedAt: null,
    finalPaymentCollectedBy: null,
  };
}

/** Every document the matrices read or mutate, keyed by path. */
export function seedDocs(): Record<string, Record<string, unknown>> {
  const ts = Timestamp.fromDate(new Date("2026-11-17T15:00:00Z"));
  return {
    // ── users ──
    "users/cust_a_uid": profile("cust_a_uid", {
      dealer_code: D1,
      installation_id: "inst_a",
      installation_role: "primary",
    }),
    "users/cust_b_uid": profile("cust_b_uid", {
      dealer_code: D1,
      installation_id: "inst_b",
      installation_role: "primary",
    }),
    "users/cust_self_uid": profile("cust_self_uid", {}),
    "users/cust_idc_uid": profile("cust_idc_uid", { installer_dealer_code: D1 }),
    "users/dealer_acct_01_uid": profile("dealer_acct_01_uid", {
      dealer_code: D1,
      user_role: "dealer",
    }),
    "users/corp_admin_acct_uid": profile("corp_admin_acct_uid", { user_role: "admin" }),
    "users/media_acct_uid": profile("media_acct_uid", { user_role: "media" }),
    "users/cust_a_uid/controllers/c1": { name: "Front", ip: "192.0.2.10" },
    "users/cust_a_uid/schedules/s1": { label: "Evening" },
    // ── installations ──
    "installations/inst_a": {
      primary_user_id: "cust_a_uid",
      dealer_code: D1,
      installer_code: "11",
      installed_at: ts,
    },
    // ── installers ── (fullPin is a non-numeric fixture value on purpose)
    "installers/i01": {
      installerCode: "11",
      dealerCode: D1,
      fullPin: "FIXTURE",
      name: "Fixture Installer 01",
      isActive: true,
      role: "installer",
    },
    "installers/i02": {
      installerCode: "21",
      dealerCode: D2,
      fullPin: "FIXTURE2",
      name: "Fixture Installer 02",
      isActive: true,
      role: "installer",
    },
    // ── dealers keyed by code ──
    "dealers/01": { dealerCode: D1, name: "Dealer One", isActive: true },
    "dealers/02": { dealerCode: D2, name: "Dealer Two", isActive: true },
    "dealers/01/pricing/current": { pricePerLinearFoot: 18, dealerCostPerLinearFoot: 9 },
    "dealers/02/pricing/current": { pricePerLinearFoot: 18, dealerCostPerLinearFoot: 9 },
    "dealers/01/config/messaging": { dealerCode: D1, senderName: "Dealer One" },
    "dealers/01/shipping_address/primary": { line1: "1 Dock Rd" },
    "dealers/01/inventoryLedger/e1": { type: "checkout", quantity: 1 },
    "dealers/01/inventory/i1": { quantityOnHand: 10 },
    "dealers/01/materialCatalog/m1": { name: "Rail", isActive: true, unitCostCents: 0 },
    // ── sales_jobs ──
    "sales_jobs/job01": draftJobPayload("job01", D1, "staff_sales_FIXTURE01"),
    "sales_jobs/job02": draftJobPayload("job02", D2, "staff_sales_FIXTURE02"),
    "sales_jobs/job01/materialList/current": { jobNumber: "NXG-1", dealerCode: D1, lines: [] },
    "sales_jobs/job01/materialLedger/l1": { type: "checkout", quantity: 1 },
    // ── referral_payouts ── (cust_b is the referrer of pay01)
    "referral_payouts/pay01": {
      referrerUid: "cust_b_uid",
      dealerCode: D1,
      status: "pending",
      createdAt: ts,
    },
    // ── dealer_orders ──
    "dealer_orders/ord01": { order_id: "ord01", dealer_code: D1, status: "draft", line_items: [] },
    "dealer_orders/ord02": { order_id: "ord02", dealer_code: D2, status: "draft", line_items: [] },
    // ── app_config / catalog ──
    "app_config/pricing_defaults": { pricePerLinearFoot: 18, dealerCostPerLinearFoot: 9 },
    "app_config/master_sales_pin": { pin_hash: "fixture-not-a-hash", role: "salesperson" },
    "product_catalog/sku1": { sku: "sku1", name: "Fixture SKU", unit_price: 1, is_active: true },
  };
}

/** Clear and reseed a project with the fixture set (rules disabled). */
export async function reseed(env: RulesTestEnvironment): Promise<void> {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const docs = seedDocs();
    for (const [path, data] of Object.entries(docs)) {
      await setDoc(doc(db, path), data);
    }
  });
}
